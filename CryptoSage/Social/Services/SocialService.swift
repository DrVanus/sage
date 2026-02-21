//
//  SocialService.swift
//  CryptoSage
//
//  Singleton service managing all social interactions including user profiles,
//  follow relationships, bot sharing, and activity feeds.
//  Uses local-first storage with optional CloudKit sync.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Social Service

@MainActor
public final class SocialService: ObservableObject {
    public static let shared = SocialService()
    
    // MARK: - Published Properties
    
    @Published public private(set) var currentProfile: UserProfile?
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: Error?
    @Published public private(set) var isBrowsingAsGuest = false
    
    @Published public private(set) var following: [UUID] = []
    @Published public private(set) var followers: [UUID] = []
    @Published public private(set) var sharedBots: [SharedBotConfig] = []
    @Published public private(set) var copiedBots: [CopiedBot] = []
    @Published public private(set) var activityFeed: [ActivityFeedItem] = []
    @Published public private(set) var discoveredUsers: [UserProfile] = []
    @Published public private(set) var discoveredBots: [SharedBotConfig] = []
    
    // MARK: - Private Properties
    
    private let storageKey = "social_data"
    private let profileKey = "user_profile"
    private let followingKey = "following_ids"
    private let sharedBotsKey = "shared_bots"
    private let copiedBotsKey = "copied_bots"
    private let activityKey = "activity_feed"
    private let likesKey = "user_likes"
    
    private var cancellables = Set<AnyCancellable>()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // Demo data for presentation
    private var useDemoData = false
    
    // MARK: - Initialization
    
    private init() {
        loadLocalData()
        setupSubscriptions()
    }
    
    // MARK: - Profile Management
    
    /// Create or update the current user's profile
    public func createOrUpdateProfile(
        username: String,
        displayName: String? = nil,
        avatarPresetId: String? = nil,
        bio: String? = nil,
        isPublic: Bool = true,
        showOnLeaderboard: Bool = false,
        leaderboardMode: LeaderboardParticipationMode = .none,
        liveTrackingConsent: Bool = false,
        primaryTradingMode: UserTradingMode = .paper,
        socialLinks: SocialLinks? = nil
    ) async throws {
        isLoading = true
        defer { isLoading = false }
        
        if var profile = currentProfile {
            // Update existing
            profile.username = username
            profile.displayName = displayName
            profile.avatarPresetId = avatarPresetId
            profile.bio = bio
            profile.isPublic = isPublic
            profile.showOnLeaderboard = showOnLeaderboard
            profile.leaderboardMode = leaderboardMode
            profile.liveTrackingConsent = liveTrackingConsent
            if liveTrackingConsent && profile.consentGrantedAt == nil {
                profile.consentGrantedAt = Date()
            } else if !liveTrackingConsent {
                profile.consentGrantedAt = nil
            }
            profile.primaryTradingMode = primaryTradingMode
            profile.socialLinks = socialLinks
            profile.updatedAt = Date()
            currentProfile = profile
        } else {
            // Create new
            let profile = UserProfile(
                username: username,
                displayName: displayName,
                avatarPresetId: avatarPresetId,
                bio: bio,
                isPublic: isPublic,
                showOnLeaderboard: showOnLeaderboard,
                primaryTradingMode: primaryTradingMode,
                leaderboardMode: leaderboardMode,
                liveTrackingConsent: liveTrackingConsent,
                consentGrantedAt: liveTrackingConsent ? Date() : nil,
                socialLinks: socialLinks
            )
            currentProfile = profile
            
            // Clear guest browsing mode since user now has a real profile
            isBrowsingAsGuest = false
            UserDefaults.standard.set(false, forKey: "social_browsing_as_guest")
        }
        
        // Sync avatar preset to AppStorage so homepage/settings can display it
        syncAvatarToAppStorage()
        
        saveLocalData()
    }
    
    /// Update profile avatar URL
    public func updateAvatar(url: String) async throws {
        guard var profile = currentProfile else {
            throw SocialError.notAuthenticated
        }
        
        profile.avatarURL = url
        profile.updatedAt = Date()
        currentProfile = profile
        saveLocalData()
    }
    
