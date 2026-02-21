//
//  SocialModels.swift
//  CryptoSage
//
//  Core data models for social features including user profiles,
//  leaderboards, shared bot configurations, and activity feeds.
//

import Foundation
import SwiftUI

// MARK: - User Profile

/// User's primary trading mode for social features
public enum UserTradingMode: String, Codable, CaseIterable {
    case paper = "Paper"
    case portfolio = "Portfolio"  // Renamed from "live" for clarity
    
    // Legacy alias for backward compatibility
    static var live: UserTradingMode { .portfolio }
    
    public var displayName: String {
        switch self {
        case .paper: return "Paper Trading"
        case .portfolio: return "Portfolio"
        }
    }
}

// MARK: - Leaderboard Participation Mode

/// How a user participates in leaderboards
public enum LeaderboardParticipationMode: String, Codable, CaseIterable {
    case none = "None"           // Not participating
    case paperOnly = "Paper"     // Paper trading only
    case liveOnly = "Live"       // Live trading only (from portfolio)
    case both = "Both"           // Compete in both
    
    public var displayName: String {
        switch self {
        case .none: return "Not Competing"
        case .paperOnly: return "Paper Trading Only"
        case .liveOnly: return "Portfolio Only"
        case .both: return "Paper & Portfolio"
        }
    }
    
    public var description: String {
        switch self {
        case .none: return "Your trading performance won't appear on leaderboards"
        case .paperOnly: return "Compete using your paper trading results"
        case .liveOnly: return "Compete using your connected portfolio performance"
        case .both: return "Compete in both paper and portfolio leaderboards"
        }
    }
    
    public var icon: String {
        switch self {
        case .none: return "eye.slash"
        case .paperOnly: return "doc.text"
        case .liveOnly: return "checkmark.seal.fill"
        case .both: return "star.fill"
        }
    }
}

/// Represents a user's social profile
public struct UserProfile: Codable, Identifiable, Equatable {
    public let id: UUID
    public var username: String
    public var displayName: String?
    public var avatarURL: String?
    public var avatarPresetId: String?  // ID of selected preset avatar (nil = use initials)
    public var bio: String?
    public var isPublic: Bool
    public var isVerified: Bool
    public var showOnLeaderboard: Bool  // Opt-in for leaderboard visibility
    public var primaryTradingMode: UserTradingMode  // Paper or Live trading
    public var leaderboardMode: LeaderboardParticipationMode  // How user participates in leaderboards
    public var liveTrackingConsent: Bool  // Explicit consent for live portfolio tracking
    public var consentGrantedAt: Date?  // When live tracking consent was granted
    public let createdAt: Date
    public var updatedAt: Date
    public var followersCount: Int
    public var followingCount: Int
    public var sharedBotsCount: Int
    public var performanceStats: PerformanceStats
    public var badges: [UserBadge]
    public var socialLinks: SocialLinks?
    
    public init(
        id: UUID = UUID(),
        username: String,
        displayName: String? = nil,
        avatarURL: String? = nil,
        avatarPresetId: String? = nil,
        bio: String? = nil,
        isPublic: Bool = true,
        isVerified: Bool = false,
        showOnLeaderboard: Bool = false,  // Opt-out by default
        primaryTradingMode: UserTradingMode = .paper,
        leaderboardMode: LeaderboardParticipationMode = .none,
        liveTrackingConsent: Bool = false,
        consentGrantedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        followersCount: Int = 0,
        followingCount: Int = 0,
        sharedBotsCount: Int = 0,
        performanceStats: PerformanceStats = .empty,
        badges: [UserBadge] = [],
        socialLinks: SocialLinks? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.avatarPresetId = avatarPresetId
        self.bio = bio
        self.isPublic = isPublic
        self.isVerified = isVerified
        self.showOnLeaderboard = showOnLeaderboard
        self.primaryTradingMode = primaryTradingMode
        self.leaderboardMode = leaderboardMode
        self.liveTrackingConsent = liveTrackingConsent
        self.consentGrantedAt = consentGrantedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.sharedBotsCount = sharedBotsCount
        self.performanceStats = performanceStats
        self.badges = badges
        self.socialLinks = socialLinks
    }
    
