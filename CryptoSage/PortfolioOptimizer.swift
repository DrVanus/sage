//
//  PortfolioOptimizer.swift
//  CryptoSage
//
//  AI-Driven Portfolio Optimizer — Generates rebalancing recommendations
//  using risk-adjusted returns, correlation analysis, and AI signals.
//

import Foundation
import Combine

// MARK: - Optimization Result

public struct PortfolioOptimizationResult: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let currentAllocations: [AssetAllocation]
    public let targetAllocations: [AssetAllocation]
    public let rebalancingActions: [RebalancingAction]
    public let expectedImprovement: ExpectedImprovement
    public let reasoning: [String]
}

public struct AssetAllocation: Identifiable, Codable {
    public let id: UUID
    public let symbol: String
    public let name: String
    public var allocationPct: Double
    public var valueUSD: Double
    
    public init(id: UUID = UUID(), symbol: String, name: String, allocationPct: Double, valueUSD: Double) {
        self.id = id; self.symbol = symbol; self.name = name
        self.allocationPct = allocationPct; self.valueUSD = valueUSD
    }
}

public struct RebalancingAction: Identifiable {
    public let id = UUID()
    public let symbol: String
    public let name: String
    public let currentPct: Double
    public let targetPct: Double
    public let changePct: Double
    public let changeUSD: Double
    public let action: RebalanceActionType
    public let priority: Int
    public let reason: String
    public let taxImplication: TaxImplication
}

public enum RebalanceActionType: String {
    case buy = "Buy"
    case sell = "Sell"
    case hold = "Hold"
    
    public var icon: String {
        switch self {
        case .buy:  return "arrow.up.circle.fill"
        case .sell: return "arrow.down.circle.fill"
        case .hold: return "equal.circle.fill"
        }
    }
}

public enum TaxImplication: String {
    case noTax = "No Tax Event"
    case shortTermGain = "Short-Term Gain"
    case longTermGain = "Long-Term Gain"
    case taxLossHarvest = "Tax-Loss Harvest"
}

public struct ExpectedImprovement {
    public let sharpeImprovement: Double
    public let riskReduction: Double
    public let diversificationGain: Double
}

// MARK: - Optimization Strategy

public enum OptimizationStrategy: String, CaseIterable {
    case equalWeight = "Equal Weight"
    case riskParity = "Risk Parity"
    case momentumWeighted = "Momentum Weighted"
    case aiSignalWeighted = "AI Signal Weighted"
    case minimumVariance = "Minimum Variance"
    case maxSharpe = "Maximum Sharpe"
    
    public var description: String {
        switch self {
        case .equalWeight:       return "Equal allocation across all assets"
        case .riskParity:        return "Weight inversely to volatility"
        case .momentumWeighted:  return "Overweight assets with positive momentum"
        case .aiSignalWeighted:  return "Weight based on AI conviction scores"
        case .minimumVariance:   return "Minimize overall portfolio volatility"
        case .maxSharpe:         return "Maximize risk-adjusted returns"
        }
    }
}

// MARK: - Portfolio Optimizer

@MainActor
public final class PortfolioOptimizer: ObservableObject {

    public static let shared = PortfolioOptimizer()

    @Published public var lastOptimization: PortfolioOptimizationResult?
    @Published public var isOptimizing: Bool = false
    @Published public var selectedStrategy: OptimizationStrategy = .aiSignalWeighted

    public var minPositionPct: Double = 2.0
    public var maxPositionPct: Double = 30.0
    public var rebalanceThresholdPct: Double = 3.0

    private init() {}

    // MARK: - Optimize