    /// Update performance stats for current user
    public func updatePerformanceStats(_ stats: PerformanceStats) {
        guard var profile = currentProfile else { return }
        profile.performanceStats = stats
        profile.updatedAt = Date()
        currentProfile = profile
        saveLocalData()
        
        // Check for badge eligibility
        checkBadgeEligibility(stats: stats)
    }
    
    /// Award a badge to the current user
    public func awardBadge(_ badge: UserBadge) {
        guard var profile = currentProfile else { return }
        
        // Don't award duplicate badges
        guard !profile.badges.contains(where: { $0.id == badge.id }) else { return }
        
        profile.badges.append(badge)
        profile.updatedAt = Date()
        currentProfile = profile
        saveLocalData()
        
        // Add activity
        addActivity(
            type: .earnedBadge,
            title: "Earned \(badge.name)",
            description: badge.description
        )
    }
    
    // MARK: - Follow Management
    
    /// Follow a user
    public func follow(userId: UUID) async throws {
        guard currentProfile != nil else {
            throw SocialError.notAuthenticated
        }
        
        guard !following.contains(userId) else { return }
        
        following.append(userId)
        saveLocalData()
        
        // Update follower count (in real app, this would be server-side)
        if var profile = currentProfile {
            profile.followingCount = following.count
            currentProfile = profile
        }
    }
    
    /// Unfollow a user
    public func unfollow(userId: UUID) async throws {
        guard currentProfile != nil else {
            throw SocialError.notAuthenticated
        }
        
        following.removeAll { $0 == userId }
        saveLocalData()
        
        if var profile = currentProfile {
            profile.followingCount = following.count
            currentProfile = profile
        }
    }
    
    /// Check if following a user
    public func isFollowing(userId: UUID) -> Bool {
        following.contains(userId)
    }
    
    /// Get follower profiles
    public func fetchFollowers() async throws -> [UserProfile] {
        // In a real app, this would fetch from a server
        // For now, return demo data
        return generateDemoUsers(count: followers.count)
    }
    
    /// Get following profiles
    public func fetchFollowing() async throws -> [UserProfile] {
        // In a real app, this would fetch from a server
        return generateDemoUsers(count: following.count)
    }
    
    // MARK: - Bot Sharing
    
    /// Share a bot configuration
    public func shareBot(
        from paperBot: PaperBot,
        name: String,
        description: String?,
        tags: [String] = [],
        riskLevel: RiskLevel = .medium
    ) async throws -> SharedBotConfig {
        guard let profile = currentProfile else {
            throw SocialError.notAuthenticated
        }
        
        let botType: SharedBotType
        switch paperBot.type {
        case .dca: botType = .dca
        case .grid: botType = .grid
        case .signal: botType = .signal
        case .derivatives: botType = .derivatives
        case .predictionMarket: botType = .predictionMarket
        }
        
        // Use the bot's config dictionary directly and add metadata
        var config = paperBot.config
        config["pair"] = paperBot.tradingPair
        config["exchange"] = paperBot.exchange
        
        // Calculate performance stats
        let botStats = calculateBotPerformance(paperBot)
        
        let sharedBot = SharedBotConfig(
            creatorId: profile.id,
            creatorUsername: profile.username,
            botType: botType,
            name: name,
            description: description,
            config: config,
            tradingPair: paperBot.tradingPair,
            exchange: paperBot.exchange,
            performanceStats: botStats,
            tags: tags,
            riskLevel: riskLevel
        )
        
        sharedBots.append(sharedBot)
        saveLocalData()
        
        // Update profile
        var updatedProfile = profile
        updatedProfile.sharedBotsCount = sharedBots.count
        currentProfile = updatedProfile
        
        // Award badge if first shared bot
        if sharedBots.count == 1 {
            awardBadge(PredefinedBadge.botCreator)
        }
        
        // Add activity
        addActivity(
            type: .sharedBot,
            title: "Shared \(name)",
            description: "A new \(botType.displayName) is now available",
            botId: sharedBot.id,
            botName: name
        )
        
        return sharedBot
    }
    
