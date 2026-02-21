//
//  AIPortfolioMonitor.swift
//  CryptoSage
//
//  Smart market alert system that eliminates per-user AI calls.
//
//  Architecture (v2 — Server-Side Digest + Client-Side Matching):
//    1. A Firebase Cloud Function (evaluateMarketAlerts) runs every 5 minutes
//       and evaluates market conditions ONCE for ALL users, writing an
//       "alertDigest" to Firestore.
//    2. Each iOS client listens to marketData/alertDigest via a snapshot listener.
//    3. When a new digest arrives, the client locally matches signals to the
//       user's held coins — no AI call needed.
//    4. Local portfolio value change detection (±3%) runs alongside, comparing
//       the user's portfolio total against their previous snapshot. This is the
//       ONLY per-user logic; it uses simple string formatting, not AI.
//
//  Cost:
//    Before: N users × 12 scans/hour = 12N AI calls/hour
//    After:  ≤12 AI calls/hour total (server-side) + 0 per-user calls
//
//  Premium feature (Pro+). Toggle on/off via Settings or NotificationsView.
//

import Foundation
import Combine
import FirebaseFirestore
import UserNotifications
import os

// MARK: - Portfolio Event Types

/// The kind of significant event the monitor detected
enum PortfolioEventKind: String, Codable {
    case largeDrop          // A held coin dropped significantly
    case largeGain          // A held coin gained significantly
    case portfolioDrop      // Overall portfolio value dropped
    case portfolioGain      // Overall portfolio value gained
    case sentimentShift     // Fear & Greed changed significantly
    case btcMajorMove       // Bitcoin made a market-moving swing
    case marketWideMove     // Broad market shift (market cap, dominance)
    case breakingNews       // High-impact news relevant to user's holdings
}

/// A significant portfolio event detected by the monitor
struct PortfolioEvent: Identifiable, Codable {
    let id: UUID
    let kind: PortfolioEventKind
    let symbol: String?
    let changePercent: Double
    let aiSummary: String
    let timestamp: Date
    let isRead: Bool
    
    init(kind: PortfolioEventKind, symbol: String? = nil, changePercent: Double = 0, aiSummary: String) {
        self.id = UUID()
        self.kind = kind
        self.symbol = symbol
        self.changePercent = changePercent
        self.aiSummary = aiSummary
        self.timestamp = Date()
        self.isRead = false
    }
    
    init(id: UUID, kind: PortfolioEventKind, symbol: String?, changePercent: Double, aiSummary: String, timestamp: Date, isRead: Bool) {
        self.id = id
        self.kind = kind
        self.symbol = symbol
        self.changePercent = changePercent
        self.aiSummary = aiSummary
        self.timestamp = timestamp
        self.isRead = isRead
    }
}

// MARK: - Alert Digest Model (matches Firestore document written by Cloud Function)

/// Server-side alert digest — written once by the Cloud Function, consumed by all clients.
struct AlertDigest {
    let timestamp: Date
    let signals: [AlertSignal]
    let marketSnapshot: MarketSnapshot
    let topMovers: [TopMover]
    let breakingNews: [BreakingNewsItem]
    
    struct MarketSnapshot {
        let btcPrice: Double
        let btcChange1h: Double
        let btcChange24h: Double
        let globalMarketCap: Double
        let globalChange24h: Double
        let fearGreedValue: Int
        let fearGreedLabel: String
        let btcDominance: Double
    }
    
    struct TopMover {
        let symbol: String
        let change1h: Double
        let price: Double
    }
    
    struct BreakingNewsItem {
        let title: String
        let source: String
        let relevantSymbols: [String]
    }
}

/// A single alert signal from the server-side digest
struct AlertSignal {
    let type: String
    let severity: String       // "low", "medium", "high"
    let affectedSymbols: [String]
    let changePercent: Double
    let title: String          // Pre-written notification title
    let summary: String        // Pre-written notification body
}

enum AIAlertCoverageMode: String, Codable, CaseIterable {
    case marketAndPortfolio
    case portfolioOnly
}

enum DigestListenerHealth: String {
    case idle
    case listening
    case retrying
    case error
}

// MARK: - AI Portfolio Monitor (v2 — Digest-Driven)

@MainActor
final class AIPortfolioMonitor: ObservableObject {
    
