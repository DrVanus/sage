//
//  LiveBotManager.swift
//  CryptoSage
//
//  Centralized manager for live 3Commas trading bots.
//  Allows users to view, start, stop, and manage their real trading bots
//  through the 3Commas API.
//

import SwiftUI
import Combine

// MARK: - Live Bot Manager

@MainActor
public final class LiveBotManager: ObservableObject {
    public static let shared = LiveBotManager()
    
    // MARK: - Published State
    
    /// List of all live bots from 3Commas (real bots)
    @Published public var realBots: [ThreeCommasBot] = []
    
    /// Demo live bots shown when demo mode is active
    @Published public var demoBots: [ThreeCommasBot] = []
    
    /// Returns demo bots when in demo mode, otherwise real bots
    public var bots: [ThreeCommasBot] {
        DemoModeManager.isEnabled ? demoBots : realBots
    }
    
    /// Loading state
    @Published public var isLoading: Bool = false
    
    /// Last error message
    @Published public var errorMessage: String?
    
    /// Last successful fetch time
    @Published public var lastFetchTime: Date?
    
    /// IDs of bots currently being toggled (for UI feedback)
    @Published public var togglingBotIds: Set<Int> = []
    
    // MARK: - Private Properties
    
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    /// Auto-refresh interval (in seconds)
    private let refreshInterval: TimeInterval = 60
    
    // MARK: - Initialization
    
    private init() {
        // Seed demo bots immediately if demo mode is already enabled
        if DemoModeManager.isEnabled {
            seedDemoLiveBots()
        }
        
        // Listen for 3Commas configuration changes
        NotificationCenter.default.publisher(for: .threeCommasConfigurationChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshBots()
                }
            }
            .store(in: &cancellables)
        
