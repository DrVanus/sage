import Foundation
import Combine
import FirebaseFirestore
import os

/// FirestoreMarketSync provides real-time market data synchronization via Firestore.
/// This ensures all devices see identical data by listening to the same Firestore document
/// that the backend updates every minute.
///
/// Data flow:
/// 1. Backend (syncMarketDataToFirestore) polls Binance every 1 minute
/// 2. Backend writes to Firestore: marketData/heatmap
/// 3. iOS devices listen via addSnapshotListener
/// 4. All devices receive the same data simultaneously
///
/// DATA CONSISTENCY: This is the PRIMARY source of truth for market data.
/// When working correctly, all devices see identical percentage changes and colors.
final class FirestoreMarketSync: ObservableObject {
    static let shared = FirestoreMarketSync()
    private static let maxCoinGeckoEmitCount = 250
    
    private let logger = Logger(subsystem: "CryptoSage", category: "FirestoreMarketSync")
    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    private var coingeckoListenerRegistration: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()
    
    // MEMORY FIX v8: Ensure Firestore listeners are cleaned up on deallocation
    deinit {
        listenerRegistration?.remove()
        coingeckoListenerRegistration?.remove()
    }
    
    // Subject to broadcast ticker updates (Binance heatmap data)
    private let tickerSubject = PassthroughSubject<[String: FirestoreTicker], Never>()
    
    // Subject to broadcast CoinGecko market data (full coin list with sparklines)
    private let coingeckoCoinsSubject = PassthroughSubject<[MarketCoin], Never>()
    
    /// Publisher for ticker updates from Firestore
    var tickerPublisher: AnyPublisher<[String: FirestoreTicker], Never> {
        tickerSubject.eraseToAnyPublisher()
    }
    
    /// Publisher for CoinGecko coin data from Firestore (full market data with sparklines, percentages)
    var coingeckoCoinsPublisher: AnyPublisher<[MarketCoin], Never> {
        coingeckoCoinsSubject.eraseToAnyPublisher()
    }
    
    /// Ticker data structure matching the backend's format
    struct FirestoreTicker {
        let price: Double
        let change24h: Double
        let change1h: Double?  // NEW: 1H change for consistency across devices (only for top coins)
        let volume: Double
        let quoteVolume: Double
        let symbol: String  // Full symbol like "BTCUSDT"
    }
    
    // DATA CONSISTENCY: Diagnostic state for debugging sync issues
    enum SyncStatus: String {
        case disconnected = "disconnected"
        case connecting = "connecting"
        case connected = "connected"
        case documentMissing = "document_missing"
        case documentEmpty = "document_empty"
        case parseError = "parse_error"
        case staleData = "stale_data"
    }

    enum FreshnessState: String {
        case fresh = "fresh"
        case stale = "stale"
        case unavailable = "unavailable"
    }
    
    // Track connection state
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var tickerCount: Int = 0
    
    // Track CoinGecko market data freshness
    @Published private(set) var lastCoinGeckoSyncAt: Date?
    @Published private(set) var coinGeckoCount: Int = 0
    @Published private(set) var tickerFreshness: FreshnessState = .unavailable
    @Published private(set) var coinGeckoFreshness: FreshnessState = .unavailable
    
    // DATA CONSISTENCY: Enhanced diagnostics
    @Published private(set) var syncStatus: SyncStatus = .disconnected
    @Published private(set) var lastError: String?
    @Published private(set) var successfulSyncs: Int = 0
    @Published private(set) var failedSyncs: Int = 0
    
    // PERFORMANCE FIX v15: Throttle emissions to reduce UI update frequency
    private var lastEmissionAt: Date = .distantPast
    // PERFORMANCE FIX v20: Queue deferred updates instead of dropping them during scroll
    private var pendingTickerEmission: [String: FirestoreTicker]?
    private var pendingCoinGeckoEmission: [MarketCoin]?
    private var scrollEndWorkItem: DispatchWorkItem?
    // COLD START FIX: The very first ticker and CoinGecko emissions must always go through
    // so LivePriceManager can populate HeatMap and other views even if the user is scrolling.
    private var hasCompletedFirstTickerEmission = false
    private var hasCompletedFirstCoinGeckoEmission = false
    