    /// Copy a shared bot to local paper bots
    public func copyBot(_ sharedBot: SharedBotConfig) async throws -> CopiedBot {
        guard let profile = currentProfile else {
            throw SocialError.notAuthenticated
        }
        
        // Create local paper bot from config
        let localBotId = UUID()
        
        // In real implementation, this would create the actual PaperBot
        // through PaperBotManager
        
        let copiedBot = CopiedBot(
            originalBotId: sharedBot.id,
            originalCreatorId: sharedBot.creatorId,
            copierId: profile.id,
            localBotId: localBotId
        )
        
        copiedBots.append(copiedBot)
        saveLocalData()
        
        // Add activity
        addActivity(
            type: .copiedBot,
            title: "Copied \(sharedBot.name)",
            description: "From @\(sharedBot.creatorUsername)",
            botId: sharedBot.id,
            botName: sharedBot.name
        )
        
        return copiedBot
    }
    
    /// Delete a shared bot
    public func deleteSharedBot(_ botId: UUID) async throws {
        sharedBots.removeAll { $0.id == botId }
        saveLocalData()
        
        if var profile = currentProfile {
            profile.sharedBotsCount = sharedBots.count
            currentProfile = profile
        }
    }
    
    /// Update shared bot stats
    public func updateSharedBotStats(_ botId: UUID, stats: BotPerformanceStats) {
        if let index = sharedBots.firstIndex(where: { $0.id == botId }) {
            sharedBots[index].performanceStats = stats
            sharedBots[index].updatedAt = Date()
            saveLocalData()
        }
    }
    
    // MARK: - Likes
    
    private var likes: Set<String> = []
    
    /// Like a bot
    public func likeBot(_ botId: UUID) async throws {
        guard currentProfile != nil else {
            throw SocialError.notAuthenticated
        }
        
        let key = "bot:\(botId.uuidString)"
        likes.insert(key)
        saveLikes()
        
        // Update count in shared bots
        if let index = sharedBots.firstIndex(where: { $0.id == botId }) {
            sharedBots[index].likesCount += 1
            saveLocalData()
        }
    }
    
    /// Unlike a bot
    public func unlikeBot(_ botId: UUID) async throws {
        let key = "bot:\(botId.uuidString)"
        likes.remove(key)
        saveLikes()
        
        if let index = sharedBots.firstIndex(where: { $0.id == botId }) {
            sharedBots[index].likesCount = max(0, sharedBots[index].likesCount - 1)
            saveLocalData()
        }
    }
    
    /// Check if user has liked a bot
    public func hasLikedBot(_ botId: UUID) -> Bool {
        likes.contains("bot:\(botId.uuidString)")
    }
    
    // MARK: - Discovery
    
    /// Discover popular bots
    public func discoverBots(
        sortBy: BotSortOption = .popular,
        botType: SharedBotType? = nil,
        riskLevel: RiskLevel? = nil,
        limit: Int = 20
    ) async throws -> [SharedBotConfig] {
        isLoading = true
        defer { isLoading = false }
        
        // In real app, this would fetch from server
        // For now, return local shared bots + demo data
        var bots = sharedBots
        
        if useDemoData || bots.isEmpty {
            bots.append(contentsOf: generateDemoBots())
        }
        
        // Filter
        if let type = botType {
            bots = bots.filter { $0.botType == type }
        }
        if let risk = riskLevel {
            bots = bots.filter { $0.riskLevel == risk }
        }
        
        // Sort
        switch sortBy {
        case .popular:
            bots.sort { $0.copiesCount > $1.copiesCount }
        case .newest:
            bots.sort { $0.createdAt > $1.createdAt }
        case .topPerformance:
            bots.sort { $0.performanceStats.pnlPercent > $1.performanceStats.pnlPercent }
        case .mostLiked:
            bots.sort { $0.likesCount > $1.likesCount }
        }
        
        discoveredBots = Array(bots.prefix(limit))
        return discoveredBots
    }
    
    /// Discover users
    public func discoverUsers(limit: Int = 20) async throws -> [UserProfile] {
        isLoading = true
        defer { isLoading = false }
        
        // In real app, fetch from server
        let users = generateDemoUsers(count: limit)
        discoveredUsers = users
        return users
    }
    
    /// Search for bots
    public func searchBots(query: String) async throws -> [SharedBotConfig] {
        let lowercasedQuery = query.lowercased()
        
        var results = sharedBots.filter {
            $0.name.lowercased().contains(lowercasedQuery) ||
            ($0.description?.lowercased().contains(lowercasedQuery) ?? false) ||
            $0.tags.contains { $0.lowercased().contains(lowercasedQuery) } ||
            $0.tradingPair.lowercased().contains(lowercasedQuery)
        }
        
        // Add demo results if needed
        if useDemoData || results.isEmpty {
            let demoBots = generateDemoBots().filter {
                $0.name.lowercased().contains(lowercasedQuery) ||
                $0.tradingPair.lowercased().contains(lowercasedQuery)
            }
            results.append(contentsOf: demoBots)
        }
        
        return results
    }
    
