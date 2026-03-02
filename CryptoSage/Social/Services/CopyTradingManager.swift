//
//  CopyTradingManager.swift
//  CryptoSage
//
//  Manager for copy trading functionality, allowing users to copy
//  and sync bot configurations from other traders.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Copy Trading Mode

/// The trading mode for copied bots
public enum BotCopyMode: Equatable {
    /// Paper trading mode - uses virtual funds
    case paper
    /// Live trading mode via 3Commas - uses real funds
    case live(accountId: Int)
    
    public var isPaper: Bool {
        if case .paper = self { return true }
        return false
    }
    
    public var isLive: Bool {
        if case .live = self { return true }
        return false
    }
}

/// Result of copying a bot
public struct BotCopyResult {
    public let paperBotId: UUID?
    public let liveBotId: Int?
    public let mode: BotCopyMode
    public let success: Bool
    
    /// Returns the appropriate bot ID based on mode
    public var botId: UUID? {
        paperBotId
    }
}

// MARK: - Copy Trading Manager

@MainActor
public final class CopyTradingManager: ObservableObject {
    public static let shared = CopyTradingManager()
    
    // MARK: - Published Properties
    
    @Published public private(set) var copiedBots: [CopiedBotInfo] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: Error?
    @Published public private(set) var syncStatus: [UUID: SyncStatus] = [:]
    
    // MARK: - Private Properties
    
    private let socialService = SocialService.shared
    private let paperBotManager = PaperBotManager.shared
    private var cancellables = Set<AnyCancellable>()
    private let storageKey = "copied_bots_info"
    
    // MARK: - Initialization
    
    private init() {
        loadCopiedBots()
        setupSubscriptions()
    }
    
    // MARK: - Public Methods
    
    /// Copy a shared bot configuration and create a local paper bot (default mode)
    /// - Parameters:
    ///   - sharedBot: The shared bot configuration to copy
    ///   - customName: Optional custom name for the copied bot
    /// - Returns: The created paper bot
    public func copyBot(_ sharedBot: SharedBotConfig, customName: String? = nil) async throws -> PaperBot {
        let result = try await copyBot(sharedBot, customName: customName, mode: .paper)
        guard let paperBotId = result.paperBotId,
              let bot = paperBotManager.getBot(id: paperBotId) else {
            throw CopyTradingError.botNotFound
        }
        return bot
    }
    
    /// Copy a shared bot configuration with explicit trading mode
    /// - Parameters:
    ///   - sharedBot: The shared bot configuration to copy
    ///   - customName: Optional custom name for the copied bot
    ///   - mode: The trading mode (paper or live)
    /// - Returns: Result containing the created bot ID(s)
    public func copyBot(_ sharedBot: SharedBotConfig, customName: String? = nil, mode: BotCopyMode) async throws -> BotCopyResult {
        isLoading = true
        defer { isLoading = false }
        
        // Check subscription access - Copy Trading requires Premium tier
        guard SubscriptionManager.shared.hasAccess(to: .copyTrading) else {
            // Track the feature attempt for paywall analytics
            await MainActor.run {
                PaywallManager.shared.trackFeatureAttempt(.copyTrading)
            }
            throw CopyTradingError.subscriptionRequired
        }
        
        // Validate
        guard socialService.currentProfile != nil else {
            throw CopyTradingError.notAuthenticated
        }
        
        // Check if already copied
        if copiedBots.contains(where: { $0.originalBotId == sharedBot.id }) {
            throw CopyTradingError.alreadyCopied
        }
        
        let name = customName ?? "Copy: \(sharedBot.name)"
        var paperBotId: UUID? = nil
        let liveBotId: Int? = nil
        
        switch mode {
        case .paper:
            // Create paper bot
            let bot = try await createPaperBot(from: sharedBot, name: name)
            paperBotId = bot.id
            
            // Track the copy
            let copiedBotInfo = CopiedBotInfo(
                id: UUID(),
                originalBotId: sharedBot.id,
                originalBotName: sharedBot.name,
                originalCreatorId: sharedBot.creatorId,
                originalCreatorUsername: sharedBot.creatorUsername,
                localBotId: bot.id,
                copiedAt: Date(),
                syncEnabled: false,
                lastSyncAt: nil,
                originalConfig: sharedBot.config,
                originalPerformance: sharedBot.performanceStats,
                tradingMode: .paper
            )
            
            copiedBots.append(copiedBotInfo)
            syncStatus[bot.id] = .idle
            
        case .live(let accountId):
            // Live mode requires 3Commas bridge (implemented in SocialTo3CommasBridge)
            // For now, create paper bot as fallback with live mode tracking
            let bot = try await createPaperBot(from: sharedBot, name: name)
            paperBotId = bot.id
            
            // Track with live mode intent
            let copiedBotInfo = CopiedBotInfo(
                id: UUID(),
                originalBotId: sharedBot.id,
                originalBotName: sharedBot.name,
                originalCreatorId: sharedBot.creatorId,
                originalCreatorUsername: sharedBot.creatorUsername,
                localBotId: bot.id,
                copiedAt: Date(),
                syncEnabled: false,
                lastSyncAt: nil,
                originalConfig: sharedBot.config,
                originalPerformance: sharedBot.performanceStats,
                tradingMode: .live(accountId: accountId)
            )
            
            copiedBots.append(copiedBotInfo)
            syncStatus[bot.id] = .idle
            
            // TODO: When SocialTo3CommasBridge is ready, create actual 3Commas bot:
            // liveBotId = try await SocialTo3CommasBridge.createLiveBot(from: sharedBot, accountId: accountId)
        }
        
        saveCopiedBots()
        
        // Record the copy in social service
        _ = try await socialService.copyBot(sharedBot)
        
        return BotCopyResult(
            paperBotId: paperBotId,
            liveBotId: liveBotId,
            mode: mode,
            success: true
        )
    }
    