    // PERFORMANCE v26: Hash-based deduplication to skip identical snapshots
    private var lastTickerSnapshotHash: Int = 0
    private var lastCoinGeckoSnapshotHash: Int = 0
    
    private init() {
        #if targetEnvironment(simulator)
        // MEMORY FIX v5.0.13: Use in-memory cache on simulator.
        // PersistentCacheSettings creates an SQLite database and background gRPC
        // connections that continuously allocate memory (~15 MB/3s) even without
        // active snapshot listeners. MemoryCacheSettings eliminates all disk I/O
        // and background network threads from Firestore.
        let settings = FirestoreSettings()
        settings.cacheSettings = MemoryCacheSettings()
        db.settings = settings
        logger.info("🔥 [FirestoreMarketSync] Initialized with memory-only cache (Simulator)")
        #else
        // Restore persistent offline cache for stable listener behavior across launches.
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings
        logger.info("🔥 [FirestoreMarketSync] Initialized with offline persistence")
        #endif
    }
    
    /// Start listening to the heatmap document in Firestore
    /// Also starts listening to CoinGecko market data (marketData/coingeckoMarkets)
    /// Call this after Firebase is configured
    func startListening() {
        guard listenerRegistration == nil else {
            logger.debug("🔥 [FirestoreMarketSync] Already listening, skipping duplicate start")
            return
        }
        
        logger.info("🔥 [FirestoreMarketSync] Starting Firestore listeners for marketData/heatmap + coingeckoMarkets")
        
        // Start CoinGecko markets listener (primary market data source)
        startCoinGeckoMarketsListener()
        
        // DATA CONSISTENCY: Update status to connecting
        DispatchQueue.main.async { [weak self] in
            self?.syncStatus = .connecting
            self?.lastError = nil
        }
        
        let docRef = db.collection("marketData").document("heatmap")
        
        listenerRegistration = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("🔥 [FirestoreMarketSync] Listener error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.syncStatus = .disconnected
                    self.lastError = "Listener error: \(error.localizedDescription)"
                    self.failedSyncs += 1
                }
                return
            }
            
