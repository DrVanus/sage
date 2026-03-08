//
//  AgentConnectionService.swift
//  CryptoSage
//
//  Manages AI agent connections — API key lifecycle, real-time Firestore
//  listeners for agent data (portfolio, trades, signals, status).
//

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseFunctions
import Combine

// MARK: - Agent Configuration (eliminates hardcoded values)

enum AgentConfig {
    static let defaultAgentName = "Sage Trader"
    static let defaultAgentDocId = "sage-trader"
    static let portfolioCollection = "agentPortfolio"
    static let tradesCollection = "agentTrades"
    static let signalsCollection = "agentSignals"
    static let statusCollection = "agentStatus"
    /// How long before we consider the agent offline (seconds)
    static let onlineThreshold: TimeInterval = 3 * 60  // 3 minutes
    static let maxRecentTrades = 20
    static let maxRecentSignals = 10

    /// Normalizes a symbol to the "-USD" pair format used locally
    static func normalizeSymbol(_ symbol: String) -> String {
        if symbol.contains("-") || symbol.contains("/") { return symbol.replacingOccurrences(of: "/", with: "-") }
        return "\(symbol)-USD"
    }
}

// MARK: - Agent Data Models

struct AgentApiKeyInfo: Identifiable, Codable {
    var id: String
    let keyPrefix: String
    let name: String
    let isActive: Bool
    let permissions: [String]
    let createdAt: String?
    let lastUsedAt: String?
}

struct AgentPortfolio: Codable {
    let balance_usd: Double
    let positions: [String: Double]
    let total_value_usd: Double
    let strategy: String
    let agent_name: String
    let updated_at: Date?

    var positionCount: Int { positions.count }
    var cryptoValue: Double { total_value_usd - balance_usd }
}

struct AgentTrade: Identifiable, Codable {
    let id: String
    let timestamp: Date?
    let action: String
    let symbol: String
    let quantity: Double
    let price: Double
    let usd_amount: Double
    let reason: String
    let composite_score: Double?
    let fear_greed: Double?
    let confidence: String?
    let paper: Bool
    let agent_name: String

    var isBuy: Bool { action.uppercased() == "BUY" }
}

struct AgentSignal: Identifiable, Codable {
    let id: String
    let timestamp: Date?
    let symbol: String
    let signal: String
    let composite_score: Double
    let fear_greed_index: Double?
    let fear_greed_category: String?
    let rsi: Double?
    let macd_trend: String?
    let primary_trend: String?
    let confidence: String?
    let risk_score: Double?
    let reasoning: String?
    let agent_name: String

    var signalColor: Color {
        switch signal.lowercased() {
        case "strong_buy", "strongbuy": return .green
        case "buy": return .green.opacity(0.8)
        case "sell": return .red.opacity(0.8)
        case "strong_sell", "strongsell": return .red
        default: return .gray
        }
    }

    var signalDisplayName: String {
        switch signal.lowercased() {
        case "strong_buy", "strongbuy": return "Strong Buy"
        case "buy": return "Buy"
        case "sell": return "Sell"
        case "strong_sell", "strongsell": return "Strong Sell"
        case "hold": return "Hold"
        default: return signal.capitalized
        }
    }
}

struct AgentStatus: Codable {
    let last_heartbeat: Date?
    let status: String
    let daily_pnl: Double?
    let open_positions: Int?
    let note: String?
    let circuit_breaker_active: Bool
    let agent_name: String
    let session_count: Int?

    var isOnline: Bool {
        guard let heartbeat = last_heartbeat else { return false }
        return Date().timeIntervalSince(heartbeat) < AgentConfig.onlineThreshold
    }

    var statusDisplayName: String {
        if !isOnline { return "Offline" }
        if circuit_breaker_active { return "Circuit Breaker" }
        return status.capitalized
    }

    var statusColor: Color {
        if !isOnline { return .gray }
        if circuit_breaker_active { return .orange }
        switch status.lowercased() {
        case "active": return .green
        case "paused": return .yellow
        case "error": return .red
        default: return .gray
        }
    }
}

