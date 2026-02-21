//
//  ThreeCommasModels.swift
//  CryptoSage
//
//  Models for 3Commas API responses including accounts, balances, and trading bots.
//

import Foundation
import SwiftUI

/// Represents a 3Commas account entry returned by the accounts endpoint.
struct Account: Decodable {
    /// Unique identifier for the account.
    let id: Int
    /// Human-readable name of the account (if provided).
    let name: String?
    /// Currency code (e.g. "BTC", "ETH").
    let currency: String?
}

/// Represents a balance entry for a specific currency within an account.
struct AccountBalance: Decodable {
    /// The currency code (e.g. "BTC", "USDT").
    let currency: String
    /// The available balance for that currency.
    let balance: Double
}

// MARK: - 3Commas Bot Models

/// Status of a 3Commas trading bot
public enum ThreeCommasBotStatus: String, Codable {
    case enabled = "enabled"
    case disabled = "disabled"
    case paused = "paused"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .enabled: return "Running"
        case .disabled: return "Stopped"
        case .paused: return "Paused"
        case .unknown: return "Unknown"
        }
    }
    
    var color: Color {
        switch self {
        case .enabled: return .green
        case .disabled: return .red
        case .paused: return .orange
        case .unknown: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .enabled: return "play.circle.fill"
        case .disabled: return "stop.circle.fill"
        case .paused: return "pause.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self).lowercased()
        self = ThreeCommasBotStatus(rawValue: value) ?? .unknown
    }
}

/// Type of 3Commas bot strategy
public enum ThreeCommasBotType: String, Codable {
    case simple = "simple"
    case composite = "composite"
    case switchBot = "switch"
    case gordon = "gordon"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .simple: return "DCA Bot"
        case .composite: return "Multi-pair Bot"
        case .switchBot: return "Smart Trade"
        case .gordon: return "Grid Bot"
        case .unknown: return "Bot"
        }
    }
    
    var icon: String {
        switch self {
        case .simple: return "repeat.circle.fill"
        case .composite: return "square.stack.3d.up.fill"
        case .switchBot: return "bolt.circle.fill"
        case .gordon: return "square.grid.3x3.fill"
        case .unknown: return "cpu"
        }
    }
    
    var color: Color {
        switch self {
        case .simple: return .blue
        case .composite: return .purple
        case .switchBot: return .orange
        case .gordon: return .cyan
        case .unknown: return .gray
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self).lowercased()
        self = ThreeCommasBotType(rawValue: value) ?? .unknown
    }
}

/// Represents a 3Commas trading bot
public struct ThreeCommasBot: Codable, Identifiable {
    public let id: Int
    public let accountId: Int
    public let accountName: String?
    public let name: String
    public let isEnabled: Bool
    public let pairs: [String]
    public let strategy: ThreeCommasBotType
    public let maxActiveDeals: Int?
    public let activeDealsCount: Int?
    public let createdAt: Date?
    public let updatedAt: Date?
    
    // Trading parameters
    public let baseOrderVolume: Double?
    public let safetyOrderVolume: Double?
    public let takeProfit: Double?
    public let martingaleVolumeCoefficient: Double?
    public let martingaleStepCoefficient: Double?
    public let maxSafetyOrders: Int?
    public let activeDealsUsdtProfit: Double?
    public let closedDealsUsdtProfit: Double?
    public let closedDealsCount: Int?
    public let dealsStartedTodayCount: Int?
    public let finishedDealsCount: Int?
    public let finishedDealsProfitUsd: Double?
    
    /// Computed status based on isEnabled
    public var status: ThreeCommasBotStatus {
        isEnabled ? .enabled : .disabled
    }
    
    /// Primary trading pair (first in pairs array)
    public var primaryPair: String {
        pairs.first ?? "Unknown"
    }
    
    /// Total profit from all deals
    public var totalProfitUsd: Double {
        (activeDealsUsdtProfit ?? 0) + (closedDealsUsdtProfit ?? 0)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case accountName = "account_name"
        case name
        case isEnabled = "is_enabled"
        case pairs
        case strategy
        case maxActiveDeals = "max_active_deals"
        case activeDealsCount = "active_deals_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case baseOrderVolume = "base_order_volume"
        case safetyOrderVolume = "safety_order_volume"
        case takeProfit = "take_profit"
        case martingaleVolumeCoefficient = "martingale_volume_coefficient"
        case martingaleStepCoefficient = "martingale_step_coefficient"
        case maxSafetyOrders = "max_safety_orders"
        case activeDealsUsdtProfit = "active_deals_usd_profit"
        case closedDealsUsdtProfit = "closed_deals_usd_profit"
        case closedDealsCount = "closed_deals_count"
        case dealsStartedTodayCount = "deals_started_today_count"
        case finishedDealsCount = "finished_deals_count"
        case finishedDealsProfitUsd = "finished_deals_profit_usd"
    }
    
