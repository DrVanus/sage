//
//  SmartDCAEngine.swift
//  CryptoSage
//
//  Smart Dollar-Cost Averaging Engine — Sentiment-adjusted DCA
//  that buys more during fear and less during greed.
//

import Foundation
import Combine
import SwiftUI

// MARK: - DCA Plan Model

public struct SmartDCAPlan: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var assets: [DCAAssetAllocation]
    public var baseAmountUSD: Double              // base DCA amount per period
    public var frequency: DCAFrequency
    public var sentimentAdjustment: Bool          // enable Fear/Greed adjustment
    public var volatilityAdjustment: Bool         // adjust based on volatility
    public var isActive: Bool
    public var createdAt: Date
    public var lastExecutedAt: Date?

    // Constraints
    public var maxSinglePurchaseUSD: Double       // never exceed this in one buy
    public var minPurchaseUSD: Double             // skip if adjusted amount is below this

    // Tax optimization
    public var taxLossHarvestEnabled: Bool        // sell losers for tax benefits
    public var rebalanceOnDCA: Bool               // rebalance while DCA-ing

    public var nextExecutionDate: Date {
        guard let lastExec = lastExecutedAt else { return Date() }
        return lastExec.addingTimeInterval(frequency.intervalSeconds)
    }

    public var isOverdue: Bool {
        Date() >= nextExecutionDate
    }
}

public struct DCAAssetAllocation: Codable, Identifiable {
    public let id: UUID
    public var symbol: String
    public var coinName: String
    public var allocationPct: Double              // % of DCA budget for this asset
    public var overrideAmount: Double?            // optional fixed amount override
}

public enum DCAFrequency: String, Codable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case biweekly = "biweekly"
    case monthly = "monthly"

    public var displayName: String {
        switch self {
        case .daily:    return "Daily"
        case .weekly:   return "Weekly"
        case .biweekly: return "Bi-Weekly"
        case .monthly:  return "Monthly"
        }
    }

    public var intervalSeconds: TimeInterval {
        switch self {
        case .daily:    return 86400
        case .weekly:   return 604800
        case .biweekly: return 1209600
        case .monthly:  return 2592000
        }
    }
}

// MARK: - DCA Execution Result

public struct DCAExecutionResult: Codable, Identifiable {
    public let id: UUID
    public let planId: UUID
    public let timestamp: Date
    public let purchases: [DCAPurchase]
    public let totalSpentUSD: Double
    public let baseAmountUSD: Double
    public let adjustedAmountUSD: Double
    public let fearGreedAtExecution: Int
    public let fearGreedMultiplier: Double
    public let volatilityMultiplier: Double
    public let reasoning: [String]
}

public struct DCAPurchase: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let coinName: String
    public let amountUSD: Double
    public let estimatedQuantity: Double
    public let priceAtExecution: Double
    public let allocationPct: Double
    public let isPaperTrade: Bool
}

// MARK: - Smart DCA Engine

/// Intelligent Dollar-Cost Averaging that adjusts purchase amounts based on
/// market sentiment, volatility, and AI signals.
@MainActor
public final class SmartDCAEngine: ObservableObject {

    // MARK: - Singleton
    public static let shared = SmartDCAEngine()

    // MARK: - Published State
    @Published public var activePlans: [SmartDCAPlan] = []
    @Published public var executionHistory: [DCAExecutionResult] = []
    @Published public var isExecuting: Bool = false
    @Published public var nextScheduledExecution: Date?

    // MARK: - Constants
    private let persistenceKey = "SmartDCAPlans"
    private let historyKey = "SmartDCAHistory"
    private let maxHistory = 200

    private init() {
        loadPlans()
        loadHistory()
    }

    // MARK: - Plan Management

    public func createPlan(
        name: String,
        assets: [DCAAssetAllocation],
        baseAmount: Double,
        frequency: DCAFrequency,
        sentimentAdjusted: Bool = true,
        volatilityAdjusted: Bool = true,
        taxOptimized: Bool = false
    ) -> SmartDCAPlan {

        let plan = SmartDCAPlan(
            id: UUID(),
            name: name,
            assets: assets,
            baseAmountUSD: baseAmount,
            frequency: frequency,
            sentimentAdjustment: sentimentAdjusted,
            volatilityAdjustment: volatilityAdjusted,
            isActive: true,
            createdAt: Date(),
            lastExecutedAt: nil,
            maxSinglePurchaseUSD: baseAmount * 3.0,
            minPurchaseUSD: 5.0,
            taxLossHarvestEnabled: taxOptimized,
            rebalanceOnDCA: false
        )

        activePlans.append(plan)
        savePlans()
        return plan
    }

    public func updatePlan(_ plan: SmartDCAPlan) {
        if let index = activePlans.firstIndex(where: { $0.id == plan.id }) {
            activePlans[index] = plan
            savePlans()
        }
    }

    public func deletePlan(id: UUID) {
        activePlans.removeAll { $0.id == id }
        savePlans()
    }