// MARK: - Agent Connection Service

@MainActor
class AgentConnectionService: ObservableObject {
    static let shared = AgentConnectionService()

    // Published state
    @Published var apiKeys: [AgentApiKeyInfo] = []
    @Published var portfolio: AgentPortfolio?
    @Published var recentTrades: [AgentTrade] = []
    @Published var latestSignals: [AgentSignal] = []
    @Published var agentStatus: AgentStatus?
    @Published var isLoading = false
    @Published var error: String?
    /// Cached count of today's trades (updated when recentTrades changes)
    @Published private(set) var todayTradeCount: Int = 0

    // Computed
    var isConnected: Bool { !apiKeys.filter(\.isActive).isEmpty }
    var hasAgent: Bool { agentStatus != nil }
    var isAgentOnline: Bool { agentStatus?.isOnline ?? false }

    private let functions = Functions.functions()
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var heartbeatTimer: Timer?

    // MARK: - Local API Key Cache (for instant UI)
    private static let apiKeyCacheKey = "CryptoSage.cachedAgentApiKeys"

    private func loadCachedApiKeys() {
        guard let data = UserDefaults.standard.data(forKey: Self.apiKeyCacheKey),
              let cached = try? JSONDecoder().decode([AgentApiKeyInfo].self, from: data),
              !cached.isEmpty else { return }
        apiKeys = cached
    }

    private func cacheApiKeys() {
        guard let data = try? JSONEncoder().encode(apiKeys) else { return }
        UserDefaults.standard.set(data, forKey: Self.apiKeyCacheKey)
    }

    private init() {
        loadCachedApiKeys()
    }

    // MARK: - API Key Management