    /// Display name with fallback to username
    public var nameToDisplay: String {
        displayName ?? username
    }
    
    /// Whether user is participating in any leaderboard
    public var isCompeting: Bool {
        leaderboardMode != .none && showOnLeaderboard
    }
    
    /// Whether user can appear on paper trading leaderboard
    public var canCompeteInPaper: Bool {
        showOnLeaderboard && (leaderboardMode == .paperOnly || leaderboardMode == .both)
    }
    
    /// Whether user can appear on live trading leaderboard
    public var canCompeteInLive: Bool {
        showOnLeaderboard && liveTrackingConsent && (leaderboardMode == .liveOnly || leaderboardMode == .both)
    }
    
    public static func == (lhs: UserProfile, rhs: UserProfile) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Performance Stats

/// Trading performance statistics for a user
public struct PerformanceStats: Codable, Equatable {
    public var totalPnL: Double
    public var pnlPercent: Double
    public var winRate: Double
    public var totalTrades: Int
    public var winningTrades: Int
    public var losingTrades: Int
    public var avgHoldTime: TimeInterval
    public var avgProfitPerTrade: Double
    public var sharpeRatio: Double?
    public var maxDrawdown: Double
    public var bestTrade: Double?
    public var worstTrade: Double?
    public var period: StatsPeriod
    public var lastUpdated: Date
    
    public init(
        totalPnL: Double = 0,
        pnlPercent: Double = 0,
        winRate: Double = 0,
        totalTrades: Int = 0,
        winningTrades: Int = 0,
        losingTrades: Int = 0,
        avgHoldTime: TimeInterval = 0,
        avgProfitPerTrade: Double = 0,
        sharpeRatio: Double? = nil,
        maxDrawdown: Double = 0,
        bestTrade: Double? = nil,
        worstTrade: Double? = nil,
        period: StatsPeriod = .allTime,
        lastUpdated: Date = Date()
    ) {
        self.totalPnL = totalPnL
        self.pnlPercent = pnlPercent
        self.winRate = winRate
        self.totalTrades = totalTrades
        self.winningTrades = winningTrades
        self.losingTrades = losingTrades
        self.avgHoldTime = avgHoldTime
        self.avgProfitPerTrade = avgProfitPerTrade
        self.sharpeRatio = sharpeRatio
        self.maxDrawdown = maxDrawdown
        self.bestTrade = bestTrade
        self.worstTrade = worstTrade
        self.period = period
        self.lastUpdated = lastUpdated
    }
    
    public static let empty = PerformanceStats()
    
    /// Computed profit factor
    public var profitFactor: Double? {
        guard losingTrades > 0, let worst = worstTrade, worst < 0 else { return nil }
        let totalLosses = abs(worst) * Double(losingTrades)
        guard totalLosses > 0 else { return nil }
        let totalWins = (bestTrade ?? 0) * Double(winningTrades)
        return totalWins / totalLosses
    }
}

// MARK: - Stats Period

public enum StatsPeriod: String, Codable, CaseIterable {
    case day = "24h"
    case week = "7d"
    case month = "30d"
    case threeMonths = "90d"
    case year = "1y"
    case allTime = "all"
    
    public var displayName: String {
        switch self {
        case .day: return "24 Hours"
        case .week: return "7 Days"
        case .month: return "30 Days"
        case .threeMonths: return "90 Days"
        case .year: return "1 Year"
        case .allTime: return "All Time"
        }
    }
    
    public var days: Int? {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 90
        case .year: return 365
        case .allTime: return nil
        }
    }
}

// MARK: - User Badge

/// Achievement badges for users
public struct UserBadge: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let iconName: String
    public let tier: BadgeTier
    public let earnedAt: Date
    public let category: BadgeCategory
    
    public init(
        id: String,
        name: String,
        description: String,
        iconName: String,
        tier: BadgeTier,
        earnedAt: Date = Date(),
        category: BadgeCategory
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.tier = tier
        self.earnedAt = earnedAt
        self.category = category
    }
}

