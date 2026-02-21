//
//  CommunityAccuracyService.swift
//  CryptoSage
//
//  CloudKit-based community accuracy sync service.
//  Enables shared learning across all users while preserving privacy.
//
//  How it works:
//  1. Users opt-in to contribute their anonymized accuracy data
//  2. All users can view aggregated community accuracy metrics
//  3. The AI uses both personal AND community data for better predictions
//  4. No personal information is ever shared - only aggregate statistics
//

import Foundation
import CloudKit
import SwiftUI
import Combine

// MARK: - Errors

/// Errors that can occur during community accuracy operations
public enum CommunityAccuracyError: LocalizedError {
    case cloudKitNotAvailable
    case notSignedIn
    case networkError(String)
    case recordNotFound
    
    public var errorDescription: String? {
        switch self {
        case .cloudKitNotAvailable:
            return "iCloud is not available. Please sign in to iCloud in Settings."
        case .notSignedIn:
            return "Please sign in to iCloud to contribute community data."
        case .networkError(let message):
            return "Network error: \(message)"
        case .recordNotFound:
            return "Community data not found."
        }
    }
}

// MARK: - Community Accuracy Models

/// Aggregated accuracy metrics from the entire community
public struct CommunityAccuracyMetrics: Codable {
    /// Total number of predictions evaluated across all users
    public let totalPredictions: Int
    
    /// Number of unique contributors
    public let contributorCount: Int
    
    /// Overall direction accuracy (percentage)
    public let directionAccuracy: Double
    
    /// Overall range accuracy (percentage)
    public let rangeAccuracy: Double
    
    /// Average price prediction error (percentage)
    public let averageError: Double
    
    /// Accuracy breakdown by timeframe
    public let timeframeAccuracy: [String: TimeframeStats]
    
    /// Accuracy breakdown by direction
    public let directionBreakdown: DirectionBreakdown
    
    /// When these metrics were last updated
    public let lastUpdated: Date
    
    /// Whether we have enough data for reliable metrics (1000+ predictions)
    public var isReliable: Bool {
        totalPredictions >= 1000
    }
    
    /// Whether we have any meaningful data (100+ predictions)
    public var hasData: Bool {
        totalPredictions >= 100
    }
    
    /// Empty/default metrics
    public static var empty: CommunityAccuracyMetrics {
        CommunityAccuracyMetrics(
            totalPredictions: 0,
            contributorCount: 0,
            directionAccuracy: 0,
            rangeAccuracy: 0,
            averageError: 0,
            timeframeAccuracy: [:],
            directionBreakdown: DirectionBreakdown(
                bullish: DirectionStats(total: 0, correct: 0),
                bearish: DirectionStats(total: 0, correct: 0),
                neutral: DirectionStats(total: 0, correct: 0)
            ),
            lastUpdated: Date.distantPast
        )
    }
    
    /// Whether these metrics are baseline (reference) data, not real community data
    public var isBaseline: Bool {
        // Baseline data has exactly these contributor counts and is not from cloud
        contributorCount == 0 && totalPredictions == 0
    }
    
    /// Baseline community metrics — returns empty when no real data is available.
    /// We no longer fabricate fake prediction counts. The UI should handle the
    /// "no community data" state gracefully instead of showing misleading numbers.
    public static var baseline: CommunityAccuracyMetrics {
        .empty
    }
}

/// Stats for a specific timeframe
public struct TimeframeStats: Codable {
    public let total: Int
    public let correct: Int
    public let accuracy: Double
}

/// Breakdown by prediction direction
public struct DirectionBreakdown: Codable {
    public let bullish: DirectionStats
    public let bearish: DirectionStats
    public let neutral: DirectionStats
}

/// Stats for a specific direction
public struct DirectionStats: Codable {
    public let total: Int
    public let correct: Int
    
    public var accuracy: Double {
        guard total > 0 else { return 0 }
        return Double(correct) / Double(total) * 100
    }
}

/// A single contribution record (anonymized)
public struct AccuracyContributionRecord: Codable {
    public let id: String
    public let appVersion: String
    public let timestamp: Date
    
    // Aggregate stats only - no personal data
    public let evaluatedCount: Int
    public let directionsCorrect: Int
    public let withinRangeCount: Int
    public let totalPriceError: Double  // Sum of all errors for averaging
    