    func generateApiKey(name: String) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        do {
            let callable = functions.httpsCallable("generateAgentApiKey")
            let result = try await callable.call(["name": name])

            guard let data = result.data as? [String: Any],
                  let apiKey = data["apiKey"] as? String else {
                throw NSError(domain: "AgentAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])
            }

            // Refresh key list
            try await loadApiKeys()

            return apiKey
        } catch let error as NSError {
            let desc = error.localizedDescription.lowercased()

            // Firebase Functions "NOT_FOUND" means the Cloud Function isn't deployed yet
            // IMPORTANT: Only match NOT_FOUND, not all Firebase Functions errors —
            // auth errors etc. should show their real message, not "not deployed".
            if desc.contains("not found") || desc.contains("not_found") || error.code == 5 /* NOT_FOUND */ {
                throw NSError(domain: "AgentAPI", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Agent API functions are not deployed yet. Deploy Firebase Cloud Functions first:\n\ncd firebase/functions && npm run deploy"
                ])
            }

            // Unauthenticated — user needs to sign in
            if desc.contains("unauthenticated") || desc.contains("not authenticated") || error.code == 16 {
                throw NSError(domain: "AgentAPI", code: -3, userInfo: [
                    NSLocalizedDescriptionKey: "Sign in to your CryptoSage account to connect an AI agent."
                ])
            }

            // UNAVAILABLE — Firebase Functions backend is unreachable
            if desc.contains("unavailable") || error.code == 14 {
                throw NSError(domain: "AgentAPI", code: -4, userInfo: [
                    NSLocalizedDescriptionKey: "Agent API is temporarily unavailable. Check your internet connection or try again later.\n\nIf this persists, redeploy Cloud Functions:\ncd firebase/functions && npm run deploy"
                ])
            }

            throw error
        }
    }

    func loadApiKeys() async throws {
        do {
            let callable = functions.httpsCallable("listAgentApiKeys")
            let result = try await callable.call([:])

            guard let data = result.data as? [String: Any],
                  let keysArray = data["keys"] as? [[String: Any]] else {
                return
            }

            apiKeys = keysArray.compactMap { dict in
                guard let id = dict["id"] as? String,
                      let keyPrefix = dict["keyPrefix"] as? String,
                      let name = dict["name"] as? String else { return nil }
                return AgentApiKeyInfo(
                    id: id,
                    keyPrefix: keyPrefix,
                    name: name,
                    isActive: dict["isActive"] as? Bool ?? false,
                    permissions: dict["permissions"] as? [String] ?? [],
                    createdAt: dict["createdAt"] as? String,
                    lastUsedAt: dict["lastUsedAt"] as? String
                )
            }
            cacheApiKeys()
        } catch {
            // Silently handle NOT_FOUND — Cloud Functions not deployed yet
            let desc = error.localizedDescription.lowercased()
            if desc.contains("not found") || desc.contains("not_found") {
                #if DEBUG
                print("[AgentConnectionService] Cloud Functions not deployed — skipping loadApiKeys")
                #endif
                return
            }
            throw error
        }
    }

    func revokeApiKey(keyId: String) async throws {
        let callable = functions.httpsCallable("revokeAgentApiKey")
        _ = try await callable.call(["keyId": keyId])
        try await loadApiKeys()
    }

    // MARK: - Firestore Listeners

    func startListening(userId: String) {
        stopListening()

        // Portfolio listener
        let portfolioRef = db.collection("users").document(userId)
            .collection(AgentConfig.portfolioCollection).document(AgentConfig.defaultAgentDocId)
        listeners.append(portfolioRef.addSnapshotListener { [weak self] snapshot, error in
            guard let data = snapshot?.data() else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.portfolio = AgentPortfolio(
                    balance_usd: data["balance_usd"] as? Double ?? 0,
                    positions: data["positions"] as? [String: Double] ?? [:],
                    total_value_usd: data["total_value_usd"] as? Double ?? 0,
                    strategy: data["strategy"] as? String ?? "Unknown",
                    agent_name: data["agent_name"] as? String ?? AgentConfig.defaultAgentName,
                    updated_at: (data["updated_at"] as? Timestamp)?.dateValue()
                )
            }
        })

        // Recent trades listener
        let tradesRef = db.collection("users").document(userId)
            .collection(AgentConfig.tradesCollection)
            .order(by: "timestamp", descending: true)
            .limit(to: AgentConfig.maxRecentTrades)
        listeners.append(tradesRef.addSnapshotListener { [weak self] snapshot, error in
            guard let docs = snapshot?.documents else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let trades = docs.compactMap { doc -> AgentTrade? in
                    let data = doc.data()
                    return AgentTrade(
                        id: doc.documentID,
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue(),
                        action: data["action"] as? String ?? "",
                        symbol: data["symbol"] as? String ?? "",
                        quantity: data["quantity"] as? Double ?? 0,
                        price: data["price"] as? Double ?? 0,
                        usd_amount: data["usd_amount"] as? Double ?? 0,
                        reason: data["reason"] as? String ?? "",
                        composite_score: data["composite_score"] as? Double,
                        fear_greed: data["fear_greed"] as? Double,
                        confidence: data["confidence"] as? String,
                        paper: data["paper"] as? Bool ?? true,
                        agent_name: data["agent_name"] as? String ?? AgentConfig.defaultAgentName
                    )
                }
                self.recentTrades = trades
                self.updateTodayTradeCount()

                // Execute new agent trades in local paper trading
                self.executeAgentTradesLocally(trades)
            }
        })

        // Signals listener
        let signalsRef = db.collection("users").document(userId)
            .collection(AgentConfig.signalsCollection)
            .order(by: "timestamp", descending: true)
            .limit(to: AgentConfig.maxRecentSignals)
        listeners.append(signalsRef.addSnapshotListener { [weak self] snapshot, error in
            guard let docs = snapshot?.documents else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.latestSignals = docs.compactMap { doc in
                    let data = doc.data()
                    return AgentSignal(
                        id: doc.documentID,
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue(),
                        symbol: data["symbol"] as? String ?? "",
                        signal: data["signal"] as? String ?? "hold",
                        composite_score: data["composite_score"] as? Double ?? 50,
                        fear_greed_index: data["fear_greed_index"] as? Double,
                        fear_greed_category: data["fear_greed_category"] as? String,
                        rsi: data["rsi"] as? Double,
                        macd_trend: data["macd_trend"] as? String,
                        primary_trend: data["primary_trend"] as? String,
                        confidence: data["confidence"] as? String,
                        risk_score: data["risk_score"] as? Double,
                        reasoning: data["reasoning"] as? String,
                        agent_name: data["agent_name"] as? String ?? AgentConfig.defaultAgentName
                    )
                }
            }
        })

        // Agent status listener
        let statusRef = db.collection("users").document(userId)
            .collection(AgentConfig.statusCollection).document(AgentConfig.defaultAgentDocId)
        listeners.append(statusRef.addSnapshotListener { [weak self] snapshot, error in
            guard let data = snapshot?.data() else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.agentStatus = AgentStatus(
                    last_heartbeat: (data["last_heartbeat"] as? Timestamp)?.dateValue(),
                    status: data["status"] as? String ?? "unknown",
                    daily_pnl: data["daily_pnl"] as? Double,
                    open_positions: data["open_positions"] as? Int,
                    note: data["note"] as? String,
                    circuit_breaker_active: data["circuit_breaker_active"] as? Bool ?? false,
                    agent_name: data["agent_name"] as? String ?? AgentConfig.defaultAgentName,
                    session_count: data["session_count"] as? Int
                )
            }
        })

        // Start heartbeat timer to re-evaluate isOnline periodically
        startHeartbeatTimer()
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Heartbeat Timer

    /// Periodically triggers objectWillChange so views re-evaluate isOnline/statusColor
    private func startHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Force views to re-check computed isOnline property
                self.objectWillChange.send()
            }
        }
    }

    // MARK: - Today Trade Count Cache

    private func updateTodayTradeCount() {
        let calendar = Calendar.current
        todayTradeCount = recentTrades.filter { trade in
            guard let ts = trade.timestamp else { return false }
            return calendar.isDateInToday(ts)
        }.count
    }

    // MARK: - Send Command to Agent

    func sendCommand(userId: String, type: String, payload: [String: Any] = [:]) async throws {
        try await db.collection("users").document(userId)
            .collection("agentCommands").addDocument(data: [
                "type": type,
                "payload": payload,
                "status": "pending",
                "created_at": FieldValue.serverTimestamp(),
            ])
    }

    // MARK: - Agent Paper Trade Execution Bridge

    /// Tracks trade IDs we've already executed locally to avoid duplicates
    private var executedTradeIds: Set<String> = []

    /// Called when the trades listener receives new documents.
    /// Executes agent trades in the local PaperTradingManager so
    /// the app's paper trading balances stay in sync with the agent.
    private func executeAgentTradesLocally(_ trades: [AgentTrade]) {
        let paperManager = PaperTradingManager.shared

        for trade in trades {
            // Skip if already executed or not a paper trade
            guard trade.paper, !executedTradeIds.contains(trade.id) else { continue }

            // Only process trades from the last 5 minutes (avoid replaying old history)
            if let ts = trade.timestamp, Date().timeIntervalSince(ts) > 300 { continue }

            let side: TradeSide = trade.isBuy ? .buy : .sell
            let symbol = AgentConfig.normalizeSymbol(trade.symbol)

            let result = paperManager.executePaperTrade(
                symbol: symbol,
                side: side,
                quantity: trade.quantity,
                price: trade.price,
                orderType: "MARKET"
            )

            if result.success {
                executedTradeIds.insert(trade.id)
                #if DEBUG
                print("[AgentBridge] Executed agent paper trade: \(trade.action) \(trade.quantity) \(trade.symbol) @ $\(String(format: "%.2f", trade.price))")
                #endif
            } else {
                #if DEBUG
                print("[AgentBridge] Failed to execute agent paper trade: \(result.errorMessage ?? "unknown")")
                #endif
            }
        }

        // Keep executedTradeIds from growing unbounded
        if executedTradeIds.count > 200 {
            executedTradeIds = Set(executedTradeIds.suffix(100))
        }
    }
}
