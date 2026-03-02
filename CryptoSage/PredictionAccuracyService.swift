//
//  PredictionAccuracyService.swift
//  CryptoSage
//
//  Service for tracking AI prediction accuracy over time.
//  Stores predictions when generated and compares against actual outcomes
//  to calculate historical accuracy metrics.
//
//  ARCHITECTURE NOTE: Cloud Sync Design (Future Phase)
//  ====================================================
//  The current implementation stores data locally per-device using UserDefaults.
//  For a smarter, shared learning system, the following cloud sync architecture
//  is designed for future implementation:
//
//  Benefits of Cloud Sync:
//  - New users immediately benefit from historical accuracy data
//  - Larger sample sizes across all users = more reliable metrics
//  - Identify market-wide patterns (e.g., predictions fail during high volatility)
//  - A/B test prediction algorithms across user cohorts
//
//  Privacy Considerations:
//  - Only anonymized accuracy metrics are synced (no personal data)
//  - User can opt-out of cloud sync while keeping local tracking
//  - No individual prediction details are shared, only aggregate stats
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore

// MARK: - Cloud Sync Architecture (Future Implementation)

/// Protocol for cloud-synced accuracy data provider
/// Implement this to enable shared learning across users
public protocol AccuracyCloudSyncProvider {
    /// Fetch global accuracy metrics from cloud
    func fetchGlobalMetrics() async throws -> GlobalAccuracyMetrics
    
    /// Upload local anonymized accuracy data to contribute to global learning
    func uploadLocalMetrics(_ metrics: AnonymizedAccuracyData) async throws
    
    /// Check if cloud sync is available and enabled
    var isEnabled: Bool { get }
}

/// Global accuracy metrics aggregated from all users
public struct GlobalAccuracyMetrics: Codable {
    /// Total predictions evaluated across all users
    public let totalPredictions: Int
    
    /// Global direction accuracy percentage
    public let globalDirectionAccuracy: Double
    
    /// Global range accuracy percentage
    public let globalRangeAccuracy: Double
    
    /// Accuracy breakdown by timeframe (global averages)
    public let timeframeAccuracy: [String: Double]  // "1h": 45.5, "24h": 52.3, etc.
    
    /// Accuracy breakdown by direction (global averages)
    public let directionAccuracy: [String: Double]  // "bullish": 38.2, "bearish": 41.5, etc.
    
    /// Market condition insights
    public let marketConditionInsights: [MarketConditionAccuracy]?
    
    /// Last updated timestamp
    public let lastUpdated: Date
    
    /// Sample size threshold met (enough data for reliable metrics)
    public var isReliable: Bool {
        totalPredictions >= 1000
    }
}

/// Accuracy data for specific market conditions
public struct MarketConditionAccuracy: Codable {
    /// Market condition identifier (e.g., "high_volatility", "trending_up", "ranging")
    public let condition: String
    
    /// Accuracy during this condition
    public let accuracy: Double
    
    /// Number of predictions in this condition
    public let sampleSize: Int
    
    /// Recommendation for this condition
    public let recommendation: String?
}

/// Anonymized accuracy data for cloud upload
/// Contains NO personal information - only aggregate metrics
public struct AnonymizedAccuracyData: Codable {
    /// Random session ID (not tied to user identity)
    public let sessionId: String
    
    /// App version for tracking algorithm changes
    public let appVersion: String
    
    /// Aggregate metrics to contribute
    public let metrics: AccuracyContribution
    
    /// Timestamp of contribution
    public let timestamp: Date
}

/// Accuracy contribution data structure
public struct AccuracyContribution: Codable {
    /// Number of predictions evaluated
    public let evaluatedCount: Int
    
    /// Direction correct count
    public let directionsCorrect: Int
    
    /// Within range count
    public let withinRangeCount: Int
    
    /// Breakdown by timeframe
    public let byTimeframe: [String: TimeframeContribution]
    
    /// Breakdown by direction
    public let byDirection: [String: DirectionContribution]
}

/// Contribution data for a specific timeframe
public struct TimeframeContribution: Codable {
    public let total: Int
    public let correct: Int
}

/// Contribution data for a specific direction
public struct DirectionContribution: Codable {
    public let total: Int
    public let correct: Int
}

/// Placeholder cloud sync provider (no-op implementation)
/// Replace with actual implementation when backend is ready
public final class PlaceholderCloudSyncProvider: AccuracyCloudSyncProvider {
    public static let shared = PlaceholderCloudSyncProvider()
    
    public var isEnabled: Bool { false }
    
    public func fetchGlobalMetrics() async throws -> GlobalAccuracyMetrics {
        // Return empty metrics - cloud sync not implemented
        return GlobalAccuracyMetrics(
            totalPredictions: 0,
            globalDirectionAccuracy: 0,
            globalRangeAccuracy: 0,
            timeframeAccuracy: [:],
            directionAccuracy: [:],
            marketConditionInsights: nil,
            lastUpdated: Date()
        )
    }
    
    public func uploadLocalMetrics(_ metrics: AnonymizedAccuracyData) async throws {
        // No-op - cloud sync not implemented
        print("[CloudSync] Upload skipped - cloud sync not enabled")
    }
}

/*
 FUTURE IMPLEMENTATION GUIDE:
 ============================
 
 1. Backend Requirements:
    - REST API or Firebase/CloudKit for data storage
    - Endpoints: GET /accuracy/global, POST /accuracy/contribute
    - Aggregation logic to combine user contributions
    - Privacy-preserving data handling
 
 2. Integration Steps:
    a. Create a concrete AccuracyCloudSyncProvider implementation
    b. Add cloud sync toggle in Settings (opt-in by default)
    c. Call fetchGlobalMetrics() on app launch (cached)
    d. Call uploadLocalMetrics() periodically (e.g., daily) when user has new evaluated predictions
    e. Display "Global Accuracy" alongside "Your Accuracy" in UI
 
 3. UI Changes Needed:
    - Add "Global Accuracy" section to PredictionAccuracyCard
    - Add cloud sync toggle in settings
    - Show "Contributing to X users" badge when enabled
 
 4. AI Prompt Integration:
    - Add global accuracy context to accuracySummaryForPrompt()
    - Example: "Global accuracy across 50,000 predictions: 48% direction"
    - Include market condition insights when available
 
 5. Example Backend Schema (Firestore):
    
    Collection: accuracy_contributions
    Document: {
      sessionId: string,
      appVersion: string,
      evaluatedCount: number,
      directionsCorrect: number,
      withinRangeCount: number,
      byTimeframe: { "1h": { total: 5, correct: 2 }, ... },
      byDirection: { "bullish": { total: 8, correct: 3 }, ... },
      timestamp: timestamp
    }
    
    Collection: global_metrics (single document, updated by Cloud Function)
    Document: {
      totalPredictions: number,
      globalDirectionAccuracy: number,
      globalRangeAccuracy: number,
      timeframeAccuracy: { "1h": 45.5, ... },
      directionAccuracy: { "bullish": 38.2, ... },
      lastUpdated: timestamp
    }
*/

// MARK: - Stored Prediction Model

/// A prediction that has been stored for accuracy tracking
public struct StoredPrediction: Codable, Identifiable {
    public let id: String
    public let coinSymbol: String
    public let coinName: String
    public let timeframe: PredictionTimeframe
    
    // Prediction data (captured at generation time)
    public let predictedDirection: PredictionDirection
    public let predictedPriceChange: Double // Percentage
    public let predictedPriceLow: Double
    public let predictedPriceHigh: Double
    public let confidenceScore: Int
    public let priceAtPrediction: Double
    public let generatedAt: Date
    public let targetDate: Date
    
    /// The AI model that generated this prediction (e.g. "deepseek-chat", "gpt-4o-mini")
    /// nil for legacy predictions that predate model tracking
    public var aiModelProvider: String?
    
    // Outcome data (filled when prediction expires)
    public var actualPrice: Double?
    public var actualPriceChange: Double? // Percentage
    public var actualDirection: PredictionDirection?
    public var evaluatedAt: Date?
    
    // Accuracy results
    public var directionCorrect: Bool?
    public var withinPriceRange: Bool?
    public var priceError: Double? // Absolute percentage error
    
    /// Whether this prediction has been evaluated
    public var isEvaluated: Bool {
        evaluatedAt != nil
    }
    
    /// Whether this prediction is ready to be evaluated (past target date)
    public var isReadyForEvaluation: Bool {
        Date() >= targetDate && !isEvaluated
    }
    
    /// Whether this is a legacy prediction (model not tracked, pre-DeepSeek)
    public var isLegacy: Bool {
        aiModelProvider == nil
    }
    
    /// Whether this prediction was generated by DeepSeek
    public var isDeepSeek: Bool {
        guard let model = aiModelProvider?.lowercased() else { return false }
        return model.contains("deepseek")
    }
    