    static let shared = AIPortfolioMonitor()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CryptoSage",
                                 category: "AIPortfolioMonitor")
    
    // MARK: - Published State
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "AIPortfolioMonitor.enabled")
            if isEnabled { startMonitoring() } else { stopMonitoring() }
        }
    }
    @Published var coverageMode: AIAlertCoverageMode {
        didSet {
            UserDefaults.standard.set(coverageMode.rawValue, forKey: "AIPortfolioMonitor.coverageMode")
        }
    }
    
    @Published var recentEvents: [PortfolioEvent] = []
    @Published private(set) var isMonitoring: Bool = false
    @Published private(set) var listenerHealth: DigestListenerHealth = .idle
    @Published private(set) var lastDigestReceivedAt: Date?
    @Published private(set) var lastNotificationSentAt: Date?
    
    // MARK: - Thresholds (local portfolio only — market thresholds are server-side)
    
    private let portfolioThreshold: Double = 3.0  // ±3% portfolio total change
    /// If last baseline is too old, re-baseline instead of comparing stale snapshots.
    private let maxSnapshotAgeForComparison: TimeInterval = 6 * 60 * 60
    /// Prevents notification bursts right after app launch/re-attach.
    private let startupNotificationSuppressionDuration: TimeInterval = 90
    
    // MARK: - Anti-spam
    
    private let cooldownPerKind: TimeInterval = 3 * 60 * 60   // 3 hours per event kind
    private let globalCooldown: TimeInterval = 20 * 60          // 20 min between any alerts
    private let maxAlertsPerDay: Int = 5
    private let macroSignalTypes: Set<String> = ["btcMajorMove", "marketWideMove", "sentimentShift", "breakingNews"]
    private let majorCoinsForNoInterestFallback: Set<String> = ["BTC", "ETH"]
    private let minSeverityForMacroWithoutInterests: Int = 2 // medium
    private let minSeverityForMajorCoinWithoutInterests: Int = 3 // high
    
    // MARK: - Internal State
    
    private let db = Firestore.firestore()
    private var digestListener: ListenerRegistration?
    private var holdingsCancellable: AnyCancellable?
    private var currentHoldings: [Holding] = []
    private var digestRetryTask: Task<Void, Never>?
    private var digestRetryAttempt: Int = 0
    
    private var lastAlertTimeByKind: [String: Date] = [:]
    private var lastAnyAlertTime: Date?
    private var alertsSentToday: Int = 0
    private var alertCountResetDate: Date = Date()
    
    /// Last known portfolio value — used for local portfolio change detection
    private var previousPortfolioValue: Double = 0
    private var previousPortfolioTimestamp: Date?
    /// Requires two complete snapshots before portfolio-change alerts are eligible.
    private var hasConfirmedPortfolioBaseline: Bool = false
    private let confirmedPortfolioBaselineKey = "AIPortfolioMonitor.confirmedPortfolioBaseline"
    private var previousPortfolioSourceMode: PortfolioSourceMode = .none
    private let previousPortfolioSourceModeKey = "AIPortfolioMonitor.prevPortfolioSourceMode"
    private var suppressAlertsUntil: Date = .distantPast
    
    /// Tracks the last digest timestamp to avoid re-processing
    private var lastProcessedDigestTimestamp: String?
    /// Baseline guard: first digest observed after listener attach should not notify.
    private var hasEstablishedDigestBaseline: Bool = false
    private let lastProcessedDigestTimestampKey = "AIPortfolioMonitor.lastProcessedDigestTimestamp"
    
    deinit {
        digestListener?.remove()
        digestRetryTask?.cancel()
    }
    
    private var currentTotalValue: Double { currentHoldings.reduce(0) { $0 + $1.currentValue } }
    
    // MARK: - Init
    
    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "AIPortfolioMonitor.enabled")
        self.coverageMode = AIAlertCoverageMode(rawValue: UserDefaults.standard.string(forKey: "AIPortfolioMonitor.coverageMode") ?? "")
            ?? .marketAndPortfolio
        self.lastProcessedDigestTimestamp = UserDefaults.standard.string(forKey: lastProcessedDigestTimestampKey)
        loadRecentEvents()
        loadPreviousPortfolioSnapshot()
        resetDailyCountIfNeeded()
        
        holdingsCancellable = PortfolioRepository.shared.holdingsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] holdings in self?.currentHoldings = holdings }
    }
    
    // MARK: - Start / Stop
    
    func startMonitoring() {
        guard isEnabled else { return }
        guard SubscriptionManager.shared.hasAccess(to: .aiPoweredAlerts) else {
            logger.info("AI Portfolio Monitor requires Pro — not starting")
            return
        }
        guard !isMonitoring else { return }
        isMonitoring = true
        listenerHealth = .listening
        suppressAlertsUntil = Date().addingTimeInterval(startupNotificationSuppressionDuration)
        logger.info("🤖 AI Portfolio Monitor v2 started (digest-driven, zero per-user AI calls)")
        
        startDigestListener()
    }
    
    func stopMonitoring() {
        digestListener?.remove()
        digestListener = nil
        digestRetryTask?.cancel()
        digestRetryTask = nil
        digestRetryAttempt = 0
        isMonitoring = false
        listenerHealth = .idle
        logger.info("🤖 AI Portfolio Monitor stopped")
    }
    
    // MARK: - Firestore Digest Listener
    
    /// Listen for new alert digests from the server-side Cloud Function
    private func startDigestListener() {
        // Remove existing listener if any
        digestListener?.remove()
        digestRetryTask?.cancel()
        digestRetryTask = nil
        hasEstablishedDigestBaseline = false
        
        let docRef = db.collection("marketData").document("alertDigest")
        
        digestListener = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                self.listenerHealth = .error
                self.logger.error("🤖 Digest listener error: \(error.localizedDescription)")
                self.scheduleDigestRetry()
                return
            }
            self.listenerHealth = .listening
            self.digestRetryAttempt = 0
            
            guard let data = snapshot?.data() else {
                self.logger.debug("🤖 Digest document is empty or does not exist yet")
                return
            }
            
            // Parse the digest
            guard let digest = self.parseDigest(data) else {
                self.logger.warning("🤖 Failed to parse alert digest from Firestore")
                return
            }
            
            // Avoid re-processing the same digest
            let tsKey = data["timestamp"] as? String ?? ""
            if tsKey == self.lastProcessedDigestTimestamp {
                self.hasEstablishedDigestBaseline = true
                return
            }
            
            // First digest after attaching listener is baseline only.
            // This prevents "alert fired on app open" behavior.
            if !self.hasEstablishedDigestBaseline {
                self.hasEstablishedDigestBaseline = true
                self.lastProcessedDigestTimestamp = tsKey
                UserDefaults.standard.set(tsKey, forKey: self.lastProcessedDigestTimestampKey)
                self.logger.debug("🤖 Baseline digest established at startup; skipping notification dispatch")
                return
            }
            
            self.lastProcessedDigestTimestamp = tsKey
            UserDefaults.standard.set(tsKey, forKey: self.lastProcessedDigestTimestampKey)
            
            Task { @MainActor in
                self.handleDigest(digest)
            }
        }
    }

    private func scheduleDigestRetry() {
        guard isEnabled, isMonitoring else { return }
        digestRetryTask?.cancel()
        digestRetryAttempt += 1
        let delaySeconds = min(pow(2.0, Double(min(digestRetryAttempt, 5))) * 5.0, 120.0)
        listenerHealth = .retrying
        digestRetryTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled, self.isEnabled, self.isMonitoring else { return }
            self.logger.info("🤖 Retrying digest listener in \(Int(delaySeconds))s (attempt \(self.digestRetryAttempt))")
            self.startDigestListener()
        }
    }
    
    // MARK: - Digest Parsing
    
    private func parseDigest(_ data: [String: Any]) -> AlertDigest? {
        // Timestamp
        let timestampStr = data["timestamp"] as? String ?? ""
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = isoFormatter.date(from: timestampStr) ?? Date()
        
        // Market snapshot
        let snapshotData = data["marketSnapshot"] as? [String: Any] ?? [:]
        let snapshot = AlertDigest.MarketSnapshot(
            btcPrice: snapshotData["btcPrice"] as? Double ?? 0,
            btcChange1h: snapshotData["btcChange1h"] as? Double ?? 0,
            btcChange24h: snapshotData["btcChange24h"] as? Double ?? 0,
            globalMarketCap: snapshotData["globalMarketCap"] as? Double ?? 0,
            globalChange24h: snapshotData["globalChange24h"] as? Double ?? 0,
            fearGreedValue: snapshotData["fearGreedValue"] as? Int ?? 0,
            fearGreedLabel: snapshotData["fearGreedLabel"] as? String ?? "N/A",
            btcDominance: snapshotData["btcDominance"] as? Double ?? 0
        )
        
        // Signals
        let signalsArray = data["signals"] as? [[String: Any]] ?? []
        let signals = signalsArray.compactMap { s -> AlertSignal? in
            guard let type = s["type"] as? String,
                  let title = s["title"] as? String,
                  let summary = s["summary"] as? String else { return nil }
            return AlertSignal(
                type: type,
                severity: s["severity"] as? String ?? "medium",
                affectedSymbols: s["affectedSymbols"] as? [String] ?? [],
                changePercent: s["changePercent"] as? Double ?? 0,
                title: title,
                summary: summary
            )
        }
        
        // Top movers
        let moversArray = data["topMovers"] as? [[String: Any]] ?? []
        let topMovers = moversArray.compactMap { m -> AlertDigest.TopMover? in
            guard let symbol = m["symbol"] as? String else { return nil }
            return AlertDigest.TopMover(
                symbol: symbol,
                change1h: m["change1h"] as? Double ?? 0,
                price: m["price"] as? Double ?? 0
            )
        }
        
        // Breaking news
        let newsArray = data["breakingNews"] as? [[String: Any]] ?? []
        let breakingNews = newsArray.compactMap { n -> AlertDigest.BreakingNewsItem? in
            guard let title = n["title"] as? String else { return nil }
            return AlertDigest.BreakingNewsItem(
                title: title,
                source: n["source"] as? String ?? "Unknown",
                relevantSymbols: n["relevantSymbols"] as? [String] ?? []
            )
        }
        
        return AlertDigest(
            timestamp: timestamp,
            signals: signals,
            marketSnapshot: snapshot,
            topMovers: topMovers,
            breakingNews: breakingNews
        )
    }
    
    // MARK: - Handle Digest (Client-Side Matching)
    
    /// Match server-side signals to the user's holdings and send local notifications.
    ///
    /// Uses a broad "interested symbols" set that includes:
    /// 1. Real portfolio holdings (exchange-synced + manual)
    /// 2. Paper trading positions (for users still learning)
    /// 3. Watchlist / favorites (coins the user tracks even without holding)
    ///
    /// If the user has NO interests at all, market-wide signals
    /// (BTC moves, sentiment, broad market shifts, major news) are still delivered.
    private func handleDigest(_ digest: AlertDigest) {
        resetDailyCountIfNeeded()
        lastDigestReceivedAt = digest.timestamp
        
        // Suppress digest notifications briefly after launch/re-attach.
        // This avoids "open app -> immediate breaking news push" behavior.
        if Date() < suppressAlertsUntil {
            checkLocalPortfolioChange(marketSnapshot: digest.marketSnapshot, allowNotifications: false)
            logger.debug("🤖 Startup suppression active; skipping digest notifications")
            return
        }
        
        guard alertsSentToday < maxAlertsPerDay else { return }
        guard canSendAnyAlert() else { return }
        
        // Build comprehensive "interested symbols" set from all sources
        let interestedSymbols = buildInterestedSymbols()
        let hasAnyInterest = !interestedSymbols.isEmpty
        
        // ── Match server signals to user's interests ──
        for signal in digest.signals {
            guard canSendAnyAlert(), alertsSentToday < maxAlertsPerDay else { break }
            let severityScore = self.severityScore(signal.severity)
            
            let kind = PortfolioEventKind(rawValue: signal.type) ?? .marketWideMove
            guard canSendAlertForKind(kind) else { continue }
            
            // Portfolio-only mode suppresses broad market alerts for users with no portfolio/watchlist context.
            if coverageMode == .portfolioOnly && !hasAnyInterest {
                continue
            }
            
            let isRelevant: Bool
            if signal.affectedSymbols.isEmpty {
                // Market-wide signals:
                //   - Always relevant if user has crypto interests.
                //   - Also relevant for users with no interests when macro severity is meaningful.
                if hasAnyInterest {
                    isRelevant = true
                } else {
                    let isMacroSignal = macroSignalTypes.contains(signal.type)
                    isRelevant = isMacroSignal && severityScore >= minSeverityForMacroWithoutInterests
                }
            } else {
                // Coin-specific signals: relevant if user is interested in any affected coin
                if hasAnyInterest {
                    isRelevant = !signal.affectedSymbols.filter { interestedSymbols.contains($0) }.isEmpty
                } else {
                    // No interests at all — still alert on high-severity BTC/ETH moves.
                    isRelevant = severityScore >= minSeverityForMajorCoinWithoutInterests
                        && !signal.affectedSymbols.filter({ majorCoinsForNoInterestFallback.contains($0) }).isEmpty
                }
            }
            
            guard isRelevant else { continue }
            let cleanTitle = sanitizeAlertTitle(signal.title, kind: kind)
            let cleanSummary = sanitizeAlertBody(signal.summary, kind: kind)
            
            // Use the pre-written title and summary from the server — NO AI call needed
            let event = PortfolioEvent(
                kind: kind,
                symbol: signal.affectedSymbols.first,
                changePercent: signal.changePercent,
                aiSummary: cleanSummary
            )
            
            recordAndNotify(event: event, notificationTitle: cleanTitle)
        }
        
        // ── Local portfolio value change detection ──
        checkLocalPortfolioChange(marketSnapshot: digest.marketSnapshot, allowNotifications: true)
    }

    private func severityScore(_ severity: String) -> Int {
        switch severity.lowercased() {
        case "high": return 3
        case "medium": return 2
        default: return 1
        }
    }
    
    // MARK: - Build Interested Symbols
    
    /// Gathers all coin symbols the user cares about from every source in the app.
    private func buildInterestedSymbols() -> Set<String> {
        var symbols = Set<String>()
        
        // 1. Real portfolio holdings
        for holding in currentHoldings where holding.assetType == .crypto {
            symbols.insert(holding.coinSymbol.uppercased())
        }
        
        // 2. Paper trading positions (non-stablecoin, non-zero balances)
        let stablecoins: Set<String> = ["USDT", "USDC", "BUSD", "DAI", "TUSD", "USDP", "USD"]
        for (asset, amount) in PaperTradingManager.shared.paperBalances {
            let sym = asset.uppercased()
            if amount > 0.000001 && !stablecoins.contains(sym) {
                symbols.insert(sym)
            }
        }
        
        // 3. Watchlist coins (favorites)
        for coin in MarketViewModel.shared.watchlistCoins {
            symbols.insert(coin.symbol.uppercased())
        }
        
        return symbols
    }
    
    // MARK: - Local Portfolio Change Detection (Lightweight, No AI)
    
    /// Check if the user's portfolio total has changed significantly since the last digest.
    /// Includes both real holdings and paper trading positions.
    /// This is the ONLY per-user logic — it uses simple string formatting, not AI.
    private func checkLocalPortfolioChange(marketSnapshot: AlertDigest.MarketSnapshot, allowNotifications: Bool) {
        let paperSnapshot = paperTradingPortfolioSnapshot()
        if paperSnapshot.hasUnpricedAssets {
            // Avoid false "portfolio up/down" alerts when price feed is incomplete
            // (e.g., BTC temporarily missing while USDT is still priced).
            previousPortfolioValue = 0
            previousPortfolioTimestamp = nil
            hasConfirmedPortfolioBaseline = false
            savePreviousPortfolioSnapshot()
            logger.debug("🤖 Skipping portfolio change check due to incomplete paper pricing (\(paperSnapshot.unpricedAssetCount) unpriced assets)")
            return
        }
        
        // Combine real portfolio + paper trading value for total
        let realTotal = currentTotalValue
        let paperTotal = paperSnapshot.totalValue
        let currentSourceMode = resolvePortfolioSourceMode(realTotal: realTotal, paperTotal: paperTotal)
        if currentSourceMode != previousPortfolioSourceMode {
            previousPortfolioSourceMode = currentSourceMode
            previousPortfolioValue = max(realTotal, 0) + max(paperTotal, 0)
            previousPortfolioTimestamp = Date()
            hasConfirmedPortfolioBaseline = false
            savePreviousPortfolioSnapshot()
            logger.debug("🤖 Re-baselined portfolio snapshot due to source mode change -> \(currentSourceMode.rawValue)")
            return
        }
        
        let currentTotal = max(realTotal, 0) + max(paperTotal, 0)
        guard currentTotal > 0 else { return }
        
        // Store initial snapshot if first time
        if previousPortfolioValue <= 0 {
            previousPortfolioValue = currentTotal
            previousPortfolioTimestamp = Date()
            hasConfirmedPortfolioBaseline = false
            savePreviousPortfolioSnapshot()
            return
        }
        
        // Require one more complete snapshot to confirm baseline before alerting.
        if !hasConfirmedPortfolioBaseline {
            previousPortfolioValue = currentTotal
            previousPortfolioTimestamp = Date()
            hasConfirmedPortfolioBaseline = true
            savePreviousPortfolioSnapshot()
            logger.debug("🤖 Portfolio baseline confirmed (second complete snapshot); alerts now armed")
            return
        }
        
        // Re-baseline stale snapshots to avoid large, misleading jumps after long gaps.
        if let prevTime = previousPortfolioTimestamp,
           Date().timeIntervalSince(prevTime) > maxSnapshotAgeForComparison {
            previousPortfolioValue = currentTotal
            previousPortfolioTimestamp = Date()
            hasConfirmedPortfolioBaseline = false
            savePreviousPortfolioSnapshot()
            logger.debug("🤖 Re-baselined portfolio snapshot due to staleness")
            return
        }
        
        // Ensure enough time has passed (at least 4 minutes)
        if let prevTime = previousPortfolioTimestamp, Date().timeIntervalSince(prevTime) < 4 * 60 {
            return
        }
        
        let changePct = ((currentTotal - previousPortfolioValue) / previousPortfolioValue) * 100
        
        if abs(changePct) >= portfolioThreshold {
            if !allowNotifications {
                previousPortfolioValue = currentTotal
                previousPortfolioTimestamp = Date()
                savePreviousPortfolioSnapshot()
                return
            }
            
            let kind: PortfolioEventKind = changePct < 0 ? .portfolioDrop : .portfolioGain
            guard canSendAlertForKind(kind), canSendAnyAlert(), alertsSentToday < maxAlertsPerDay else {
                // Still update the snapshot so we don't re-alert on stale data
                previousPortfolioValue = currentTotal
                previousPortfolioTimestamp = Date()
                savePreviousPortfolioSnapshot()
                return
            }
            
            // Build contextual notification using market snapshot data — no AI call
            let direction = changePct > 0 ? "up" : "down"
            let pctStr = String(format: "%.1f", abs(changePct))
            
            let summary: String
            if abs(marketSnapshot.btcChange1h) > 2 {
                let btcDir = marketSnapshot.btcChange1h > 0 ? "up" : "down"
                summary = "Your portfolio is \(direction) \(pctStr)% recently. BTC is \(btcDir) \(String(format: "%.1f", abs(marketSnapshot.btcChange1h)))% this hour. Market sentiment: \(marketSnapshot.fearGreedLabel) (\(marketSnapshot.fearGreedValue)/100)."
            } else {
                summary = "Your portfolio is \(direction) \(pctStr)% recently. Overall market \(marketSnapshot.globalChange24h >= 0 ? "up" : "down") \(String(format: "%.1f", abs(marketSnapshot.globalChange24h)))% in 24h."
            }
            
            let title = changePct > 0
                ? "Portfolio up \(pctStr)%"
                : "Portfolio down \(pctStr)%"
            
            let event = PortfolioEvent(
                kind: kind,
                symbol: nil,
                changePercent: changePct,
                aiSummary: summary
            )
            
            recordAndNotify(event: event, notificationTitle: "🤖 \(title)")
        }
        
        // Update snapshot for next comparison
        previousPortfolioValue = currentTotal
        previousPortfolioTimestamp = Date()
        savePreviousPortfolioSnapshot()
    }
    
    // MARK: - Paper Trading Portfolio Value
    
    private struct PaperPortfolioSnapshot {
        let totalValue: Double
        let unpricedAssetCount: Int
        
        var hasUnpricedAssets: Bool { unpricedAssetCount > 0 }
    }
    
    /// Estimates paper portfolio value and tracks whether any non-stable assets were unpriced.
    private func paperTradingPortfolioSnapshot() -> PaperPortfolioSnapshot {
        guard PaperTradingManager.shared.isPaperTradingEnabled else {
            return PaperPortfolioSnapshot(totalValue: 0, unpricedAssetCount: 0)
        }
        
        let balances = PaperTradingManager.shared.paperBalances
        guard !balances.isEmpty else {
            return PaperPortfolioSnapshot(totalValue: 0, unpricedAssetCount: 0)
        }
        
        let stablecoins: Set<String> = ["USDT", "USDC", "BUSD", "DAI", "TUSD", "USDP", "USD"]
        var total: Double = 0
        var unpricedAssets = 0
        
        let allCoins = MarketViewModel.shared.allCoins
        
        for (asset, amount) in balances {
            let sym = asset.uppercased()
            guard amount > 0.000001 else { continue }
            
            if stablecoins.contains(sym) {
                // Stablecoins: $1 each
                total += amount
            } else if let coin = allCoins.first(where: { $0.symbol.uppercased() == sym }),
                      let price = coin.priceUsd {
                total += amount * price
            } else {
                // Price missing for an active position: mark snapshot incomplete.
                unpricedAssets += 1
            }
        }
        
        return PaperPortfolioSnapshot(totalValue: total, unpricedAssetCount: unpricedAssets)
    }
    
    private enum PortfolioSourceMode: String {
        case none
        case realOnly
        case paperOnly
        case combined
    }
    
    private func resolvePortfolioSourceMode(realTotal: Double, paperTotal: Double) -> PortfolioSourceMode {
        let hasReal = realTotal > 0.0001
        let hasPaper = paperTotal > 0.0001
        switch (hasReal, hasPaper) {
        case (true, true): return .combined
        case (true, false): return .realOnly
        case (false, true): return .paperOnly
        case (false, false): return .none
        }
    }
    
    // MARK: - Record Event & Send Notification
    
    private func recordAndNotify(event: PortfolioEvent, notificationTitle: String) {
        let cleanedTitle = sanitizeAlertTitle(notificationTitle, kind: event.kind)
        let cleanedSummary = sanitizeAlertBody(event.aiSummary, kind: event.kind)
        let cleanEvent = PortfolioEvent(
            kind: event.kind,
            symbol: event.symbol,
            changePercent: event.changePercent,
            aiSummary: cleanedSummary
        )
        
        // Store event
        recentEvents.insert(cleanEvent, at: 0)
        if recentEvents.count > 50 { recentEvents = Array(recentEvents.prefix(50)) }
        saveRecentEvents()
        
        // Update cooldowns
        lastAlertTimeByKind[cleanEvent.kind.rawValue] = Date()
        lastAnyAlertTime = Date()
        alertsSentToday += 1
        lastNotificationSentAt = Date()
        
        // Send local push notification
        sendPushNotification(title: cleanedTitle, body: cleanedSummary, event: cleanEvent)
        
        // Post internal notification
        NotificationCenter.default.post(
            name: .aiPortfolioAlertTriggered,
            object: nil,
            userInfo: ["event": cleanEvent.id.uuidString, "kind": cleanEvent.kind.rawValue]
        )
        
        logger.info("🤖 Alert sent: \(cleanEvent.kind.rawValue) — \(cleanEvent.aiSummary.prefix(80))")
    }
    
    // MARK: - Push Notifications
    
    private func sendPushNotification(title: String, body: String, event: PortfolioEvent) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "AI_PORTFOLIO_ALERT"
        content.userInfo = [
            "eventID": event.id.uuidString,
            "kind": event.kind.rawValue,
            "symbol": event.symbol ?? ""
        ]
        
        let request = UNNotificationRequest(
            identifier: "ai-portfolio-\(event.id.uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Push notification failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Cooldown & Rate Limiting
    
    private func canSendAlertForKind(_ kind: PortfolioEventKind) -> Bool {
        guard let lastTime = lastAlertTimeByKind[kind.rawValue] else { return true }
        return Date().timeIntervalSince(lastTime) >= cooldownPerKind
    }
    
    private func canSendAnyAlert() -> Bool {
        guard let lastTime = lastAnyAlertTime else { return true }
        return Date().timeIntervalSince(lastTime) >= globalCooldown
    }
    
    private func resetDailyCountIfNeeded() {
        if !Calendar.current.isDateInToday(alertCountResetDate) {
            alertsSentToday = 0
            alertCountResetDate = Date()
        }
    }
    
    // MARK: - Persistence
    
    private func saveRecentEvents() {
        guard let data = try? JSONEncoder().encode(recentEvents) else { return }
        UserDefaults.standard.set(data, forKey: "AIPortfolioMonitor.recentEvents")
    }
    
    private func loadRecentEvents() {
        guard let data = UserDefaults.standard.data(forKey: "AIPortfolioMonitor.recentEvents"),
              let events = try? JSONDecoder().decode([PortfolioEvent].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        recentEvents = events
            .filter { $0.timestamp > cutoff }
            .map { event in
                PortfolioEvent(
                    id: event.id,
                    kind: event.kind,
                    symbol: event.symbol,
                    changePercent: event.changePercent,
                    aiSummary: sanitizeAlertBody(event.aiSummary, kind: event.kind),
                    timestamp: event.timestamp,
                    isRead: event.isRead
                )
            }
    }
    
    private func savePreviousPortfolioSnapshot() {
        UserDefaults.standard.set(previousPortfolioValue, forKey: "AIPortfolioMonitor.prevPortfolioValue")
        UserDefaults.standard.set(hasConfirmedPortfolioBaseline, forKey: confirmedPortfolioBaselineKey)
        UserDefaults.standard.set(previousPortfolioSourceMode.rawValue, forKey: previousPortfolioSourceModeKey)
        if let ts = previousPortfolioTimestamp {
            UserDefaults.standard.set(ts.timeIntervalSince1970, forKey: "AIPortfolioMonitor.prevPortfolioTimestamp")
        } else {
            UserDefaults.standard.removeObject(forKey: "AIPortfolioMonitor.prevPortfolioTimestamp")
        }
    }
    
    private func loadPreviousPortfolioSnapshot() {
        previousPortfolioValue = UserDefaults.standard.double(forKey: "AIPortfolioMonitor.prevPortfolioValue")
        let ts = UserDefaults.standard.double(forKey: "AIPortfolioMonitor.prevPortfolioTimestamp")
        if ts > 0 {
            previousPortfolioTimestamp = Date(timeIntervalSince1970: ts)
        }
        hasConfirmedPortfolioBaseline = UserDefaults.standard.bool(forKey: confirmedPortfolioBaselineKey)
        previousPortfolioSourceMode = PortfolioSourceMode(
            rawValue: UserDefaults.standard.string(forKey: previousPortfolioSourceModeKey) ?? ""
        ) ?? .none
    }
    
    // MARK: - Clear
    
    func clearAllEvents() {
        recentEvents.removeAll()
        saveRecentEvents()
    }
    
    // MARK: - Wording Sanitization
    
    private func sanitizeAlertTitle(_ rawTitle: String, kind: PortfolioEventKind) -> String {
        let cleaned = sanitizeText(rawTitle)
        if !cleaned.isEmpty {
            if kind == .breakingNews {
                return "Breaking Crypto News"
            }
            return cleaned
        }
        
        switch kind {
        case .breakingNews: return "Breaking Crypto News"
        case .portfolioGain: return "Portfolio Update"
        case .portfolioDrop: return "Portfolio Update"
        case .btcMajorMove: return "Bitcoin Market Alert"
        case .sentimentShift: return "Market Sentiment Alert"
        case .marketWideMove: return "Market Update"
        case .largeGain: return "Coin Movement Alert"
        case .largeDrop: return "Coin Movement Alert"
        }
    }
    
    private func sanitizeAlertBody(_ rawBody: String, kind: PortfolioEventKind) -> String {
        var cleaned = sanitizeText(rawBody)
        
        if kind == .breakingNews {
            let lower = cleaned.lowercased()
            if lower.hasPrefix("breaking crypto news:") {
                cleaned = cleaned
                    .dropFirst("breaking crypto news:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if lower.hasPrefix("breaking news:") {
                cleaned = cleaned
                    .dropFirst("breaking news:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if !cleaned.isEmpty {
                cleaned = "Breaking news: \(cleaned)"
            }
        }
        
        if cleaned.isEmpty {
            switch kind {
            case .breakingNews:
                return "A high-impact crypto story is now available."
            case .portfolioGain, .portfolioDrop:
                return "Your portfolio moved meaningfully. Open Alerts for full details."
            default:
                return "New AI market signal detected. Open Alerts for details."
            }
        }
        
        return cleaned
    }
    
    private func sanitizeText(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "(undefined).", with: "")
            .replacingOccurrences(of: "(undefined)", with: "")
            .replacingOccurrences(of: "undefined.", with: "")
            .replacingOccurrences(of: "undefined", with: "")
        
        // Normalize spacing and punctuation after token removal.
        cleaned = cleaned
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: "..", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleaned.hasSuffix("()") {
            cleaned.removeLast(2)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return cleaned
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let aiPortfolioAlertTriggered = Notification.Name("aiPortfolioAlertTriggered")
}
