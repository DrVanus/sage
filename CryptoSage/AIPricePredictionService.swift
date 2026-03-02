//
//  AIPricePredictionService.swift
//  CryptoSage
//
//  AI-powered price prediction service that combines technical indicators,
//  market sentiment, and AI analysis to generate price forecasts.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Prediction Models

/// Confidence level for a price prediction
public enum PredictionConfidence: String, Codable, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
    
    public var score: Double {
        switch self {
        case .low: return 0.33
        case .medium: return 0.66
        case .high: return 1.0
        }
    }
    
    public var color: Color {
        switch self {
        case .low: return .red
        case .medium:
            // Adaptive: warm amber in light mode for readability (pure yellow is washed out)
            return Color(UIColor { tc in
                tc.userInterfaceStyle == .dark
                    ? UIColor.systemYellow
                    : UIColor(red: 0.72, green: 0.55, blue: 0.10, alpha: 1.0)
            })
        case .high: return .green
        }
    }
    
    public static func from(score: Int) -> PredictionConfidence {
        // Updated thresholds for timeframe-aware confidence scoring
        // - High: Strong signal agreement + favorable timeframe
        // - Medium: Moderate signals or longer timeframes
        // - Low: Mixed signals or very long timeframes
        if score >= 70 { return .high }
        if score >= 45 { return .medium }
        return .low
    }
}

/// Direction of predicted price movement
public enum PredictionDirection: String, Codable {
    case bullish = "bullish"
    case bearish = "bearish"
    case neutral = "neutral"
    
    public var displayName: String {
        switch self {
        case .bullish: return "Bullish"
        case .bearish: return "Bearish"
        case .neutral: return "Neutral"
        }
    }
    
    public var icon: String {
        switch self {
        case .bullish: return "arrow.up.right"
        case .bearish: return "arrow.down.right"
        case .neutral: return "arrow.right"
        }
    }
    
    public var color: Color {
        switch self {
        case .bullish: return .green
        case .bearish: return .red
        case .neutral:
            // Adaptive: warm amber in light mode (pure yellow is nearly invisible on white)
            return Color(UIColor { tc in
                tc.userInterfaceStyle == .dark
                    ? UIColor.systemYellow
                    : UIColor(red: 0.72, green: 0.55, blue: 0.10, alpha: 1.0)
            })
        }
    }
}

/// Timeframe for predictions
public enum PredictionTimeframe: String, Codable, CaseIterable {
    case hour = "1h"
    case fourHours = "4h"
    case twelveHours = "12h"
    case day = "1d"
    case week = "7d"
    case month = "30d"
    
    public var displayName: String {
        switch self {
        case .hour: return "1H"
        case .fourHours: return "4H"
        case .twelveHours: return "12H"
        case .day: return "24H"
        case .week: return "7D"
        case .month: return "30D"
        }
    }
    
    public var fullName: String {
        switch self {
        case .hour: return "1 Hour"
        case .fourHours: return "4 Hours"
        case .twelveHours: return "12 Hours"
        case .day: return "24 Hours"
        case .week: return "7 Days"
        case .month: return "30 Days"
        }
    }
    
    /// Short-term timeframes need different analysis focus
    public var isShortTerm: Bool {
        switch self {
        case .hour, .fourHours: return true
        default: return false
        }
    }
    
    /// Expected volatility multiplier for price range calculations
    public var volatilityMultiplier: Double {
        switch self {
        case .hour: return 0.3
        case .fourHours: return 0.5
        case .twelveHours: return 0.75
        case .day: return 1.0
        case .week: return 2.0
        case .month: return 3.5
        }
    }
    
    /// Duration in seconds for calculating target date
    public var durationSeconds: TimeInterval {
        switch self {
        case .hour: return 3600
        case .fourHours: return 4 * 3600
        case .twelveHours: return 12 * 3600
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        case .month: return 30 * 24 * 3600
        }
    }
    
    /// Firebase-compatible timeframe string
    /// Maps to the format expected by Firebase cloud functions
    public var firebaseTimeframe: String {
        switch self {
        case .hour: return "1h"
        case .fourHours: return "4h"
        case .twelveHours: return "12h"
        case .day: return "24h"
        case .week: return "7d"
        case .month: return "30d"
        }
    }
}

/// A factor driving the prediction
public struct PredictionDriver: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let value: String
    public let signal: String // "bullish", "bearish", "neutral"
    public let weight: Double // 0-1 importance
    
    public init(name: String, value: String, signal: String, weight: Double = 0.5) {
        self.id = UUID().uuidString
        self.name = name
        self.value = value
        self.signal = signal
        self.weight = weight
    }
    
    public var signalColor: Color {
        switch signal.lowercased() {
        case "bullish", "buy": return .green
        case "bearish", "sell": return .red
        default: return .yellow
        }
    }
}

/// Complete price prediction result
public struct AIPricePrediction: Codable, Identifiable {
    public let id: String
    public let coinSymbol: String
    public let coinName: String
    public let currentPrice: Double
    public let predictedPriceChange: Double // Percentage change
    public let predictedPriceLow: Double
    public let predictedPriceHigh: Double
    public let confidenceScore: Int // 0-100
    public let confidence: PredictionConfidence
    public let direction: PredictionDirection
    public let timeframe: PredictionTimeframe
    public let drivers: [PredictionDriver]
    public let analysis: String
    public let generatedAt: Date
    
    // MARK: - Probability Distribution Fields (CoinStats-style)
    
    /// Probability of price moving +2% or more (0-100)
    public let probabilityUp2Pct: Double?
    /// Probability of price moving +5% or more (0-100)
    public let probabilityUp5Pct: Double?
    /// Probability of price moving +10% or more (0-100)
    public let probabilityUp10Pct: Double?
    /// Probability of price moving -2% or more (0-100)
    public let probabilityDown2Pct: Double?
    /// Probability of price moving -5% or more (0-100)
    public let probabilityDown5Pct: Double?
    /// Probability of price moving -10% or more (0-100)
    public let probabilityDown10Pct: Double?
    /// Directional score from -100 (very bearish) to +100 (very bullish)
    public let directionalScore: Int?
    
    public var predictedPrice: Double {
        currentPrice * (1 + predictedPriceChange / 100)
    }
    
    /// Returns the predicted price adjusted for a given live price
    /// Maintains the same % change from the live price as originally predicted
    /// Use this when displaying predictions after the market has moved from the original prediction price
    public func adjustedPredictedPrice(forLivePrice livePrice: Double) -> Double {
        return livePrice * (1 + predictedPriceChange / 100)
    }
    
    /// Returns the predicted LOW price adjusted for a given live price
    /// Extracts the percentage range from the original prediction and applies it to the live price
    /// This ensures the price range stays consistent when the base price changes
    public func adjustedPredictedPriceLow(forLivePrice livePrice: Double) -> Double {
        guard currentPrice > 0, predictedPriceLow > 0 else {
            // Fallback: use predictedPriceChange minus 3% buffer
            let lowPct = predictedPriceChange - 3.0
            return livePrice * (1 + lowPct / 100)
        }
        let lowPctChange = ((predictedPriceLow / currentPrice) - 1) * 100
        return livePrice * (1 + lowPctChange / 100)
    }
    
    /// Returns the predicted HIGH price adjusted for a given live price
    /// Extracts the percentage range from the original prediction and applies it to the live price
    /// This ensures the price range stays consistent when the base price changes
    public func adjustedPredictedPriceHigh(forLivePrice livePrice: Double) -> Double {
        guard currentPrice > 0, predictedPriceHigh > 0 else {
            // Fallback: use predictedPriceChange plus 3% buffer
            let highPct = predictedPriceChange + 3.0
            return livePrice * (1 + highPct / 100)
        }
        let highPctChange = ((predictedPriceHigh / currentPrice) - 1) * 100
        return livePrice * (1 + highPctChange / 100)
    }
    
    public var formattedPriceChange: String {
        let sign = predictedPriceChange >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", predictedPriceChange))%"
    }
    
    // PERFORMANCE FIX: Cached currency formatters for price range text
    private static let _rangeFmt2: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode; nf.maximumFractionDigits = 2; return nf
    }()
    private static let _rangeFmt4: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode; nf.maximumFractionDigits = 4; return nf
    }()
    public var priceRangeText: String {
        // FIX: Static formatters capture currencyCode once at init and never update.
        // Refresh the currency code each time so the formatter reflects the current setting.
        let currentCode = CurrencyManager.currencyCode
        Self._rangeFmt2.currencyCode = currentCode
        Self._rangeFmt4.currencyCode = currentCode
        let formatter = predictedPriceLow < 1 ? Self._rangeFmt4 : Self._rangeFmt2
        let low = formatter.string(from: NSNumber(value: predictedPriceLow)) ?? "$\(predictedPriceLow)"
        let high = formatter.string(from: NSNumber(value: predictedPriceHigh)) ?? "$\(predictedPriceHigh)"
        return "\(low) – \(high)"
    }
    
    /// Target date when this prediction is for
    public var targetDate: Date {
        generatedAt.addingTimeInterval(timeframe.durationSeconds)
    }
    
    /// Time remaining until target date
    public var timeRemaining: TimeInterval {
        targetDate.timeIntervalSince(Date())
    }
    
    /// Whether the prediction has expired
    public var isExpired: Bool {
        timeRemaining <= 0
    }
    
    /// How much time has elapsed since the prediction was generated
    public var elapsedTime: TimeInterval {
        Date().timeIntervalSince(generatedAt)
    }
    
    /// Progress through the prediction timeframe (0.0 to 1.0+)
    public var timeframeProgress: Double {
        elapsedTime / timeframe.durationSeconds
    }
    
    /// Whether the prediction is getting stale (>50% through timeframe)
    public var isStale: Bool {
        timeframeProgress > 0.5
    }
    
    /// Whether the prediction urgently needs refresh (>75% through timeframe)
    public var needsRefresh: Bool {
        timeframeProgress > 0.75
    }
    
    /// Human-readable "generated X ago" string
    public var generatedAgoText: String {
        let elapsed = elapsedTime
        
        if elapsed < 60 {
            return "Just now"
        } else if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return "\(minutes)m ago"
        } else if elapsed < 86400 {
            let hours = Int(elapsed / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(elapsed / 86400)
            return "\(days)d ago"
        }
    }
    
    /// Suggested refresh text based on staleness
    public var refreshSuggestionText: String? {
        if needsRefresh {
            return "Prediction is getting old - consider refreshing"
        } else if isStale {
            return "Market may have changed - refresh available"
        }
        return nil
    }
    
    /// Formatted target date string
    public var formattedTargetDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: targetDate)
    }
    
    /// Short formatted target date
    public var shortTargetDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: targetDate)
    }
    
    public static let disclaimer = "AI predictions are not financial advice. Cryptocurrency markets are highly volatile. Always do your own research before making investment decisions."
    
    // MARK: - Probability Helpers
    
    /// Whether probability data is available
    public var hasProbabilityData: Bool {
        probabilityUp2Pct != nil || directionalScore != nil
    }
    
    /// Formatted directional score string with sign
    public var formattedDirectionalScore: String? {
        guard let score = directionalScore else { return nil }
        let sign = score >= 0 ? "+" : ""
        return "\(sign)\(score)"
    }
    
    /// Directional score interpretation
    public var directionalScoreLabel: String? {
        guard let score = directionalScore else { return nil }
        switch score {
        case 70...100: return "Strongly Bullish"
        case 30..<70: return "Bullish"
        case 10..<30: return "Slightly Bullish"
        case -10..<10: return "Neutral"
        case -30..<(-10): return "Slightly Bearish"
        case -70..<(-30): return "Bearish"
        default: return "Strongly Bearish"
        }
    }
    
    /// Color for directional score
    public var directionalScoreColor: Color {
        guard let score = directionalScore else { return .gray }
        if score > 30 { return .green }
        if score > 0 { return .green.opacity(0.7) }
        if score > -30 { return .red.opacity(0.7) }
        return .red
    }
    
    /// Get probability for a specific threshold
    public func probability(for threshold: ProbabilityThreshold) -> Double? {
        switch threshold {
        case .up2: return probabilityUp2Pct
        case .up5: return probabilityUp5Pct
        case .up10: return probabilityUp10Pct
        case .down2: return probabilityDown2Pct
        case .down5: return probabilityDown5Pct
        case .down10: return probabilityDown10Pct
        }
    }
}

/// Probability threshold options for display
public enum ProbabilityThreshold: String, CaseIterable {
    case up2 = "+2%"
    case up5 = "+5%"
    case up10 = "+10%"
    case down2 = "-2%"
    case down5 = "-5%"
    case down10 = "-10%"
    
    public var isPositive: Bool {
        switch self {
        case .up2, .up5, .up10: return true
        case .down2, .down5, .down10: return false
        }
    }
    
    public var color: Color {
        isPositive ? .green : .red
    }
}

// MARK: - AIPricePrediction Helpers

extension AIPricePrediction {
    /// Creates a new prediction with fallback drivers if the current drivers array is empty
    /// This ensures the Key Drivers section always has something to display
    func withFallbackDrivers() -> AIPricePrediction {
        guard drivers.isEmpty else { return self }
        
        let signalValue = direction == .bullish ? "bullish" : (direction == .bearish ? "bearish" : "neutral")
        let fallbackDrivers: [PredictionDriver] = [
            PredictionDriver(
                name: "AI Analysis",
                value: "\(direction.displayName) outlook",
                signal: signalValue,
                weight: 0.5
            ),
            PredictionDriver(
                name: "Confidence",
                value: "\(confidenceScore)% (\(confidence.rawValue))",
                signal: signalValue,
                weight: 0.4
            ),
            PredictionDriver(
                name: "Price Target",
                value: formattedPriceChange,
                signal: signalValue,
                weight: 0.3
            )
        ]
        
        return AIPricePrediction(
            id: id,
            coinSymbol: coinSymbol,
            coinName: coinName,
            currentPrice: currentPrice,
            predictedPriceChange: predictedPriceChange,
            predictedPriceLow: predictedPriceLow,
            predictedPriceHigh: predictedPriceHigh,
            confidenceScore: confidenceScore,
            confidence: confidence,
            direction: direction,
            timeframe: timeframe,
            drivers: fallbackDrivers,
            analysis: analysis,
            generatedAt: generatedAt,
            probabilityUp2Pct: probabilityUp2Pct,
            probabilityUp5Pct: probabilityUp5Pct,
            probabilityUp10Pct: probabilityUp10Pct,
            probabilityDown2Pct: probabilityDown2Pct,
            probabilityDown5Pct: probabilityDown5Pct,
            probabilityDown10Pct: probabilityDown10Pct,
            directionalScore: directionalScore
        )
    }
}

// MARK: - Prediction Service Error

public enum PredictionServiceError: LocalizedError, Equatable {
    case noAPIKey
    case insufficientData
    case aiServiceFailed(String)
    case parseError
    case rateLimited
    case timeout
    case coinNotAllowedForFreeTier(String)
    
    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "AI predictions temporarily unavailable"
        case .insufficientData:
            return "Insufficient market data for prediction"
        case .aiServiceFailed(let message):
            // Pass through the underlying message for proper error categorization
            return message
        case .parseError:
            return "Failed to parse AI response. Please try again."
        case .rateLimited:
            return "Rate limited. Please try again in a moment."
        case .timeout:
            return "Request timed out. Please try again."
        case .coinNotAllowedForFreeTier(let symbol):
            return "AI predictions for \(symbol) require Pro. Upgrade to unlock all coins, or try BTC, ETH, SOL, XRP, or BNB."
        }
    }
}

// MARK: - AI Price Prediction Service

@MainActor
public final class AIPricePredictionService: ObservableObject {
    public static let shared = AIPricePredictionService()
    
    // MARK: - Published Properties
    
    @Published public var isLoading: Bool = false
    @Published public var lastError: String? = nil
    @Published public var cachedPredictions: [String: AIPricePrediction] = [:] // keyed by symbol+timeframe
    
    // MARK: - Cache Configuration
    
    // Cache duration is now dynamic based on prediction timeframe
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheStorageKey = "AIPrediction.CachedPredictions"
    private let cacheTimestampsKey = "AIPrediction.CacheTimestamps"
    
    // MARK: - Cooldown (prevents rapid refresh even with forceRefresh)
    private var lastRequestTimestamps: [String: Date] = [:]
    
    /// Base cooldown durations per timeframe before tier multiplier is applied
    private func baseCooldownSeconds(for timeframe: PredictionTimeframe) -> TimeInterval {
        switch timeframe {
        case .hour: return 15 * 60          // 15 minutes for 1H
        case .fourHours: return 30 * 60     // 30 minutes for 4H
        case .twelveHours: return 45 * 60   // 45 minutes for 12H
        case .day: return 60 * 60           // 1 hour for 24H
        case .week: return 2 * 60 * 60      // 2 hours for 7D
        case .month: return 4 * 60 * 60     // 4 hours for 30D
        }
    }
    
    /// Tier-aware cooldown multiplier: Premium gets 50%, Pro gets 75%, Free gets 100%
    private func tierCooldownMultiplier() -> Double {
        switch SubscriptionManager.shared.effectiveTier {
        case .premium: return 0.50  // Premium: half the cooldown
        case .pro: return 0.75      // Pro: 75% cooldown
        case .free: return 1.0      // Free: full cooldown
        }
    }
    
    /// Minimum time between predictions for the same coin/timeframe (prevents rapid refresh)
    /// Tier-aware: Premium users get shorter cooldowns than Pro, who get shorter than Free.
    private func minimumCooldownSeconds(for timeframe: PredictionTimeframe) -> TimeInterval {
        return baseCooldownSeconds(for: timeframe) * tierCooldownMultiplier()
    }
    
    /// Public: Check how many seconds remain in the cooldown for a given coin/timeframe.
    /// Returns 0 if cooldown has elapsed (refresh is available).
    public func cooldownRemaining(for symbol: String, timeframe: PredictionTimeframe) -> TimeInterval {
        let key = cacheKey(symbol: symbol, timeframe: timeframe)
        let cooldown = minimumCooldownSeconds(for: timeframe)
        guard let lastRequest = lastRequestTimestamps[key] else { return 0 }
        let elapsed = Date().timeIntervalSince(lastRequest)
        return max(0, cooldown - elapsed)
    }
    