    /// Create from an AIPricePrediction
    public init(from prediction: AIPricePrediction, modelProvider: String? = nil) {
        self.id = prediction.id
        self.coinSymbol = prediction.coinSymbol
        self.coinName = prediction.coinName
        self.timeframe = prediction.timeframe
        self.predictedDirection = prediction.direction
        self.predictedPriceChange = prediction.predictedPriceChange
        self.predictedPriceLow = prediction.predictedPriceLow
        self.predictedPriceHigh = prediction.predictedPriceHigh
        self.confidenceScore = prediction.confidenceScore
        self.priceAtPrediction = prediction.currentPrice
        self.generatedAt = prediction.generatedAt
        self.targetDate = prediction.targetDate
        self.aiModelProvider = modelProvider
    }
    
    /// Evaluate this prediction against the actual outcome
    public mutating func evaluate(actualPrice: Double) {
        self.actualPrice = actualPrice
        self.evaluatedAt = Date()
        
        // Calculate actual price change percentage (guard against division by zero)
        let change = priceAtPrediction > 0 ? ((actualPrice - priceAtPrediction) / priceAtPrediction) * 100 : 0
        self.actualPriceChange = change
        
        // Timeframe-scaled neutral threshold
        // Longer timeframes naturally have more price drift, so the "neutral zone" widens
        let neutralThreshold: Double = {
            switch timeframe {
            case .hour:        return 1.0
            case .fourHours:   return 1.5
            case .twelveHours: return 2.0
            case .day:         return 2.5
            case .week:        return 4.0
            case .month:       return 6.0
            }
        }()
        
        // Determine actual direction using scaled threshold
        if change > neutralThreshold {
            self.actualDirection = .bullish
        } else if change < -neutralThreshold {
            self.actualDirection = .bearish
        } else {
            self.actualDirection = .neutral
        }
        
        // Check if direction was correct
        // Neutral predictions are correct if price stayed within the threshold
        if predictedDirection == .neutral {
            self.directionCorrect = abs(change) <= neutralThreshold
        } else {
            self.directionCorrect = actualDirection == predictedDirection
        }
        
        // Check if actual price is within predicted range
        self.withinPriceRange = actualPrice >= predictedPriceLow && actualPrice <= predictedPriceHigh
        
        // Calculate absolute percentage error from predicted change
        self.priceError = abs(change - predictedPriceChange)
    }
}

// MARK: - Accuracy Metrics

/// Aggregated accuracy metrics for predictions
public struct AccuracyMetrics: Codable {
    public let totalPredictions: Int
    public let evaluatedPredictions: Int
    
    // Direction accuracy
    public let directionsCorrect: Int
    public let directionAccuracyPercent: Double
    
    // Range accuracy
    public let withinRangeCount: Int
    public let rangeAccuracyPercent: Double
    
    // Error metrics
    public let averagePriceError: Double
    public let medianPriceError: Double
    
    // Breakdown by direction
    public let bullishPredictions: Int
    public let bullishCorrect: Int
    public let bearishPredictions: Int
    public let bearishCorrect: Int
    public let neutralPredictions: Int
    public let neutralCorrect: Int
    
    // Breakdown by timeframe
    public let metricsByTimeframe: [PredictionTimeframe: TimeframeMetrics]
    
    // Breakdown by confidence level
    public let highConfidenceAccuracy: Double?
    public let mediumConfidenceAccuracy: Double?
    public let lowConfidenceAccuracy: Double?
    
    /// Empty metrics for display when no data
    public static var empty: AccuracyMetrics {
        AccuracyMetrics(
            totalPredictions: 0,
            evaluatedPredictions: 0,
            directionsCorrect: 0,
            directionAccuracyPercent: 0,
            withinRangeCount: 0,
            rangeAccuracyPercent: 0,
            averagePriceError: 0,
            medianPriceError: 0,
            bullishPredictions: 0,
            bullishCorrect: 0,
            bearishPredictions: 0,
            bearishCorrect: 0,
            neutralPredictions: 0,
            neutralCorrect: 0,
            metricsByTimeframe: [:],
            highConfidenceAccuracy: nil,
            mediumConfidenceAccuracy: nil,
            lowConfidenceAccuracy: nil
        )
    }
    
    /// Whether we have enough data for meaningful metrics
    public var hasEnoughData: Bool {
        evaluatedPredictions >= 5
    }
    
    /// Formatted direction accuracy string
    public var formattedDirectionAccuracy: String {
        String(format: "%.0f%%", directionAccuracyPercent)
    }
    
    /// Formatted range accuracy string
    public var formattedRangeAccuracy: String {
        String(format: "%.0f%%", rangeAccuracyPercent)
    }
    
    /// Formatted average error string
    public var formattedAverageError: String {
        String(format: "%.1f%%", averagePriceError)
    }
}

/// Metrics for a specific timeframe
public struct TimeframeMetrics: Codable {
    public let timeframe: PredictionTimeframe
    public let totalPredictions: Int
    public let evaluatedPredictions: Int
    public let directionsCorrect: Int
    public let directionAccuracyPercent: Double
    public let averagePriceError: Double
}

/// Structured accuracy conditions for prediction feedback
public struct AccuracyConditions {
    public let totalEvaluated: Int
    public let overallAccuracy: Double
    
    /// Best performing timeframe (timeframe, accuracy%)
    public let bestTimeframe: (PredictionTimeframe, Double)?
    /// Worst performing timeframe (timeframe, accuracy%)
    public let worstTimeframe: (PredictionTimeframe, Double)?
    
    /// Best performing direction (direction, accuracy%)
    public let bestDirection: (PredictionDirection, Double)?
    /// Worst performing direction (direction, accuracy%)
    public let worstDirection: (PredictionDirection, Double)?
    
    /// Whether high confidence predictions are reliable (>65% accurate)
    public let highConfidenceReliable: Bool
    /// Whether low confidence predictions are unreliable (<45% accurate)
    public let lowConfidenceUnreliable: Bool
    
    /// Average price prediction error
    public let averageError: Double
    
    /// Accuracy by confidence bracket
    public let highConfidenceAccuracy: Double?
    public let mediumConfidenceAccuracy: Double?
    public let lowConfidenceAccuracy: Double?
    
    /// Whether we have enough data for meaningful analysis
    public var hasEnoughData: Bool {
        totalEvaluated >= 5
    }
    
    /// Summary string for display
    public var summaryText: String {
        guard hasEnoughData else {
            return "Not enough predictions evaluated yet"
        }
        
        var parts: [String] = []
        parts.append("\(String(format: "%.0f", overallAccuracy))% overall accuracy")
        
        if let best = bestTimeframe {
            parts.append("Best: \(best.0.displayName) (\(String(format: "%.0f", best.1))%)")
        }
        
        return parts.joined(separator: " | ")
    }
}

// MARK: - Prediction Learning Insights

/// Structured insights from past predictions used to improve future predictions
public struct PredictionLearningInsights {
    public let totalEvaluated: Int
    public let overallAccuracy: Double
    public let recentAccuracy: Double  // Last 5 predictions
    public let highConfidenceAccuracy: Double
    public let lowConfidenceAccuracy: Double
    public let overestimateCount: Int
    public let underestimateCount: Int
    public let avgPredictedMagnitude: Double
    public let avgActualMagnitude: Double
    public let failedPredictionCount: Int
    public let successPredictionCount: Int
    
    /// Whether confidence scores are poorly calibrated (high conf < low conf)
    public let confidenceCalibrationOff: Bool
    /// Whether predictions tend to over-predict price changes
    public let tendToOverpredict: Bool
    /// Whether predictions tend to under-predict price changes
    public let tendToUnderpredict: Bool
    
    public static var empty: PredictionLearningInsights {
        PredictionLearningInsights(
            totalEvaluated: 0, overallAccuracy: 0, recentAccuracy: 0,
            highConfidenceAccuracy: 0, lowConfidenceAccuracy: 0,
            overestimateCount: 0, underestimateCount: 0,
            avgPredictedMagnitude: 0, avgActualMagnitude: 0,
            failedPredictionCount: 0, successPredictionCount: 0,
            confidenceCalibrationOff: false, tendToOverpredict: false, tendToUnderpredict: false
        )
    }
    