    // Breakdown by timeframe
    public let timeframe1h: TimeframeContrib?
    public let timeframe4h: TimeframeContrib?
    public let timeframe24h: TimeframeContrib?
    public let timeframe7d: TimeframeContrib?
    public let timeframe30d: TimeframeContrib?
    
    // Breakdown by direction
    public let bullishTotal: Int
    public let bullishCorrect: Int
    public let bearishTotal: Int
    public let bearishCorrect: Int
    public let neutralTotal: Int
    public let neutralCorrect: Int
}

/// Timeframe contribution data
public struct TimeframeContrib: Codable {
    public let total: Int
    public let correct: Int
}

// MARK: - Community Accuracy Service

@MainActor
public final class CommunityAccuracyService: ObservableObject {
    public static let shared = CommunityAccuracyService()
    
    // MARK: - Published Properties
    
    /// Community-wide accuracy metrics
    @Published public private(set) var communityMetrics: CommunityAccuracyMetrics = .empty
    
    /// Whether the user has opted in to contribute their data
    @Published public var isContributionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isContributionEnabled, forKey: contributionEnabledKey)
            if isContributionEnabled {
                // Contribute immediately when user opts in
                Task { await contributeLocalData() }
            }
        }
    }
    
    /// Whether we're currently syncing
    @Published public private(set) var isSyncing: Bool = false
    
    /// Last sync date
    @Published public private(set) var lastSyncDate: Date?
    
    /// Last contribution date
    @Published public private(set) var lastContributionDate: Date?
    
    /// Error message if sync failed
    @Published public private(set) var syncError: String?
    
    // MARK: - Private Properties
    
    // CloudKit community sync is DISABLED.
    // 
    // Despite proper Apple Developer Portal setup, CloudKit causes EXC_BREAKPOINT
    // crashes due to provisioning profile issues that are difficult to resolve.
    // 
    // The app works perfectly without it:
    //   - Personal accuracy tracking: ✅ Works locally
    //   - Community data: ✅ Uses baseline reference data
    //   - AI calibration: ✅ Uses both personal + baseline data
    //
    // Live community sync can be enabled in a future update once CloudKit
    // provisioning issues are resolved at the Apple Developer Portal level.
    private let cloudKitEnabled = false
    
    // PERFORMANCE: Lazy CloudKit initialization to avoid blocking on startup
    private var _container: CKContainer?
    private var _publicDatabase: CKDatabase?
    private var _cloudKitAvailable: Bool?
    
    private var container: CKContainer? {
        // SAFETY: Never access CKContainer when CloudKit is disabled
        guard cloudKitEnabled else { return nil }
        if _container == nil {
            _container = CKContainer.default()
        }
        return _container
    }
    
    private var publicDatabase: CKDatabase? {
        // SAFETY: Never access CKDatabase when CloudKit is disabled
        guard cloudKitEnabled, let cont = container else { return nil }
        if _publicDatabase == nil {
            _publicDatabase = cont.publicCloudDatabase
        }
        return _publicDatabase
    }
    
    /// Check if CloudKit is available (entitlements configured correctly)
    /// SAFETY: This property defaults to false until checkCloudKitAvailability() is called.
    /// Never access CKContainer.containerIdentifier synchronously - it can crash with EXC_BREAKPOINT.
    public var isCloudKitAvailable: Bool {
        return _cloudKitAvailable ?? false
    }
    
    /// Safely check CloudKit availability.
    /// 
    /// ⚠️ IMPORTANT: When cloudKitEnabled = false, this method does NOT call any CloudKit APIs.
    /// This is critical because CKContainer APIs will crash with EXC_BREAKPOINT if the
    /// provisioning profile doesn't have CloudKit enabled - and Swift cannot catch this.
    ///
    /// When cloudKitEnabled = true, uses the async accountStatus() API with timeout.
    public func checkCloudKitAvailability() async {
        // SAFETY FIRST: If CloudKit feature is disabled, don't touch ANY CloudKit APIs
        // This prevents EXC_BREAKPOINT crashes when provisioning profile lacks CloudKit
        guard cloudKitEnabled else {
            _cloudKitAvailable = false
            print("[CommunityAccuracy] CloudKit DISABLED - using local learning with baseline community data")
            return
        }
        
        // Already checked - skip
        if _cloudKitAvailable != nil {
            return
        }
        
        // Use a timeout to prevent blocking on slow/unavailable network
        do {
            let available = try await withThrowingTaskGroup(of: Bool.self) { group in
                // Task 1: Check CloudKit status
                group.addTask {
                    let status = try await CKContainer.default().accountStatus()
                    return status == .available
                }
                
                // Task 2: Timeout after 10 seconds
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    throw CommunityAccuracyError.networkError("CloudKit check timed out")
                }
                
                // Return first result, cancel the other
                guard let result = try await group.next() else {
                    return false
                }
                group.cancelAll()
                return result
            }
            
            await MainActor.run {
                self._cloudKitAvailable = available
            }
            
            if available {
                print("[CommunityAccuracy] ✅ CloudKit is available - community learning enabled")
            } else {
                print("[CommunityAccuracy] ⚠️ CloudKit not available - using local/baseline data")
            }
        } catch {
            // If we can't even check status, CloudKit is definitely not available
            await MainActor.run {
                self._cloudKitAvailable = false
            }
            print("[CommunityAccuracy] ⚠️ CloudKit check failed: \(error.localizedDescription) - using local/baseline data")
        }
    }
    
    private let contributionEnabledKey = "CommunityAccuracy.ContributionEnabled"
    private let cachedMetricsKey = "CommunityAccuracy.CachedMetrics"
    private let lastSyncKey = "CommunityAccuracy.LastSync"
    private let lastContributionKey = "CommunityAccuracy.LastContribution"
    private let contributionIdKey = "CommunityAccuracy.ContributionId"
    
    /// Minimum time between contributions (24 hours)
    private let contributionCooldown: TimeInterval = 24 * 60 * 60
    
    /// Minimum time between fetches (1 hour)
    private let fetchCooldown: TimeInterval = 60 * 60
    
    // CloudKit record types
    private let contributionRecordType = "AccuracyContribution"
    private let aggregateRecordType = "CommunityAggregate"
    
    // MARK: - Initialization
    
    private init() {
        // PERFORMANCE: CloudKit initialization is now LAZY - deferred until first actual use
        // This prevents blocking the main thread on startup if entitlements are missing
        
        // Load saved preferences (local only - no CloudKit)
        self.isContributionEnabled = UserDefaults.standard.bool(forKey: contributionEnabledKey)
        
        // Load cached metrics (local only - no CloudKit)
        loadCachedMetrics()
        
        // Load last sync/contribution dates (local only - no CloudKit)
        if let syncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            self.lastSyncDate = syncDate
        }
        if let contribDate = UserDefaults.standard.object(forKey: lastContributionKey) as? Date {
            self.lastContributionDate = contribDate
        }
    }
    
    // MARK: - Public API
    
    /// Fetch community metrics (respects cooldown unless forced)
    /// Includes a 30-second timeout to prevent hanging on slow networks
    public func fetchCommunityMetrics(force: Bool = false) async {
        // PERFORMANCE: Skip if CloudKit not available (avoids blocking/errors)
        guard isCloudKitAvailable else {
            print("[CommunityAccuracy] CloudKit not available - using cached/baseline metrics")
            return
        }
        
        // Check cooldown unless forced
        if !force, let lastSync = lastSyncDate {
            let elapsed = Date().timeIntervalSince(lastSync)
            if elapsed < fetchCooldown {
                print("[CommunityAccuracy] Skipping fetch - cooldown active (\(Int(fetchCooldown - elapsed))s remaining)")
                return
            }
        }
        
        guard !isSyncing else { return }
        
        isSyncing = true
        syncError = nil
        
        defer { isSyncing = false }
        
        do {
            // Fetch with timeout to prevent hanging
            let metrics = try await withThrowingTaskGroup(of: CommunityAccuracyMetrics.self) { group in
                group.addTask {
                    try await self.fetchAggregateMetrics()
                }
                
                group.addTask {
                    try await Task.sleep(nanoseconds: 30_000_000_000) // 30 second timeout
                    throw CommunityAccuracyError.networkError("Fetch timed out")
                }
                
                guard let result = try await group.next() else {
                    return CommunityAccuracyMetrics.baseline
                }
                group.cancelAll()
                return result
            }
            
            await MainActor.run {
                self.communityMetrics = metrics
                self.lastSyncDate = Date()
                self.syncError = nil
            }
            
            // Cache the metrics
            saveCachedMetrics()
            UserDefaults.standard.set(Date(), forKey: lastSyncKey)
            
            print("[CommunityAccuracy] ✅ Fetched community metrics: \(metrics.totalPredictions) predictions from \(metrics.contributorCount) contributors")
            
        } catch {
            print("[CommunityAccuracy] ⚠️ Fetch error: \(error.localizedDescription) - keeping cached/baseline data")
            await MainActor.run {
                self.syncError = error.localizedDescription
            }
            // Don't clear existing metrics on error - keep cached/baseline data
        }
    }
    
    /// Contribute local accuracy data to the community (if opted in)
    /// Includes a 30-second timeout to prevent hanging on slow networks
    public func contributeLocalData() async {
        // PERFORMANCE: Skip if CloudKit not available
        guard isCloudKitAvailable else {
            print("[CommunityAccuracy] CloudKit not available - cannot contribute")
            return
        }
        
        guard isContributionEnabled else {
            print("[CommunityAccuracy] Contribution disabled - skipping")
            return
        }
        
        // Check cooldown
        if let lastContrib = lastContributionDate {
            let elapsed = Date().timeIntervalSince(lastContrib)
            if elapsed < contributionCooldown {
                print("[CommunityAccuracy] Skipping contribution - cooldown active (\(Int((contributionCooldown - elapsed) / 3600))h remaining)")
                return
            }
        }
        
        let localMetrics = PredictionAccuracyService.shared.metrics
        
        // Need at least 5 evaluated predictions to contribute
        guard localMetrics.evaluatedPredictions >= 5 else {
            print("[CommunityAccuracy] Not enough local data to contribute (need 5+)")
            return
        }
        
        do {
            // Upload with timeout
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.uploadContribution(from: localMetrics)
                }
                
                group.addTask {
                    try await Task.sleep(nanoseconds: 30_000_000_000) // 30 second timeout
                    throw CommunityAccuracyError.networkError("Upload timed out")
                }
                
                // Wait for upload to complete or timeout
                _ = try await group.next()
                group.cancelAll()
            }
            
            await MainActor.run {
                self.lastContributionDate = Date()
            }
            UserDefaults.standard.set(Date(), forKey: lastContributionKey)
            
            print("[CommunityAccuracy] ✅ Successfully contributed \(localMetrics.evaluatedPredictions) predictions to community")
            
            // Refresh community metrics after contributing
            await fetchCommunityMetrics(force: true)
            
        } catch {
            print("[CommunityAccuracy] ⚠️ Contribution error: \(error.localizedDescription) - will retry later")
        }
    }
    
    /// Sync both directions - fetch and contribute if needed
    public func sync() async {
        await fetchCommunityMetrics()
        
        if isContributionEnabled {
            await contributeLocalData()
        }
    }
    
    // MARK: - CloudKit Operations
    
    private func fetchAggregateMetrics() async throws -> CommunityAccuracyMetrics {
        // SAFETY: If CloudKit is disabled, return baseline immediately
        guard let db = publicDatabase else {
            print("[CommunityAccuracy] CloudKit disabled - using baseline data")
            return .baseline
        }
        
        // First, try to fetch the pre-computed aggregate record
        do {
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: aggregateRecordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
            
            let (results, _) = try await db.records(matching: query, resultsLimit: 1)
            
            if let (_, result) = results.first,
               let record = try? result.get() {
                let metrics = parseAggregateRecord(record)
                if metrics.totalPredictions > 0 {
                    print("[CommunityAccuracy] Using pre-computed aggregate: \(metrics.totalPredictions) predictions")
                    return metrics
                }
            }
        } catch {
            print("[CommunityAccuracy] Failed to fetch aggregate: \(error.localizedDescription)")
        }
        
        // Fallback: Try to aggregate from individual contributions
        do {
            let aggregated = try await aggregateFromContributions()
            if aggregated.totalPredictions > 0 {
                print("[CommunityAccuracy] Aggregated from contributions: \(aggregated.totalPredictions) predictions")
                return aggregated
            }
        } catch {
            print("[CommunityAccuracy] Failed to aggregate contributions: \(error.localizedDescription)")
        }
        
        // Final fallback: No real community data available
        print("[CommunityAccuracy] No community data available (CloudKit not configured or no contributions)")
        return .empty
    }
    
    /// Aggregate metrics from all contribution records (on-device aggregation)
    /// This is used when no pre-computed aggregate exists
    private func aggregateFromContributions() async throws -> CommunityAccuracyMetrics {
        // SAFETY: If CloudKit is disabled, return empty
        guard let db = publicDatabase else {
            return .empty
        }
        
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: contributionRecordType, predicate: predicate)
        
        let (results, _) = try await db.records(matching: query, resultsLimit: 100)
        
        guard !results.isEmpty else {
            return .empty
        }
        
        // Aggregate all contributions
        var totalPredictions = 0
        var totalDirectionsCorrect = 0
        var totalWithinRange = 0
        var totalPriceError: Double = 0
        var contributorCount = 0
        
        var timeframeTotals: [String: (total: Int, correct: Int)] = [:]
        var bullishTotal = 0, bullishCorrect = 0
        var bearishTotal = 0, bearishCorrect = 0
        var neutralTotal = 0, neutralCorrect = 0
        
        for (_, result) in results {
            guard let record = try? result.get() else { continue }
            
            let evaluated = record["evaluatedCount"] as? Int ?? 0
            let correct = record["directionsCorrect"] as? Int ?? 0
            let inRange = record["withinRangeCount"] as? Int ?? 0
            let errorSum = record["totalPriceError"] as? Double ?? 0
            
            totalPredictions += evaluated
            totalDirectionsCorrect += correct
            totalWithinRange += inRange
            totalPriceError += errorSum
            contributorCount += 1
            
            // Timeframe breakdown
            for tf in ["1h", "4h", "1d", "7d", "30d"] {
                let tfTotal = record["\(tf)_total"] as? Int ?? 0
                let tfCorrect = record["\(tf)_correct"] as? Int ?? 0
                let existing = timeframeTotals[tf] ?? (0, 0)
                timeframeTotals[tf] = (existing.total + tfTotal, existing.correct + tfCorrect)
            }
            
            // Direction breakdown
            bullishTotal += record["bullishTotal"] as? Int ?? 0
            bullishCorrect += record["bullishCorrect"] as? Int ?? 0
            bearishTotal += record["bearishTotal"] as? Int ?? 0
            bearishCorrect += record["bearishCorrect"] as? Int ?? 0
            neutralTotal += record["neutralTotal"] as? Int ?? 0
            neutralCorrect += record["neutralCorrect"] as? Int ?? 0
        }
        
        guard totalPredictions > 0 else { return .empty }
        
        // Calculate aggregated metrics
        let directionAccuracy = Double(totalDirectionsCorrect) / Double(totalPredictions) * 100
        let rangeAccuracy = Double(totalWithinRange) / Double(totalPredictions) * 100
        let averageError = totalPriceError / Double(totalPredictions)
        
        var timeframeAccuracy: [String: TimeframeStats] = [:]
        for (tf, stats) in timeframeTotals where stats.total > 0 {
            let acc = Double(stats.correct) / Double(stats.total) * 100
            timeframeAccuracy[tf] = TimeframeStats(total: stats.total, correct: stats.correct, accuracy: acc)
        }
        
        return CommunityAccuracyMetrics(
            totalPredictions: totalPredictions,
            contributorCount: contributorCount,
            directionAccuracy: directionAccuracy,
            rangeAccuracy: rangeAccuracy,
            averageError: averageError,
            timeframeAccuracy: timeframeAccuracy,
            directionBreakdown: DirectionBreakdown(
                bullish: DirectionStats(total: bullishTotal, correct: bullishCorrect),
                bearish: DirectionStats(total: bearishTotal, correct: bearishCorrect),
                neutral: DirectionStats(total: neutralTotal, correct: neutralCorrect)
            ),
            lastUpdated: Date()
        )
    }
    
    private func uploadContribution(from metrics: AccuracyMetrics) async throws {
        // SAFETY: If CloudKit is disabled, throw immediately
        guard let cont = container, let db = publicDatabase else {
            print("[CommunityAccuracy] CloudKit disabled - cannot upload contribution")
            throw CommunityAccuracyError.cloudKitNotAvailable
        }
        
        // Check CloudKit availability first
        let accountStatus = try await cont.accountStatus()
        guard accountStatus == .available else {
            print("[CommunityAccuracy] CloudKit not available (status: \(accountStatus))")
            throw CommunityAccuracyError.cloudKitNotAvailable
        }
        
        // Get or create a stable contribution ID for this device
        // This allows us to update rather than duplicate
        let contributionId = getOrCreateContributionId()
        
        let recordID = CKRecord.ID(recordName: contributionId)
        
        // Try to fetch existing record to update, or create new
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
            print("[CommunityAccuracy] Updating existing contribution record")
        } catch {
            // Record doesn't exist, create new
            record = CKRecord(recordType: contributionRecordType, recordID: recordID)
            print("[CommunityAccuracy] Creating new contribution record")
        }
        
        // Populate record with anonymized data
        record["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        record["timestamp"] = Date()
        record["evaluatedCount"] = metrics.evaluatedPredictions
        record["directionsCorrect"] = metrics.directionsCorrect
        record["withinRangeCount"] = metrics.withinRangeCount
        record["totalPriceError"] = metrics.averagePriceError * Double(metrics.evaluatedPredictions)
        
        // Timeframe breakdown
        for (tf, tfMetrics) in metrics.metricsByTimeframe {
            record["\(tf.rawValue)_total"] = tfMetrics.evaluatedPredictions
            record["\(tf.rawValue)_correct"] = tfMetrics.directionsCorrect
        }
        
        // Direction breakdown
        record["bullishTotal"] = metrics.bullishPredictions
        record["bullishCorrect"] = metrics.bullishCorrect
        record["bearishTotal"] = metrics.bearishPredictions
        record["bearishCorrect"] = metrics.bearishCorrect
        record["neutralTotal"] = metrics.neutralPredictions
        record["neutralCorrect"] = metrics.neutralCorrect
        
        // Save the record
        try await db.save(record)
        
        // Trigger aggregate recalculation (in production, this would be a CloudKit subscription/trigger)
        // For now, we'll do a simple aggregation on-device when fetching
    }
    
    private func parseAggregateRecord(_ record: CKRecord) -> CommunityAccuracyMetrics {
        let totalPredictions = record["totalPredictions"] as? Int ?? 0
        let contributorCount = record["contributorCount"] as? Int ?? 0
        let directionsCorrect = record["directionsCorrect"] as? Int ?? 0
        let withinRangeCount = record["withinRangeCount"] as? Int ?? 0
        let totalPriceError = record["totalPriceError"] as? Double ?? 0
        
        let directionAccuracy = totalPredictions > 0 ? Double(directionsCorrect) / Double(totalPredictions) * 100 : 0
        let rangeAccuracy = totalPredictions > 0 ? Double(withinRangeCount) / Double(totalPredictions) * 100 : 0
        let averageError = totalPredictions > 0 ? totalPriceError / Double(totalPredictions) : 0
        
        // Parse timeframe stats
        var timeframeAccuracy: [String: TimeframeStats] = [:]
        for tf in ["1h", "4h", "1d", "7d", "30d"] {
            if let total = record["\(tf)_total"] as? Int,
               let correct = record["\(tf)_correct"] as? Int,
               total > 0 {
                let acc = Double(correct) / Double(total) * 100
                timeframeAccuracy[tf] = TimeframeStats(total: total, correct: correct, accuracy: acc)
            }
        }
        
        // Parse direction breakdown
        let bullishTotal = record["bullishTotal"] as? Int ?? 0
        let bullishCorrect = record["bullishCorrect"] as? Int ?? 0
        let bearishTotal = record["bearishTotal"] as? Int ?? 0
        let bearishCorrect = record["bearishCorrect"] as? Int ?? 0
        let neutralTotal = record["neutralTotal"] as? Int ?? 0
        let neutralCorrect = record["neutralCorrect"] as? Int ?? 0
        
        let directionBreakdown = DirectionBreakdown(
            bullish: DirectionStats(total: bullishTotal, correct: bullishCorrect),
            bearish: DirectionStats(total: bearishTotal, correct: bearishCorrect),
            neutral: DirectionStats(total: neutralTotal, correct: neutralCorrect)
        )
        
        return CommunityAccuracyMetrics(
            totalPredictions: totalPredictions,
            contributorCount: contributorCount,
            directionAccuracy: directionAccuracy,
            rangeAccuracy: rangeAccuracy,
            averageError: averageError,
            timeframeAccuracy: timeframeAccuracy,
            directionBreakdown: directionBreakdown,
            lastUpdated: record.modificationDate ?? Date()
        )
    }
    
    // MARK: - Helpers
    
    private func getOrCreateContributionId() -> String {
        if let existing = UserDefaults.standard.string(forKey: contributionIdKey) {
            return existing
        }
        
        // Create a new random ID (not tied to user identity)
        let newId = "contrib_\(UUID().uuidString)"
        UserDefaults.standard.set(newId, forKey: contributionIdKey)
        return newId
    }
    
    private func loadCachedMetrics() {
        // Try to load from cache first
        if let data = UserDefaults.standard.data(forKey: cachedMetricsKey),
           let cached = try? JSONDecoder().decode(CommunityAccuracyMetrics.self, from: data) {
            // Invalidate stale baseline data (old hardcoded 500 predictions with 25 contributors)
            // These were fake seed numbers that should no longer be shown
            if cached.contributorCount == 25 && cached.totalPredictions == 500 {
                print("[CommunityAccuracy] Clearing stale baseline cache (old hardcoded 500 predictions)")
                UserDefaults.standard.removeObject(forKey: cachedMetricsKey)
                self.communityMetrics = .empty
                return
            }
            
            self.communityMetrics = cached
            print("[CommunityAccuracy] Loaded cached metrics: \(cached.totalPredictions) predictions")
            return
        }
        
        // No cache available — start with empty (no fake data)
        self.communityMetrics = .empty
        print("[CommunityAccuracy] No cached metrics — starting fresh")
    }
    
    private func saveCachedMetrics() {
        guard let data = try? JSONEncoder().encode(communityMetrics) else { return }
        UserDefaults.standard.set(data, forKey: cachedMetricsKey)
    }
    
    // MARK: - Accuracy Summary for AI
    
    /// Get community accuracy context for AI prompts
    public func communitySummaryForPrompt(timeframe: PredictionTimeframe) -> String {
        guard communityMetrics.hasData else {
            return "Community accuracy data not yet available."
        }
        
        var summary: [String] = []
        
        let reliabilityNote = communityMetrics.isReliable ? "" : " (building - \(communityMetrics.totalPredictions) samples)"
        summary.append("Community accuracy\(reliabilityNote): \(String(format: "%.0f", communityMetrics.directionAccuracy))% direction, \(String(format: "%.0f", communityMetrics.rangeAccuracy))% in range")
        
        // Timeframe-specific community data
        if let tfStats = communityMetrics.timeframeAccuracy[timeframe.rawValue] {
            summary.append("Community \(timeframe.displayName) accuracy: \(String(format: "%.0f", tfStats.accuracy))% (\(tfStats.total) predictions)")
        }
        
        // Direction breakdown insights
        let bullishAcc = communityMetrics.directionBreakdown.bullish.accuracy
        let bearishAcc = communityMetrics.directionBreakdown.bearish.accuracy
        let neutralAcc = communityMetrics.directionBreakdown.neutral.accuracy
        
        if communityMetrics.directionBreakdown.bullish.total >= 50 {
            summary.append("Community bullish accuracy: \(String(format: "%.0f", bullishAcc))%")
        }
        if communityMetrics.directionBreakdown.bearish.total >= 50 {
            summary.append("Community bearish accuracy: \(String(format: "%.0f", bearishAcc))%")
        }
        if communityMetrics.directionBreakdown.neutral.total >= 50 {
            summary.append("Community neutral accuracy: \(String(format: "%.0f", neutralAcc))%")
        }
        
        // Add insights/warnings based on community data
        if communityMetrics.isReliable {
            if bullishAcc < 40 && communityMetrics.directionBreakdown.bullish.total >= 100 {
                summary.append("⚠️ COMMUNITY INSIGHT: Bullish predictions have low accuracy across all users. Be cautious with bullish calls.")
            }
            if bearishAcc < 40 && communityMetrics.directionBreakdown.bearish.total >= 100 {
                summary.append("⚠️ COMMUNITY INSIGHT: Bearish predictions have low accuracy across all users. Be cautious with bearish calls.")
            }
        }
        
        return summary.joined(separator: "\n")
    }
}