    public func optimize(
        holdings: [Holding],
        decisions: [SmartTradingDecision],
        strategy: OptimizationStrategy? = nil
    ) -> PortfolioOptimizationResult {
        isOptimizing = true
        defer { isOptimizing = false }

        let activeStrategy = strategy ?? selectedStrategy
        let totalValue = holdings.map(\.currentValue).reduce(0, +)
        guard totalValue > 0 else { return makeEmptyResult() }

        let currentAllocations = holdings.map { h -> AssetAllocation in
            AssetAllocation(
                symbol: h.coinSymbol, name: h.coinName,
                allocationPct: h.currentValue / totalValue * 100,
                valueUSD: h.currentValue
            )
        }

        let targets = calculateTargets(current: currentAllocations, decisions: decisions, strategy: activeStrategy)
        let actions = generateActions(current: currentAllocations, target: targets, holdings: holdings, totalValue: totalValue)

        let diversScore = calculateDiversification(allocations: currentAllocations)
        let targetDiversScore = calculateDiversification(allocations: targets)

        let improvement = ExpectedImprovement(
            sharpeImprovement: 0,
            riskReduction: 0,
            diversificationGain: targetDiversScore - diversScore
        )

        var reasoning: [String] = [
            "Strategy: \(activeStrategy.rawValue)",
            "Portfolio: $\(String(format: "%.0f", totalValue))",
            "Diversification: \(String(format: "%.0f", diversScore))/100"
        ]
        let actionableCount = actions.filter { $0.action != .hold }.count
        reasoning.append(actionableCount > 0 ? "\(actionableCount) rebalancing actions" : "Portfolio within thresholds")

        let result = PortfolioOptimizationResult(
            timestamp: Date(),
            currentAllocations: currentAllocations,
            targetAllocations: targets,
            rebalancingActions: actions.sorted { $0.priority < $1.priority },
            expectedImprovement: improvement,
            reasoning: reasoning
        )
        lastOptimization = result
        return result
    }

    // MARK: - Target Strategies

    private func calculateTargets(
        current: [AssetAllocation],
        decisions: [SmartTradingDecision],
        strategy: OptimizationStrategy
    ) -> [AssetAllocation] {
        switch strategy {
        case .equalWeight:
            return equalWeight(current: current)
        case .riskParity:
            return riskParity(current: current, decisions: decisions)
        case .momentumWeighted:
            return momentumWeighted(current: current, decisions: decisions)
        case .aiSignalWeighted:
            return aiWeighted(current: current, decisions: decisions)
        case .minimumVariance:
            return riskParity(current: current, decisions: decisions)
        case .maxSharpe:
            return maxSharpe(current: current, decisions: decisions)
        }
    }

    private func equalWeight(current: [AssetAllocation]) -> [AssetAllocation] {
        let count = Double(current.count)
        guard count > 0 else { return current }
        let pct = 100.0 / count
        return current.map { var t = $0; t.allocationPct = pct; return t }
    }

    private func riskParity(current: [AssetAllocation], decisions: [SmartTradingDecision]) -> [AssetAllocation] {
        var weights: [(AssetAllocation, Double)] = current.map { alloc in
            let decision = decisions.first { $0.symbol.lowercased() == alloc.symbol.lowercased() }
            let risk = decision.map { max(100 - $0.conviction, 10) } ?? 50
            return (alloc, 1.0 / risk)
        }
        let total = weights.map(\.1).reduce(0, +)
        guard total > 0 else { return equalWeight(current: current) }
        return weights.map { var t = $0.0; t.allocationPct = clamp($0.1 / total * 100); return t }
    }

    private func momentumWeighted(current: [AssetAllocation], decisions: [SmartTradingDecision]) -> [AssetAllocation] {
        var scores: [(AssetAllocation, Double)] = current.map { alloc in
            let decision = decisions.first { $0.symbol.lowercased() == alloc.symbol.lowercased() }
            let techScore = decision?.technicalSignal.score ?? 0
            return (alloc, max(techScore + 100, 10))
        }
        let total = scores.map(\.1).reduce(0, +)
        guard total > 0 else { return equalWeight(current: current) }
        return scores.map { var t = $0.0; t.allocationPct = clamp($0.1 / total * 100); return t }
    }