public enum BadgeTier: String, Codable, CaseIterable {
    case bronze
    case silver
    case gold
    case platinum
    case diamond
    
    public var color: Color {
        switch self {
        case .bronze: return Color(red: 0.8, green: 0.5, blue: 0.2)
        case .silver: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case .gold: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case .platinum: return Color(red: 0.9, green: 0.9, blue: 0.95)
        case .diamond: return Color(red: 0.7, green: 0.85, blue: 1.0)
        }
    }
}

public enum BadgeCategory: String, Codable, CaseIterable {
    case trading
    case social
    case learning
    case achievement
    case special
}

// MARK: - Social Links

public struct SocialLinks: Codable, Equatable {
    public var twitter: String?
    public var telegram: String?
    public var discord: String?
    public var website: String?
    
    public init(twitter: String? = nil, telegram: String? = nil, discord: String? = nil, website: String? = nil) {
        self.twitter = twitter
        self.telegram = telegram
        self.discord = discord
        self.website = website
    }
}

// MARK: - Shared Bot Configuration

/// A bot configuration shared by a user for others to copy
public struct SharedBotConfig: Codable, Identifiable, Equatable {
    public let id: UUID
    public let creatorId: UUID
    public let creatorUsername: String
    public let botType: SharedBotType
    public var name: String
    public var description: String?
    public let config: [String: String]
    public let tradingPair: String
    public let exchange: String
    public var performanceStats: BotPerformanceStats
    public var copiesCount: Int
    public var likesCount: Int
    public var commentsCount: Int
    public let createdAt: Date
    public var updatedAt: Date
    public var isActive: Bool
    public var tags: [String]
    public var riskLevel: RiskLevel
    
    public init(
        id: UUID = UUID(),
        creatorId: UUID,
        creatorUsername: String,
        botType: SharedBotType,
        name: String,
        description: String? = nil,
        config: [String: String],
        tradingPair: String,
        exchange: String,
        performanceStats: BotPerformanceStats = .empty,
        copiesCount: Int = 0,
        likesCount: Int = 0,
        commentsCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isActive: Bool = true,
        tags: [String] = [],
        riskLevel: RiskLevel = .medium
    ) {
        self.id = id
        self.creatorId = creatorId
        self.creatorUsername = creatorUsername
        self.botType = botType
        self.name = name
        self.description = description
        self.config = config
        self.tradingPair = tradingPair
        self.exchange = exchange
        self.performanceStats = performanceStats
        self.copiesCount = copiesCount
        self.likesCount = likesCount
        self.commentsCount = commentsCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
        self.tags = tags
        self.riskLevel = riskLevel
    }
    
    public static func == (lhs: SharedBotConfig, rhs: SharedBotConfig) -> Bool {
        lhs.id == rhs.id
    }
}

public enum SharedBotType: String, Codable, CaseIterable {
    case dca = "DCA"
    case grid = "Grid"
    case signal = "Signal"
    case derivatives = "Derivatives"
    case predictionMarket = "Prediction"
    
    public var displayName: String {
        switch self {
        case .dca: return "DCA Bot"
        case .grid: return "Grid Bot"
        case .signal: return "Signal Bot"
        case .derivatives: return "Derivatives Bot"
        case .predictionMarket: return "Prediction Bot"
        }
    }
    
    public var icon: String {
        switch self {
        case .dca: return "repeat.circle.fill"
        case .grid: return "square.grid.3x3.fill"
        case .signal: return "bolt.circle.fill"
        case .derivatives: return "chart.line.uptrend.xyaxis.circle.fill"
        case .predictionMarket: return "chart.bar.xaxis.ascending"
        }
    }
    
    public var color: Color {
        switch self {
        case .dca: return .blue
        case .grid: return .purple
        case .signal: return .orange
        case .derivatives: return .red
        case .predictionMarket: return .teal
        }
    }
}

// MARK: - Bot Performance Stats

public struct BotPerformanceStats: Codable, Equatable {
    public var totalPnL: Double
    public var pnlPercent: Double
    public var totalTrades: Int
    public var winRate: Double
    public var avgTradeProfit: Double
    public var maxDrawdown: Double
    public var runningDays: Int
    public var lastTradeAt: Date?
    