    public func togglePlan(id: UUID) {
        if let index = activePlans.firstIndex(where: { $0.id == id }) {
            activePlans[index].isActive.toggle()
            savePlans()
        }
    }

    // MARK: - Smart DCA Calculation

    /// Calculate what a DCA execution would look like right now,
    /// without actually executing it.
    public func previewExecution(plan: SmartDCAPlan) -> DCAExecutionResult {
        let fearGreedValue = getCurrentFearGreed()
        let volatility = getMarketVolatility()

        // 1. Fear/Greed Adjustment
        let fgMultiplier = plan.sentimentAdjustment
            ? calculateFearGreedDCAMultiplier(fearGreedValue: fearGreedValue)
            : 1.0

        // 2. Volatility Adjustment
        let volMultiplier = plan.volatilityAdjustment
            ? calculateVolatilityDCAMultiplier(volatility: volatility)
            : 1.0

        // 3. Calculate adjusted amount
        let adjustedAmount = plan.baseAmountUSD * fgMultiplier * volMultiplier
        let clampedAmount = min(
            max(adjustedAmount, plan.minPurchaseUSD),
            plan.maxSinglePurchaseUSD
        )

        // 4. Distribute across assets
        var purchases: [DCAPurchase] = []
        var reasoning: [String] = []

        reasoning.append("Base DCA: $\(String(format: "%.2f", plan.baseAmountUSD))")
        if plan.sentimentAdjustment {
            reasoning.append("Fear/Greed adjustment: ×\(String(format: "%.2f", fgMultiplier)) (F&G: \(fearGreedValue))")
        }
        if plan.volatilityAdjustment {
            reasoning.append("Volatility adjustment: ×\(String(format: "%.2f", volMultiplier))")
        }
        reasoning.append("Final amount: $\(String(format: "%.2f", clampedAmount))")

        for asset in plan.assets {
            let assetAmount = asset.overrideAmount ?? (clampedAmount * asset.allocationPct / 100.0)
            let price = getCurrentPrice(for: asset.symbol)
            let quantity = price > 0 ? assetAmount / price : 0

            let purchase = DCAPurchase(
                id: UUID(),
                symbol: asset.symbol,
                coinName: asset.coinName,
                amountUSD: assetAmount,
                estimatedQuantity: quantity,
                priceAtExecution: price,
                allocationPct: asset.allocationPct,
                isPaperTrade: true
            )
            purchases.append(purchase)
        }

        return DCAExecutionResult(
            id: UUID(),
            planId: plan.id,
            timestamp: Date(),
            purchases: purchases,
            totalSpentUSD: purchases.map(\.amountUSD).reduce(0, +),
            baseAmountUSD: plan.baseAmountUSD,
            adjustedAmountUSD: clampedAmount,
            fearGreedAtExecution: fearGreedValue,
            fearGreedMultiplier: fgMultiplier,
            volatilityMultiplier: volMultiplier,
            reasoning: reasoning
        )
    }

    /// Execute a DCA plan (paper trade by default).
    public func executePlan(_ plan: SmartDCAPlan) async -> DCAExecutionResult {
        isExecuting = true
        defer { isExecuting = false }

        let result = previewExecution(plan: plan)

        // Record execution
        executionHistory.append(result)
        if executionHistory.count > maxHistory {
            executionHistory = Array(executionHistory.suffix(maxHistory))
        }

        // Update plan's last execution time
        if let index = activePlans.firstIndex(where: { $0.id == plan.id }) {
            activePlans[index].lastExecutedAt = Date()
        }

        saveHistory()
        savePlans()

        return result
    }

    /// Check and execute any overdue plans.
    public func executeOverduePlans() async -> [DCAExecutionResult] {
        var results: [DCAExecutionResult] = []

        for plan in activePlans where plan.isActive && plan.isOverdue {
            let result = await executePlan(plan)
            results.append(result)
        }

        return results
    }

    // MARK: - Fear/Greed DCA Multiplier

    /// Maps Fear & Greed to DCA multiplier.
    /// Key insight: Buy MORE during fear, LESS during greed.
    ///
    /// F&G 0-10:  Buy 2.0x (extreme fear = extreme opportunity)
    /// F&G 10-25: Buy 1.5-2.0x
    /// F&G 25-40: Buy 1.1-1.5x
    /// F&G 40-60: Buy 1.0x (neutral)
    /// F&G 60-75: Buy 0.7-1.0x (getting greedy, slow down)
    /// F&G 75-90: Buy 0.4-0.7x (high greed, significantly reduce)
    /// F&G 90-100: Buy 0.25x (extreme greed, minimal buying)
    private func calculateFearGreedDCAMultiplier(fearGreedValue: Int) -> Double {
        let fg = Double(fearGreedValue)

        switch fg {
        case 0..<10:   return 2.0
        case 10..<25:  return lerp(from: 2.0, to: 1.5, t: (fg - 10) / 15)
        case 25..<40:  return lerp(from: 1.5, to: 1.1, t: (fg - 25) / 15)
        case 40..<60:  return 1.0
        case 60..<75:  return lerp(from: 1.0, to: 0.7, t: (fg - 60) / 15)
        case 75..<90:  return lerp(from: 0.7, to: 0.4, t: (fg - 75) / 15)
        case 90...100: return 0.25
        default:       return 1.0
        }
    }

