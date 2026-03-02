//
//  WhaleTrackingService.swift
//  CryptoSage
//
//  Service for fetching and monitoring whale transactions.
//

import Foundation
import Combine
import UIKit

/// Service for tracking large cryptocurrency transactions (whale movements)
@MainActor
public final class WhaleTrackingService: ObservableObject {
    public static let shared = WhaleTrackingService()
    
    // MARK: - Published Properties
    
    @Published public private(set) var recentTransactions: [WhaleTransaction] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var statistics: WhaleStatistics?
    @Published public private(set) var dataSourceStatus: DataSourceStatus = .idle
    @Published public private(set) var volumeHistory: [VolumeDataPoint] = []
    @Published public private(set) var smartMoneySignals: [SmartMoneySignal] = []
    @Published public private(set) var smartMoneyIndex: SmartMoneyIndex?
    @Published public private(set) var newTransactionArrived: Bool = false
    @Published public private(set) var isUsingCachedData: Bool = false
    @Published public private(set) var isDataStale: Bool = false
    @Published public private(set) var lastDataUpdatedAt: Date?
    @Published public private(set) var activeDataProviders: [String] = []
    @Published public var watchedWallets: [WatchedWallet] = []
    @Published public var config: WhaleAlertConfig = .defaultConfig
    
    // Track previous transaction IDs for detecting new arrivals
    private var previousTransactionIds: Set<String> = []
    
    // LOG SPAM FIX: Only log Etherscan V1 deprecation warning once per session
    private static var didLogEtherscanV1Deprecation: Bool = false
    private static var lastEtherscanErrorLogAt: Date? = nil
    private static let etherscanErrorLogThrottleInterval: TimeInterval = 5 * 60 // 5 minutes
    // FIX v23: Track whether coordinator block has been logged this session
    private static var hasLoggedCoordinatorBlock: Bool = false
    // Keep verbose timestamp/hour-bucket debug off unless actively investigating whale parsing.
    private static let verboseTimestampDebug: Bool = false
    
    // MARK: - Volume History Model
    
    public struct VolumeDataPoint: Identifiable, Codable {
        public let id: UUID
        public let date: Date
        public let volumeUSD: Double
        public let transactionCount: Int
        public let exchangeInflow: Double
        public let exchangeOutflow: Double
        
        public init(date: Date, volumeUSD: Double, transactionCount: Int, exchangeInflow: Double = 0, exchangeOutflow: Double = 0) {
            self.id = UUID()
            self.date = date
            self.volumeUSD = volumeUSD
            self.transactionCount = transactionCount
            self.exchangeInflow = exchangeInflow
            self.exchangeOutflow = exchangeOutflow
        }
        
        public var netFlow: Double {
            exchangeInflow - exchangeOutflow
        }
    }
    
    // MARK: - Data Source Status
    
    public enum DataSourceStatus: Equatable {
        case idle
        case fetching
        case success(source: String)
        case usingFallback
        case error(String)
    }
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private let cacheKey = "cachedWhaleTransactions"
    private let watchedWalletsKey = "watchedWallets"
    private let configKey = "whaleAlertConfig"
    
    // SECURITY FIX: API Keys stored in Keychain instead of UserDefaults
    private static let keychainService = "CryptoSage.WhaleTracking"
    private static let whaleAlertKeyAccount = "whale_alert_api_key"
    private static let arkhamKeyAccount = "arkham_api_key"
    
    private var whaleAlertAPIKey: String? {
        try? KeychainHelper.shared.read(service: Self.keychainService, account: Self.whaleAlertKeyAccount)
    }
    
    private var arkhamAPIKey: String? {
        try? KeychainHelper.shared.read(service: Self.keychainService, account: Self.arkhamKeyAccount)
    }
    
    // Expanded whale addresses for Ethereum (100+ addresses)
    private let ethereumWhaleAddresses = [
        // Binance
        "0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8",
        "0xf977814e90da44bfa03b6295a0616a897441acec",
        "0x28C6c06298d514Db089934071355E5743bf21d60",
        "0x21a31Ee1afC51d94C2eFcCAa2092aD1028285549",
        "0x3f5CE5FBFe3E9af3971dD833D26BA9b5C936f0bE",
        "0xdfd5293d8e347dfe59e90efd55b2956a1343963d",
        // Coinbase
        "0xDFd5293D8e347dFe59E90eFd55b2956a1343963d",
        "0x503828976D22510aad0201ac7EC88293211D23Da",
        "0x71660c4005BA85c37ccec55d0C4493E66Fe775d3",
        "0xa9d1e08c7793af67e9d92fe308d5697fb81d3e43",
        "0x9696f59e4d72e237be84ffd425dcad154bf96976",
        // OKX
        "0x66f820a414680B5bcda5eECA5dea238543F42054",
        "0x6cc5f688a315f3dc28a7781717a9a798a59fda7b",
        "0x98ec059dc3adfbdd63429454aeb0c990fba4a128",
        // Kraken
        "0x2910543Af39abA0Cd09dBb2D50200b3E800A63D2",
        "0x267be1c1d684f78cb4f6a176c4911b741e4ffdc0",
        // Bitfinex
        "0x876EabF441B2EE5B5b0554Fd502a8E0600950cFa",
        "0x77134cbc06cb00b66f4c7e623d5fdbf6777635ec",
        // Gemini
        "0xd24400ae8bfebb18ca49be86258a3c749cf46853",
        "0x6fc82a5fe25a5cdb58bc74600a40a69c065263f8",
        // Crypto.com
        "0x6262998ced04146fa42253a5c0af90ca02dfd2a3",
        "0x46340b20830761efd32832a74d7169b29feb9758",
        // KuCoin
        "0x2b5634c42055806a59e9107ed44d43c426e58258",
        "0x689c56aef474df92d44a1b70850f808488f9769c",
        // Huobi
        "0x46705dfff24256421a05d056c29e81bdc09723b8",
        "0xab5c66752a9e8167967685f1450532fb96d5d24f",
        // Gate.io
        "0xd793281182a0e3e023116f5a0d46e4c2a2d1dedc",
        // Bybit
        "0xf89d7b9c864f589bbf53a82105107622b35eaa40",
        // DEX Routers & Bridges
        "0x7a250d5630b4cf539739df2c5dacb4c659f2488d", // Uniswap V2 Router
        "0xe592427a0aece92de3edee1f18e0157c05861564", // Uniswap V3 Router
        "0xd9e1ce17f2641f24ae83637ab66a2cca9c378b9f", // SushiSwap Router
        "0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b", // Compound
        "0x7d2768de32b0b80b7a3454c06bdac94a69ddc7a9", // Aave V2
        // Treasury Wallets
        "0x40ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf", // Polygon Bridge
        "0x8eb8a3b98659cce290402893d0123abb75e3ab28", // Avalanche Bridge
    ]
    
    // Bitcoin whale addresses
    private let bitcoinWhaleAddresses = [
        // Binance
        "34xp4vRoCGJym3xR7yCVPFHoCNxv4Twseo",
        "bc1qgdjqv0av3q56jvd82tkdjpy7gdp9ut8tlqmgrpmv24sq90ecnvqqjwvw97",
        // Bitfinex
        "bc1qgxj7wur8rphqkqt2z2hxs8gqvnz7x2jxs8a6e5",
        // Coinbase
        "3Nxwenay9Z8Lc9JBiywExpnEFiLp6Afp8v",
        // Kraken
        "bc1qx4rz3kpfp4ahzqqmgkqw5k3nqy8qxcjvqg5kxv",
        // OKX
        "bc1qjasf9z3h7w3jspkhtgatgpyvvzgpa2wwd2lr0eh5tx44reyn2k7sfc27a4",
    ]
    
    // Solana whale addresses - expanded for better coverage
    private let solanaWhaleAddresses = [
        "GaBxu5TxgA9V4CgKeLHvKgGzYhYu5EATN7hjHDapjMNj", // Binance
        "5tzFkiKscXHK5ZXCGbXZxdw7gTjjD1mBwuoFbhUvuAi9", // FTX (historical)
        "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM", // Alameda
        "5Q544fKrFoe6tsEbD7S8EmxGTJYAKtTVhAW5Q5pge4j1", // Raydium
        "H8sMJSCQxfKiFTCfDR3DUMLPwcRbM61LGFJ8N4dK3WjS", // Coinbase
        "2AQdpHJ2JpcEgPiATUXjQxA8QmafFegfQwSLWSprPicm", // OKX
        "7dVexiqgZSXBNnz5MrXJghC8Yvv3ZJqLZpHbSNPYTnKx", // Kraken
        "9n4nbM75f5Ui33ZbPYXn59EwSgE8CGsHtAeTH5YFeJ9E", // Binance Hot Wallet
    ]
    
    // Delegate for alert notifications
    public weak var alertDelegate: WhaleAlertDelegate?
    
    // MARK: - Initialization
    
    private init() {
        // PERFORMANCE FIX v18: Defer heavy cache loading to after first frame renders
        // Loading 56+ transactions from UserDefaults + calculateStatistics() was blocking app launch.
        // The whale section is far down the home scroll - user won't see it for several seconds.
        loadConfig()
        
        // Connect to NotificationsManager as alert delegate
        alertDelegate = NotificationsManager.shared
        
        // Defer cache loading to background - whale data isn't visible on first screen
        Task { @MainActor in
            // Small delay to let the critical startup path complete first
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            self.loadCachedData() // loadCachedData already calls calculateStatistics() internally
            self.loadWatchedWallets()
            // FIX v23: Removed redundant calculateStatistics() call.
            // loadCachedData() already calls calculateStatistics() at line 1980,
            // so calling it again here produced duplicate TIMESTAMP DEBUG logs.
        }
    }
    
    // MARK: - Public Methods
    