    public init(
        totalPnL: Double = 0,
        pnlPercent: Double = 0,
        totalTrades: Int = 0,
        winRate: Double = 0,
        avgTradeProfit: Double = 0,
        maxDrawdown: Double = 0,
        runningDays: Int = 0,
        lastTradeAt: Date? = nil
    ) {
        self.totalPnL = totalPnL
        self.pnlPercent = pnlPercent
        self.totalTrades = totalTrades
        self.winRate = winRate
        self.avgTradeProfit = avgTradeProfit
        self.maxDrawdown = maxDrawdown
        self.runningDays = runningDays
        self.lastTradeAt = lastTradeAt
    }
    
    public static let empty = BotPerformanceStats()
}

// MARK: - Risk Level (reuse from RiskScan if available)

public enum SocialRiskLevel: String, Codable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case veryHigh = "Very High"
    
    public var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        }
    }
}

// MARK: - Follow Relationship

public struct FollowRelation: Codable, Identifiable, Equatable {
    public let id: UUID
    public let followerId: UUID
    public let followingId: UUID
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        followerId: UUID,
        followingId: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.followerId = followerId
        self.followingId = followingId
        self.createdAt = createdAt
    }
}

// MARK: - Leaderboard Entry Trading Mode

/// Trading mode for leaderboard entries (mirrors LeaderboardTradingMode in LeaderboardEngine)
public enum LeaderboardEntryTradingMode: String, Codable, CaseIterable {
    case paper = "Paper"
    case portfolio = "Portfolio"
    
    /// Backward compatibility alias
    public static var live: LeaderboardEntryTradingMode { .portfolio }
    
    public var displayName: String {
        switch self {
        case .paper: return "Paper Trading"
        case .portfolio: return "Portfolio Tracking"
        }
    }
    
    public var badgeText: String {
        switch self {
        case .paper: return "Virtual"
        case .portfolio: return "Verified"
        }
    }
    
    public var color: Color {
        switch self {
        case .paper: return AppTradingMode.paper.color
        case .portfolio: return .green
        }
    }
}

// MARK: - Leaderboard Entry

public struct LeaderboardEntry: Codable, Identifiable, Equatable {
    public let id: UUID
    public let userId: UUID
    public let username: String
    public let displayName: String?
    public let avatarURL: String?
    public let avatarPresetId: String?  // ID of selected preset avatar
    public var rank: Int
    public let score: Double
    public let pnl: Double
    public let pnlPercent: Double
    public let winRate: Double
    public let totalTrades: Int
    public let badges: [UserBadge]
    public let period: StatsPeriod
    public let category: LeaderboardCategory
    public let tradingMode: LeaderboardEntryTradingMode
    public let updatedAt: Date
    
    /// Whether this is a real user (vs demo/mock data)
    /// Used for gradual demo data phase-out as real users join
    public let isRealUser: Bool
    
    // MARK: - Anti-Gaming Fields
    
    /// Whether the user recently reset their paper trading account (14-day cooldown)
    public let isInResetCooldown: Bool
    
    /// Score penalty percentage applied due to resets (0-100)
    public let scorePenaltyPercent: Int
    
    /// Raw score before anti-gaming adjustments (for transparency)
    public let rawScore: Double
    
    public init(
        id: UUID = UUID(),
        userId: UUID,
        username: String,
        displayName: String? = nil,
        avatarURL: String? = nil,
        avatarPresetId: String? = nil,
        rank: Int,
        score: Double,
        pnl: Double,
        pnlPercent: Double,
        winRate: Double,
        totalTrades: Int,
        badges: [UserBadge] = [],
        period: StatsPeriod,
        category: LeaderboardCategory,
        tradingMode: LeaderboardEntryTradingMode = .paper,
        updatedAt: Date = Date(),
        isRealUser: Bool = false,
        isInResetCooldown: Bool = false,
        scorePenaltyPercent: Int = 0,
        rawScore: Double? = nil
    ) {
        self.id = id
        self.userId = userId
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.avatarPresetId = avatarPresetId
        self.rank = rank
        self.score = score
        self.pnl = pnl
        self.pnlPercent = pnlPercent
        self.winRate = winRate
        self.totalTrades = totalTrades
        self.badges = badges
        self.period = period
        self.category = category
        self.tradingMode = tradingMode
        self.updatedAt = updatedAt
        self.isRealUser = isRealUser
        self.isInResetCooldown = isInResetCooldown
        self.scorePenaltyPercent = scorePenaltyPercent
        self.rawScore = rawScore ?? score
    }
    
