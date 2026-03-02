//
//  PredictionTradingService.swift
//  CryptoSage
//
//  Service for executing live trades on prediction market platforms.
//  Supports Polymarket (Polygon/USDC) and Kalshi (USD).
//
//  IMPORTANT: Live prediction market trading requires:
//  1. Connected wallet with USDC on Polygon (for Polymarket)
//  2. KYC verification (for Kalshi - US residents only)
//  3. Understanding of prediction market mechanics
//

import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

// MARK: - Live Prediction Trade

/// Represents a live prediction market trade
public struct LivePredictionTrade: Codable, Identifiable {
    public let id: String
    public let marketId: String
    public let marketTitle: String
    public let platform: String
    public let outcome: String           // "YES" or "NO"
    public let amount: Double            // Amount in USD/USDC
    public let price: Double             // Entry price (0.0 to 1.0)
    public let shares: Double            // Number of shares purchased
    public var status: TradeStatus       // Mutable for settlement updates
    public let createdAt: Date
    public var settledAt: Date?
    public var profit: Double?           // Profit/loss after settlement
    public var transactionHash: String?  // Blockchain tx hash (for Polymarket)
    
    public enum TradeStatus: String, Codable {
        case pending = "Pending"
        case active = "Active"
        case won = "Won"
        case lost = "Lost"
        case cancelled = "Cancelled"
        
        var color: String {
            switch self {
            case .pending: return "orange"
            case .active: return "blue"
            case .won: return "green"
            case .lost: return "red"
            case .cancelled: return "gray"
            }
        }
    }
    
    /// Potential profit if outcome wins
    var potentialProfit: Double {
        guard price > 0 && price < 1 else { return 0 }
        return (amount / price) - amount
    }
    
    /// Current value based on market price
    func currentValue(marketPrice: Double) -> Double {
        return shares * marketPrice
    }
}

// MARK: - Live Prediction Bot

/// Represents a live prediction market trading bot
public struct LivePredictionBot: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public let platform: String
    public let marketId: String
    public let marketTitle: String
    public let outcome: String
    public let targetPrice: Double
    public let betAmount: Double
    public var status: BotStatus
    public var isEnabled: Bool
    public let createdAt: Date
    public var lastTradeAt: Date?
    public var trades: [LivePredictionTrade]
    public var totalInvested: Double
    public var totalProfit: Double
    
    public enum BotStatus: String, Codable {
        case idle = "Idle"
        case monitoring = "Monitoring"
        case trading = "Trading"
        case completed = "Completed"
        case error = "Error"
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        platform: String,
        marketId: String,
        marketTitle: String,
        outcome: String,
        targetPrice: Double,
        betAmount: Double,
        status: BotStatus = .idle,
        isEnabled: Bool = false,
        createdAt: Date = Date(),
        lastTradeAt: Date? = nil,
        trades: [LivePredictionTrade] = [],
        totalInvested: Double = 0,
        totalProfit: Double = 0
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.marketId = marketId
        self.marketTitle = marketTitle
        self.outcome = outcome
        self.targetPrice = targetPrice
        self.betAmount = betAmount
        self.status = status
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastTradeAt = lastTradeAt
        self.trades = trades
        self.totalInvested = totalInvested
        self.totalProfit = totalProfit
    }
}

// MARK: - Polymarket Order Request

/// Order request for Polymarket CLOB API
private struct PolymarketOrderRequest: Codable {
    let tokenID: String
    let price: Double
    let size: Double
    let side: String      // "BUY" or "SELL"
    let feeRateBps: Int
    let nonce: Int
    let signature: String
}

/// Order response from Polymarket
private struct PolymarketOrderResponse: Codable {
    let id: String?
    let status: String?
    let error: String?
}

// MARK: - Prediction Trading Service

/// Service for executing live prediction market trades
@MainActor
public final class PredictionTradingService: ObservableObject {
    public static let shared = PredictionTradingService()
    
    // MARK: - Published State
    
    @Published public var liveBots: [LivePredictionBot] = []
    @Published public var activeTrades: [LivePredictionTrade] = []
    @Published public var isLoading: Bool = false
    @Published public var lastError: String?
    @Published public var isWalletConnected: Bool = false
    @Published public var walletAddress: String?
    @Published public var usdcBalance: Double = 0
    
    // MARK: - Configuration
    