    /// Search for users
    public func searchUsers(query: String) async throws -> [UserProfile] {
        let lowercasedQuery = query.lowercased()
        
        let demoUsers = generateDemoUsers(count: 10)
        return demoUsers.filter {
            $0.username.lowercased().contains(lowercasedQuery) ||
            ($0.displayName?.lowercased().contains(lowercasedQuery) ?? false)
        }
    }
    
    // MARK: - Activity Feed
    
    /// Fetch activity feed
    public func fetchActivityFeed(limit: Int = 50) async throws -> [ActivityFeedItem] {
        // In real app, fetch from server based on followed users
        if useDemoData || activityFeed.isEmpty {
            activityFeed = generateDemoActivity()
        }
        return Array(activityFeed.prefix(limit))
    }
    
    /// Add an activity item
    public func addActivity(
        type: ActivityType,
        title: String,
        description: String? = nil,
        botId: UUID? = nil,
        botName: String? = nil,
        metadata: [String: String]? = nil
    ) {
        guard let profile = currentProfile else { return }
        
        let item = ActivityFeedItem(
            userId: profile.id,
            username: profile.username,
            avatarURL: profile.avatarURL,
            activityType: type,
            title: title,
            description: description,
            relatedBotId: botId,
            relatedBotName: botName,
            metadata: metadata
        )
        
        activityFeed.insert(item, at: 0)
        
        // Keep only last 100 items
        if activityFeed.count > 100 {
            activityFeed = Array(activityFeed.prefix(100))
        }
        
        saveLocalData()
    }
    
    // MARK: - Demo Mode
    
    /// Enable demo mode - allows viewing demo content without creating a profile
    /// This does NOT create a fake user profile, just enables viewing of demo leaderboards and bots
    public func enableDemoMode() {
        useDemoData = true
        isBrowsingAsGuest = true
        
        // Persist guest browsing preference
        UserDefaults.standard.set(true, forKey: "social_browsing_as_guest")
        
        // Note: We no longer auto-create a demo profile
        // User must explicitly create a profile to participate in social features
        
        Task {
            _ = try? await discoverBots()
            _ = try? await discoverUsers()
            _ = try? await fetchActivityFeed()
        }
    }
    
    /// Disable demo mode
    public func disableDemoMode() {
        useDemoData = false
        isBrowsingAsGuest = false
        UserDefaults.standard.set(false, forKey: "social_browsing_as_guest")
    }
    
    /// Check if user has a real profile (not just browsing as guest)
    public var hasRealProfile: Bool {
        currentProfile != nil
    }
    
    // MARK: - Private Helpers
    