    /// Create a paper bot from a shared configuration
    private func createPaperBot(from sharedBot: SharedBotConfig, name: String) async throws -> PaperBot {
        // Convert SharedBotType to PaperBotType
        let botType: PaperBotType
        switch sharedBot.botType {
        case .dca: botType = .dca
        case .grid: botType = .grid
        case .signal: botType = .signal
        case .derivatives: botType = .derivatives
        case .predictionMarket: botType = .predictionMarket
        }
        
        // Create the paper bot with config dictionary
        let bot = paperBotManager.createBot(
            name: name,
            type: botType,
            exchange: sharedBot.exchange,
            tradingPair: sharedBot.tradingPair,
            config: sharedBot.config
        )
        
        return bot
    }
    
    /// Remove a copied bot
    public func removeCopiedBot(localBotId: UUID) async throws {
        guard let index = copiedBots.firstIndex(where: { $0.localBotId == localBotId }) else {
            throw CopyTradingError.botNotFound
        }
        
        // Remove from paper bots
        paperBotManager.deleteBot(id: localBotId)
        
        // Remove from tracking
        copiedBots.remove(at: index)
        syncStatus.removeValue(forKey: localBotId)
        saveCopiedBots()
    }
    
    /// Enable sync for a copied bot
    public func enableSync(localBotId: UUID) {
        if let index = copiedBots.firstIndex(where: { $0.localBotId == localBotId }) {
            copiedBots[index].syncEnabled = true
            saveCopiedBots()
        }
    }
    
    /// Disable sync for a copied bot
    public func disableSync(localBotId: UUID) {
        if let index = copiedBots.firstIndex(where: { $0.localBotId == localBotId }) {
            copiedBots[index].syncEnabled = false
            saveCopiedBots()
        }
    }
    
    /// Sync a copied bot with the original
    public func syncBot(localBotId: UUID) async throws {
        guard let copiedInfo = copiedBots.first(where: { $0.localBotId == localBotId }) else {
            throw CopyTradingError.botNotFound
        }
        
        guard copiedInfo.syncEnabled else {
            throw CopyTradingError.syncDisabled
        }
        
        syncStatus[localBotId] = .syncing
        
        do {
            // In a real app, this would fetch the latest config from the server
            // For now, we'll simulate the sync
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
            
            // Update last sync time
            if let index = copiedBots.firstIndex(where: { $0.localBotId == localBotId }) {
                copiedBots[index].lastSyncAt = Date()
                saveCopiedBots()
            }
            
            syncStatus[localBotId] = .synced
        } catch {
            syncStatus[localBotId] = .error(error.localizedDescription)
            throw error
        }
    }
    
    /// Sync all bots with sync enabled
    public func syncAllBots() async {
        let botsToSync = copiedBots.filter { $0.syncEnabled }
        
        for bot in botsToSync {
            do {
                try await syncBot(localBotId: bot.localBotId)
            } catch {
                #if DEBUG
                print("Failed to sync bot \(bot.localBotId): \(error)")
                #endif
            }
        }
    }
    
    /// Check if a shared bot has been copied
    public func isCopied(sharedBotId: UUID) -> Bool {
        copiedBots.contains { $0.originalBotId == sharedBotId }
    }
    
    /// Get copied bot info for a local bot
    public func getCopiedBotInfo(localBotId: UUID) -> CopiedBotInfo? {
        copiedBots.first { $0.localBotId == localBotId }
    }
    
    /// Get all bots copied from a specific creator
    public func getBotsFromCreator(creatorId: UUID) -> [CopiedBotInfo] {
        copiedBots.filter { $0.originalCreatorId == creatorId }
    }
    
    /// Update local bot config to match original
    public func applyOriginalConfig(localBotId: UUID) async throws {
        guard let copiedInfo = copiedBots.first(where: { $0.localBotId == localBotId }) else {
            throw CopyTradingError.botNotFound
        }
        
        guard var localBot = paperBotManager.paperBots.first(where: { $0.id == localBotId }) else {
            throw CopyTradingError.botNotFound
        }
        
        // Apply the original config dictionary
        localBot.config = copiedInfo.originalConfig
        
        paperBotManager.updateBot(localBot)
    }
    
    // MARK: - Private Methods
    
