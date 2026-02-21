//
//  NotificationsManager.swift
//  CryptoSage
//
//  Manages price alerts with persistence, monitoring, and local notifications.
//
//  FIRESTORE SYNC: When user is authenticated, alerts sync to Firestore
//  for cross-device consistency. Falls back to local-only when not authenticated.
//

import Foundation
import Combine
import UserNotifications
import FirebaseFirestore
import os

final class NotificationsManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsManager()

    @Published var alerts: [PriceAlert] = []
    @Published var triggeredAlertIDs: Set<UUID> = []
    @Published var advancedAlerts: [PriceAlert] = []
    
    /// Metadata stored when an alert triggers (price, timestamp, AI reason)
    struct TriggerMetadata: Codable {
        let triggeredPrice: Double
        let triggeredAt: Date
        let aiReason: String?
        let notificationSent: Bool
    }
    @Published var triggerMetadata: [UUID: TriggerMetadata] = [:]
    
    /// Alerts being delayed by Smart Timing due to low volatility
    @Published var smartTimingDelayedAlerts: Set<UUID> = []
    
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?
    private let alertsKey = "userPriceAlerts"
    private let triggeredKey = "triggeredAlertIDs"
    private let triggerMetadataKey = "triggerMetadataStore"
    private let advancedAlertsKey = "userAdvancedAlerts"
    private let sentimentHistoryKey = "sentimentHistoryCache"
    private let lastSentimentKey = "lastSentimentValue"
    private let lastSentimentClassKey = "lastSentimentClassification"
    
    // MARK: - Firestore Sync
    
    private let db = Firestore.firestore()
    private var firestoreListener: ListenerRegistration?
    private var isApplyingFirestoreUpdate = false  // Prevent sync loops
    private let logger = Logger(subsystem: "CryptoSage", category: "NotificationsManager")
    
    deinit {
        firestoreListener?.remove()
    }
    
    /// Whether Firestore sync is currently active
    @Published private(set) var isFirestoreSyncActive: Bool = false
    
    // Cache for current prices
    private var priceCache: [String: Double] = [:]
    
    // Cache for historical prices (for percent change alerts)
    private var priceHistory: [String: [(Date, Double)]] = [:]
    
    // Cache for RSI values
    private var rsiCache: [String: Double] = [:]
    
    // Cache for volume data
    private var volumeCache: [String: (current: Double, average: Double)] = [:]
    
    // MARK: - AI-Powered Alert Caches
    
    /// Sentiment history entry (Codable for persistence)
    private struct SentimentHistoryEntry: Codable {
        let timestamp: Date
        let value: Int
        let classification: String
    }
    
    /// Sentiment history for AI sentiment analysis alerts (persisted to UserDefaults)
    private var sentimentHistory: [(Date, Int, String)] = [] // (timestamp, value, classification)
    
    /// Last recorded sentiment value (for detecting significant changes) - persisted
    private var lastSentimentValue: Int? = nil
    
    /// Last sentiment classification - persisted
    private var lastSentimentClassification: String? = nil
    
    /// Price volatility tracker for smart timing (symbol -> recent price changes)
    private var volatilityTracker: [String: [Double]] = [:]
    
    /// Tracks if we're in a "quiet" period for smart timing
    private var isLowVolatilityPeriod: Bool = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        loadAlerts()
        loadAdvancedAlerts()
        loadTriggeredIDs()
        loadSentimentHistory()
        
        // Firestore sync startup is orchestrated by AuthenticationManager
        // to avoid duplicate listener bursts during app launch.
    }
    
    // MARK: - Firestore Sync Methods
    
    /// Start listening to Firestore for alert changes if user is authenticated
    func startFirestoreSyncIfAuthenticated() {
        Task { @MainActor in
            guard AuthenticationManager.shared.isAuthenticated,
                  let userId = AuthenticationManager.shared.currentUser?.id else {
                logger.debug("🔔 [NotificationsManager] Not authenticated, skipping Firestore sync")
                return
            }
            
            startFirestoreListener(userId: userId)
        }
    }
    
    /// Whether we have completed the initial server fetch after sign-in.
    private var hasCompletedInitialFetch = false
    
    /// Start Firestore listener for a specific user
    private func startFirestoreListener(userId: String) {
        guard firestoreListener == nil else {
            logger.debug("🔔 [NotificationsManager] Firestore listener already active")
            return
        }
        
        logger.info("🔔 [NotificationsManager] Starting Firestore alerts sync for user \(userId)")
        
        let alertsRef = db.collection("users").document(userId).collection("alerts").document("priceAlerts")
        
        // ── Step 1: Explicit server fetch on sign-in ──
        hasCompletedInitialFetch = false
        
        alertsRef.getDocument(source: .server) { [weak self] snapshot, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.hasCompletedInitialFetch = true
                
                if let error = error {
                    self.logger.error("🔔 [NotificationsManager] Initial server fetch failed: \(error.localizedDescription)")
                } else if let snapshot = snapshot {
                    self.isFirestoreSyncActive = true
                    self.applyFirestoreSnapshot(snapshot)
                }
            }
        }
        
        // ── Step 2: Real-time listener for ongoing changes ──
        firestoreListener = alertsRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("🔔 [NotificationsManager] Firestore listener error: \(error.localizedDescription)")
                // PERFORMANCE FIX v20: Stop the listener on permission errors to prevent
                // endless retry cycles that spam the console and waste resources.
                // The Firestore SDK automatically retries on transient errors, but permission
                // errors are permanent until rules are updated.
                if error.localizedDescription.contains("Missing or insufficient permissions") {
                    self.logger.warning("🔔 [NotificationsManager] Stopping listener due to permission error - check Firestore rules for alerts collection")
                    self.firestoreListener?.remove()
                    self.firestoreListener = nil
                }
                return
            }
            
            guard let snapshot = snapshot else { return }
            
            DispatchQueue.main.async {
                // Guard: Don't upload local data based on empty cache on fresh install
                if !snapshot.exists {
                    if snapshot.metadata.isFromCache || !self.hasCompletedInitialFetch {
                        self.logger.debug("🔔 [NotificationsManager] Ignoring empty snapshot (waiting for server)")
                        return
                    }
                }
                
                // PERFORMANCE FIX: Defer Firestore updates during scroll
                // Alert sync can wait until scroll ends
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else {
                    // Re-queue after short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.isFirestoreSyncActive = true
                        self?.applyFirestoreSnapshot(snapshot)
                    }
                    return
                }
                
                self.isFirestoreSyncActive = true
                self.applyFirestoreSnapshot(snapshot)
            }
        }
    }
    
    /// Stop Firestore listener
    func stopFirestoreSync() {
        firestoreListener?.remove()
        firestoreListener = nil
        isFirestoreSyncActive = false
        hasCompletedInitialFetch = false
        logger.info("🔔 [NotificationsManager] Stopped Firestore alerts sync")
    }
    
    /// Apply changes from Firestore snapshot
    private func applyFirestoreSnapshot(_ snapshot: DocumentSnapshot) {
        guard snapshot.exists, let data = snapshot.data() else {
            // Document doesn't exist yet - upload local data
            uploadToFirestore()
            return
        }
        
        // Prevent sync loop
        isApplyingFirestoreUpdate = true
        defer { isApplyingFirestoreUpdate = false }
        
        // Decode alerts from Firestore
        if let alertsData = data["alerts"] as? [[String: Any]] {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: alertsData)
                let decoded = try JSONDecoder().decode([PriceAlert].self, from: jsonData)
                let sanitized = sanitizeLoadedAlerts(decoded)
                if sanitized != alerts {
                    alerts = sanitized
                    logger.info("🔔 [NotificationsManager] Updated alerts from Firestore: \(sanitized.count) alerts")
                }
            } catch {
                logger.warning("🔔 [NotificationsManager] Failed to decode alerts: \(error.localizedDescription)")
            }
        }
        
        // Decode advanced alerts
        if let advancedData = data["advancedAlerts"] as? [[String: Any]] {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: advancedData)
                let decoded = try JSONDecoder().decode([PriceAlert].self, from: jsonData)
                let sanitized = sanitizeLoadedAlerts(decoded)
                if sanitized != advancedAlerts {
                    advancedAlerts = sanitized
                    logger.info("🔔 [NotificationsManager] Updated advanced alerts from Firestore: \(sanitized.count) alerts")
                }
            } catch {
                logger.warning("🔔 [NotificationsManager] Failed to decode advanced alerts: \(error.localizedDescription)")
            }
        }
        
        // Decode triggered IDs
        if let triggeredStrings = data["triggeredAlertIDs"] as? [String] {
            let newTriggered = Set(triggeredStrings.compactMap { UUID(uuidString: $0) })
            if newTriggered != triggeredAlertIDs {
                triggeredAlertIDs = newTriggered
                logger.info("🔔 [NotificationsManager] Updated triggered IDs from Firestore")
            }
        }
        
        // Persist locally as well
        saveAlerts()
        saveAdvancedAlerts()
        saveTriggeredIDs()
    }
    
    /// Sync local changes to Firestore (debounced via Combine in save methods)
    private func syncToFirestoreIfNeeded() {
        // Don't sync if this change came from Firestore (prevent loop)
        guard !isApplyingFirestoreUpdate else { return }
        
        // Capture values needed for Firestore write
        let currentAlerts = alerts
        let currentAdvanced = advancedAlerts
        let currentTriggered = triggeredAlertIDs
        
        // Access MainActor-isolated auth properties safely
        Task { @MainActor in
            guard AuthenticationManager.shared.isAuthenticated,
                  let userId = AuthenticationManager.shared.currentUser?.id else {
                return
            }
            
            let alertsRef = self.db.collection("users").document(userId).collection("alerts").document("priceAlerts")
            
            // Convert alerts to dictionaries for Firestore
            var alertsDicts: [[String: Any]] = []
            var advancedDicts: [[String: Any]] = []
            
            do {
                let alertsData = try JSONEncoder().encode(currentAlerts)
                if let alertsArray = try JSONSerialization.jsonObject(with: alertsData) as? [[String: Any]] {
                    alertsDicts = alertsArray
                }
                
                let advancedData = try JSONEncoder().encode(currentAdvanced)
                if let advancedArray = try JSONSerialization.jsonObject(with: advancedData) as? [[String: Any]] {
                    advancedDicts = advancedArray
                }
            } catch {
                self.logger.error("🔔 [NotificationsManager] Failed to encode alerts for Firestore: \(error.localizedDescription)")
                return
            }
            
            let data: [String: Any] = [
                "alerts": alertsDicts,
                "advancedAlerts": advancedDicts,
                "triggeredAlertIDs": currentTriggered.map { $0.uuidString },
                "updatedAt": FieldValue.serverTimestamp(),
                "version": FieldValue.increment(Int64(1))
            ]
            
            alertsRef.setData(data, merge: true) { [weak self] error in
                if let error = error {
                    self?.logger.error("🔔 [NotificationsManager] Failed to sync to Firestore: \(error.localizedDescription)")
                } else {
                    self?.logger.debug("🔔 [NotificationsManager] Synced \(currentAlerts.count + currentAdvanced.count) alerts to Firestore")
                }
            }
        }
    }
    
    /// Force upload local data to Firestore (used when document doesn't exist)
    private func uploadToFirestore() {
        // Capture values needed for Firestore write
        let currentAlerts = alerts
        let currentAdvanced = advancedAlerts
        let currentTriggered = triggeredAlertIDs
        
        // Access MainActor-isolated auth properties safely
        Task { @MainActor [weak self] in
            guard let self,
                  AuthenticationManager.shared.isAuthenticated,
                  let userId = AuthenticationManager.shared.currentUser?.id else {
                return
            }
            
            let alertsRef = self.db.collection("users").document(userId).collection("alerts").document("priceAlerts")
            
            // Convert alerts to dictionaries for Firestore
            var alertsDicts: [[String: Any]] = []
            var advancedDicts: [[String: Any]] = []
            
            do {
                let alertsData = try JSONEncoder().encode(currentAlerts)
                if let alertsArray = try JSONSerialization.jsonObject(with: alertsData) as? [[String: Any]] {
                    alertsDicts = alertsArray
                }
                
                let advancedData = try JSONEncoder().encode(currentAdvanced)
                if let advancedArray = try JSONSerialization.jsonObject(with: advancedData) as? [[String: Any]] {
                    advancedDicts = advancedArray
                }
            } catch {
                self.logger.error("🔔 [NotificationsManager] Failed to encode alerts for upload: \(error.localizedDescription)")
                return
            }
            
            let data: [String: Any] = [
                "alerts": alertsDicts,
                "advancedAlerts": advancedDicts,
                "triggeredAlertIDs": currentTriggered.map { $0.uuidString },
                "updatedAt": FieldValue.serverTimestamp(),
                "version": 1
            ]
            
            alertsRef.setData(data) { [weak self] error in
                if let error = error {
                    self?.logger.error("🔔 [NotificationsManager] Failed to upload to Firestore: \(error.localizedDescription)")
                } else {
                    self?.logger.info("🔔 [NotificationsManager] Uploaded local alerts to Firestore")
                }
            }
        }
    }

    // MARK: - Persistence

    private func loadAlerts() {
        guard
            let data = UserDefaults.standard.data(forKey: alertsKey),
            let decoded = try? JSONDecoder().decode([PriceAlert].self, from: data)
        else { return }
        alerts = sanitizeLoadedAlerts(decoded)
    }

    private func saveAlerts() {
        if let data = try? JSONEncoder().encode(alerts) {
            UserDefaults.standard.set(data, forKey: alertsKey)
        }
        // Sync to Firestore if authenticated
        syncToFirestoreIfNeeded()
    }
    
    private func loadAdvancedAlerts() {
        guard
            let data = UserDefaults.standard.data(forKey: advancedAlertsKey),
            let decoded = try? JSONDecoder().decode([PriceAlert].self, from: data)
        else { return }
        advancedAlerts = sanitizeLoadedAlerts(decoded)
    }

    private func sanitizeLoadedAlerts(_ loaded: [PriceAlert]) -> [PriceAlert] {
        loaded.filter { !$0.conditionType.isComingSoon }
    }
    
    private func saveAdvancedAlerts() {
        if let data = try? JSONEncoder().encode(advancedAlerts) {
            UserDefaults.standard.set(data, forKey: advancedAlertsKey)
        }
        // Sync to Firestore if authenticated
        syncToFirestoreIfNeeded()
    }
    
    private func loadTriggeredIDs() {
        guard
            let data = UserDefaults.standard.data(forKey: triggeredKey),
            let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data)
        else { return }
        triggeredAlertIDs = decoded
        
        // Load trigger metadata
        if let metaData = UserDefaults.standard.data(forKey: triggerMetadataKey),
           let decoded = try? JSONDecoder().decode([String: TriggerMetadata].self, from: metaData) {
            triggerMetadata = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            })
        }
    }
    
    private func saveTriggeredIDs() {
        if let data = try? JSONEncoder().encode(triggeredAlertIDs) {
            UserDefaults.standard.set(data, forKey: triggeredKey)
        }
        // Save trigger metadata
        let stringKeyedMeta = Dictionary(uniqueKeysWithValues: triggerMetadata.map { ($0.key.uuidString, $0.value) })
        if let metaData = try? JSONEncoder().encode(stringKeyedMeta) {
            UserDefaults.standard.set(metaData, forKey: triggerMetadataKey)
        }
        // Sync to Firestore if authenticated
        syncToFirestoreIfNeeded()
    }
    
    // MARK: - Sentiment History Persistence
    
    private func loadSentimentHistory() {
        // Load history
        if let data = UserDefaults.standard.data(forKey: sentimentHistoryKey),
           let entries = try? JSONDecoder().decode([SentimentHistoryEntry].self, from: data) {
            // Filter to last 24 hours and convert to tuple format
            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            sentimentHistory = entries
                .filter { $0.timestamp > cutoff }
                .map { ($0.timestamp, $0.value, $0.classification) }
            logger.debug("🔔 [NotificationsManager] Loaded \(self.sentimentHistory.count) sentiment history entries")
        }
        
        // Load last sentiment value
        if UserDefaults.standard.object(forKey: lastSentimentKey) != nil {
            lastSentimentValue = UserDefaults.standard.integer(forKey: lastSentimentKey)
        }
        
        // Load last sentiment classification
        lastSentimentClassification = UserDefaults.standard.string(forKey: lastSentimentClassKey)
    }
    
    private func saveSentimentHistory() {
        // Convert to Codable format and save
        let entries = sentimentHistory.map { SentimentHistoryEntry(timestamp: $0.0, value: $0.1, classification: $0.2) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: sentimentHistoryKey)
        }
        
        // Save last values
        if let lastValue = lastSentimentValue {
            UserDefaults.standard.set(lastValue, forKey: lastSentimentKey)
        }
        if let lastClass = lastSentimentClassification {
            UserDefaults.standard.set(lastClass, forKey: lastSentimentClassKey)
        }
    }

    // MARK: - Alert Management

    func addAlert(symbol: String,
                  threshold: Double,
                  isAbove: Bool,
                  enablePush: Bool,
                  enableEmail: Bool,
                  enableTelegram: Bool) {
        let conditionType: AlertConditionType = isAbove ? .priceAbove : .priceBelow
        let new = PriceAlert(
            symbol: symbol.uppercased(),
            threshold: threshold,
            isAbove: isAbove,
            enablePush: enablePush,
            enableEmail: enableEmail,
            enableTelegram: enableTelegram,
            conditionType: conditionType
        )
        alerts.append(new)
        saveAlerts()
        
        // Request notification permission if push is enabled
        if enablePush {
            requestAuthorization()
        }
        
        // Start monitoring if not already
        if timerCancellable == nil {
            startMonitoring()
        }
        
        // Schedule background tasks so alert works even when app is backgrounded
        scheduleBackgroundAlertChecks()
    }
    
    /// Add an advanced alert with full configuration
    func addAdvancedAlert(
        symbol: String,
        threshold: Double,
        conditionType: AlertConditionType,
        timeframe: AlertTimeframe? = nil,
        enablePush: Bool = true,
        enableEmail: Bool = false,
        enableTelegram: Bool = false,
        minWhaleAmount: Double? = nil,
        walletAddress: String? = nil,
        volumeMultiplier: Double? = nil
    ) {
        guard !conditionType.isComingSoon else {
            logger.warning("🔔 [NotificationsManager] Ignoring addAdvancedAlert for coming-soon condition: \(conditionType.rawValue)")
            return
        }
        
        let isAbove: Bool
        switch conditionType {
        case .priceAbove, .percentChangeUp, .rsiAbove, .volumeSpike, .whaleMovement:
            isAbove = true
        case .priceBelow, .percentChangeDown, .rsiBelow, .portfolioChange:
            isAbove = false
        }
        
        let new = PriceAlert(
            symbol: symbol.uppercased(),
            threshold: threshold,
            isAbove: isAbove,
            enablePush: enablePush,
            enableEmail: enableEmail,
            enableTelegram: enableTelegram,
            conditionType: conditionType,
            timeframe: timeframe,
            minWhaleAmount: minWhaleAmount,
            walletAddress: walletAddress,
            volumeMultiplier: volumeMultiplier
        )
        
        if conditionType.isAdvanced {
            advancedAlerts.append(new)
            saveAdvancedAlerts()
        } else {
            alerts.append(new)
            saveAlerts()
        }
        
        if enablePush {
            requestAuthorization()
        }
        
        if timerCancellable == nil {
            startMonitoring()
        }
        
        // Schedule background tasks so alert works even when app is backgrounded
        scheduleBackgroundAlertChecks()
    }
    
    /// Add an alert with full configuration including AI features and frequency
    func addAlertWithAI(
        symbol: String,
        threshold: Double,
        isAbove: Bool,
        conditionType: AlertConditionType,
        timeframe: AlertTimeframe? = nil,
        enablePush: Bool = true,
        enableEmail: Bool = false,
        enableTelegram: Bool = false,
        minWhaleAmount: Double? = nil,
        walletAddress: String? = nil,
        volumeMultiplier: Double? = nil,
        enableSentimentAnalysis: Bool = false,
        enableSmartTiming: Bool = false,
        enableAIVolumeSpike: Bool = false,
        frequency: AlertFrequency = .oneTime,
        creationPrice: Double? = nil
    ) {
        guard !conditionType.isComingSoon else {
            logger.warning("🔔 [NotificationsManager] Ignoring addAlertWithAI for coming-soon condition: \(conditionType.rawValue)")
            return
        }
        
        let new = PriceAlert(
            symbol: symbol.uppercased(),
            threshold: threshold,
            isAbove: isAbove,
            enablePush: enablePush,
            enableEmail: enableEmail,
            enableTelegram: enableTelegram,
            conditionType: conditionType,
            timeframe: timeframe,
            minWhaleAmount: minWhaleAmount,
            walletAddress: walletAddress,
            volumeMultiplier: volumeMultiplier,
            enableSentimentAnalysis: enableSentimentAnalysis,
            enableSmartTiming: enableSmartTiming,
            enableAIVolumeSpike: enableAIVolumeSpike,
            frequency: frequency,
            creationPrice: creationPrice
        )
        
        // Store in appropriate array based on type
        if conditionType.isAdvanced || new.hasAIFeatures {
            advancedAlerts.append(new)
            saveAdvancedAlerts()
        } else {
            alerts.append(new)
            saveAlerts()
        }
        
        if enablePush {
            requestAuthorization()
        }
        
        if timerCancellable == nil {
            startMonitoring()
        }
        
        // Schedule background tasks so alert works even when app is backgrounded
        scheduleBackgroundAlertChecks()
    }
    
    /// Schedule background refresh + processing tasks for alert monitoring when app is not active
    private func scheduleBackgroundAlertChecks() {
        CryptoSageAIApp.schedulePriceAlertBackgroundRefresh()
        CryptoSageAIApp.schedulePriceAlertBackgroundProcessing()
    }

    func removeAlerts(at offsets: IndexSet) {
        let idsToRemove = offsets.map { alerts[$0].id }
        alerts.remove(atOffsets: offsets)
        saveAlerts()
        
        // Clean up triggered IDs
        for id in idsToRemove {
            triggeredAlertIDs.remove(id)
            conditionBaseline.removeValue(forKey: id)
        }
        saveTriggeredIDs()
    }
    
    func removeAlert(id: UUID) {
        if let idx = alerts.firstIndex(where: { $0.id == id }) {
            alerts.remove(at: idx)
            saveAlerts()
            triggeredAlertIDs.remove(id)
            conditionBaseline.removeValue(forKey: id)
            saveTriggeredIDs()
        }
        
        // Also check advanced alerts
        if let idx = advancedAlerts.firstIndex(where: { $0.id == id }) {
            advancedAlerts.remove(at: idx)
            saveAdvancedAlerts()
            triggeredAlertIDs.remove(id)
            conditionBaseline.removeValue(forKey: id)
            saveTriggeredIDs()
        }
    }
    
    func resetAlert(id: UUID) {
        triggeredAlertIDs.remove(id)
        triggerMetadata.removeValue(forKey: id)
        conditionBaseline.removeValue(forKey: id)
        saveTriggeredIDs()
    }
    
    /// Get all alerts (both basic and advanced)
    var allAlerts: [PriceAlert] {
        alerts + advancedAlerts
    }
    
    /// Get alerts filtered by condition type
    func alerts(ofType type: AlertConditionType) -> [PriceAlert] {
        allAlerts.filter { $0.conditionType == type }
    }

    // MARK: - Authorization
    
    /// Whether notification permission has been granted (cached from last check)
    @Published private(set) var notificationPermissionGranted: Bool = false

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.notificationPermissionGranted = granted
            }
            if let error = error {
                print("[NotificationsManager] Authorization error: \(error)")
            } else if granted {
                print("[NotificationsManager] Push notifications authorized")
            } else {
                print("[NotificationsManager] ⚠️ Push notifications NOT authorized — alerts will trigger but notifications won't appear")
            }
        }
    }
    
    /// Check current notification permission status and log it
    func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                self?.notificationPermissionGranted = granted
            }
            if !granted {
                print("[NotificationsManager] ⚠️ Notification permission status: \(settings.authorizationStatus.rawValue) — notifications will NOT be delivered")
            }
        }
    }

    // MARK: - Monitoring
    
    /// Minimum seconds between consecutive checkAlerts() calls to prevent duplicates on launch
    private static let checkAlertsCooldown: TimeInterval = 30
    /// Timestamp of the last checkAlerts() invocation
    private var lastCheckAlertsAt: Date = .distantPast
    /// Tracks previous condition state for all alerts so they fire on transitions only.
    /// This avoids immediate "launch-triggered" notifications when a condition is already true.
    private var conditionBaseline: [UUID: Bool] = [:]
    
    /// Whether the monitoring timer is currently running
    var isMonitoring: Bool { timerCancellable != nil }

    func startMonitoring(interval: TimeInterval = 60) {
        // If already monitoring, don't restart the timer (prevents duplicate checks
        // from NotificationsView.onAppear calling this every time the tab appears)
        if timerCancellable != nil {
            logger.debug("🔔 [NotificationsManager] Already monitoring — skipping redundant startMonitoring()")
            return
        }
        
        // Ensure notification permissions are requested before monitoring starts
        requestAuthorization()
        
        // Check immediately on start, but only if we haven't checked very recently
        // This prevents the "alert fires on every relaunch" issue when the condition is still met
        let timeSinceLastCheck = Date().timeIntervalSince(lastCheckAlertsAt)
        if timeSinceLastCheck >= Self.checkAlertsCooldown {
            Task { await checkAlerts() }
        } else {
            logger.debug("🔔 [NotificationsManager] Skipping immediate check — last check was \(String(format: "%.0f", timeSinceLastCheck))s ago (cooldown: \(Self.checkAlertsCooldown)s)")
        }
        
        // Then check periodically
        // PERFORMANCE FIX v19: Changed .common to .default so timer pauses during scroll
        timerCancellable = Timer.publish(every: interval, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.checkAlerts() }
            }
    }
    
    /// Restart monitoring after returning from background.
    /// Unlike startMonitoring(), this always restarts the timer even if one was running,
    /// because the old timer may have been invalidated by the system.
    func resumeMonitoring(interval: TimeInterval = 60) {
        timerCancellable?.cancel()
        timerCancellable = nil
        
        // Perform a fresh check now (respecting cooldown)
        let timeSinceLastCheck = Date().timeIntervalSince(lastCheckAlertsAt)
        if timeSinceLastCheck >= Self.checkAlertsCooldown {
            Task { await checkAlerts() }
        }
        
        timerCancellable = Timer.publish(every: interval, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.checkAlerts() }
            }
        logger.debug("🔔 [NotificationsManager] Resumed monitoring timer")
    }

    func stopMonitoring() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    // MARK: - Price Checking

    /// Check all alerts against current prices. Called by monitoring timer and background refresh.
    func checkAlerts() async {
        // Record check time for cooldown tracking
        await MainActor.run { lastCheckAlertsAt = Date() }
        
        let allAlertsToCheck = allAlerts
        guard !allAlertsToCheck.isEmpty else { return }
        
        // Get unique symbols to fetch
        let symbols = Set(allAlertsToCheck.map { $0.symbol })
        
        // Fetch prices for all symbols
        await withTaskGroup(of: (String, Double?).self) { group in
            for symbol in symbols {
                group.addTask {
                    let price = await self.fetchPrice(for: symbol)
                    return (symbol, price)
                }
            }
            
            for await (symbol, price) in group {
                if let price = price {
                    // Store in history for percent change alerts
                    await MainActor.run {
                        var history = self.priceHistory[symbol] ?? []
                        history.append((Date(), price))
                        // Keep last 7 days of history
                        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
                        history = history.filter { $0.0 > cutoff }
                        self.priceHistory[symbol] = history
                        self.priceCache[symbol] = price
                    }
                }
            }
        }
        
        // Check each alert against current prices/conditions
        for alert in allAlertsToCheck {
            guard !triggeredAlertIDs.contains(alert.id) else { continue }
            
            // Hide incomplete/coming-soon condition types from runtime evaluation.
            if alert.conditionType.isComingSoon { continue }
            
            // Check frequency-based cooldown
            if !shouldAlertBasedOnFrequency(alert) { continue }
            
            let currentPrice = priceCache[alert.symbol] ?? 0
            
            // Evaluate basic alert condition
            let basicTriggered = await evaluateAlertCondition(alert)
            
            // For AI-powered alerts, also evaluate AI features
            if alert.hasAIFeatures {
                // AI alerts can trigger in two ways:
                // 1. Basic condition met + AI features pass
                // 2. AI features detect something significant (sentiment shift, volume spike)
                let (aiTriggered, aiReason) = await evaluateAIFeatures(alert, currentPrice: currentPrice)
                
                if basicTriggered && aiTriggered {
                    if shouldTriggerAlertNow(alert: alert, conditionMet: true) {
                        await triggerAlert(alert, currentPrice: currentPrice, aiReason: aiReason)
                    }
                } else if aiTriggered && (alert.enableSentimentAnalysis || alert.enableAIVolumeSpike) {
                    // AI-only trigger (sentiment or volume spike detected independently)
                    if shouldTriggerAlertNow(alert: alert, conditionMet: true) {
                        await triggerAlert(alert, currentPrice: currentPrice, aiReason: aiReason)
                    }
                } else {
                    _ = shouldTriggerAlertNow(alert: alert, conditionMet: false)
                }
            } else if basicTriggered {
                if shouldTriggerAlertNow(alert: alert, conditionMet: true) {
                    await triggerAlert(alert, currentPrice: currentPrice, aiReason: nil)
                }
            } else {
                _ = shouldTriggerAlertNow(alert: alert, conditionMet: false)
            }
        }
    }
    
    /// Alerts should fire only when condition transitions false -> true.
    /// Frequency/cooldown limits are still enforced separately by shouldAlertBasedOnFrequency(_:)
    /// before this method is called.
    private func shouldTriggerAlertNow(alert: PriceAlert, conditionMet: Bool) -> Bool {
        let previousState = conditionBaseline[alert.id]
        conditionBaseline[alert.id] = conditionMet
        
        // First observation establishes baseline without notifying.
        guard let previousState else { return false }
        
        // Fire only on rising edge (false -> true).
        return !previousState && conditionMet
    }
    
    /// Check if alert should fire based on frequency settings
    private func shouldAlertBasedOnFrequency(_ alert: PriceAlert) -> Bool {
        switch alert.frequency {
        case .oneTime:
            // One-time alerts only fire once (checked via triggeredAlertIDs)
            return true
            
        case .onceDaily:
            // Check if already fired today
            if let lastTrigger = alert.lastTriggeredAt {
                let calendar = Calendar.current
                if calendar.isDateInToday(lastTrigger) {
                    return false // Already triggered today
                }
            }
            return true
            
        case .always:
            // Always can trigger (but still needs cooldown period)
            if let lastTrigger = alert.lastTriggeredAt {
                // Minimum 5 minute cooldown between triggers
                let cooldown: TimeInterval = 5 * 60
                if Date().timeIntervalSince(lastTrigger) < cooldown {
                    return false
                }
            }
            return true
        }
    }
    
    /// Evaluate whether an alert condition has been met
    private func evaluateAlertCondition(_ alert: PriceAlert) async -> Bool {
        switch alert.conditionType {
        case .priceAbove:
            guard let currentPrice = priceCache[alert.symbol] else { return false }
            return currentPrice >= alert.threshold
            
        case .priceBelow:
            guard let currentPrice = priceCache[alert.symbol] else { return false }
            return currentPrice <= alert.threshold
            
        case .percentChangeUp:
            return await evaluatePercentChange(alert, isUp: true)
            
        case .percentChangeDown:
            return await evaluatePercentChange(alert, isUp: false)
            
        case .rsiAbove:
            guard let rsi = rsiCache[alert.symbol] else {
                // Fetch RSI if not cached
                await fetchRSI(for: alert.symbol)
                guard let rsi = rsiCache[alert.symbol] else { return false }
                return rsi >= alert.threshold
            }
            return rsi >= alert.threshold
            
        case .rsiBelow:
            guard let rsi = rsiCache[alert.symbol] else {
                await fetchRSI(for: alert.symbol)
                guard let rsi = rsiCache[alert.symbol] else { return false }
                return rsi <= alert.threshold
            }
            return rsi <= alert.threshold
            
        case .volumeSpike:
            guard let volumeData = volumeCache[alert.symbol] else {
                await fetchVolumeData(for: alert.symbol)
                guard let volumeData = volumeCache[alert.symbol] else { return false }
                let multiplier = alert.volumeMultiplier ?? 2.0
                return volumeData.current >= volumeData.average * multiplier
            }
            let multiplier = alert.volumeMultiplier ?? 2.0
            return volumeData.current >= volumeData.average * multiplier
            
        case .portfolioChange:
            // This would integrate with PortfolioViewModel
            return false // Handled separately via portfolio updates
            
        case .whaleMovement:
            // This will be handled by WhaleTrackingService
            return false // Handled separately via whale tracking
        }
    }
    
    private func evaluatePercentChange(_ alert: PriceAlert, isUp: Bool) async -> Bool {
        guard let currentPrice = priceCache[alert.symbol],
              let history = priceHistory[alert.symbol],
              let timeframe = alert.timeframe else {
            return false
        }
        
        // Find price from timeframe hours ago
        let targetTime = Date().addingTimeInterval(-Double(timeframe.rawValue) * 60 * 60)
        
        // Find the closest price to the target time
        guard let historicalEntry = history.min(by: { 
            abs($0.0.timeIntervalSince(targetTime)) < abs($1.0.timeIntervalSince(targetTime)) 
        }) else {
            return false
        }
        
        // Only use if within 10% of target time
        let timeDiff = abs(historicalEntry.0.timeIntervalSince(targetTime))
        let allowedDiff = Double(timeframe.rawValue) * 60 * 60 * 0.1
        guard timeDiff <= allowedDiff else { return false }
        
        let historicalPrice = historicalEntry.1
        guard historicalPrice > 0 else { return false }
        
        let percentChange = ((currentPrice - historicalPrice) / historicalPrice) * 100
        
        if isUp {
            return percentChange >= alert.threshold
        } else {
            return percentChange <= -alert.threshold
        }
    }
    
    // MARK: - AI-Powered Alert Evaluation
    
    /// Evaluates AI-powered features for an alert (sentiment, timing, volume spike detection)
    /// Returns (shouldTrigger: Bool, aiReason: String?)
    private func evaluateAIFeatures(_ alert: PriceAlert, currentPrice: Double) async -> (Bool, String?) {
        guard alert.hasAIFeatures else { return (true, nil) }
        
        var reasons: [String] = []
        var shouldTrigger = false
        
        // 1. Sentiment Analysis - Check if market sentiment has shifted significantly
        if alert.enableSentimentAnalysis {
            let (sentimentTriggered, sentimentReason) = await evaluateSentimentTrigger(alert)
            if sentimentTriggered {
                shouldTrigger = true
                if let reason = sentimentReason {
                    reasons.append(reason)
                }
            }
        }
        
        // 2. AI Volume Spike Detection - More sophisticated than basic volume spike
        if alert.enableAIVolumeSpike {
            let (volumeTriggered, volumeReason) = await evaluateAIVolumeSpike(alert)
            if volumeTriggered {
                shouldTrigger = true
                if let reason = volumeReason {
                    reasons.append(reason)
                }
            }
        }
        
        // 3. Smart Timing - Evaluate if this is a good time to alert
        // If smart timing is enabled, it can delay non-urgent alerts during low volatility
        if alert.enableSmartTiming {
            let (isGoodTiming, timingReason) = evaluateSmartTiming(alert, currentPrice: currentPrice)
            if !isGoodTiming && !shouldTrigger {
                // Don't trigger yet - waiting for better timing
                return (false, nil)
            }
            if let reason = timingReason {
                reasons.append(reason)
            }
        }
        
        let combinedReason = reasons.isEmpty ? nil : reasons.joined(separator: "; ")
        return (shouldTrigger, combinedReason)
    }
    
    /// Evaluate sentiment-based trigger for AI alerts
    private func evaluateSentimentTrigger(_ alert: PriceAlert) async -> (Bool, String?) {
        // Get current sentiment from ExtendedFearGreedViewModel
        let sentimentVM = await MainActor.run { ExtendedFearGreedViewModel.shared }
        
        guard let currentValue = await MainActor.run(body: { sentimentVM.currentValue }),
              let currentClassification = await MainActor.run(body: { sentimentVM.currentClassificationKey }) else {
            return (false, nil)
        }
        
        // Store in history
        await MainActor.run {
            self.sentimentHistory.append((Date(), currentValue, currentClassification))
            // Keep last 24 hours of sentiment data
            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            self.sentimentHistory = self.sentimentHistory.filter { $0.0 > cutoff }
        }
        
        // Check for significant sentiment changes (compute inside MainActor to avoid captured var mutation)
        let (triggered, reason) = await MainActor.run { () -> (Bool, String?) in
            var triggered = false
            var reason: String? = nil
            
            // If we have a previous sentiment value, check for significant change
            if let lastValue = self.lastSentimentValue {
                let change = currentValue - lastValue
                
                // Trigger if sentiment changed by 15+ points
                if abs(change) >= 15 {
                    triggered = true
                    let direction = change > 0 ? "increased" : "decreased"
                    reason = "Market sentiment \(direction) significantly (\(lastValue) → \(currentValue))"
                }
                
                // Trigger on classification change (e.g., Fear → Greed)
                if let lastClass = self.lastSentimentClassification,
                   lastClass != currentClassification {
                    let majorShift = self.isMajorSentimentShift(from: lastClass, to: currentClassification)
                    if majorShift {
                        triggered = true
                        reason = "Sentiment shifted from \(lastClass.capitalized) to \(currentClassification.capitalized)"
                    }
                }
            }
            
            // Update last values
            self.lastSentimentValue = currentValue
            self.lastSentimentClassification = currentClassification
            
            // Persist sentiment history for cross-session continuity
            self.saveSentimentHistory()
            
            return (triggered, reason)
        }
        
        return (triggered, reason)
    }
    
    /// Check if sentiment shift is significant (e.g., fear → greed or vice versa)
    private func isMajorSentimentShift(from: String, to: String) -> Bool {
        let fearStates = ["extreme fear", "fear"]
        let greedStates = ["greed", "extreme greed"]
        
        let fromFear = fearStates.contains(from.lowercased())
        let fromGreed = greedStates.contains(from.lowercased())
        let toFear = fearStates.contains(to.lowercased())
        let toGreed = greedStates.contains(to.lowercased())
        
        // Major shift: fear → greed or greed → fear
        return (fromFear && toGreed) || (fromGreed && toFear)
    }
    
    /// Evaluate AI-enhanced volume spike detection
    private func evaluateAIVolumeSpike(_ alert: PriceAlert) async -> (Bool, String?) {
        // First, check basic volume data
        if volumeCache[alert.symbol] == nil {
            await fetchVolumeData(for: alert.symbol)
        }
        
        guard let volumeData = volumeCache[alert.symbol] else {
            return (false, nil)
        }
        
        // AI-enhanced: Use a dynamic multiplier based on recent volatility
        // During high volatility periods, require higher volume spike
        // During low volatility, even smaller spikes are noteworthy
        let baseMultiplier = alert.volumeMultiplier ?? 2.0
        let volatilityAdjustedMultiplier = await calculateVolatilityAdjustedMultiplier(
            symbol: alert.symbol,
            baseMultiplier: baseMultiplier
        )
        
        if volumeData.current >= volumeData.average * volatilityAdjustedMultiplier {
            let multiplier = volumeData.current / volumeData.average
            return (true, "Volume spike: \(String(format: "%.1f", multiplier))x average volume")
        }
        
        return (false, nil)
    }
    
    /// Calculate volatility-adjusted multiplier for smarter volume detection
    private func calculateVolatilityAdjustedMultiplier(symbol: String, baseMultiplier: Double) async -> Double {
        // Get recent price changes for volatility estimate
        guard let history = priceHistory[symbol], history.count >= 5 else {
            return baseMultiplier
        }
        
        let recentPrices = history.suffix(10).map { $0.1 }
        guard recentPrices.count >= 2 else { return baseMultiplier }
        
        // Calculate price volatility (standard deviation of % changes)
        var changes: [Double] = []
        for i in 1..<recentPrices.count {
            let change = abs((recentPrices[i] - recentPrices[i-1]) / recentPrices[i-1]) * 100
            changes.append(change)
        }
        
        let avgChange = changes.reduce(0, +) / Double(changes.count)
        
        // High volatility (>3% avg change) = require higher volume spike
        // Low volatility (<1% avg change) = lower threshold is significant
        if avgChange > 3.0 {
            return baseMultiplier * 1.5 // Require 50% more volume during volatile periods
        } else if avgChange < 1.0 {
            return baseMultiplier * 0.75 // 25% less volume needed during calm periods
        }
        
        return baseMultiplier
    }
    
    /// Evaluate smart timing - should we alert now or wait?
    private func evaluateSmartTiming(_ alert: PriceAlert, currentPrice: Double) -> (Bool, String?) {
        // Update volatility tracker
        if let lastPrice = priceCache[alert.symbol] {
            let change = abs((currentPrice - lastPrice) / lastPrice) * 100
            var tracker = volatilityTracker[alert.symbol] ?? []
            tracker.append(change)
            if tracker.count > 20 { tracker.removeFirst() }
            volatilityTracker[alert.symbol] = tracker
        }
        
        // Calculate recent volatility
        guard let tracker = volatilityTracker[alert.symbol], tracker.count >= 5 else {
            // Not enough data, allow alert and remove from delayed set
            Task { @MainActor in
                self.smartTimingDelayedAlerts.remove(alert.id)
            }
            return (true, nil)
        }
        
        let avgVolatility = tracker.reduce(0, +) / Double(tracker.count)
        
        // During low volatility (<0.5% avg move), delay non-critical alerts
        // During high volatility (>2% avg move), alert immediately
        if avgVolatility > 2.0 {
            // High volatility - alert immediately, remove from delayed set
            Task { @MainActor in
                self.smartTimingDelayedAlerts.remove(alert.id)
            }
            return (true, "High market activity detected")
        } else if avgVolatility < 0.5 {
            // Low volatility - only alert if price is very close to threshold
            let distanceToThreshold = abs(currentPrice - alert.threshold)
            let percentDistance = (distanceToThreshold / alert.threshold) * 100
            
            if percentDistance < 1.0 {
                // Close enough, alert now
                Task { @MainActor in
                    self.smartTimingDelayedAlerts.remove(alert.id)
                }
                return (true, "Price nearing target during quiet period")
            } else {
                // Add to delayed set and wait for more activity
                Task { @MainActor in
                    self.smartTimingDelayedAlerts.insert(alert.id)
                    self.logger.debug("🔔 [NotificationsManager] Smart Timing delaying alert \(alert.symbol) - low volatility (\(String(format: "%.2f", avgVolatility))% avg)")
                }
                return (false, nil)
            }
        }
        
        // Normal volatility - alert normally
        Task { @MainActor in
            self.smartTimingDelayedAlerts.remove(alert.id)
        }
        return (true, nil)
    }
    
    /// Fetch RSI for a symbol (simplified calculation)
    private func fetchRSI(for symbol: String) async {
        // Use cached price history to calculate RSI
        guard let history = priceHistory[symbol], history.count >= 14 else { return }
        
        // Get last 14 price changes
        let prices = history.suffix(15).map { $0.1 }
        var gains: [Double] = []
        var losses: [Double] = []
        
        for i in 1..<prices.count {
            let change = prices[i] - prices[i-1]
            if change > 0 {
                gains.append(change)
                losses.append(0)
            } else {
                gains.append(0)
                losses.append(abs(change))
            }
        }
        
        let avgGain = gains.reduce(0, +) / Double(gains.count)
        let avgLoss = losses.reduce(0, +) / Double(losses.count)
        
        guard avgLoss > 0 else {
            await MainActor.run { rsiCache[symbol] = 100 }
            return
        }
        
        let rs = avgGain / avgLoss
        let rsi = 100 - (100 / (1 + rs))
        
        await MainActor.run { rsiCache[symbol] = rsi }
    }
    
    /// Fetch volume data for a symbol with proper historical average
    private func fetchVolumeData(for symbol: String) async {
        let binanceSymbol = symbol.hasSuffix("USDT") ? symbol : "\(symbol)USDT"
        
        // PERFORMANCE FIX v25: Skip when Binance is geo-blocked
        if UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked") { return }
        
        // Check rate limiter
        guard APIRequestCoordinator.shared.canMakeRequest(for: .binance) else {
            return
        }
        APIRequestCoordinator.shared.recordRequest(for: .binance)
        
        // FIX: Use ExchangeHostPolicy to get correct endpoint (US if geo-blocked)
        let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
        
        // Fetch current 24hr volume
        let ticker24hURL = "\(endpoints.restBase)/ticker/24hr?symbol=\(binanceSymbol)"
        guard let tickerURL = URL(string: ticker24hURL) else {
            APIRequestCoordinator.shared.recordFailure(for: .binance)
            return
        }
        
        do {
            let (tickerData, tickerResponse) = try await URLSession.shared.data(from: tickerURL)
            
            // FIX: Report HTTP status to policy for geo-block detection
            if let httpResponse = tickerResponse as? HTTPURLResponse {
                await ExchangeHostPolicy.shared.onHTTPStatus(httpResponse.statusCode)
                guard httpResponse.statusCode == 200 else {
                    APIRequestCoordinator.shared.recordFailure(for: .binance)
                    return
                }
            } else {
                APIRequestCoordinator.shared.recordFailure(for: .binance)
                return
            }
            
            struct TickerResponse: Codable {
                let volume: String
                let quoteVolume: String
            }
            
            let tickerDecoded = try JSONDecoder().decode(TickerResponse.self, from: tickerData)
            guard let currentVolume = Double(tickerDecoded.quoteVolume) else {
                APIRequestCoordinator.shared.recordFailure(for: .binance)
                return
            }
            
            APIRequestCoordinator.shared.recordSuccess(for: .binance)
            
            // Fetch historical klines for proper average calculation (last 7 days of daily data)
            // FIX: Use same endpoints from ExchangeHostPolicy
            let klinesURL = "\(endpoints.restBase)/klines?symbol=\(binanceSymbol)&interval=1d&limit=7"
            guard let historyURL = URL(string: klinesURL),
                  APIRequestCoordinator.shared.canMakeRequest(for: .binance) else {
                // Fallback: use current volume with slight adjustment
                await MainActor.run {
                    volumeCache[symbol] = (current: currentVolume, average: currentVolume * 0.85)
                }
                return
            }
            
            APIRequestCoordinator.shared.recordRequest(for: .binance)
            
            let (klinesData, klinesResponse) = try await URLSession.shared.data(from: historyURL)
            
            guard let klinesHttpResponse = klinesResponse as? HTTPURLResponse,
                  klinesHttpResponse.statusCode == 200 else {
                APIRequestCoordinator.shared.recordFailure(for: .binance)
                // Fallback
                await MainActor.run {
                    volumeCache[symbol] = (current: currentVolume, average: currentVolume * 0.85)
                }
                return
            }
            
            // Parse klines response (array of arrays)
            // Format: [[openTime, open, high, low, close, volume, closeTime, quoteVolume, ...], ...]
            if let klines = try JSONSerialization.jsonObject(with: klinesData) as? [[Any]] {
                var historicalVolumes: [Double] = []
                
                for kline in klines {
                    // Index 7 is quote asset volume (USDT volume)
                    if kline.count > 7,
                       let quoteVolumeStr = kline[7] as? String,
                       let quoteVolume = Double(quoteVolumeStr) {
                        historicalVolumes.append(quoteVolume)
                    }
                }
                
                // Calculate average from historical data
                let avgVolume: Double
                if historicalVolumes.count >= 3 {
                    // Remove highest and lowest, then average (trimmed mean)
                    let sorted = historicalVolumes.sorted()
                    let trimmed = Array(sorted.dropFirst().dropLast())
                    avgVolume = trimmed.isEmpty ? currentVolume : trimmed.reduce(0, +) / Double(trimmed.count)
                } else if !historicalVolumes.isEmpty {
                    avgVolume = historicalVolumes.reduce(0, +) / Double(historicalVolumes.count)
                } else {
                    avgVolume = currentVolume * 0.85
                }
                
                APIRequestCoordinator.shared.recordSuccess(for: .binance)
                
                await MainActor.run {
                    volumeCache[symbol] = (current: currentVolume, average: avgVolume)
                    logger.debug("🔔 [NotificationsManager] Volume for \(symbol): current=\(String(format: "%.0f", currentVolume)), avg=\(String(format: "%.0f", avgVolume)) (ratio: \(String(format: "%.2f", currentVolume/avgVolume))x)")
                }
            } else {
                APIRequestCoordinator.shared.recordFailure(for: .binance)
                // Fallback
                await MainActor.run {
                    volumeCache[symbol] = (current: currentVolume, average: currentVolume * 0.85)
                }
            }
        } catch {
            APIRequestCoordinator.shared.recordFailure(for: .binance)
            logger.warning("🔔 [NotificationsManager] Failed to fetch volume for \(symbol): \(error.localizedDescription)")
        }
    }
    
    // PERFORMANCE FIX: Static cache for price lookups to reduce API calls
    private static var priceFetchCache: [String: (price: Double, fetchedAt: Date)] = [:]
    private static let priceFetchCacheTTL: TimeInterval = 30.0  // 30 second cache for notification checks
    
    private func fetchPrice(for symbol: String) async -> Double? {
        // Try Binance API first (most symbols are in XXXUSDT format)
        let binanceSymbol = symbol.hasSuffix("USDT") ? symbol : "\(symbol)USDT"
        
        // PERFORMANCE FIX: Check cache first
        let now = Date()
        if let cached = Self.priceFetchCache[binanceSymbol],
           now.timeIntervalSince(cached.fetchedAt) < Self.priceFetchCacheTTL {
            return cached.price
        }
        
        // PERFORMANCE FIX: Check rate limiter before making request
        guard APIRequestCoordinator.shared.canMakeRequest(for: .binance) else {
            // Return cached value if available
            if let cached = Self.priceFetchCache[binanceSymbol] {
                return cached.price
            }
            // Try LivePriceManager as fallback
            let coins = await MainActor.run { LivePriceManager.shared.currentCoinsList }
            if let coin = coins.first(where: { $0.symbol.uppercased() == symbol.uppercased() }) {
                return coin.priceUsd
            }
            return nil
        }
        
        APIRequestCoordinator.shared.recordRequest(for: .binance)
        
        // FIX: Use ExchangeHostPolicy to get correct endpoint (US if geo-blocked)
        let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
        let urlString = "\(endpoints.restBase)/ticker/price?symbol=\(binanceSymbol)"
        guard let url = URL(string: urlString) else {
            APIRequestCoordinator.shared.recordFailure(for: .binance)
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // FIX: Report HTTP status to policy for geo-block detection
            if let httpResponse = response as? HTTPURLResponse {
                await ExchangeHostPolicy.shared.onHTTPStatus(httpResponse.statusCode)
                guard httpResponse.statusCode == 200 else {
                    APIRequestCoordinator.shared.recordFailure(for: .binance)
                    return nil
                }
            }
            
            struct PriceResponse: Codable {
                let price: String
            }
            
            let decoded = try JSONDecoder().decode(PriceResponse.self, from: data)
            if let price = Double(decoded.price) {
                // PERFORMANCE FIX: Update cache
                Self.priceFetchCache[binanceSymbol] = (price, Date())
                APIRequestCoordinator.shared.recordSuccess(for: .binance)
                return price
            }
            APIRequestCoordinator.shared.recordFailure(for: .binance)
            return nil
        } catch {
            APIRequestCoordinator.shared.recordFailure(for: .binance)
            print("[NotificationsManager] Failed to fetch price for \(symbol): \(error)")
            return nil
        }
    }
    
    // MARK: - Alert Triggering

    @MainActor
    private func triggerAlert(_ alert: PriceAlert, currentPrice: Double, aiReason: String? = nil) {
        // Store trigger metadata (price, time, reason)
        let metadata = TriggerMetadata(
            triggeredPrice: currentPrice,
            triggeredAt: Date(),
            aiReason: aiReason,
            notificationSent: alert.enablePush
        )
        triggerMetadata[alert.id] = metadata
        
        // Handle based on frequency
        switch alert.frequency {
        case .oneTime:
            // Mark as triggered to prevent repeat notifications
            triggeredAlertIDs.insert(alert.id)
            saveTriggeredIDs()
            
        case .onceDaily, .always:
            // Update lastTriggeredAt for frequency tracking
            updateAlertLastTriggered(alert.id)
        }
        
        // Send push notification if enabled
        if alert.enablePush {
            sendLocalNotification(for: alert, currentPrice: currentPrice, aiReason: aiReason)
        } else {
            print("[NotificationsManager] ⚠️ Alert triggered for \(alert.symbol) but push notifications are disabled for this alert")
        }
        
        // Post notification for in-app handling
        var userInfo: [String: Any] = [
            "alertID": alert.id.uuidString,
            "symbol": alert.symbol,
            "conditionType": alert.conditionType.rawValue,
            "currentPrice": currentPrice,
            "hasAIFeatures": alert.hasAIFeatures
        ]
        if let reason = aiReason {
            userInfo["aiReason"] = reason
        }
        
        NotificationCenter.default.post(
            name: .alertTriggered,
            object: nil,
            userInfo: userInfo
        )
        
        // Log for debugging
        let aiTag = alert.hasAIFeatures ? " [AI]" : ""
        let reasonTag = aiReason.map { " - \($0)" } ?? ""
        print("[NotificationsManager] Alert triggered\(aiTag): \(alert.symbol) [\(alert.conditionType.rawValue)] threshold=\(alert.threshold) (current: \(currentPrice))\(reasonTag)")
    }
    
    /// Update the lastTriggeredAt timestamp for recurring alerts
    private func updateAlertLastTriggered(_ alertId: UUID) {
        // Update in basic alerts
        if let idx = alerts.firstIndex(where: { $0.id == alertId }) {
            var updatedAlert = alerts[idx]
            updatedAlert.lastTriggeredAt = Date()
            alerts[idx] = updatedAlert
            saveAlerts()
        }
        
        // Update in advanced alerts
        if let idx = advancedAlerts.firstIndex(where: { $0.id == alertId }) {
            var updatedAlert = advancedAlerts[idx]
            updatedAlert.lastTriggeredAt = Date()
            advancedAlerts[idx] = updatedAlert
            saveAdvancedAlerts()
        }
    }
    
    private func sendLocalNotification(for alert: PriceAlert, currentPrice: Double, aiReason: String? = nil) {
        // Verify notification permission before attempting to send
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                print("[NotificationsManager] ⚠️ Cannot send notification for \(alert.symbol) — permission not granted (status: \(settings.authorizationStatus.rawValue))")
                // Try requesting permission again in case user hasn't been asked yet
                if settings.authorizationStatus == .notDetermined {
                    self?.requestAuthorization()
                }
                return
            }
            
            let content = UNMutableNotificationContent()
            
            // Customize title and body based on alert type
            var (title, body) = self?.buildNotificationContent(for: alert, currentPrice: currentPrice) ?? ("Price Alert", "\(alert.symbol)")
            
            // Add AI badge to title for AI-powered alerts
            if alert.hasAIFeatures {
                title = "🤖 " + title
            }
            
            // Append AI reason if available
            if let reason = aiReason, !reason.isEmpty {
                body += "\n\n💡 AI Insight: \(reason)"
            }
            
            content.title = title
            content.body = body
            content.sound = .default
            content.badge = 1
            
            // Add category for actions
            content.categoryIdentifier = "PRICE_ALERT"
            content.userInfo = [
                "alertID": alert.id.uuidString,
                "conditionType": alert.conditionType.rawValue
            ]
            
            let request = UNNotificationRequest(
                identifier: alert.id.uuidString,
                content: content,
                trigger: nil // Deliver immediately
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("[NotificationsManager] Failed to send notification: \(error)")
                } else {
                    print("[NotificationsManager] ✅ Notification sent for \(alert.symbol) at $\(currentPrice)")
                }
            }
        }
    }
    
    private func buildNotificationContent(for alert: PriceAlert, currentPrice: Double) -> (title: String, body: String) {
        let formattedCurrent = formatPrice(currentPrice)
        let formattedThreshold = formatPrice(alert.threshold)
        let currencySymbol = CurrencyManager.symbol
        
        switch alert.conditionType {
        case .priceAbove:
            return (
                "📈 Price Alert: \(alert.symbol)",
                "\(alert.symbol) has risen above \(currencySymbol)\(formattedThreshold). Current: \(currencySymbol)\(formattedCurrent)"
            )
            
        case .priceBelow:
            return (
                "📉 Price Alert: \(alert.symbol)",
                "\(alert.symbol) has fallen below \(currencySymbol)\(formattedThreshold). Current: \(currencySymbol)\(formattedCurrent)"
            )
            
        case .percentChangeUp:
            let timeframe = alert.timeframe?.displayName ?? "period"
            return (
                "🚀 \(alert.symbol) Pumping!",
                "\(alert.symbol) is up \(String(format: "%.1f", alert.threshold))% in the last \(timeframe)"
            )
            
        case .percentChangeDown:
            let timeframe = alert.timeframe?.displayName ?? "period"
            return (
                "🔻 \(alert.symbol) Dropping!",
                "\(alert.symbol) is down \(String(format: "%.1f", alert.threshold))% in the last \(timeframe)"
            )
            
        case .rsiAbove:
            let rsi = rsiCache[alert.symbol] ?? 0
            return (
                "⚡ RSI Alert: \(alert.symbol)",
                "\(alert.symbol) RSI has crossed above \(Int(alert.threshold)). Current RSI: \(Int(rsi))"
            )
            
        case .rsiBelow:
            let rsi = rsiCache[alert.symbol] ?? 0
            return (
                "📊 RSI Alert: \(alert.symbol)",
                "\(alert.symbol) RSI has dropped below \(Int(alert.threshold)). Current RSI: \(Int(rsi))"
            )
            
        case .volumeSpike:
            let multiplier = alert.volumeMultiplier ?? 2.0
            return (
                "📊 Volume Spike: \(alert.symbol)",
                "\(alert.symbol) volume is \(String(format: "%.1f", multiplier))x above average!"
            )
            
        case .portfolioChange:
            return (
                "💼 Portfolio Alert",
                "Your portfolio has changed by \(String(format: "%.1f", alert.threshold))%"
            )
            
        case .whaleMovement:
            let amount = alert.minWhaleAmount ?? 1_000_000
            return (
                "🐋 Whale Alert: \(alert.symbol)",
                "Large \(alert.symbol) movement detected (>\(currencySymbol)\(MarketFormat.largeNumber(amount)))"
            )
        }
    }
    
    private func formatPrice(_ price: Double) -> String {
        if price >= 1 {
            return String(format: "%.2f", price)
        } else if price >= 0.01 {
            return String(format: "%.4f", price)
        } else {
            return String(format: "%.6f", price)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap - could navigate to alert details
        let userInfo = response.notification.request.content.userInfo
        if let alertIDString = userInfo["alertID"] as? String,
           let _ = UUID(uuidString: alertIDString) {
            // Post notification for UI to respond
            NotificationCenter.default.post(name: .priceAlertTapped, object: nil, userInfo: userInfo)
        }
        completionHandler()
    }
    
    // MARK: - Utility
    
    func currentPrice(for symbol: String) -> Double? {
        return priceCache[symbol]
    }
    
    var hasActiveAlerts: Bool {
        !allAlerts.isEmpty
    }
    
    var untriggeredAlertsCount: Int {
        alerts.filter { !triggeredAlertIDs.contains($0.id) }.count
    }
}