    /// Generate a concise summary for injecting into AI prompts
    public func promptSummary() -> String {
        guard totalEvaluated >= 3 else {
            return "Insufficient historical data for learning insights."
        }
        
        var lines: [String] = []
        
        lines.append("LEARNING FROM \(totalEvaluated) PAST PREDICTIONS:")
        lines.append("Overall accuracy: \(String(format: "%.0f", overallAccuracy))% | Recent (last 5): \(String(format: "%.0f", recentAccuracy))%")
        
        if confidenceCalibrationOff {
            lines.append("⚠️ CONFIDENCE CALIBRATION ISSUE: High confidence predictions (\(String(format: "%.0f", highConfidenceAccuracy))%) are LESS accurate than low confidence (\(String(format: "%.0f", lowConfidenceAccuracy))%). Lower your confidence scores.")
        }
        
        if tendToOverpredict {
            lines.append("⚠️ OVERPREDICTION BIAS: Avg predicted move: \(String(format: "%.1f", avgPredictedMagnitude))% vs actual: \(String(format: "%.1f", avgActualMagnitude))%. Reduce predicted price change magnitude.")
        }
        
        if tendToUnderpredict {
            lines.append("⚠️ UNDERPREDICTION BIAS: Avg predicted move: \(String(format: "%.1f", avgPredictedMagnitude))% vs actual: \(String(format: "%.1f", avgActualMagnitude))%. Increase predicted price change magnitude.")
        }
        
        if overestimateCount > underestimateCount * 2 {
            lines.append("PATTERN: Consistently overestimating price moves (\(overestimateCount) overestimates vs \(underestimateCount) underestimates)")
        } else if underestimateCount > overestimateCount * 2 {
            lines.append("PATTERN: Consistently underestimating price moves (\(underestimateCount) underestimates vs \(overestimateCount) overestimates)")
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Prediction Accuracy Service

@MainActor
public final class PredictionAccuracyService: ObservableObject {
    public static let shared = PredictionAccuracyService()
    
    // MARK: - Published Properties
    
    @Published public private(set) var storedPredictions: [StoredPrediction] = []
    @Published public private(set) var metrics: AccuracyMetrics = .empty
    @Published public private(set) var isEvaluating: Bool = false
    @Published public private(set) var lastEvaluationDate: Date?
    
    // MARK: - Storage Keys
    
    private let storageKey = "PredictionAccuracy.StoredPredictions"
    private let metricsKey = "PredictionAccuracy.Metrics"
    private let lastEvalKey = "PredictionAccuracy.LastEvaluation"
    
    // MARK: - Configuration
    
    /// Maximum number of predictions to store (older ones are pruned)
    private let maxStoredPredictions = 200
    
    /// Minimum time between automatic evaluations
    private let evaluationCooldown: TimeInterval = 60 * 60 // 1 hour
    
    /// Firestore database reference
    private let db = Firestore.firestore()
    
    /// Whether Firestore sync is active
    private var firestoreListener: ListenerRegistration?
    private var isApplyingFirestoreUpdate = false
    
    deinit {
        firestoreListener?.remove()
    }
    
    // MARK: - Initialization
    
    private init() {
        loadFromStorage()
        // NOTE: Do NOT call startFirestoreSyncIfAuthenticated() here.
        // AuthenticationManager calls it after session restore/sign-in.
        // Calling it here caused a duplicate listener (init triggers lazy singleton
        // creation, then AuthManager calls it again on the returned instance).
    }
    
    // MARK: - Public API
    
    /// Store a new prediction for accuracy tracking
    /// - Parameters:
    ///   - prediction: The AI prediction to store
    ///   - modelProvider: The AI model that generated it (e.g. "deepseek-chat", "gpt-4o-mini")
    public func storePrediction(_ prediction: AIPricePrediction, modelProvider: String? = nil) {
        // Check if we already have this prediction
        guard !storedPredictions.contains(where: { $0.id == prediction.id }) else {
            return
        }
        
        let stored = StoredPrediction(from: prediction, modelProvider: modelProvider)
        storedPredictions.append(stored)
        
        // Prune old predictions if over limit
        pruneOldPredictions()
        
        // Save to storage
        saveToStorage()
        
        let modelTag = modelProvider ?? "unknown"
        print("[PredictionAccuracy] Stored prediction for \(prediction.coinSymbol) (\(prediction.timeframe.displayName)) [model: \(modelTag)]")
        
        // Push to Firestore for cross-device sync (debounced)
        debouncedPushToFirestore()
        
        // Schedule evaluation for when this prediction expires
        scheduleEvaluation(for: stored)
    }
    
    /// Schedule a delayed evaluation for a prediction that will expire in the future
    /// Only schedules for short-term predictions (≤4h) to avoid accumulating long-lived Tasks
    private func scheduleEvaluation(for prediction: StoredPrediction) {
        let delay = prediction.targetDate.timeIntervalSinceNow
        guard delay > 0 else {
            // Already expired — evaluate shortly
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await evaluatePendingPredictions()
            }
            return
        }
        
        // Only auto-schedule for short timeframes (≤4 hours)
        // Longer predictions rely on app launch evaluation passes
        let maxAutoScheduleDelay: TimeInterval = 4 * 3600 + 60 // 4h + 1min buffer
        guard delay < maxAutoScheduleDelay else {
            print("[PredictionAccuracy] Prediction for \(prediction.coinSymbol) expires in \(Int(delay/3600))h — will evaluate on next app launch")
            return
        }
        
        let evaluationDelay = delay + 30
        scheduledEvaluationTask?.cancel()
        scheduledEvaluationTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(evaluationDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            print("[PredictionAccuracy] Auto-evaluating expired prediction for \(prediction.coinSymbol)")
            await evaluatePendingPredictions()
        }
    }
    
    /// Single tracked evaluation task (prevents accumulation)
    private var scheduledEvaluationTask: Task<Void, Never>?
    
    /// Track retry attempts to prevent infinite loops
    private var evaluationRetryCount: Int = 0
    private let maxEvaluationRetries: Int = 5
    
    /// Evaluate all pending predictions
    /// Enhanced with retry logic — retries up to 5 times with increasing backoff
    public func evaluatePendingPredictions() async {
        guard !isEvaluating else { return }
        
        isEvaluating = true
        defer { isEvaluating = false }
        
        let pendingPredictions = storedPredictions.filter { $0.isReadyForEvaluation }
        
        guard !pendingPredictions.isEmpty else {
            evaluationRetryCount = 0 // Reset on clean state
            return
        }
        
        print("[PredictionAccuracy] Evaluating \(pendingPredictions.count) pending predictions (attempt \(evaluationRetryCount + 1))")
        
        var evaluatedCount = 0
        for prediction in pendingPredictions {
            let beforeCount = storedPredictions.filter { $0.isEvaluated }.count
            await evaluatePrediction(prediction)
            let afterCount = storedPredictions.filter { $0.isEvaluated }.count
            if afterCount > beforeCount { evaluatedCount += 1 }
        }
        
        // Recalculate metrics
        recalculateMetrics()
        
        // Update last evaluation date
        lastEvaluationDate = Date()
        
        // Save to storage
        saveToStorage()
        
        print("[PredictionAccuracy] Evaluated \(evaluatedCount)/\(pendingPredictions.count) predictions successfully")
        
        // If some failed and we haven't exceeded retry limit, schedule a retry with backoff
        let stillPending = storedPredictions.filter { $0.isReadyForEvaluation }.count
        if stillPending > 0 && evaluationRetryCount < maxEvaluationRetries {
            evaluationRetryCount += 1
            let backoffSeconds = min(120 * evaluationRetryCount, 600) // 2min, 4min, 6min, 8min, 10min max
            print("[PredictionAccuracy] \(stillPending) still pending — retry \(evaluationRetryCount)/\(maxEvaluationRetries) in \(backoffSeconds)s")
            Task {
                try? await Task.sleep(nanoseconds: UInt64(backoffSeconds) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self.evaluatePendingPredictions()
            }
        } else if stillPending > 0 {
            print("[PredictionAccuracy] \(stillPending) still pending but max retries reached — will retry on next app launch")
            evaluationRetryCount = 0
        } else {
            evaluationRetryCount = 0
        }
    }
    
    /// Evaluate a specific prediction by fetching current price
    /// Uses MarketViewModel first, then falls back to direct CoinGecko API fetch
    private func evaluatePrediction(_ prediction: StoredPrediction) async {
        var actualPrice: Double?
        
        // Strategy 1: Try MarketViewModel (fastest, no API call)
        // Normalize symbol: trim whitespace, uppercase, strip common suffixes
        let normalizedSymbol = prediction.coinSymbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-USD", with: "")
            .replacingOccurrences(of: "/USD", with: "")
            .replacingOccurrences(of: "USDT", with: "") // Handle "BTCUSDT" → "BTC"
        
        let marketVM = MarketViewModel.shared
        if let coin = marketVM.allCoins.first(where: {
            $0.symbol.uppercased() == normalizedSymbol ||
            $0.symbol.uppercased() == prediction.coinSymbol.uppercased()
        }) {
            actualPrice = coin.priceUsd
        }
        
        // Strategy 2: Direct CoinGecko API fetch (works even if market view not loaded)
        if actualPrice == nil {
            do {
                let price = try await CryptoAPIService.shared.fetchSpotPrice(coin: prediction.coinSymbol)
                if price > 0 {
                    actualPrice = price
                    print("[PredictionAccuracy] Fetched price via API for \(prediction.coinSymbol): $\(String(format: "%.2f", price))")
                }
            } catch {
                print("[PredictionAccuracy] API price fetch failed for \(prediction.coinSymbol): \(error.localizedDescription)")
            }
        }
        
        guard let price = actualPrice, price > 0 else {
            print("[PredictionAccuracy] Could not get price for \(prediction.coinSymbol) - will retry later")
            return
        }
        
        // Find and update the prediction
        if let index = storedPredictions.firstIndex(where: { $0.id == prediction.id }) {
            storedPredictions[index].evaluate(actualPrice: price)
            
            let result = storedPredictions[index]
            print("[PredictionAccuracy] Evaluated \(prediction.coinSymbol): direction=\(result.directionCorrect ?? false), inRange=\(result.withinPriceRange ?? false), error=\(String(format: "%.2f", result.priceError ?? 0))%")
            
            // Record evaluation to Firebase for global tracking
            await recordEvaluationToFirebase(result)
        }
    }
    
    /// Get metrics for a specific coin
    public func metricsForCoin(_ symbol: String) -> AccuracyMetrics? {
        let coinPredictions = storedPredictions.filter {
            $0.coinSymbol.uppercased() == symbol.uppercased() && $0.isEvaluated
        }
        
        guard coinPredictions.count >= 3 else { return nil }
        
        return calculateMetrics(from: coinPredictions)
    }
    
    /// Get metrics for a specific timeframe
    public func metricsForTimeframe(_ timeframe: PredictionTimeframe) -> TimeframeMetrics? {
        metrics.metricsByTimeframe[timeframe]
    }
    
    /// Get recent predictions for display
    public func recentPredictions(limit: Int = 10) -> [StoredPrediction] {
        Array(storedPredictions
            .filter { $0.isEvaluated }
            .sorted { $0.evaluatedAt ?? .distantPast > $1.evaluatedAt ?? .distantPast }
            .prefix(limit))
    }
    
    /// Clear all stored data (for testing/reset)
    public func clearAllData() {
        storedPredictions = []
        metrics = .empty
        lastEvaluationDate = nil
        saveToStorage()
    }
    
    /// Clear only legacy predictions (those without model tracking, i.e. old ChatGPT predictions)
    /// Keeps DeepSeek and other model-tagged predictions intact
    public func clearLegacyPredictions() {
        let before = storedPredictions.count
        storedPredictions.removeAll { $0.isLegacy }
        let removed = before - storedPredictions.count
        
        // Recalculate metrics from remaining predictions
        recalculateMetrics()
        saveToStorage()
        
        print("[PredictionAccuracy] Cleared \(removed) legacy predictions, \(storedPredictions.count) remaining")
    }
    
    /// Get metrics filtered to only DeepSeek (current model) predictions
    public var deepSeekMetrics: AccuracyMetrics {
        let deepSeekPredictions = storedPredictions.filter { $0.isDeepSeek && $0.isEvaluated }
        guard !deepSeekPredictions.isEmpty else { return .empty }
        return calculateMetrics(from: deepSeekPredictions)
    }
    
    /// Count of legacy (pre-DeepSeek) predictions still stored
    public var legacyPredictionCount: Int {
        storedPredictions.filter { $0.isLegacy }.count
    }
    
    /// Count of DeepSeek predictions stored
    public var deepSeekPredictionCount: Int {
        storedPredictions.filter { $0.isDeepSeek }.count
    }
    
    /// Count of DeepSeek predictions that have been evaluated
    public var deepSeekEvaluatedCount: Int {
        storedPredictions.filter { $0.isDeepSeek && $0.isEvaluated }.count
    }
    
    /// Count of legacy predictions that have been evaluated
    public var legacyEvaluatedCount: Int {
        storedPredictions.filter { $0.isLegacy && $0.isEvaluated }.count
    }
    
    /// Whether there are any DeepSeek evaluated predictions to show
    public var hasDeepSeekEvaluatedData: Bool {
        deepSeekEvaluatedCount > 0
    }
    
    /// Best metrics to display in the UI:
    /// - If DeepSeek has evaluated predictions, show only those (current model)
    /// - Otherwise fall back to all evaluated predictions (may include legacy)
    public var displayMetrics: AccuracyMetrics {
        if hasDeepSeekEvaluatedData {
            return deepSeekMetrics
        }
        return metrics
    }
    
    /// Whether the displayed metrics are DeepSeek-only
    public var isShowingDeepSeekMetrics: Bool {
        hasDeepSeekEvaluatedData
    }
    
    // MARK: - Accuracy Feedback for Predictions
    
    /// Get accuracy-based confidence adjustment for a given prediction context
    /// Returns a multiplier: 1.0 = neutral, >1 = historically more accurate, <1 = historically less accurate
    /// Enhanced with aggressive penalties for consistently poor performance
    /// - Parameters:
    ///   - symbol: The coin symbol (optional for symbol-specific adjustment)
    ///   - timeframe: The prediction timeframe
    ///   - direction: The predicted direction
    /// - Returns: Confidence multiplier (typically 0.5 to 1.2)
    public func confidenceAdjustment(
        for symbol: String? = nil,
        timeframe: PredictionTimeframe,
        direction: PredictionDirection
    ) -> Double {
        // Base multiplier
        var multiplier = 1.0
        
        // Check if we have enough data
        guard metrics.evaluatedPredictions >= 5 else {
            print("[PredictionAccuracy] Insufficient data for confidence adjustment (need 5, have \(metrics.evaluatedPredictions))")
            return 1.0
        }
        
        // CRITICAL: Overall accuracy penalty
        // If overall accuracy is below 40%, apply a global penalty
        if metrics.directionAccuracyPercent < 40 {
            let globalPenalty = (40 - metrics.directionAccuracyPercent) / 100  // Up to -0.4
            multiplier -= globalPenalty
            print("[PredictionAccuracy] Global accuracy penalty: \(String(format: "%.2f", -globalPenalty)) (overall accuracy: \(String(format: "%.0f", metrics.directionAccuracyPercent))%)")
        }
        
        // Timeframe adjustment - more aggressive for poor performers
        if let tfMetrics = metrics.metricsByTimeframe[timeframe], tfMetrics.evaluatedPredictions >= 3 {
            let tfAccuracy = tfMetrics.directionAccuracyPercent
            
            // Strong penalty for timeframes performing below 35%
            if tfAccuracy < 35 {
                let tfPenalty = (35 - tfAccuracy) / 70  // Up to -0.5 for 0% accuracy
                multiplier -= tfPenalty
                print("[PredictionAccuracy] Timeframe \(timeframe.displayName) PENALTY: \(String(format: "%.2f", -tfPenalty)) (accuracy: \(String(format: "%.0f", tfAccuracy))%)")
            } else {
                // Normal adjustment for decent performers
                let tfAdjustment = (tfAccuracy - 50) / 200  // Range: -0.25 to +0.25
                multiplier += tfAdjustment
                print("[PredictionAccuracy] Timeframe \(timeframe.displayName) accuracy: \(String(format: "%.0f", tfAccuracy))%, adjustment: \(String(format: "%+.2f", tfAdjustment))")
            }
        }
        
        // Direction adjustment - aggressive penalty for failing directions
        let directionAccuracy: Double
        let directionCount: Int
        switch direction {
        case .bullish:
            directionAccuracy = metrics.bullishPredictions > 0 ? 
                Double(metrics.bullishCorrect) / Double(metrics.bullishPredictions) * 100 : 50
            directionCount = metrics.bullishPredictions
        case .bearish:
            directionAccuracy = metrics.bearishPredictions > 0 ?
                Double(metrics.bearishCorrect) / Double(metrics.bearishPredictions) * 100 : 50
            directionCount = metrics.bearishPredictions
        case .neutral:
            directionAccuracy = metrics.neutralPredictions > 0 ?
                Double(metrics.neutralCorrect) / Double(metrics.neutralPredictions) * 100 : 50
            directionCount = metrics.neutralPredictions
        }
        
        // Only apply if we have enough samples for this direction
        if directionCount >= 3 {
            // Strong penalty for direction accuracy below 30%
            if directionAccuracy < 30 {
                let dirPenalty = (30 - directionAccuracy) / 60  // Up to -0.5 for 0% accuracy
                multiplier -= dirPenalty
                print("[PredictionAccuracy] Direction \(direction.displayName) PENALTY: \(String(format: "%.2f", -dirPenalty)) (accuracy: \(String(format: "%.0f", directionAccuracy))%)")
            } else {
                let dirAdjustment = (directionAccuracy - 50) / 200  // Range: -0.25 to +0.25
                multiplier += dirAdjustment
                print("[PredictionAccuracy] Direction \(direction.displayName) accuracy: \(String(format: "%.0f", directionAccuracy))%, adjustment: \(String(format: "%+.2f", dirAdjustment))")
            }
        }
        
        // Symbol-specific adjustment (if available and requested)
        if let sym = symbol, let coinMetrics = metricsForCoin(sym) {
            let coinAccuracy = coinMetrics.directionAccuracyPercent
            // Lighter weight for coin-specific (may have small sample)
            let coinAdjustment = (coinAccuracy - 50) / 400  // Range: -0.125 to +0.125
            multiplier += coinAdjustment
            
            print("[PredictionAccuracy] Coin \(sym) accuracy: \(String(format: "%.0f", coinAccuracy))%, adjustment: \(String(format: "%+.2f", coinAdjustment))")
        }
        
        // Confidence calibration check - penalize if high confidence predictions are failing
        if let highConfAcc = metrics.highConfidenceAccuracy, highConfAcc < 50 {
            // High confidence predictions should be >50% accurate
            // If they're not, apply a penalty to all predictions
            let calibrationPenalty = (50 - highConfAcc) / 200  // Up to -0.25
            multiplier -= calibrationPenalty
            print("[PredictionAccuracy] Confidence calibration penalty: \(String(format: "%.2f", -calibrationPenalty)) (high conf accuracy: \(String(format: "%.0f", highConfAcc))%)")
        }
        
        // Clamp to reasonable range - allow lower floor for poor performers
        multiplier = max(0.5, min(1.2, multiplier))
        
        print("[PredictionAccuracy] Final confidence multiplier: \(String(format: "%.2f", multiplier))")
        
        return multiplier
    }
    
    /// Apply confidence adjustment to a raw confidence score
    /// - Parameters:
    ///   - rawConfidence: The original confidence score (0-100)
    ///   - symbol: The coin symbol
    ///   - timeframe: The prediction timeframe
    ///   - direction: The predicted direction
    /// - Returns: Adjusted confidence score (0-100)
    public func adjustConfidenceScore(
        _ rawConfidence: Int,
        for symbol: String? = nil,
        timeframe: PredictionTimeframe,
        direction: PredictionDirection
    ) -> Int {
        let multiplier = confidenceAdjustment(for: symbol, timeframe: timeframe, direction: direction)
        let adjusted = Double(rawConfidence) * multiplier
        let clamped = max(10, min(95, Int(adjusted)))  // Keep between 10-95
        
        if clamped != rawConfidence {
            print("[PredictionAccuracy] Adjusted confidence: \(rawConfidence) -> \(clamped) (multiplier: \(String(format: "%.2f", multiplier)))")
        }
        
        return clamped
    }
    
    /// Get structured accuracy conditions data for prediction context
    /// Returns information about when predictions work best/worst
    public func accuracyConditions() -> AccuracyConditions {
        // Find best/worst timeframes
        var bestTimeframe: (PredictionTimeframe, Double)? = nil
        var worstTimeframe: (PredictionTimeframe, Double)? = nil
        
        for (tf, tfMetrics) in metrics.metricsByTimeframe {
            guard tfMetrics.evaluatedPredictions >= 3 else { continue }
            
            if bestTimeframe.map({ tfMetrics.directionAccuracyPercent > $0.1 }) ?? true {
                bestTimeframe = (tf, tfMetrics.directionAccuracyPercent)
            }
            if worstTimeframe.map({ tfMetrics.directionAccuracyPercent < $0.1 }) ?? true {
                worstTimeframe = (tf, tfMetrics.directionAccuracyPercent)
            }
        }
        
        // Find best/worst direction
        var bestDirection: (PredictionDirection, Double)? = nil
        var worstDirection: (PredictionDirection, Double)? = nil
        
        let directions: [(PredictionDirection, Int, Int)] = [
            (.bullish, metrics.bullishPredictions, metrics.bullishCorrect),
            (.bearish, metrics.bearishPredictions, metrics.bearishCorrect),
            (.neutral, metrics.neutralPredictions, metrics.neutralCorrect)
        ]
        
        for (dir, total, correct) in directions {
            guard total >= 3 else { continue }
            let accuracy = Double(correct) / Double(total) * 100
            
            if bestDirection.map({ accuracy > $0.1 }) ?? true {
                bestDirection = (dir, accuracy)
            }
            if worstDirection.map({ accuracy < $0.1 }) ?? true {
                worstDirection = (dir, accuracy)
            }
        }
        
        // Confidence bracket analysis
        let highConfReliable = (metrics.highConfidenceAccuracy ?? 0) >= 65
        let lowConfUnreliable = (metrics.lowConfidenceAccuracy ?? 0) < 45
        
        return AccuracyConditions(
            totalEvaluated: metrics.evaluatedPredictions,
            overallAccuracy: metrics.directionAccuracyPercent,
            bestTimeframe: bestTimeframe,
            worstTimeframe: worstTimeframe,
            bestDirection: bestDirection,
            worstDirection: worstDirection,
            highConfidenceReliable: highConfReliable,
            lowConfidenceUnreliable: lowConfUnreliable,
            averageError: metrics.averagePriceError,
            highConfidenceAccuracy: metrics.highConfidenceAccuracy,
            mediumConfidenceAccuracy: metrics.mediumConfidenceAccuracy,
            lowConfidenceAccuracy: metrics.lowConfidenceAccuracy
        )
    }
    
    /// Get a summary string of accuracy context for AI prompts
    /// Enhanced with specific failure patterns and bias warnings
    public func accuracySummaryForPrompt(
        timeframe: PredictionTimeframe,
        direction: PredictionDirection? = nil
    ) -> String {
        guard metrics.evaluatedPredictions >= 5 else {
            return "Insufficient historical data for accuracy assessment."
        }
        
        var summary: [String] = []
        var warnings: [String] = []
        var recommendations: [String] = []
        
        // Basic accuracy stats
        summary.append("Historical accuracy: \(String(format: "%.0f", metrics.directionAccuracyPercent))% direction, \(String(format: "%.0f", metrics.rangeAccuracyPercent))% within range")
        
        // Timeframe-specific accuracy
        if let tfMetrics = metrics.metricsByTimeframe[timeframe] {
            summary.append("This timeframe (\(timeframe.displayName)): \(String(format: "%.0f", tfMetrics.directionAccuracyPercent))% accuracy (\(tfMetrics.evaluatedPredictions) samples)")
            
            // Warning for poor timeframe performance
            if tfMetrics.evaluatedPredictions >= 3 && tfMetrics.directionAccuracyPercent < 40 {
                warnings.append("WARNING: \(timeframe.displayName) timeframe has poor accuracy (\(String(format: "%.0f", tfMetrics.directionAccuracyPercent))%). Consider reducing confidence for this timeframe.")
            }
        }
        
        // Direction-specific analysis with failure pattern detection
        let bullishAcc = metrics.bullishPredictions > 0 ? Double(metrics.bullishCorrect) / Double(metrics.bullishPredictions) * 100 : -1
        let bearishAcc = metrics.bearishPredictions > 0 ? Double(metrics.bearishCorrect) / Double(metrics.bearishPredictions) * 100 : -1
        let neutralAcc = metrics.neutralPredictions > 0 ? Double(metrics.neutralCorrect) / Double(metrics.neutralPredictions) * 100 : -1
        
        // Report all direction accuracies
        if metrics.bullishPredictions >= 3 {
            summary.append("Bullish predictions: \(String(format: "%.0f", bullishAcc))% accuracy (\(metrics.bullishCorrect)/\(metrics.bullishPredictions))")
        }
        if metrics.bearishPredictions >= 3 {
            summary.append("Bearish predictions: \(String(format: "%.0f", bearishAcc))% accuracy (\(metrics.bearishCorrect)/\(metrics.bearishPredictions))")
        }
        if metrics.neutralPredictions >= 3 {
            summary.append("Neutral predictions: \(String(format: "%.0f", neutralAcc))% accuracy (\(metrics.neutralCorrect)/\(metrics.neutralPredictions))")
        }
        
        // BIAS DETECTION: Check for over-reliance on neutral predictions
        let totalDirectional = metrics.bullishPredictions + metrics.bearishPredictions + metrics.neutralPredictions
        if totalDirectional >= 5 {
            let neutralRatio = Double(metrics.neutralPredictions) / Double(totalDirectional)
            if neutralRatio > 0.5 {
                warnings.append("BIAS DETECTED: \(Int(neutralRatio * 100))% of predictions are Neutral. This may indicate over-caution. Consider making more decisive bullish/bearish calls when signals are clear.")
            }
            
            // Check if bullish predictions are consistently failing
            if metrics.bullishPredictions >= 3 && bullishAcc < 30 {
                warnings.append("FAILURE PATTERN: Bullish predictions have only \(String(format: "%.0f", bullishAcc))% accuracy. Use wider price ranges and lower confidence for bullish calls, but still make bullish calls when indicators support it — do NOT default to neutral instead.")
                recommendations.append("For bullish predictions: Widen the predicted price range and reduce confidence score, but still commit to the bullish direction when signals support it.")
            }
            
            // Check if bearish predictions are consistently failing
            if metrics.bearishPredictions >= 3 && bearishAcc < 30 {
                warnings.append("FAILURE PATTERN: Bearish predictions have only \(String(format: "%.0f", bearishAcc))% accuracy. Use wider price ranges and lower confidence for bearish calls, but still make bearish calls when indicators support it — do NOT default to neutral instead.")
                recommendations.append("For bearish predictions: Widen the predicted price range and reduce confidence score, but still commit to the bearish direction when signals support it.")
            }
            
            // Check for directional imbalance
            if metrics.bullishPredictions > 0 && metrics.bearishPredictions > 0 {
                let bullishRatio = Double(metrics.bullishPredictions) / Double(metrics.bullishPredictions + metrics.bearishPredictions)
                if bullishRatio > 0.75 {
                    warnings.append("IMBALANCE: Heavy bullish bias (\(Int(bullishRatio * 100))% bullish vs bearish). Review if market conditions justify this optimism.")
                } else if bullishRatio < 0.25 {
                    warnings.append("IMBALANCE: Heavy bearish bias (\(Int((1 - bullishRatio) * 100))% bearish vs bullish). Review if market conditions justify this pessimism.")
                }
            }
        }
        
        // Confidence level analysis
        if let highAcc = metrics.highConfidenceAccuracy {
            summary.append("High confidence (70+) predictions: \(String(format: "%.0f", highAcc))% accurate")
            if highAcc < 50 {
                warnings.append("CONFIDENCE CALIBRATION NEEDED: High confidence predictions are only \(String(format: "%.0f", highAcc))% accurate. Reduce confidence scores across the board.")
            }
        }
        
        if let _ = metrics.mediumConfidenceAccuracy, let lowAcc = metrics.lowConfidenceAccuracy {
            // Check if confidence correlates with accuracy (it should)
            if lowAcc > (metrics.highConfidenceAccuracy ?? 100) {
                warnings.append("CONFIDENCE INVERSION: Low confidence predictions (\(String(format: "%.0f", lowAcc))%) outperform high confidence ones. Re-evaluate what signals truly indicate high confidence.")
            }
        }
        
        summary.append("Average price error: \(String(format: "%.1f", metrics.averagePriceError))%")
        
        // Compile final output
        var output = summary.joined(separator: "\n")
        
        if !warnings.isEmpty {
            output += "\n\n--- ACCURACY WARNINGS ---\n"
            output += warnings.joined(separator: "\n")
        }
        
        if !recommendations.isEmpty {
            output += "\n\n--- RECOMMENDATIONS ---\n"
            output += recommendations.joined(separator: "\n")
        }
        
        return output
    }
    
    // MARK: - Metrics Calculation
    
    private func recalculateMetrics() {
        let evaluatedPredictions = storedPredictions.filter { $0.isEvaluated }
        metrics = calculateMetrics(from: evaluatedPredictions)
    }
    
    private func calculateMetrics(from predictions: [StoredPrediction]) -> AccuracyMetrics {
        guard !predictions.isEmpty else { return .empty }
        
        let evaluated = predictions.filter { $0.isEvaluated }
        guard !evaluated.isEmpty else { return .empty }
        
        // Direction accuracy
        let directionsCorrect = evaluated.filter { $0.directionCorrect == true }.count
        let directionAccuracy = Double(directionsCorrect) / Double(evaluated.count) * 100
        
        // Range accuracy
        let withinRange = evaluated.filter { $0.withinPriceRange == true }.count
        let rangeAccuracy = Double(withinRange) / Double(evaluated.count) * 100
        
        // Error metrics
        let errors = evaluated.compactMap { $0.priceError }
        let avgError = errors.isEmpty ? 0 : errors.reduce(0, +) / Double(errors.count)
        let medianError = errors.isEmpty ? 0 : errors.sorted()[errors.count / 2]
        
        // Direction breakdown
        let bullish = evaluated.filter { $0.predictedDirection == .bullish }
        let bearish = evaluated.filter { $0.predictedDirection == .bearish }
        let neutral = evaluated.filter { $0.predictedDirection == .neutral }
        
        // Timeframe breakdown
        var timeframeMetrics: [PredictionTimeframe: TimeframeMetrics] = [:]
        for tf in PredictionTimeframe.allCases {
            let tfPredictions = evaluated.filter { $0.timeframe == tf }
            guard !tfPredictions.isEmpty else { continue }
            
            let tfCorrect = tfPredictions.filter { $0.directionCorrect == true }.count
            let tfErrors = tfPredictions.compactMap { $0.priceError }
            
            timeframeMetrics[tf] = TimeframeMetrics(
                timeframe: tf,
                totalPredictions: predictions.filter { $0.timeframe == tf }.count,
                evaluatedPredictions: tfPredictions.count,
                directionsCorrect: tfCorrect,
                directionAccuracyPercent: Double(tfCorrect) / Double(tfPredictions.count) * 100,
                averagePriceError: tfErrors.isEmpty ? 0 : tfErrors.reduce(0, +) / Double(tfErrors.count)
            )
        }
        
        // Confidence breakdown - thresholds match PredictionConfidence.from()
        let highConf = evaluated.filter { $0.confidenceScore >= 70 }
        let medConf = evaluated.filter { $0.confidenceScore >= 45 && $0.confidenceScore < 70 }
        let lowConf = evaluated.filter { $0.confidenceScore < 45 }
        
        let highConfAcc = highConf.isEmpty ? nil : Double(highConf.filter { $0.directionCorrect == true }.count) / Double(highConf.count) * 100
        let medConfAcc = medConf.isEmpty ? nil : Double(medConf.filter { $0.directionCorrect == true }.count) / Double(medConf.count) * 100
        let lowConfAcc = lowConf.isEmpty ? nil : Double(lowConf.filter { $0.directionCorrect == true }.count) / Double(lowConf.count) * 100
        
        return AccuracyMetrics(
            totalPredictions: predictions.count,
            evaluatedPredictions: evaluated.count,
            directionsCorrect: directionsCorrect,
            directionAccuracyPercent: directionAccuracy,
            withinRangeCount: withinRange,
            rangeAccuracyPercent: rangeAccuracy,
            averagePriceError: avgError,
            medianPriceError: medianError,
            bullishPredictions: bullish.count,
            bullishCorrect: bullish.filter { $0.directionCorrect == true }.count,
            bearishPredictions: bearish.count,
            bearishCorrect: bearish.filter { $0.directionCorrect == true }.count,
            neutralPredictions: neutral.count,
            neutralCorrect: neutral.filter { $0.directionCorrect == true }.count,
            metricsByTimeframe: timeframeMetrics,
            highConfidenceAccuracy: highConfAcc,
            mediumConfidenceAccuracy: medConfAcc,
            lowConfidenceAccuracy: lowConfAcc
        )
    }
    
    // MARK: - Firebase Firestore Sync
    
    /// Key for caching Firestore permission denial (avoids wasted network requests on every launch)
    private static let permDeniedKey = "firestorePermsDenied_prediction_tracking"
    
    /// Start listening to Firestore for prediction data (cross-device sync)
    public func startFirestoreSyncIfAuthenticated() {
        guard let userId = FirebaseService.shared.currentUserId, !userId.isEmpty else {
            print("[PredictionAccuracy] No authenticated user - using local storage only")
            return
        }
        
        // Stop existing listener
        firestoreListener?.remove()
        
        let docRef = db.collection("users").document(userId).collection("prediction_tracking").document("data")
        
        firestoreListener = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                if error.localizedDescription.contains("Missing or insufficient permissions") {
                    print("[PredictionAccuracy] Firestore permissions not configured — using local storage only")
                    self.firestoreListener?.remove()
                    self.firestoreListener = nil
                    // Cache the denial to avoid retrying on next launch
                    UserDefaults.standard.set([
                        "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
                        "at": Date().timeIntervalSince1970
                    ], forKey: Self.permDeniedKey)
                } else {
                    print("[PredictionAccuracy] Firestore listener error: \(error.localizedDescription)")
                }
                return
            }
            
            // Permission succeeded — clear any cached denial
            UserDefaults.standard.removeObject(forKey: Self.permDeniedKey)
            
            guard let data = snapshot?.data(),
                  let predictionsArray = data["predictions"] as? [[String: Any]] else {
                // No data in Firestore yet — push local data up
                Task { @MainActor in
                    await self.pushToFirestore()
                }
                return
            }
            
            // Don't apply if we're the ones who pushed
            guard !self.isApplyingFirestoreUpdate else { return }
            
            // Merge Firestore data with local data
            Task { @MainActor in
                self.mergeFirestoreData(predictionsArray)
            }
        }
        
        #if DEBUG
        print("[PredictionAccuracy] Firestore sync started for user \(userId)")
        #endif
    }
    
    /// Stop Firestore listener and cancel pending tasks
    public func stopFirestoreSync() {
        firestoreListener?.remove()
        firestoreListener = nil
        scheduledEvaluationTask?.cancel()
        scheduledEvaluationTask = nil
        firestorePushTask?.cancel()
        firestorePushTask = nil
    }
    
    /// Debounce timer for Firestore pushes
    private var firestorePushTask: Task<Void, Never>?
    private var lastFirestorePush: Date?
    private let firestorePushCooldown: TimeInterval = 10 // Min 10s between pushes
    
    /// Debounced push — coalesces rapid pushes into a single write
    private func debouncedPushToFirestore() {
        firestorePushTask?.cancel()
        firestorePushTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s debounce
            guard !Task.isCancelled else { return }
            await pushToFirestore()
        }
    }
    