    /// Get appropriate cache duration based on prediction timeframe
    /// Extended cache durations for significant cost savings - predictions should be stable
    private func cacheValiditySeconds(for timeframe: PredictionTimeframe) -> TimeInterval {
        switch timeframe {
        case .hour:
            return 30 * 60        // 30 minutes for 1H predictions (extended from 15)
        case .fourHours:
            return 90 * 60        // 90 minutes for 4H predictions (extended from 45)
        case .twelveHours:
            return 3 * 60 * 60    // 3 hours for 12H predictions
        case .day:
            return 6 * 60 * 60    // 6 hours for 24H predictions (extended from 3)
        case .week:
            return 18 * 60 * 60   // 18 hours for 7D predictions (extended from 12)
        case .month:
            return 36 * 60 * 60   // 36 hours for 30D predictions (extended from 24)
        }
    }
    
    // MARK: - Daily Limit Tracking (All tiers)
    
    /// Daily prediction limits per subscription tier (uses centralized SubscriptionManager values)
    private func dailyLimit(for tier: SubscriptionTierType) -> Int {
        tier.predictionsPerDay
    }
    
    @Published public private(set) var predictionsUsedToday: Int = 0
    private var lastUsageResetDate: Date = Date()
    private let usageKey = "AIPrediction.UsageToday"
    private let usageResetKey = "AIPrediction.LastUsageResetDate"
    
    // MARK: - Initialization
    
    private init() {
        loadUsageState()
        loadCachedPredictions()
    }
    
    // MARK: - Cache Persistence
    
    /// Load cached predictions from UserDefaults on app launch.
    /// BUG FIX: Timestamps are loaded FIRST so cache validity can be checked properly.
    /// Uses cache validity window (not prediction expiry) to decide what to keep, so
    /// predictions survive app restarts within their cache window even after the timeframe elapses.
    private func loadCachedPredictions() {
        // Load timestamps FIRST — needed to check cache validity when filtering predictions
        if let data = UserDefaults.standard.data(forKey: cacheTimestampsKey) {
            do {
                cacheTimestamps = try JSONDecoder().decode([String: Date].self, from: data)
            } catch {
                #if DEBUG
                print("[AIPrediction] Failed to decode cache timestamps: \(error)")
                #endif
                cacheTimestamps = [:]
            }
        }
        
        // Load predictions — keep any that are still within cache validity OR not yet expired
        if let data = UserDefaults.standard.data(forKey: cacheStorageKey) {
            do {
                let decoded = try JSONDecoder().decode([String: AIPricePrediction].self, from: data)
                cachedPredictions = decoded
                    .filter { key, prediction in
                        // Keep if within cache validity window (primary check)
                        if let timestamp = cacheTimestamps[key] {
                            let maxAge = cacheValiditySeconds(for: prediction.timeframe)
                            if Date().timeIntervalSince(timestamp) < maxAge {
                                return true
                            }
                        }
                        // Also keep if the prediction itself hasn't expired yet (fallback)
                        return !prediction.isExpired
                    }
                    .mapValues { prediction in
                        // Ensure predictions have drivers - add fallback if empty
                        if prediction.drivers.isEmpty {
                            return prediction.withFallbackDrivers()
                        }
                        return prediction
                    }
                #if DEBUG
                print("[AIPrediction] Loaded \(cachedPredictions.count) cached predictions from storage (of \(decoded.count) total)")
                #endif
            } catch {
                #if DEBUG
                print("[AIPrediction] Failed to decode cached predictions: \(error)")
                #endif
                cachedPredictions = [:]
            }
        }
    }
    
    /// Save cached predictions to UserDefaults for persistence across app launches
    private func saveCachedPredictions() {
        do {
            // Only save non-expired predictions
            let validPredictions = cachedPredictions.filter { !$0.value.isExpired }
            let predictionsData = try JSONEncoder().encode(validPredictions)
            UserDefaults.standard.set(predictionsData, forKey: cacheStorageKey)
            
            let timestampsData = try JSONEncoder().encode(cacheTimestamps)
            UserDefaults.standard.set(timestampsData, forKey: cacheTimestampsKey)
        } catch {
            #if DEBUG
            print("[AIPrediction] Failed to save cached predictions: \(error)")
            #endif
        }
    }
    
    // MARK: - Usage Tracking
    
    private func loadUsageState() {
        predictionsUsedToday = UserDefaults.standard.integer(forKey: usageKey)
        if let date = UserDefaults.standard.object(forKey: usageResetKey) as? Date {
            lastUsageResetDate = date
        }
        checkDailyReset()
    }
    
    private func saveUsageState() {
        UserDefaults.standard.set(predictionsUsedToday, forKey: usageKey)
        UserDefaults.standard.set(lastUsageResetDate, forKey: usageResetKey)
    }
    
    private func checkDailyReset() {
        if !Calendar.current.isDateInToday(lastUsageResetDate) {
            predictionsUsedToday = 0
            lastUsageResetDate = Date()
            saveUsageState()
        }
    }
    
    /// Current user's daily prediction limit based on subscription tier
    public var currentDailyLimit: Int {
        dailyLimit(for: SubscriptionManager.shared.effectiveTier)
    }
    
    public var canGeneratePrediction: Bool {
        // Developer mode bypasses all limits
        if SubscriptionManager.shared.isDeveloperMode { return true }
        checkDailyReset()
        return predictionsUsedToday < currentDailyLimit
    }
    
    public var remainingPredictions: Int {
        checkDailyReset()
        return max(0, currentDailyLimit - predictionsUsedToday)
    }
    
    /// Legacy property for backwards compatibility
    public var remainingFreePredictions: Int {
        remainingPredictions
    }
    
    private func recordUsage() {
        // Don't count usage in developer mode (allows unlimited testing)
        if SubscriptionManager.shared.isDeveloperMode { return }
        checkDailyReset()
        predictionsUsedToday += 1
        saveUsageState()
    }
    
    // MARK: - Cache Management
    
    private func cacheKey(symbol: String, timeframe: PredictionTimeframe) -> String {
        return "\(symbol.uppercased())_\(timeframe.rawValue)"
    }
    
    private func isCacheValid(for key: String, timeframe: PredictionTimeframe) -> Bool {
        guard let timestamp = cacheTimestamps[key] else { return false }
        let maxAge = cacheValiditySeconds(for: timeframe)
        return Date().timeIntervalSince(timestamp) < maxAge
    }
    
    public func clearCache() {
        cachedPredictions.removeAll()
        cacheTimestamps.removeAll()
        // Also clear persisted storage
        UserDefaults.standard.removeObject(forKey: cacheStorageKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampsKey)
    }
    
    // MARK: - Generate Prediction
    
    /// Timeout for prediction generation (30 seconds)
    private let predictionTimeoutSeconds: TimeInterval = 30
    
    /// Generate an AI price prediction for a coin
    /// Uses Firebase shared cache when available - predictions for the same coin/timeframe are shared across users.
    public func generatePrediction(
        for symbol: String,
        coinName: String? = nil,
        timeframe: PredictionTimeframe = .week,
        forceRefresh: Bool = false
    ) async throws -> AIPricePrediction {
        let key = cacheKey(symbol: symbol, timeframe: timeframe)
        #if DEBUG
        print("[AIPrediction] Starting prediction for \(symbol.uppercased()) (\(timeframe.displayName)), forceRefresh=\(forceRefresh)")
        #endif
        
        // When force refreshing, invalidate the existing cache entry to ensure fresh data
        if forceRefresh {
            #if DEBUG
            print("[AIPrediction] Force refresh - invalidating cache for \(key)")
            #endif
            cachedPredictions.removeValue(forKey: key)
            cacheTimestamps.removeValue(forKey: key)
        }
        
        // Check local cache first - cache duration depends on prediction timeframe
        if !forceRefresh, let cached = cachedPredictions[key], isCacheValid(for: key, timeframe: timeframe) {
            // Invalidate "fresh enough by time" cache when market has moved materially.
            // This prevents stale targets after sharp moves while still preserving cost savings.
            if cached.currentPrice > 0,
               let livePrice = await MainActor.run(body: { MarketViewModel.shared.bestPrice(forSymbol: symbol) }),
               livePrice.isFinite, livePrice > 0 {
                let drift = abs(livePrice - cached.currentPrice) / cached.currentPrice
                if drift >= 0.05 {
                    #if DEBUG
                    print("[AIPrediction] Cache invalidated for \(key) due to \(Int(drift * 100))% live-price drift")
                    #endif
                    cachedPredictions.removeValue(forKey: key)
                    cacheTimestamps.removeValue(forKey: key)
                } else {
                    let cacheMinutes = Int(cacheValiditySeconds(for: timeframe) / 60)
                    #if DEBUG
                    print("[AIPrediction] Returning cached prediction for \(key) (cache valid for \(cacheMinutes) min)")
                    #endif
                    // Track cache hit (cost savings) - report DeepSeek as the model (Firebase uses DeepSeek for predictions)
                    AnalyticsService.shared.trackAIFeatureUsage(
                        feature: .prediction,
                        model: "deepseek-chat",
                        maxTokens: 512,
                        tier: SubscriptionManager.shared.effectiveTier,
                        cached: true
                    )
                    // Ensure drivers are populated (for old cached predictions that may have empty drivers)
                    let prepared = cached.drivers.isEmpty ? cached.withFallbackDrivers() : cached
                    // Backfill accuracy tracking for cache hits that were generated before tracking was wired.
                    PredictionAccuracyService.shared.storePrediction(prepared, modelProvider: "deepseek-chat")
                    return prepared
                }
            } else {
                let cacheMinutes = Int(cacheValiditySeconds(for: timeframe) / 60)
                #if DEBUG
                print("[AIPrediction] Returning cached prediction for \(key) (cache valid for \(cacheMinutes) min)")
                #endif
                // Track cache hit (cost savings) - report DeepSeek as the model (Firebase uses DeepSeek for predictions)
                AnalyticsService.shared.trackAIFeatureUsage(
                    feature: .prediction,
                    model: "deepseek-chat",
                    maxTokens: 512,
                    tier: SubscriptionManager.shared.effectiveTier,
                    cached: true
                )
                // Ensure drivers are populated (for old cached predictions that may have empty drivers)
                let prepared = cached.drivers.isEmpty ? cached.withFallbackDrivers() : cached
                // Backfill accuracy tracking for cache hits that were generated before tracking was wired.
                PredictionAccuracyService.shared.storePrediction(prepared, modelProvider: "deepseek-chat")
                return prepared
            }
        }
        
        // Check coin restriction for free tier users
        // Developer mode bypasses coin restrictions for testing
        if !SubscriptionManager.shared.isDeveloperMode {
            guard SubscriptionManager.shared.canAccessAIForCoin(symbol) else {
                #if DEBUG
                print("[AIPrediction] ❌ Coin \(symbol) not allowed for free tier")
                #endif
                throw PredictionServiceError.coinNotAllowedForFreeTier(symbol.uppercased())
            }
        }
        
        // FIREBASE: Try shared cache first - all users get the same prediction for the same coin/timeframe
        // This significantly reduces API costs and ensures consistency
        // All timeframes including 12H are now supported by Firebase via DeepSeek
        
        if FirebaseService.shared.useFirebaseForAI {
            do {
                // Reduced timeout to 8 seconds - fail fast and use fallback
                // This prevents the UI from appearing stuck
                let firebaseTimeoutSeconds: TimeInterval = 8
                
                #if DEBUG
                print("[AIPrediction] Attempting Firebase prediction (timeout: \(Int(firebaseTimeoutSeconds))s)...")
                #endif
                
                // Use Task.withTimeout pattern for cleaner cancellation
                let prediction = try await withThrowingTaskGroup(of: AIPricePrediction.self) { group in
                    // Add the actual Firebase fetch task
                    group.addTask { @MainActor in
                        return try await self.fetchPredictionViaFirebase(
                            symbol: symbol,
                            coinName: coinName,
                            timeframe: timeframe
                        )
                    }
                    
                    // Add a timeout task that throws after the timeout
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(firebaseTimeoutSeconds * 1_000_000_000))
                        throw PredictionServiceError.timeout
                    }
                    
                    // Return the first successful result or throw the first error
                    let result = try await group.next()!
                    group.cancelAll() // Cancel remaining tasks
                    return result
                }
                
                // Cache locally for faster access
                cachedPredictions[key] = prediction
                cacheTimestamps[key] = Date()
                lastRequestTimestamps[key] = Date()
                saveCachedPredictions()
                
                // Store for accuracy tracking (local) — Firebase predictions use DeepSeek
                PredictionAccuracyService.shared.storePrediction(prediction, modelProvider: "deepseek-chat")
                
                // Record to Firebase for global accuracy tracking (fire-and-forget)
                enqueueGlobalOutcomeRecord(for: prediction)
                
                #if DEBUG
                print("[AIPrediction] ✅ Prediction loaded from Firebase")
                #endif
                return prediction
            } catch PredictionServiceError.timeout {
                #if DEBUG
                print("[AIPrediction] Firebase timed out after 8s, using technical analysis fallback")
                #endif
                // Fall through to technical fallback (skip direct API to avoid more delays)
            } catch {
                #if DEBUG
                print("[AIPrediction] Firebase prediction failed: \(error.localizedDescription), using fallback")
                #endif
                // Fall through to fallback
            }
            