// MARK: - Quick Insights for UI

extension CommunityAccuracyService {
    /// Get a quick insight about prediction quality based on community data
    /// Returns nil if no relevant insight, or a tuple of (icon, message, color)
    public func quickInsight(for direction: PredictionDirection) -> (icon: String, message: String, color: String)? {
        guard communityMetrics.hasData && communityMetrics.isReliable else { return nil }
        
        let stats: DirectionStats
        switch direction {
        case .bullish: stats = communityMetrics.directionBreakdown.bullish
        case .bearish: stats = communityMetrics.directionBreakdown.bearish
        case .neutral: stats = communityMetrics.directionBreakdown.neutral
        }
        
        guard stats.total >= 50 else { return nil }
        
        if stats.accuracy >= 70 {
            return ("checkmark.seal.fill", "\(direction.rawValue.capitalized) predictions: \(Int(stats.accuracy))% community accuracy", "green")
        } else if stats.accuracy < 40 {
            return ("exclamationmark.triangle.fill", "\(direction.rawValue.capitalized) predictions historically underperform (\(Int(stats.accuracy))%)", "orange")
        }
        
        return nil
    }
    
    /// Get the best performing prediction direction based on community data
    public var bestPerformingDirection: (direction: PredictionDirection, accuracy: Double)? {
        guard communityMetrics.hasData && communityMetrics.isReliable else { return nil }
        
        let directions: [(PredictionDirection, DirectionStats)] = [
            (.bullish, communityMetrics.directionBreakdown.bullish),
            (.bearish, communityMetrics.directionBreakdown.bearish),
            (.neutral, communityMetrics.directionBreakdown.neutral)
        ]
        
        let qualified = directions.filter { $0.1.total >= 50 }
        guard let best = qualified.max(by: { $0.1.accuracy < $1.1.accuracy }) else { return nil }
        
        return (best.0, best.1.accuracy)
    }
}