    public var nameToDisplay: String {
        displayName ?? username
    }
    
    /// Whether this entry has any active anti-gaming penalties
    public var hasPenalty: Bool {
        isInResetCooldown || scorePenaltyPercent > 0
    }
}

public enum LeaderboardCategory: String, Codable, CaseIterable {
    case pnl = "PnL"
    case pnlPercent = "ROI"
    case winRate = "Win Rate"
    case consistency = "Consistency"
    case botPerformance = "Bot Performance"
    case copiedMost = "Most Copied"
    
    public var displayName: String {
        switch self {
        case .pnl: return "Highest PnL"
        case .pnlPercent: return "Best ROI"
        case .winRate: return "Best Win Rate"
        case .consistency: return "Most Consistent"
        case .botPerformance: return "Bot Performance"
        case .copiedMost: return "Most Copied"
        }
    }
    
    public var icon: String {
        switch self {
        case .pnl: return "dollarsign.circle.fill"
        case .pnlPercent: return "percent"
        case .winRate: return "trophy.fill"
        case .consistency: return "chart.line.uptrend.xyaxis"
        case .botPerformance: return "bolt.fill"
        case .copiedMost: return "doc.on.doc.fill"
        }
    }
}

// MARK: - Activity Feed Item

public struct ActivityFeedItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public let userId: UUID
    public let username: String
    public let avatarURL: String?
    public let activityType: ActivityType
    public let title: String
    public let description: String?
    public let relatedBotId: UUID?
    public let relatedBotName: String?
    public let metadata: [String: String]?
    public let timestamp: Date
    
    public init(
        id: UUID = UUID(),
        userId: UUID,
        username: String,
        avatarURL: String? = nil,
        activityType: ActivityType,
        title: String,
        description: String? = nil,
        relatedBotId: UUID? = nil,
        relatedBotName: String? = nil,
        metadata: [String: String]? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.username = username
        self.avatarURL = avatarURL
        self.activityType = activityType
        self.title = title
        self.description = description
        self.relatedBotId = relatedBotId
        self.relatedBotName = relatedBotName
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

public enum ActivityType: String, Codable, CaseIterable {
    case sharedBot
    case copiedBot
    case achievedRank
    case earnedBadge
    case milestoneReached
    case botPerformance
    case newFollower
    
    public var icon: String {
        switch self {
        case .sharedBot: return "square.and.arrow.up.fill"
        case .copiedBot: return "doc.on.doc.fill"
        case .achievedRank: return "trophy.fill"
        case .earnedBadge: return "star.fill"
        case .milestoneReached: return "flag.fill"
        case .botPerformance: return "chart.line.uptrend.xyaxis"
        case .newFollower: return "person.badge.plus"
        }
    }
    
    public var color: Color {
        switch self {
        case .sharedBot: return .blue
        case .copiedBot: return .purple
        case .achievedRank: return .yellow
        case .earnedBadge: return .orange
        case .milestoneReached: return .green
        case .botPerformance: return .cyan
        case .newFollower: return .pink
        }
    }
}

// MARK: - Bot Comment

public struct BotComment: Codable, Identifiable, Equatable {
    public let id: UUID
    public let botId: UUID
    public let userId: UUID
    public let username: String
    public let avatarURL: String?
    public var text: String
    public var likesCount: Int
    public let createdAt: Date
    public var updatedAt: Date
    public let parentId: UUID? // For replies
    public var repliesCount: Int
    
    public init(
        id: UUID = UUID(),
        botId: UUID,
        userId: UUID,
        username: String,
        avatarURL: String? = nil,
        text: String,
        likesCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        parentId: UUID? = nil,
        repliesCount: Int = 0
    ) {
        self.id = id
        self.botId = botId
        self.userId = userId
        self.username = username
        self.avatarURL = avatarURL
        self.text = text
        self.likesCount = likesCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.parentId = parentId
        self.repliesCount = repliesCount
    }
}

// MARK: - Copied Bot Tracking

public struct CopiedBot: Codable, Identifiable, Equatable {
    public let id: UUID
    public let originalBotId: UUID
    public let originalCreatorId: UUID
    public let copierId: UUID
    public let localBotId: UUID // The user's local PaperBot ID
    public let copiedAt: Date
    public var syncEnabled: Bool
    public var lastSyncAt: Date?
    
    public init(
        id: UUID = UUID(),
        originalBotId: UUID,
        originalCreatorId: UUID,
        copierId: UUID,
        localBotId: UUID,
        copiedAt: Date = Date(),
        syncEnabled: Bool = false,
        lastSyncAt: Date? = nil
    ) {
        self.id = id
        self.originalBotId = originalBotId
        self.originalCreatorId = originalCreatorId
        self.copierId = copierId
        self.localBotId = localBotId
        self.copiedAt = copiedAt
        self.syncEnabled = syncEnabled
        self.lastSyncAt = lastSyncAt
    }
}

// MARK: - Like

public struct SocialLike: Codable, Identifiable, Equatable {
    public let id: UUID
    public let userId: UUID
    public let targetType: LikeTargetType
    public let targetId: UUID
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        userId: UUID,
        targetType: LikeTargetType,
        targetId: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.targetType = targetType
        self.targetId = targetId
        self.createdAt = createdAt
    }
}

