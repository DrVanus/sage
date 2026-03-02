//
//  PaperTradingManager.swift
//  CryptoSage
//
//  Centralized manager for paper trading state, balances, and trade history.
//  Paper trading allows users to practice trading with virtual money ($100k starting balance).
//

import SwiftUI
import Combine
import FirebaseFirestore
import os

/// Model for a paper trade record
public struct PaperTrade: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let side: TradeSide
    public let quantity: Double
    public let price: Double
    public let timestamp: Date
    public let orderType: String
    
    public var totalValue: Double { quantity * price }
    
    public init(
        id: UUID = UUID(),
        symbol: String,
        side: TradeSide,
        quantity: Double,
        price: Double,
        timestamp: Date = Date(),
        orderType: String = "MARKET"
    ) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.quantity = quantity
        self.price = price
        self.timestamp = timestamp
        self.orderType = orderType
    }
}

/// Model for a pending paper limit order (simulating realistic limit order behavior)
public struct PaperPendingOrder: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let side: TradeSide
    public let quantity: Double
    public let limitPrice: Double
    public let stopPrice: Double?  // For stop and stop-limit orders
    public let orderType: String   // LIMIT, STOP, STOP_LIMIT
    public let createdAt: Date
    
    public var totalValue: Double { quantity * limitPrice }
    
    /// Check if this order should be filled at the current market price
    public func shouldFill(currentPrice: Double) -> Bool {
        switch orderType {
        case "LIMIT":
            // Limit buy fills when price drops to or below limit price
            // Limit sell fills when price rises to or above limit price
            if side == .buy {
                return currentPrice <= limitPrice
            } else {
                return currentPrice >= limitPrice
            }
        case "STOP":
            // Stop buy triggers when price rises to stop price
            // Stop sell triggers when price drops to stop price
            guard let stop = stopPrice else { return false }
            if side == .buy {
                return currentPrice >= stop
            } else {
                return currentPrice <= stop
            }
        case "STOP_LIMIT":
            // Stop-limit triggers when stop price is hit, then waits for limit price
            // For simplicity, we fill when the stop is triggered
            guard let stop = stopPrice else { return false }
            if side == .buy {
                // Stop triggered AND limit price is achievable
                return currentPrice >= stop && currentPrice <= limitPrice
            } else {
                return currentPrice <= stop && currentPrice >= limitPrice
            }
        default:
            return false
        }
    }
    
    public init(
        id: UUID = UUID(),
        symbol: String,
        side: TradeSide,
        quantity: Double,
        limitPrice: Double,
        stopPrice: Double? = nil,
        orderType: String = "LIMIT",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.quantity = quantity
        self.limitPrice = limitPrice
        self.stopPrice = stopPrice
        self.orderType = orderType
        self.createdAt = createdAt
    }
}

/// Centralized manager for paper trading across the entire app.
/// When paper trading is ON: Trades are simulated with virtual money, balances are tracked locally.
/// When paper trading is OFF: Real trading occurs through connected exchanges.
@MainActor
public final class PaperTradingManager: ObservableObject {
    public static let shared = PaperTradingManager()
    
    // MARK: - Storage Keys
    private static let enabledKey = "paper_trading_enabled"
    private static let balancesKey = "paper_trading_balances"
    private static let historyKey = "paper_trading_history"
    private static let pendingOrdersKey = "paper_trading_pending_orders"
    private static let startingBalanceKey = "paper_trading_starting_balance"
    private static let initialValueKey = "paper_trading_initial_value"
    private static let realisticLimitOrdersKey = "paper_trading_realistic_limits"
    private static let lastKnownPricesKey = "paper_trading_last_known_prices"
    private static let lastKnownPriceTimestampsKey = "paper_trading_last_known_price_timestamps"
    private static let valueSnapshotsKey = "paper_trading_value_snapshots"
    private static let resetTimestampsKey = "paper_trading_reset_timestamps"
    private static let totalResetCountKey = "paper_trading_total_reset_count"
    private static let lastResetAtKey = "paper_trading_last_reset_at"
    
    // MARK: - Reset Limits (Anti-Gaming)
    //
    // Industry context: Webull, Interactive Brokers, TradingView, Cryptohopper, and
    // 3Commas all allow unlimited paper trading resets — because their paper trading
    // is purely a practice tool with no competitive leaderboard.
    //
    // Our app has a competitive leaderboard, so we need limits. But paper trading is
    // still fundamentally a LEARNING tool — users shouldn't be permanently stuck with
    // a blown-up account. The solution: let everyone reset at a reasonable cadence,
    // and make the leaderboard handle the anti-gaming separately via cooldowns and
    // score penalties.
    //
    // Tier-based reset frequency:
    //   - Free:    No paper trading access at all
    //   - Pro:     1 reset per 90 days (quarterly fresh start)
    //   - Premium: 1 reset per 30 days (monthly fresh start)
    //
    // Leaderboard protection (applies to ALL resets regardless of tier):
    //   - 14-day leaderboard cooldown after each reset
    //   - 20% score penalty per reset in the rolling window
    //   - Time-weight multiplier resets to minimum (0.7x), takes months to rebuild
    //
    // This means every user can recover from a bad run, Premium gets more flexibility,
    // and the leaderboard stays fair because resets carry real competitive consequences.
    
    /// Maximum resets allowed per rolling window, by subscription tier.
    /// Pro gets 1 per 90 days (quarterly), Premium gets 1 per 30 days (monthly).
    /// The window itself differs by tier — see `resetLimitWindowDays(for:)`.
    public static func maxResetsPerPeriod(for tier: SubscriptionTierType) -> Int {
        switch tier {
        case .premium: return 1   // 1 per 30 days (monthly)
        case .pro: return 1       // 1 per 90 days (quarterly)
        case .free: return 0      // No paper trading access
        }
    }
    
    /// Rolling window in days for reset limit calculation.
    /// Pro: 90-day window (quarterly), Premium: 30-day window (monthly).
    public static func resetLimitWindowDays(for tier: SubscriptionTierType) -> Int {
        switch tier {
        case .premium: return 30   // Monthly window
        case .pro: return 90       // Quarterly window
        case .free: return 90      // N/A but default to 90
        }
    }
    
    /// Convenience: window for the current user's tier
    public static var resetLimitWindowDays: Int {
        resetLimitWindowDays(for: SubscriptionManager.shared.effectiveTier)
    }
    
    /// Cooldown period after a reset before leaderboard scores are unpenalized (14 days)
    public static let leaderboardCooldownAfterReset: TimeInterval = 14 * 24 * 3600
    
    /// Leaderboard score penalty multiplier per reset in window (20% reduction per reset)
    public static let resetScorePenalty: Double = 0.20
    
    // MARK: - Default Values
    public static let defaultStartingBalance: Double = 100_000.0
    public static let defaultQuoteCurrency = "USDT"
    
    // MARK: - Published State
    
