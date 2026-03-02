//
//  LeaderboardEngine.swift
//  CryptoSage
//
//  Engine for calculating and managing leaderboard rankings.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Trading Mode

/// Distinguishes between paper trading and portfolio (real) trading leaderboards
public enum LeaderboardTradingMode: String, Codable, CaseIterable {
    case paper = "Paper"
    case portfolio = "Portfolio"  // Renamed from "live" for clarity
    
    // Legacy alias for backward compatibility
    static var live: LeaderboardTradingMode { .portfolio }
    
    public var displayName: String {
        switch self {
        case .paper: return "Paper Trading"
        case .portfolio: return "Portfolio"
        }
    }
    
    public var shortName: String {
        rawValue
    }
    
    public var badgeText: String {
        switch self {
        case .paper: return "Virtual trades"
        case .portfolio: return "Real trades"
        }
    }
    
    public var icon: String {
        switch self {
        case .paper: return "doc.text"
        case .portfolio: return "chart.pie.fill"
        }
    }
    
    public var color: Color {
        switch self {
        case .paper: return AppTradingMode.paper.color  // Warm amber (consistent with LeaderboardEntryTradingMode)
        case .portfolio: return .green
        }
    }
}

// MARK: - Leaderboard Engine

@MainActor
public final class LeaderboardEngine: ObservableObject {
    public static let shared = LeaderboardEngine()
    
    // MARK: - Leaderboard Eligibility Requirements
    //
    // Anti-gaming system to prevent leaderboard manipulation.
    // Requirements differ between Paper and Portfolio (live) modes.
    
    /// Requirements for appearing on the leaderboard
    ///
    /// The system is intentionally lightweight — both Pro and Premium can reset their
    /// paper trading accounts, but at different frequencies:
    ///   - Pro:     1 reset per 90 days (quarterly)
    ///   - Premium: 1 reset per 30 days (monthly)
    ///
    /// The main anti-gaming protection is the leaderboard impact of resets:
    ///   - 14-day cooldown where scores carry a penalty
    ///   - 20% score reduction per reset in the rolling window
    ///   - Time-weight multiplier resets to minimum (0.7x), takes months to rebuild
    ///
    /// This approach lets everyone recover from a bad run (paper trading is for learning)
    /// while keeping the leaderboard competitive and fair.
    public struct EligibilityRequirements {
        // Paper Trading Leaderboard
        static let paperRequireStandardBalance: Bool = true // Must use $100K standard balance
        
        // Portfolio (Live) Leaderboard
        static let portfolioMinPortfolioValueUSD: Double = 500.0  // Minimum $500 portfolio
        static let portfolioMinAccountAgeDays: Int = 7            // Account must be 7+ days old
        
        // Scoring Adjustments (Anti-Gaming)
        
        /// Time-weighting: longer track records get a bonus multiplier (max 1.5x at 90+ days)
        /// This naturally rewards users who DON'T reset, making resets a real tradeoff.
        static func timeWeightMultiplier(daysSinceStart: Int) -> Double {
            let days = Double(max(1, daysSinceStart))
            // Ramps from 0.7x at day 1 to 1.0x at day 30 to 1.5x at day 90+
            return min(1.5, 0.7 + (days / 100.0))
        }
    }
    
    // MARK: - Demo Data Configuration
    
    /// Controls how demo data is handled as real users join
    public struct DemoDataConfig {
        /// Minimum number of real users before demo data is completely hidden
        /// Once we have this many real users, demo data disappears entirely
        static let minRealUsersToHideDemo: Int = 15
        
        /// Maximum number of demo users to show when we have few real users
        /// This decreases as more real users join
        static let maxDemoUsers: Int = 50
        
        /// Whether to show demo data at all (master switch)
        /// Can be toggled via server config in the future
        static var showDemoData: Bool = true
        
        /// Demo user identifier prefix (to distinguish from real users)
        static let demoUserPrefix: String = "demo_"
    }
    
    // MARK: - Published Properties
    
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var currentLeaderboard: [LeaderboardEntry] = []
    @Published public private(set) var currentCategory: LeaderboardCategory = .pnl
    @Published public private(set) var currentPeriod: StatsPeriod = .month
    @Published public var currentTradingMode: LeaderboardTradingMode = {
        // Smart default: Portfolio for free users, Paper for Pro+ users with paper trading
        let hasPaperAccess = SubscriptionManager.shared.hasAccess(to: .paperTrading)
        let isPaperEnabled = PaperTradingManager.shared.isPaperTradingEnabled
        return (hasPaperAccess && isPaperEnabled) ? .paper : .portfolio
    }()
    
    // Cached leaderboards
    @Published public private(set) var cachedLeaderboards: [String: [LeaderboardEntry]] = [:]
    
    /// Number of real users currently on the leaderboard (for monitoring)
    @Published public private(set) var realUserCount: Int = 0
    