    // MARK: - Volatility DCA Multiplier

    /// During high volatility, DCA slightly more (buying dips).
    /// During low volatility, DCA normally.
    private func calculateVolatilityDCAMultiplier(volatility: Double) -> Double {
        // volatility is annualized (e.g., 0.8 = 80% annual vol for crypto)
        switch volatility {
        case 0..<0.3:    return 0.9   // Very low vol — market might be topping
        case 0.3..<0.6:  return 1.0   // Normal crypto vol
        case 0.6..<1.0:  return 1.1   // Elevated — slight increase
        case 1.0..<1.5:  return 1.2   // High vol — buying opportunity
        case 1.5...:     return 1.3   // Extreme vol — significant opportunity but careful
        default:         return 1.0
        }
    }

    // MARK: - DCA Performance Analytics

    /// Calculate performance metrics for a DCA plan.
    public func calculatePlanPerformance(planId: UUID) -> DCAPerformanceMetrics? {
        let executions = executionHistory.filter { $0.planId == planId }
        guard !executions.isEmpty else { return nil }

        let totalInvested = executions.map(\.totalSpentUSD).reduce(0, +)
        let executionCount = executions.count
        let avgFearGreed = Double(executions.map(\.fearGreedAtExecution).reduce(0, +)) / Double(executionCount)
        let avgMultiplier = executions.map(\.fearGreedMultiplier).reduce(0, +) / Double(executionCount)

        // Calculate current value (would need live prices in production)
        // For now, track the investment pattern metrics
        let savingsFromSentiment = executions.map { exec -> Double in
            let wouldHaveSpent = exec.baseAmountUSD
            let actuallySpent = exec.adjustedAmountUSD
            return wouldHaveSpent - actuallySpent
        }.reduce(0, +)

        return DCAPerformanceMetrics(
            planId: planId,
            totalInvested: totalInvested,
            executionCount: executionCount,
            averageFearGreedAtPurchase: avgFearGreed,
            averageMultiplier: avgMultiplier,
            sentimentSavingsUSD: savingsFromSentiment,
            firstExecution: executions.first?.timestamp ?? Date(),
            lastExecution: executions.last?.timestamp ?? Date()
        )
    }

    // MARK: - Helper: Current Market Data

    private func getCurrentFearGreed() -> Int {
        let vm = ExtendedFearGreedViewModel.shared
        if let firebaseScore = vm.firebaseSentimentScore { return firebaseScore }
        if let first = vm.data.first, let val = Int(first.value) { return val }
        return 50
    }

    private func getMarketVolatility() -> Double {
        if let vol = ExtendedFearGreedViewModel.shared.marketVolatility {
            return vol / 100.0 // normalize to 0-1+ range
        }
        return 0.6 // default moderate crypto volatility
    }

    private func getCurrentPrice(for symbol: String) -> Double {
        // Use LivePriceManager as the single source of truth
        let marketVM = MarketViewModel.shared
        if let coin = marketVM.allCoins.first(where: { $0.symbol.lowercased() == symbol.lowercased() }),
           let price = coin.priceUsd {
            return price
        }
        return 0
    }

    private func lerp(from a: Double, to b: Double, t: Double) -> Double {
        a + (b - a) * max(0, min(1, t))
    }

    // MARK: - Persistence

    private func savePlans() {
        if let data = try? JSONEncoder().encode(activePlans) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    private func loadPlans() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let plans = try? JSONDecoder().decode([SmartDCAPlan].self, from: data) {
            activePlans = plans
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(executionHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let history = try? JSONDecoder().decode([DCAExecutionResult].self, from: data) {
            executionHistory = history
        }
    }
}

// MARK: - DCA Performance Metrics

public struct DCAPerformanceMetrics {
    public let planId: UUID
    public let totalInvested: Double
    public let executionCount: Int
    public let averageFearGreedAtPurchase: Double
    public let averageMultiplier: Double
    public let sentimentSavingsUSD: Double
    public let firstExecution: Date
    public let lastExecution: Date

    public var timeSpan: TimeInterval {
        lastExecution.timeIntervalSince(firstExecution)
    }

    public var averageInvestmentPerExecution: Double {
        executionCount > 0 ? totalInvested / Double(executionCount) : 0
    }

    /// Whether the sentiment adjustment has been saving money overall
    /// (positive = saved money during greed, spent more during fear)
    public var sentimentAdjustmentEffective: Bool {
        sentimentSavingsUSD > 0
    }
}
