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
        return Date().timeIntervalSince(heartbeat) < 30 * 60 // 30 minutes
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

    // Computed
    var isConnected: Bool { !apiKeys.filter(\.isActive).isEmpty }
    var hasAgent: Bool { agentStatus != nil }
    var isAgentOnline: Bool { agentStatus?.isOnline ?? false }

    private let functions = Functions.functions()
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    private init() {}

    // MARK: - API Key Management

    func generateApiKey(name: String) async throws -> String {
        isLoading = true
        defer { isLoading = false }

        let callable = functions.httpsCallable("generateAgentApiKey")
        let result = try await callable.call(["name": name])

        guard let data = result.data as? [String: Any],
              let apiKey = data["apiKey"] as? String else {
            throw NSError(domain: "AgentAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        // Refresh key list
        try await loadApiKeys()

        return apiKey
    }

    func loadApiKeys() async throws {
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
            .collection("agentPortfolio").document("sage-trader")
        listeners.append(portfolioRef.addSnapshotListener { [weak self] snapshot, error in
            guard let data = snapshot?.data() else { return }
            Task { @MainActor in
                self?.portfolio = AgentPortfolio(
                    balance_usd: data["balance_usd"] as? Double ?? 0,
                    positions: data["positions"] as? [String: Double] ?? [:],
                    total_value_usd: data["total_value_usd"] as? Double ?? 0,
                    strategy: data["strategy"] as? String ?? "Unknown",
                    agent_name: data["agent_name"] as? String ?? "Agent",
                    updated_at: (data["updated_at"] as? Timestamp)?.dateValue()
                )
            }
        })

        // Recent trades listener (last 20)
        let tradesRef = db.collection("users").document(userId)
            .collection("agentTrades")
            .order(by: "timestamp", descending: true)
            .limit(to: 20)
        listeners.append(tradesRef.addSnapshotListener { [weak self] snapshot, error in
            guard let docs = snapshot?.documents else { return }
            Task { @MainActor in
                self?.recentTrades = docs.compactMap { doc in
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
                        agent_name: data["agent_name"] as? String ?? "Agent"
                    )
                }
            }
        })

        // Signals listener (last 10)
        let signalsRef = db.collection("users").document(userId)
            .collection("agentSignals")
            .order(by: "timestamp", descending: true)
            .limit(to: 10)
        listeners.append(signalsRef.addSnapshotListener { [weak self] snapshot, error in
            guard let docs = snapshot?.documents else { return }
            Task { @MainActor in
                self?.latestSignals = docs.compactMap { doc in
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
                        agent_name: data["agent_name"] as? String ?? "Agent"
                    )
                }
            }
        })

        // Agent status listener
        let statusRef = db.collection("users").document(userId)
            .collection("agentStatus").document("sage-trader")
        listeners.append(statusRef.addSnapshotListener { [weak self] snapshot, error in
            guard let data = snapshot?.data() else { return }
            Task { @MainActor in
                self?.agentStatus = AgentStatus(
                    last_heartbeat: (data["last_heartbeat"] as? Timestamp)?.dateValue(),
                    status: data["status"] as? String ?? "unknown",
                    daily_pnl: data["daily_pnl"] as? Double,
                    open_positions: data["open_positions"] as? Int,
                    note: data["note"] as? String,
                    circuit_breaker_active: data["circuit_breaker_active"] as? Bool ?? false,
                    agent_name: data["agent_name"] as? String ?? "Agent",
                    session_count: data["session_count"] as? Int
                )
            }
        })
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
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
}