    /// Whether paper trading mode is enabled
    @Published public var isPaperTradingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPaperTradingEnabled, forKey: Self.enabledKey)
            // Defer to avoid "Modifying state during view update" warnings
            Task { self.objectWillChange.send() }
        }
    }
    
    /// Current paper balances by asset (e.g., ["USDT": 100000, "BTC": 0.5])
    @Published public var paperBalances: [String: Double] {
        didSet {
            savePaperBalances()
        }
    }
    
    /// History of all paper trades
    @Published public var paperTradeHistory: [PaperTrade] {
        didSet {
            savePaperTradeHistory()
        }
    }
    
    /// Starting balance for paper trading (default $100,000)
    @Published public var startingBalance: Double {
        didSet {
            UserDefaults.standard.set(startingBalance, forKey: Self.startingBalanceKey)
        }
    }
    
    /// Initial portfolio value when paper trading was started/reset (for P&L calculation)
    @Published public var initialPortfolioValue: Double {
        didSet {
            UserDefaults.standard.set(initialPortfolioValue, forKey: Self.initialValueKey)
        }
    }
    
    /// Pending limit/stop orders waiting to be filled
    @Published public var pendingOrders: [PaperPendingOrder] = [] {
        didSet {
            savePendingOrders()
        }
    }
    
    /// Whether to use realistic limit order simulation (queue orders instead of instant fill)
    @Published public var realisticLimitOrders: Bool {
        didSet {
            UserDefaults.standard.set(realisticLimitOrders, forKey: Self.realisticLimitOrdersKey)
        }
    }
    
    /// Last known prices for assets - used as fallback when live prices are unavailable (API rate limiting, degraded mode)
    /// This prevents portfolio value from dropping to $0 for assets when price APIs fail
    @Published public var lastKnownPrices: [String: Double] = [:] {
        didSet {
            saveLastKnownPrices()
        }
    }
    
    /// Timestamps for when each lastKnownPrice was last updated.
    /// Used to reject stale cached prices older than `cachedPriceMaxAge`.
    private var lastKnownPriceTimestamps: [String: Date] = [:]
    
    /// Maximum age for cached fallback prices (30 minutes).
    /// Prices older than this are considered unreliable and will not be used.
    private let cachedPriceMaxAge: TimeInterval = 30 * 60
    
    /// Periodic portfolio value snapshots for accurate historical P&L calculations.
    /// Stored as [(timestamp, value)] pairs, taken every 6 hours.
    /// This allows the sparkline extension to use real historical values instead of
    /// always anchoring at initialValue, fixing the "1 Month P&L = All Time P&L" bug.
    private var valueSnapshots: [(date: Date, value: Double)] = []
    
    /// Minimum interval between snapshots (6 hours)
    private let snapshotInterval: TimeInterval = 6 * 3600
    
    /// Maximum number of snapshots to store (365 days at 4/day = ~1460)
    private let maxSnapshots = 1500
    
    /// Price update subscription for monitoring pending orders
    private var priceSubscription: AnyCancellable?
    
    // MARK: - Reset Tracking State
    
    /// Timestamps of all resets within the rolling window (persisted)
    @Published public private(set) var resetTimestamps: [Date] = []
    
    /// Total lifetime reset count (for analytics/display)
    @Published public private(set) var totalResetCount: Int = 0
    
    /// When the most recent reset occurred (nil if never reset)
    @Published public private(set) var lastResetAt: Date? = nil
    
    // MARK: - Firestore Sync
    
    private let db = Firestore.firestore()
    private var firestoreListener: ListenerRegistration?
    private var isApplyingFirestoreUpdate = false // Prevent sync loops
    private let ptLogger = Logger(subsystem: "CryptoSage", category: "PaperTradingSync")
    private var syncDebounceTimer: Timer?
    private let syncDebounceInterval: TimeInterval = 2.0
    
    /// Whether Firestore sync is currently active
    @Published public private(set) var isFirestoreSyncActive: Bool = false
    
    deinit {
        firestoreListener?.remove()
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load persisted state
        self.isPaperTradingEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        self.startingBalance = UserDefaults.standard.object(forKey: Self.startingBalanceKey) as? Double ?? Self.defaultStartingBalance
        self.initialPortfolioValue = UserDefaults.standard.object(forKey: Self.initialValueKey) as? Double ?? Self.defaultStartingBalance
        self.realisticLimitOrders = UserDefaults.standard.object(forKey: Self.realisticLimitOrdersKey) as? Bool ?? true
        self.paperBalances = [:]
        self.paperTradeHistory = []
        self.pendingOrders = []
        self.lastKnownPrices = [:]
        
        // Load balances, history, pending orders, cached prices, timestamps, and value snapshots
        loadPaperBalances()
        loadPaperTradeHistory()
        loadPendingOrders()
        loadLastKnownPrices()
        loadLastKnownPriceTimestamps()
        loadValueSnapshots()
        loadResetTracking()
        
        // Initialize with starting balance if empty
        if paperBalances.isEmpty {
            paperBalances = [Self.defaultQuoteCurrency: startingBalance]
            initialPortfolioValue = startingBalance
        }
        
        // Set up price monitoring for pending orders
        setupPriceMonitoring()
    }
    
    // MARK: - Subscription Check
    
    /// Check if user has access to paper trading feature
    /// Returns true if user has Pro tier or higher, or if developer mode is active
    public var hasAccess: Bool {
        return SubscriptionManager.shared.hasAccess(to: .paperTrading)
    }
    
    // MARK: - Public API
    
    /// Enable paper trading mode
    /// Automatically disables Demo Mode to prevent conflicts
    /// Returns true if paper trading was enabled, false if user lacks subscription access
    @discardableResult
    public func enablePaperTrading() -> Bool {
        // Check subscription access first
        guard hasAccess else {
            return false
        }
        
        // Turn off Demo Mode when enabling Paper Trading
        // Paper Trading provides a more realistic practice experience
        if DemoModeManager.shared.isDemoMode {
            DemoModeManager.shared.disableDemoMode()
        }
        
        // Reset initialPortfolioValue if balances are at default (no trades made)
        // This ensures the chart always starts at $100K for fresh paper trading sessions
        let isAtDefaultBalance = paperBalances.isEmpty ||
            (paperBalances.count == 1 &&
             paperBalances[Self.defaultQuoteCurrency] == startingBalance)
        
        if isAtDefaultBalance {
            initialPortfolioValue = startingBalance
        }
        
        isPaperTradingEnabled = true
        return true
    }
    
    /// Disable paper trading mode
    public func disablePaperTrading() {
        isPaperTradingEnabled = false
    }
    
    /// Toggle paper trading mode
    /// Returns true if the operation was successful
    @discardableResult
    public func toggle() -> Bool {
        if isPaperTradingEnabled {
            disablePaperTrading()
            return true
        } else {
            return enablePaperTrading() // This will also disable Demo Mode
        }
    }
    
    /// Get balance for a specific asset
    public func balance(for asset: String) -> Double {
        return paperBalances[asset.uppercased()] ?? 0.0
    }
    
    /// Update balance for a specific asset
    public func updateBalance(asset: String, amount: Double) {
        // NaN GUARD: In Swift, max(0, NaN) returns NaN, silently corrupting the balance.
        // This would persist to UserDefaults and permanently break the portfolio.
        guard amount.isFinite else {
            #if DEBUG
            print("⚠️ [PaperTrading] Blocked NaN/Inf updateBalance for \(asset): \(amount)")
            #endif
            return
        }
        paperBalances[asset.uppercased()] = max(0, amount)
    }
    
    /// Add to existing balance for an asset
    public func addToBalance(asset: String, amount: Double) {
        // NaN GUARD: Prevent corrupted amounts from poisoning the balance
        guard amount.isFinite else {
            #if DEBUG
            print("⚠️ [PaperTrading] Blocked NaN/Inf addToBalance for \(asset): \(amount)")
            #endif
            return
        }
        let current = balance(for: asset)
        paperBalances[asset.uppercased()] = max(0, current + amount)
    }
    
    /// Deduct from existing balance for an asset
    public func deductFromBalance(asset: String, amount: Double) -> Bool {
        let current = balance(for: asset)
        if current >= amount {
            paperBalances[asset.uppercased()] = current - amount
            return true
        }
        return false
    }
    
    /// Record a paper trade
    public func recordTrade(_ trade: PaperTrade) {
        paperTradeHistory.insert(trade, at: 0) // Most recent first
    }
    
    /// Execute a paper trade (updates balances and records trade)
    /// Returns an OrderResult indicating success or failure
    /// For limit/stop orders with realisticLimitOrders enabled, order is queued as pending
    public func executePaperTrade(
        symbol: String,
        side: TradeSide,
        quantity: Double,
        price: Double,
        orderType: String = "MARKET",
        stopPrice: Double? = nil
    ) -> OrderResult {
        // CRITICAL: Validate price and quantity to prevent NaN/Infinity from corrupting balances.
        // Once NaN enters paperBalances (persisted to UserDefaults), the ENTIRE portfolio is
        // permanently corrupted — every future calculation returns NaN.
        guard price > 0, price.isFinite else {
            return OrderResult(
                success: false,
                errorMessage: "Invalid price: \(price). Cannot execute trade.",
                exchange: "Paper Trading"
            )
        }
        guard quantity > 0, quantity.isFinite else {
            return OrderResult(
                success: false,
                errorMessage: "Invalid quantity: \(quantity). Cannot execute trade.",
                exchange: "Paper Trading"
            )
        }
        
        // For non-market orders with realistic simulation, queue as pending
        let isNonMarketOrder = orderType != "MARKET"
        if isNonMarketOrder && realisticLimitOrders {
            return placePendingOrder(
                symbol: symbol,
                side: side,
                quantity: quantity,
                limitPrice: price,
                stopPrice: stopPrice,
                orderType: orderType
            )
        }
        
        // Parse base and quote assets from symbol
        let (baseAsset, quoteAsset) = parseSymbol(symbol)
        let totalCost = quantity * price
        
        // Paper trading fee rate (0.1% - matches typical exchange taker fees)
        let feeRate = 0.001
        let fee = totalCost * feeRate
        
        switch side {
        case .buy:
            // Check if we have enough quote currency (including fee)
            let totalCostWithFee = totalCost + fee
            let quoteBalance = balance(for: quoteAsset)
            guard quoteBalance >= totalCostWithFee else {
                return OrderResult(
                    success: false,
                    errorMessage: "Insufficient \(quoteAsset) balance. Need \(formatCurrency(totalCostWithFee)) (includes \(formatCurrency(fee)) fee), have \(formatCurrency(quoteBalance))",
                    exchange: "Paper Trading"
                )
            }
            
            // Deduct quote currency (including fee), add base currency
            _ = deductFromBalance(asset: quoteAsset, amount: totalCostWithFee)
            addToBalance(asset: baseAsset, amount: quantity)
            
        case .sell:
            // Check if we have enough base currency
            let baseBalance = balance(for: baseAsset)
            guard baseBalance >= quantity else {
                return OrderResult(
                    success: false,
                    errorMessage: "Insufficient \(baseAsset) balance. Need \(formatQuantity(quantity)), have \(formatQuantity(baseBalance))",
                    exchange: "Paper Trading"
                )
            }
            
            // Deduct base currency, add quote currency minus fee
            let proceedsAfterFee = totalCost - fee
            _ = deductFromBalance(asset: baseAsset, amount: quantity)
            addToBalance(asset: quoteAsset, amount: proceedsAfterFee)
        }
        
        // Record the trade
        let trade = PaperTrade(
            symbol: symbol,
            side: side,
            quantity: quantity,
            price: price,
            orderType: orderType
        )
        recordTrade(trade)
        
        return OrderResult(
            success: true,
            orderId: trade.id.uuidString,
            status: .filled,
            filledQuantity: quantity,
            averagePrice: price,
            exchange: "Paper Trading"
        )
    }
    
    /// Reset paper trading to starting balance
    /// Returns false if reset limit has been reached for the current subscription tier.
    @discardableResult
    public func resetPaperTrading() -> Bool {
        guard canReset else {
            #if DEBUG
            print("[PaperTrading] Reset blocked — limit reached for current tier")
            #endif
            return false
        }

        paperBalances = [Self.defaultQuoteCurrency: startingBalance]
        paperTradeHistory = []
        pendingOrders = []
        initialPortfolioValue = startingBalance
        valueSnapshots = []
        saveValueSnapshots()
        lastKnownPriceTimestamps = [:]
        saveLastKnownPriceTimestamps()
        
        recordReset()
        return true
    }
    
    /// Reset with a custom starting balance
    /// Returns false if reset limit has been reached for the current subscription tier.
    @discardableResult
    public func resetPaperTrading(withBalance balance: Double) -> Bool {
        guard canReset else {
            #if DEBUG
            print("[PaperTrading] Reset blocked — limit reached for current tier")
            #endif
            return false
        }

        startingBalance = balance
        paperBalances = [Self.defaultQuoteCurrency: balance]
        paperTradeHistory = []
        pendingOrders = []
        initialPortfolioValue = balance
        valueSnapshots = []
        saveValueSnapshots()
        lastKnownPriceTimestamps = [:]
        saveLastKnownPriceTimestamps()
        
        recordReset()
        return true
    }
    
    // MARK: - Reset Limit API
    
    /// Whether the user can currently reset.
    /// Both Pro and Premium can reset, but at different frequencies.
    public var canReset: Bool {
        let tier = SubscriptionManager.shared.effectiveTier
        let maxResets = Self.maxResetsPerPeriod(for: tier)
        guard maxResets > 0 else { return false } // Free tier has no paper trading
        return resetsUsedInCurrentWindow < maxResets
    }
    
    /// Number of resets used in the current rolling window (window size depends on tier)
    public var resetsUsedInCurrentWindow: Int {
        let tier = SubscriptionManager.shared.effectiveTier
        let windowDays = Self.resetLimitWindowDays(for: tier)
        let cutoff = Date().addingTimeInterval(-Double(windowDays) * 24 * 3600)
        return resetTimestamps.filter { $0 > cutoff }.count
    }
    
    /// Number of resets remaining in the current rolling window
    public var resetsRemaining: Int {
        let tier = SubscriptionManager.shared.effectiveTier
        let maxResets = Self.maxResetsPerPeriod(for: tier)
        return max(0, maxResets - resetsUsedInCurrentWindow)
    }
    
    /// Maximum resets allowed for the current tier
    public var maxResetsForCurrentTier: Int {
        Self.maxResetsPerPeriod(for: SubscriptionManager.shared.effectiveTier)
    }
    
    /// The rolling window length (in days) for the current tier
    public var resetWindowDaysForCurrentTier: Int {
        Self.resetLimitWindowDays(for: SubscriptionManager.shared.effectiveTier)
    }
    
    /// Whether the user is in leaderboard cooldown after a recent reset (7-day penalty window)
    public var isInLeaderboardCooldown: Bool {
        guard let lastReset = lastResetAt else { return false }
        return Date().timeIntervalSince(lastReset) < Self.leaderboardCooldownAfterReset
    }
    
    /// Days remaining in leaderboard cooldown (0 if not in cooldown)
    public var leaderboardCooldownDaysRemaining: Int {
        guard let lastReset = lastResetAt else { return 0 }
        let elapsed = Date().timeIntervalSince(lastReset)
        let remaining = Self.leaderboardCooldownAfterReset - elapsed
        return remaining > 0 ? Int(ceil(remaining / (24 * 3600))) : 0
    }
    
    /// Date when the earliest reset in the window expires (frees up a reset slot)
    public var nextResetSlotAvailableAt: Date? {
        let tier = SubscriptionManager.shared.effectiveTier
        let windowDays = Self.resetLimitWindowDays(for: tier)
        let cutoff = Date().addingTimeInterval(-Double(windowDays) * 24 * 3600)
        let resetsInWindow = resetTimestamps.filter { $0 > cutoff }.sorted()
        guard let earliest = resetsInWindow.first else { return nil }
        return earliest.addingTimeInterval(Double(windowDays) * 24 * 3600)
    }
    
    /// Score multiplier based on resets in the rolling window.
    /// Each reset applies a 20% penalty. With 1 reset that's 0.80x, with 2 that's 0.64x.
    public var leaderboardScorePenaltyMultiplier: Double {
        let resetsInWindow = resetsUsedInCurrentWindow
        guard resetsInWindow > 0 else { return 1.0 }
        return pow(1.0 - Self.resetScorePenalty, Double(resetsInWindow))
    }
    
    /// Whether the user is using the standard starting balance (required for fair leaderboard competition)
    public var isUsingStandardBalance: Bool {
        startingBalance == Self.defaultStartingBalance
    }
    
    /// Days since last reset (for leaderboard cooldown tracking)
    public var daysSinceLastReset: Int {
        guard let lastReset = lastResetAt else {
            return 999 // Never reset
        }
        return Int(Date().timeIntervalSince(lastReset) / (24 * 3600))
    }
    
    // MARK: - Reset Tracking (Private)
    
    private func recordReset() {
        let now = Date()
        resetTimestamps.append(now)
        totalResetCount += 1
        lastResetAt = now
        
        // Prune timestamps older than 90 days (keep 3x the window for history)
        let pruneCutoff = now.addingTimeInterval(-90 * 24 * 3600)
        resetTimestamps = resetTimestamps.filter { $0 > pruneCutoff }
        
        saveResetTracking()
        #if DEBUG
        print("[PaperTrading] Reset recorded. Total: \(totalResetCount), In window: \(resetsUsedInCurrentWindow), Remaining: \(resetsRemaining)")
        #endif
    }
    
    private func loadResetTracking() {
        if let data = UserDefaults.standard.data(forKey: Self.resetTimestampsKey),
           let timestamps = try? JSONDecoder().decode([Date].self, from: data) {
            self.resetTimestamps = timestamps
        }
        self.totalResetCount = UserDefaults.standard.integer(forKey: Self.totalResetCountKey)
        if let lastResetInterval = UserDefaults.standard.object(forKey: Self.lastResetAtKey) as? Double {
            self.lastResetAt = Date(timeIntervalSince1970: lastResetInterval)
        }
    }
    
    private func saveResetTracking() {
        if let data = try? JSONEncoder().encode(resetTimestamps) {
            UserDefaults.standard.set(data, forKey: Self.resetTimestampsKey)
        }
        UserDefaults.standard.set(totalResetCount, forKey: Self.totalResetCountKey)
        if let lastReset = lastResetAt {
            UserDefaults.standard.set(lastReset.timeIntervalSince1970, forKey: Self.lastResetAtKey)
        }
        syncToFirestoreIfNeeded()
    }
    
    /// Calculate current portfolio value in quote currency (USDT)
    /// Requires current prices for non-quote assets
    /// Falls back to lastKnownPrices when live prices are unavailable (e.g., API rate limiting)
    public func calculatePortfolioValue(prices: [String: Double]) -> Double {
        var totalValue: Double = 0
        let now = Date()
        
        for (asset, amount) in paperBalances {
            guard amount.isFinite, amount > 0 else { continue }
            
            if asset == Self.defaultQuoteCurrency {
                totalValue += amount
            } else if let price = prices[asset], price > 0, price.isFinite {
                // Use live price if available and valid
                totalValue += amount * price
            } else if let cachedPrice = lastKnownPrices[asset], cachedPrice > 0, cachedPrice.isFinite,
                      isCachedPriceFresh(for: asset, now: now) {
                // Fallback to last known price when live price is unavailable,
                // but ONLY if the cached price is less than 30 minutes old.
                // Stale prices from hours/days ago can be wildly inaccurate.
                totalValue += amount * cachedPrice
            }
            // If no price available or cached price is stale, asset contributes $0
            // This is safer than using a days-old price that could be far off
        }
        
        return totalValue.isFinite ? totalValue : 0
    }
    
    /// Returns true if the cached price for the given asset is fresh enough to use as a fallback.
    /// Prices older than `cachedPriceMaxAge` (30 minutes) are considered stale.
    public func isCachedPriceFresh(for asset: String, now: Date = Date()) -> Bool {
        guard let timestamp = lastKnownPriceTimestamps[asset] else {
            // No timestamp recorded — treat as stale (legacy data from before timestamps were added)
            return false
        }
        return now.timeIntervalSince(timestamp) < cachedPriceMaxAge
    }
    
    /// Build a current price dictionary from all available sources.
    /// Use this instead of passing `[:]` to calculatePortfolioValue.
    public func buildCurrentPrices() -> [String: Double] {
        var prices: [String: Double] = [:]
        // Add stablecoin prices
        prices["USDT"] = 1.0
        prices["USD"] = 1.0
        prices["USDC"] = 1.0
        prices["BUSD"] = 1.0
        prices["FDUSD"] = 1.0
        
        // Add live prices from MarketViewModel
        for coin in MarketViewModel.shared.allCoins {
            let symbol = coin.symbol.uppercased()
            if let price = MarketViewModel.shared.bestPrice(for: coin.id), price > 0 {
                prices[symbol] = price
            } else if let price = coin.priceUsd, price > 0 {
                prices[symbol] = price
            }
        }
        
        // Fill gaps from bestPrice(forSymbol:) for held assets
        for (asset, _) in paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let price = MarketViewModel.shared.bestPrice(forSymbol: symbol), price > 0 {
                    prices[symbol] = price
                }
            }
        }
        
        return prices
    }
    
    /// Calculate profit/loss based on current prices
    public func calculateProfitLoss(prices: [String: Double]) -> Double {
        let currentValue = calculatePortfolioValue(prices: prices)
        return currentValue - initialPortfolioValue
    }
    
    /// Calculate profit/loss percentage
    public func calculateProfitLossPercent(prices: [String: Double]) -> Double {
        guard initialPortfolioValue > 0 else { return 0 }
        let pnl = calculateProfitLoss(prices: prices)
        return (pnl / initialPortfolioValue) * 100
    }
    
    /// Get all non-zero balances
    public var nonZeroBalances: [(asset: String, amount: Double)] {
        paperBalances
            .filter { $0.value > 0.000001 }
            .sorted { $0.key < $1.key }
            .map { (asset: $0.key, amount: $0.value) }
    }
    
    /// Get recent trades (limited)
    public func recentTrades(limit: Int = 10) -> [PaperTrade] {
        Array(paperTradeHistory.prefix(limit))
    }
    
    // MARK: - Performance Statistics
    
    /// Total number of trades
    public var totalTradeCount: Int {
        paperTradeHistory.count
    }
    
    /// Number of buy trades
    public var buyTradeCount: Int {
        paperTradeHistory.filter { $0.side == .buy }.count
    }
    
    /// Number of sell trades
    public var sellTradeCount: Int {
        paperTradeHistory.filter { $0.side == .sell }.count
    }
    
    /// Calculate win rate based on sell trades that were profitable
    /// A "win" is when a sell trade's value is higher than the average buy price for that asset
    public func calculateWinRate(prices: [String: Double]) -> Double {
        let sellTrades = paperTradeHistory.filter { $0.side == .sell }
        guard !sellTrades.isEmpty else { return 0.0 }
        
        var wins = 0
        for sell in sellTrades {
            let (base, _) = parseSymbol(sell.symbol)
            // Get average buy price for this asset
            let buys = paperTradeHistory.filter { $0.side == .buy && parseSymbol($0.symbol).base == base }
            guard !buys.isEmpty else { continue }
            
            let avgBuyPrice = buys.map { $0.price }.reduce(0, +) / Double(buys.count)
            if sell.price > avgBuyPrice {
                wins += 1
            }
        }
        
        return Double(wins) / Double(sellTrades.count) * 100
    }
    
    /// Best trade by total value
    public var bestTrade: PaperTrade? {
        paperTradeHistory.max(by: { $0.totalValue < $1.totalValue })
    }
    
    /// Smallest trade by total value
    public var smallestTrade: PaperTrade? {
        paperTradeHistory.min(by: { $0.totalValue < $1.totalValue })
    }
    
    /// Average trade size in USD value
    public var averageTradeSize: Double {
        guard !paperTradeHistory.isEmpty else { return 0.0 }
        let total = paperTradeHistory.map { $0.totalValue }.reduce(0, +)
        return total / Double(paperTradeHistory.count)
    }
    
    /// Total volume traded (sum of all trade values)
    public var totalVolumeTraded: Double {
        paperTradeHistory.map { $0.totalValue }.reduce(0, +)
    }
    
    /// Date of first trade (trading since)
    public var tradingSinceDate: Date? {
        paperTradeHistory.last?.timestamp
    }
    
    /// Get unique assets traded
    public var uniqueAssetsTraded: [String] {
        let assets = paperTradeHistory.map { parseSymbol($0.symbol).base }
        return Array(Set(assets)).sorted()
    }
    
    /// Get trades filtered by side
    public func trades(side: TradeSide?) -> [PaperTrade] {
        guard let side = side else { return paperTradeHistory }
        return paperTradeHistory.filter { $0.side == side }
    }
    
    /// Get trades filtered by asset
    public func trades(forAsset asset: String?) -> [PaperTrade] {
        guard let asset = asset, !asset.isEmpty else { return paperTradeHistory }
        return paperTradeHistory.filter { parseSymbol($0.symbol).base == asset.uppercased() }
    }
    
    /// Get trades with combined filters
    public func filteredTrades(side: TradeSide?, asset: String?) -> [PaperTrade] {
        var result = paperTradeHistory
        
        if let side = side {
            result = result.filter { $0.side == side }
        }
        
        if let asset = asset, !asset.isEmpty {
            result = result.filter { parseSymbol($0.symbol).base == asset.uppercased() }
        }
        
        return result
    }
    
    /// Export trades to CSV format
    public func exportToCSV() -> String {
        var csv = "Date,Symbol,Side,Quantity,Price,Total Value,Order Type\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        for trade in paperTradeHistory {
            let date = dateFormatter.string(from: trade.timestamp)
            let line = "\(date),\(trade.symbol),\(trade.side.rawValue),\(trade.quantity),\(trade.price),\(trade.totalValue),\(trade.orderType)\n"
            csv += line
        }
        
        return csv
    }
    
    // MARK: - Thread-Safe Access
    
    /// Thread-safe check for paper trading status
    nonisolated public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "paper_trading_enabled")
    }
    
    // MARK: - Symbol Parsing
    
    /// Parse a trading symbol into base and quote assets
    /// Handles multiple formats: "BTCUSDT", "BTC_USDT", "BTC/USDT", "BTC-USDT", "BTC"
    public func parseSymbol(_ symbol: String) -> (base: String, quote: String) {
        let upper = symbol.uppercased()
        
        // CRITICAL FIX: Handle delimiter-separated pairs FIRST (e.g., "BTC_USDT", "BTC/USDT", "BTC-USDT")
        // Without this, "BTC_USDT" would parse as base="BTC_" (with trailing underscore),
        // causing all price lookups and balance operations to fail silently.
        let delimiters: [Character] = ["_", "/", "-"]
        for delimiter in delimiters {
            if upper.contains(delimiter) {
                let parts = upper.split(separator: delimiter, maxSplits: 1)
                if parts.count == 2 {
                    return (String(parts[0]), String(parts[1]))
                }
            }
        }
        
        // Handle concatenated pairs (e.g., "BTCUSDT")
        let quotes = ["USDT", "USD", "BUSD", "USDC", "FDUSD"]
        for q in quotes where upper.hasSuffix(q) {
            let base = String(upper.dropLast(q.count))
            if !base.isEmpty {
                return (base, q)
            }
        }
        
        // Base-only symbol (e.g., "BTC") — default to USDT
        return (upper, "USDT")
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    private func formatQuantity(_ value: Double) -> String {
        if value < 0.001 {
            return String(format: "%.8f", value)
        } else if value < 1 {
            return String(format: "%.6f", value)
        } else {
            return String(format: "%.4f", value)
        }
    }
    
    // MARK: - Persistence
    
    private func savePaperBalances() {
        if let data = try? JSONEncoder().encode(paperBalances) {
            UserDefaults.standard.set(data, forKey: Self.balancesKey)
        }
        syncToFirestoreIfNeeded()
    }
    
    private func loadPaperBalances() {
        if let data = UserDefaults.standard.data(forKey: Self.balancesKey),
           let balances = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.paperBalances = balances
        }
    }
    
    private func savePaperTradeHistory() {
        // Keep only last 500 trades to prevent excessive storage
        let trimmedHistory = Array(paperTradeHistory.prefix(500))
        if let data = try? JSONEncoder().encode(trimmedHistory) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
        syncToFirestoreIfNeeded()
    }
    
    private func loadPaperTradeHistory() {
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let history = try? JSONDecoder().decode([PaperTrade].self, from: data) {
            self.paperTradeHistory = history
        }
    }
    
    private func savePendingOrders() {
        if let data = try? JSONEncoder().encode(pendingOrders) {
            UserDefaults.standard.set(data, forKey: Self.pendingOrdersKey)
        }
        syncToFirestoreIfNeeded()
    }
    
    private func loadPendingOrders() {
        if let data = UserDefaults.standard.data(forKey: Self.pendingOrdersKey),
           let orders = try? JSONDecoder().decode([PaperPendingOrder].self, from: data) {
            self.pendingOrders = orders
        }
    }
    
    private func saveLastKnownPrices() {
        if let data = try? JSONEncoder().encode(lastKnownPrices) {
            UserDefaults.standard.set(data, forKey: Self.lastKnownPricesKey)
        }
    }
    
    private func loadLastKnownPrices() {
        if let data = UserDefaults.standard.data(forKey: Self.lastKnownPricesKey),
           let prices = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.lastKnownPrices = prices
        }
    }
    
    private func saveLastKnownPriceTimestamps() {
        // Encode [String: Date] as [String: TimeInterval] for simple serialization
        let encoded = lastKnownPriceTimestamps.mapValues { $0.timeIntervalSince1970 }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: Self.lastKnownPriceTimestampsKey)
        }
    }
    
    private func loadLastKnownPriceTimestamps() {
        if let data = UserDefaults.standard.data(forKey: Self.lastKnownPriceTimestampsKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.lastKnownPriceTimestamps = decoded.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }
    
    // MARK: - Value Snapshots (for historical P&L accuracy)
    
    private func saveValueSnapshots() {
        // Encode as array of [timestamp, value] pairs
        let pairs: [[Double]] = valueSnapshots.map { [$0.date.timeIntervalSince1970, $0.value] }
        if let data = try? JSONEncoder().encode(pairs) {
            UserDefaults.standard.set(data, forKey: Self.valueSnapshotsKey)
        }
        syncToFirestoreIfNeeded()
    }
    
    private func loadValueSnapshots() {
        if let data = UserDefaults.standard.data(forKey: Self.valueSnapshotsKey),
           let pairs = try? JSONDecoder().decode([[Double]].self, from: data) {
            valueSnapshots = pairs.compactMap { pair in
                guard pair.count == 2 else { return nil }
                return (date: Date(timeIntervalSince1970: pair[0]), value: pair[1])
            }
        }
    }
    
    /// Record a portfolio value snapshot if enough time has passed since the last one.
    /// Call this periodically (e.g., from the portfolio view's price refresh cycle).
    public func recordSnapshotIfNeeded(currentValue: Double) {
        guard isPaperTradingEnabled, currentValue > 0 else { return }
        
        let now = Date()
        if let lastSnapshot = valueSnapshots.last {
            // Only record if at least snapshotInterval has passed
            guard now.timeIntervalSince(lastSnapshot.date) >= snapshotInterval else { return }
        }
        
        valueSnapshots.append((date: now, value: currentValue))
        
        // Prune old snapshots
        if valueSnapshots.count > maxSnapshots {
            valueSnapshots = Array(valueSnapshots.suffix(maxSnapshots))
        }
        
        saveValueSnapshots()
        #if DEBUG
        print("[PaperTrading] Recorded portfolio snapshot: $\(String(format: "%.2f", currentValue)) at \(now)")
        #endif
    }
    
    /// Find the closest snapshot value to a given date.
    /// Returns nil if no snapshots exist or none are within 24 hours of the requested date.
    public func snapshotValue(nearDate date: Date) -> Double? {
        guard !valueSnapshots.isEmpty else { return nil }
        
        // Find the snapshot closest to the requested date
        var bestSnapshot: (date: Date, value: Double)?
        var bestDistance: TimeInterval = .greatestFiniteMagnitude
        
        for snapshot in valueSnapshots {
            let distance = abs(snapshot.date.timeIntervalSince(date))
            if distance < bestDistance {
                bestDistance = distance
                bestSnapshot = snapshot
            }
        }
        
        // Only use if within 24 hours of the requested date
        guard let best = bestSnapshot, bestDistance < 24 * 3600 else { return nil }
        return best.value
    }
    
    /// Update last known prices with new valid prices
    /// Only updates prices that are greater than 0 (valid prices)
    /// This is called when fresh prices are available to cache them for fallback.
    /// Also records timestamps so stale prices can be detected and rejected.
    public func updateLastKnownPrices(_ prices: [String: Double]) {
        var updated = false
        let now = Date()
        for (symbol, price) in prices where price > 0 {
            if lastKnownPrices[symbol] != price {
                lastKnownPrices[symbol] = price
                updated = true
            }
            // Always update timestamp when we receive a valid price,
            // even if the value hasn't changed (it's still fresh)
            lastKnownPriceTimestamps[symbol] = now
        }
        // Only save if there were updates (avoid unnecessary disk writes)
        if updated {
            saveLastKnownPrices()
            saveLastKnownPriceTimestamps()
        }
    }
    
    // MARK: - Pending Order Management
    
    /// Place a pending limit order (for realistic simulation)
    /// Returns an OrderResult with the pending order ID
    public func placePendingOrder(
        symbol: String,
        side: TradeSide,
        quantity: Double,
        limitPrice: Double,
        stopPrice: Double? = nil,
        orderType: String = "LIMIT"
    ) -> OrderResult {
        // Validate the order
        let (base, quote) = parseSymbol(symbol)
        
        if side == .buy {
            // For buy orders, need enough quote currency (including 0.1% fee)
            // FIX: Previously didn't include fee in reserve, causing under-reservation
            let feeRate = 0.001
            let baseCost = quantity * limitPrice
            let fee = baseCost * feeRate
            let requiredQuote = baseCost + fee
            let quoteBalance = paperBalances[quote] ?? 0
            if quoteBalance < requiredQuote {
                return OrderResult(
                    success: false,
                    errorMessage: "Insufficient \(quote) balance. Required: \(String(format: "%.2f", requiredQuote)) (includes fee), Available: \(String(format: "%.2f", quoteBalance))",
                    exchange: "Paper Trading"
                )
            }
            // Reserve the quote currency (including fee)
            paperBalances[quote] = quoteBalance - requiredQuote
        } else {
            // For sell orders, need enough base currency
            let baseBalance = paperBalances[base] ?? 0
            if baseBalance < quantity {
                return OrderResult(
                    success: false,
                    errorMessage: "Insufficient \(base) balance. Required: \(String(format: "%.8f", quantity)), Available: \(String(format: "%.8f", baseBalance))",
                    exchange: "Paper Trading"
                )
            }
            // Reserve the base currency
            paperBalances[base] = baseBalance - quantity
        }
        
        // Create and add the pending order
        let order = PaperPendingOrder(
            symbol: symbol,
            side: side,
            quantity: quantity,
            limitPrice: limitPrice,
            stopPrice: stopPrice,
            orderType: orderType
        )
        
        pendingOrders.append(order)
        
        return OrderResult(
            success: true,
            orderId: order.id.uuidString,
            status: .pending,
            exchange: "Paper Trading"
        )
    }
    
    /// Cancel a pending order
    /// Returns the reserved funds back to the balance (including the reserved fee)
    public func cancelPendingOrder(orderId: String) -> Bool {
        guard let orderUUID = UUID(uuidString: orderId),
              let index = pendingOrders.firstIndex(where: { $0.id == orderUUID }) else {
            return false
        }
        
        let order = pendingOrders[index]
        let (base, quote) = parseSymbol(order.symbol)
        
        // Return reserved funds
        if order.side == .buy {
            // FIX: Must return the FULL reserved amount including the 0.1% fee.
            // Previously only returned (quantity * limitPrice), losing the fee portion.
            // This caused 0.1% of the order value to vanish on every cancellation.
            let feeRate = 0.001
            let baseCost = order.quantity * order.limitPrice
            let reservedQuote = baseCost + (baseCost * feeRate)
            paperBalances[quote, default: 0] += reservedQuote
        } else {
            paperBalances[base, default: 0] += order.quantity
        }
        
        pendingOrders.remove(at: index)
        return true
    }
    
    /// Cancel all pending orders for a symbol
    public func cancelAllPendingOrders(symbol: String? = nil) {
        let ordersToCancel: [PaperPendingOrder]
        if let symbol = symbol {
            ordersToCancel = pendingOrders.filter { $0.symbol.uppercased() == symbol.uppercased() }
        } else {
            ordersToCancel = pendingOrders
        }
        
        for order in ordersToCancel {
            _ = cancelPendingOrder(orderId: order.id.uuidString)
        }
    }
    
    /// Get pending orders for a specific symbol
    public func getPendingOrders(for symbol: String? = nil) -> [PaperPendingOrder] {
        guard let symbol = symbol else { return pendingOrders }
        // FIX: Use exact match or base-symbol match instead of .contains().
        // Previously, searching for "BTC" would also match "WBTCUSDT", "BTCBUSD", etc.
        // Searching for "USD" would match virtually everything.
        let upperSymbol = symbol.uppercased()
        return pendingOrders.filter {
            let orderUpper = $0.symbol.uppercased()
            // Match exact symbol OR match by base asset
            let (base, _) = parseSymbol(orderUpper)
            return orderUpper == upperSymbol || base == upperSymbol
        }
    }
    
    /// Check if any pending orders should be filled at current prices
    /// Call this when prices are updated
    public func checkPendingOrders(prices: [String: Double]) {
        guard !pendingOrders.isEmpty else { return }
        
        var ordersToFill: [(Int, PaperPendingOrder, Double)] = []
        
        for (index, order) in pendingOrders.enumerated() {
            let (base, _) = parseSymbol(order.symbol)
            guard let currentPrice = prices[base.uppercased()] else { continue }
            
            if order.shouldFill(currentPrice: currentPrice) {
                // Determine fill price
                let fillPrice: Double
                switch order.orderType {
                case "STOP":
                    // Stop orders fill at market (current) price
                    fillPrice = currentPrice
                case "STOP_LIMIT", "LIMIT":
                    // Limit orders fill at the limit price (or better)
                    fillPrice = order.limitPrice
                default:
                    fillPrice = order.limitPrice
                }
                ordersToFill.append((index, order, fillPrice))
            }
        }
        
        // Fill orders (reverse order to handle index shifts)
        for (_, order, fillPrice) in ordersToFill.sorted(by: { $0.0 > $1.0 }) {
            fillPendingOrder(order, atPrice: fillPrice)
        }
    }
    
    /// Fill a pending order at the specified price
    /// FIX: Now deducts 0.1% trading fee, matching executePaperTrade behavior.
    /// Previously, limit/stop orders filled without any fee deduction, causing
    /// incorrect balances compared to market orders.
    private func fillPendingOrder(_ order: PaperPendingOrder, atPrice price: Double) {
        let (base, quote) = parseSymbol(order.symbol)
        let totalCost = order.quantity * price
        let feeRate = 0.001 // 0.1% fee, same as executePaperTrade
        let fee = totalCost * feeRate
        
        if order.side == .buy {
            // Buy: add base currency (quote was already reserved at limitPrice + fee)
            paperBalances[base, default: 0] += order.quantity
            
            // Reserved amount includes fee: limitPrice * quantity * 1.001
            let reservedFeeRate = 0.001
            let reservedBaseCost = order.quantity * order.limitPrice
            let reservedQuote = reservedBaseCost + (reservedBaseCost * reservedFeeRate)
            let actualCostWithFee = totalCost + fee
            
            // Refund difference between reserved and actual (price improvement)
            if reservedQuote > actualCostWithFee {
                paperBalances[quote, default: 0] += (reservedQuote - actualCostWithFee)
            } else if actualCostWithFee > reservedQuote {
                // Fill price was worse than limit (possible for stop orders where market
                // price at trigger exceeds the stop price).
                // FIX: Cap the deduction to available balance to prevent negative balances.
                // Negative balances corrupt portfolio calculations and show impossible values.
                let shortfall = actualCostWithFee - reservedQuote
                let availableQuote = paperBalances[quote, default: 0]
                let actualDeduction = min(shortfall, availableQuote)
                paperBalances[quote, default: 0] -= actualDeduction
                if shortfall > availableQuote {
                    #if DEBUG
                    print("⚠️ [PaperTrading] Stop order fill for \(order.symbol): insufficient funds for price slippage. Shortfall: \(formatCurrency(shortfall - actualDeduction))")
                    #endif
                }
            }
        } else {
            // Sell: add quote currency minus fee (base was already reserved)
            let proceedsAfterFee = totalCost - fee
            paperBalances[quote, default: 0] += proceedsAfterFee
        }
        
        // Record the trade
        let trade = PaperTrade(
            symbol: order.symbol,
            side: order.side,
            quantity: order.quantity,
            price: price,
            orderType: order.orderType
        )
        recordTrade(trade)
        
        // Remove from pending
        if let index = pendingOrders.firstIndex(where: { $0.id == order.id }) {
            pendingOrders.remove(at: index)
        }
    }
    
    /// Set up price monitoring for pending orders and lastKnownPrices cache
    private func setupPriceMonitoring() {
        // Subscribe to live price updates from LivePriceManager
        // PERFORMANCE FIX v22: Use throttledPublisher (500ms) instead of raw publisher.
        // Pending order fill checks don't need every single emission — 500ms is fast enough
        // to catch limit order fills while reducing processing overhead significantly.
        priceSubscription = LivePriceManager.shared.throttledPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coins in
                guard let self = self else { return }
                
                // Build price dictionary from incoming prices
                var prices: [String: Double] = [:]
                for coin in coins {
                    if let price = coin.priceUsd, price > 0 {
                        prices[coin.symbol.uppercased()] = price
                    }
                }
                
                // Always update lastKnownPrices cache with valid prices
                // This happens on background price updates, not during view body evaluation
                if !prices.isEmpty {
                    self.updateLastKnownPrices(prices)
                }
                
                // Check if any pending orders should fill
                if !self.pendingOrders.isEmpty {
                    self.checkPendingOrders(prices: prices)
                }
            }
    }
    
    // MARK: - Demo Mode Support
    
    /// Demo trade history (not persisted, generated fresh each session)
    @Published public var demoTradeHistory: [PaperTrade] = []
    
    /// Seed demo trades for demo mode display
    /// Creates sample trades that match the demo bots' activity
    public func seedDemoTrades() {
        guard demoTradeHistory.isEmpty else { return } // Already seeded
        
        let now = Date()
        let calendar = Calendar.current
        
        var trades: [PaperTrade] = []
        
        // BTC DCA Bot trades (12 trades over 14 days)
        let btcPrices: [(Double, Int)] = [
            (94200, -14), (93800, -12), (94500, -10), (95100, -8),
            (94800, -7), (95300, -6), (95800, -5), (94900, -4),
            (95200, -3), (95600, -2), (95900, -1), (96100, 0)
        ]
        for (price, daysAgo) in btcPrices {
            let timestamp = calendar.date(byAdding: .day, value: daysAgo, to: now) ?? now
            trades.append(PaperTrade(
                symbol: "BTCUSDT",
                side: .buy,
                quantity: 100.0 / price, // ~$100 per trade
                price: price,
                timestamp: timestamp,
                orderType: "BOT_DCA"
            ))
        }
        
        // ETH Grid Bot trades (34 trades over 21 days - mix of buys and sells)
        let ethTrades: [(TradeSide, Double, Int)] = [
            (.buy, 3250, -21), (.sell, 3320, -20), (.buy, 3280, -19), (.sell, 3350, -18),
            (.buy, 3300, -17), (.sell, 3380, -16), (.buy, 3310, -15), (.sell, 3400, -14),
            (.buy, 3350, -13), (.sell, 3420, -12), (.buy, 3380, -11), (.sell, 3450, -10),
            (.buy, 3400, -9), (.sell, 3480, -8), (.buy, 3420, -7), (.sell, 3500, -6),
            (.buy, 3450, -5), (.sell, 3520, -4), (.buy, 3480, -3), (.sell, 3550, -2),
            (.buy, 3500, -1), (.sell, 3580, 0), (.buy, 3300, -18), (.sell, 3370, -17),
            (.buy, 3340, -16), (.sell, 3410, -15), (.buy, 3380, -14), (.sell, 3440, -13),
            (.buy, 3410, -12), (.sell, 3470, -11), (.buy, 3440, -10), (.sell, 3510, -9),
            (.buy, 3470, -8), (.sell, 3530, -7)
        ]
        for (side, price, daysAgo) in ethTrades {
            let timestamp = calendar.date(byAdding: .day, value: daysAgo, to: now) ?? now
            let adjustedTimestamp = calendar.date(byAdding: .hour, value: Int.random(in: 0...23), to: timestamp) ?? timestamp
            trades.append(PaperTrade(
                symbol: "ETHUSDT",
                side: side,
                quantity: 50.0 / price, // ~$50 per trade
                price: price,
                timestamp: adjustedTimestamp,
                orderType: "BOT_GRID"
            ))
        }
        
        // SOL Signal Bot trades (8 trades over 7 days)
        let solTrades: [(TradeSide, Double, Int)] = [
            (.buy, 175, -7), (.sell, 182, -6), (.buy, 178, -5), (.sell, 185, -4),
            (.buy, 180, -3), (.sell, 188, -2), (.buy, 183, -2), (.sell, 190, -1)
        ]
        for (side, price, daysAgo) in solTrades {
            let timestamp = calendar.date(byAdding: .day, value: daysAgo, to: now) ?? now
            let adjustedTimestamp = calendar.date(byAdding: .hour, value: Int.random(in: 0...23), to: timestamp) ?? timestamp
            trades.append(PaperTrade(
                symbol: "SOLUSDT",
                side: side,
                quantity: 500.0 / 3.0 / price, // ~$166 per trade (500/3 entries)
                price: price,
                timestamp: adjustedTimestamp,
                orderType: "BOT_SIGNAL"
            ))
        }
        
        // Sort by timestamp (most recent first)
        trades.sort { $0.timestamp > $1.timestamp }
        
        demoTradeHistory = trades
    }
    
    /// Clear demo trades
    public func clearDemoTrades() {
        demoTradeHistory.removeAll()
    }
    
    /// Demo trade statistics
    public var demoTradeCount: Int {
        demoTradeHistory.count
    }
    
    public var demoBuyTradeCount: Int {
        demoTradeHistory.filter { $0.side == .buy }.count
    }
    
    public var demoSellTradeCount: Int {
        demoTradeHistory.filter { $0.side == .sell }.count
    }
    
    public var demoTotalVolumeTraded: Double {
        demoTradeHistory.map { $0.totalValue }.reduce(0, +)
    }
    
    /// Get recent demo trades (limited)
    public func recentDemoTrades(limit: Int = 10) -> [PaperTrade] {
        Array(demoTradeHistory.prefix(limit))
    }
    
    /// Get demo trades filtered by side
    public func demoTrades(side: TradeSide?) -> [PaperTrade] {
        guard let side = side else { return demoTradeHistory }
        return demoTradeHistory.filter { $0.side == side }
    }
    
    /// Get demo trades filtered by asset
    public func demoTrades(forAsset asset: String?) -> [PaperTrade] {
        guard let asset = asset, !asset.isEmpty else { return demoTradeHistory }
        return demoTradeHistory.filter { parseSymbol($0.symbol).base == asset.uppercased() }
    }
    
    // MARK: - Firestore Cloud Sync
    
    /// Start listening to Firestore for paper trading data if user is authenticated.
    /// Called after sign-in completes.
    public func startFirestoreSyncIfAuthenticated() {
        Task { @MainActor in
            guard AuthenticationManager.shared.isAuthenticated,
                  let userId = AuthenticationManager.shared.currentUser?.id else {
                ptLogger.debug("🔥 [PaperTradingSync] Not authenticated, skipping Firestore sync")
                return
            }
            
            startFirestoreListener(userId: userId)
        }
    }
    
    /// Stop Firestore listener. Called on sign-out.
    public func stopFirestoreSync() {
        firestoreListener?.remove()
        firestoreListener = nil
        isFirestoreSyncActive = false
        hasCompletedInitialFetch = false
        syncDebounceTimer?.invalidate()
        syncDebounceTimer = nil
        ptLogger.info("🔥 [PaperTradingSync] Stopped Firestore sync")
    }
    
    /// Trigger a debounced sync of current paper trading data to Firestore.
    /// Called automatically on balance/trade changes via the save methods.
    private func syncToFirestoreIfNeeded() {
        guard !isApplyingFirestoreUpdate, isFirestoreSyncActive else { return }
        
        syncDebounceTimer?.invalidate()
        syncDebounceTimer = Timer.scheduledTimer(withTimeInterval: syncDebounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.uploadToFirestore()
            }
        }
    }
    
    // MARK: - Firestore Listener
    
    /// Whether we have completed the initial server fetch after sign-in.
    /// Until the server confirms no document exists, we must not upload default
    /// local data (which would wipe real cloud data on a fresh install).
    private var hasCompletedInitialFetch = false
    
    /// Key for caching Firestore permission denial
    private static let permDeniedKey = "firestorePermsDenied_paper_trading"
    
    private func startFirestoreListener(userId: String) {
        guard firestoreListener == nil else {
            ptLogger.debug("🔥 [PaperTradingSync] Firestore listener already active")
            return
        }
        
        ptLogger.info("🔥 [PaperTradingSync] Starting Firestore paper trading sync for user \(userId)")
        
        let docRef = db.collection("users").document(userId).collection("paper_trading").document("state")
        
        // ── Step 1: Explicit server fetch on sign-in ──
        // On a fresh install the local Firestore cache is empty. An explicit
        // server fetch ensures we get the real data before the listener can
        // misinterpret an empty cache as "no cloud data" and upload defaults.
        hasCompletedInitialFetch = false
        
        docRef.getDocument(source: .server) { [weak self] snapshot, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.hasCompletedInitialFetch = true
                
                if let error = error {
                    if error.localizedDescription.contains("Missing or insufficient permissions") {
                        self.ptLogger.info("🔥 [PaperTradingSync] Firestore permissions not configured — using local data only")
                        UserDefaults.standard.set([
                            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
                            "at": Date().timeIntervalSince1970
                        ], forKey: Self.permDeniedKey)
                    } else {
                        self.ptLogger.error("🔥 [PaperTradingSync] Initial server fetch failed: \(error.localizedDescription)")
                    }
                } else if let snapshot = snapshot, snapshot.exists, let data = snapshot.data() {
                    UserDefaults.standard.removeObject(forKey: Self.permDeniedKey)
                    self.ptLogger.info("🔥 [PaperTradingSync] Initial server fetch succeeded — restoring paper trading data")
                    self.applyFirestoreSnapshot(data)
                } else {
                    UserDefaults.standard.removeObject(forKey: Self.permDeniedKey)
                    self.ptLogger.info("🔥 [PaperTradingSync] No cloud paper trading data on server, uploading local data")
                    self.uploadToFirestore()
                }
            }
        }
        
        // ── Step 2: Real-time listener for ongoing changes ──
        firestoreListener = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                if error.localizedDescription.contains("Missing or insufficient permissions") {
                    self.ptLogger.info("🔥 [PaperTradingSync] Firestore permissions not configured — using local data only")
                    self.firestoreListener?.remove()
                    self.firestoreListener = nil
                    UserDefaults.standard.set([
                        "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
                        "at": Date().timeIntervalSince1970
                    ], forKey: Self.permDeniedKey)
                } else {
                    self.ptLogger.error("🔥 [PaperTradingSync] Firestore listener error: \(error.localizedDescription)")
                }
                return
            }
            
            // Permission succeeded — clear any cached denial
            UserDefaults.standard.removeObject(forKey: Self.permDeniedKey)
            
            Task { @MainActor in
                self.isFirestoreSyncActive = true
                
                guard let snapshot = snapshot else { return }
                
                // Guard: Never upload default local data based on a cached snapshot
                // before the initial server fetch completes. On a fresh install the
                // cache is empty, so an early snapshot would report !exists and trigger
                // an upload of the default $100k balance — wiping the real cloud data.
                if !snapshot.exists {
                    if snapshot.metadata.isFromCache {
                        self.ptLogger.debug("🔥 [PaperTradingSync] Ignoring empty cache snapshot (waiting for server)")
                        return
                    }
                    if !self.hasCompletedInitialFetch {
                        self.ptLogger.debug("🔥 [PaperTradingSync] Waiting for initial server fetch before uploading")
                        return
                    }
                    self.ptLogger.info("🔥 [PaperTradingSync] No cloud data found (server confirmed), uploading local data")
                    self.uploadToFirestore()
                    return
                }
                
                guard let data = snapshot.data() else { return }
                self.applyFirestoreSnapshot(data)
            }
        }
    }
    
    // MARK: - Apply Firestore Data Locally
    
    private func applyFirestoreSnapshot(_ data: [String: Any]) {
        isApplyingFirestoreUpdate = true
        defer { isApplyingFirestoreUpdate = false }
        
        // Balances
        if let balancesData = data["balances"] as? [String: Double] {
            if balancesData != paperBalances {
                paperBalances = balancesData
                ptLogger.debug("🔥 [PaperTradingSync] Restored balances: \(balancesData.count) assets")
            }
        }
        
        // Trade history
        if let historyJSON = data["tradeHistory"] as? String,
           let historyData = historyJSON.data(using: .utf8),
           let history = try? JSONDecoder().decode([PaperTrade].self, from: historyData) {
            if history.count != paperTradeHistory.count {
                paperTradeHistory = history
                ptLogger.debug("🔥 [PaperTradingSync] Restored \(history.count) trades")
            }
        }
        
        // Pending orders
        if let ordersJSON = data["pendingOrders"] as? String,
           let ordersData = ordersJSON.data(using: .utf8),
           let orders = try? JSONDecoder().decode([PaperPendingOrder].self, from: ordersData) {
            pendingOrders = orders
            ptLogger.debug("🔥 [PaperTradingSync] Restored \(orders.count) pending orders")
        }
        
        // Starting balance
        if let startBal = data["startingBalance"] as? Double {
            startingBalance = startBal
        }
        
        // Initial portfolio value
        if let initVal = data["initialPortfolioValue"] as? Double {
            initialPortfolioValue = initVal
        }
        
        // Paper trading enabled state
        if let enabled = data["isPaperTradingEnabled"] as? Bool {
            isPaperTradingEnabled = enabled
        }
        
        // Realistic limits
        if let realistic = data["realisticLimitOrders"] as? Bool {
            realisticLimitOrders = realistic
        }
        
        // Value snapshots
        if let snapshotsJSON = data["valueSnapshots"] as? String,
           let snapshotsData = snapshotsJSON.data(using: .utf8),
           let pairs = try? JSONDecoder().decode([[Double]].self, from: snapshotsData) {
            valueSnapshots = pairs.compactMap { pair in
                guard pair.count == 2 else { return nil }
                return (date: Date(timeIntervalSince1970: pair[0]), value: pair[1])
            }
            ptLogger.debug("🔥 [PaperTradingSync] Restored \(self.valueSnapshots.count) value snapshots")
        }
        
        // Reset tracking
        if let resetCount = data["totalResetCount"] as? Int {
            totalResetCount = resetCount
        }
        if let lastReset = data["lastResetAt"] as? Double, lastReset > 0 {
            lastResetAt = Date(timeIntervalSince1970: lastReset)
        }
        if let resetStampsArr = data["resetTimestamps"] as? [Double] {
            resetTimestamps = resetStampsArr.map { Date(timeIntervalSince1970: $0) }
        }
        
        // Persist restored data to UserDefaults
        savePaperBalances()
        savePaperTradeHistory()
        savePendingOrders()
        saveValueSnapshots()
        saveResetTracking()
        
        ptLogger.info("🔥 [PaperTradingSync] Applied Firestore paper trading snapshot")
        
        // Force SwiftUI views observing this manager to refresh
        objectWillChange.send()
        NotificationCenter.default.post(name: .paperTradingDidRestoreFromCloud, object: nil)
    }
    
    // MARK: - Upload to Firestore
    
    private func uploadToFirestore() {
        guard !isApplyingFirestoreUpdate else { return }
        
        Task { @MainActor in
            guard AuthenticationManager.shared.isAuthenticated,
                  let userId = AuthenticationManager.shared.currentUser?.id else {
                return
            }
            
            // Encode trade history as JSON string (Firestore doesn't support custom Codable arrays directly)
            let historyJSON: String
            if let data = try? JSONEncoder().encode(Array(paperTradeHistory.prefix(500))),
               let str = String(data: data, encoding: .utf8) {
                historyJSON = str
            } else {
                historyJSON = "[]"
            }
            
            // Encode pending orders as JSON string
            let ordersJSON: String
            if let data = try? JSONEncoder().encode(pendingOrders),
               let str = String(data: data, encoding: .utf8) {
                ordersJSON = str
            } else {
                ordersJSON = "[]"
            }
            
            // Encode value snapshots as JSON string
            let snapshotPairs: [[Double]] = valueSnapshots.map { [$0.date.timeIntervalSince1970, $0.value] }
            let snapshotsJSON: String
            if let data = try? JSONEncoder().encode(snapshotPairs),
               let str = String(data: data, encoding: .utf8) {
                snapshotsJSON = str
            } else {
                snapshotsJSON = "[]"
            }
            
            let paperData: [String: Any] = [
                "balances": paperBalances,
                "tradeHistory": historyJSON,
                "pendingOrders": ordersJSON,
                "startingBalance": startingBalance,
                "initialPortfolioValue": initialPortfolioValue,
                "isPaperTradingEnabled": isPaperTradingEnabled,
                "realisticLimitOrders": realisticLimitOrders,
                "valueSnapshots": snapshotsJSON,
                "totalResetCount": totalResetCount,
                "lastResetAt": lastResetAt?.timeIntervalSince1970 ?? 0,
                "resetTimestamps": resetTimestamps.map { $0.timeIntervalSince1970 },
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            let docRef = db.collection("users").document(userId).collection("paper_trading").document("state")
            
            docRef.setData(paperData, merge: true) { [weak self] error in
                if let error = error {
                    self?.ptLogger.error("🔥 [PaperTradingSync] Failed to sync to Firestore: \(error.localizedDescription)")
                } else {
                    self?.ptLogger.debug("🔥 [PaperTradingSync] Paper trading data synced to Firestore")
                }
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted after PaperTradingManager applies Firestore data to local storage.
    /// Views that cache paper trading state can observe this to force a refresh.
    static let paperTradingDidRestoreFromCloud = Notification.Name("PaperTradingDidRestoreFromCloud")
}

// MARK: - View Extension

extension View {
    /// Observes paper trading changes and triggers the given action.
    func onPaperTradingChange(perform action: @escaping (Bool) -> Void) -> some View {
        self.onReceive(PaperTradingManager.shared.$isPaperTradingEnabled) { newValue in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                action(newValue)
            }
        }
    }
}