    /// Push local prediction data to Firestore
    private func pushToFirestore() async {
        guard let userId = FirebaseService.shared.currentUserId, !userId.isEmpty else { return }
        
        // Enforce cooldown
        if let lastPush = lastFirestorePush, Date().timeIntervalSince(lastPush) < firestorePushCooldown {
            return
        }
        
        isApplyingFirestoreUpdate = true
        defer { isApplyingFirestoreUpdate = false }
        lastFirestorePush = Date()
        
        let docRef = db.collection("users").document(userId).collection("prediction_tracking").document("data")
        
        // Encode predictions to dictionaries
        let predictionsData: [[String: Any]] = storedPredictions.compactMap { prediction in
            guard let data = try? JSONEncoder().encode(prediction),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return dict
        }
        
        let payload: [String: Any] = [
            "predictions": predictionsData,
            "lastUpdated": FieldValue.serverTimestamp(),
            "predictionCount": storedPredictions.count,
            "evaluatedCount": storedPredictions.filter { $0.isEvaluated }.count,
            "deviceId": UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        ]
        
        do {
            try await docRef.setData(payload, merge: true)
            #if DEBUG
            print("[PredictionAccuracy] Pushed \(storedPredictions.count) predictions to Firestore")
            #endif
        } catch {
            #if DEBUG
            print("[PredictionAccuracy] Firestore push failed: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Merge incoming Firestore predictions with local data
    private func mergeFirestoreData(_ predictionsArray: [[String: Any]]) {
        var merged = false
        
        for predDict in predictionsArray {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: predDict),
                  let prediction = try? JSONDecoder().decode(StoredPrediction.self, from: jsonData) else {
                continue
            }
            
            // Check if this prediction already exists locally
            if let localIndex = storedPredictions.firstIndex(where: { $0.id == prediction.id }) {
                // If Firestore version is evaluated but local isn't, use Firestore version
                if prediction.isEvaluated && !storedPredictions[localIndex].isEvaluated {
                    storedPredictions[localIndex] = prediction
                    merged = true
                }
            } else {
                // New prediction from another device — add it
                storedPredictions.append(prediction)
                merged = true
            }
        }
        
        if merged {
            pruneOldPredictions()
            recalculateMetrics()
            saveToStorage()
            print("[PredictionAccuracy] Merged Firestore data — now have \(storedPredictions.count) predictions")
        }
    }
    
    /// Record a completed evaluation to Firebase for global accuracy tracking
    private func recordEvaluationToFirebase(_ prediction: StoredPrediction) async {
        guard prediction.isEvaluated else { return }
        
        // Push updated local data to Firestore (per-user)
        await pushToFirestore()
        
        // Also record to global accuracy collection (anonymized)
        guard let userId = FirebaseService.shared.currentUserId else { return }
        
        let evaluationData: [String: Any] = [
            "coinSymbol": prediction.coinSymbol,
            "timeframe": prediction.timeframe.rawValue,
            "predictedDirection": prediction.predictedDirection.rawValue,
            "actualDirection": prediction.actualDirection?.rawValue ?? "unknown",
            "directionCorrect": prediction.directionCorrect ?? false,
            "withinPriceRange": prediction.withinPriceRange ?? false,
            "priceError": prediction.priceError ?? 0,
            "confidenceScore": prediction.confidenceScore,
            "predictedPriceChange": prediction.predictedPriceChange,
            "actualPriceChange": prediction.actualPriceChange ?? 0,
            "aiModelProvider": prediction.aiModelProvider ?? "unknown",
            "generatedAt": Timestamp(date: prediction.generatedAt),
            "evaluatedAt": Timestamp(date: prediction.evaluatedAt ?? Date()),
            "userId": userId  // For per-user aggregation only, not displayed
        ]
        
        do {
            try await db.collection("prediction_evaluations").addDocument(data: evaluationData)
            print("[PredictionAccuracy] Recorded evaluation to global Firebase collection")
        } catch {
            print("[PredictionAccuracy] Failed to record evaluation to Firebase: \(error.localizedDescription)")
        }
        
        // Update per-user accuracy summary in Firestore
        await updateUserAccuracySummary()
    }
    
    /// Update the user's aggregated accuracy summary in Firestore
    private func updateUserAccuracySummary() async {
        guard let userId = FirebaseService.shared.currentUserId else { return }
        
        let summaryData: [String: Any] = [
            "totalPredictions": metrics.totalPredictions,
            "evaluatedPredictions": metrics.evaluatedPredictions,
            "directionsCorrect": metrics.directionsCorrect,
            "directionAccuracyPercent": metrics.directionAccuracyPercent,
            "withinRangeCount": metrics.withinRangeCount,
            "rangeAccuracyPercent": metrics.rangeAccuracyPercent,
            "averagePriceError": metrics.averagePriceError,
            "bullishPredictions": metrics.bullishPredictions,
            "bullishCorrect": metrics.bullishCorrect,
            "bearishPredictions": metrics.bearishPredictions,
            "bearishCorrect": metrics.bearishCorrect,
            "neutralPredictions": metrics.neutralPredictions,
            "neutralCorrect": metrics.neutralCorrect,
            "lastUpdated": FieldValue.serverTimestamp()
        ]
        
        do {
            try await db.collection("users").document(userId)
                .collection("prediction_tracking").document("summary")
                .setData(summaryData, merge: true)
        } catch {
            print("[PredictionAccuracy] Failed to update accuracy summary: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Storage
    
    private func loadFromStorage() {
        // Load predictions
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([StoredPrediction].self, from: data) {
            storedPredictions = decoded
        }
        
        // Load metrics
        if let data = UserDefaults.standard.data(forKey: metricsKey),
           let decoded = try? JSONDecoder().decode(AccuracyMetrics.self, from: data) {
            metrics = decoded
        }
        
        // Load last evaluation date
        if let date = UserDefaults.standard.object(forKey: lastEvalKey) as? Date {
            lastEvaluationDate = date
        }
        
        // BUG FIX: Recalculate metrics from stored predictions to ensure consistency.
        // Previously, if metrics were saved in a stale state (or predictions were stored
        // but metrics weren't), the display would show 0% across the board after restart.
        if !storedPredictions.isEmpty {
            recalculateMetrics()
        }
        
        print("[PredictionAccuracy] Loaded \(storedPredictions.count) predictions, \(metrics.evaluatedPredictions) evaluated")
    }
    
    private func saveToStorage() {
        // Save predictions
        if let encoded = try? JSONEncoder().encode(storedPredictions) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
        
        // Save metrics
        if let encoded = try? JSONEncoder().encode(metrics) {
            UserDefaults.standard.set(encoded, forKey: metricsKey)
        }
        
        // Save last evaluation date
        if let date = lastEvaluationDate {
            UserDefaults.standard.set(date, forKey: lastEvalKey)
        }
    }
    
    // MARK: - Learning Feedback (Past Predictions Improve Future)
    
    /// Get detailed learning insights from past predictions
    /// This data is injected into the AI prompt to help calibrate future predictions
    public func learningInsights(for symbol: String? = nil, timeframe: PredictionTimeframe? = nil) -> PredictionLearningInsights {
        let evaluatedPreds = storedPredictions.filter { $0.isEvaluated }
        guard !evaluatedPreds.isEmpty else {
            return PredictionLearningInsights.empty
        }
        
        // Filter by symbol and timeframe if provided
        var relevantPreds = evaluatedPreds
        if let sym = symbol {
            let symFiltered = evaluatedPreds.filter { $0.coinSymbol.uppercased() == sym.uppercased() }
            if symFiltered.count >= 2 { relevantPreds = symFiltered }
        }
        if let tf = timeframe {
            let tfFiltered = relevantPreds.filter { $0.timeframe == tf }
            if tfFiltered.count >= 2 { relevantPreds = tfFiltered }
        }
        
        // Analyze common failure patterns
        let failedPreds = relevantPreds.filter { $0.directionCorrect == false }
        let successPreds = relevantPreds.filter { $0.directionCorrect == true }
        
        // Analyze confidence calibration
        let highConfPreds = relevantPreds.filter { $0.confidenceScore >= 70 }
        let highConfCorrect = highConfPreds.filter { $0.directionCorrect == true }.count
        let highConfAccuracy = highConfPreds.isEmpty ? 0.0 : Double(highConfCorrect) / Double(highConfPreds.count) * 100
        
        let lowConfPreds = relevantPreds.filter { $0.confidenceScore < 45 }
        let lowConfCorrect = lowConfPreds.filter { $0.directionCorrect == true }.count
        let lowConfAccuracy = lowConfPreds.isEmpty ? 0.0 : Double(lowConfCorrect) / Double(lowConfPreds.count) * 100
        
        // Analyze overestimation vs underestimation
        let overestimates = relevantPreds.filter {
            guard let actual = $0.actualPriceChange else { return false }
            return $0.predictedPriceChange > actual && abs($0.predictedPriceChange - actual) > 1
        }
        let underestimates = relevantPreds.filter {
            guard let actual = $0.actualPriceChange else { return false }
            return $0.predictedPriceChange < actual && abs($0.predictedPriceChange - actual) > 1
        }
        
        // Average predicted vs actual magnitude
        let avgPredictedMagnitude = relevantPreds.map { abs($0.predictedPriceChange) }.reduce(0, +) / max(1, Double(relevantPreds.count))
        let avgActualMagnitude = relevantPreds.compactMap { $0.actualPriceChange }.map { abs($0) }.reduce(0, +) / max(1, Double(relevantPreds.count))
        
        // Recent trend (last 5 predictions)
        let recent = relevantPreds.sorted { ($0.evaluatedAt ?? .distantPast) > ($1.evaluatedAt ?? .distantPast) }.prefix(5)
        let recentCorrect = recent.filter { $0.directionCorrect == true }.count
        let recentAccuracy = recent.isEmpty ? 0.0 : Double(recentCorrect) / Double(recent.count) * 100
        
        return PredictionLearningInsights(
            totalEvaluated: relevantPreds.count,
            overallAccuracy: relevantPreds.isEmpty ? 0 : Double(successPreds.count) / Double(relevantPreds.count) * 100,
            recentAccuracy: recentAccuracy,
            highConfidenceAccuracy: highConfAccuracy,
            lowConfidenceAccuracy: lowConfAccuracy,
            overestimateCount: overestimates.count,
            underestimateCount: underestimates.count,
            avgPredictedMagnitude: avgPredictedMagnitude,
            avgActualMagnitude: avgActualMagnitude,
            failedPredictionCount: failedPreds.count,
            successPredictionCount: successPreds.count,
            confidenceCalibrationOff: highConfAccuracy < lowConfAccuracy && highConfPreds.count >= 3,
            tendToOverpredict: avgPredictedMagnitude > avgActualMagnitude * 1.3,
            tendToUnderpredict: avgActualMagnitude > avgPredictedMagnitude * 1.3
        )
    }
    
    private func pruneOldPredictions() {
        guard storedPredictions.count > maxStoredPredictions else { return }
        
        // Sort by date and keep most recent
        storedPredictions.sort { $0.generatedAt > $1.generatedAt }
        storedPredictions = Array(storedPredictions.prefix(maxStoredPredictions))
        
        print("[PredictionAccuracy] Pruned to \(storedPredictions.count) predictions")
    }
    
    // MARK: - Cloud Sync (Future Implementation)
    
    /// Cloud sync provider (set to actual implementation when ready)
    private var cloudSyncProvider: AccuracyCloudSyncProvider = PlaceholderCloudSyncProvider.shared
    
    /// Global accuracy metrics from cloud (when available)
    @Published public private(set) var globalMetrics: GlobalAccuracyMetrics?
    
    /// Whether cloud sync is enabled
    public var isCloudSyncEnabled: Bool {
        cloudSyncProvider.isEnabled
    }
    
    /// Prepare anonymized data for cloud contribution
    /// Call this when uploading local metrics to contribute to global learning
    public func prepareCloudContribution() -> AnonymizedAccuracyData {
        // Create timeframe contribution data
        var timeframeContribs: [String: TimeframeContribution] = [:]
        for (tf, tfMetrics) in metrics.metricsByTimeframe {
            timeframeContribs[tf.rawValue] = TimeframeContribution(
                total: tfMetrics.evaluatedPredictions,
                correct: tfMetrics.directionsCorrect
            )
        }
        
        // Create direction contribution data
        let directionContribs: [String: DirectionContribution] = [
            "bullish": DirectionContribution(total: metrics.bullishPredictions, correct: metrics.bullishCorrect),
            "bearish": DirectionContribution(total: metrics.bearishPredictions, correct: metrics.bearishCorrect),
            "neutral": DirectionContribution(total: metrics.neutralPredictions, correct: metrics.neutralCorrect)
        ]
        
        let contribution = AccuracyContribution(
            evaluatedCount: metrics.evaluatedPredictions,
            directionsCorrect: metrics.directionsCorrect,
            withinRangeCount: metrics.withinRangeCount,
            byTimeframe: timeframeContribs,
            byDirection: directionContribs
        )
        
        return AnonymizedAccuracyData(
            sessionId: UUID().uuidString,  // Random ID, not tied to user
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            metrics: contribution,
            timestamp: Date()
        )
    }
    
    /// Fetch global metrics from cloud (when implemented)
    public func fetchGlobalMetrics() async {
        guard cloudSyncProvider.isEnabled else { return }
        
        do {
            let global = try await cloudSyncProvider.fetchGlobalMetrics()
            await MainActor.run {
                self.globalMetrics = global
            }
            print("[PredictionAccuracy] Fetched global metrics: \(global.totalPredictions) total predictions")
        } catch {
            print("[PredictionAccuracy] Failed to fetch global metrics: \(error)")
        }
    }
    
    /// Upload local metrics to contribute to global learning (when implemented)
    public func contributeToGlobalLearning() async {
        guard cloudSyncProvider.isEnabled else { return }
        guard metrics.evaluatedPredictions >= 10 else {
            print("[PredictionAccuracy] Not enough local data to contribute (need 10+)")
            return
        }
        
        let contribution = prepareCloudContribution()
        
        do {
            try await cloudSyncProvider.uploadLocalMetrics(contribution)
            print("[PredictionAccuracy] Contributed local metrics to global learning")
        } catch {
            print("[PredictionAccuracy] Failed to upload metrics: \(error)")
        }
    }
    
    /// Set the cloud sync provider (call this when backend is ready)
    public func setCloudSyncProvider(_ provider: AccuracyCloudSyncProvider) {
        self.cloudSyncProvider = provider
    }
    
    /// Get enhanced accuracy summary including global data (when available)
    public func accuracySummaryWithGlobalContext(
        timeframe: PredictionTimeframe,
        direction: PredictionDirection? = nil
    ) -> String {
        var summary = accuracySummaryForPrompt(timeframe: timeframe, direction: direction)
        
        // Add global context if available
        if let global = globalMetrics, global.isReliable {
            summary += "\n\n--- GLOBAL ACCURACY DATA (from \(global.totalPredictions) predictions across all users) ---"
            summary += "\nGlobal direction accuracy: \(String(format: "%.0f", global.globalDirectionAccuracy))%"
            summary += "\nGlobal range accuracy: \(String(format: "%.0f", global.globalRangeAccuracy))%"
            
            if let tfAcc = global.timeframeAccuracy[timeframe.rawValue] {
                summary += "\nGlobal \(timeframe.displayName) accuracy: \(String(format: "%.0f", tfAcc))%"
            }
            
            if let dir = direction, let dirAcc = global.directionAccuracy[dir.rawValue] {
                summary += "\nGlobal \(dir.displayName) accuracy: \(String(format: "%.0f", dirAcc))%"
            }
            
            // Add market condition insights if available
            if let insights = global.marketConditionInsights {
                for insight in insights where insight.sampleSize >= 100 {
                    summary += "\n\(insight.condition): \(String(format: "%.0f", insight.accuracy))% accuracy"
                    if let rec = insight.recommendation {
                        summary += " - \(rec)"
                    }
                }
            }
        }
        
        return summary
    }
}