    private func setupSubscriptions() {
        // Auto-sync every hour for enabled bots
        Timer.publish(every: 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.syncAllBots()
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadCopiedBots() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let bots = try? JSONDecoder().decode([CopiedBotInfo].self, from: data) else {
            return
        }
        copiedBots = bots
        
        // Initialize sync status
        for bot in bots {
            syncStatus[bot.localBotId] = .idle
        }
    }
    
    private func saveCopiedBots() {
        guard let data = try? JSONEncoder().encode(copiedBots) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - Copied Bot Info

/// Detailed information about a copied bot
public struct CopiedBotInfo: Codable, Identifiable, Equatable {
    public let id: UUID
    public let originalBotId: UUID
    public let originalBotName: String
    public let originalCreatorId: UUID
    public let originalCreatorUsername: String
    public let localBotId: UUID
    public let copiedAt: Date
    public var syncEnabled: Bool
    public var lastSyncAt: Date?
    public let originalConfig: [String: String]
    public let originalPerformance: BotPerformanceStats
    public var tradingMode: StoredBotCopyMode
    
    public init(
        id: UUID = UUID(),
        originalBotId: UUID,
        originalBotName: String,
        originalCreatorId: UUID,
        originalCreatorUsername: String,
        localBotId: UUID,
        copiedAt: Date = Date(),
        syncEnabled: Bool = false,
        lastSyncAt: Date? = nil,
        originalConfig: [String: String],
        originalPerformance: BotPerformanceStats,
        tradingMode: StoredBotCopyMode = .paper
    ) {
        self.id = id
        self.originalBotId = originalBotId
        self.originalBotName = originalBotName
        self.originalCreatorId = originalCreatorId
        self.originalCreatorUsername = originalCreatorUsername
        self.localBotId = localBotId
        self.copiedAt = copiedAt
        self.syncEnabled = syncEnabled
        self.lastSyncAt = lastSyncAt
        self.originalConfig = originalConfig
        self.originalPerformance = originalPerformance
        self.tradingMode = tradingMode
    }
    
    public var daysSinceCopy: Int {
        Calendar.current.dateComponents([.day], from: copiedAt, to: Date()).day ?? 0
    }
    
    public var timeSinceLastSync: String? {
        guard let lastSync = lastSyncAt else { return nil }
        let interval = Date().timeIntervalSince(lastSync)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
    }
    
    public var isPaperMode: Bool {
        tradingMode == .paper
    }
    
    public var isLiveMode: Bool {
        if case .live = tradingMode { return true }
        return false
    }
}

/// Codable version of BotCopyMode for storage
public enum StoredBotCopyMode: Codable, Equatable {
    case paper
    case live(accountId: Int)
    
    public init(from mode: BotCopyMode) {
        switch mode {
        case .paper:
            self = .paper
        case .live(let accountId):
            self = .live(accountId: accountId)
        }
    }
    
    public var toBotCopyMode: BotCopyMode {
        switch self {
        case .paper:
            return .paper
        case .live(let accountId):
            return .live(accountId: accountId)
        }
    }
}

// MARK: - Sync Status

public enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced
    case error(String)
    
    public var displayText: String {
        switch self {
        case .idle: return "Not synced"
        case .syncing: return "Syncing..."
        case .synced: return "Synced"
        case .error(let msg): return "Error: \(msg)"
        }
    }
    
    public var color: Color {
        switch self {
        case .idle: return .gray
        case .syncing: return .blue
        case .synced: return .green
        case .error: return .red
        }
    }
}

// MARK: - Copy Trading Errors

public enum CopyTradingError: LocalizedError, Equatable {
    case notAuthenticated
    case botNotFound
    case alreadyCopied
    case syncDisabled
    case syncFailed(String)
    case invalidConfig
    case liveModeNotConfigured
    case threeCommasError(String)
    case subscriptionRequired
    
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please create a profile to copy bots"
        case .botNotFound:
            return "Bot not found"
        case .alreadyCopied:
            return "You have already copied this bot"
        case .syncDisabled:
            return "Sync is disabled for this bot"
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        case .invalidConfig:
            return "Invalid bot configuration"
        case .liveModeNotConfigured:
            return "Live trading requires 3Commas to be configured. Please add your API keys in Settings."
        case .threeCommasError(let message):
            return "3Commas error: \(message)"
        case .subscriptionRequired:
            return "Copy Trading requires a Premium subscription. Upgrade to unlock this feature!"
        }
    }
    
    /// Whether this error should trigger the paywall UI
    public var shouldShowPaywall: Bool {
        self == .subscriptionRequired
    }
}

// MARK: - Copy Trading Statistics

public extension CopyTradingManager {
    /// Total number of copied bots
    var totalCopiedBots: Int {
        copiedBots.count
    }
    
    /// Number of bots with sync enabled
    var syncEnabledCount: Int {
        copiedBots.filter { $0.syncEnabled }.count
    }
    
    /// Unique creators followed via copy trading
    var uniqueCreatorsCount: Int {
        Set(copiedBots.map { $0.originalCreatorId }).count
    }
    
    /// Most copied creator username
    var topCopiedCreator: String? {
        let grouped = Dictionary(grouping: copiedBots) { $0.originalCreatorUsername }
        return grouped.max { $0.value.count < $1.value.count }?.key
    }
}