// MARK: - Notification Name Extension

extension Notification.Name {
    static let priceAlertTapped = Notification.Name("priceAlertTapped")
    static let alertTriggered = Notification.Name("alertTriggered")
}

// MARK: - WhaleTrackingDelegate Protocol

/// Protocol for receiving whale movement alerts from WhaleTrackingService
public protocol WhaleAlertDelegate: AnyObject {
    func didDetectWhaleMovement(symbol: String, amount: Double, fromAddress: String?, toAddress: String?)
}

extension NotificationsManager: WhaleAlertDelegate {
    func didDetectWhaleMovement(symbol: String, amount: Double, fromAddress: String?, toAddress: String?) {
        // Check if any whale alerts match this movement
        let whaleAlerts = advancedAlerts.filter { 
            $0.conditionType == .whaleMovement && 
            $0.symbol.uppercased() == symbol.uppercased() &&
            !triggeredAlertIDs.contains($0.id)
        }
        
        for alert in whaleAlerts {
            let minAmount = alert.minWhaleAmount ?? 1_000_000
            
            // Check if movement meets minimum threshold
            guard amount >= minAmount else { continue }
            
            // Check if watching specific wallet
            if let watchedWallet = alert.walletAddress?.lowercased(),
               !watchedWallet.isEmpty {
                let fromMatch = fromAddress?.lowercased() == watchedWallet
                let toMatch = toAddress?.lowercased() == watchedWallet
                guard fromMatch || toMatch else { continue }
            }
            
            // Trigger the alert
            Task { @MainActor in
                triggerAlert(alert, currentPrice: amount)
            }
        }
    }
}