public enum LikeTargetType: String, Codable {
    case bot
    case comment
}

// MARK: - Predefined Badges

public enum PredefinedBadge {
    public static let firstTrade = UserBadge(
        id: "first_trade",
        name: "First Trade",
        description: "Completed your first trade",
        iconName: "sparkles",
        tier: .bronze,
        category: .trading
    )
    
    public static let profitable10 = UserBadge(
        id: "profitable_10",
        name: "Profit Starter",
        description: "Made $10 in profit",
        iconName: "dollarsign.circle.fill",
        tier: .bronze,
        category: .trading
    )
    
    public static let profitable100 = UserBadge(
        id: "profitable_100",
        name: "Profit Hunter",
        description: "Made $100 in profit",
        iconName: "dollarsign.circle.fill",
        tier: .silver,
        category: .trading
    )
    
    public static let profitable1000 = UserBadge(
        id: "profitable_1000",
        name: "Profit Master",
        description: "Made $1,000 in profit",
        iconName: "dollarsign.circle.fill",
        tier: .gold,
        category: .trading
    )
    
    public static let winStreak5 = UserBadge(
        id: "win_streak_5",
        name: "Hot Streak",
        description: "5 winning trades in a row",
        iconName: "flame.fill",
        tier: .silver,
        category: .trading
    )
    
    public static let botCreator = UserBadge(
        id: "bot_creator",
        name: "Bot Creator",
        description: "Created and shared your first bot",
        iconName: "gearshape.2.fill",
        tier: .bronze,
        category: .social
    )
    
    public static let popular10 = UserBadge(
        id: "popular_10",
        name: "Rising Star",
        description: "Your bot was copied 10 times",
        iconName: "star.fill",
        tier: .silver,
        category: .social
    )
    
    public static let popular100 = UserBadge(
        id: "popular_100",
        name: "Trending",
        description: "Your bot was copied 100 times",
        iconName: "star.fill",
        tier: .gold,
        category: .social
    )
    
    public static let topTrader = UserBadge(
        id: "top_trader",
        name: "Top Trader",
        description: "Reached top 10 on leaderboard",
        iconName: "trophy.fill",
        tier: .platinum,
        category: .achievement
    )
    
    public static let earlyAdopter = UserBadge(
        id: "early_adopter",
        name: "Early Adopter",
        description: "Joined during launch period",
        iconName: "clock.badge.checkmark.fill",
        tier: .gold,
        category: .special
    )
}