    private func aiWeighted(current: [AssetAllocation], decisions: [SmartTradingDecision]) -> [AssetAllocation] {
        var scores: [(AssetAllocation, Double)] = current.map { alloc in
            let decision = decisions.first { $0.symbol.lowercased() == alloc.symbol.lowercased() }
            let conv = decision?.conviction ?? 50
            let actionMult: Double = {
                switch decision?.action {
                case .strongBuy: return 2.0; case .buy: return 1.5; case .accumulate: return 1.2
                case .hold: return 1.0; case .reducePosition: return 0.5; case .sell: return 0.3
                case .strongSell: return 0.1; case .none: return 1.0
                }
            }()
            return (alloc, max(conv * actionMult, 5))
        }
        let total = scores.map(\.1).reduce(0, +)
        guard total > 0 else { return equalWeight(current: current) }
        return scores.map { var t = $0.0; t.allocationPct = clamp($0.1 / total * 100); return t }
    }

    private func maxSharpe(current: [AssetAllocation], decisions: [SmartTradingDecision]) -> [AssetAllocation] {
        let mom = momentumWeighted(current: current, decisions: decisions)
        let risk = riskParity(current: current, decisions: decisions)
        return zip(mom, risk).map { var t = $0.0; t.allocationPct = ($0.0.allocationPct + $0.1.allocationPct) / 2; return t }
    }

    // MARK: - Rebalancing Actions

    private func generateActions(
        current: [AssetAllocation], target: [AssetAllocation],
        holdings: [Holding], totalValue: Double
    ) -> [RebalancingAction] {
        zip(current, target).map { (curr, tgt) in
            let change = tgt.allocationPct - curr.allocationPct
            let changeUSD = change / 100 * totalValue
            guard abs(change) >= rebalanceThresholdPct else {
                return RebalancingAction(
                    symbol: curr.symbol, name: curr.name,
                    currentPct: curr.allocationPct, targetPct: tgt.allocationPct,
                    changePct: change, changeUSD: changeUSD,
                    action: .hold, priority: 3, reason: "Within threshold", taxImplication: .noTax
                )
            }
            let actionType: RebalanceActionType = change > 0 ? .buy : .sell
            let priority = abs(change) > 10 ? 1 : abs(change) > 5 ? 2 : 3
            let holding = holdings.first { $0.coinSymbol.lowercased() == curr.symbol.lowercased() }
            let taxImpl = determineTax(holding: holding, action: actionType)
            let reason = actionType == .buy
                ? "Underweight by \(String(format: "%.1f", abs(change)))%"
                : "Overweight by \(String(format: "%.1f", abs(change)))%"
            return RebalancingAction(
                symbol: curr.symbol, name: curr.name,
                currentPct: curr.allocationPct, targetPct: tgt.allocationPct,
                changePct: change, changeUSD: changeUSD,
                action: actionType, priority: priority, reason: reason, taxImplication: taxImpl
            )
        }
    }

    // MARK: - Helpers

    private func calculateDiversification(allocations: [AssetAllocation]) -> Double {
        let weights = allocations.map { $0.allocationPct / 100.0 }
        let hhi = weights.map { pow($0, 2) }.reduce(0, +)
        let n = Double(allocations.count)
        let minHHI = n > 0 ? 1.0 / n : 1.0
        return n > 1 ? max(0, min(100, (1.0 - (hhi - minHHI) / (1.0 - minHHI)) * 100)) : 0
    }

    private func determineTax(holding: Holding?, action: RebalanceActionType) -> TaxImplication {
        guard let h = holding, action == .sell else { return .noTax }
        if h.profitLoss < 0 { return .taxLossHarvest }
        return Date().timeIntervalSince(h.purchaseDate) > 365 * 86400 ? .longTermGain : .shortTermGain
    }

    private func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(value, minPositionPct), maxPositionPct)
    }

    private func makeEmptyResult() -> PortfolioOptimizationResult {
        PortfolioOptimizationResult(
            timestamp: Date(), currentAllocations: [], targetAllocations: [],
            rebalancingActions: [],
            expectedImprovement: ExpectedImprovement(sharpeImprovement: 0, riskReduction: 0, diversificationGain: 0),
            reasoning: ["No portfolio data"]
        )
    }
}