    /// Start automatic refresh of whale transactions
    /// Fetches live blockchain data from multiple APIs
    public func startMonitoring(interval: TimeInterval = 90) {
        // Tab/visibility gating: do not start heavy whale polling unless user is on Home.
        guard AppState.shared.selectedTab == .home else { return }
        // FIX v23: Guard against redundant calls from LazyVStack onAppear.
        // WhaleActivityPreviewSection calls startMonitoring() on every onAppear,
        // which fires each time the section scrolls into view. Previously this
        // cancelled the timer and triggered a new immediate fetch (blocked by coordinator)
        // every time the user scrolled past the section. Now we skip if already monitoring.
        if refreshTimer != nil { return }
        
        // Initial fetch - fetch immediately (cached data already shown by init)
        Task {
            await fetchRecentTransactions()
        }
        
        // Schedule periodic refresh for live updates
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.fetchRecentTransactions() }
        }
    }
    
    /// Stop automatic monitoring
    public func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    /// Manual refresh - bypasses rate limiting for user-initiated refreshes
    /// Use this for pull-to-refresh and manual refresh buttons
    public func refresh() async {
        guard !isLoading else { return }
        
        // Skip coordinator check for user-initiated refresh
        // Users expect immediate feedback when they pull to refresh
        #if DEBUG
        print("[WhaleTracking] Manual refresh - bypassing rate limiter")
        #endif
        
        await performFetch()
    }
    
    /// Fetch recent whale transactions
    /// Primary: Uses Firebase proxy for shared caching and rate limit management
    /// Fallback: Direct API calls if Firebase is unavailable
    public func fetchRecentTransactions() async {
        guard !isLoading else { return }
        
        // PERFORMANCE FIX: Check API coordinator before making requests
        // This prevents thundering herd during startup and foreground transitions
        guard APIRequestCoordinator.shared.canMakeRequest(for: .whaleTracking) else {
            // FIX v23: Only log the first block per session to reduce console spam.
            // The 90-second timer fires this repeatedly and it was logging 12+ times per session.
            if !Self.hasLoggedCoordinatorBlock {
                Self.hasLoggedCoordinatorBlock = true
                #if DEBUG
                print("[WhaleTracking] Blocked by APIRequestCoordinator - will retry on next timer tick")
                #endif
            }
            return
        }
        Self.hasLoggedCoordinatorBlock = false // Reset on successful pass
        APIRequestCoordinator.shared.recordRequest(for: .whaleTracking)
        
        await performFetch()
    }
    
    /// Internal fetch logic - called by both fetchRecentTransactions() and refresh()
    private func performFetch() async {
        guard !isLoading else { return }
        
        isLoading = true
        lastError = nil
        dataSourceStatus = .fetching
        isUsingCachedData = false
        isDataStale = false
        lastDataUpdatedAt = nil
        
        var allTransactions: [WhaleTransaction] = []
        var firebaseFetchSucceeded = false
        
        // PRIMARY: Try Firebase proxy first (shared caching, no rate limits)
        if FirebaseService.shared.shouldUseFirebase {
            let firebaseResult = await fetchFromFirebase()
            firebaseFetchSucceeded = firebaseResult.didSucceed
            isUsingCachedData = firebaseResult.cached
            isDataStale = firebaseResult.stale
            lastDataUpdatedAt = firebaseResult.updatedAt
            let firebaseTransactions = firebaseResult.transactions
            if !firebaseTransactions.isEmpty {
                allTransactions = firebaseTransactions
                #if DEBUG
                print("[WhaleTrackingService] Fetched \(firebaseTransactions.count) transactions from Firebase proxy")
                #endif
            }
        }
        
        // FALLBACK: Only run direct APIs when Firebase is unavailable/failed.
        // If Firebase succeeds with zero results, treat that as valid "no activity".
        if allTransactions.isEmpty && (!FirebaseService.shared.shouldUseFirebase || !firebaseFetchSucceeded) {
            #if DEBUG
            print("[WhaleTrackingService] Falling back to direct API calls")
            #endif
            
            // Fetch from multiple sources in parallel for comprehensive coverage
            await withTaskGroup(of: (String, [WhaleTransaction]).self) { group in
                // ETHEREUM: Multiple sources for better coverage
                if config.enabledBlockchains.contains(.ethereum) {
                    // Primary: Etherscan (address-based monitoring)
                    group.addTask { ("Etherscan", await self.fetchEthereumWhales()) }
                    // Secondary: Ethplorer (large token transfers - FREE)
                    group.addTask { ("Ethplorer", await self.fetchEthplorerWhales()) }
                }
                
                // BITCOIN: Blockchair (most reliable free API)
                if config.enabledBlockchains.contains(.bitcoin) {
                    group.addTask { ("Blockchair", await self.fetchBitcoinWhalesBlockchair()) }
                }
                
                // SOLANA: Multiple sources for better coverage
                if config.enabledBlockchains.contains(.solana) {
                    // Primary: Solscan (free tier)
                    group.addTask { ("Solscan", await self.fetchSolanaWhales()) }
                    // Secondary: Helius (professional API with free tier)
                    group.addTask { ("Helius", await self.fetchHeliusWhales()) }
                }
                
                // PREMIUM API sources (if user has configured API keys)
                if self.whaleAlertAPIKey != nil {
                    group.addTask { ("Whale Alert", await self.fetchFromWhaleAlert()) }
                }
                
                if self.arkhamAPIKey != nil {
                    group.addTask { ("Arkham", await self.fetchFromArkham()) }
                }
                
                for await (source, transactions) in group {
                    if !transactions.isEmpty {
                        allTransactions.append(contentsOf: transactions)
                        #if DEBUG
                        print("[WhaleTrackingService] Fetched \(transactions.count) transactions from \(source)")
                        #endif
                    }
                }
            }
            // Direct API mode implies fresh client-side fetch.
            if !allTransactions.isEmpty {
                isUsingCachedData = false
                isDataStale = false
                lastDataUpdatedAt = Date()
            }
        }
        
        // DEDUPLICATION: Remove duplicate transactions from multiple API sources
        // Same transaction might be returned by Etherscan AND Ethplorer, or Solscan AND Helius
        // Deduplicate by transaction hash (the unique blockchain identifier)
        let beforeDedup = allTransactions.count
        allTransactions = deduplicateTransactions(allTransactions)
        let afterDedup = allTransactions.count
        
        #if DEBUG
        if beforeDedup != afterDedup {
            print("[WhaleTrackingService] Deduplication: \(beforeDedup) → \(afterDedup) transactions (removed \(beforeDedup - afterDedup) duplicates)")
        }
        #endif
        
        activeDataProviders = Array(Set(allTransactions.map { $0.dataSource.rawValue })).sorted()
        
        // LIVE DATA ONLY - No simulated/demo data for professional App Store release
        // All transactions shown are real blockchain data from APIs
        let liveTransactionCount = allTransactions.count
        
        if allTransactions.isEmpty {
            // No live data available - show empty state (handled by UI)
            #if DEBUG
            if !recentTransactions.isEmpty {
                print("[WhaleTrackingService] No new live whale transactions found (retaining cached history)")
            } else {
                print("[WhaleTrackingService] No live whale transactions found")
            }
            #endif
            dataSourceStatus = .success(source: "No recent whale transfers")
        } else {
            // We have live blockchain data
            #if DEBUG
            print("[WhaleTrackingService] Found \(liveTransactionCount) unique whale transactions")
            #endif
            dataSourceStatus = .success(source: "Live • \(liveTransactionCount) transactions")
        }
        
        // Sort by timestamp (newest first)
        allTransactions.sort { $0.timestamp > $1.timestamp }
        
        // Filter by minimum amount from config
        let filtered = allTransactions.filter { $0.amountUSD >= config.minAmountUSD }
        
        // Update with live data
        if !filtered.isEmpty {
            // Detect new transactions for notifications
            let newTransactionIds = Set(filtered.map { $0.id })
            let detectedNewTransactions = !previousTransactionIds.isEmpty && 
                newTransactionIds.subtracting(previousTransactionIds).count > 0
            
            recentTransactions = filtered
            previousTransactionIds = newTransactionIds
            
            // Trigger new transaction notification with haptic
            if detectedNewTransactions {
                triggerNewTransactionFeedback()
            }
        } else {
            // Clear transactions if none match filters
            recentTransactions = []
        }
        
        // Cache and merge with historical data (this updates recentTransactions)
        cacheTransactions()
        
        // Calculate statistics AFTER caching to include historical data
        calculateStatistics()
        
        // Check for watched wallet activity
        checkWatchedWalletActivity(transactions: recentTransactions)
        
        isLoading = false
    }
    
    // MARK: - Deduplication
    
    private func normalizedHash(from hash: String) -> String {
        hash.replacingOccurrences(of: "0x", with: "").lowercased()
    }
    
    private func deduplicationKey(for transaction: WhaleTransaction) -> String {
        // Same hash can exist on different chains, so include blockchain.
        "\(transaction.blockchain.rawValue)_\(normalizedHash(from: transaction.hash))"
    }
    
    /// Remove duplicate transactions that may come from multiple API sources
    /// Same transaction can be returned by Etherscan AND Ethplorer, or Solscan AND Helius
    /// We deduplicate by transaction hash, keeping the most reliable data source
    private func deduplicateTransactions(_ transactions: [WhaleTransaction]) -> [WhaleTransaction] {
        var seenHashes = Set<String>()
        var uniqueTransactions: [WhaleTransaction] = []
        
        // Data source priority (higher = preferred when duplicates found)
        // Premium/reliable sources are preferred
        let sourcePriority: [WhaleDataSource: Int] = [
            .whaleAlert: 100,    // Premium - most reliable
            .arkham: 90,         // Premium - detailed intelligence
            .blockchair: 70,     // Reliable Bitcoin data
            .etherscan: 60,      // Primary Ethereum source
            .ethplorer: 50,      // Secondary Ethereum (token transfers)
            .solscan: 60,        // Primary Solana source
            .helius: 50,         // Secondary Solana
            .blockchainInfo: 30, // Fallback
            .duneAnalytics: 80,  // Premium analytics
            .demo: 0             // Demo data - lowest priority
        ]
        
        // Sort by source priority (highest first) so we keep the best data
        let sorted = transactions.sorted { tx1, tx2 in
            let p1 = sourcePriority[tx1.dataSource] ?? 0
            let p2 = sourcePriority[tx2.dataSource] ?? 0
            return p1 > p2
        }
        
        for transaction in sorted {
            let uniqueKey = deduplicationKey(for: transaction)
            if !seenHashes.contains(uniqueKey) {
                seenHashes.insert(uniqueKey)
                uniqueTransactions.append(transaction)
            }
        }
        
        return uniqueTransactions
    }
    
    // MARK: - Firebase Proxy
    
    /// Fetch whale transactions from Firebase proxy
    /// Benefits: Shared caching across all users, no rate limiting issues
    private func fetchFromFirebase() async -> (transactions: [WhaleTransaction], didSucceed: Bool, cached: Bool, stale: Bool, updatedAt: Date?) {
        do {
            // Build blockchain list from config
            var blockchains: [String] = []
            if config.enabledBlockchains.contains(.ethereum) { blockchains.append("ethereum") }
            if config.enabledBlockchains.contains(.bitcoin) { blockchains.append("bitcoin") }
            if config.enabledBlockchains.contains(.solana) { blockchains.append("solana") }
            
            let response = try await FirebaseService.shared.getWhaleTransactions(
                minAmountUSD: config.minAmountUSD,
                blockchains: blockchains
            )
            
            // Convert Firebase response to local model
            let mapped: [WhaleTransaction] = response.transactions.compactMap { tx -> WhaleTransaction? in
                let blockchain: WhaleBlockchain
                switch tx.blockchain.lowercased() {
                case "bitcoin": blockchain = .bitcoin
                case "ethereum": blockchain = .ethereum
                case "solana": blockchain = .solana
                case "bsc": blockchain = .bsc
                case "polygon": blockchain = .polygon
                case "avalanche": blockchain = .avalanche
                case "arbitrum": blockchain = .arbitrum
                default: blockchain = .ethereum
                }
                
                let txType: WhaleTransactionType
                switch tx.transactionType {
                case "exchangeDeposit": txType = .exchangeDeposit
                case "exchangeWithdrawal": txType = .exchangeWithdrawal
                default: txType = .transfer
                }
                
                let dataSource: WhaleDataSource
                switch tx.dataSource {
                case "etherscan": dataSource = .etherscan
                case "blockchair": dataSource = .blockchair
                case "solscan": dataSource = .solscan
                case "whaleAlert": dataSource = .whaleAlert
                case "arkham": dataSource = .arkham
                default: dataSource = .etherscan
                }

                guard isReasonableTimestamp(tx.date, source: "Firebase-\(tx.blockchain)") else {
                    return nil
                }
                
                return WhaleTransaction(
                    id: tx.id,
                    blockchain: blockchain,
                    symbol: tx.symbol,
                    amount: tx.amount,
                    amountUSD: tx.amountUSD,
                    fromAddress: tx.fromAddress,
                    toAddress: tx.toAddress,
                    hash: tx.hash,
                    timestamp: tx.date,
                    transactionType: txType,
                    dataSource: dataSource
                )
            }
            return (
                mapped,
                true,
                response.cached,
                response.stale ?? false,
                parseProxyUpdatedAt(response.updatedAt)
            )
        } catch {
            #if DEBUG
            print("[WhaleTrackingService] Firebase proxy error: \(error.localizedDescription)")
            #endif
            return ([], false, false, false, nil)
        }
    }

    private func isReasonableTimestamp(_ timestamp: Date, source: String) -> Bool {
        let now = Date()
        let age = now.timeIntervalSince(timestamp)
        let maxAge: TimeInterval = 7 * 24 * 60 * 60
        let maxFutureSkew: TimeInterval = 5 * 60

        if age < -maxFutureSkew || age > maxAge {
            #if DEBUG
            print("[WhaleTrackingService] Skipping suspicious \(source) timestamp: age=\(Int(age / 60))m (\(timestamp))")
            #endif
            return false
        }
        return true
    }
    
    private func parseProxyUpdatedAt(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = iso.date(from: value) {
            return parsed
        }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: value)
    }
    
    /// Add a wallet to watch list
    public func addWatchedWallet(_ wallet: WatchedWallet) {
        guard !watchedWallets.contains(where: { $0.address.lowercased() == wallet.address.lowercased() }) else {
            return
        }
        watchedWallets.append(wallet)
        saveWatchedWallets()
    }
    
    /// Remove a wallet from watch list
    public func removeWatchedWallet(id: UUID) {
        watchedWallets.removeAll { $0.id == id }
        saveWatchedWallets()
    }
    
    /// Update watch configuration
    public func updateConfig(_ newConfig: WhaleAlertConfig) {
        config = newConfig
        saveConfig()
    }
    
    /// Trigger haptic feedback for new transactions
    private func triggerNewTransactionFeedback() {
        // Medium haptic for new whale transaction
        let impactMedium = UIImpactFeedbackGenerator(style: .medium)
        impactMedium.prepare()
        impactMedium.impactOccurred()
        
        // Set flag for UI to react
        newTransactionArrived = true
        
        // Reset flag after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.newTransactionArrived = false
        }
    }
    
    /// Reset the new transaction flag (call after handling)
    public func acknowledgeNewTransaction() {
        newTransactionArrived = false
    }
    
    // MARK: - API Key Management
    
    /// Set Whale Alert API key (stored securely in Keychain)
    public func setWhaleAlertAPIKey(_ key: String?) {
        if let key = key, !key.isEmpty {
            try? KeychainHelper.shared.save(key, service: Self.keychainService, account: Self.whaleAlertKeyAccount)
        } else {
            try? KeychainHelper.shared.delete(service: Self.keychainService, account: Self.whaleAlertKeyAccount)
        }
    }
    
    /// Set Arkham Intelligence API key (stored securely in Keychain)
    public func setArkhamAPIKey(_ key: String?) {
        if let key = key, !key.isEmpty {
            try? KeychainHelper.shared.save(key, service: Self.keychainService, account: Self.arkhamKeyAccount)
        } else {
            try? KeychainHelper.shared.delete(service: Self.keychainService, account: Self.arkhamKeyAccount)
        }
    }
    
    /// Whether a Whale Alert key is configured.
    public var hasWhaleAlertAPIKey: Bool {
        guard let key = whaleAlertAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !key.isEmpty
    }
    
    /// Whether an Arkham key is configured.
    public var hasArkhamAPIKey: Bool {
        guard let key = arkhamAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !key.isEmpty
    }
    
    /// Check if any premium API is configured.
    public var hasPremiumAPIKeys: Bool {
        hasWhaleAlertAPIKey || hasArkhamAPIKey
    }
    
    /// Available data sources based on configuration
    public var availableDataSources: [String] {
        var sources = ["Etherscan", "Ethplorer", "Blockchair", "Solscan", "Helius"]
        if hasWhaleAlertAPIKey {
            sources.append("Whale Alert (Premium)")
        }
        if hasArkhamAPIKey {
            sources.append("Arkham (Premium)")
        }
        return sources
    }
    
    /// Count of active free data sources
    public var freeDataSourceCount: Int {
        return 5 // Etherscan, Ethplorer, Blockchair, Solscan, Helius (via Solana RPC)
    }
    
    /// Count of premium data sources configured
    public var premiumDataSourceCount: Int {
        var count = 0
        if hasWhaleAlertAPIKey { count += 1 }
        if hasArkhamAPIKey { count += 1 }
        return count
    }
    
    /// Get transactions for a specific wallet
    public func transactions(for address: String) -> [WhaleTransaction] {
        recentTransactions.filter {
            $0.fromAddress.lowercased() == address.lowercased() ||
            $0.toAddress.lowercased() == address.lowercased()
        }
    }
    
    // MARK: - Private Methods - Fetching
    
    private func fetchEthereumWhales() async -> [WhaleTransaction] {
        // Using Etherscan V2 API to get large ETH transfers
        // Free tier: 5 calls/sec, 100,000 calls/day
        // Note: V2 API requires chainid parameter (1 for Ethereum mainnet)
        
        var transactions: [WhaleTransaction] = []
        
        // Read Etherscan API key from Keychain (required for V2 API)
        let etherscanAPIKey = (try? KeychainHelper.shared.read(service: "CryptoSage.APIConfig", account: "etherscan")) ?? ""
        let apiKeyParam = etherscanAPIKey.isEmpty ? "" : "&apikey=\(etherscanAPIKey)"
        
        if etherscanAPIKey.isEmpty {
            #if DEBUG
            print("[WhaleTrackingService] ⚠️ No Etherscan API key configured — whale Ethereum tracking limited")
            #endif
        }
        
        // IMPROVED: Fetch from 12 addresses for better coverage
        // Rate limit: 5 calls/sec, so 12 addresses with 300ms delays = ~3.6 seconds total
        // Increased offset to 20 transactions per address for more data
        for address in ethereumWhaleAddresses.prefix(12) {
            let urlString = "https://api.etherscan.io/v2/api?chainid=1&module=account&action=txlist&address=\(address)&startblock=0&endblock=99999999&page=1&offset=20&sort=desc\(apiKeyParam)"
            
            guard let url = URL(string: urlString) else { continue }
            
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { continue }
                
                let decoded = try JSONDecoder().decode(EtherscanResponse.self, from: data)
                
                // Check for error responses before processing
                guard decoded.isSuccess else {
                    // Log error message if present (e.g., rate limit, invalid API key)
                    if let errorMsg = decoded.errorMessage {
                        #if DEBUG
                        // LOG SPAM FIX: Special handling for V1 deprecation - log once per session
                        if errorMsg.contains("deprecated V1") || errorMsg.contains("V2") {
                            if !Self.didLogEtherscanV1Deprecation {
                                Self.didLogEtherscanV1Deprecation = true
                                print("[WhaleTrackingService] Etherscan V1 API deprecated - migration to V2 needed")
                            }
                        } else {
                            // Throttle other errors to once every 5 minutes
                            let now = Date()
                            if Self.lastEtherscanErrorLogAt == nil || now.timeIntervalSince(Self.lastEtherscanErrorLogAt!) >= Self.etherscanErrorLogThrottleInterval {
                                Self.lastEtherscanErrorLogAt = now
                                print("[WhaleTrackingService] Etherscan error for \(address.prefix(10))...: \(errorMsg)")
                            }
                        }
                        #endif
                    }
                    // Rate limited response - increase delay
                    if decoded.message.lowercased().contains("rate") {
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    }
                    continue
                }
                
                let ethPrice = await getCurrentETHPrice()
                
                for tx in decoded.transactions {
                    guard let value = Double(tx.value),
                          value > 0 else { continue }
                    
                    let ethAmount = value / 1e18 // Convert from wei
                    let usdValue = ethAmount * ethPrice
                    
                    // Only include transactions above configured minimum threshold.
                    guard usdValue >= config.minAmountUSD else { continue }
                    
                    // TIMESTAMP FIX: Skip transactions with invalid timestamps instead of using current time
                    // This prevents fake clustered timestamps that confuse users
                    guard let timestampDouble = Double(tx.timeStamp), timestampDouble > 0 else {
                        #if DEBUG
                        print("[WhaleTrackingService] Skipping Etherscan tx \(tx.hash.prefix(10))... - invalid timestamp: '\(tx.timeStamp)'")
                        #endif
                        continue
                    }
                    
                    let transaction = WhaleTransaction(
                        id: tx.hash,
                        blockchain: .ethereum,
                        symbol: "ETH",
                        amount: ethAmount,
                        amountUSD: usdValue,
                        fromAddress: tx.from,
                        toAddress: tx.to ?? "",
                        hash: tx.hash,
                        timestamp: Date(timeIntervalSince1970: timestampDouble),
                        transactionType: determineTransactionType(from: tx.from, to: tx.to ?? ""),
                        dataSource: .etherscan
                    )
                    transactions.append(transaction)
                }
                
                // Rate limit between calls - be generous to avoid 429s
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                
            } catch let decodingError as DecodingError {
                // Handle decoding errors separately with more detail
                #if DEBUG
                switch decodingError {
                case .dataCorrupted(let context):
                    print("[WhaleTrackingService] Etherscan decode error for \(address.prefix(10))...: Data corrupted - \(context.debugDescription)")
                case .keyNotFound(let key, _):
                    print("[WhaleTrackingService] Etherscan decode error for \(address.prefix(10))...: Missing key '\(key.stringValue)'")
                case .typeMismatch(let type, let context):
                    print("[WhaleTrackingService] Etherscan decode error for \(address.prefix(10))...: Type mismatch for \(type) - \(context.debugDescription)")
                case .valueNotFound(let type, _):
                    print("[WhaleTrackingService] Etherscan decode error for \(address.prefix(10))...: Value not found for \(type)")
                @unknown default:
                    print("[WhaleTrackingService] Etherscan decode error for \(address.prefix(10))...: Unknown decoding error")
                }
                #endif
            } catch {
                #if DEBUG
                // LOG SPAM FIX: Throttle error logging
                let now = Date()
                if Self.lastEtherscanErrorLogAt == nil || now.timeIntervalSince(Self.lastEtherscanErrorLogAt!) >= Self.etherscanErrorLogThrottleInterval {
                    Self.lastEtherscanErrorLogAt = now
                    print("[WhaleTrackingService] Etherscan error for \(address.prefix(10))...: \(error.localizedDescription)")
                }
                #endif
            }
        }
        
        return transactions
    }
    
    private func fetchBitcoinWhalesBlockchair() async -> [WhaleTransaction] {
        // Using Blockchair API for large BTC transactions - more reliable than blockchain.info
        // Free tier: 1440 requests/day
        
        // Calculate minimum satoshis based on config (default $100k)
        // At ~$95k/BTC: $100k ≈ 1.05 BTC = 105,000,000 satoshis
        // Using 100,000,000 satoshis (1 BTC) as minimum to catch more transactions
        let btcPrice = await getCurrentBTCPrice()
        let minBTC = config.minAmountUSD / btcPrice
        let minSatoshis = Int(minBTC * 100_000_000)
        
        let urlString = "https://api.blockchair.com/bitcoin/transactions?q=output_total(\(minSatoshis)..)&s=time(desc)&limit=30"
        guard let url = URL(string: urlString) else { return [] }
        
        var transactions: [WhaleTransaction] = []
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                // Fallback to blockchain.info if Blockchair fails
                return await fetchBitcoinWhalesBlockchainInfo()
            }
            
            let btcPrice = await getCurrentBTCPrice()
            
            // Parse Blockchair response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = json["data"] as? [[String: Any]] {
                
                for txData in dataObj.prefix(25) {
                    guard let hash = txData["hash"] as? String,
                          let outputTotal = txData["output_total"] as? Int,
                          let timeString = txData["time"] as? String else { continue }
                    
                    let btcAmount = Double(outputTotal) / 100_000_000
                    let usdValue = btcAmount * btcPrice
                    
                    // Only include large transactions (use config minimum)
                    guard usdValue >= config.minAmountUSD else { continue }
                    
                    // TIMESTAMP FIX: Parse timestamp and skip if invalid
                    // Try multiple date formats since Blockchair format may vary
                    let dateFormatter = ISO8601DateFormatter()
                    dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    
                    var timestamp: Date?
                    timestamp = dateFormatter.date(from: timeString)
                    
                    // Try without fractional seconds if first attempt fails
                    if timestamp == nil {
                        dateFormatter.formatOptions = [.withInternetDateTime]
                        timestamp = dateFormatter.date(from: timeString)
                    }
                    
                    // Skip transaction if we can't parse the timestamp
                    guard let validTimestamp = timestamp else {
                        #if DEBUG
                        print("[WhaleTrackingService] Skipping Blockchair tx \(hash.prefix(10))... - invalid timestamp: '\(timeString)'")
                        #endif
                        continue
                    }
                    
                    let transaction = WhaleTransaction(
                        id: hash,
                        blockchain: .bitcoin,
                        symbol: "BTC",
                        amount: btcAmount,
                        amountUSD: usdValue,
                        fromAddress: "Multiple Inputs",
                        toAddress: "Multiple Outputs",
                        hash: hash,
                        timestamp: validTimestamp,
                        transactionType: .transfer,
                        dataSource: .blockchair
                    )
                    transactions.append(transaction)
                }
            }
            
        } catch {
            #if DEBUG
            print("[WhaleTrackingService] Blockchair error: \(error.localizedDescription)")
            #endif
            // Fallback to blockchain.info
            return await fetchBitcoinWhalesBlockchainInfo()
        }
        
        return transactions
    }
    
    private func fetchBitcoinWhalesBlockchainInfo() async -> [WhaleTransaction] {
        // Fallback: Using Blockchain.com API for large BTC transactions
        
        let urlString = "https://blockchain.info/unconfirmed-transactions?format=json"
        guard let url = URL(string: urlString) else { return [] }
        
        var transactions: [WhaleTransaction] = []
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }
            
            let decoded = try JSONDecoder().decode(BlockchainUnconfirmedResponse.self, from: data)
            let btcPrice = await getCurrentBTCPrice()
            
            for tx in decoded.txs.prefix(50) {
                // Calculate total output value
                let totalSatoshis = tx.out.reduce(0) { $0 + ($1.value ?? 0) }
                let btcAmount = Double(totalSatoshis) / 100_000_000
                let usdValue = btcAmount * btcPrice
                
                // Only include large transactions (use config minimum)
                guard usdValue >= config.minAmountUSD else { continue }
                
                let fromAddress = tx.inputs.first?.prev_out?.addr ?? "Unknown"
                let toAddress = tx.out.first?.addr ?? "Unknown"
                
                let transaction = WhaleTransaction(
                    id: tx.hash,
                    blockchain: .bitcoin,
                    symbol: "BTC",
                    amount: btcAmount,
                    amountUSD: usdValue,
                    fromAddress: fromAddress,
                    toAddress: toAddress,
                    hash: tx.hash,
                    timestamp: Date(timeIntervalSince1970: Double(tx.time)),
                    transactionType: .transfer,
                    dataSource: .blockchainInfo
                )
                transactions.append(transaction)
            }
            
        } catch {
            #if DEBUG
            print("[WhaleTrackingService] Blockchain.info error: \(error.localizedDescription)")
            #endif
        }
        
        return transactions
    }
    
    private func fetchSolanaWhales() async -> [WhaleTransaction] {
        // Using Solscan public API for Solana whale transactions
        let solPrice = await getCurrentSOLPrice()
        var transactions: [WhaleTransaction] = []
        
        // Known Solana whale/exchange addresses to monitor - expanded list
        let solanaWhaleAddresses = [
            "9WzDXwBbmPdCBoccRSmN7fc1FS1VkPMiZbq1ampYP9xJ", // Binance Hot Wallet
            "5tzFkiKscXHK5ZXCGbXZxdw7gTjjD1mBwuoFbhUvuAi9", // Binance 2
            "H8sMJSCQxfKiFTCfDR3DUMLPwcRbM61LGFJ8N4dK3WjS", // Coinbase
            "3yFwqXBfZY4jBVUafQ1YEXw189y2dN3V5KQq9uzBDy1E", // FTX (Alameda related)
            "2AQdpHJ2JpcEgPiATUXjQxA8QmafFegfQwSLWSprPicm", // Kraken
            "GaBxu5TxgA9V4CgKeLHvKgGzYhYu5EATN7hjHDapjMNj", // Large Solana whale
            "9n4nbM75f5Ui33ZbPYXn59EwSgE8CGsHtAeTH5YFeJ9E", // Binance Hot Wallet 2
            "7dVexiqgZSXBNnz5MrXJghC8Yvv3ZJqLZpHbSNPYTnKx", // OKX
        ]
        
        // Fetch from Solscan API for each whale address
        // FIX v23: Track consecutive 404s and short-circuit. Solscan's free API returns 404
        // for all addresses when the endpoint is down or requires authentication.
        // Previously this made 8 sequential HTTP requests that all failed with 404.
        var consecutive404s = 0
        for address in solanaWhaleAddresses.prefix(8) {
            // Short-circuit if Solscan API is returning 404s consistently
            if consecutive404s >= 2 {
                #if DEBUG
                print("[WhaleTrackingService] Solscan API returning 404s - skipping remaining addresses")
                #endif
                break
            }
            let txs = await fetchSolscanTransactions(address: address, solPrice: solPrice)
            if txs.isEmpty {
                consecutive404s += 1
            } else {
                consecutive404s = 0
            }
            transactions.append(contentsOf: txs)
            
            // Small delay to respect rate limits
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        
        // LIVE DATA ONLY - No fallback to demo data
        #if DEBUG
        if transactions.isEmpty {
            print("[WhaleTrackingService] Solscan API returned no whale transactions")
        } else {
            print("[WhaleTrackingService] Fetched \(transactions.count) live Solana transactions from Solscan")
        }
        #endif
        return transactions
    }
    
    /// Fetch transactions from Solscan API (v2 with optional Pro token, falls back to public v1)
    private func fetchSolscanTransactions(address: String, solPrice: Double) async -> [WhaleTransaction] {
        // Solscan v1 public-api.solscan.io is deprecated and returns 404.
        // Try v2 Pro API first (requires token), then fall back to v1 as last resort.
        let solscanToken = (try? KeychainHelper.shared.read(service: "CryptoSage.APIConfig", account: "solscan")) ?? ""
        
        let urlString: String
        if !solscanToken.isEmpty {
            // Pro API v2.0 with authentication token
            urlString = "https://pro-api.solscan.io/v2.0/account/transactions?account=\(address)&limit=15"
        } else {
            // Public API (deprecated, may return 404 — Helius fallback is the primary Solana source)
            urlString = "https://public-api.solscan.io/account/transactions?account=\(address)&limit=15"
        }
        guard let url = URL(string: urlString) else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !solscanToken.isEmpty {
            request.setValue(solscanToken, forHTTPHeaderField: "token")
        }
        request.timeoutInterval = 10
        
        var transactions: [WhaleTransaction] = []
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                #if DEBUG
                // Throttle 404 logging — the public API is deprecated so this is expected
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                if statusCode != 404 {
                    print("[WhaleTrackingService] Solscan API status: \(statusCode)")
                }
                #endif
                return []
            }
            
            // Parse Solscan response
            let decoded = try JSONDecoder().decode([SolscanTransaction].self, from: data)
            
            for tx in decoded {
                // Convert lamports to SOL (1 SOL = 1,000,000,000 lamports)
                let solAmount = Double(tx.lamport ?? 0) / 1_000_000_000.0
                let usdValue = solAmount * solPrice
                
                // Only include whale-sized transactions
                guard usdValue >= config.minAmountUSD else { continue }
                
                let transaction = WhaleTransaction(
                    id: "sol_\(tx.txHash)",
                    blockchain: .solana,
                    symbol: "SOL",
                    amount: solAmount,
                    amountUSD: usdValue,
                    fromAddress: tx.signer.first ?? address,
                    toAddress: address,
                    hash: tx.txHash,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(tx.blockTime)),
                    transactionType: determineSolanaTransactionType(from: tx.signer.first, to: address),
                    dataSource: .solscan
                )
                transactions.append(transaction)
            }
            
        } catch {
            #if DEBUG
            print("[WhaleTrackingService] Solscan error for \(address.prefix(8))...: \(error.localizedDescription)")
            #endif
        }
        
        return transactions
    }
    
    /// Determine transaction type based on known exchange addresses
    private func determineSolanaTransactionType(from: String?, to: String) -> WhaleTransactionType {
        let knownExchanges = Set([
            "9WzDXwBbmPdCBoccRSmN7fc1FS1VkPMiZbq1ampYP9xJ",
            "5tzFkiKscXHK5ZXCGbXZxdw7gTjjD1mBwuoFbhUvuAi9",
            "H8sMJSCQxfKiFTCfDR3DUMLPwcRbM61LGFJ8N4dK3WjS",
            "2AQdpHJ2JpcEgPiATUXjQxA8QmafFegfQwSLWSprPicm"
        ].map { $0.lowercased() })
        
        let fromIsExchange = from.map { knownExchanges.contains($0.lowercased()) } ?? false
        let toIsExchange = knownExchanges.contains(to.lowercased())
        
        if fromIsExchange && !toIsExchange {
            return .exchangeWithdrawal
        } else if !fromIsExchange && toIsExchange {
            return .exchangeDeposit
        } else {
            return .transfer
        }
    }
    
    /// Generate demo Solana transactions as fallback
    private func generateSolanaDemoTransactions(solPrice: Double) -> [WhaleTransaction] {
        var transactions: [WhaleTransaction] = []
        
        let demoAddresses = [
            ("9WzDXwBbmPdCBoccRSmN7fc1FS1VkPMiZbq1ampYP9xJ", "Binance Hot Wallet"),
            ("H8sMJSCQxfKiFTCfDR3DUMLPwcRbM61LGFJ8N4dK3WjS", "Coinbase Hot Wallet"),
        ]
        
        for i in 0..<2 {
            let (address, _) = demoAddresses[i % demoAddresses.count]
            let solAmount = Double.random(in: 50000...200000)
            let usdValue = solAmount * solPrice
            
            guard usdValue >= 500_000 else { continue }
            
            let tx = WhaleTransaction(
                id: "sol_demo_\(UUID().uuidString.prefix(8))",
                blockchain: .solana,
                symbol: "SOL",
                amount: solAmount,
                amountUSD: usdValue,
                fromAddress: address,
                toAddress: "Unknown Wallet",
                hash: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(64)),
                timestamp: Date().addingTimeInterval(-Double.random(in: 60...3600)),
                transactionType: .transfer,
                dataSource: .demo
            )
            transactions.append(tx)
        }
        
        return transactions
    }
    
    // MARK: - Ethplorer API (FREE - Ethereum Large Transfers)
    
    /// Fetch large ETH/token transfers from Ethplorer
    /// Free API: No key required, tracks large token movements
    private func fetchEthplorerWhales() async -> [WhaleTransaction] {
        let ethPrice = await getCurrentETHPrice()
        var transactions: [WhaleTransaction] = []
        
        // Ethplorer top token transfers endpoint (free, no API key)
        // Returns recent large token movements across Ethereum
        _ = "https://api.ethplorer.io/getTopTokenHolders/0x0000000000000000000000000000000000000000?apiKey=freekey&limit=50"
        
        // Alternative: Get recent large transactions for top addresses
        let topAddressesURL = "https://api.ethplorer.io/getTop?apiKey=freekey&criteria=cap&limit=10"
        
        guard let url = URL(string: topAddressesURL) else { return [] }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                #if DEBUG
                print("[WhaleTrackingService] Ethplorer API returned status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                #endif
                return []
            }
            
            // Parse Ethplorer response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tokens = json["tokens"] as? [[String: Any]] {
                
                // Get transactions from top token addresses
                for token in tokens.prefix(5) {
                    guard let address = token["address"] as? String else { continue }
                    
                    // Fetch recent transfers for this token
                    let transfersURL = "https://api.ethplorer.io/getTokenHistory/\(address)?apiKey=freekey&type=transfer&limit=20"
                    guard let transferURL = URL(string: transfersURL) else { continue }
                    
                    let (transferData, transferResponse) = try await URLSession.shared.data(from: transferURL)
                    guard (transferResponse as? HTTPURLResponse)?.statusCode == 200 else { continue }
                    
                    if let transferJson = try? JSONSerialization.jsonObject(with: transferData) as? [String: Any],
                       let operations = transferJson["operations"] as? [[String: Any]] {
                        
                        for op in operations.prefix(10) {
                            guard let value = op["value"] as? String,
                                  let timestamp = op["timestamp"] as? Int,
                                  let from = op["from"] as? String,
                                  let to = op["to"] as? String,
                                  let txHash = op["transactionHash"] as? String else { continue }
                            
                            let tokenInfo = op["tokenInfo"] as? [String: Any]
                            let symbol = tokenInfo?["symbol"] as? String ?? "ETH"
                            let decimals = (tokenInfo?["decimals"] as? String).flatMap { Int($0) } ?? 18
                            let priceUSD = (tokenInfo?["price"] as? [String: Any])?["rate"] as? Double ?? ethPrice
                            
                            // Calculate amount with proper decimals
                            let rawAmount = Double(value) ?? 0
                            let amount = rawAmount / pow(10.0, Double(decimals))
                            let usdValue = amount * priceUSD
                            
                            // Only include whale-sized transactions
                            guard usdValue >= config.minAmountUSD else { continue }
                            
                            let transaction = WhaleTransaction(
                                id: "ethplorer_\(txHash)",
                                blockchain: .ethereum,
                                symbol: symbol,
                                amount: amount,
                                amountUSD: usdValue,
                                fromAddress: from,
                                toAddress: to,
                                hash: txHash,
                                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                                transactionType: determineEthereumTransactionType(from: from, to: to),
                                dataSource: .ethplorer
                            )
                            transactions.append(transaction)
                        }
                    }
                    
                    // Small delay to respect rate limits
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
            }
            
        } catch {
            #if DEBUG
            print("[WhaleTrackingService] Ethplorer error: \(error.localizedDescription)")
            #endif
        }

        #if DEBUG
        print("[WhaleTrackingService] Ethplorer returned \(transactions.count) whale transactions")
        #endif
        return transactions
    }
    
    // MARK: - Helius API (FREE TIER - Professional Solana Data)
    
    /// Fetch Solana whale transactions from Helius
    /// Free tier: 100k requests/month, professional-grade Solana data
    /// Sign up at: https://dashboard.helius.dev/signup
    private func fetchHeliusWhales() async -> [WhaleTransaction] {
        let solPrice = await getCurrentSOLPrice()
        var transactions: [WhaleTransaction] = []
        
        // Helius requires an API key - check if user has configured one
        // For now, we'll use their public endpoints where available
        // Users can add their free Helius API key in settings for better data
        
        // Known Solana whale wallets to monitor via Helius-style queries
        let whaleWallets = [
            "9WzDXwBbmPdCBoccRSmN7fc1FS1VkPMiZbq1ampYP9xJ", // Binance
            "5tzFkiKscXHK5ZXCGbXZxdw7gTjjD1mBwuoFbhUvuAi9", // Binance 2
            "H8sMJSCQxfKiFTCfDR3DUMLPwcRbM61LGFJ8N4dK3WjS", // Coinbase
            "2AQdpHJ2JpcEgPiATUXjQxA8QmafFegfQwSLWSprPicm", // Kraken
        ]
        
        // Use Solana's native RPC for balance changes (works without API key)
        // This is a fallback approach that works universally
        for wallet in whaleWallets.prefix(4) {
            let rpcURL = "https://api.mainnet-beta.solana.com"
            guard let url = URL(string: rpcURL) else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Get recent signatures for this wallet
            let body: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "getSignaturesForAddress",
                "params": [
                    wallet,
                    ["limit": 10]
                ]
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = json["result"] as? [[String: Any]] {
                    
                    for sig in result.prefix(5) {
                        guard let signature = sig["signature"] as? String,
                              let blockTime = sig["blockTime"] as? Int else { continue }
                        
                        // Get transaction details
                        let detailBody: [String: Any] = [
                            "jsonrpc": "2.0",
                            "id": 1,
                            "method": "getTransaction",
                            "params": [
                                signature,
                                ["encoding": "jsonParsed", "maxSupportedTransactionVersion": 0]
                            ]
                        ]
                        
                        var detailRequest = URLRequest(url: url)
                        detailRequest.httpMethod = "POST"
                        detailRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        detailRequest.httpBody = try JSONSerialization.data(withJSONObject: detailBody)
                        
                        let (detailData, _) = try await URLSession.shared.data(for: detailRequest)
                        
                        if let detailJson = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
                           let txResult = detailJson["result"] as? [String: Any],
                           let meta = txResult["meta"] as? [String: Any] {
                            
                            // Calculate SOL transfer amount from balance changes
                            let preBalances = meta["preBalances"] as? [Int] ?? []
                            let postBalances = meta["postBalances"] as? [Int] ?? []
                            
                            if !preBalances.isEmpty && !postBalances.isEmpty {
                                let lamportChange = abs(postBalances[0] - preBalances[0])
                                let solAmount = Double(lamportChange) / 1_000_000_000.0
                                let usdValue = solAmount * solPrice
                                
                                // Only include whale-sized transactions
                                guard usdValue >= config.minAmountUSD else { continue }
                                
                                let transaction = WhaleTransaction(
                                    id: "helius_\(signature)",
                                    blockchain: .solana,
                                    symbol: "SOL",
                                    amount: solAmount,
                                    amountUSD: usdValue,
                                    fromAddress: wallet,
                                    toAddress: "Transfer",
                                    hash: signature,
                                    timestamp: Date(timeIntervalSince1970: TimeInterval(blockTime)),
                                    transactionType: .transfer,
                                    dataSource: .helius
                                )
                                transactions.append(transaction)
                            }
                        }
                    }
                }
                
                // Delay between wallets to respect rate limits
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                
            } catch {
                #if DEBUG
                print("[WhaleTrackingService] Helius/Solana RPC error: \(error.localizedDescription)")
                #endif
            }
        }

        #if DEBUG
        print("[WhaleTrackingService] Helius returned \(transactions.count) whale transactions")
        #endif
        return transactions
    }
    
    /// Helper to determine Ethereum transaction type
    private func determineEthereumTransactionType(from: String, to: String) -> WhaleTransactionType {
        // First entries are known exchange wallets; normalize for case-insensitive matching.
        let knownExchanges = Set(ethereumWhaleAddresses.prefix(8).map { $0.lowercased() })
        
        let fromIsExchange = knownExchanges.contains(from.lowercased())
        let toIsExchange = knownExchanges.contains(to.lowercased())
        
        if fromIsExchange && !toIsExchange {
            return .exchangeWithdrawal
        } else if !fromIsExchange && toIsExchange {
            return .exchangeDeposit
        } else {
            return .transfer
        }
    }
    
    // MARK: - Premium API Sources
    
    /// Fetch from Whale Alert API (requires API key)
    private func fetchFromWhaleAlert() async -> [WhaleTransaction] {
        guard let apiKey = whaleAlertAPIKey else { return [] }
        
        // Whale Alert API - Get recent transactions (last hour)
        let minValue = Int(config.minAmountUSD)
        let startTime = Int(Date().addingTimeInterval(-3600).timeIntervalSince1970) // 1 hour ago
        
        let urlString = "https://api.whale-alert.io/v1/transactions?api_key=\(apiKey)&min_value=\(minValue)&start=\(startTime)&cursor="
        
        guard let url = URL(string: urlString) else { return [] }
        
        var transactions: [WhaleTransaction] = []
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                #if DEBUG
                print("[WhaleTrackingService] Whale Alert API returned status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                #endif
                return []
            }
            
            let decoded = try JSONDecoder().decode(WhaleAlertResponse.self, from: data)
            
            for tx in decoded.transactions ?? [] {
                let blockchain = whaleAlertBlockchain(from: tx.blockchain)
                let transactionType = determineWhaleAlertType(from: tx.from, to: tx.to)
                
                let transaction = WhaleTransaction(
                    id: tx.id ?? tx.hash,
                    blockchain: blockchain,
                    symbol: tx.symbol.uppercased(),
                    amount: tx.amount,
                    amountUSD: tx.amount_usd,
                    fromAddress: tx.from.address ?? "Unknown",
                    toAddress: tx.to.address ?? "Unknown",
                    hash: tx.hash,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(tx.timestamp)),
                    transactionType: transactionType,
                    dataSource: .whaleAlert
                )
                transactions.append(transaction)
            }
            
            #if DEBUG
            print("[WhaleTrackingService] Fetched \(transactions.count) from Whale Alert")
            #endif

        } catch {
            #if DEBUG
            print("[WhaleTrackingService] Whale Alert error: \(error.localizedDescription)")
            #endif
        }
        
        return transactions
    }
    
    private func whaleAlertBlockchain(from chain: String) -> WhaleBlockchain {
        switch chain.lowercased() {
        case "bitcoin": return .bitcoin
        case "ethereum": return .ethereum
        case "solana": return .solana
        case "binancesmartchain", "bsc": return .bsc
        case "polygon", "matic": return .polygon
        case "avalanche", "avax": return .avalanche
        case "arbitrum": return .arbitrum
        default: return .ethereum
        }
    }
    
    private func determineWhaleAlertType(from: WhaleAlertOwner, to: WhaleAlertOwner) -> WhaleTransactionType {
        let fromIsExchange = from.owner_type == "exchange"
        let toIsExchange = to.owner_type == "exchange"
        
        if fromIsExchange && !toIsExchange {
            return .exchangeWithdrawal
        } else if !fromIsExchange && toIsExchange {
            return .exchangeDeposit
        } else {
            return .transfer
        }
    }
    
    /// Fetch from Arkham Intelligence API (requires API key)
    private func fetchFromArkham() async -> [WhaleTransaction] {
        guard let apiKey = arkhamAPIKey else { return [] }
        
        // Arkham API endpoint for large transfers
        let urlString = "https://api.arkhamintelligence.com/transfers/large?api_key=\(apiKey)&min_usd=\(Int(config.minAmountUSD))&limit=50"
        
        guard let url = URL(string: urlString) else { return [] }
        
        var transactions: [WhaleTransaction] = []
        
        do {
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "API-Key")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                #if DEBUG
                print("[WhaleTrackingService] Arkham API returned status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                #endif
                return []
            }
            
            let decoded = try JSONDecoder().decode(ArkhamResponse.self, from: data)
            
            for tx in decoded.transfers ?? [] {
                // TIMESTAMP FIX: Skip transactions with invalid/missing timestamps
                guard let timestamp = tx.timestamp, timestamp > 0 else {
                    #if DEBUG
                    print("[WhaleTrackingService] Skipping Arkham tx \(tx.hash.prefix(10))... - missing timestamp")
                    #endif
                    continue
                }
                
                let transaction = WhaleTransaction(
                    id: tx.hash,
                    blockchain: whaleAlertBlockchain(from: tx.chain ?? "ethereum"),
                    symbol: tx.tokenSymbol ?? "ETH",
                    amount: tx.amount ?? 0,
                    amountUSD: tx.usdValue ?? 0,
                    fromAddress: tx.fromAddress ?? "Unknown",
                    toAddress: tx.toAddress ?? "Unknown",
                    hash: tx.hash,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                    transactionType: .transfer, // Arkham doesn't provide this directly
                    dataSource: .arkham
                )
                transactions.append(transaction)
            }
            
            #if DEBUG
            print("[WhaleTrackingService] Fetched \(transactions.count) from Arkham")
            #endif

        } catch {
            #if DEBUG
            print("[WhaleTrackingService] Arkham error: \(error.localizedDescription)")
            #endif
        }
        
        return transactions
    }
    
    // MARK: - Demo/Fallback Data
    
    private func generateDemoTransactions() -> [WhaleTransaction] {
        // Generate realistic demo transactions for when APIs fail or return sparse data
        // This ensures users always see a useful whale feed with varied transaction sizes
        
        var transactions: [WhaleTransaction] = []
        let now = Date()
        
        // Demo transaction data - realistic whale movements with varied sizes (30 transactions)
        // Range from $150K (small whale) to $39M (mega whale) for good variety
        let demoData: [(WhaleBlockchain, String, Double, Double, String, String, WhaleTransactionType, Int)] = [
            // (blockchain, symbol, amount, usdAmount, from, to, type, minutesAgo)
            
            // === VERY RECENT (Last 15 minutes) - High activity feel ===
            (.solana, "SOL", 76821.59, 11_100_000, "GaBxu5TxgA9V4CgKeLHvKgGzYhYu5EATN7hjHDapjMNj", "Unknown Wallet", .transfer, 2),
            (.ethereum, "ETH", 350, 1_155_000, "0x71660c4005BA85c37ccec55d0C4493E66Fe775d3", "0x742d35Cc6634C0532925a3b844Bc9e7595f9E091", .exchangeWithdrawal, 4),
            (.solana, "SOL", 104304.44, 15_000_000, "5tzFkiKscXHK5ZXCGbXZxdw7gTjjD1mBwuoFbhUvuAi9", "Unknown Wallet", .transfer, 7),
            (.bitcoin, "BTC", 2.5, 237_500, "34xp4vRoCGJym3xR7yCVPFHoCNxv4Twseo", "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh", .exchangeWithdrawal, 11),
            
            // === RECENT (15-60 minutes) ===
            (.bitcoin, "BTC", 150.5, 14_297_500, "34xp4vRoCGJym3xR7yCVPFHoCNxv4Twseo", "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh", .exchangeWithdrawal, 16),
            (.ethereum, "ETH", 5000, 16_500_000, "0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8", "0x742d35Cc6634C0532925a3b844Bc9e7595f9E091", .exchangeWithdrawal, 22),
            (.solana, "SOL", 8500, 170_000, "H8sMJSCQxfKiFTCfDR3DUMLPwcRbM61LGFJ8N4dK3WjS", "2AQdpHJ2JpcEgPiATUXjQxA8QmafFegfQwSLWSprPicm", .transfer, 28),
            (.ethereum, "ETH", 3200, 10_560_000, "0xDFd5293D8e347dFe59E90eFd55b2956a1343963d", "0x71660c4005BA85c37ccec55d0C4493E66Fe775d3", .transfer, 34),
            (.bitcoin, "BTC", 75.2, 7_144_000, "1P5ZEDWTKTFGxQjZphgWPQUpe554WKDfHQ", "34xp4vRoCGJym3xR7yCVPFHoCNxv4Twseo", .exchangeDeposit, 42),
            (.polygon, "MATIC", 500000, 250_000, "0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245", "0x0D0707963952f2fBA59dD06f2b425ace40b492Fe", .transfer, 48),
            (.ethereum, "ETH", 2500, 8_250_000, "0xDFd5293D8e347dFe59E90eFd55b2956a1343963d", "0x503828976D22510aad0201ac7EC88293211D23Da", .transfer, 55),
            
            // === 1-2 HOURS AGO ===
            (.arbitrum, "ETH", 1800, 5_940_000, "0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D", "0x1714400FF23dB4aF24F9fd64e7039e6597f18C2b", .transfer, 68),
            (.solana, "SOL", 125000, 2_500_000, "GaBxu5TxgA9V4CgKeLHvKgGzYhYu5EATN7hjHDapjMNj", "5tzFkiKscXHK5ZXCGbXZxdw7gTjjD1mBwuoFbhUvuAi9", .transfer, 75),
            (.bitcoin, "BTC", 200.0, 19_000_000, "bc1qgdjqv0av3q56jvd82tkdjpy7gdp9ut8tlqmgrpmv24sq90ecnvqqjwvw97", "3FupZp77ySr7jwoLYEJ9mwzJpvoNBXsBnE", .exchangeDeposit, 82),
            (.ethereum, "ETH", 8500, 28_050_000, "0x66f820a414680B5bcda5eECA5dea238543F42054", "0x2910543Af39abA0Cd09dBb2D50200b3E800A63D2", .transfer, 95),
            (.solana, "SOL", 15000, 300_000, "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM", "5Q544fKrFoe6tsEbD7S8EmxGTJYAKtTVhAW5Q5pge4j1", .exchangeDeposit, 105),
            (.polygon, "MATIC", 18000000, 9_000_000, "0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245", "0x0D0707963952f2fBA59dD06f2b425ace40b492Fe", .exchangeWithdrawal, 115),
            
            // === 2-4 HOURS AGO ===
            (.ethereum, "ETH", 4200, 13_860_000, "0x876EabF441B2EE5B5b0554Fd502a8E0600950cFa", "0x28C6c06298d514Db089934071355E5743bf21d60", .exchangeDeposit, 130),
            (.bsc, "BNB", 50000, 15_000_000, "0x8894E0a0c962CB723c1976a4421c95949bE2D4E3", "0xF977814e90dA44bFA03b6295A0616a897441aceC", .transfer, 150),
            (.bitcoin, "BTC", 85.5, 8_122_500, "3Kzh9qAqVWQhEsfQz7zEQL1EuSx5tyNLNS", "1FzWLkAahHooV3kzPgBvNNBfKXxhbzA6BQ", .exchangeWithdrawal, 175),
            (.ethereum, "ETH", 180, 594_000, "0x503828976D22510aad0201ac7EC88293211D23Da", "0xDFd5293D8e347dFe59E90eFd55b2956a1343963d", .transfer, 195),
            (.polygon, "MATIC", 25000000, 12_500_000, "0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245", "0x5a52E96BAcdaBb82fd05763E25335261B270Efcb", .exchangeWithdrawal, 210),
            (.solana, "SOL", 22000, 440_000, "5Q544fKrFoe6tsEbD7S8EmxGTJYAKtTVhAW5Q5pge4j1", "GaBxu5TxgA9V4CgKeLHvKgGzYhYu5EATN7hjHDapjMNj", .exchangeWithdrawal, 225),
            (.ethereum, "ETH", 6800, 22_440_000, "0x2B5634C42055806a59e9107ED44D43c426E58258", "0xd6216fC19DB775Df9774a6E33526131dA7D19a2c", .transfer, 240),
            
            // === 4-8 HOURS AGO ===
            (.avalanche, "AVAX", 500000, 10_000_000, "0x9f8c163cBA728e99993ABe7495F06c0A3c8Ac8b9", "Unknown Wallet", .transfer, 280),
            (.bitcoin, "BTC", 5.2, 494_000, "bc1qgdjqv0av3q56jvd82tkdjpy7gdp9ut8tlqmgrpmv24sq90ecnvqqjwvw97", "34xp4vRoCGJym3xR7yCVPFHoCNxv4Twseo", .exchangeDeposit, 320),
            (.solana, "SOL", 280000, 5_600_000, "H8sMJSCQxfKiFTCfDR3DUMLPwcRbM61LGFJ8N4dK3WjS", "2AQdpHJ2JpcEgPiATUXjQxA8QmafFegfQwSLWSprPicm", .exchangeWithdrawal, 365),
            (.ethereum, "ETH", 12000, 39_600_000, "0xab5c66752a9e8167967685f1450532fb96d5d24f", "0x6748f50f686bfbcA6Fe8ad62b22228b87F31ff2b", .transfer, 410),
            (.arbitrum, "ETH", 450, 1_485_000, "0x1714400FF23dB4aF24F9fd64e7039e6597f18C2b", "0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D", .exchangeWithdrawal, 455),
            (.bsc, "BNB", 1200, 360_000, "0xF977814e90dA44bFA03b6295A0616a897441aceC", "0x8894E0a0c962CB723c1976a4421c95949bE2D4E3", .transfer, 490),
        ]
        
        for (blockchain, symbol, amount, usdAmount, from, to, type, minutesAgo) in demoData {
            let tx = WhaleTransaction(
                id: "demo_\(UUID().uuidString.prefix(8))",
                blockchain: blockchain,
                symbol: symbol,
                amount: amount,
                amountUSD: usdAmount,
                fromAddress: from,
                toAddress: to,
                hash: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(64)),
                timestamp: now.addingTimeInterval(-Double(minutesAgo * 60)),
                transactionType: type,
                dataSource: .demo
            )
            transactions.append(tx)
        }
        
        return transactions
    }
    
    // MARK: - Private Methods - Helpers
    
    // Cache for crypto prices
    private static var priceCache: [String: (price: Double, timestamp: Date)] = [:]
    private static let priceCacheTTL: TimeInterval = 60 // 1 minute cache
    
    private func getCurrentETHPrice() async -> Double {
        await fetchCachedPrice(for: "ethereum")
    }
    
    private func getCurrentBTCPrice() async -> Double {
        await fetchCachedPrice(for: "bitcoin")
    }
    
    private func getCurrentSOLPrice() async -> Double {
        await fetchCachedPrice(for: "solana")
    }
    
    /// Fetch price from real data sources only - NO FAKE FALLBACKS
    /// Priority: 1) Local cache, 2) MarketViewModel, 3) CoinGecko API
    /// Returns 0 if no real data available
    private func fetchCachedPrice(for coinId: String) async -> Double {
        // Check local cache first
        if let cached = Self.priceCache[coinId],
           Date().timeIntervalSince(cached.timestamp) < Self.priceCacheTTL {
            return cached.price
        }
        
        // Try MarketViewModel's cached data (loaded synchronously at startup)
        if let price = await MainActor.run(body: { MarketViewModel.shared.bestPrice(for: coinId) }),
           price > 0 {
            Self.priceCache[coinId] = (price, Date())
            return price
        }
        
        // Fetch from CoinGecko simple price endpoint as last resort
        let curr = CurrencyManager.apiValue
        let urlString = "https://api.coingecko.com/api/v3/simple/price?ids=\(coinId)&vs_currencies=\(curr)"
        guard let url = URL(string: urlString) else { return 0 }
        
        do {
            let req = APIConfig.coinGeckoRequest(url: url)
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return 0
            }
            
            // Parse response: {"bitcoin":{"eur":87000}} (dynamic currency key)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]],
               let priceData = json[coinId],
               let price = priceData[curr] ?? priceData["usd"] {
                Self.priceCache[coinId] = (price, Date())
                return price
            }
        } catch {
            #if DEBUG
            print("[WhaleTrackingService] Failed to fetch \(coinId) price: \(error.localizedDescription)")
            #endif
        }
        
        // NO FAKE FALLBACKS - return 0 if no real data available
        return 0
    }
    
    private func determineTransactionType(from: String, to: String) -> WhaleTransactionType {
        let fromIsExchange = isExchangeAddress(from)
        let toIsExchange = isExchangeAddress(to)
        
        if fromIsExchange && !toIsExchange {
            return .exchangeWithdrawal
        } else if !fromIsExchange && toIsExchange {
            return .exchangeDeposit
        } else if fromIsExchange && toIsExchange {
            // Exchange to exchange transfer - treat as neutral
            return .transfer
        }
        return .transfer
    }
    
    /// Enhanced exchange address detection with pattern matching
    private func isExchangeAddress(_ address: String) -> Bool {
        // First check the known labels database
        if KnownWhaleLabels.isExchangeAddress(address) {
            return true
        }
        
        // Additional pattern-based detection for common exchange patterns
        let lowercaseAddr = address.lowercased()
        
        // Known exchange address prefixes/patterns
        let exchangePatterns = [
            // Binance patterns
            "0x28c6c06298d514db089934071355e5743bf21d60",
            "0xbe0eb53f46cd790cd13851d5eff43d12404d33e8",
            "0xf977814e90da44bfa03b6295a0616a897441acec",
            "0x3f5ce5fbfe3e9af3971dd833d26ba9b5c936f0be",
            // Coinbase patterns
            "0x503828976d22510aad0201ac7ec88293211d23da",
            "0xdfd5293d8e347dfe59e90efd55b2956a1343963d",
            "0x71660c4005ba85c37ccec55d0c4493e66fe775d3",
            // Known Bitcoin exchange patterns
            "34xp4v", "1p5zed", "bc1qgd", "3fupzp", "bc1qxy",
        ]
        
        for pattern in exchangePatterns {
            if lowercaseAddr.hasPrefix(pattern) || lowercaseAddr.contains(pattern) {
                return true
            }
        }
        
        // Check for common exchange naming patterns in known labels
        if let label = KnownWhaleLabels.label(for: address) {
            let labelLower = label.lowercased()
            let exchangeKeywords = ["binance", "coinbase", "kraken", "bitfinex", "okx", "gemini", 
                                    "kucoin", "huobi", "htx", "bybit", "crypto.com", "exchange", "hot wallet"]
            for keyword in exchangeKeywords {
                if labelLower.contains(keyword) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func calculateStatistics() {
        let uniqueRecent = deduplicateTransactions(recentTransactions)
        guard !uniqueRecent.isEmpty else {
            statistics = WhaleStatistics(
                totalTransactionsLast24h: 0,
                totalVolumeUSD: 0,
                largestTransaction: nil,
                mostActiveBlockchain: nil,
                avgTransactionSize: 0,
                exchangeInflowUSD: 0,
                exchangeOutflowUSD: 0
            )
            volumeHistory = []
            analyzeSmartMoneyActivity()
            return
        }
        
        let now = Date()
        let last24h = uniqueRecent.filter {
            now.timeIntervalSince($0.timestamp) < 24 * 60 * 60
        }
        
        #if DEBUG
        if Self.verboseTimestampDebug {
            // Debug: Log timestamp distribution to diagnose chart issues
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss"
            print("[WhaleTrackingService] === TIMESTAMP DEBUG ===")
            print("[WhaleTrackingService] Total transactions: \(recentTransactions.count), Last 24h: \(last24h.count)")
            for (index, tx) in last24h.prefix(10).enumerated() {
                let ageMinutes = now.timeIntervalSince(tx.timestamp) / 60
                print("[WhaleTrackingService] Tx \(index): \(dateFormatter.string(from: tx.timestamp)) (\(Int(ageMinutes))min ago) - \(tx.dataSource) - $\(Int(tx.amountUSD/1000))K")
            }

            // Group by rendered relative label to detect visual clustering ("4h ago" etc.)
            let groupedByRelative = Dictionary(grouping: last24h) { tx in
                WhaleRelativeTimeFormatter.format(tx.timestamp, now: now)
            }
            let heavyBuckets = groupedByRelative
                .filter { $0.value.count >= 3 }
                .sorted { $0.value.count > $1.value.count }
            for (label, group) in heavyBuckets.prefix(5) {
                let oldest = group.map(\.timestamp).min() ?? now
                let newest = group.map(\.timestamp).max() ?? now
                let spreadMinutes = Int(newest.timeIntervalSince(oldest) / 60)
                print("[WhaleTrackingService] Relative bucket '\(label)': \(group.count) tx (spread \(spreadMinutes)m)")
            }
            print("[WhaleTrackingService] === END DEBUG ===")
        }
        #endif
        
        let totalVolume = last24h.reduce(0) { $0 + $1.amountUSD }
        let avgSize = last24h.isEmpty ? 0 : totalVolume / Double(last24h.count)
        
        let exchangeInflow = last24h.filter { $0.transactionType == .exchangeDeposit }.reduce(0) { $0 + $1.amountUSD }
        let exchangeOutflow = last24h.filter { $0.transactionType == .exchangeWithdrawal }.reduce(0) { $0 + $1.amountUSD }
        
        // Find most active blockchain
        let blockchainCounts = Dictionary(grouping: last24h, by: { $0.blockchain })
        let mostActive = blockchainCounts.max(by: { $0.value.count < $1.value.count })?.key
        
        statistics = WhaleStatistics(
            totalTransactionsLast24h: last24h.count,
            totalVolumeUSD: totalVolume,
            largestTransaction: last24h.max(by: { $0.amountUSD < $1.amountUSD }),
            mostActiveBlockchain: mostActive,
            avgTransactionSize: avgSize,
            exchangeInflowUSD: exchangeInflow,
            exchangeOutflowUSD: exchangeOutflow
        )
        
        // Calculate volume history
        calculateVolumeHistory(using: last24h)
        
        // Analyze smart money activity
        analyzeSmartMoneyActivity()
    }
    
    /// Generate volume history data points grouped by hour for the last 24 hours
    private func calculateVolumeHistory(using transactions24h: [WhaleTransaction]) {
        let calendar = Calendar.current
        let now = Date()
        
        // Create hourly buckets for last 24 hours
        var historyPoints: [VolumeDataPoint] = []
        
        // Get the start of the current hour for proper alignment
        let currentHourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        
        // Last 24 hours: hourly data points
        // hoursAgo=0 means current hour (from currentHourStart to now)
        // hoursAgo=1 means previous hour, etc.
        for hoursAgo in 0..<24 {
            let bucketStart = calendar.date(byAdding: .hour, value: -hoursAgo, to: currentHourStart)!
            let bucketEnd: Date
            
            if hoursAgo == 0 {
                // Current hour: from hour start to now
                bucketEnd = now
            } else {
                // Previous hours: full hour buckets
                bucketEnd = calendar.date(byAdding: .hour, value: 1, to: bucketStart)!
            }
            
            let hourTransactions = transactions24h.filter { tx in
                tx.timestamp >= bucketStart && tx.timestamp < bucketEnd
            }
            
            let volume = hourTransactions.reduce(0) { $0 + $1.amountUSD }
            let inflow = hourTransactions.filter { $0.transactionType == .exchangeDeposit }.reduce(0) { $0 + $1.amountUSD }
            let outflow = hourTransactions.filter { $0.transactionType == .exchangeWithdrawal }.reduce(0) { $0 + $1.amountUSD }
            
            #if DEBUG
            if Self.verboseTimestampDebug && hourTransactions.count > 0 {
                print("[WhaleTrackingService] Hour bucket \(hoursAgo): \(bucketStart) - \(bucketEnd), \(hourTransactions.count) txs, $\(Int(volume/1_000_000))M")
            }
            #endif
            
            historyPoints.append(VolumeDataPoint(
                date: bucketStart,
                volumeUSD: volume,
                transactionCount: hourTransactions.count,
                exchangeInflow: inflow,
                exchangeOutflow: outflow
            ))
        }
        
        // LIVE DATA ONLY - Show real volume history even if sparse
        // Chart will display actual blockchain activity, not simulated data
        
        // Sort by date ascending for charts (oldest first)
        volumeHistory = historyPoints.sorted { $0.date < $1.date }
    }
    
    /// Generate demo volume history for visualization
    private func generateDemoVolumeHistory() -> [VolumeDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        var points: [VolumeDataPoint] = []
        
        // Generate 24 hourly data points with realistic variation
        for hoursAgo in 0..<24 {
            let date = calendar.date(byAdding: .hour, value: -hoursAgo, to: now)!
            
            // Simulate higher activity during certain hours
            let hourOfDay = calendar.component(.hour, from: date)
            let activityMultiplier: Double
            
            // Higher activity during US trading hours (13:00-21:00 UTC / 8am-4pm EST)
            if hourOfDay >= 13 && hourOfDay <= 21 {
                activityMultiplier = Double.random(in: 1.2...2.0)
            } else if hourOfDay >= 1 && hourOfDay <= 8 {
                // Asian hours
                activityMultiplier = Double.random(in: 0.8...1.5)
            } else {
                activityMultiplier = Double.random(in: 0.5...1.0)
            }
            
            let baseVolume = Double.random(in: 2_000_000...15_000_000) * activityMultiplier
            let txCount = Int(Double.random(in: 3...15) * activityMultiplier)
            let inflowRatio = Double.random(in: 0.3...0.7)
            let inflow = baseVolume * inflowRatio
            let outflow = baseVolume * (1 - inflowRatio)
            
            points.append(VolumeDataPoint(
                date: date,
                volumeUSD: baseVolume,
                transactionCount: txCount,
                exchangeInflow: inflow,
                exchangeOutflow: outflow
            ))
        }
        
        return points
    }
    
    // MARK: - Smart Money Tracking
    
    /// Analyze transactions for smart money activity
    private func analyzeSmartMoneyActivity() {
        var signals: [SmartMoneySignal] = []
        
        for transaction in recentTransactions {
            // Check if from address is smart money
            if let smartWallet = KnownSmartMoneyWallets.wallet(for: transaction.fromAddress) {
                let signalType = determineSmartMoneySignalType(transaction: transaction, isFrom: true)
                let confidence = calculateSignalConfidence(transaction: transaction, wallet: smartWallet)
                
                signals.append(SmartMoneySignal(
                    wallet: smartWallet,
                    transaction: transaction,
                    signalType: signalType,
                    confidence: confidence,
                    timestamp: transaction.timestamp
                ))
            }
            
            // Check if to address is smart money
            if let smartWallet = KnownSmartMoneyWallets.wallet(for: transaction.toAddress) {
                let signalType = determineSmartMoneySignalType(transaction: transaction, isFrom: false)
                let confidence = calculateSignalConfidence(transaction: transaction, wallet: smartWallet)
                
                signals.append(SmartMoneySignal(
                    wallet: smartWallet,
                    transaction: transaction,
                    signalType: signalType,
                    confidence: confidence,
                    timestamp: transaction.timestamp
                ))
            }
        }
        
        // LIVE DATA ONLY - No demo signals for production
        // Smart money signals come only from real transactions matching known wallets
        
        // Sort by timestamp descending
        smartMoneySignals = signals.sorted { $0.timestamp > $1.timestamp }
        
        // Calculate smart money index
        calculateSmartMoneyIndex()
    }
    
    private func determineSmartMoneySignalType(transaction: WhaleTransaction, isFrom: Bool) -> SmartMoneySignal.SignalType {
        switch transaction.transactionType {
        case .exchangeDeposit:
            return isFrom ? .depositing : .accumulating
        case .exchangeWithdrawal:
            return isFrom ? .withdrawing : .accumulating
        case .transfer:
            return isFrom ? .distributing : .accumulating
        case .unknown:
            return .transferring
        }
    }
    
    private func calculateSignalConfidence(transaction: WhaleTransaction, wallet: SmartMoneyWallet) -> Double {
        var confidence: Double = 50.0
        
        // Higher confidence for larger transactions
        if transaction.amountUSD >= 10_000_000 {
            confidence += 25
        } else if transaction.amountUSD >= 5_000_000 {
            confidence += 15
        } else if transaction.amountUSD >= 1_000_000 {
            confidence += 10
        }
        
        // Higher confidence for wallets with good historical ROI
        if let roi = wallet.historicalROI, roi > 200 {
            confidence += 15
        } else if let roi = wallet.historicalROI, roi > 100 {
            confidence += 10
        }
        
        // Category-based confidence boost
        switch wallet.category {
        case .institutionalFund:
            confidence += 10
        case .defiWhale:
            confidence += 8
        case .earlyAdopter:
            confidence += 5
        default:
            break
        }
        
        return min(confidence, 95) // Cap at 95%
    }
    
    private func calculateSmartMoneyIndex() {
        let last24hSignals = smartMoneySignals.filter {
            Date().timeIntervalSince($0.timestamp) < 24 * 60 * 60
        }
        
        guard !last24hSignals.isEmpty else {
            smartMoneyIndex = SmartMoneyIndex(
                score: 50,
                trend: .neutral,
                bullishSignals: 0,
                bearishSignals: 0,
                neutralSignals: 0,
                lastUpdated: Date()
            )
            return
        }
        
        var bullishCount = 0
        var bearishCount = 0
        var neutralCount = 0
        var weightedScore: Double = 0
        var totalWeight: Double = 0
        
        for signal in last24hSignals {
            let weight = signal.confidence / 100.0
            
            switch signal.signalType.sentiment {
            case .bullish:
                bullishCount += 1
                weightedScore += 100 * weight
            case .bearish:
                bearishCount += 1
                weightedScore += 0 * weight
            case .neutral:
                neutralCount += 1
                weightedScore += 50 * weight
            }
            totalWeight += weight
        }
        
        let finalScore = totalWeight > 0 ? Int(weightedScore / totalWeight) : 50
        
        smartMoneyIndex = SmartMoneyIndex(
            score: finalScore,
            trend: SmartMoneyIndex.from(score: finalScore),
            bullishSignals: bullishCount,
            bearishSignals: bearishCount,
            neutralSignals: neutralCount,
            lastUpdated: Date()
        )
    }
    
    /// Generate demo smart money signals
    private func generateDemoSmartMoneySignals() -> [SmartMoneySignal] {
        var signals: [SmartMoneySignal] = []
        let now = Date()
        let knownWallets = KnownSmartMoneyWallets.wallets
        
        // Generate realistic demo signals with varied wallets
        // (walletIndex, minutesAgo, signalType, amountUSD, confidence)
        let signalData: [(Int, Int, SmartMoneySignal.SignalType, Double, Double)] = [
            // Recent signals - prioritize well-known names
            (0, 11, .accumulating, 2_500_000, 78),    // Jump Trading
            (1, 21, .withdrawing, 5_200_000, 85),     // Paradigm
            (5, 38, .accumulating, 3_800_000, 72),    // Polychain
            (10, 52, .distributing, 4_800_000, 68),   // Wintermute
            (15, 78, .withdrawing, 6_500_000, 91),    // Tetranode
            (18, 95, .accumulating, 4_200_000, 83),   // Andre Cronje
            // More signals - variety of funds and chains
            (6, 125, .depositing, 2_100_000, 65),     // Dragonfly
            (8, 180, .accumulating, 8_500_000, 92),   // Multicoin
            (23, 240, .withdrawing, 3_400_000, 74),   // Jump SOL
            (35, 300, .depositing, 3_100_000, 71),    // MicroStrategy
            (11, 380, .withdrawing, 4_700_000, 88),   // Amber Group
            (39, 450, .accumulating, 2_200_000, 76),  // Punk6529
        ]
        
        for (walletIndex, minutesAgo, signalType, amount, confidence) in signalData {
            let wallet = knownWallets[walletIndex % knownWallets.count]
            let timestamp = now.addingTimeInterval(-Double(minutesAgo * 60))
            
            let demoTx = WhaleTransaction(
                id: "smart_\(UUID().uuidString.prefix(8))",
                blockchain: wallet.blockchain,
                symbol: wallet.blockchain.symbol,
                amount: amount / 3300, // Rough conversion
                amountUSD: amount,
                fromAddress: signalType == .distributing || signalType == .depositing ? wallet.address : "Unknown",
                toAddress: signalType == .accumulating || signalType == .withdrawing ? wallet.address : "Unknown",
                hash: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(64)),
                timestamp: timestamp,
                transactionType: signalType == .depositing ? .exchangeDeposit : signalType == .withdrawing ? .exchangeWithdrawal : .transfer,
                dataSource: .demo
            )
            
            signals.append(SmartMoneySignal(
                wallet: wallet,
                transaction: demoTx,
                signalType: signalType,
                confidence: confidence,
                timestamp: timestamp
            ))
        }
        
        return signals
    }
    
    private func checkWatchedWalletActivity(transactions: [WhaleTransaction]) {
        for transaction in transactions {
            for wallet in watchedWallets where wallet.notifyOnActivity {
                let addressLower = wallet.address.lowercased()
                let isFromWallet = transaction.fromAddress.lowercased() == addressLower
                let isToWallet = transaction.toAddress.lowercased() == addressLower
                
                if (isFromWallet || isToWallet) && transaction.amountUSD >= wallet.minTransactionAmount {
                    // Notify delegate
                    alertDelegate?.didDetectWhaleMovement(
                        symbol: transaction.symbol,
                        amount: transaction.amountUSD,
                        fromAddress: transaction.fromAddress,
                        toAddress: transaction.toAddress
                    )
                    
                    // Update last activity
                    if let index = watchedWallets.firstIndex(where: { $0.id == wallet.id }) {
                        watchedWallets[index].lastActivity = transaction.timestamp
                    }
                }
            }
        }
        saveWatchedWallets()
    }
    
    // MARK: - Persistence
    
    private func loadCachedData() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([WhaleTransaction].self, from: data) {
            // Filter out stale cached transactions (older than 24 hours)
            let now = Date()
            let validCached = cached.filter {
                now.timeIntervalSince($0.timestamp) < 24 * 60 * 60
            }
            recentTransactions = validCached
            calculateStatistics()
            #if DEBUG
            print("[WhaleTrackingService] Loaded \(validCached.count) cached transactions (removed \(cached.count - validCached.count) stale)")
            #endif
        }
    }
    
    /// Cache transactions, merging with historical data to build up 24h history
    private func cacheTransactions() {
        // Load existing cached transactions
        var allTransactions = recentTransactions
        
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([WhaleTransaction].self, from: data) {
            // Merge: Add cached transactions that aren't in current set
            let currentHashes = Set(recentTransactions.map { deduplicationKey(for: $0) })
            let historicalTxs = cached.filter { !currentHashes.contains(deduplicationKey(for: $0)) }
            allTransactions.append(contentsOf: historicalTxs)
        }
        
        // Ensure merged list remains logically unique before windowing/sorting.
        allTransactions = deduplicateTransactions(allTransactions)
        
        // Filter to only keep last 24 hours
        let now = Date()
        let recent24h = allTransactions.filter {
            now.timeIntervalSince($0.timestamp) < 24 * 60 * 60
        }
        
        // Sort by timestamp (newest first) and limit to prevent unbounded growth
        let sorted = recent24h.sorted { $0.timestamp > $1.timestamp }
        let limited = Array(sorted.prefix(500)) // Max 500 transactions
        
        // Update recentTransactions to include historical data
        recentTransactions = limited
        
        if let data = try? JSONEncoder().encode(limited) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        
        #if DEBUG
        print("[WhaleTrackingService] Cached \(limited.count) transactions (24h window)")
        #endif
    }
    
    private func loadWatchedWallets() {
        if let data = UserDefaults.standard.data(forKey: watchedWalletsKey),
           let wallets = try? JSONDecoder().decode([WatchedWallet].self, from: data) {
            watchedWallets = wallets
        }
    }
    
    private func saveWatchedWallets() {
        if let data = try? JSONEncoder().encode(watchedWallets) {
            UserDefaults.standard.set(data, forKey: watchedWalletsKey)
        }
    }
    
    private func loadConfig() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let savedConfig = try? JSONDecoder().decode(WhaleAlertConfig.self, from: data) {
            config = savedConfig
        }
    }
    
    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }
}