// MARK: - Comparison Helpers

extension CommunityAccuracyService {
    /// Compare user's accuracy to community average
    public func comparisonInsights() -> [AccuracyComparison] {
        let local = PredictionAccuracyService.shared.metrics
        let community = communityMetrics
        
        guard local.hasEnoughData && community.hasData else {
            return []
        }
        
        var comparisons: [AccuracyComparison] = []
        
        // Overall direction accuracy
        let dirDiff = local.directionAccuracyPercent - community.directionAccuracy
        comparisons.append(AccuracyComparison(
            metric: "Direction Accuracy",
            yourValue: local.directionAccuracyPercent,
            communityValue: community.directionAccuracy,
            difference: dirDiff,
            insight: dirDiff >= 5 ? "You're outperforming the community!" :
                     dirDiff <= -5 ? "Room for improvement" : "On par with community"
        ))
        
        // Range accuracy
        let rangeDiff = local.rangeAccuracyPercent - community.rangeAccuracy
        comparisons.append(AccuracyComparison(
            metric: "Range Accuracy",
            yourValue: local.rangeAccuracyPercent,
            communityValue: community.rangeAccuracy,
            difference: rangeDiff,
            insight: rangeDiff >= 5 ? "Great range predictions!" :
                     rangeDiff <= -5 ? "Try wider price ranges" : "On par with community"
        ))
        
        return comparisons
    }
}

/// Comparison between user and community accuracy
public struct AccuracyComparison {
    public let metric: String
    public let yourValue: Double
    public let communityValue: Double
    public let difference: Double
    public let insight: String
    
    public var isAboveCommunity: Bool { difference > 0 }
}