            guard let snapshot = snapshot else {
                self.logger.warning("🔥 [FirestoreMarketSync] Snapshot is nil - document may not exist")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.syncStatus = .documentMissing
                    self.lastError = "Snapshot is nil - ensure Firebase Cloud Function syncMarketDataToFirestore is deployed and running"
                    self.failedSyncs += 1
                }
                return
            }
            
            guard snapshot.exists else {
                // DATA CONSISTENCY: Document doesn't exist - Cloud Function may not be deployed
                self.logger.warning("🔥 [FirestoreMarketSync] Document marketData/heatmap does not exist - Cloud Function may not be deployed")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.syncStatus = .documentMissing
                    self.lastError = "Document marketData/heatmap does not exist. Deploy Firebase Cloud Function: syncMarketDataToFirestore"
                    self.failedSyncs += 1
                }
                return
            }
            
            // Parse the document data
            self.parseSnapshot(snapshot)
        }
    }
    
    /// Stop listening to Firestore updates
    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        coingeckoListenerRegistration?.remove()
        coingeckoListenerRegistration = nil
        scrollEndWorkItem?.cancel()
        scrollEndWorkItem = nil
        pendingTickerEmission = nil
        pendingCoinGeckoEmission = nil
        isConnected = false
        syncStatus = .disconnected
        tickerFreshness = .unavailable
        coinGeckoFreshness = .unavailable
        logger.info("🔥 [FirestoreMarketSync] Stopped all Firestore listeners")
    }
    
    /// DATA CONSISTENCY: Get diagnostic information for debugging
    func getDiagnostics() -> String {
        var info: [String] = []
        info.append("Status: \(syncStatus.rawValue)")
        info.append("Connected: \(isConnected)")
        info.append("Ticker count: \(tickerCount)")
        info.append("Successful syncs: \(successfulSyncs)")
        info.append("Failed syncs: \(failedSyncs)")
        if let lastSync = lastSyncAt {
            let age = Int(Date().timeIntervalSince(lastSync))
            info.append("Last sync: \(age)s ago")
        } else {
            info.append("Last sync: never")
        }
        if let error = lastError {
            info.append("Last error: \(error)")
        }
        return info.joined(separator: ", ")
    }
    
    /// Parse a Firestore snapshot into ticker data
    private func parseSnapshot(_ snapshot: DocumentSnapshot) {
        guard let data = snapshot.data() else {
            logger.warning("🔥 [FirestoreMarketSync] Snapshot has no data")
            DispatchQueue.main.async { [weak self] in
                self?.syncStatus = .documentEmpty
                self?.lastError = "Document exists but has no data"
                self?.failedSyncs += 1
            }
            return
        }
        
        // Parse tickers manually since Firestore doesn't use Codable directly
        guard let tickersRaw = data["tickers"] as? [String: [String: Any]] else {
            logger.warning("🔥 [FirestoreMarketSync] Missing or invalid 'tickers' field")
            DispatchQueue.main.async { [weak self] in
                self?.syncStatus = .parseError
                self?.lastError = "Document missing 'tickers' field - check Cloud Function output format"
                self?.failedSyncs += 1
            }
            return
        }
        
        var tickers: [String: FirestoreTicker] = [:]
        var parseErrors = 0
        
        func asDouble(_ raw: Any?) -> Double? {
            switch raw {
            case let v as Double:
                return v
            case let v as Int:
                return Double(v)
            case let v as NSNumber:
                return v.doubleValue
            case let v as String:
                return Double(v)
            default:
                return nil
            }
        }
        
        for (symbol, tickerData) in tickersRaw {
            guard let price = asDouble(tickerData["price"]),
                  let change24h = asDouble(tickerData["change24h"]),
                  let volume = asDouble(tickerData["volume"]),
                  let quoteVolume = asDouble(tickerData["quoteVolume"]),
                  let fullSymbol = tickerData["symbol"] as? String else {
                parseErrors += 1
                continue
            }
            
            // NEW: Read optional change1h field (only present for top coins)
            let change1h = asDouble(tickerData["change1h"])
            
            tickers[symbol] = FirestoreTicker(
                price: price,
                change24h: change24h,
                change1h: change1h,
                volume: volume,
                quoteVolume: quoteVolume,
                symbol: fullSymbol
            )
        }
        
        if parseErrors > 0 {
            logger.debug("🔥 [FirestoreMarketSync] Skipped \(parseErrors) tickers due to parse errors")
        }
        
        let count = data["tickerCount"] as? Int ?? tickers.count
        let syncedAt = data["syncedAt"] as? String
        let source = data["source"] as? String ?? "unknown"
        
        // DATA CONSISTENCY: Check for stale data
        var dataAge: TimeInterval = 0
        var parsedSyncDate: Date?
        if let syncedAt = syncedAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: syncedAt) {
                parsedSyncDate = date
                dataAge = Date().timeIntervalSince(date)
            }
        }
        
        // Reject stale snapshots so old backend payloads are never emitted as live data.
        if dataAge > 120 {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.syncStatus = .staleData
                self.tickerFreshness = .stale
                self.lastError = "Ticker data is \(Int(dataAge))s old - rejecting stale snapshot"
                self.failedSyncs += 1
            }
            logger.warning("🔥 [FirestoreMarketSync] Rejected stale ticker snapshot (age=\(Int(dataAge))s)")
            return
        }

        // Update state on main thread
        // PERFORMANCE FIX v16: Defer state updates during scroll to avoid triggering UI re-renders
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Skip @Published property updates during scroll (they cause UI re-renders)
            // Connection status can be updated after scroll ends
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else {
                // Still update internal state but without triggering @Published didSet
                return
            }
            
            self.isConnected = true
            self.tickerCount = count
            self.lastSyncAt = parsedSyncDate ?? Date()
            self.successfulSyncs += 1
            self.lastError = nil
            self.syncStatus = .connected
            self.tickerFreshness = .fresh
        }
        
        // PERFORMANCE v26: Increased throttle from 15s to 30s. The backend updates Firestore
        // every ~60s, but Firestore's addSnapshotListener fires TWICE per update (once from
        // local cache, once from server). At 30s, we guarantee at most 2 emissions per minute,
        // cutting redundant processing in half compared to 15s.
        let now = Date()
        guard now.timeIntervalSince(lastEmissionAt) >= 30.0 else {
            return  // Silently throttle - no log needed for normal operation
        }
        
        // PERFORMANCE v26: Hash-based deduplication - skip if data is identical to last emission
        // Firestore local cache + server snapshots often carry the same data
        let snapshotHash = tickers.reduce(0) { $0 ^ $1.key.hashValue ^ $1.value.change24h.hashValue }
        if snapshotHash == lastTickerSnapshotHash && hasCompletedFirstTickerEmission {
            return  // Identical data, skip
        }
        
        // DATA CONSISTENCY: Log sample data for debugging (only when data actually passes through)
        #if DEBUG
        if let btcTicker = tickers["BTC"] {
            let change1hStr = btcTicker.change1h.map { String(format: "%.2f", $0) } ?? "n/a"
            logger.info("🔥 [FirestoreMarketSync] BTC change24h: \(String(format: "%.2f", btcTicker.change24h))%, change1h: \(change1hStr)% (from \(source))")
        }
        
        let coinsWithChange1h = tickers.values.filter { $0.change1h != nil }.count
        logger.info("🔥 [FirestoreMarketSync] Received \(tickers.count) tickers (\(coinsWithChange1h) with 1H data) from \(source), age: \(Int(dataAge))s")
        #endif
        
        // COLD START FIX: First emission always goes through to populate views
        let isFirstTickerEmission = !hasCompletedFirstTickerEmission
        
        // PERFORMANCE FIX v20: Queue updates during scroll instead of dropping them
        // When scroll ends, the latest queued data is emitted so prices stay fresh
        if !isFirstTickerEmission && ScrollStateAtomicStorage.shared.shouldBlock() {
            pendingTickerEmission = tickers
            scheduleScrollEndFlush()
            return
        }
        
        if isFirstTickerEmission { hasCompletedFirstTickerEmission = true }
        lastEmissionAt = now
        lastTickerSnapshotHash = snapshotHash
        pendingTickerEmission = nil  // Clear any queued data since we're emitting fresh
        
        // Emit the tickers through the subject
        tickerSubject.send(tickers)
    }
    
    /// PERFORMANCE FIX v25: Schedule a STAGGERED flush of queued data when scroll ends.
    /// Instead of flushing ticker + CoinGecko data simultaneously (which caused a burst of
    /// heavy main-thread work after every scroll), this now:
    /// 1. Waits 1.0s after scroll stops (cooldown for the UI to settle and deceleration to finish)
    /// 2. Flushes ticker data first (lighter - just price updates)
    /// 3. Waits another 0.8s before flushing CoinGecko data (heavier - 250 coin merge)
    /// This prevents the "pause after scroll stops" that users experience.
    ///
    /// v25 improvements over v21:
    /// - Increased cooldown from 0.8s to 1.0s to better handle momentum deceleration
    /// - Increased CoinGecko stagger from 0.6s to 0.8s for smoother resume
    /// - Uses a single delayed dispatch instead of a polling timer (avoids repeated 0.8s checks)
    private func scheduleScrollEndFlush() {
        // Don't schedule multiple flushes
        guard scrollEndWorkItem == nil else { return }
        
        let flushWork = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.scrollEndWorkItem = nil
            
            // Wait until scroll has fully stopped (not just paused)
            guard !ScrollStateAtomicStorage.shared.shouldBlock() else {
                self.scheduleScrollEndFlush()
                return
            }
            
            // PHASE 1: Flush ticker data first (lighter operation)
            if let pending = self.pendingTickerEmission {
                self.lastEmissionAt = Date()
                self.tickerSubject.send(pending)
                self.pendingTickerEmission = nil
                self.logger.info("🔥 [FirestoreMarketSync] Flushed queued ticker data after scroll ended")
            }
            
            // PHASE 2: Stagger CoinGecko flush by 800ms to avoid burst
            // This gives LivePriceManager time to process ticker data before the heavier
            // CoinGecko ingestion arrives.
            guard self.pendingCoinGeckoEmission != nil else { return }
            let staggeredCoinGeckoFlush = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.scrollEndWorkItem = nil
                // Re-check scroll state - user might have started scrolling again
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else {
                    self.scheduleScrollEndFlush()
                    return
                }
                if let pending = self.pendingCoinGeckoEmission {
                    self.lastCoinGeckoEmissionAt = Date()
                    self.coingeckoCoinsSubject.send(pending)
                    self.pendingCoinGeckoEmission = nil
                    self.logger.info("🔥 [FirestoreMarketSync] Flushed queued CoinGecko data (staggered) after scroll ended")
                }
            }
            self.scrollEndWorkItem = staggeredCoinGeckoFlush
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: staggeredCoinGeckoFlush)
        }
        
        scrollEndWorkItem = flushWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: flushWork)
    }
    
    /// Check if Firestore ticker data is fresh (updated within last 45 seconds).
    /// This stricter window forces earlier overlay takeover when backend freshness degrades.
    var isDataFresh: Bool {
        guard let lastSync = lastSyncAt else { return false }
        return Date().timeIntervalSince(lastSync) < 45
    }
    
    /// Check if CoinGecko market data from Firestore is fresh (< 5 minutes old)
    /// When this is true, the iOS app can skip direct CoinGecko polling.
    /// Keeps UI data tighter to the backend's intended 5-minute cadence.
    var isCoinGeckoDataFresh: Bool {
        guard let lastSync = lastCoinGeckoSyncAt else { return false }
        return Date().timeIntervalSince(lastSync) < 300
    }
    
    // MARK: - CoinGecko Markets Listener
    
    /// Emission throttle for CoinGecko data (same pattern as heatmap)
    private var lastCoinGeckoEmissionAt: Date = .distantPast
    
    /// Start a real-time listener for the CoinGecko market data document
    /// This document contains up to 250 coins with sparklines, prices, and percentages
    /// Updated by the backend every 60 seconds via syncMarketDataToFirestore
    private func startCoinGeckoMarketsListener() {
        guard coingeckoListenerRegistration == nil else {
            logger.debug("🔥 [FirestoreMarketSync] CoinGecko listener already active")
            return
        }
        
        let docRef = db.collection("marketData").document("coingeckoMarkets")
        
        coingeckoListenerRegistration = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("🔥 [FirestoreMarketSync] CoinGecko listener error: \(error.localizedDescription)")
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists, let data = snapshot.data() else {
                self.logger.warning("🔥 [FirestoreMarketSync] CoinGecko document not found - backend may not have synced yet")
                return
            }
            
            self.parseCoinGeckoSnapshot(data)
        }
    }
    
    /// Parse the CoinGecko markets document into MarketCoin array
    private func parseCoinGeckoSnapshot(_ data: [String: Any]) {
        guard let coinsArray = data["coins"] as? [[String: Any]] else {
            logger.warning("🔥 [FirestoreMarketSync] CoinGecko document missing 'coins' array")
            return
        }
        
        let source = data["source"] as? String ?? "unknown"
        let syncedAt = data["syncedAt"] as? String
        let coinCount = data["coinCount"] as? Int ?? coinsArray.count
        
        // Parse syncedAt for staleness check
        var dataAge: TimeInterval = 0
        var parsedSyncDate: Date?
        if let syncedAt = syncedAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: syncedAt) {
                parsedSyncDate = date
                dataAge = Date().timeIntervalSince(date)
            }
        }
        
        // Staleness check: skip if data is older than 6 minutes.
        // MEMORY FIX v12: Increased from 180s to 360s to match isCoinGeckoDataFresh and the
        // Cloud Function's 5-minute sync schedule. At 180s, data was always detected as stale
        // for 2 minutes of every 5-minute cycle, causing the app to skip valid Firestore data
        // and trigger the heavy direct CoinGecko API fallback path on startup.
        // 360s gives a comfortable buffer over the 5-minute interval.
        if dataAge > 360 {
            DispatchQueue.main.async { [weak self] in
                self?.coinGeckoFreshness = .stale
            }
            logger.warning("🔥 [FirestoreMarketSync] CoinGecko data is \(Int(dataAge))s old - stale, skipping")
            return
        }
        
        // Decode each coin dictionary into MarketCoin using JSONSerialization + JSONDecoder
        // This leverages MarketCoin's existing Codable conformance
        var coins: [MarketCoin] = []
        coins.reserveCapacity(coinsArray.count)
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: coinsArray, options: [])
            let decoded = try JSONDecoder().decode([MarketCoin].self, from: jsonData)
            coins = decoded
        } catch {
            logger.error("🔥 [FirestoreMarketSync] Failed to decode CoinGecko coins: \(error.localizedDescription)")
            return
        }
        
        guard !coins.isEmpty else {
            logger.warning("🔥 [FirestoreMarketSync] CoinGecko decoded 0 coins")
            return
        }
        
        // Update state on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastCoinGeckoSyncAt = parsedSyncDate ?? Date()
            self.coinGeckoCount = coinCount
            self.coinGeckoFreshness = .fresh
        }
        
        // PERFORMANCE v26: Increased throttle from 15s to 30s (same as ticker emissions).
        let now = Date()
        guard now.timeIntervalSince(lastCoinGeckoEmissionAt) >= 30.0 else {
            return  // Silently throttle
        }
        
        // PERFORMANCE v26: Hash-based deduplication for CoinGecko data
        let snapshotHash = coins.reduce(0) { $0 ^ ($1.id.hashValue) ^ ($1.priceUsd?.hashValue ?? 0) }
        if snapshotHash == lastCoinGeckoSnapshotHash && hasCompletedFirstCoinGeckoEmission {
            return
        }
        
        // Log sample data only when data passes through throttle
        #if DEBUG
        if let btc = coins.first(where: { $0.id == "bitcoin" }) {
            let pctStr = btc.priceChangePercentage24hInCurrency.map { String(format: "%.2f", $0) } ?? "n/a"
            logger.info("🔥 [FirestoreMarketSync] CoinGecko: BTC $\(btc.priceUsd ?? 0, privacy: .public), 24h: \(pctStr)% (from \(source), age: \(Int(dataAge))s)")
        }
        logger.info("🔥 [FirestoreMarketSync] CoinGecko: received \(coins.count) coins from Firestore")
        #endif
        
        // COLD START FIX: First CoinGecko emission always goes through so HeatMap gets data
        let isFirstCoinGeckoEmission = !hasCompletedFirstCoinGeckoEmission
        
        // PERFORMANCE FIX v20: Queue during scroll instead of dropping
        if !isFirstCoinGeckoEmission && ScrollStateAtomicStorage.shared.shouldBlock() {
            pendingCoinGeckoEmission = coins.count > Self.maxCoinGeckoEmitCount ? Array(coins.prefix(Self.maxCoinGeckoEmitCount)) : coins
            scheduleScrollEndFlush()
            return
        }
        
        if isFirstCoinGeckoEmission { hasCompletedFirstCoinGeckoEmission = true }
        lastCoinGeckoEmissionAt = now
        lastCoinGeckoSnapshotHash = snapshotHash
        pendingCoinGeckoEmission = nil  // Clear queued data
        // Keep Firestore CoinGecko feed aligned with the app's 250-coin market universe.
        let capped = coins.count > Self.maxCoinGeckoEmitCount ? Array(coins.prefix(Self.maxCoinGeckoEmitCount)) : coins
        coingeckoCoinsSubject.send(capped)
    }
}