    private let polymarketAPIBase = "https://clob.polymarket.com"
    private let kalshiAPIBase = "https://trading-api.kalshi.com/trade-api/v2"
    
    // Storage keys
    private static let botsKey = "live_prediction_bots"
    private static let tradesKey = "live_prediction_trades"
    
    // Session
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()
    
    private init() {
        loadBots()
        loadTrades()
        checkWalletConnection()
    }
    
    // MARK: - Wallet Connection
    
    /// Check if wallet is connected via WalletConnect
    private func checkWalletConnection() {
        let walletService = WalletConnectService.shared
        isWalletConnected = walletService.isConnected
        walletAddress = walletService.connectedAccount?.address
        
        // Listen for wallet connection changes
        NotificationCenter.default.addObserver(
            forName: .walletConnectionChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self = self else { return }
                let connected = notification.userInfo?["connected"] as? Bool ?? false
                self.isWalletConnected = connected
                if connected {
                    self.walletAddress = notification.userInfo?["address"] as? String
                    Task { await self.fetchUSDCBalance() }
                } else {
                    self.walletAddress = nil
                    self.usdcBalance = 0
                }
            }
        }
    }
    
    /// Fetch USDC balance on Polygon
    public func fetchUSDCBalance() async {
        guard let address = walletAddress else { return }
        
        // USDC contract on Polygon
        let usdcContract = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"
        
        // Use Polygon RPC to get balance
        guard let url = URL(string: "https://polygon-rpc.com") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // balanceOf(address) function call
        let data: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_call",
            "params": [
                [
                    "to": usdcContract,
                    "data": "0x70a08231000000000000000000000000\(address.dropFirst(2))"
                ],
                "latest"
            ],
            "id": 1
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: data)
            let (responseData, _) = try await session.data(for: request)
            
            if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let result = json["result"] as? String {
                // Convert hex to decimal (USDC has 6 decimals)
                if let balance = UInt64(result.dropFirst(2), radix: 16) {
                    usdcBalance = Double(balance) / 1_000_000
                }
            }
        } catch {
            #if DEBUG
            print("[PredictionTradingService] Failed to fetch USDC balance: \(error)")
            #endif
        }
    }
    
    // MARK: - Live Bot Management
    
    /// Create a live prediction bot
    @discardableResult
    public func createLiveBot(
        name: String,
        platform: String,
        marketId: String,
        marketTitle: String,
        outcome: String,
        targetPrice: Double,
        betAmount: Double
    ) -> LivePredictionBot {
        let bot = LivePredictionBot(
            name: name.isEmpty ? "Prediction Bot" : name,
            platform: platform,
            marketId: marketId,
            marketTitle: marketTitle,
            outcome: outcome,
            targetPrice: targetPrice,
            betAmount: betAmount
        )
        
        liveBots.insert(bot, at: 0)
        saveBots()
        
        return bot
    }
    
    /// Enable (start) a live bot
    public func enableBot(id: UUID) async {
        guard var bot = liveBots.first(where: { $0.id == id }) else { return }
        guard isWalletConnected else {
            lastError = "Please connect your wallet first"
            return
        }
        guard usdcBalance >= bot.betAmount else {
            lastError = "Insufficient USDC balance. You have $\(String(format: "%.2f", usdcBalance)) but need $\(String(format: "%.2f", bot.betAmount))"
            return
        }
        
        bot.isEnabled = true
        bot.status = .monitoring
        updateBot(bot)
        
        // Start monitoring the market
        Task {
            await monitorAndTrade(bot: bot)
        }
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    
    /// Disable (stop) a live bot
    public func disableBot(id: UUID) {
        guard var bot = liveBots.first(where: { $0.id == id }) else { return }
        
        bot.isEnabled = false
        bot.status = .idle
        updateBot(bot)
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    
    /// Update a bot
    public func updateBot(_ bot: LivePredictionBot) {
        if let index = liveBots.firstIndex(where: { $0.id == bot.id }) {
            liveBots[index] = bot
            saveBots()
        }
    }
    
    /// Delete a bot
    public func deleteBot(id: UUID) {
        disableBot(id: id)
        liveBots.removeAll { $0.id == id }
        saveBots()
    }
    
    // MARK: - Trading Logic
    
    /// Monitor market and execute trade when conditions are met
    private func monitorAndTrade(bot: LivePredictionBot) async {
        var currentBot = bot
        
        while currentBot.isEnabled {
            // Fetch current market price
            let currentPrice = await fetchMarketPrice(
                marketId: bot.marketId,
                platform: bot.platform,
                outcome: bot.outcome
            )
            
            // Check if we should execute
            if shouldExecuteTrade(bot: currentBot, currentPrice: currentPrice) {
                currentBot.status = .trading
                updateBot(currentBot)
                
                // Execute the trade
                let trade = await executeTrade(bot: currentBot, price: currentPrice)
                
                if let trade = trade {
                    currentBot.trades.append(trade)
                    currentBot.totalInvested += trade.amount
                    currentBot.lastTradeAt = Date()
                    currentBot.status = .completed
                    currentBot.isEnabled = false
                    activeTrades.append(trade)
                    saveTrades()
                } else {
                    currentBot.status = .error
                }
                
                updateBot(currentBot)
                break
            }
            
            // Refresh bot from storage in case it was disabled
            if let updated = liveBots.first(where: { $0.id == bot.id }) {
                currentBot = updated
            }
            
            // Wait before next check (30 seconds)
            try? await Task.sleep(nanoseconds: 30_000_000_000)
        }
    }
    
    /// Determine if trade should be executed
    private func shouldExecuteTrade(bot: LivePredictionBot, currentPrice: Double) -> Bool {
        // Execute if current price is at or below target price (good entry)
        return currentPrice > 0 && currentPrice <= bot.targetPrice
    }
    
    /// Fetch current market price from platform API
    private func fetchMarketPrice(marketId: String, platform: String, outcome: String) async -> Double {
        // For now, use cached data from PredictionMarketService
        if let market = PredictionMarketService.shared.getMarket(id: marketId) {
            return outcome == "YES" ? (market.yesPrice ?? 0.5) : (market.noPrice ?? 0.5)
        }
        return 0.5
    }
    
    /// Execute a trade on the prediction market
    private func executeTrade(bot: LivePredictionBot, price: Double) async -> LivePredictionTrade? {
        // SAFETY: Block live trading when disabled at app config level
        guard AppConfig.liveTradingEnabled else {
            lastError = AppConfig.liveTradingDisabledMessage
            #if DEBUG
            print("[PredictionTradingService] Live trading disabled - trade blocked")
            #endif
            return nil
        }
        
        guard isWalletConnected, let address = walletAddress else {
            lastError = "Wallet not connected"
            return nil
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            if bot.platform.lowercased().contains("polymarket") {
                return try await executePolymarketTrade(bot: bot, price: price, address: address)
            } else if bot.platform.lowercased().contains("kalshi") {
                return try await executeKalshiTrade(bot: bot, price: price)
            }
        } catch {
            lastError = "Trade failed: \(error.localizedDescription)"
            #if DEBUG
            print("[PredictionTradingService] Trade execution error: \(error)")
            #endif
        }
        
        return nil
    }
    
    /// Execute trade on Polymarket
    private func executePolymarketTrade(bot: LivePredictionBot, price: Double, address: String) async throws -> LivePredictionTrade {
        // Polymarket uses a CLOB (Central Limit Order Book) system
        // Orders require signatures from the connected wallet
        
        guard price > 0 else { throw PredictionTradingError.invalidPrice }
        let shares = bot.betAmount / price
        
        // Build order request
        guard let url = URL(string: "\(polymarketAPIBase)/order") else {
            throw PredictionTradingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(address, forHTTPHeaderField: "X-Wallet-Address")
        
        // In production, you would:
        // 1. Get the token ID for the outcome
        // 2. Sign the order with WalletConnect
        // 3. Submit to the CLOB API
        
        // For now, create a pending trade that would be confirmed
        let trade = LivePredictionTrade(
            id: UUID().uuidString,
            marketId: bot.marketId,
            marketTitle: bot.marketTitle,
            platform: bot.platform,
            outcome: bot.outcome,
            amount: bot.betAmount,
            price: price,
            shares: shares,
            status: .pending,
            createdAt: Date(),
            settledAt: nil,
            profit: nil,
            transactionHash: nil
        )
        
        // NOTE: In production, this would await wallet signature and blockchain confirmation
        // The actual flow would be:
        // 1. Call WalletConnectService.shared.signTransaction()
        // 2. Submit signed order to Polymarket CLOB
        // 3. Wait for order fill confirmation
        // 4. Update trade status
        
        return trade
    }
    
    /// Execute trade on Kalshi
    private func executeKalshiTrade(bot: LivePredictionBot, price: Double) async throws -> LivePredictionTrade {
        // Kalshi requires API key authentication
        // and KYC verification for US residents
        
        guard price > 0 else { throw PredictionTradingError.invalidPrice }
        let shares = Int(bot.betAmount / price)
        
        // In production, you would:
        // 1. Authenticate with Kalshi API (requires email/password or API key)
        // 2. Submit order via POST /markets/{ticker}/orders
        // 3. Handle order confirmation
        
        let trade = LivePredictionTrade(
            id: UUID().uuidString,
            marketId: bot.marketId,
            marketTitle: bot.marketTitle,
            platform: bot.platform,
            outcome: bot.outcome,
            amount: bot.betAmount,
            price: price,
            shares: Double(shares),
            status: .pending,
            createdAt: Date(),
            settledAt: nil,
            profit: nil,
            transactionHash: nil
        )
        
        return trade
    }
    
    // MARK: - Trade Management
    
    /// Get all trades for a specific market
    public func trades(for marketId: String) -> [LivePredictionTrade] {
        activeTrades.filter { $0.marketId == marketId }
    }
    
    /// Get total P/L across all trades
    public var totalProfitLoss: Double {
        activeTrades.compactMap { $0.profit }.reduce(0, +)
    }
    
    /// Update trade status (called when market settles)
    public func settleTradeResult(tradeId: String, won: Bool) {
        guard var trade = activeTrades.first(where: { $0.id == tradeId }) else { return }
        
        trade.status = won ? .won : .lost
        trade.settledAt = Date()
        trade.profit = won ? trade.potentialProfit : -trade.amount
        
        if let index = activeTrades.firstIndex(where: { $0.id == tradeId }) {
            activeTrades[index] = trade
            saveTrades()
        }
        
        // Update associated bot
        if var bot = liveBots.first(where: { $0.trades.contains(where: { $0.id == tradeId }) }) {
            if let tradeIndex = bot.trades.firstIndex(where: { $0.id == tradeId }) {
                bot.trades[tradeIndex] = trade
                bot.totalProfit += trade.profit ?? 0
                updateBot(bot)
            }
        }
    }
    
    // MARK: - Persistence
    
    private func loadBots() {
        guard let data = UserDefaults.standard.data(forKey: Self.botsKey) else { return }
        do {
            liveBots = try JSONDecoder().decode([LivePredictionBot].self, from: data)
        } catch {
            #if DEBUG
            print("[PredictionTradingService] Failed to load bots: \(error)")
            #endif
        }
    }
    
    private func saveBots() {
        do {
            let data = try JSONEncoder().encode(liveBots)
            UserDefaults.standard.set(data, forKey: Self.botsKey)
        } catch {
            #if DEBUG
            print("[PredictionTradingService] Failed to save bots: \(error)")
            #endif
        }
    }
    
    private func loadTrades() {
        guard let data = UserDefaults.standard.data(forKey: Self.tradesKey) else { return }
        do {
            activeTrades = try JSONDecoder().decode([LivePredictionTrade].self, from: data)
        } catch {
            #if DEBUG
            print("[PredictionTradingService] Failed to load trades: \(error)")
            #endif
        }
    }
    
    private func saveTrades() {
        do {
            let data = try JSONEncoder().encode(activeTrades)
            UserDefaults.standard.set(data, forKey: Self.tradesKey)
        } catch {
            #if DEBUG
            print("[PredictionTradingService] Failed to save trades: \(error)")
            #endif
        }
    }
}

// MARK: - Errors

public enum PredictionTradingError: LocalizedError {
    case invalidURL
    case invalidPrice
    case notAuthenticated
    case insufficientBalance
    case walletNotConnected
    case orderFailed(String)
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidPrice:
            return "Invalid price (must be greater than zero)"
        case .notAuthenticated:
            return "Not authenticated with prediction market platform"
        case .insufficientBalance:
            return "Insufficient balance to place order"
        case .walletNotConnected:
            return "Wallet not connected. Please connect via WalletConnect"
        case .orderFailed(let reason):
            return "Order failed: \(reason)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let walletConnectionChanged = Notification.Name("walletConnectionChanged")
    static let predictionTradeExecuted = Notification.Name("predictionTradeExecuted")
    static let predictionMarketSettled = Notification.Name("predictionMarketSettled")
}