            // If Firebase failed, immediately use technical fallback for fast response
            // Don't wait for direct OpenAI - that would add more delay
            #if DEBUG
            print("[AIPrediction] Generating instant technical analysis prediction...")
            #endif
            let fallbackPrediction = await generateTechnicalFallbackPrediction(
                symbol: symbol,
                coinName: coinName,
                timeframe: timeframe
            )
            cachedPredictions[key] = fallbackPrediction
            cacheTimestamps[key] = Date()
            lastRequestTimestamps[key] = Date()
            saveCachedPredictions()
            // Track technical fallback predictions so accuracy card is never empty when predictions exist.
            PredictionAccuracyService.shared.storePrediction(fallbackPrediction, modelProvider: "technical-fallback")
            enqueueGlobalOutcomeRecord(for: fallbackPrediction)
            return fallbackPrediction
        }
        
        // FALLBACK: Direct OpenAI call (when Firebase unavailable)
        // Cooldown check: prevent rapid requests to protect API costs
        // When forceRefresh is true (user explicitly tapped Refresh), bypass cooldown
        // so the prediction actually updates instead of silently returning stale data.
        if !forceRefresh && !SubscriptionManager.shared.isDeveloperMode {
            let cooldown = minimumCooldownSeconds(for: timeframe)
            if let lastRequest = lastRequestTimestamps[key],
               Date().timeIntervalSince(lastRequest) < cooldown {
                let waitMinutes = Int((cooldown - Date().timeIntervalSince(lastRequest)) / 60)
                #if DEBUG
                print("[AIPrediction] Cooldown active - wait \(waitMinutes) more minutes")
                #endif
                // Track cooldown triggered (cost savings)
                AnalyticsService.shared.trackAICooldownTriggered(
                    feature: .prediction,
                    tier: SubscriptionManager.shared.effectiveTier
                )
                // Return stale cached prediction if within cooldown
                if let cached = cachedPredictions[key] {
                    let prepared = cached.drivers.isEmpty ? cached.withFallbackDrivers() : cached
                    PredictionAccuracyService.shared.storePrediction(prepared, modelProvider: "deepseek-chat")
                    return prepared
                }
                throw PredictionServiceError.rateLimited
            }
        }
        
        // Check API key for direct calls - DeepSeek (recommended) or OpenAI
        // If neither is available, generate technical analysis fallback
        guard APIConfig.hasValidDeepseekKey || APIConfig.hasValidOpenAIKey else {
            #if DEBUG
            print("[AIPrediction] No AI API key configured - generating technical analysis fallback")
            #endif
            let fallbackPrediction = await generateTechnicalFallbackPrediction(
                symbol: symbol,
                coinName: coinName,
                timeframe: timeframe
            )
            cachedPredictions[key] = fallbackPrediction
            cacheTimestamps[key] = Date()
            lastRequestTimestamps[key] = Date()
            saveCachedPredictions()
            // Track technical fallback predictions so accuracy card is never empty when predictions exist.
            PredictionAccuracyService.shared.storePrediction(fallbackPrediction, modelProvider: "technical-fallback")
            enqueueGlobalOutcomeRecord(for: fallbackPrediction)
            return fallbackPrediction
        }
        
        // Log which provider will be used
        let providerInfo = AIService.shared.predictionProviderInfo
        #if DEBUG
        print("[AIPrediction] Using \(providerInfo.provider) (\(providerInfo.model)) for prediction\(providerInfo.isOptimized ? " [OPTIMIZED]" : "")")
        #endif

        // Check usage limit for direct API calls
        guard canGeneratePrediction else {
            #if DEBUG
            print("[AIPrediction] ❌ Rate limited - daily limit exceeded")
            #endif
            throw PredictionServiceError.rateLimited
        }
        
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        #if DEBUG
        print("[AIPrediction] Collecting market data for \(timeframe.displayName) timeframe...")
        #endif

        // Collect market data with timeframe-specific sparkline slicing
        let marketData = await collectMarketData(symbol: symbol, timeframe: timeframe)

        #if DEBUG
        print("[AIPrediction] Market data collected: price=$\(String(format: "%.2f", marketData.currentPrice)), drivers=\(marketData.drivers.count), timeframe=\(timeframe.displayName)")
        #endif
        
        // Build prompt
        let prompt = buildPredictionPrompt(
            symbol: symbol,
            coinName: coinName ?? symbol,
            timeframe: timeframe,
            marketData: marketData
        )
        
        // Call AI service with timeout
        #if DEBUG
        print("[AIPrediction] Calling AI service with \(predictionTimeoutSeconds)s timeout...")
        #endif
        let startTime = Date()
        
        do {
            // Check for cancellation before AI call
            try Task.checkCancellation()
            
            let systemPrompt = buildSystemPrompt()
            
            // Use actor to safely handle race between timeout and API response
            actor TimeoutCoordinator {
                var isCompleted = false
                func markCompleted() -> Bool {
                    if isCompleted { return false }
                    isCompleted = true
                    return true
                }
            }
            
            let coordinator = TimeoutCoordinator()
            
            // Wrap AI call in a timeout task using safe coordination
            let response: String = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                // Timeout task
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(self.predictionTimeoutSeconds * 1_000_000_000))
                    if await coordinator.markCompleted() {
                        continuation.resume(throwing: PredictionServiceError.timeout)
                    }
                }
                
                // API task - uses DeepSeek when available (Alpha Arena winner: +116% return)
                // Falls back to OpenAI if DeepSeek not configured
                Task {
                    do {
                        let result = try await AIService.shared.sendPredictionMessage(
                            prompt,
                            systemPrompt: systemPrompt,
                            temperature: 0.25, // Balanced temperature for varied but still consistent predictions
                            maxTokens: 512 // Predictions are structured and concise
                        )
                        if await coordinator.markCompleted() {
                            continuation.resume(returning: result.response)
                        }
                    } catch {
                        if await coordinator.markCompleted() {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            #if DEBUG
            print("[AIPrediction] AI response received in \(String(format: "%.1f", elapsed))s")
            #endif
            
            // Parse response
            let prediction = try parsePredictionResponse(
                response: response,
                symbol: symbol,
                coinName: coinName ?? symbol,
                currentPrice: marketData.currentPrice,
                timeframe: timeframe,
                drivers: marketData.drivers
            )
            
            #if DEBUG
            print("[AIPrediction] ✅ Prediction parsed: \(prediction.direction.displayName) \(prediction.formattedPriceChange) confidence=\(prediction.confidenceScore)%")
            #endif
            
            // Cache result and persist to storage
            cachedPredictions[key] = prediction
            cacheTimestamps[key] = Date()
            lastRequestTimestamps[key] = Date() // Update cooldown timestamp
            saveCachedPredictions()
            
            // Record usage
            recordUsage()
            
            // Track AI usage for cost analysis
            let providerUsed = AIService.shared.predictionProviderInfo
            AnalyticsService.shared.trackAIFeatureUsage(
                feature: .prediction,
                model: providerUsed.model,
                maxTokens: 512,
                tier: SubscriptionManager.shared.effectiveTier,
                cached: false
            )
            
            // Store prediction for accuracy tracking — tag with actual model used
            PredictionAccuracyService.shared.storePrediction(prediction, modelProvider: providerUsed.model)
            enqueueGlobalOutcomeRecord(for: prediction)
            
            return prediction
        } catch let error as PredictionServiceError where error == .timeout {
            #if DEBUG
            print("[AIPrediction] ❌ Request timed out after \(predictionTimeoutSeconds)s")
            #endif
            lastError = "Request timed out. Please try again."
            throw error
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            #if DEBUG
            print("[AIPrediction] ❌ Error after \(String(format: "%.1f", elapsed))s: \(error.localizedDescription)")
            #endif
            lastError = error.localizedDescription
            throw PredictionServiceError.aiServiceFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Firebase Backend

    /// Fire-and-forget global prediction outcome registration so backend can evaluate later
    /// and improve shared accuracy metrics across users.
    private func enqueueGlobalOutcomeRecord(for prediction: AIPricePrediction) {
        let priceLowPct = prediction.currentPrice > 0
            ? ((prediction.predictedPriceLow / prediction.currentPrice) - 1) * 100
            : nil
        let priceHighPct = prediction.currentPrice > 0
            ? ((prediction.predictedPriceHigh / prediction.currentPrice) - 1) * 100
            : nil
        let coinId = prediction.coinSymbol.lowercased()

        Task.detached(priority: .utility) {
            await FirebaseService.shared.recordPredictionOutcome(
                coinId: coinId,
                symbol: prediction.coinSymbol,
                timeframe: prediction.timeframe.firebaseTimeframe,
                direction: prediction.direction.rawValue,
                confidence: prediction.confidenceScore,
                priceAtPrediction: prediction.currentPrice,
                priceLow: priceLowPct,
                priceHigh: priceHighPct
            )
        }
    }
    
    /// Fetch prediction via Firebase Cloud Function
    /// This is the preferred method - predictions are shared across all users for the same coin/timeframe
    private func fetchPredictionViaFirebase(
        symbol: String,
        coinName: String?,
        timeframe: PredictionTimeframe
    ) async throws -> AIPricePrediction {
        // Get coin data from MarketViewModel
        let marketVM = await MainActor.run { MarketViewModel.shared }
        let coinData = await MainActor.run { marketVM.allCoins.first { $0.symbol.uppercased() == symbol.uppercased() } }
        // Use bestPrice(forSymbol:) to get live price from Firebase/Binance, falling back to allCoins cache
        let livePrice = await MainActor.run { marketVM.bestPrice(forSymbol: symbol) }
        
        // Map timeframe to Firebase format
        // All timeframes now supported including 12H via DeepSeek
        let firebaseTimeframe = timeframe.firebaseTimeframe
        
        // Get Fear & Greed index if available
        let fearGreedValue = await MainActor.run { ExtendedFearGreedViewModel.shared.currentValue }
        
        // Collect technical indicators to enrich Firebase predictions
        // This sends RSI, MACD, ADX, etc. so DeepSeek has full context
        let techIndicators = await collectTechnicalIndicatorsForFirebase(symbol: symbol, timeframe: timeframe)
        
        // Call Firebase with live price and rich technical data
        let response = try await FirebaseService.shared.getPricePrediction(
            coinId: getCoinGeckoId(for: symbol) ?? symbol.lowercased(),
            symbol: symbol,
            timeframe: firebaseTimeframe,
            currentPrice: livePrice ?? coinData?.priceUsd,
            technicalIndicators: techIndicators,
            fearGreedIndex: fearGreedValue
        )
        
        // Map Firebase response to AIPricePrediction
        let direction: PredictionDirection
        switch response.prediction.lowercased() {
        case "bullish": direction = .bullish
        case "bearish": direction = .bearish
        default: direction = .neutral
        }
        
        // Calculate price targets from percentage range using live price
        // Try multiple sources to get a valid price - this fixes the $0.00 display bug
        var currentPrice = livePrice ?? coinData?.priceUsd ?? 0
        
        // If price is still 0, try additional fallback sources
        if currentPrice <= 0 {
            // Try to get price from allCoins with different matching strategies
            let allCoins = await MainActor.run { marketVM.allCoins }
            if let matchedCoin = allCoins.first(where: { $0.symbol.uppercased() == symbol.uppercased() }),
               let price = matchedCoin.priceUsd, price > 0 {
                currentPrice = price
                #if DEBUG
                print("[AIPrediction] Price recovered from allCoins: $\(String(format: "%.2f", currentPrice))")
                #endif
            }
        }
        
        // If still 0, try LivePriceManager's currentCoinsList as last resort
        if currentPrice <= 0 {
            let lpmCoins = await MainActor.run { LivePriceManager.shared.currentCoinsList }
            if let matchedCoin = lpmCoins.first(where: { $0.symbol.uppercased() == symbol.uppercased() }),
               let price = matchedCoin.priceUsd, price > 0 {
                currentPrice = price
                #if DEBUG
                print("[AIPrediction] Price recovered from LivePriceManager: $\(String(format: "%.2f", currentPrice))")
                #endif
            }
        }

        #if DEBUG
        // Log warning if we couldn't get a valid price - prediction will still work
        // but the view will need to use live price fallback for display
        if currentPrice <= 0 {
            print("[AIPrediction] ⚠️ Warning: Could not get valid price for \(symbol). View will use live price fallback.")
        }

        // Debug: Log raw Firebase response
        print("[AIPrediction] 📊 Firebase Response for \(symbol) (\(firebaseTimeframe)):")
        print("  - Direction: \(response.prediction)")
        print("  - Confidence: \(response.confidence)")
        print("  - PriceRange: \(response.priceRange.map { "low: \($0.low), high: \($0.high)" } ?? "nil")")
        print("  - Cached: \(response.cached)")
        #endif
        
        // Calculate price range with direction-aware fallbacks
        // The bug was: if priceRange is nil or both values are 0, we'd get 0% change
        let rawLowPct = response.priceRange?.low
        let rawHighPct = response.priceRange?.high
        
        // Timeframe-specific expected move ranges (based on typical crypto volatility)
        let (defaultLow, defaultHigh): (Double, Double) = {
            switch timeframe {
            case .hour: return (-1.5, 1.5)
            case .fourHours: return (-3.0, 3.0)
            case .twelveHours: return (-4.5, 4.5)
            case .day: return (-6.0, 6.0)
            case .week: return (-12.0, 12.0)
            case .month: return (-20.0, 20.0)
            }
        }()
        
        // Check if priceRange is missing or suspiciously zero (indicates Firebase returned bad data)
        let priceRangeIsMissing = rawLowPct == nil && rawHighPct == nil
        let priceRangeIsZero = (rawLowPct ?? 0) == 0 && (rawHighPct ?? 0) == 0
        
        var lowPct: Double
        var highPct: Double
        
        if priceRangeIsMissing || priceRangeIsZero {
            // Firebase didn't return valid price range - infer from direction
            #if DEBUG
            print("[AIPrediction] ⚠️ Price range missing/zero, inferring from direction: \(direction.rawValue)")
            #endif
            
            switch direction {
            case .bullish:
                // Bullish: skew range upward
                lowPct = defaultLow * 0.3  // Smaller downside
                highPct = defaultHigh * 1.2  // Larger upside
            case .bearish:
                // Bearish: skew range downward
                lowPct = defaultLow * 1.2  // Larger downside
                highPct = defaultHigh * 0.3  // Smaller upside
            case .neutral:
                // Neutral: use full default range — price could go either way
                // Previously 0.5x which was too tight and caused instant "Target Reached"
                lowPct = defaultLow * 0.8
                highPct = defaultHigh * 0.8
            }
            
            #if DEBUG
            print("[AIPrediction] 🔄 Inferred range: low=\(String(format: "%.2f", lowPct))%, high=\(String(format: "%.2f", highPct))%")
            #endif
        } else {
            // Use Firebase values
            lowPct = rawLowPct ?? defaultLow
            highPct = rawHighPct ?? defaultHigh
        }
        
        // Ensure lowPct < highPct
        if lowPct > highPct { swap(&lowPct, &highPct) }
        
        // Guard against zero/negative currentPrice
        let safePrice = currentPrice > 0 ? currentPrice : 1.0
        
        var targetLow = safePrice * (1 + lowPct / 100)
        var targetHigh = safePrice * (1 + highPct / 100)
        
        // Ensure non-negative and proper ordering
        targetLow = max(0, targetLow)
        targetHigh = max(targetLow + 0.01, targetHigh)
        
        let predictedChangePercent = (lowPct + highPct) / 2
        
        #if DEBUG
        print("[AIPrediction] ✅ Final prediction: \(String(format: "%.2f", predictedChangePercent))% change")
        #endif
        
        // Validate and adjust confidence based on timeframe constraints
        // Firebase may return overly uniform values, so we apply timeframe-based caps
        let rawConfidence = min(100, max(0, response.confidence))
        
        // Apply timeframe-specific confidence caps (longer timeframes = lower max confidence)
        let maxConfidenceForTimeframe: Int
        switch timeframe {
        case .hour: maxConfidenceForTimeframe = 82
        case .fourHours: maxConfidenceForTimeframe = 78
        case .twelveHours: maxConfidenceForTimeframe = 72
        case .day: maxConfidenceForTimeframe = 68
        case .week: maxConfidenceForTimeframe = 62
        case .month: maxConfidenceForTimeframe = 55
        }
        
        // If raw confidence is suspiciously close to a default value (60-70 range),
        // apply deterministic timeframe-based adjustment instead of random noise.
        // This ensures consistency: two users see the same confidence for the same prediction.
        var adjustedConfidence = rawConfidence
        if rawConfidence >= 60 && rawConfidence <= 70 {
            // Likely a default value from the AI - apply timeframe-aware cap
            // Longer timeframes should have lower confidence (more uncertainty)
            let timeframeAdjustment: Int
            switch timeframe {
            case .hour: timeframeAdjustment = 5         // Short-term can be more confident
            case .fourHours: timeframeAdjustment = 0    // Slight boost
            case .twelveHours: timeframeAdjustment = -3 // Moderate reduction
            case .day: timeframeAdjustment = -7         // Daily has more noise
            case .week: timeframeAdjustment = -12       // Weekly is inherently uncertain
            case .month: timeframeAdjustment = -18      // Monthly is most uncertain
            }
            adjustedConfidence = rawConfidence + timeframeAdjustment
            #if DEBUG
            print("[AIPrediction] Confidence adjusted for timeframe: \(rawConfidence) -> \(adjustedConfidence) (\(timeframe.displayName))")
            #endif
        }
        
        // Apply timeframe cap
        let confidenceScore = min(maxConfidenceForTimeframe, max(15, adjustedConfidence))
        // Use the unified PredictionConfidence.from() method for consistency
        let confidence = PredictionConfidence.from(score: confidenceScore)
        
        // Create fallback drivers for Firebase predictions (since Firebase doesn't return detailed drivers)
        let signalValue = direction == .bullish ? "bullish" : (direction == .bearish ? "bearish" : "neutral")
        let directionLabel = direction == .bullish ? "Bullish" : (direction == .bearish ? "Bearish" : "Neutral")
        let fallbackDrivers: [PredictionDriver] = [
            PredictionDriver(
                name: "AI Analysis",
                value: "\(directionLabel) outlook",
                signal: signalValue,
                weight: 0.5
            ),
            PredictionDriver(
                name: "Market Sentiment",
                value: "\(directionLabel) bias",
                signal: signalValue,
                weight: 0.3
            ),
            PredictionDriver(
                name: "Price Action",
                value: "\(directionLabel) momentum",
                signal: signalValue,
                weight: 0.2
            )
        ]
        
        let prediction = AIPricePrediction(
            id: UUID().uuidString,
            coinSymbol: symbol.uppercased(),
            coinName: coinName ?? symbol,
            currentPrice: currentPrice,
            predictedPriceChange: predictedChangePercent,
            predictedPriceLow: targetLow,
            predictedPriceHigh: targetHigh,
            confidenceScore: confidenceScore,
            confidence: confidence,
            direction: direction,
            timeframe: timeframe,
            drivers: fallbackDrivers,
            analysis: response.reasoning,
            generatedAt: Date(),
            probabilityUp2Pct: nil,
            probabilityUp5Pct: nil,
            probabilityUp10Pct: nil,
            probabilityDown2Pct: nil,
            probabilityDown5Pct: nil,
            probabilityDown10Pct: nil,
            directionalScore: nil
        )
        
        // Track usage with actual model from Firebase response
        AnalyticsService.shared.trackAIFeatureUsage(
            feature: .prediction,
            model: response.model ?? "deepseek-chat", // Firebase shared predictions use DeepSeek
            maxTokens: 512,
            tier: SubscriptionManager.shared.effectiveTier,
            cached: response.cached
        )
        
        return prediction
    }
    
    /// Map common symbols to CoinGecko IDs
    private func getCoinGeckoId(for symbol: String) -> String? {
        let mapping: [String: String] = [
            "BTC": "bitcoin",
            "ETH": "ethereum",
            "SOL": "solana",
            "XRP": "ripple",
            "ADA": "cardano",
            "DOGE": "dogecoin",
            "AVAX": "avalanche-2",
            "LINK": "chainlink",
            "DOT": "polkadot",
            "MATIC": "matic-network",
            "SHIB": "shiba-inu",
            "LTC": "litecoin",
        ]
        return mapping[symbol.uppercased()]
    }
    
    // MARK: - Data Collection
    
    private struct MarketDataSnapshot {
        let currentPrice: Double
        let change24h: Double
        let change7d: Double
        let volume24h: Double
        let marketCap: Double
        let rsi: Double?
        let stochRSI: (k: Double, d: Double)?
        let macdSignal: String?
        let maAlignment: String?
        let adx: Double?
        let bollingerPosition: String?
        let supportLevel: Double?
        let resistanceLevel: Double?
        let volumeTrend: String?
        let rangeTightness: Double?
        let fearGreedIndex: Int?
        let fearGreedClassification: String?
        // MARK: - Smart Money / Whale Data
        let smartMoneyIndex: Int?
        let smartMoneyTrend: String?
        let exchangeNetFlow: Double?
        let exchangeFlowSentiment: String?
        let recentWhaleActivity: String?
        // MARK: - Market Regime & Confluence
        let marketRegime: MarketRegime?
        let regimeConfidence: Double?
        let multiTimeframeConfluence: MultiTimeframeConfluence?
        // MARK: - Derivatives Market Data
        let fundingRate: Double?              // Current funding rate (e.g., 0.0001 = 0.01%)
        let fundingRateSentiment: String?     // "bullish_crowd", "bearish_crowd", "neutral"
        let openInterest: Double?             // Open interest in USD
        let openInterestFormatted: String?    // Formatted OI string (e.g., "$15.2B")
        // MARK: - Trader Positioning Data
        let longShortRatio: Double?           // Global long/short account ratio
        let longShortSentiment: String?       // "extreme_long", "bullish_crowd", "balanced", etc.
        let topTraderRatio: Double?           // Top traders' long/short position ratio
        let topTraderSignal: String?          // "top_traders_long", "top_traders_short", etc.
        let takerBuySellRatio: Double?        // Taker buy/sell volume ratio
        let takerSignal: String?              // "aggressive_buying", "aggressive_selling", etc.
        // MARK: - Market Context
        let btcDominance: Double?             // BTC market dominance percentage
        let drivers: [PredictionDriver]
    }
    
    // MARK: - Multi-Timeframe Confluence
    
    /// Result of multi-timeframe confluence analysis
    struct MultiTimeframeConfluence {
        let agrees: Bool
        let higherTimeframeTrend: String  // "bullish", "bearish", "neutral"
        let shortTermTrend: String
        let confluenceStrength: Double  // 0-1
        let details: String
        
        var summary: String {
            if agrees {
                return "Higher TF confirms \(higherTimeframeTrend) (\(Int(confluenceStrength * 100))% strength)"
            } else {
                return "Divergence: short-term \(shortTermTrend), higher TF \(higherTimeframeTrend)"
            }
        }
    }
    
    /// Returns the number of data points to use for technical indicator calculations based on timeframe.
    /// Shorter timeframes use more recent data for more relevant momentum signals.
    private func dataPointsForIndicators(timeframe: PredictionTimeframe) -> Int {
        switch timeframe {
        case .hour:
            return 12      // ~12 hours - very recent momentum for 1H predictions
        case .fourHours:
            return 24      // ~1 day - short-term trend for 4H predictions
        case .twelveHours:
            return 36      // ~1.5 days - medium-term trend for 12H predictions
        case .day:
            return 48      // ~2 days - day trading context for 24H predictions
        case .week:
            return 168     // Full 7 days for weekly predictions
        case .month:
            return 168     // Full 7 days (best available) for monthly predictions
        }
    }
    
    /// Check multi-timeframe confluence - whether higher timeframes agree with the prediction direction
    /// This increases confidence when multiple timeframes align
    private func checkMultiTimeframeConfluence(
        sparkline: [Double],
        targetTimeframe: PredictionTimeframe
    ) -> MultiTimeframeConfluence? {
        // Need sufficient data for higher timeframe analysis
        guard sparkline.count >= 50 else { return nil }
        
        // Determine what constitutes "higher timeframe" for comparison
        // 1H -> compare with daily data (full sparkline)
        // 4H -> compare with daily data
        // 1D -> compare with weekly trend (full sparkline)
        // 7D -> compare with monthly perspective (full sparkline)
        // 30D -> no higher TF available
        
        let shortTermPoints: Int
        let longTermPoints: Int
        
        switch targetTimeframe {
        case .hour:
            shortTermPoints = 12   // ~12 hours
            longTermPoints = 168   // Full 7 days
        case .fourHours:
            shortTermPoints = 24   // ~1 day
            longTermPoints = 168   // Full 7 days
        case .twelveHours:
            shortTermPoints = 36   // ~1.5 days
            longTermPoints = 168   // Full 7 days
        case .day:
            shortTermPoints = 48   // ~2 days
            longTermPoints = 168   // Full 7 days
        case .week:
            shortTermPoints = 96   // ~4 days
            longTermPoints = 168   // Full 7 days
        case .month:
            // For monthly, use full data - no higher TF comparison meaningful
            return nil
        }
        
        guard sparkline.count >= longTermPoints else { return nil }
        
        // Get short-term trend from recent data
        let shortTermData = Array(sparkline.suffix(shortTermPoints))
        let shortTermTrend = determineTrend(from: shortTermData)
        
        // Get long-term trend from full data
        let longTermTrend = determineTrend(from: sparkline)
        
        // Calculate confluence
        let agrees = shortTermTrend == longTermTrend || longTermTrend == "neutral"
        
        // Calculate strength based on how strong each trend signal is
        let shortMA = shortTermData.count >= 10 ? TechnicalsEngine.sma(shortTermData, period: 10) : nil
        let longMA = sparkline.count >= 50 ? TechnicalsEngine.sma(sparkline, period: 50) : nil
        
        var confluenceStrength: Double = 0.5
        if let shortMA = shortMA, let longMA = longMA, let lastPrice = sparkline.last {
            // Price above both MAs and short MA > long MA = strong bullish confluence
            // Price below both MAs and short MA < long MA = strong bearish confluence
            let priceVsShort = lastPrice > shortMA
            let priceVsLong = lastPrice > longMA
            let shortVsLong = shortMA > longMA
            
            if priceVsShort && priceVsLong && shortVsLong {
                confluenceStrength = 0.9  // Strong bullish alignment
            } else if !priceVsShort && !priceVsLong && !shortVsLong {
                confluenceStrength = 0.9  // Strong bearish alignment
            } else if (priceVsShort == priceVsLong) {
                confluenceStrength = 0.7  // Moderate alignment
            } else {
                confluenceStrength = 0.4  // Mixed signals
            }
        }
        
        let details: String
        if agrees {
            details = "Short-term (\(shortTermPoints)h) and long-term (7d) trends align: \(longTermTrend)"
        } else {
            details = "Divergence detected: short-term \(shortTermTrend), long-term \(longTermTrend)"
        }
        
        return MultiTimeframeConfluence(
            agrees: agrees,
            higherTimeframeTrend: longTermTrend,
            shortTermTrend: shortTermTrend,
            confluenceStrength: agrees ? confluenceStrength : confluenceStrength * 0.5,
            details: details
        )
    }
    
    /// Determine trend direction from price data using MA crossover and price position
    private func determineTrend(from data: [Double]) -> String {
        guard data.count >= 20 else { return "neutral" }
        
        // Calculate short and medium MAs
        let shortPeriod = min(10, data.count / 2)
        let medPeriod = min(20, data.count)
        
        guard let shortMA = TechnicalsEngine.sma(data, period: shortPeriod),
              let medMA = TechnicalsEngine.sma(data, period: medPeriod),
              let lastPrice = data.last else {
            return "neutral"
        }
        
        // Calculate price change over the period
        let firstPrice = data.first ?? lastPrice
        let priceChange = (lastPrice - firstPrice) / firstPrice * 100
        
        // Determine trend
        if shortMA > medMA && lastPrice > shortMA && priceChange > 1 {
            return "bullish"
        } else if shortMA < medMA && lastPrice < shortMA && priceChange < -1 {
            return "bearish"
        } else {
            return "neutral"
        }
    }
    
    /// Generates a technical analysis-based prediction when AI is unavailable
    /// Collect technical indicators to send to Firebase for enriched DeepSeek predictions.
    /// This ensures the server-side AI has the same rich data as local predictions.
    private func collectTechnicalIndicatorsForFirebase(symbol: String, timeframe: PredictionTimeframe) async -> [String: Any] {
        let sym = symbol.uppercased()
        let marketVM = MarketViewModel.shared
        let coin = marketVM.allCoins.first { $0.symbol.uppercased() == sym }
        var indicators: [String: Any] = [:]
        
        // Price momentum
        let change24h = coin?.unified24hPercent ?? coin?.changePercent24Hr ?? 0
        let change7d = coin?.unified7dPercent ?? coin?.weeklyChange ?? 0
        if change24h != 0 { indicators["change24h"] = String(format: "%.2f", change24h) }
        if change7d != 0 { indicators["change7d"] = String(format: "%.2f", change7d) }
        
        // Use sparkline data sliced for the specific timeframe
        let fullSparkline = coin?.sparklineIn7d ?? []
        let targetPoints = dataPointsForIndicators(timeframe: timeframe)
        let sparkline: [Double] = fullSparkline.count <= targetPoints ? fullSparkline : Array(fullSparkline.suffix(targetPoints))
        
        if sparkline.count >= 14 {
            // RSI
            if let rsiVal = TechnicalsEngine.rsi(sparkline) {
                let zone = rsiVal < 30 ? "Oversold" : (rsiVal > 70 ? "Overbought" : "Neutral")
                indicators["rsi"] = "\(String(format: "%.1f", rsiVal)) [\(zone)]"
            }
            
            // Stochastic RSI
            if let stoch = TechnicalsEngine.stochRSI(sparkline) {
                let signal = stoch.k < 20 ? "Oversold" : (stoch.k > 80 ? "Overbought" : (stoch.k > stoch.d ? "Bullish cross" : "Bearish cross"))
                indicators["stochRSI"] = "K=\(String(format: "%.0f", stoch.k)), D=\(String(format: "%.0f", stoch.d)) - \(signal)"
            }
            
            // MACD
            if let macd = TechnicalsEngine.macdLineSignal(sparkline) {
                let isBullish = macd.macd > macd.signal
                indicators["macdSignal"] = isBullish ? "Bullish" : "Bearish"
            }
            
            // ADX
            if let adxResult = TechnicalsEngine.adxApprox(sparkline) {
                let strength = adxResult.adx > 40 ? "Very Strong" : (adxResult.adx > 25 ? "Strong" : (adxResult.adx > 20 ? "Developing" : "Weak"))
                indicators["adx"] = "\(String(format: "%.0f", adxResult.adx)) - \(strength)"
            }
            
            // MA Alignment
            if sparkline.count >= 50, let ma = TechnicalsEngine.maAlignment(closes: sparkline) {
                indicators["maTrend"] = ma.order.replacingOccurrences(of: "_", with: " ").capitalized
            }
            
            // Bollinger Bands
            if let bb = TechnicalsEngine.bollingerBands(sparkline), let lastPrice = sparkline.last {
                let percentB = (lastPrice - bb.lower) / (bb.upper - bb.lower) * 100
                indicators["bollingerPosition"] = "\(String(format: "%.0f", percentB))%B"
            }
        }
        
        // Volume trend
        let volume24h = coin?.volumeUsd24Hr ?? 0
        let marketCap = coin?.marketCap ?? 0
        if volume24h > 0 && marketCap > 0 {
            let ratio = (volume24h / marketCap) * 100
            let trend = ratio > 25 ? "Very High" : (ratio > 15 ? "High" : (ratio > 8 ? "Above Avg" : (ratio > 3 ? "Normal" : "Low")))
            indicators["volumeTrend"] = trend
        }
        
        // BTC Dominance
        if let btcDom = marketVM.btcDominance, btcDom > 0 {
            indicators["btcDominance"] = String(format: "%.1f", btcDom)
        }
        
        // Smart Money / Whale data (MainActor properties)
        let whaleService = WhaleTrackingService.shared
        if let smi = whaleService.smartMoneyIndex {
            indicators["smartMoneyIndex"] = "\(smi.score)/100 (\(smi.trend.rawValue))"
        }
        if let stats = whaleService.statistics {
            indicators["exchangeFlowSentiment"] = stats.flowSentiment
        }
        
        // Market Regime detection from sparkline
        let fullSparklineForRegime = coin?.sparklineIn7d ?? []
        if fullSparklineForRegime.count >= 20 {
            let regimeResult = MarketRegimeDetector.detectRegime(closes: fullSparklineForRegime)
            indicators["marketRegime"] = regimeResult.regime.rawValue
        }
        
        return indicators
    }
    
    private func generateTechnicalFallbackPrediction(
        symbol: String,
        coinName: String?,
        timeframe: PredictionTimeframe
    ) async -> AIPricePrediction {
        let sym = symbol.uppercased()
        let marketVM = MarketViewModel.shared
        let coin = marketVM.allCoins.first { $0.symbol.uppercased() == sym }
        
        // Try multiple sources to get a valid price - fixes $0.00 display bug
        var currentPrice = coin?.priceUsd ?? 0
        if currentPrice <= 0 {
            currentPrice = marketVM.bestPrice(forSymbol: sym) ?? 0
        }
        if currentPrice <= 0 {
            // Try LivePriceManager's currentCoinsList
            let lpmCoins = await MainActor.run { LivePriceManager.shared.currentCoinsList }
            if let matchedCoin = lpmCoins.first(where: { $0.symbol.uppercased() == sym }),
               let price = matchedCoin.priceUsd, price > 0 {
                currentPrice = price
            }
        }
        
        let change24h = coin?.dailyChange ?? 0
        let sparkline = coin?.sparklineIn7d ?? []
        
        var drivers: [PredictionDriver] = []
        var bullishSignals = 0
        var bearishSignals = 0
        
        // RSI analysis
        if sparkline.count >= 14, let rsi = TechnicalsEngine.rsi(sparkline, period: 14) {
            let rsiSignal: String
            if rsi < 30 {
                rsiSignal = "bullish"
                bullishSignals += 2 // Oversold is a strong bullish signal
            } else if rsi > 70 {
                rsiSignal = "bearish"
                bearishSignals += 2 // Overbought is a strong bearish signal
            } else if rsi < 45 {
                rsiSignal = "bullish"
                bullishSignals += 1
            } else if rsi > 55 {
                rsiSignal = "bearish"
                bearishSignals += 1
            } else {
                rsiSignal = "neutral"
            }
            drivers.append(PredictionDriver(name: "RSI(14)", value: String(format: "%.0f", rsi), signal: rsiSignal, weight: 0.3))
        }
        
        // Price momentum
        if change24h > 3 {
            bullishSignals += 1
            drivers.append(PredictionDriver(name: "24h Momentum", value: String(format: "+%.1f%%", change24h), signal: "bullish", weight: 0.2))
        } else if change24h < -3 {
            bearishSignals += 1
            drivers.append(PredictionDriver(name: "24h Momentum", value: String(format: "%.1f%%", change24h), signal: "bearish", weight: 0.2))
        } else {
            drivers.append(PredictionDriver(name: "24h Momentum", value: String(format: "%.1f%%", change24h), signal: "neutral", weight: 0.2))
        }
        
        // Market sentiment
        if let sentiment = ExtendedFearGreedViewModel.shared.currentValue {
            let sentimentSignal: String
            if sentiment < 30 {
                sentimentSignal = "bullish" // Contrarian - extreme fear often precedes rallies
                bullishSignals += 1
            } else if sentiment > 70 {
                sentimentSignal = "bearish" // Contrarian - extreme greed often precedes corrections
                bearishSignals += 1
            } else {
                sentimentSignal = "neutral"
            }
            drivers.append(PredictionDriver(name: "Market Sentiment", value: "\(sentiment)/100", signal: sentimentSignal, weight: 0.2))
        }
        
        // Determine direction and confidence with timeframe awareness
        let direction: PredictionDirection
        var confidenceScore: Int
        let confidence: PredictionConfidence
        var predictedChange: Double
        
        // Timeframe-specific confidence caps and base values
        let (baseConfidence, maxConfidence, moveScale): (Int, Int, Double) = {
            switch timeframe {
            case .hour: return (45, 75, 0.5)
            case .fourHours: return (42, 72, 0.75)
            case .twelveHours: return (40, 68, 1.0)
            case .day: return (38, 65, 1.5)
            case .week: return (35, 60, 2.5)
            case .month: return (30, 52, 4.0)
            }
        }()
        
        let netSignal = bullishSignals - bearishSignals
        if netSignal >= 2 {
            direction = .bullish
            confidenceScore = min(baseConfidence + netSignal * 6, maxConfidence)
            predictedChange = Double(netSignal) * moveScale + Double.random(in: 0.3...1.5) * moveScale
        } else if netSignal <= -2 {
            direction = .bearish
            confidenceScore = min(baseConfidence + abs(netSignal) * 6, maxConfidence)
            predictedChange = Double(netSignal) * moveScale - Double.random(in: 0.3...1.5) * moveScale
        } else {
            // Mixed signals — still make a directional call based on lean
            // Avoid defaulting to neutral: use netSignal direction even if weak
            confidenceScore = max(20, baseConfidence - 10)
            
            if netSignal > 0 {
                // Slight bullish lean
                direction = .bullish
                predictedChange = Double.random(in: 0.2...0.8) * moveScale
            } else if netSignal < 0 {
                // Slight bearish lean
                direction = .bearish
                predictedChange = Double.random(in: -0.8 ... -0.2) * moveScale
            } else {
                // Truly 50/50 — use recent price momentum as tiebreaker
                let recentMomentum = change24h
                if recentMomentum > 0 {
                    direction = .bullish
                    predictedChange = Double.random(in: 0.1...0.5) * moveScale
                } else if recentMomentum < 0 {
                    direction = .bearish
                    predictedChange = Double.random(in: -0.5 ... -0.1) * moveScale
                } else {
                    // Only truly neutral if absolutely no signal at all
                    direction = .neutral
                    predictedChange = Double.random(in: -0.3...0.3) * moveScale
                }
            }
        }
        
        // Ensure confidence is in reasonable range
        confidence = PredictionConfidence.from(score: confidenceScore)
        
        // Calculate price range based on timeframe volatility
        let volatilityMultiplier: Double
        switch timeframe {
        case .hour: volatilityMultiplier = 0.5
        case .fourHours: volatilityMultiplier = 0.75
        case .twelveHours: volatilityMultiplier = 0.875
        case .day: volatilityMultiplier = 1.0
        case .week: volatilityMultiplier = 2.5
        case .month: volatilityMultiplier = 5.0
        }
        
        let rangePercent = abs(predictedChange) + (3.0 * volatilityMultiplier)
        let safePrice = currentPrice > 0 ? currentPrice : 1.0
        var targetLow = safePrice * (1 + (predictedChange - rangePercent) / 100)
        var targetHigh = safePrice * (1 + (predictedChange + rangePercent) / 100)
        targetLow = max(0, targetLow)
        targetHigh = max(targetLow + 0.01, targetHigh)
        
        // Build analysis text
        let analysisText = buildFallbackAnalysisText(
            symbol: sym,
            direction: direction,
            drivers: drivers,
            change24h: change24h
        )
        
        return AIPricePrediction(
            id: UUID().uuidString,
            coinSymbol: sym,
            coinName: coinName ?? symbol,
            currentPrice: currentPrice,
            predictedPriceChange: predictedChange,
            predictedPriceLow: targetLow,
            predictedPriceHigh: targetHigh,
            confidenceScore: confidenceScore,
            confidence: confidence,
            direction: direction,
            timeframe: timeframe,
            drivers: drivers,
            analysis: analysisText,
            generatedAt: Date(),
            probabilityUp2Pct: nil,
            probabilityUp5Pct: nil,
            probabilityUp10Pct: nil,
            probabilityDown2Pct: nil,
            probabilityDown5Pct: nil,
            probabilityDown10Pct: nil,
            directionalScore: nil
        )
    }
    
    /// Builds analysis text for fallback predictions
    private func buildFallbackAnalysisText(
        symbol: String,
        direction: PredictionDirection,
        drivers: [PredictionDriver],
        change24h: Double
    ) -> String {
        var parts: [String] = []
        
        // Opening based on direction
        switch direction {
        case .bullish:
            parts.append("Technical indicators suggest bullish momentum for \(symbol).")
        case .bearish:
            parts.append("Technical indicators suggest bearish pressure on \(symbol).")
        case .neutral:
            parts.append("\(symbol) shows mixed signals with no clear directional bias.")
        }
        
        // Key driver mentions
        for driver in drivers.prefix(2) {
            if driver.signal != "neutral" {
                parts.append("\(driver.name) at \(driver.value) is \(driver.signal).")
            }
        }
        
        // Disclaimer
        parts.append("Analysis based on technical indicators; connect AI for deeper insights.")
        
        return parts.joined(separator: " ")
    }
    
    /// Calculate dynamic confidence based on market signals and timeframe
    /// Used to validate/adjust AI confidence scores
    private func calculateSignalBasedConfidence(
        drivers: [PredictionDriver],
        timeframe: PredictionTimeframe,
        fearGreedValue: Int?
    ) -> Int {
        var baseConfidence: Int
        
        // Base confidence varies by timeframe (longer = less certain)
        switch timeframe {
        case .hour:
            baseConfidence = 55  // 1H can have higher confidence when signals are clear
        case .fourHours:
            baseConfidence = 50
        case .twelveHours:
            baseConfidence = 45
        case .day:
            baseConfidence = 42
        case .week:
            baseConfidence = 38
        case .month:
            baseConfidence = 32  // 30D predictions inherently less certain
        }
        
        // Signal agreement bonus/penalty
        let bullishCount = drivers.filter { $0.signal.lowercased() == "bullish" }.count
        let bearishCount = drivers.filter { $0.signal.lowercased() == "bearish" }.count
        let neutralCount = drivers.filter { $0.signal.lowercased() == "neutral" }.count
        let totalSignals = bullishCount + bearishCount + neutralCount
        
        if totalSignals > 0 {
            let dominantCount = max(bullishCount, bearishCount)
            let agreementRatio = Double(dominantCount) / Double(totalSignals)
            
            if agreementRatio >= 0.75 {
                // Strong agreement (+15-20 confidence)
                baseConfidence += Int((agreementRatio - 0.5) * 60)
            } else if agreementRatio >= 0.5 {
                // Moderate agreement (+5-10 confidence)
                baseConfidence += Int((agreementRatio - 0.5) * 30)
            } else {
                // Mixed signals (-5 to -15 confidence)
                baseConfidence -= Int((0.5 - agreementRatio) * 30)
            }
        }
        
        // Fear & Greed impact - extreme values increase confidence for contrarian calls
        if let fgi = fearGreedValue {
            if fgi < 25 || fgi > 75 {
                // Extreme sentiment is more predictive
                baseConfidence += 8
            } else if fgi >= 40 && fgi <= 60 {
                // Neutral sentiment is less predictive
                baseConfidence -= 5
            }
        }
        
        // Weighted driver strength bonus
        let weightedStrength = drivers.reduce(0.0) { sum, driver in
            let signalStrength = driver.signal.lowercased() != "neutral" ? 1.0 : 0.0
            return sum + (driver.weight * signalStrength)
        }
        let avgWeightedStrength = drivers.isEmpty ? 0 : weightedStrength / Double(drivers.count)
        baseConfidence += Int(avgWeightedStrength * 15)
        
        // Clamp to reasonable range based on timeframe
        let maxConfidence: Int
        switch timeframe {
        case .hour: maxConfidence = 80
        case .fourHours: maxConfidence = 75
        case .twelveHours: maxConfidence = 70
        case .day: maxConfidence = 68
        case .week: maxConfidence = 62
        case .month: maxConfidence = 55
        }
        
        return max(15, min(maxConfidence, baseConfidence))
    }
    
    private func collectMarketData(symbol: String, timeframe: PredictionTimeframe) async -> MarketDataSnapshot {
        let sym = symbol.uppercased()
        var drivers: [PredictionDriver] = []
        
        // Get coin data from MarketViewModel
        let marketVM = MarketViewModel.shared
        let coin = marketVM.allCoins.first { $0.symbol.uppercased() == sym }
        
        // Use bestPrice(forSymbol:) to get live price from Firebase/Binance, falling back to allCoins cache
        // Try multiple sources to avoid $0 price issue
        var currentPrice = marketVM.bestPrice(forSymbol: sym) ?? coin?.priceUsd ?? 0
        
        // If price is still 0, try LivePriceManager's currentCoinsList as additional fallback
        if currentPrice <= 0 {
            let lpmCoins = await MainActor.run { LivePriceManager.shared.currentCoinsList }
            if let matchedCoin = lpmCoins.first(where: { $0.symbol.uppercased() == sym }),
               let price = matchedCoin.priceUsd, price > 0 {
                currentPrice = price
                #if DEBUG
                print("[AIPrediction] collectMarketData: Price recovered from LivePriceManager: $\(String(format: "%.2f", currentPrice))")
                #endif
            }
        }
        
        let change24h = coin?.unified24hPercent ?? coin?.changePercent24Hr ?? 0
        let change7d = coin?.unified7dPercent ?? coin?.weeklyChange ?? 0
        let volume24h = coin?.volumeUsd24Hr ?? 0
        let marketCap = coin?.marketCap ?? 0
        
        // Add price momentum driver - weight based on timeframe relevance
        if change24h != 0 {
            let signal = change24h > 0 ? "bullish" : "bearish"
            // 24H momentum is more relevant for short timeframes
            let weight: Double = timeframe.isShortTerm ? 0.8 : 0.6
            drivers.append(PredictionDriver(
                name: "24H Momentum",
                value: String(format: "%.2f%%", change24h),
                signal: signal,
                weight: weight
            ))
        }
        
        if change7d != 0 {
            let signal = change7d > 0 ? "bullish" : "bearish"
            // 7D trend is more relevant for longer timeframes
            let weight: Double = timeframe.isShortTerm ? 0.3 : 0.5
            drivers.append(PredictionDriver(
                name: "7D Trend",
                value: String(format: "%.2f%%", change7d),
                signal: signal,
                weight: weight
            ))
        }
        
        // Get technical indicators
        var rsi: Double? = nil
        var stochRSI: (k: Double, d: Double)? = nil
        var macdSignal: String? = nil
        var maAlignment: String? = nil
        var adx: Double? = nil
        var bollingerPosition: String? = nil
        var supportLevel: Double? = nil
        var resistanceLevel: Double? = nil
        var volumeTrend: String? = nil
        var rangeTightness: Double? = nil
        
        // Use sparkline data sliced for the specific timeframe
        // This ensures shorter timeframes use more recent data for momentum signals
        let fullSparkline = coin?.sparklineIn7d ?? []
        let targetPoints = dataPointsForIndicators(timeframe: timeframe)
        let sparkline: [Double] = {
            if fullSparkline.count <= targetPoints {
                return fullSparkline
            }
            // Take the most recent N points for timeframe-appropriate analysis
            return Array(fullSparkline.suffix(targetPoints))
        }()
        
        if sparkline.count >= 14 {
            // RSI (14)
            if let rsiVal = TechnicalsEngine.rsi(sparkline) {
                rsi = rsiVal
                let signal: String
                let interpretation: String
                if rsiVal < 30 {
                    signal = "bullish"
                    interpretation = "Oversold"
                } else if rsiVal > 70 {
                    signal = "bearish"
                    interpretation = "Overbought"
                } else if rsiVal < 45 {
                    signal = "neutral"
                    interpretation = "Weakening"
                } else if rsiVal > 55 {
                    signal = "neutral"
                    interpretation = "Strengthening"
                } else {
                    signal = "neutral"
                    interpretation = "Neutral"
                }
                drivers.append(PredictionDriver(
                    name: "RSI(14)",
                    value: "\(String(format: "%.1f", rsiVal)) - \(interpretation)",
                    signal: signal,
                    weight: 0.7
                ))
            }
            
            // Stochastic RSI - more sensitive for momentum
            if let stochResult = TechnicalsEngine.stochRSI(sparkline) {
                stochRSI = stochResult
                let signal: String
                let interpretation: String
                if stochResult.k < 20 && stochResult.d < 20 {
                    signal = "bullish"
                    interpretation = "Oversold"
                } else if stochResult.k > 80 && stochResult.d > 80 {
                    signal = "bearish"
                    interpretation = "Overbought"
                } else if stochResult.k > stochResult.d {
                    signal = "bullish"
                    interpretation = "Bullish cross"
                } else if stochResult.k < stochResult.d {
                    signal = "bearish"
                    interpretation = "Bearish cross"
                } else {
                    signal = "neutral"
                    interpretation = "Neutral"
                }
                drivers.append(PredictionDriver(
                    name: "Stoch RSI",
                    value: "\(String(format: "%.0f", stochResult.k))/\(String(format: "%.0f", stochResult.d)) - \(interpretation)",
                    signal: signal,
                    weight: 0.6
                ))
            }
            
            // MACD
            if let macd = TechnicalsEngine.macdLineSignal(sparkline) {
                let isBullish = macd.macd > macd.signal
                let histogram = macd.macd - macd.signal
                macdSignal = isBullish ? "bullish" : "bearish"
                
                // Check MACD momentum (is histogram growing or shrinking?)
                let momentum = abs(histogram) > 0.001 ? (histogram > 0 ? "expanding" : "contracting") : "flat"
                
                drivers.append(PredictionDriver(
                    name: "MACD",
                    value: isBullish ? "Bullish (\(momentum))" : "Bearish (\(momentum))",
                    signal: macdSignal!,
                    weight: 0.65
                ))
            }
            
            // ADX - Trend Strength (research-backed: ADX > 25 = strong trend)
            if let adxResult = TechnicalsEngine.adxApprox(sparkline) {
                adx = adxResult.adx
                let signal: String
                let strength: String
                if adxResult.adx > 40 {
                    strength = "Very Strong"
                    signal = adxResult.plusDI > adxResult.minusDI ? "bullish" : "bearish"
                } else if adxResult.adx > 25 {
                    strength = "Strong"
                    signal = adxResult.plusDI > adxResult.minusDI ? "bullish" : "bearish"
                } else if adxResult.adx > 20 {
                    strength = "Developing"
                    signal = "neutral"
                } else {
                    strength = "Weak/Range"
                    signal = "neutral"
                }
                drivers.append(PredictionDriver(
                    name: "ADX Trend",
                    value: "\(String(format: "%.0f", adxResult.adx)) - \(strength)",
                    signal: signal,
                    weight: 0.55
                ))
            }
            
            // MA Alignment (research-backed: 10 > 20 > 50 = bullish structure)
            if sparkline.count >= 50 {
                if let ma = TechnicalsEngine.maAlignment(closes: sparkline) {
                    maAlignment = ma.order
                    let signal: String
                    let description: String
                    if ma.order == "bullish_perfect" {
                        signal = "bullish"
                        description = "Perfect bullish"
                    } else if ma.order == "bullish_partial" {
                        signal = "bullish"
                        description = "Bullish trend"
                    } else if ma.order == "bearish_perfect" {
                        signal = "bearish"
                        description = "Perfect bearish"
                    } else if ma.order == "bearish_partial" {
                        signal = "bearish"
                        description = "Bearish trend"
                    } else {
                        signal = "neutral"
                        description = "Mixed/Transitioning"
                    }
                    
                    // Add inclining info
                    let inclineText = ma.allInclining ? " (inclining)" : ""
                    drivers.append(PredictionDriver(
                        name: "MA Structure",
                        value: "\(description)\(inclineText)",
                        signal: signal,
                        weight: 0.6
                    ))
                }
            }
            
            // Bollinger Bands position
            if let bb = TechnicalsEngine.bollingerBands(sparkline), let lastPrice = sparkline.last {
                let position: String
                let signal: String
                
                // Calculate %B (position within bands)
                let percentB = (lastPrice - bb.lower) / (bb.upper - bb.lower) * 100
                
                if lastPrice > bb.upper {
                    position = "Above upper (\(String(format: "%.0f", percentB))%B)"
                    signal = "bearish"
                } else if lastPrice < bb.lower {
                    position = "Below lower (\(String(format: "%.0f", percentB))%B)"
                    signal = "bullish"
                } else if percentB > 80 {
                    position = "Near upper (\(String(format: "%.0f", percentB))%B)"
                    signal = "neutral"
                } else if percentB < 20 {
                    position = "Near lower (\(String(format: "%.0f", percentB))%B)"
                    signal = "neutral"
                } else {
                    position = "Mid-band (\(String(format: "%.0f", percentB))%B)"
                    signal = "neutral"
                }
                bollingerPosition = position
                drivers.append(PredictionDriver(
                    name: "Bollinger Bands",
                    value: position,
                    signal: signal,
                    weight: 0.45
                ))
            }
            
            // Support & Resistance levels from recent price action
            if sparkline.count >= 20 {
                let recentData = Array(sparkline.suffix(20))
                if let high = recentData.max(), let low = recentData.min() {
                    resistanceLevel = high
                    supportLevel = low
                    
                    // Check if price is near support or resistance
                    if let current = sparkline.last {
                        let distToResistance = (high - current) / current * 100
                        let distToSupport = (current - low) / current * 100
                        
                        if distToResistance < 2 {
                            drivers.append(PredictionDriver(
                                name: "Near Resistance",
                                value: String(format: "$%.2f (%.1f%% away)", high, distToResistance),
                                signal: "bearish",
                                weight: 0.5
                            ))
                        } else if distToSupport < 2 {
                            drivers.append(PredictionDriver(
                                name: "Near Support",
                                value: String(format: "$%.2f (%.1f%% away)", low, distToSupport),
                                signal: "bullish",
                                weight: 0.5
                            ))
                        }
                    }
                }
            }
            
            // Range Tightness (research-backed: tightening range often precedes breakout)
            if let rangeResult = TechnicalsEngine.rangeTightness(closes: sparkline, period: 10) {
                rangeTightness = rangeResult.ratio
                if rangeResult.tightening {
                    drivers.append(PredictionDriver(
                        name: "Consolidation",
                        value: "Range tightening (\(String(format: "%.0f", rangeResult.ratio * 100))%)",
                        signal: "neutral",
                        weight: 0.4
                    ))
                }
            }
        }
        
        // Fear & Greed Index (research-backed contrarian indicator)
        let fgVM = ExtendedFearGreedViewModel.shared
        var fearGreedIndex: Int? = nil
        var fearGreedClassification: String? = nil
        
        if let currentValue = fgVM.currentValue {
            fearGreedIndex = currentValue
            fearGreedClassification = fgVM.data.first?.valueClassification
            
            // Contrarian interpretation
            let signal: String
            let interpretation: String
            if currentValue < 20 {
                signal = "bullish"
                interpretation = "Extreme Fear (contrarian buy)"
            } else if currentValue < 35 {
                signal = "bullish"
                interpretation = "Fear (potential opportunity)"
            } else if currentValue > 80 {
                signal = "bearish"
                interpretation = "Extreme Greed (contrarian sell)"
            } else if currentValue > 65 {
                signal = "bearish"
                interpretation = "Greed (caution advised)"
            } else {
                signal = "neutral"
                interpretation = "Neutral"
            }
            drivers.append(PredictionDriver(
                name: "Fear & Greed",
                value: "\(currentValue) - \(interpretation)",
                signal: signal,
                weight: 0.55
            ))
        }
        
        // BTC Dominance - important for altcoin predictions
        // Rising BTC dominance = bearish for altcoins (flight to safety)
        // Falling BTC dominance = bullish for altcoins (risk-on)
        let btcDominanceValue = marketVM.btcDominance
        if let btcDom = btcDominanceValue, btcDom > 0 {
            let isAltcoin = sym != "BTC"
            
            if isAltcoin {
                let signal: String
                let interpretation: String
                
                if btcDom > 55 {
                    signal = "bearish"
                    interpretation = "High BTC dominance (\(String(format: "%.1f", btcDom))%) - altcoins struggling"
                } else if btcDom > 50 {
                    signal = "neutral"
                    interpretation = "Moderate BTC dominance (\(String(format: "%.1f", btcDom))%)"
                } else if btcDom > 45 {
                    signal = "bullish"
                    interpretation = "Lower BTC dominance (\(String(format: "%.1f", btcDom))%) - altseason potential"
                } else {
                    signal = "bullish"
                    interpretation = "Low BTC dominance (\(String(format: "%.1f", btcDom))%) - altseason mode"
                }
                
                drivers.append(PredictionDriver(
                    name: "BTC Dominance",
                    value: interpretation,
                    signal: signal,
                    weight: 0.45
                ))
            } else {
                // For BTC itself, high dominance = strength
                let signal = btcDom > 50 ? "bullish" : "neutral"
                drivers.append(PredictionDriver(
                    name: "BTC Dominance",
                    value: "\(String(format: "%.1f", btcDom))% market share",
                    signal: signal,
                    weight: 0.3
                ))
            }
        }
        
        // Volume analysis with trend detection
        if volume24h > 0 && marketCap > 0 {
            let volumeToMcap = (volume24h / marketCap) * 100
            let signal: String
            let interpretation: String
            
            if volumeToMcap > 25 {
                signal = "bullish"
                interpretation = "Very high activity"
                volumeTrend = "very_high"
            } else if volumeToMcap > 15 {
                signal = "bullish"
                interpretation = "High activity"
                volumeTrend = "high"
            } else if volumeToMcap > 8 {
                signal = "bullish"
                interpretation = "Above average"
                volumeTrend = "above_avg"
            } else if volumeToMcap > 3 {
                signal = "neutral"
                interpretation = "Normal activity"
                volumeTrend = "normal"
            } else if volumeToMcap > 0.5 {
                signal = "neutral"
                interpretation = "Below average"
                volumeTrend = "below_avg"
            } else {
                signal = "bearish"
                interpretation = "Low activity"
                volumeTrend = "low"
            }
            drivers.append(PredictionDriver(
                name: "Volume Profile",
                value: "\(String(format: "%.1f", volumeToMcap))% - \(interpretation)",
                signal: signal,
                weight: 0.4
            ))
        } else {
            // Volume data not available - add neutral driver
            drivers.append(PredictionDriver(
                name: "Volume Profile",
                value: "Data unavailable",
                signal: "neutral",
                weight: 0.2
            ))
        }
        
        // MARK: - Smart Money / Whale Data Integration
        // Fetch whale tracking data for institutional/smart money signals
        var smartMoneyIndex: Int? = nil
        var smartMoneyTrend: String? = nil
        var exchangeNetFlow: Double? = nil
        var exchangeFlowSentiment: String? = nil
        var recentWhaleActivity: String? = nil
        
        let whaleService = WhaleTrackingService.shared
        
        // Smart Money Index - aggregated sentiment from tracked smart money wallets
        if let smi = whaleService.smartMoneyIndex {
            smartMoneyIndex = smi.score
            smartMoneyTrend = smi.trend.rawValue
            
            let signal: String
            let interpretation: String
            if smi.score >= 70 {
                signal = "bullish"
                interpretation = "Strong accumulation"
            } else if smi.score >= 55 {
                signal = "bullish"
                interpretation = "Accumulating"
            } else if smi.score <= 30 {
                signal = "bearish"
                interpretation = "Strong distribution"
            } else if smi.score <= 45 {
                signal = "bearish"
                interpretation = "Distributing"
            } else {
                signal = "neutral"
                interpretation = "Mixed signals"
            }
            
            drivers.append(PredictionDriver(
                name: "Smart Money",
                value: "\(smi.score)/100 - \(interpretation)",
                signal: signal,
                weight: 0.75  // High weight - this is real alpha from institutional flow
            ))
            
            #if DEBUG
            print("[AIPrediction] Smart Money Index: \(smi.score) (\(smi.trend.rawValue)) - \(smi.bullishSignals) bullish, \(smi.bearishSignals) bearish signals")
            #endif
        }
        
        // Exchange Flow Analysis - net inflow/outflow from exchanges
        if let stats = whaleService.statistics {
            exchangeNetFlow = stats.netExchangeFlow
            exchangeFlowSentiment = stats.flowSentiment
            
            let netFlow = stats.netExchangeFlow
            let signal: String
            let interpretation: String
            
            // Outflow from exchanges (negative netFlow) = bullish (accumulation)
            // Inflow to exchanges (positive netFlow) = bearish (preparing to sell)
            if netFlow < -1_000_000 {
                signal = "bullish"
                interpretation = "Heavy outflow ($\(formatLargeNumber(abs(netFlow))))"
            } else if netFlow < -100_000 {
                signal = "bullish"
                interpretation = "Net outflow ($\(formatLargeNumber(abs(netFlow))))"
            } else if netFlow > 1_000_000 {
                signal = "bearish"
                interpretation = "Heavy inflow ($\(formatLargeNumber(netFlow)))"
            } else if netFlow > 100_000 {
                signal = "bearish"
                interpretation = "Net inflow ($\(formatLargeNumber(netFlow)))"
            } else {
                signal = "neutral"
                interpretation = "Balanced flow"
            }
            
            drivers.append(PredictionDriver(
                name: "Exchange Flow",
                value: interpretation,
                signal: signal,
                weight: 0.65  // Important signal - large moves often precede price action
            ))
            
            #if DEBUG
            print("[AIPrediction] Exchange Flow: $\(String(format: "%.0f", netFlow)) (\(stats.flowSentiment))")
            #endif
        }
        
        // Summarize recent whale activity
        let recentTxCount = whaleService.recentTransactions.filter { 
            Date().timeIntervalSince($0.timestamp) < 3600 // Last hour
        }.count
        if recentTxCount > 0 {
            let largestRecent = whaleService.recentTransactions
                .filter { Date().timeIntervalSince($0.timestamp) < 3600 }
                .max(by: { $0.amountUSD < $1.amountUSD })
            
            if let largest = largestRecent {
                recentWhaleActivity = "\(recentTxCount) moves in 1h, largest: $\(formatLargeNumber(largest.amountUSD)) \(largest.symbol)"
                
                // If there's significant whale activity for this specific coin
                let coinWhaleActivity = whaleService.recentTransactions.filter {
                    $0.symbol.uppercased() == sym && Date().timeIntervalSince($0.timestamp) < 86400
                }
                if !coinWhaleActivity.isEmpty {
                    let totalVolume = coinWhaleActivity.reduce(0.0) { $0 + $1.amountUSD }
                    let depositsCount = coinWhaleActivity.filter { $0.transactionType == .exchangeDeposit }.count
                    let withdrawalsCount = coinWhaleActivity.filter { $0.transactionType == .exchangeWithdrawal }.count
                    
                    let whaleSignal: String
                    if withdrawalsCount > depositsCount * 2 {
                        whaleSignal = "bullish"
                    } else if depositsCount > withdrawalsCount * 2 {
                        whaleSignal = "bearish"
                    } else {
                        whaleSignal = "neutral"
                    }
                    
                    drivers.append(PredictionDriver(
                        name: "\(sym) Whale Activity",
                        value: "\(coinWhaleActivity.count) moves ($\(formatLargeNumber(totalVolume))), \(withdrawalsCount) withdrawals, \(depositsCount) deposits",
                        signal: whaleSignal,
                        weight: 0.7  // Very relevant - specific to this coin
                    ))
                }
            }
        }
        
        // MARK: - Market Regime Detection
        // Detect current market regime (trending/ranging/volatile) to adjust indicator interpretation
        var marketRegime: MarketRegime? = nil
        var regimeConfidence: Double? = nil
        
        if fullSparkline.count >= 20 {
            let regimeResult = MarketRegimeDetector.detectRegime(closes: fullSparkline, currentPrice: currentPrice)
            marketRegime = regimeResult.regime
            regimeConfidence = regimeResult.confidence
            
            // Add regime as a driver for context
            let regimeSignal: String
            switch regimeResult.regime {
            case .trendingUp:
                regimeSignal = "bullish"
            case .trendingDown:
                regimeSignal = "bearish"
            case .breakoutPotential:
                regimeSignal = "neutral"  // Direction uncertain
            default:
                regimeSignal = "neutral"
            }
            
            drivers.append(PredictionDriver(
                name: "Market Regime",
                value: "\(regimeResult.regime.displayName) (\(Int(regimeResult.confidence))% conf)",
                signal: regimeSignal,
                weight: 0.5  // Contextual - affects interpretation of other indicators
            ))
            
            #if DEBUG
            print("[AIPrediction] Market Regime: \(regimeResult.summary)")
            #endif
        }
        
        // MARK: - Multi-Timeframe Confluence
        // Check if higher timeframes agree with short-term analysis
        var confluence: MultiTimeframeConfluence? = nil
        
        if fullSparkline.count >= 50 {
            confluence = checkMultiTimeframeConfluence(sparkline: fullSparkline, targetTimeframe: timeframe)
            
            if let conf = confluence {
                let confSignal = conf.higherTimeframeTrend == "bullish" ? "bullish" :
                                 conf.higherTimeframeTrend == "bearish" ? "bearish" : "neutral"
                
                if conf.agrees {
                    // Confluence exists - add as positive driver
                    drivers.append(PredictionDriver(
                        name: "Timeframe Confluence",
                        value: conf.summary,
                        signal: confSignal,
                        weight: 0.65  // Important - multiple timeframes agreeing increases confidence
                    ))
                } else {
                    // Divergence - add as cautionary driver
                    drivers.append(PredictionDriver(
                        name: "TF Divergence",
                        value: conf.summary,
                        signal: "neutral",  // Divergence = caution
                        weight: 0.55
                    ))
                }
                
                #if DEBUG
                print("[AIPrediction] Multi-TF Confluence: \(conf.details)")
                #endif
            }
        }
        
        // MARK: - Derivatives Market Data (Funding Rate + Open Interest + Trader Positioning)
        // Fetch from Binance Futures for major coins
        var fundingRateValue: Double? = nil
        var fundingRateSentiment: String? = nil
        var openInterestValue: Double? = nil
        var openInterestFormatted: String? = nil
        var longShortRatioValue: Double? = nil
        var longShortSentiment: String? = nil
        var topTraderRatioValue: Double? = nil
        var topTraderSignal: String? = nil
        var takerBuySellRatioValue: Double? = nil
        var takerSignal: String? = nil
        
        // Map common crypto symbols to Binance Futures perpetual symbols
        let futuresSymbolMap: [String: String] = [
            "BTC": "BTCUSDT", "ETH": "ETHUSDT", "SOL": "SOLUSDT", "BNB": "BNBUSDT",
            "XRP": "XRPUSDT", "DOGE": "DOGEUSDT", "ADA": "ADAUSDT", "AVAX": "AVAXUSDT",
            "LINK": "LINKUSDT", "DOT": "DOTUSDT", "MATIC": "MATICUSDT", "SHIB": "SHIBUSDT",
            "LTC": "LTCUSDT", "TRX": "TRXUSDT", "ATOM": "ATOMUSDT", "UNI": "UNIUSDT",
            "ETC": "ETCUSDT", "XLM": "XLMUSDT", "NEAR": "NEARUSDT", "APT": "APTUSDT",
            "OP": "OPUSDT", "ARB": "ARBUSDT", "INJ": "INJUSDT", "SUI": "SUIUSDT",
            "FIL": "FILUSDT", "AAVE": "AAVEUSDT", "MKR": "MKRUSDT", "PEPE": "PEPEUSDT"
        ]
        
        // Fetch futures data in PARALLEL with a 10-second timeout for each
        // This prevents the sequential calls from blocking the prediction
        if let futuresSymbol = futuresSymbolMap[sym] {
            let futuresService = FuturesTradingExecutionService.shared
            let futuresTimeout: UInt64 = 10_000_000_000 // 10 seconds
            
            #if DEBUG
            print("[AIPrediction] Fetching futures data for \(futuresSymbol) in parallel...")
            #endif
            
            // Use TaskGroup to run all futures API calls in parallel, collecting drivers
            let collectedDrivers = await withTaskGroup(of: PredictionDriver?.self) { group -> [PredictionDriver] in
                // Funding Rate
                group.addTask {
                    do {
                        let fundingData = try await withThrowingTaskGroup(of: FundingRate.self) { innerGroup in
                            innerGroup.addTask { try await futuresService.fetchFundingRate(symbol: futuresSymbol) }
                            innerGroup.addTask {
                                try await Task.sleep(nanoseconds: futuresTimeout)
                                throw CancellationError()
                            }
                            guard let result = try await innerGroup.next() else { throw CancellationError() }
                            innerGroup.cancelAll()
                            return result
                        }
                        
                        fundingRateValue = fundingData.fundingRate
                        let fundingPct = fundingData.fundingRate * 100
                        let driver: PredictionDriver
                        if fundingPct > 0.05 {
                            fundingRateSentiment = "very_bullish_crowd"
                            driver = PredictionDriver(name: "Funding Rate", value: "\(fundingData.formattedRate) - Crowded longs (contrarian bearish)", signal: "bearish", weight: 0.55)
                        } else if fundingPct > 0.01 {
                            fundingRateSentiment = "bullish_crowd"
                            driver = PredictionDriver(name: "Funding Rate", value: "\(fundingData.formattedRate) - Longs paying shorts", signal: "neutral", weight: 0.4)
                        } else if fundingPct < -0.05 {
                            fundingRateSentiment = "very_bearish_crowd"
                            driver = PredictionDriver(name: "Funding Rate", value: "\(fundingData.formattedRate) - Crowded shorts (contrarian bullish)", signal: "bullish", weight: 0.55)
                        } else if fundingPct < -0.01 {
                            fundingRateSentiment = "bearish_crowd"
                            driver = PredictionDriver(name: "Funding Rate", value: "\(fundingData.formattedRate) - Shorts paying longs", signal: "neutral", weight: 0.4)
                        } else {
                            fundingRateSentiment = "neutral"
                            driver = PredictionDriver(name: "Funding Rate", value: "\(fundingData.formattedRate) - Balanced", signal: "neutral", weight: 0.3)
                        }
                        #if DEBUG
                        print("[AIPrediction] Funding Rate: \(fundingData.formattedRate)")
                        #endif
                        return driver
                    } catch {
                        #if DEBUG
                        print("[AIPrediction] Funding rate skipped: \(error.localizedDescription)")
                        #endif
                        return nil
                    }
                }
                
                // Open Interest
                group.addTask {
                    do {
                        let oiData = try await withThrowingTaskGroup(of: OpenInterestData.self) { innerGroup in
                            innerGroup.addTask { try await futuresService.fetchOpenInterest(symbol: futuresSymbol) }
                            innerGroup.addTask {
                                try await Task.sleep(nanoseconds: futuresTimeout)
                                throw CancellationError()
                            }
                            guard let result = try await innerGroup.next() else { throw CancellationError() }
                            innerGroup.cancelAll()
                            return result
                        }
                        openInterestValue = oiData.openInterestValue
                        openInterestFormatted = oiData.formattedValue
                        #if DEBUG
                        print("[AIPrediction] Open Interest: \(oiData.formattedValue)")
                        #endif
                        return PredictionDriver(name: "Open Interest", value: oiData.formattedValue, signal: "neutral", weight: 0.25)
                    } catch {
                        #if DEBUG
                        print("[AIPrediction] Open interest skipped: \(error.localizedDescription)")
                        #endif
                        return nil
                    }
                }
                
                // Long/Short Ratio
                group.addTask {
                    do {
                        let lsData = try await withThrowingTaskGroup(of: LongShortRatioData.self) { innerGroup in
                            innerGroup.addTask { try await futuresService.fetchLongShortRatio(symbol: futuresSymbol) }
                            innerGroup.addTask {
                                try await Task.sleep(nanoseconds: futuresTimeout)
                                throw CancellationError()
                            }
                            guard let result = try await innerGroup.next() else { throw CancellationError() }
                            innerGroup.cancelAll()
                            return result
                        }
                        longShortRatioValue = lsData.longShortRatio
                        longShortSentiment = lsData.sentiment
                        let signalType: String
                        let driverValue: String
                        switch lsData.sentiment {
                        case "extreme_long":
                            signalType = "bearish"
                            driverValue = "L/S Ratio: \(lsData.formattedRatio) - EXTREME crowded longs"
                        case "extreme_short":
                            signalType = "bullish"
                            driverValue = "L/S Ratio: \(lsData.formattedRatio) - EXTREME crowded shorts"
                        case "bullish_crowd":
                            signalType = "neutral"
                            driverValue = "L/S Ratio: \(lsData.formattedRatio) - Moderately long"
                        case "bearish_crowd":
                            signalType = "neutral"
                            driverValue = "L/S Ratio: \(lsData.formattedRatio) - Moderately short"
                        default:
                            signalType = "neutral"
                            driverValue = "L/S Ratio: \(lsData.formattedRatio) - Balanced"
                        }
                        #if DEBUG
                        print("[AIPrediction] L/S Ratio: \(lsData.formattedRatio)")
                        #endif
                        return PredictionDriver(name: "Long/Short Ratio", value: driverValue, signal: signalType, weight: lsData.sentiment.contains("extreme") ? 0.6 : 0.35)
                    } catch {
                        #if DEBUG
                        print("[AIPrediction] L/S ratio skipped: \(error.localizedDescription)")
                        #endif
                        return nil
                    }
                }
                
                // Top Trader Ratio
                group.addTask {
                    do {
                        let topData = try await withThrowingTaskGroup(of: TopTraderRatioData.self) { innerGroup in
                            innerGroup.addTask { try await futuresService.fetchTopTraderRatio(symbol: futuresSymbol) }
                            innerGroup.addTask {
                                try await Task.sleep(nanoseconds: futuresTimeout)
                                throw CancellationError()
                            }
                            guard let result = try await innerGroup.next() else { throw CancellationError() }
                            innerGroup.cancelAll()
                            return result
                        }
                        topTraderRatioValue = topData.longShortRatio
                        topTraderSignal = topData.signal
                        let signalType: String
                        let driverValue: String
                        switch topData.signal {
                        case "top_traders_long":
                            signalType = "bullish"
                            driverValue = "Top Traders: \(topData.formattedRatio) - Smart money LONG"
                        case "top_traders_short":
                            signalType = "bearish"
                            driverValue = "Top Traders: \(topData.formattedRatio) - Smart money SHORT"
                        default:
                            signalType = "neutral"
                            driverValue = "Top Traders: \(topData.formattedRatio) - Neutral"
                        }
                        #if DEBUG
                        print("[AIPrediction] Top Traders: \(topData.formattedRatio)")
                        #endif
                        return PredictionDriver(name: "Top Traders", value: driverValue, signal: signalType, weight: topData.signal == "top_traders_neutral" ? 0.3 : 0.55)
                    } catch {
                        #if DEBUG
                        print("[AIPrediction] Top trader ratio skipped: \(error.localizedDescription)")
                        #endif
                        return nil
                    }
                }
                
                // Taker Buy/Sell Ratio
                group.addTask {
                    do {
                        let takerData = try await withThrowingTaskGroup(of: TakerBuySellData.self) { innerGroup in
                            innerGroup.addTask { try await futuresService.fetchTakerBuySellRatio(symbol: futuresSymbol) }
                            innerGroup.addTask {
                                try await Task.sleep(nanoseconds: futuresTimeout)
                                throw CancellationError()
                            }
                            guard let result = try await innerGroup.next() else { throw CancellationError() }
                            innerGroup.cancelAll()
                            return result
                        }
                        takerBuySellRatioValue = takerData.buySellRatio
                        takerSignal = takerData.signal
                        let signalType: String
                        let driverValue: String
                        switch takerData.signal {
                        case "aggressive_buying":
                            signalType = "bullish"
                            driverValue = "Taker Flow: \(takerData.formattedRatio) - Aggressive BUYING"
                        case "aggressive_selling":
                            signalType = "bearish"
                            driverValue = "Taker Flow: \(takerData.formattedRatio) - Aggressive SELLING"
                        default:
                            signalType = "neutral"
                            driverValue = "Taker Flow: \(takerData.formattedRatio) - Balanced"
                        }
                        #if DEBUG
                        print("[AIPrediction] Taker Flow: \(takerData.formattedRatio)")
                        #endif
                        return PredictionDriver(name: "Taker Flow", value: driverValue, signal: signalType, weight: takerData.signal == "balanced_flow" ? 0.25 : 0.5)
                    } catch {
                        #if DEBUG
                        print("[AIPrediction] Taker ratio skipped: \(error.localizedDescription)")
                        #endif
                        return nil
                    }
                }
                
                // Collect all non-nil drivers
                var results: [PredictionDriver] = []
                for await driver in group {
                    if let d = driver {
                        results.append(d)
                    }
                }
                return results
            }
            
            // Add collected futures drivers to main drivers array (thread-safe now)
            drivers.append(contentsOf: collectedDrivers)
            #if DEBUG
            print("[AIPrediction] Futures data collection completed with \(collectedDrivers.count) drivers")
            #endif
        }
        
        // Ensure we have at least basic drivers (fallback when primary analysis fails)
        if drivers.isEmpty {
            // Add basic price action driver based on available data
            if change24h != 0 {
                let priceSignal = change24h > 0 ? "bullish" : "bearish"
                let trendDescription = change24h > 0 ? "Upward momentum" : "Downward momentum"
                drivers.append(PredictionDriver(
                    name: "Price Action",
                    value: trendDescription,
                    signal: priceSignal,
                    weight: 0.5
                ))
            }
            
            // Add market data availability driver
            drivers.append(PredictionDriver(
                name: "Market Analysis",
                value: currentPrice > 0 ? "Active" : "Limited data",
                signal: "neutral",
                weight: 0.3
            ))
            
            #if DEBUG
            print("[AIPrediction] Added fallback drivers, total: \(drivers.count)")
            #endif
        }
        
        return MarketDataSnapshot(
            currentPrice: currentPrice,
            change24h: change24h,
            change7d: change7d,
            volume24h: volume24h,
            marketCap: marketCap,
            rsi: rsi,
            stochRSI: stochRSI,
            macdSignal: macdSignal,
            maAlignment: maAlignment,
            adx: adx,
            bollingerPosition: bollingerPosition,
            supportLevel: supportLevel,
            resistanceLevel: resistanceLevel,
            volumeTrend: volumeTrend,
            rangeTightness: rangeTightness,
            fearGreedIndex: fearGreedIndex,
            fearGreedClassification: fearGreedClassification,
            smartMoneyIndex: smartMoneyIndex,
            smartMoneyTrend: smartMoneyTrend,
            exchangeNetFlow: exchangeNetFlow,
            exchangeFlowSentiment: exchangeFlowSentiment,
            recentWhaleActivity: recentWhaleActivity,
            marketRegime: marketRegime,
            regimeConfidence: regimeConfidence,
            multiTimeframeConfluence: confluence,
            fundingRate: fundingRateValue,
            fundingRateSentiment: fundingRateSentiment,
            openInterest: openInterestValue,
            openInterestFormatted: openInterestFormatted,
            longShortRatio: longShortRatioValue,
            longShortSentiment: longShortSentiment,
            topTraderRatio: topTraderRatioValue,
            topTraderSignal: topTraderSignal,
            takerBuySellRatio: takerBuySellRatioValue,
            takerSignal: takerSignal,
            btcDominance: btcDominanceValue,
            drivers: drivers
        )
    }
    
    // MARK: - Prompt Building
    
    private func buildSystemPrompt() -> String {
        return """
        You are an expert cryptocurrency quantitative analyst with deep knowledge of technical analysis, market psychology, and price action.
        
        RESEARCH-BACKED ANALYSIS METHODOLOGY:
        
        1. TREND ANALYSIS (Weight: 30%)
           - MA Structure: Bullish when 10 > 20 > 50 SMA, all inclining
           - ADX > 25 indicates strong trend, > 40 very strong
           - MACD crossovers with expanding histogram confirm momentum
        
        2. MOMENTUM OSCILLATORS (Weight: 25%)
           - RSI: <30 oversold (bullish), >70 overbought (bearish)
           - Stochastic RSI: More sensitive, good for timing
           - Look for bullish/bearish divergences
        
        3. VOLATILITY & BANDS (Weight: 15%)
           - Bollinger Band position (%B): <20 near support, >80 near resistance
           - Range tightening often precedes breakouts
           - ATR for volatility assessment
        
        4. MARKET SENTIMENT (Weight: 15%)
           - Fear & Greed Index: CONTRARIAN indicator
           - Extreme Fear (<25) = potential buying opportunity
           - Extreme Greed (>75) = potential selling signal
           - Volume confirms moves - high volume validates trends
        
        5. SMART MONEY / WHALE ACTIVITY (Weight: 15%) - IMPORTANT ALPHA SOURCE
           - Smart Money Index: Aggregated institutional/whale sentiment (0-100)
           - Exchange Flow: Net inflow = bearish (preparing to sell), net outflow = bullish (accumulation)
           - Whale Activity: Large transactions by known smart money wallets
           - These signals often PRECEDE price moves - treat with high weight
           - If smart money is accumulating while retail panics = strong bullish signal
           - If smart money is distributing while retail is greedy = strong bearish signal
        
        6. MARKET REGIME CONTEXT (Weight: 10%)
           - Trending: Follow trend indicators, trails stops, RSI can stay overbought/oversold
           - Ranging: Use oscillators, mean reversion strategies, trade bounces
           - High Volatility: Reduce confidence, widen price ranges, expect larger moves
           - Low Volatility / Breakout Setup: Watch for volume expansion, potential big move
           - Adjust indicator interpretation based on current regime
        
        7. MULTI-TIMEFRAME CONFLUENCE (Weight: 10%)
           - Higher timeframe agreement increases prediction confidence
           - If short-term and long-term trends align = stronger signal
           - Divergence between timeframes = caution, lower confidence
           - Always respect the higher timeframe trend
        
        8. SUPPORT/RESISTANCE (Weight: 5%)
           - Price near support = potential bounce
           - Price near resistance = potential rejection
           - Breakouts need volume confirmation
        
        9. DERIVATIVES DATA (Weight: 10%) - CONTRARIAN INDICATOR
           - Funding Rate: Shows crowd positioning in perpetual futures
             * High positive (>0.01%) = crowded long, potential correction
             * High negative (<-0.01%) = crowded short, potential squeeze
             * Extreme funding (>0.05% or <-0.05%) = STRONG contrarian signal
           - Open Interest: Total value of futures positions
             * Rising OI + rising price = strong uptrend (positions adding to winners)
             * Rising OI + falling price = distribution (smart money selling to retail)
             * Falling OI = positions closing, trend may be weakening
           - Use as CONFIRMATION or CONTRARIAN signal depending on context
        
        10. TRADER POSITIONING (Weight: 12%) - CROWD VS SMART MONEY
           - Global Long/Short Ratio: CONTRARIAN indicator (fade the crowd)
             * Ratio > 2.0 = EXTREME longs, high correction risk
             * Ratio < 0.5 = EXTREME shorts, high squeeze risk
             * Use extreme readings as STRONG contrarian signals
           - Top Trader Ratio: FOLLOW indicator (smart money)
             * Top traders long (>1.5) = bullish signal, follow smart money
             * Top traders short (<0.67) = bearish signal, follow smart money
             * Top traders are professional traders with larger accounts
           - Taker Buy/Sell Volume: MOMENTUM indicator
             * Ratio > 1.2 = aggressive buying, bulls in control
             * Ratio < 0.8 = aggressive selling, bears in control
             * Shows real-time order flow aggression
           - KEY INSIGHT: When crowd is extreme but top traders are opposite,
             this is a VERY STRONG contrarian signal (retail vs smart money divergence)
        
        CONFIDENCE SCORING RULES:
        - 75-100: 4+ indicators agree, clear trend, aligned sentiment
        - 55-74: 3 indicators agree, moderate trend clarity
        - 40-54: Mixed signals, range-bound market likely
        - 0-39: Conflicting indicators, high uncertainty
        
        TIMEFRAME CONSIDERATIONS:
        - 1H: Ultra-short term scalping. Focus on RSI, Stoch RSI, immediate momentum. Very low confidence typical.
        - 4H: Short-term swing. Focus on MACD, RSI, recent price action. Moderate confidence possible.
        - 24H: Day trading timeframe. Focus on momentum, short-term oversold/overbought
        - 7D: Swing trading. Balance trend + momentum, medium confidence
        - 30D: Position trading. Emphasize trend structure + sentiment cycles
        
        SHORT-TERM (1H/4H) SPECIAL RULES:
        - Confidence rarely exceeds 60% due to noise
        - Focus heavily on momentum oscillators (RSI, Stoch RSI)
        - Volume spikes are crucial signals
        - Fear/Greed less relevant, price action is king
        - Smaller expected moves (typically 0.5-3% for 1H, 1-5% for 4H)
        
        CRITICAL PREDICTION RULES:
        - NEVER predict exactly 0.00% change - markets always have SOME movement
        - Even in consolidation/neutral conditions, predict small moves: +0.2%, -0.3%, +0.5%, etc.
        - Use the timeframe to scale predictions: 1H might be +0.1%, while 30D might be +2.5%
        - Each timeframe should produce DIFFERENT predictions based on the relevant data window
        - Short timeframes (1H, 4H) should show more volatility awareness
        - Long timeframes (7D, 30D) should show trend bias
        
        DIRECTIONAL COMMITMENT (CRITICAL - DO NOT DEFAULT TO NEUTRAL):
        - "neutral" should be used SPARINGLY — only when signals are genuinely 50/50 with no lean
        - If there is ANY discernible bias from indicators, make a directional call (bullish or bearish)
        - Even a slight bullish or bearish lean should result in "bullish" or "bearish", not "neutral"
        - Crypto markets are volatile — pure sideways action is RARE. Most timeframes have a directional bias.
        - Using "neutral" as a safe default is LAZY analysis. Take a stance based on the data.
        - If RSI, MACD, trend, sentiment, or volume give ANY directional signal, commit to that direction
        - Lower your confidence if uncertain, but still make a directional call
        - Maximum 20% of predictions should be neutral in a typical market environment
        
        ANALYSIS TEXT CONSISTENCY (CRITICAL):
        - Your "analysis" text MUST match your "direction" prediction
        - If direction is "bullish", analysis should explain WHY it's bullish (e.g., "upward momentum", "buying opportunity", "bullish setup")
        - If direction is "bearish", analysis should explain WHY it's bearish (e.g., "downward pressure", "selling pressure", "bearish setup")
        - If direction is "neutral", analysis should explain the mixed signals or consolidation
        - NEVER write "neutral bias" in analysis if direction is "bullish" or "bearish"
        - NEVER contradict yourself - direction and analysis MUST tell the same story
        
        RESPONSE FORMAT (respond ONLY with this JSON, no markdown):
        {
            "direction": "bullish" | "bearish" | "neutral",
            "confidence": 0-100,
            "predictedPriceChange": number (percentage, can be negative, NEVER exactly 0.00),
            "priceRangeLow": number (percentage change for low estimate),
            "priceRangeHigh": number (percentage change for high estimate),
            "analysis": "2-3 sentence analysis that MATCHES your direction - explain the bullish/bearish/neutral outlook consistently",
            "probabilityUp2Pct": number (0-100, probability of +2% or more),
            "probabilityUp5Pct": number (0-100, probability of +5% or more),
            "probabilityUp10Pct": number (0-100, probability of +10% or more),
            "probabilityDown2Pct": number (0-100, probability of -2% or more),
            "probabilityDown5Pct": number (0-100, probability of -5% or more),
            "probabilityDown10Pct": number (0-100, probability of -10% or more),
            "directionalScore": number (-100 to +100, overall directional bias)
        }
        
        PROBABILITY ESTIMATION GUIDELINES:
        - Base probabilities on historical volatility and current market conditions
        - Probabilities should be logically consistent (e.g., probabilityUp5Pct < probabilityUp2Pct)
        - For short timeframes (1H, 4H): larger moves less likely
        - For longer timeframes (7D, 30D): larger moves more probable
        - Directional score should reflect net bullish/bearish bias: +50 to +100 = strongly bullish, +10 to +50 = mildly bullish, -10 to +10 = neutral, -50 to -10 = mildly bearish, -100 to -50 = strongly bearish
        - These probabilities help users understand the RANGE of possible outcomes, not just a single prediction
        
        EXPECTED MOVE RANGES BY TIMEFRAME (Min to Max):
        - 1H: ±0.1% to ±3% (typical: ±0.5%), confidence rarely >50%
        - 4H: ±0.2% to ±5% (typical: ±1%), confidence rarely >60%
        - 24H: ±0.5% to ±15% (typical: ±2%)
        - 7D: ±1% to ±30% (typical: ±5%)
        - 30D: ±2% to ±50% (typical: ±10%)
        
        IMPORTANT: Always predict within these ranges. Never predict exactly 0%.
        Even in sideways markets, expect small oscillations.
        """
    }
    
    private func buildPredictionPrompt(
        symbol: String,
        coinName: String,
        timeframe: PredictionTimeframe,
        marketData: MarketDataSnapshot
    ) -> String {
        var prompt = """
        Generate a price prediction for \(coinName) (\(symbol)) over the next \(timeframe.fullName).
        
        ═══════════════════════════════════════════════════════════════
        MARKET DATA
        ═══════════════════════════════════════════════════════════════
        Current Price: $\(formatPrice(marketData.currentPrice))
        24H Change: \(String(format: "%+.2f", marketData.change24h))%
        7D Change: \(String(format: "%+.2f", marketData.change7d))%
        24H Volume: $\(formatLargeNumber(marketData.volume24h))
        Market Cap: $\(formatLargeNumber(marketData.marketCap))
        
        ═══════════════════════════════════════════════════════════════
        TREND INDICATORS
        ═══════════════════════════════════════════════════════════════
        """
        
        if let ma = marketData.maAlignment {
            prompt += "\nMA Structure: \(ma.replacingOccurrences(of: "_", with: " ").capitalized)"
        }
        
        if let adx = marketData.adx {
            let strength = adx > 40 ? "Very Strong Trend" : (adx > 25 ? "Strong Trend" : (adx > 20 ? "Developing" : "Weak/Ranging"))
            prompt += "\nADX(14): \(String(format: "%.1f", adx)) - \(strength)"
        }
        
        if let macd = marketData.macdSignal {
            prompt += "\nMACD: \(macd.capitalized) signal"
        }
        
        prompt += """
        
        
        ═══════════════════════════════════════════════════════════════
        MOMENTUM OSCILLATORS
        ═══════════════════════════════════════════════════════════════
        """
        
        if let rsi = marketData.rsi {
            let zone = rsi < 30 ? "OVERSOLD" : (rsi > 70 ? "OVERBOUGHT" : "NEUTRAL")
            prompt += "\nRSI(14): \(String(format: "%.1f", rsi)) [\(zone)]"
        }
        
        if let stoch = marketData.stochRSI {
            let signal = stoch.k < 20 ? "Oversold" : (stoch.k > 80 ? "Overbought" : (stoch.k > stoch.d ? "Bullish Cross" : "Bearish Cross"))
            prompt += "\nStoch RSI: K=\(String(format: "%.0f", stoch.k)), D=\(String(format: "%.0f", stoch.d)) - \(signal)"
        }
        
        prompt += """
        
        
        ═══════════════════════════════════════════════════════════════
        VOLATILITY & PRICE STRUCTURE
        ═══════════════════════════════════════════════════════════════
        """
        
        if let bb = marketData.bollingerPosition {
            prompt += "\nBollinger Bands: \(bb)"
        }
        
        if let support = marketData.supportLevel, let resistance = marketData.resistanceLevel {
            prompt += "\n20-Period Range: Support $\(formatPrice(support)) | Resistance $\(formatPrice(resistance))"
            let rangePercent = (resistance - support) / marketData.currentPrice * 100
            prompt += "\nRange Width: \(String(format: "%.1f", rangePercent))%"
        }
        
        if let tightness = marketData.rangeTightness, tightness < 0.7 {
            prompt += "\n⚠️ CONSOLIDATION ALERT: Range tightening (\(String(format: "%.0f", tightness * 100))% of prior range) - potential breakout setup"
        }
        
        prompt += """
        
        
        ═══════════════════════════════════════════════════════════════
        MARKET SENTIMENT (CONTRARIAN)
        ═══════════════════════════════════════════════════════════════
        """
        
        if let fg = marketData.fearGreedIndex, let fgClass = marketData.fearGreedClassification {
            let contrarian: String
            if fg < 25 {
                contrarian = "Extreme Fear often marks bottoms - contrarian bullish"
            } else if fg < 40 {
                contrarian = "Fear zone - potential buying opportunity"
            } else if fg > 75 {
                contrarian = "Extreme Greed often marks tops - contrarian bearish"
            } else if fg > 60 {
                contrarian = "Greed zone - exercise caution"
            } else {
                contrarian = "Neutral zone - follow trend"
            }
            prompt += "\nFear & Greed Index: \(fg) (\(fgClass))"
            prompt += "\nContrarian Signal: \(contrarian)"
        }
        
        if let volTrend = marketData.volumeTrend {
            let volInterpret: String
            switch volTrend {
            case "very_high": volInterpret = "Very high activity - strong conviction"
            case "high": volInterpret = "Elevated activity - increased interest"
            case "low": volInterpret = "Low activity - weak conviction, watch for reversals"
            default: volInterpret = "Normal activity"
            }
            prompt += "\nVolume Trend: \(volInterpret)"
        }
        
        // BTC Dominance context
        if let btcDom = marketData.btcDominance, btcDom > 0 {
            prompt += "\nBTC Dominance: \(String(format: "%.1f", btcDom))%"
            if symbol.uppercased() != "BTC" {
                if btcDom > 55 {
                    prompt += " (High - typically bearish for altcoins)"
                } else if btcDom < 45 {
                    prompt += " (Low - altseason conditions)"
                }
            }
        }
        
        // MARK: - Smart Money / Whale Activity Section
        prompt += """
        
        
        ═══════════════════════════════════════════════════════════════
        SMART MONEY / WHALE ACTIVITY (HIGH PRIORITY)
        ═══════════════════════════════════════════════════════════════
        """
        
        if let smi = marketData.smartMoneyIndex, let trend = marketData.smartMoneyTrend {
            let interpretation: String
            if smi >= 70 {
                interpretation = "Strong accumulation by institutions - BULLISH signal"
            } else if smi >= 55 {
                interpretation = "Smart money accumulating - bullish bias"
            } else if smi <= 30 {
                interpretation = "Strong distribution by institutions - BEARISH signal"
            } else if smi <= 45 {
                interpretation = "Smart money distributing - bearish bias"
            } else {
                interpretation = "Mixed institutional activity"
            }
            prompt += "\nSmart Money Index: \(smi)/100 (\(trend))"
            prompt += "\nInterpretation: \(interpretation)"
        } else {
            prompt += "\nSmart Money Index: Data unavailable"
        }
        
        if let netFlow = marketData.exchangeNetFlow, let sentiment = marketData.exchangeFlowSentiment {
            let flowInterpretation: String
            if netFlow < -1_000_000 {
                flowInterpretation = "Heavy outflow from exchanges - whales accumulating - BULLISH"
            } else if netFlow < -100_000 {
                flowInterpretation = "Net outflow - accumulation ongoing - bullish"
            } else if netFlow > 1_000_000 {
                flowInterpretation = "Heavy inflow to exchanges - preparing to sell - BEARISH"
            } else if netFlow > 100_000 {
                flowInterpretation = "Net inflow - potential selling pressure - bearish"
            } else {
                flowInterpretation = "Balanced flow - neutral"
            }
            prompt += "\nExchange Flow: \(sentiment)"
            prompt += "\nFlow Interpretation: \(flowInterpretation)"
        }
        
        if let activity = marketData.recentWhaleActivity {
            prompt += "\nRecent Whale Activity: \(activity)"
        }
        
        // MARK: - Derivatives Market Data Section
        prompt += """
        
        
        ═══════════════════════════════════════════════════════════════
        DERIVATIVES MARKET DATA (CONTRARIAN SIGNALS)
        ═══════════════════════════════════════════════════════════════
        """
        
        if let fundingRate = marketData.fundingRate {
            let fundingPct = fundingRate * 100
            prompt += "\nFunding Rate: \(String(format: "%+.4f%%", fundingPct))"
            
            if let sentiment = marketData.fundingRateSentiment {
                let interpretation: String
                switch sentiment {
                case "very_bullish_crowd":
                    interpretation = "⚠️ EXTREME crowded longs - HIGH risk of correction (contrarian BEARISH)"
                case "bullish_crowd":
                    interpretation = "Longs paying shorts - mildly crowded long"
                case "very_bearish_crowd":
                    interpretation = "⚠️ EXTREME crowded shorts - HIGH squeeze potential (contrarian BULLISH)"
                case "bearish_crowd":
                    interpretation = "Shorts paying longs - mildly crowded short"
                default:
                    interpretation = "Balanced - no extreme positioning"
                }
                prompt += "\nInterpretation: \(interpretation)"
            }
        } else {
            prompt += "\nFunding Rate: Not available (coin may not have perpetual futures)"
        }
        
        if let oi = marketData.openInterestFormatted {
            prompt += "\nOpen Interest: \(oi)"
            prompt += "\nNote: Rising OI + rising price = strong trend. Rising OI + falling price = distribution."
        }
        
        // MARK: - Trader Positioning Section
        prompt += """
        
        
        ═══════════════════════════════════════════════════════════════
        TRADER POSITIONING (CROWD VS SMART MONEY)
        ═══════════════════════════════════════════════════════════════
        """
        
        if let lsRatio = marketData.longShortRatio, let lsSentiment = marketData.longShortSentiment {
            prompt += "\nGlobal Long/Short Ratio: \(String(format: "%.2f", lsRatio))"
            let crowdInterpretation: String
            switch lsSentiment {
            case "extreme_long":
                crowdInterpretation = "⚠️ EXTREME crowded longs - HIGH correction risk (CONTRARIAN BEARISH)"
            case "bullish_crowd":
                crowdInterpretation = "Moderately bullish crowd positioning"
            case "extreme_short":
                crowdInterpretation = "⚠️ EXTREME crowded shorts - HIGH squeeze potential (CONTRARIAN BULLISH)"
            case "bearish_crowd":
                crowdInterpretation = "Moderately bearish crowd positioning"
            default:
                crowdInterpretation = "Balanced positioning - no extreme"
            }
            prompt += "\nCrowd Sentiment: \(crowdInterpretation)"
        } else {
            prompt += "\nGlobal Long/Short Ratio: Not available"
        }
        
        if let topRatio = marketData.topTraderRatio, let topSignal = marketData.topTraderSignal {
            prompt += "\nTop Trader Ratio: \(String(format: "%.2f", topRatio))"
            let smartMoneyInterpretation: String
            switch topSignal {
            case "top_traders_long":
                smartMoneyInterpretation = "✓ Smart money is LONG - bullish signal (follow top traders)"
            case "top_traders_short":
                smartMoneyInterpretation = "✓ Smart money is SHORT - bearish signal (follow top traders)"
            default:
                smartMoneyInterpretation = "Top traders neutral - no clear direction"
            }
            prompt += "\nSmart Money Signal: \(smartMoneyInterpretation)"
        }
        
        if let takerRatio = marketData.takerBuySellRatio, let takerSig = marketData.takerSignal {
            prompt += "\nTaker Buy/Sell Ratio: \(String(format: "%.2f", takerRatio))"
            let flowInterpretation: String
            switch takerSig {
            case "aggressive_buying":
                flowInterpretation = "Aggressive BUYING - bulls in control of order flow"
            case "aggressive_selling":
                flowInterpretation = "Aggressive SELLING - bears in control of order flow"
            default:
                flowInterpretation = "Balanced order flow"
            }
            prompt += "\nOrder Flow: \(flowInterpretation)"
        }
        
        // MARK: - Market Regime Section
        prompt += """
        
        
        ═══════════════════════════════════════════════════════════════
        MARKET REGIME CONTEXT
        ═══════════════════════════════════════════════════════════════
        """
        
        if let regime = marketData.marketRegime, let confidence = marketData.regimeConfidence {
            prompt += "\nCurrent Regime: \(regime.displayName) (\(Int(confidence))% confidence)"
            prompt += "\nRegime Implications: \(regime.implications)"
            
            // Add specific guidance based on regime
            switch regime {
            case .trendingUp:
                prompt += "\n⚠️ In uptrend: RSI can stay overbought, favor long entries on pullbacks"
            case .trendingDown:
                prompt += "\n⚠️ In downtrend: RSI can stay oversold, avoid catching falling knives"
            case .ranging:
                prompt += "\n⚠️ Range-bound: Oscillators work best, trade the boundaries"
            case .highVolatility:
                prompt += "\n⚠️ High volatility: REDUCE confidence, WIDEN price ranges, expect surprises"
            case .lowVolatility:
                prompt += "\n⚠️ Low volatility: Watch for breakout, volume expansion will confirm direction"
            case .breakoutPotential:
                prompt += "\n⚠️ Breakout setup: Direction uncertain, wait for confirmation, high reward potential"
            }
        } else {
            prompt += "\nRegime: Insufficient data for detection"
        }
        
        // MARK: - Multi-Timeframe Confluence Section
        prompt += """
        
        
        ═══════════════════════════════════════════════════════════════
        MULTI-TIMEFRAME ANALYSIS
        ═══════════════════════════════════════════════════════════════
        """
        
        if let confluence = marketData.multiTimeframeConfluence {
            prompt += "\nHigher Timeframe Trend: \(confluence.higherTimeframeTrend.uppercased())"
            prompt += "\nShort-Term Trend: \(confluence.shortTermTrend.uppercased())"
            prompt += "\nConfluence: \(confluence.agrees ? "YES - Aligned" : "NO - Divergence")"
            prompt += "\nStrength: \(Int(confluence.confluenceStrength * 100))%"
            
            if confluence.agrees {
                prompt += "\n✅ Multiple timeframes AGREE - INCREASE confidence"
            } else {
                prompt += "\n⚠️ Timeframe DIVERGENCE - REDUCE confidence, be cautious"
            }
        } else {
            prompt += "\nMulti-TF Analysis: Insufficient data"
        }
        
        // MARK: - Historical Accuracy Context (Personal + Community)
        prompt += """
        
        
        ═══════════════════════════════════════════════════════════════
        HISTORICAL ACCURACY CONTEXT
        ═══════════════════════════════════════════════════════════════
        """
        
        // Personal accuracy history
        let accuracyService = PredictionAccuracyService.shared
        let accuracySummary = accuracyService.accuracySummaryForPrompt(timeframe: timeframe)
        prompt += "\n--- USER'S PERSONAL ACCURACY ---\n"
        prompt += accuracySummary
        
        // Learning insights from past predictions (what worked, what didn't)
        let learningInsights = accuracyService.learningInsights(for: symbol, timeframe: timeframe)
        if learningInsights.totalEvaluated >= 3 {
            prompt += "\n\n--- PREDICTION LEARNING INSIGHTS ---\n"
            prompt += learningInsights.promptSummary()
            prompt += "\nIMPORTANT: Adjust your prediction based on these historical patterns. Past failures should inform more cautious or corrected predictions."
        }
        
        // Community-wide accuracy data (from all users)
        let communityService = CommunityAccuracyService.shared
        let communitySummary = communityService.communitySummaryForPrompt(timeframe: timeframe)
        prompt += "\n\n--- COMMUNITY-WIDE ACCURACY ---\n"
        prompt += communitySummary
        
        // Combined guidance based on both personal and community data
        if accuracyService.metrics.hasEnoughData && communityService.communityMetrics.hasData {
            prompt += "\n\n--- COMBINED INSIGHTS ---"
            
            // Compare personal vs community and provide guidance
            let personalDir = accuracyService.metrics.directionAccuracyPercent
            let communityDir = communityService.communityMetrics.directionAccuracy
            
            if personalDir > communityDir + 10 {
                prompt += "\nThis user's predictions outperform community average - maintain approach."
            } else if personalDir < communityDir - 10 {
                prompt += "\nThis user's predictions underperform community average - apply more conservative confidence."
            }
            
            // Direction-specific guidance from community data
            let communityBullish = communityService.communityMetrics.directionBreakdown.bullish.accuracy
            let communityBearish = communityService.communityMetrics.directionBreakdown.bearish.accuracy
            _ = communityService.communityMetrics.directionBreakdown.neutral.accuracy
            
            if communityBullish > 0 && communityBullish < 40 {
                prompt += "\n⚠️ COMMUNITY WARNING: Bullish predictions have low accuracy across all users (\(String(format: "%.0f", communityBullish))%). Be extra cautious with bullish calls."
            }
            if communityBearish > 0 && communityBearish < 40 {
                prompt += "\n⚠️ COMMUNITY WARNING: Bearish predictions have low accuracy across all users (\(String(format: "%.0f", communityBearish))%). Be extra cautious with bearish calls."
            }
            // NOTE: Removed neutral community bias - it was causing the AI to default to neutral
            // for nearly all predictions, making the system useless. Neutral should only be used
            // when there are genuinely no clear signals, not as a safe default.
        }
        
        prompt += """
        
        
        ═══════════════════════════════════════════════════════════════
        SIGNAL SUMMARY FROM DRIVERS
        ═══════════════════════════════════════════════════════════════
        """
        
        // Count signals
        let bullishCount = marketData.drivers.filter { $0.signal.lowercased() == "bullish" }.count
        let bearishCount = marketData.drivers.filter { $0.signal.lowercased() == "bearish" }.count
        let neutralCount = marketData.drivers.filter { $0.signal.lowercased() == "neutral" }.count
        
        prompt += "\nBullish Signals: \(bullishCount)"
        prompt += "\nBearish Signals: \(bearishCount)"
        prompt += "\nNeutral Signals: \(neutralCount)"
        prompt += "\nNet Signal: \(bullishCount > bearishCount ? "BULLISH BIAS" : (bearishCount > bullishCount ? "BEARISH BIAS" : "MIXED/NEUTRAL"))"
        
        prompt += """
        
        
        ═══════════════════════════════════════════════════════════════
        GENERATE PREDICTION
        ═══════════════════════════════════════════════════════════════
        Timeframe: \(timeframe.fullName)
        
        Weight the indicators according to the ENHANCED methodology:
        - Trend Analysis (25%): MA structure, ADX, MACD
        - Momentum (20%): RSI, Stoch RSI
        - Smart Money/Whale (15%): Smart Money Index, Exchange Flow - IMPORTANT ALPHA
        - Market Sentiment (15%): Fear/Greed, Volume
        - Market Regime (10%): Adjust interpretation based on regime
        - Multi-TF Confluence (10%): Higher TF agreement increases confidence
        - S/R Levels (5%): Support/Resistance proximity
        
        CRITICAL: Smart money and whale data often LEADS price. Pay close attention!
        If smart money is accumulating while price drops = potential reversal.
        If smart money is distributing while price rises = potential top.
        
        Respond with ONLY the JSON prediction object.
        """
        
        return prompt
    }
    
    // MARK: - Response Parsing
    
    private func parsePredictionResponse(
        response: String,
        symbol: String,
        coinName: String,
        currentPrice: Double,
        timeframe: PredictionTimeframe,
        drivers: [PredictionDriver]
    ) throws -> AIPricePrediction {
        // Try to extract JSON from the response
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        // SAFETY: Use half-open range to prevent String index out of bounds crash
        if jsonString.hasPrefix("```") {
            if let startRange = jsonString.range(of: "{"),
               let endRange = jsonString.range(of: "}", options: .backwards),
               startRange.lowerBound < endRange.upperBound {
                jsonString = String(jsonString[startRange.lowerBound..<endRange.upperBound])
            }
        }
        
        // Parse JSON
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw PredictionServiceError.parseError
        }
        
        struct AIResponse: Decodable {
            let direction: String
            let confidence: Int
            let predictedPriceChange: Double
            let priceRangeLow: Double
            let priceRangeHigh: Double
            let analysis: String
            // Probability distribution fields (optional for backward compatibility)
            let probabilityUp2Pct: Double?
            let probabilityUp5Pct: Double?
            let probabilityUp10Pct: Double?
            let probabilityDown2Pct: Double?
            let probabilityDown5Pct: Double?
            let probabilityDown10Pct: Double?
            let directionalScore: Int?
        }
        
        do {
            let decoded = try JSONDecoder().decode(AIResponse.self, from: jsonData)
            
            // Parse the AI's stated direction
            let aiDirection: PredictionDirection
            switch decoded.direction.lowercased() {
            case "bullish": aiDirection = .bullish
            case "bearish": aiDirection = .bearish
            default: aiDirection = .neutral
            }
            
            let priceChange = decoded.predictedPriceChange
            
            // Timeframe-aware validation thresholds
            // Shorter timeframes can have smaller meaningful moves
            // NOTE: Thresholds lowered for 7D/30D to prevent labeling meaningful moves as "neutral"
            // while the target card shows a clear directional price (confusing UX)
            let neutralThreshold: Double = {
                switch timeframe {
                case .hour: return 0.3        // 0.3% for 1H
                case .fourHours: return 0.5   // 0.5% for 4H
                case .twelveHours: return 0.75 // 0.75% for 12H
                case .day: return 1.0         // 1.0% for 24H
                case .week: return 1.5        // 1.5% for 7D (was 2.0%)
                case .month: return 2.0       // 2.0% for 30D (was 3.0%)
                }
            }()
            
            // Determine validated direction:
            // 1. Trust AI's direction if price change is in that direction (even if small)
            // 2. Only override if there's a clear contradiction
            let validatedDirection: PredictionDirection
            
            // TRUST THE AI's DIRECTION CALL — only override in extreme contradictions
            // Previously this was too aggressive at forcing neutral, making all predictions useless
            if aiDirection == .neutral {
                // AI explicitly said neutral — validate it
                if abs(priceChange) >= neutralThreshold * 2 {
                    // AI said neutral but predicted a significant move — use the move direction
                    validatedDirection = priceChange > 0 ? .bullish : .bearish
                } else {
                    validatedDirection = .neutral
                }
            } else {
                // AI said bullish or bearish — trust it
                // Only override if the predicted price change STRONGLY contradicts (>2x threshold)
                if abs(priceChange) > neutralThreshold * 2 {
                    // Large predicted move — direction must match
                    if (aiDirection == .bullish && priceChange < -neutralThreshold) {
                        validatedDirection = .bearish // AI said bullish but predicted big drop
                    } else if (aiDirection == .bearish && priceChange > neutralThreshold) {
                        validatedDirection = .bullish // AI said bearish but predicted big rise
                    } else {
                        validatedDirection = aiDirection
                    }
                } else {
                    // Small or moderate move — trust the AI's directional call
                    validatedDirection = aiDirection
                }
            }
            
            #if DEBUG
            // Log validation results
            if aiDirection != validatedDirection {
                print("[AIPrediction] Direction adjusted: AI said \(aiDirection.displayName), price change \(String(format: "%.2f", priceChange))%, threshold \(String(format: "%.1f", neutralThreshold))% -> using \(validatedDirection.displayName)")
            } else {
                print("[AIPrediction] Direction validated: \(validatedDirection.displayName) with \(String(format: "%.2f", priceChange))% change")
            }
            #endif
            
            // Apply accuracy-based confidence calibration
            // This adjusts confidence based on historical performance for this direction/timeframe
            let accuracyService = PredictionAccuracyService.shared
            let boundedConfidence = max(0, min(100, decoded.confidence))
            let adjustedConfidenceScore = accuracyService.adjustConfidenceScore(
                boundedConfidence,
                for: symbol,
                timeframe: timeframe,
                direction: validatedDirection
            )
            
            let confidence = PredictionConfidence.from(score: adjustedConfidenceScore)
            
            // Calculate price range with validation
            let safeRangeLow = decoded.priceRangeLow.isFinite ? decoded.priceRangeLow : -5.0
            let safeRangeHigh = decoded.priceRangeHigh.isFinite ? decoded.priceRangeHigh : 5.0
            let safeCurrentPrice = currentPrice > 0 ? currentPrice : 1.0 // Prevent zero division
            
            var priceLow = safeCurrentPrice * (1 + safeRangeLow / 100)
            var priceHigh = safeCurrentPrice * (1 + safeRangeHigh / 100)
            
            // Ensure low < high (swap if AI returned inverted range)
            if priceLow > priceHigh { swap(&priceLow, &priceHigh) }
            
            // Ensure non-negative prices
            priceLow = max(0, priceLow)
            priceHigh = max(priceLow + 0.01, priceHigh)
            
            return AIPricePrediction(
                id: UUID().uuidString,
                coinSymbol: symbol.uppercased(),
                coinName: coinName,
                currentPrice: currentPrice,
                predictedPriceChange: decoded.predictedPriceChange,
                predictedPriceLow: priceLow,
                predictedPriceHigh: priceHigh,
                confidenceScore: adjustedConfidenceScore,
                confidence: confidence,
                direction: validatedDirection,
                timeframe: timeframe,
                drivers: drivers,
                analysis: decoded.analysis,
                generatedAt: Date(),
                probabilityUp2Pct: decoded.probabilityUp2Pct,
                probabilityUp5Pct: decoded.probabilityUp5Pct,
                probabilityUp10Pct: decoded.probabilityUp10Pct,
                probabilityDown2Pct: decoded.probabilityDown2Pct,
                probabilityDown5Pct: decoded.probabilityDown5Pct,
                probabilityDown10Pct: decoded.probabilityDown10Pct,
                directionalScore: decoded.directionalScore
            )
        } catch {
            // Fallback: create a neutral prediction if parsing fails
            throw PredictionServiceError.parseError
        }
    }
    
    // MARK: - Helpers
    
    private func formatPrice(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.2f", value)
        } else if value >= 1 {
            return String(format: "%.4f", value)
        } else {
            return String(format: "%.6f", value)
        }
    }
    
    private func formatLargeNumber(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "%.2fT", value / 1_000_000_000_000)
        } else if value >= 1_000_000_000 {
            return String(format: "%.2fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.2fK", value / 1_000)
        }
        return String(format: "%.2f", value)
    }
}

// MARK: - Notification Support

extension AIPricePredictionService {
    private func notifySubscriptionChanged() {
        NotificationCenter.default.post(name: .subscriptionDidChange, object: nil)
    }
}

extension Notification.Name {
    static let subscriptionDidChange = Notification.Name("subscriptionDidChange")
}