        // Observe demo mode changes to seed/clear demo bots
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if DemoModeManager.isEnabled {
                    self.seedDemoLiveBots()
                } else {
                    self.clearDemoLiveBots()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Demo Mode
    
    /// Seeds sample demo live bots for display when demo mode is active
    public func seedDemoLiveBots() {
        guard demoBots.isEmpty else { return }
        
        let now = Date()
        
        // Demo DCA Bot - BTC
        let dcaBot = ThreeCommasBot(
            id: 99001,
            accountId: 1001,
            accountName: "Binance Demo",
            name: "BTC DCA Pro",
            isEnabled: true,
            pairs: ["USDT_BTC"],
            strategy: .simple, // DCA Bot
            maxActiveDeals: 3,
            activeDealsCount: 2,
            createdAt: now.addingTimeInterval(-86400 * 30), // 30 days ago
            updatedAt: now.addingTimeInterval(-3600),
            baseOrderVolume: 100,
            safetyOrderVolume: 50,
            takeProfit: 2.5,
            martingaleVolumeCoefficient: 1.5,
            martingaleStepCoefficient: 1.2,
            maxSafetyOrders: 5,
            activeDealsUsdtProfit: 125.50,
            closedDealsUsdtProfit: 892.30,
            closedDealsCount: 45,
            dealsStartedTodayCount: 2,
            finishedDealsCount: 45,
            finishedDealsProfitUsd: 892.30
        )
        
        // Demo Grid Bot - ETH
        let gridBot = ThreeCommasBot(
            id: 99002,
            accountId: 1002,
            accountName: "Coinbase Demo",
            name: "ETH Grid Master",
            isEnabled: true,
            pairs: ["USD_ETH"],
            strategy: .gordon, // Grid Bot
            maxActiveDeals: 5,
            activeDealsCount: 3,
            createdAt: now.addingTimeInterval(-86400 * 14), // 14 days ago
            updatedAt: now.addingTimeInterval(-1800),
            baseOrderVolume: 200,
            safetyOrderVolume: 100,
            takeProfit: 1.8,
            martingaleVolumeCoefficient: 1.3,
            martingaleStepCoefficient: 1.1,
            maxSafetyOrders: 8,
            activeDealsUsdtProfit: 78.25,
            closedDealsUsdtProfit: 456.80,
            closedDealsCount: 28,
            dealsStartedTodayCount: 1,
            finishedDealsCount: 28,
            finishedDealsProfitUsd: 456.80
        )
        
        // Demo Composite Bot - SOL (stopped)
        let compositeBot = ThreeCommasBot(
            id: 99003,
            accountId: 1001,
            accountName: "Binance Demo",
            name: "SOL Scalper",
            isEnabled: false,
            pairs: ["USDT_SOL"],
            strategy: .composite, // Multi-pair Bot
            maxActiveDeals: 2,
            activeDealsCount: 0,
            createdAt: now.addingTimeInterval(-86400 * 7), // 7 days ago
            updatedAt: now.addingTimeInterval(-86400), // 1 day ago
            baseOrderVolume: 75,
            safetyOrderVolume: 35,
            takeProfit: 3.0,
            martingaleVolumeCoefficient: 1.4,
            martingaleStepCoefficient: 1.15,
            maxSafetyOrders: 4,
            activeDealsUsdtProfit: 0,
            closedDealsUsdtProfit: 234.15,
            closedDealsCount: 18,
            dealsStartedTodayCount: 0,
            finishedDealsCount: 18,
            finishedDealsProfitUsd: 234.15
        )
        
        demoBots = [dcaBot, gridBot, compositeBot]
        objectWillChange.send()
    }
    
    /// Clears all demo live bots
    public func clearDemoLiveBots() {
        demoBots.removeAll()
        objectWillChange.send()
    }
    
    // MARK: - Public API
    
    /// Check if 3Commas is configured
    public var isConfigured: Bool {
        ThreeCommasAPI.shared.isConfigured
    }
    
    /// Total number of bots
    public var totalBotCount: Int {
        bots.count
    }
    
    /// Number of enabled (running) bots
    public var enabledBotCount: Int {
        bots.filter { $0.isEnabled }.count
    }
    
    /// Number of disabled (stopped) bots
    public var disabledBotCount: Int {
        bots.filter { !$0.isEnabled }.count
    }
    
    /// Total profit across all bots (USD)
    public var totalProfitUsd: Double {
        bots.reduce(0) { $0 + $1.totalProfitUsd }
    }
    
    /// Filter bots by status
    public func bots(status: ThreeCommasBotStatus) -> [ThreeCommasBot] {
        switch status {
        case .enabled:
            return bots.filter { $0.isEnabled }
        case .disabled:
            return bots.filter { !$0.isEnabled }
        default:
            return bots
        }
    }
    
    // MARK: - Fetching Bots
    
    /// Fetch all bots from 3Commas API
    public func refreshBots() async {
        guard isConfigured else {
            errorMessage = "3Commas is not configured. Please add your API credentials in settings."
            realBots = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let fetchedBots = try await ThreeCommasAPI.shared.listBots()
            realBots = fetchedBots.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            lastFetchTime = Date()
            errorMessage = nil
        } catch let error as ThreeCommasError {
            errorMessage = error.localizedDescription
            #if DEBUG
            print("[LiveBotManager] Failed to fetch bots: \(error.localizedDescription)")
            #endif
        } catch {
            errorMessage = "Failed to fetch bots: \(error.localizedDescription)"
            #if DEBUG
            print("[LiveBotManager] Unexpected error: \(error)")
            #endif
        }
        
        isLoading = false
    }
    
    /// Fetch a specific bot by ID
    public func fetchBot(id: Int) async -> ThreeCommasBot? {
        guard isConfigured else { return nil }
        
        do {
            let bot = try await ThreeCommasAPI.shared.getBot(botId: id)
            
            // Update in local cache
            if let index = realBots.firstIndex(where: { $0.id == id }) {
                realBots[index] = bot
            }
            
            return bot
        } catch {
            #if DEBUG
            print("[LiveBotManager] Failed to fetch bot \(id): \(error)")
            #endif
            return nil
        }
    }
    
    // MARK: - Bot Control
    
    /// Enable (start) a bot
    public func enableBot(id: Int) async {
        // SAFETY: Block live bot operations when trading is disabled at app config level
        guard AppConfig.liveTradingEnabled else {
            errorMessage = AppConfig.liveTradingDisabledMessage
            #if DEBUG
            print("[LiveBotManager] Live trading disabled - cannot enable bot \(id)")
            #endif
            return
        }
        
        guard isConfigured else { return }
        
        togglingBotIds.insert(id)
        
        do {
            let updatedBot = try await ThreeCommasAPI.shared.enableBot(botId: id)
            
            // Update in local cache
            if let index = realBots.firstIndex(where: { $0.id == id }) {
                realBots[index] = updatedBot
            }
            
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            
            #if DEBUG
            print("[LiveBotManager] Bot \(id) enabled successfully")
            #endif
        } catch let error as ThreeCommasError {
            errorMessage = error.localizedDescription
            #if DEBUG
            print("[LiveBotManager] Failed to enable bot \(id): \(error.localizedDescription)")
            #endif
        } catch {
            errorMessage = "Failed to enable bot: \(error.localizedDescription)"
            #if DEBUG
            print("[LiveBotManager] Unexpected error enabling bot \(id): \(error)")
            #endif
        }
        
        togglingBotIds.remove(id)
    }
    
    /// Disable (stop) a bot
    /// NOTE: Disabling bots is ALWAYS allowed even when live trading is off.
    /// This is a safety feature - you should always be able to STOP a running bot
    /// to prevent losses, regardless of your trading mode settings.
    public func disableBot(id: Int) async {
        // No live trading check here - stopping a bot is always allowed for safety
        guard isConfigured else { return }
        
        togglingBotIds.insert(id)
        
        do {
            let updatedBot = try await ThreeCommasAPI.shared.disableBot(botId: id)
            
            // Update in local cache
            if let index = realBots.firstIndex(where: { $0.id == id }) {
                realBots[index] = updatedBot
            }
            
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            
            #if DEBUG
            print("[LiveBotManager] Bot \(id) disabled successfully")
            #endif
        } catch let error as ThreeCommasError {
            errorMessage = error.localizedDescription
            #if DEBUG
            print("[LiveBotManager] Failed to disable bot \(id): \(error.localizedDescription)")
            #endif
        } catch {
            errorMessage = "Failed to disable bot: \(error.localizedDescription)"
            #if DEBUG
            print("[LiveBotManager] Unexpected error disabling bot \(id): \(error)")
            #endif
        }
        
        togglingBotIds.remove(id)
    }
    
    /// Toggle bot enabled/disabled state
    /// NOTE: Disabling is always allowed (safety), but enabling requires live trading to be on
    public func toggleBot(id: Int) async {
        guard let bot = bots.first(where: { $0.id == id }) else { return }
        
        if bot.isEnabled {
            // Disabling is always allowed for safety
            await disableBot(id: id)
        } else {
            // Enabling requires live trading to be on
            guard AppConfig.liveTradingEnabled else {
                errorMessage = "Enable Developer Mode with Live Trading to start bots"
                #if DEBUG
                print("[LiveBotManager] Live trading disabled - cannot enable bot \(id)")
                #endif
                return
            }
            await enableBot(id: id)
        }
    }
    
    /// Check if a bot is currently being toggled
    public func isToggling(id: Int) -> Bool {
        togglingBotIds.contains(id)
    }
    
    // MARK: - Auto-Refresh
    
    /// Start auto-refreshing bots
    public func startAutoRefresh() {
        stopAutoRefresh()
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshBots()
            }
        }
        
        // Also fetch immediately
        Task {
            await refreshBots()
        }
    }
    
    /// Stop auto-refreshing bots
    public func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - Helpers
    
    /// Clear all cached data
    public func clearCache() {
        realBots = []
        demoBots = []
        lastFetchTime = nil
        errorMessage = nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let threeCommasConfigurationChanged = Notification.Name("threeCommasConfigurationChanged")
}