// MARK: - API Response Models

/// Etherscan response wrapper that handles both success and error cases.
/// On success: status="1", result is an array of transactions
/// On error: status="0", result is a string with error message
private struct EtherscanResponse: Codable {
    let status: String
    let message: String
    let result: EtherscanResult
    
    /// Check if this is a successful response
    var isSuccess: Bool { status == "1" }
    
    /// Get transactions if this is a success response
    var transactions: [EtherscanTransaction] {
        if case .transactions(let txs) = result {
            return txs
        }
        return []
    }
    
    /// Get error message if this is an error response
    var errorMessage: String? {
        if case .error(let msg) = result {
            return msg
        }
        return nil
    }
}

/// Etherscan result can be either an array of transactions or a string error message
private enum EtherscanResult: Codable {
    case transactions([EtherscanTransaction])
    case error(String)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try to decode as array first (success case)
        if let transactions = try? container.decode([EtherscanTransaction].self) {
            self = .transactions(transactions)
            return
        }
        
        // Try to decode as string (error case)
        if let errorMessage = try? container.decode(String.self) {
            self = .error(errorMessage)
            return
        }
        
        // Default to empty transactions
        self = .transactions([])
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .transactions(let txs):
            try container.encode(txs)
        case .error(let msg):
            try container.encode(msg)
        }
    }
}

private struct EtherscanTransaction: Codable {
    let hash: String
    let from: String
    let to: String?
    let value: String
    let timeStamp: String
}

private struct BlockchainUnconfirmedResponse: Codable {
    let txs: [BlockchainTransaction]
}

private struct BlockchainTransaction: Codable {
    let hash: String
    let time: Int
    let inputs: [BlockchainInput]
    let out: [BlockchainOutput]
}

private struct BlockchainInput: Codable {
    let prev_out: BlockchainOutput?
}

private struct BlockchainOutput: Codable {
    let value: Int?
    let addr: String?
}

// MARK: - Solscan API Models

private struct SolscanTransaction: Codable {
    let txHash: String
    let blockTime: Int
    let lamport: Int?
    let signer: [String]
    let status: String?
    let fee: Int?
    
    enum CodingKeys: String, CodingKey {
        case txHash
        case blockTime
        case lamport
        case signer
        case status
        case fee
    }
}