    /// Memberwise initializer for creating bots programmatically (e.g., demo bots)
    public init(
        id: Int,
        accountId: Int,
        accountName: String?,
        name: String,
        isEnabled: Bool,
        pairs: [String],
        strategy: ThreeCommasBotType,
        maxActiveDeals: Int?,
        activeDealsCount: Int?,
        createdAt: Date?,
        updatedAt: Date?,
        baseOrderVolume: Double?,
        safetyOrderVolume: Double?,
        takeProfit: Double?,
        martingaleVolumeCoefficient: Double?,
        martingaleStepCoefficient: Double?,
        maxSafetyOrders: Int?,
        activeDealsUsdtProfit: Double?,
        closedDealsUsdtProfit: Double?,
        closedDealsCount: Int?,
        dealsStartedTodayCount: Int?,
        finishedDealsCount: Int?,
        finishedDealsProfitUsd: Double?
    ) {
        self.id = id
        self.accountId = accountId
        self.accountName = accountName
        self.name = name
        self.isEnabled = isEnabled
        self.pairs = pairs
        self.strategy = strategy
        self.maxActiveDeals = maxActiveDeals
        self.activeDealsCount = activeDealsCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.baseOrderVolume = baseOrderVolume
        self.safetyOrderVolume = safetyOrderVolume
        self.takeProfit = takeProfit
        self.martingaleVolumeCoefficient = martingaleVolumeCoefficient
        self.martingaleStepCoefficient = martingaleStepCoefficient
        self.maxSafetyOrders = maxSafetyOrders
        self.activeDealsUsdtProfit = activeDealsUsdtProfit
        self.closedDealsUsdtProfit = closedDealsUsdtProfit
        self.closedDealsCount = closedDealsCount
        self.dealsStartedTodayCount = dealsStartedTodayCount
        self.finishedDealsCount = finishedDealsCount
        self.finishedDealsProfitUsd = finishedDealsProfitUsd
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(Int.self, forKey: .id)
        accountId = try container.decode(Int.self, forKey: .accountId)
        accountName = try container.decodeIfPresent(String.self, forKey: .accountName)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        pairs = try container.decode([String].self, forKey: .pairs)
        strategy = try container.decodeIfPresent(ThreeCommasBotType.self, forKey: .strategy) ?? .unknown
        maxActiveDeals = try container.decodeIfPresent(Int.self, forKey: .maxActiveDeals)
        activeDealsCount = try container.decodeIfPresent(Int.self, forKey: .activeDealsCount)
        
        // Parse dates
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let createdAtString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = dateFormatter.date(from: createdAtString)
        } else {
            createdAt = nil
        }
        
        if let updatedAtString = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = dateFormatter.date(from: updatedAtString)
        } else {
            updatedAt = nil
        }
        
        // Parse trading parameters - handle both String and Double types
        baseOrderVolume = Self.decodeFlexibleDouble(container: container, key: .baseOrderVolume)
        safetyOrderVolume = Self.decodeFlexibleDouble(container: container, key: .safetyOrderVolume)
        takeProfit = Self.decodeFlexibleDouble(container: container, key: .takeProfit)
        martingaleVolumeCoefficient = Self.decodeFlexibleDouble(container: container, key: .martingaleVolumeCoefficient)
        martingaleStepCoefficient = Self.decodeFlexibleDouble(container: container, key: .martingaleStepCoefficient)
        maxSafetyOrders = try container.decodeIfPresent(Int.self, forKey: .maxSafetyOrders)
        activeDealsUsdtProfit = Self.decodeFlexibleDouble(container: container, key: .activeDealsUsdtProfit)
        closedDealsUsdtProfit = Self.decodeFlexibleDouble(container: container, key: .closedDealsUsdtProfit)
        closedDealsCount = try container.decodeIfPresent(Int.self, forKey: .closedDealsCount)
        dealsStartedTodayCount = try container.decodeIfPresent(Int.self, forKey: .dealsStartedTodayCount)
        finishedDealsCount = try container.decodeIfPresent(Int.self, forKey: .finishedDealsCount)
        finishedDealsProfitUsd = Self.decodeFlexibleDouble(container: container, key: .finishedDealsProfitUsd)
    }
    
    /// Helper to decode values that might be String or Double
    private static func decodeFlexibleDouble(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Double? {
        if let doubleValue = try? container.decode(Double.self, forKey: key) {
            return doubleValue
        }
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return Double(stringValue)
        }
        return nil
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(accountId, forKey: .accountId)
        try container.encodeIfPresent(accountName, forKey: .accountName)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(pairs, forKey: .pairs)
        try container.encode(strategy, forKey: .strategy)
        try container.encodeIfPresent(maxActiveDeals, forKey: .maxActiveDeals)
        try container.encodeIfPresent(activeDealsCount, forKey: .activeDealsCount)
        try container.encodeIfPresent(baseOrderVolume, forKey: .baseOrderVolume)
        try container.encodeIfPresent(safetyOrderVolume, forKey: .safetyOrderVolume)
        try container.encodeIfPresent(takeProfit, forKey: .takeProfit)
        try container.encodeIfPresent(martingaleVolumeCoefficient, forKey: .martingaleVolumeCoefficient)
        try container.encodeIfPresent(martingaleStepCoefficient, forKey: .martingaleStepCoefficient)
        try container.encodeIfPresent(maxSafetyOrders, forKey: .maxSafetyOrders)
        try container.encodeIfPresent(activeDealsUsdtProfit, forKey: .activeDealsUsdtProfit)
        try container.encodeIfPresent(closedDealsUsdtProfit, forKey: .closedDealsUsdtProfit)
        try container.encodeIfPresent(closedDealsCount, forKey: .closedDealsCount)
        try container.encodeIfPresent(dealsStartedTodayCount, forKey: .dealsStartedTodayCount)
        try container.encodeIfPresent(finishedDealsCount, forKey: .finishedDealsCount)
        try container.encodeIfPresent(finishedDealsProfitUsd, forKey: .finishedDealsProfitUsd)
    }
}

/// Response wrapper for bot operations
public struct ThreeCommasBotResponse: Codable {
    public let bot: ThreeCommasBot?
    public let error: String?
    public let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case bot
        case error
        case errorDescription = "error_description"
    }
}