    private func setupSubscriptions() {
        // Subscribe to DemoModeManager if available
        NotificationCenter.default.publisher(for: .init("DemoModeChanged"))
            .sink { [weak self] notification in
                if let enabled = notification.object as? Bool {
                    if enabled {
                        self?.enableDemoMode()
                    } else {
                        self?.disableDemoMode()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadLocalData() {
        // Load profile
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let profile = try? decoder.decode(UserProfile.self, from: data) {
            currentProfile = profile
            // Sync avatar to AppStorage on startup
            syncAvatarToAppStorage()
        }
        
        // Load guest browsing preference
        isBrowsingAsGuest = UserDefaults.standard.bool(forKey: "social_browsing_as_guest")
        if isBrowsingAsGuest {
            useDemoData = true
        }
        
        // Load following
        if let data = UserDefaults.standard.data(forKey: followingKey),
           let ids = try? decoder.decode([UUID].self, from: data) {
            following = ids
        }
        
        // Load shared bots
        if let data = UserDefaults.standard.data(forKey: sharedBotsKey),
           let bots = try? decoder.decode([SharedBotConfig].self, from: data) {
            sharedBots = bots
        }
        
        // Load copied bots
        if let data = UserDefaults.standard.data(forKey: copiedBotsKey),
           let bots = try? decoder.decode([CopiedBot].self, from: data) {
            copiedBots = bots
        }
        
        // Load activity
        if let data = UserDefaults.standard.data(forKey: activityKey),
           let items = try? decoder.decode([ActivityFeedItem].self, from: data) {
            activityFeed = items
        }
        
        // Load likes
        if let data = UserDefaults.standard.data(forKey: likesKey),
           let likeSet = try? decoder.decode(Set<String>.self, from: data) {
            likes = likeSet
        }
    }
    
    /// Sync social profile avatar to AppStorage so the homepage/settings can display it
    private func syncAvatarToAppStorage() {
        let presetId = currentProfile?.avatarPresetId ?? ""
        UserDefaults.standard.set(presetId, forKey: "profile.avatarPresetId")
    }
    
    private func saveLocalData() {
        if let profile = currentProfile,
           let data = try? encoder.encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
        
        if let data = try? encoder.encode(following) {
            UserDefaults.standard.set(data, forKey: followingKey)
        }
        
        if let data = try? encoder.encode(sharedBots) {
            UserDefaults.standard.set(data, forKey: sharedBotsKey)
        }
        
        if let data = try? encoder.encode(copiedBots) {
            UserDefaults.standard.set(data, forKey: copiedBotsKey)
        }
        
        if let data = try? encoder.encode(activityFeed) {
            UserDefaults.standard.set(data, forKey: activityKey)
        }
    }
    
    private func saveLikes() {
        if let data = try? encoder.encode(likes) {
            UserDefaults.standard.set(data, forKey: likesKey)
        }
    }
    
    private func calculateBotPerformance(_ bot: PaperBot) -> BotPerformanceStats {
        // Use the bot's stored statistics
        let totalPnL = bot.totalProfit
        let totalTrades = bot.totalTrades
        
        guard totalTrades > 0 else { return .empty }
        
        // Estimate win rate from profit (positive profit suggests more wins)
        let estimatedWinRate = totalPnL > 0 ? 0.55 : 0.45
        
        return BotPerformanceStats(
            totalPnL: totalPnL,
            pnlPercent: totalPnL > 0 ? (totalPnL / 10000) * 100 : 0, // Assume $10k base
            totalTrades: totalTrades,
            winRate: estimatedWinRate,
            avgTradeProfit: totalTrades > 0 ? totalPnL / Double(totalTrades) : 0,
            maxDrawdown: 0.1,
            runningDays: Calendar.current.dateComponents([.day], from: bot.createdAt, to: Date()).day ?? 0,
            lastTradeAt: bot.lastRunAt
        )
    }
    
    private func checkBadgeEligibility(stats: PerformanceStats) {
        guard let profile = currentProfile else { return }
        
        // First trade badge
        if stats.totalTrades >= 1 && !profile.badges.contains(where: { $0.id == "first_trade" }) {
            awardBadge(PredefinedBadge.firstTrade)
        }
        
        // Profit milestones
        if stats.totalPnL >= 10 && !profile.badges.contains(where: { $0.id == "profitable_10" }) {
            awardBadge(PredefinedBadge.profitable10)
        }
        if stats.totalPnL >= 100 && !profile.badges.contains(where: { $0.id == "profitable_100" }) {
            awardBadge(PredefinedBadge.profitable100)
        }
        if stats.totalPnL >= 1000 && !profile.badges.contains(where: { $0.id == "profitable_1000" }) {
            awardBadge(PredefinedBadge.profitable1000)
        }
    }
    
    // MARK: - Demo Data Generation
    
    private func generateDemoUsers(count: Int) -> [UserProfile] {
        let usernames = ["crypto_whale", "btc_maxi", "defi_degen", "grid_master", "dca_king",
                        "algo_trader", "moon_hunter", "diamond_hands", "eth_bull", "sol_trader"]
        let displayNames = ["Crypto Whale", "BTC Maximalist", "DeFi Degen", "Grid Master", "DCA King",
                           "Algo Trader", "Moon Hunter", "Diamond Hands", "ETH Bull", "SOL Trader"]
        
        return (0..<min(count, usernames.count)).map { i in
            UserProfile(
                username: usernames[i],
                displayName: displayNames[i],
                bio: "Trading since 2020 | \(["🚀", "📈", "💎", "🦍", "🐋"].randomElement() ?? "🚀")",
                isPublic: true,
                followersCount: Int.random(in: 10...5000),
                followingCount: Int.random(in: 5...500),
                sharedBotsCount: Int.random(in: 0...10),
                performanceStats: PerformanceStats(
                    totalPnL: Double.random(in: -1000...50000),
                    pnlPercent: Double.random(in: -20...150),
                    winRate: Double.random(in: 0.4...0.85),
                    totalTrades: Int.random(in: 50...1000),
                    winningTrades: Int.random(in: 30...600),
                    losingTrades: Int.random(in: 20...400)
                ),
                badges: [PredefinedBadge.firstTrade, PredefinedBadge.profitable100]
            )
        }
    }
    
    private func generateDemoBots() -> [SharedBotConfig] {
        let botConfigs: [(String, SharedBotType, String)] = [
            ("BTC Weekly DCA", .dca, "BTCUSDT"),
            ("ETH Grid Hunter", .grid, "ETHUSDT"),
            ("SOL Momentum", .signal, "SOLUSDT"),
            ("BNB Scalper", .derivatives, "BNBUSDT"),
            ("AVAX Accumulator", .dca, "AVAXUSDT"),
            ("DOT Grid Trader", .grid, "DOTUSDT"),
            ("LINK Signal Bot", .signal, "LINKUSDT"),
            ("MATIC DCA Pro", .dca, "MATICUSDT")
        ]
        
        let demoUsers = generateDemoUsers(count: 8)
        
        return botConfigs.enumerated().map { index, config in
            let user = demoUsers[index % demoUsers.count]
            return SharedBotConfig(
                creatorId: user.id,
                creatorUsername: user.username,
                botType: config.1,
                name: config.0,
                description: "Automated \(config.1.displayName) for \(config.2) pair",
                config: ["pair": config.2],
                tradingPair: config.2,
                exchange: ["Binance", "KuCoin", "Bybit"].randomElement() ?? "Binance",
                performanceStats: BotPerformanceStats(
                    totalPnL: Double.random(in: 100...10000),
                    pnlPercent: Double.random(in: 5...80),
                    totalTrades: Int.random(in: 20...500),
                    winRate: Double.random(in: 0.5...0.85),
                    runningDays: Int.random(in: 7...180)
                ),
                copiesCount: Int.random(in: 5...500),
                likesCount: Int.random(in: 10...1000),
                tags: [config.1.rawValue.lowercased(), config.2.lowercased().replacingOccurrences(of: "usdt", with: "")],
                riskLevel: [.low, .medium, .high].randomElement() ?? .medium
            )
        }
    }
    
    private func generateDemoActivity() -> [ActivityFeedItem] {
        let users = generateDemoUsers(count: 5)
        let bots = generateDemoBots()
        
        var activities: [ActivityFeedItem] = []
        
        for (i, user) in users.enumerated() {
            let types: [ActivityType] = [.sharedBot, .copiedBot, .achievedRank, .earnedBadge, .botPerformance]
            let type = types[i % types.count]
            let bot = bots[i % bots.count]
            
            activities.append(ActivityFeedItem(
                userId: user.id,
                username: user.username,
                avatarURL: user.avatarURL,
                activityType: type,
                title: "\(type == .sharedBot ? "Shared" : type == .copiedBot ? "Copied" : "Updated") \(bot.name)",
                description: type == .botPerformance ? "+\(String(format: "%.1f", bot.performanceStats.pnlPercent))% this week" : nil,
                relatedBotId: bot.id,
                relatedBotName: bot.name,
                timestamp: Date().addingTimeInterval(-Double(i) * 3600 * Double.random(in: 1...24))
            ))
        }
        
        return activities.sorted { $0.timestamp > $1.timestamp }
    }
}

// MARK: - Bot Sort Option

public enum BotSortOption: String, CaseIterable {
    case popular = "Popular"
    case newest = "Newest"
    case topPerformance = "Top Performance"
    case mostLiked = "Most Liked"
}

// MARK: - Social Errors

public enum SocialError: LocalizedError {
    case notAuthenticated
    case userNotFound
    case botNotFound
    case alreadyFollowing
    case notFollowing
    case invalidData
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please create a profile first"
        case .userNotFound:
            return "User not found"
        case .botNotFound:
            return "Bot not found"
        case .alreadyFollowing:
            return "Already following this user"
        case .notFollowing:
            return "Not following this user"
        case .invalidData:
            return "Invalid data"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