    /// Whether demo data is currently being shown
    @Published public private(set) var isShowingDemoData: Bool = true
    
    // MARK: - Private Properties
    
    private let socialService = SocialService.shared
    private var cancellables = Set<AnyCancellable>()
    private let cacheKey = "leaderboard_cache"
    private let updateInterval: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    private init() {
        loadCachedLeaderboards()
        loadDemoDataPreference()
    }
    
    // MARK: - Public Methods
    
    /// Fetch leaderboard for a specific category, period, and trading mode
    public func fetchLeaderboard(
        category: LeaderboardCategory = .pnl,
        period: StatsPeriod = .month,
        tradingMode: LeaderboardTradingMode? = nil,
        limit: Int = 100,
        forceRefresh: Bool = false
    ) async throws -> [LeaderboardEntry] {
        let mode = tradingMode ?? currentTradingMode
        let cacheKey = "\(mode.rawValue)_\(category.rawValue)_\(period.rawValue)"
        
        // Check cache
        if !forceRefresh,
           let cached = cachedLeaderboards[cacheKey],
           !cached.isEmpty,
           let lastUpdate = lastUpdated,
           Date().timeIntervalSince(lastUpdate) < updateInterval {
            currentLeaderboard = cached
            currentCategory = category
            currentPeriod = period
            currentTradingMode = mode
            return cached
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // In a real app, this would fetch from a server
        // For now, generate leaderboard from local data + demo users
        let entries = await generateLeaderboard(category: category, period: period, tradingMode: mode, limit: limit)
        
        // Cache the results
        cachedLeaderboards[cacheKey] = entries
        currentLeaderboard = entries
        currentCategory = category
        currentPeriod = period
        currentTradingMode = mode
        lastUpdated = Date()
        
        saveCachedLeaderboards()
        
        return entries
    }
    
    /// Switch trading mode and refresh leaderboard
    public func switchTradingMode(_ mode: LeaderboardTradingMode) async {
        currentTradingMode = mode
        _ = try? await fetchLeaderboard(
            category: currentCategory,
            period: currentPeriod,
            tradingMode: mode,
            forceRefresh: false
        )
    }
    
    /// Calculate rankings for a set of users
    public func calculateRankings(
        users: [UserProfile],
        category: LeaderboardCategory,
        period: StatsPeriod
    ) -> [LeaderboardEntry] {
        let filteredUsers = users.filter { $0.isPublic }
        
        let entries = filteredUsers.map { user -> LeaderboardEntry in
            let score = calculateScore(for: user, category: category, period: period)
            return LeaderboardEntry(
                userId: user.id,
                username: user.username,
                displayName: user.displayName,
                avatarURL: user.avatarURL,
                rank: 0, // Will be set after sorting
                score: score,
                pnl: user.performanceStats.totalPnL,
                pnlPercent: user.performanceStats.pnlPercent,
                winRate: user.performanceStats.winRate,
                totalTrades: user.performanceStats.totalTrades,
                badges: Array(user.badges.prefix(3)),
                period: period,
                category: category
            )
        }
        
        // Sort by score descending
        var sortedEntries = entries.sorted { $0.score > $1.score }
        
        // Assign ranks
        for i in 0..<sortedEntries.count {
            sortedEntries[i].rank = i + 1
        }
        
        return sortedEntries
    }
    
    /// Update a user's stats in the leaderboard
    public func updateUserStats(userId: UUID, stats: PerformanceStats) {
        // Update all cached leaderboards
        for (key, var entries) in cachedLeaderboards {
            if let index = entries.firstIndex(where: { $0.userId == userId }) {
                entries[index] = LeaderboardEntry(
                    id: entries[index].id,
                    userId: userId,
                    username: entries[index].username,
                    displayName: entries[index].displayName,
                    avatarURL: entries[index].avatarURL,
                    rank: entries[index].rank,
                    score: calculateScoreFromStats(stats, category: currentCategory),
                    pnl: stats.totalPnL,
                    pnlPercent: stats.pnlPercent,
                    winRate: stats.winRate,
                    totalTrades: stats.totalTrades,
                    badges: entries[index].badges,
                    period: currentPeriod,
                    category: currentCategory
                )
                
                // Re-sort and re-rank
                entries.sort { $0.score > $1.score }
                for i in 0..<entries.count {
                    entries[i].rank = i + 1
                }
                
                cachedLeaderboards[key] = entries
            }
        }
        
        // Update current leaderboard if applicable
        if let index = currentLeaderboard.firstIndex(where: { $0.userId == userId }) {
            var updated = currentLeaderboard[index]
            updated = LeaderboardEntry(
                id: updated.id,
                userId: userId,
                username: updated.username,
                displayName: updated.displayName,
                avatarURL: updated.avatarURL,
                rank: updated.rank,
                score: calculateScoreFromStats(stats, category: currentCategory),
                pnl: stats.totalPnL,
                pnlPercent: stats.pnlPercent,
                winRate: stats.winRate,
                totalTrades: stats.totalTrades,
                badges: updated.badges,
                period: currentPeriod,
                category: currentCategory
            )
            currentLeaderboard[index] = updated
            
            // Re-sort
            currentLeaderboard.sort { $0.score > $1.score }
            for i in 0..<currentLeaderboard.count {
                currentLeaderboard[i].rank = i + 1
            }
        }
        
        saveCachedLeaderboards()
    }
    
    /// Get user's current rank
    public func getUserRank(userId: UUID, category: LeaderboardCategory = .pnl, period: StatsPeriod = .month, tradingMode: LeaderboardTradingMode? = nil) -> Int? {
        let mode = tradingMode ?? currentTradingMode
        let cacheKey = "\(mode.rawValue)_\(category.rawValue)_\(period.rawValue)"
        guard let entries = cachedLeaderboards[cacheKey] else { return nil }
        return entries.first { $0.userId == userId }?.rank
    }
    
    /// Get top N entries
    public func getTopEntries(count: Int = 10) -> [LeaderboardEntry] {
        Array(currentLeaderboard.prefix(count))
    }
    
    /// Get entries around a specific rank
    public func getEntriesAround(rank: Int, range: Int = 5) -> [LeaderboardEntry] {
        guard !currentLeaderboard.isEmpty else { return [] }
        
        let startIndex = max(0, rank - range - 1)
        let endIndex = min(currentLeaderboard.count, rank + range)
        
        return Array(currentLeaderboard[startIndex..<endIndex])
    }
    
    // MARK: - Leaderboard Eligibility
    
    /// Reason why a user is ineligible for the leaderboard
    public enum IneligibilityReason: String, Codable {
        case recentReset = "Leaderboard cooldown active after reset"
        case nonStandardBalance = "Use the standard $100K balance to qualify"
        case portfolioTooSmall = "Minimum $500 portfolio value required"
        case accountTooNew = "Account must be at least 7 days old"
        case notParticipating = "Join the leaderboard to compete"
    }
    
    /// Check if the current user is eligible for the paper trading leaderboard.
    /// Returns nil if eligible, or the reason for ineligibility.
    ///
    /// Eligibility is simple by design:
    ///   - Must use standard $100K balance (fair comparison)
    ///   - Must not be in reset cooldown (14 days after a reset)
    ///
    /// Anti-gaming is handled by the tier system (Pro can't reset at all) and
    /// score penalties (time-weighting + reset penalty) rather than arbitrary minimums.
    public func paperTradingEligibility() -> IneligibilityReason? {
        let ptm = PaperTradingManager.shared
        
        // Must not be in cooldown after a reset
        if ptm.isInLeaderboardCooldown {
            return .recentReset
        }
        
        // Must use standard starting balance for fair ROI comparison
        if EligibilityRequirements.paperRequireStandardBalance && !ptm.isUsingStandardBalance {
            return .nonStandardBalance
        }
        
        return nil // Eligible
    }
    
    /// Check if the current user is eligible for the portfolio (live) leaderboard.
    /// portfolioValue: current portfolio value in USD
    /// accountCreatedAt: when the user's account was created
    public func portfolioEligibility(
        portfolioValue: Double,
        accountCreatedAt: Date
    ) -> IneligibilityReason? {
        // Must have minimum portfolio value (prevents gaming with tiny accounts)
        if portfolioValue < EligibilityRequirements.portfolioMinPortfolioValueUSD {
            return .portfolioTooSmall
        }
        
        // Account must be old enough
        let accountAgeDays = Int(Date().timeIntervalSince(accountCreatedAt) / (24 * 3600))
        if accountAgeDays < EligibilityRequirements.portfolioMinAccountAgeDays {
            return .accountTooNew
        }
        
        return nil // Eligible
    }
    
    /// Calculate the anti-gaming adjusted score for a paper trading user.
    /// Applies reset penalty + time-weighting to the raw score.
    ///
    /// The key insight: Pro users can't reset, so they have long track records and
    /// naturally benefit from time-weighting. Premium users who reset get penalized
    /// both by the 20% score hit AND by resetting their time-weight back to minimum.
    /// This makes resetting a genuine tradeoff rather than a free do-over.
    public func adjustedPaperScore(rawScore: Double, category: LeaderboardCategory) -> Double {
        let ptm = PaperTradingManager.shared
        
        // 1. Reset penalty: each reset in the 90-day window reduces score by 20%
        let resetMultiplier = ptm.leaderboardScorePenaltyMultiplier
        
        // 2. Time weighting: longer track records get a multiplier bonus (max 1.5x at 90+ days)
        // This naturally rewards Pro users who can't reset — they accumulate time weight
        let timeMultiplier = EligibilityRequirements.timeWeightMultiplier(daysSinceStart: ptm.daysSinceLastReset)
        
        // Apply both adjustments to all categories
        // The time multiplier already handles the "one lucky trade" concern —
        // a fresh account starts at 0.7x which ramps up over months of consistent trading
        return rawScore * resetMultiplier * timeMultiplier
    }
    
    /// Summary of current user's eligibility status for display in UI
    public struct EligibilityStatus {
        public let isEligible: Bool
        public let reason: IneligibilityReason?
        public let canReset: Bool
        public let resetsRemaining: Int
        public let maxResets: Int
        public let resetWindowDays: Int
        public let isInCooldown: Bool
        public let cooldownDaysRemaining: Int
        public let scorePenaltyPercent: Int  // 0-100, how much their score is reduced
        public let timeWeightPercent: Int    // Current time-weight as a percentage (70-150%)
    }
    
    /// Get the current user's full eligibility status for paper trading
    public func currentPaperEligibilityStatus() -> EligibilityStatus {
        let ptm = PaperTradingManager.shared
        let ineligibility = paperTradingEligibility()
        let penaltyPercent = Int((1.0 - ptm.leaderboardScorePenaltyMultiplier) * 100)
        let timeWeight = Int(EligibilityRequirements.timeWeightMultiplier(daysSinceStart: ptm.daysSinceLastReset) * 100)
        
        return EligibilityStatus(
            isEligible: ineligibility == nil,
            reason: ineligibility,
            canReset: ptm.canReset,
            resetsRemaining: ptm.resetsRemaining,
            maxResets: ptm.maxResetsForCurrentTier,
            resetWindowDays: ptm.resetWindowDaysForCurrentTier,
            isInCooldown: ptm.isInLeaderboardCooldown,
            cooldownDaysRemaining: ptm.leaderboardCooldownDaysRemaining,
            scorePenaltyPercent: penaltyPercent,
            timeWeightPercent: timeWeight
        )
    }
    
    /// Clear all cached data
    public func clearCache() {
        cachedLeaderboards.removeAll()
        currentLeaderboard = []
        lastUpdated = nil
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
    
    // MARK: - Demo Data Control
    
    /// Manually toggle demo data visibility (for testing/admin purposes)
    /// This is persisted in UserDefaults
    public func setDemoDataEnabled(_ enabled: Bool) {
        DemoDataConfig.showDemoData = enabled
        UserDefaults.standard.set(enabled, forKey: "leaderboard_show_demo_data")
        
        // Refresh leaderboard to apply change
        Task {
            _ = try? await fetchLeaderboard(
                category: currentCategory,
                period: currentPeriod,
                tradingMode: currentTradingMode,
                forceRefresh: true
            )
        }
    }
    
    /// Load demo data preference from storage
    private func loadDemoDataPreference() {
        // Default to true if not set
        if UserDefaults.standard.object(forKey: "leaderboard_show_demo_data") != nil {
            DemoDataConfig.showDemoData = UserDefaults.standard.bool(forKey: "leaderboard_show_demo_data")
        }
    }
    
    /// Get the current demo data status message for UI display
    public var demoDataStatusMessage: String? {
        guard isShowingDemoData else { return nil }
        
        let realCount = realUserCount
        let threshold = DemoDataConfig.minRealUsersToHideDemo
        let remaining = threshold - realCount
        
        if realCount == 0 {
            return "Showing sample leaderboard data"
        } else if remaining > 0 {
            return "\(realCount) real trader\(realCount == 1 ? "" : "s") • \(remaining) more to unlock full leaderboard"
        }
        return nil
    }
    
    /// Check if an entry is a demo/mock user
    public func isDemoUser(_ entry: LeaderboardEntry) -> Bool {
        return !entry.isRealUser
    }
    
    // MARK: - Private Methods
    
    /// Smart leaderboard generation with gradual demo data phase-out
    /// 
    /// How it works:
    /// 1. Real users who opted into the leaderboard are ALWAYS included first
    /// 2. Demo users fill remaining spots to make the leaderboard look populated
    /// 3. As more real users join, fewer demo users are shown
    /// 4. Once we have enough real users (15+), demo data disappears completely
    /// 5. Real users are ranked by their actual performance - they can beat demo users!
    private func generateLeaderboard(
        category: LeaderboardCategory,
        period: StatsPeriod,
        tradingMode: LeaderboardTradingMode,
        limit: Int
    ) async -> [LeaderboardEntry] {
        var realEntries: [LeaderboardEntry] = []
        var demoEntries: [LeaderboardEntry] = []
        
        // Convert trading mode for entry
        let entryTradingMode: LeaderboardEntryTradingMode = tradingMode == .paper ? .paper : .portfolio
        
        // STEP 1: Collect all real users who opted into the leaderboard
        // In production, this would fetch from Firebase/backend
        // For now, we include the current user if they've opted in
        realEntries = await fetchRealLeaderboardEntries(
            category: category,
            period: period,
            tradingMode: tradingMode,
            entryTradingMode: entryTradingMode
        )
        
        // Update real user count for monitoring
        realUserCount = realEntries.count
        
        // STEP 2: Determine if we need demo data
        let needsDemoData = DemoDataConfig.showDemoData && 
                           realEntries.count < DemoDataConfig.minRealUsersToHideDemo
        
        isShowingDemoData = needsDemoData
        
        // STEP 3: If we need demo data, generate it to fill gaps
        if needsDemoData {
            // Calculate how many demo users to show
            // Formula: Start with max, subtract 3 for each real user (accelerates phase-out)
            let demoUsersToShow = max(0, DemoDataConfig.maxDemoUsers - (realEntries.count * 3))
            
            if demoUsersToShow > 0 {
                demoEntries = generateDemoEntries(
                    category: category,
                    period: period,
                    tradingMode: tradingMode,
                    entryTradingMode: entryTradingMode,
                    count: demoUsersToShow
                )
            }
        }
        
        // STEP 4: Combine and sort all entries by score
        // Real users compete fairly with demo users - if a real user performs better, they rank higher!
        var allEntries = realEntries + demoEntries
        allEntries.sort { $0.score > $1.score }
        
        // STEP 5: Assign ranks
        for i in 0..<allEntries.count {
            allEntries[i].rank = i + 1
        }
        
        return Array(allEntries.prefix(limit))
    }
    
    /// Fetch real users who have opted into the leaderboard
    private func fetchRealLeaderboardEntries(
        category: LeaderboardCategory,
        period: StatsPeriod,
        tradingMode: LeaderboardTradingMode,
        entryTradingMode: LeaderboardEntryTradingMode
    ) async -> [LeaderboardEntry] {
        var entries: [LeaderboardEntry] = []
        
        // Include current user if they have a profile and opted into leaderboard
        if let currentProfile = socialService.currentProfile,
           currentProfile.showOnLeaderboard {
            
            // Check if user can compete in this specific leaderboard mode
            // Uses the proper participation mode check instead of just primary mode
            let canCompete: Bool = {
                switch tradingMode {
                case .paper:
                    return currentProfile.canCompeteInPaper
                case .portfolio:
                    return currentProfile.canCompeteInLive
                }
            }()
            
            if canCompete {
                let stats = currentProfile.performanceStats
                let score = calculateScore(for: currentProfile, category: category, period: period)
                
                entries.append(LeaderboardEntry(
                    userId: currentProfile.id,
                    username: currentProfile.username,
                    displayName: currentProfile.displayName,
                    avatarURL: currentProfile.avatarURL,
                    avatarPresetId: currentProfile.avatarPresetId,
                    rank: 0,
                    score: score,
                    pnl: stats.totalPnL,
                    pnlPercent: stats.pnlPercent,
                    winRate: stats.winRate,
                    totalTrades: stats.totalTrades,
                    badges: Array(currentProfile.badges.prefix(3)),
                    period: period,
                    category: category,
                    tradingMode: entryTradingMode,
                    isRealUser: true  // Mark as real user
                ))
            }
        }
        
        // TODO: In production, fetch other opted-in users from Firebase
        // let otherUsers = await socialService.fetchLeaderboardUsers(tradingMode: tradingMode)
        // for user in otherUsers { ... }
        
        return entries
    }
    
    /// Generate demo entries to fill the leaderboard
    private func generateDemoEntries(
        category: LeaderboardCategory,
        period: StatsPeriod,
        tradingMode: LeaderboardTradingMode,
        entryTradingMode: LeaderboardEntryTradingMode,
        count: Int
    ) -> [LeaderboardEntry] {
        var entries: [LeaderboardEntry] = []
        
        // Different demo users for paper vs live trading
        let demoNames: [(String, String, Double, Double, Double)] = tradingMode == .paper
            ? generatePaperTradingDemoNames()
            : generatePortfolioDemoNames()
        
        // Demo avatar preset IDs for variety - different presets per trading mode
        let demoAvatarPresets: [String?] = tradingMode == .paper ? [
            // Paper Trading - More playful/virtual themed avatars
            "special_crown", "animal_dolphin", "crypto_chart", "abstract_hexagon",
            "crypto_rocket", "special_fire", "animal_owl", "abstract_spiral",
            "crypto_bitcoin", "special_aurora",
            "animal_fox", "crypto_moon", "abstract_prism", "animal_wolf",
            "crypto_lightning", "abstract_star", "animal_eagle", "crypto_shield",
            "abstract_cube", "animal_hawk",
            "crypto_ethereum", "animal_tiger", "abstract_wave", "crypto_globe",
            "animal_lion", "abstract_crystal", "animal_shark", "crypto_stack",
            "abstract_atom", "animal_dragon",
            "abstract_sphere", "crypto_diamond", "animal_bear", "abstract_infinity",
            nil, nil, nil, nil, nil, nil
        ] : [
            // Portfolio Trading - More professional/serious avatars
            "animal_whale", "special_crown", "animal_bull", "crypto_diamond",
            "animal_shark", "crypto_chart", "abstract_hexagon", "animal_lion",
            "crypto_moon", "special_fire",
            "animal_eagle", "crypto_lightning", "abstract_prism", "animal_wolf",
            "crypto_bitcoin", "abstract_star", "animal_tiger", "crypto_shield",
            "abstract_spiral", "animal_hawk",
            "crypto_globe", "animal_fox", "abstract_cube", "crypto_stack",
            "animal_owl", "abstract_crystal", "animal_dragon", "crypto_ethereum",
            "abstract_wave", "special_aurora",
            "abstract_atom", "crypto_rocket", "animal_bear", "abstract_sphere",
            nil, nil, nil, nil, nil, nil
        ]
        
        // Add demo entries (limited by count parameter)
        for (i, demo) in demoNames.prefix(count).enumerated() {
            let score: Double
            switch category {
            case .pnl:
                score = demo.2
            case .pnlPercent:
                score = demo.3
            case .winRate:
                score = demo.4 * 100
            case .consistency:
                score = demo.4 * demo.3
            case .botPerformance:
                score = demo.3 * 0.7 + demo.4 * 30
            case .copiedMost:
                score = Double(500 - i * 20)
            }
            
            let avatarPresetId = i < demoAvatarPresets.count ? demoAvatarPresets[i] : nil
            
            entries.append(LeaderboardEntry(
                userId: UUID(),
                username: demo.0,
                displayName: demo.1,
                avatarURL: nil,
                avatarPresetId: avatarPresetId,
                rank: 0,
                score: score,
                pnl: demo.2,
                pnlPercent: demo.3,
                winRate: demo.4,
                totalTrades: Int.random(in: 100...2000),
                badges: generateRandomBadges(),
                period: period,
                category: category,
                tradingMode: entryTradingMode,
                isRealUser: false  // Mark as demo user
            ))
        }
        
        return entries
    }
    
    // MARK: - Demo Data Generation
    
    /// Generate demo names for Paper Trading leaderboard
    private func generatePaperTradingDemoNames() -> [(String, String, Double, Double, Double)] {
        return [
            // Top 10
            ("CryptoTrader_47", "CryptoTrader_47", 256780.50, 385.4, 0.85),
            ("PortfolioKing", "PortfolioKing", 198450.25, 295.2, 0.82),
            ("SatoshiFan", "SatoshiFan", 187230.00, 268.5, 0.79),
            ("DiamondHands", "DiamondHands", 176540.75, 242.3, 0.77),
            ("MoonWatcher", "MoonWatcher", 165890.30, 228.9, 0.75),
            ("BlockchainBull", "BlockchainBull", 154320.80, 215.4, 0.73),
            ("AltcoinAce", "AltcoinAce", 148750.25, 198.7, 0.71),
            ("TokenSage", "TokenSage", 142180.60, 186.3, 0.69),
            ("ChartNinja", "ChartNinja", 138940.15, 178.2, 0.68),
            ("HODLer_99", "HODLer_99", 134560.90, 169.5, 0.66),
            // 11-20
            ("TrendRider", "TrendRider", 131280.45, 162.8, 0.65),
            ("ScalpHawk", "ScalpHawk", 128750.30, 157.4, 0.64),
            ("SwingKing_21", "SwingKing_21", 125420.80, 151.2, 0.63),
            ("PositionAlpha", "PositionAlpha", 122890.55, 146.8, 0.62),
            ("CryptoOwl", "CryptoOwl", 120150.40, 142.3, 0.61),
            ("MarketPulse", "MarketPulse", 118340.25, 138.9, 0.60),
            ("AlphaSeeker", "AlphaSeeker", 116780.90, 135.2, 0.59),
            ("YieldHunter", "YieldHunter", 115230.65, 132.1, 0.58),
            ("NFT_Collector", "NFT_Collector", 113890.40, 129.4, 0.57),
            ("TokenMaxi", "TokenMaxi", 112450.80, 126.8, 0.56),
            // 21-30
            ("MomentumPro", "MomentumPro", 111890.20, 124.5, 0.55),
            ("BreakoutKing", "BreakoutKing", 111250.40, 122.8, 0.54),
            ("ChartWizard", "ChartWizard", 110680.30, 121.2, 0.53),
            ("VolumeTracker", "VolumeTracker", 110120.55, 119.8, 0.52),
            ("PatternFinder", "PatternFinder", 9650.80, 18.4, 0.51),
            ("FibTrader_88", "FibTrader_88", 9180.25, 17.2, 0.50),
            ("RSI_Watcher", "RSI_Watcher", 8740.60, 16.1, 0.49),
            ("MACD_Runner", "MACD_Runner", 8320.40, 15.0, 0.48),
            ("EMA_Crosser", "EMA_Crosser", 7920.15, 14.1, 0.47),
            ("BollingerPro", "BollingerPro", 7540.90, 13.3, 0.46),
            // 31-40
            ("CandleReader", "CandleReader", 7180.45, 12.5, 0.45),
            ("SupportLevel", "SupportLevel", 6840.30, 11.8, 0.44),
            ("ResistanceHit", "ResistanceHit", 6520.80, 11.2, 0.43),
            ("LiquidityPro", "LiquidityPro", 6210.55, 10.6, 0.42),
            ("OrderFlowGuy", "OrderFlowGuy", 5920.40, 10.1, 0.41),
            ("TapeReader_X", "TapeReader_X", 5640.25, 9.6, 0.40),
            ("SpreadHunter", "SpreadHunter", 5380.60, 9.2, 0.39),
            ("ArbTrader_77", "ArbTrader_77", 5130.40, 8.8, 0.38),
            ("FuturesBull", "FuturesBull", 4890.15, 8.4, 0.37),
            ("PerpTrader", "PerpTrader", 4660.90, 8.0, 0.36),
            // 41-50
            ("LeverageKing", "LeverageKing", 4450.45, 7.7, 0.35),
            ("MarginCall_X", "MarginCall_X", 4250.30, 7.4, 0.34),
            ("DeltaNeutral", "DeltaNeutral", 4060.80, 7.1, 0.33),
            ("GammaTrader", "GammaTrader", 3880.55, 6.8, 0.32),
            ("ThetaGang_12", "ThetaGang_12", 3710.40, 6.5, 0.31),
            ("VegaCrusher", "VegaCrusher", 3550.25, 6.3, 0.30),
            ("RhoTrader", "RhoTrader", 3400.60, 6.0, 0.29),
            ("IV_Crusher", "IV_Crusher", 3260.40, 5.8, 0.28),
            ("SpotTrader_1", "SpotTrader_1", 3130.15, 5.6, 0.27),
            ("LimitSniper", "LimitSniper", 3010.90, 5.4, 0.26)
        ]
    }
    
    /// Generate demo names for Portfolio leaderboard (more conservative gains)
    private func generatePortfolioDemoNames() -> [(String, String, Double, Double, Double)] {
        return [
            // Top 10 - Portfolio Elite (more realistic gains)
            ("crypto_legend", "Crypto Legend", 156780.50, 85.4, 0.72),
            ("whale_hunter", "Whale Hunter", 98450.25, 65.2, 0.68),
            ("moon_sniper", "Moon Sniper", 87230.00, 58.5, 0.65),
            ("diamond_whale", "Diamond Whale", 76540.75, 52.3, 0.63),
            ("defi_master", "DeFi Master", 65890.30, 48.9, 0.61),
            ("grid_genius", "Grid Genius", 54320.80, 45.4, 0.59),
            ("dca_warrior", "DCA Warrior", 48750.25, 38.7, 0.57),
            ("signal_sage", "Signal Sage", 42180.60, 36.3, 0.55),
            ("algo_architect", "Algo Architect", 38940.15, 32.2, 0.54),
            ("bot_builder", "Bot Builder", 34560.90, 29.5, 0.52),
            // 11-20
            ("trend_tracker", "Trend Tracker", 31280.45, 26.8, 0.51),
            ("scalp_king", "Scalp King", 28750.30, 24.4, 0.50),
            ("swing_master", "Swing Master", 25420.80, 21.2, 0.49),
            ("position_pro", "Position Pro", 22890.55, 18.8, 0.48),
            ("crypto_sage", "Crypto Sage", 20150.40, 16.3, 0.47),
            ("market_maven", "Market Maven", 18340.25, 14.9, 0.46),
            ("alpha_hunter", "Alpha Hunter", 16780.90, 13.2, 0.45),
            ("yield_farmer", "Yield Farmer", 15230.65, 12.1, 0.44),
            ("nft_whale", "NFT Whale", 13890.40, 11.4, 0.43),
            ("token_trader", "Token Trader", 12450.80, 10.8, 0.42),
            // 21-30
            ("momentum_king", "Momentum King", 11890.20, 9.5, 0.41),
            ("breakout_boss", "Breakout Boss", 11250.40, 8.8, 0.40),
            ("chart_wizard", "Chart Wizard", 10680.30, 8.2, 0.39),
            ("volume_victor", "Volume Victor", 10120.55, 7.8, 0.38),
            ("pattern_pro", "Pattern Pro", 9650.80, 7.4, 0.37),
            ("fib_master", "Fib Master", 9180.25, 6.9, 0.36),
            ("rsi_ranger", "RSI Ranger", 8740.60, 6.5, 0.35),
            ("macd_maven", "MACD Maven", 8320.40, 6.2, 0.34),
            ("ema_expert", "EMA Expert", 7920.15, 5.9, 0.33),
            ("bollinger_bull", "Bollinger Bull", 7540.90, 5.6, 0.32),
            // 31-40
            ("candle_crusher", "Candle Crusher", 7180.45, 5.3, 0.31),
            ("support_sniper", "Support Sniper", 6840.30, 5.0, 0.30),
            ("resistance_raider", "Resistance Raider", 6520.80, 4.8, 0.29),
            ("liquidity_lord", "Liquidity Lord", 6210.55, 4.5, 0.28),
            ("order_flow_oracle", "Order Flow Oracle", 5920.40, 4.2, 0.27),
            ("tape_reader", "Tape Reader", 5640.25, 3.9, 0.26),
            ("spread_specialist", "Spread Specialist", 5380.60, 3.7, 0.25),
            ("arb_ace", "Arb Ace", 5130.40, 3.5, 0.24),
            ("futures_fox", "Futures Fox", 4890.15, 3.3, 0.23),
            ("perp_pioneer", "Perp Pioneer", 4660.90, 3.1, 0.22),
            // 41-50
            ("leverage_lion", "Leverage Lion", 4450.45, 2.9, 0.21),
            ("margin_master", "Margin Master", 4250.30, 2.7, 0.20),
            ("delta_dealer", "Delta Dealer", 4060.80, 2.5, 0.19),
            ("gamma_guru", "Gamma Guru", 3880.55, 2.4, 0.18),
            ("theta_tycoon", "Theta Tycoon", 3710.40, 2.2, 0.17),
            ("vega_victor", "Vega Victor", 3550.25, 2.0, 0.16),
            ("rho_rider", "Rho Rider", 3400.60, 1.9, 0.15),
            ("iv_investor", "IV Investor", 3260.40, 1.8, 0.14),
            ("spot_specialist", "Spot Specialist", 3130.15, 1.6, 0.13),
            ("limit_lord", "Limit Lord", 3010.90, 1.5, 0.12)
        ]
    }
    
    private func calculateScore(for user: UserProfile, category: LeaderboardCategory, period: StatsPeriod) -> Double {
        let stats = user.performanceStats
        return calculateScoreFromStats(stats, category: category)
    }
    
    private func calculateScoreFromStats(_ stats: PerformanceStats, category: LeaderboardCategory) -> Double {
        switch category {
        case .pnl:
            return stats.totalPnL
        case .pnlPercent:
            return stats.pnlPercent
        case .winRate:
            return stats.winRate * 100
        case .consistency:
            // Consistency score: combination of win rate, sharpe ratio, and low drawdown
            let sharpe = stats.sharpeRatio ?? 0
            let drawdownPenalty = 1.0 - stats.maxDrawdown
            return stats.winRate * 50 + sharpe * 30 + drawdownPenalty * 20
        case .botPerformance:
            // Bot performance: ROI weighted by trade count
            let tradeWeight = min(Double(stats.totalTrades) / 100, 1.0)
            return stats.pnlPercent * tradeWeight
        case .copiedMost:
            // This would be based on social metrics, not trading stats
            return 0
        }
        // Note: Anti-gaming adjustments (time-weighting, reset penalties) are applied
        // separately via adjustedPaperScore() at the leaderboard rendering layer,
        // not here in the raw score calculation.
    }
    
    private func generateRandomBadges() -> [UserBadge] {
        let allBadges = [
            PredefinedBadge.firstTrade,
            PredefinedBadge.profitable10,
            PredefinedBadge.profitable100,
            PredefinedBadge.profitable1000,
            PredefinedBadge.winStreak5,
            PredefinedBadge.botCreator,
            PredefinedBadge.popular10
        ]
        
        let count = Int.random(in: 1...3)
        return Array(allBadges.shuffled().prefix(count))
    }
    
    private func loadCachedLeaderboards() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([String: [LeaderboardEntry]].self, from: data) else {
            return
        }
        cachedLeaderboards = cached
    }
    
    private func saveCachedLeaderboards() {
        guard let data = try? JSONEncoder().encode(cachedLeaderboards) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

// MARK: - Leaderboard View Model Extension

public extension LeaderboardEngine {
    /// Formatted rank string with medal emoji
    func formattedRank(_ rank: Int) -> String {
        switch rank {
        case 1: return "🥇 1st"
        case 2: return "🥈 2nd"
        case 3: return "🥉 3rd"
        default: return "#\(rank)"
        }
    }
    
    /// Color for rank
    func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        case 4...10: return .blue
        default: return .primary
        }
    }
    
    /// Check if user is in top 10
    func isTop10(userId: UUID) -> Bool {
        currentLeaderboard.prefix(10).contains { $0.userId == userId }
    }
}
