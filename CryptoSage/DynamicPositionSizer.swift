//
//  DynamicPositionSizer.swift
//  CryptoSage
//
//  Dynamic Position Sizing Engine — Fear/Greed-adjusted position sizes
//  with portfolio-level risk controls.
//

import Foundation

// MARK: - Position Sizing Result

public struct PositionSizing {
    public let symbol: String?
    public let positionPct: Double       // recommended % of portfolio
    public let amountUSD: Double         // dollar amount based on portfolio value
    public let maxPct: Double            // hard cap on this position
    public let fearGreedMultiplier: Double
    public let regimeMultiplier: Double
    public let volatilityMultiplier: Double
    public let convictionMultiplier: Double
    public let reasoning: [String]

    /// The effective multiplier applied to base position size
    public var totalMultiplier: Double {
        fearGreedMultiplier * regimeMultiplier * volatilityMultiplier * convictionMultiplier
    }
}

// MARK: - Dynamic Position Sizer

/// Calculates intelligent position sizes based on:
/// - Fear/Greed sentiment (contrarian: buy more in fear, less in greed)
/// - Market regime (reduce in volatile, increase in trending)
/// - Volatility (reduce for high-vol assets)
/// - Conviction level from signal fusion
/// - Portfolio-level risk constraints
@MainActor
public final class DynamicPositionSizer: ObservableObject {

    // MARK: - Singleton
    public static let shared = DynamicPositionSizer()

    // MARK: - Constants
    private let basePositionPct: Double = 5.0  // default 5% per position

    private init() {}

    // MARK: - Main Calculation

    /// Calculate the optimal position size for a trade, adjusting for all factors.
    public func calculatePositionSize(
        action: SmartAction,
        conviction: Double,
        fearGreedValue: Int,
        regime: String,
        currentPrice: Double,
        volatility: Double,
        portfolioSnapshot: PortfolioRiskSnapshot,
        config: SmartEngineConfig
    ) -> PositionSizing {

        var reasoning: [String] = []

        // 1. Base position size
        var positionPct = basePositionPct
        reasoning.append("Base position: \(String(format: "%.1f", basePositionPct))%")

        // 2. Fear/Greed Multiplier (CONTRARIAN)
        let fgMultiplier = calculateFearGreedMultiplier(
            fearGreedValue: fearGreedValue,
            action: action,
            config: config
        )
        positionPct *= fgMultiplier
        reasoning.append("Fear/Greed adjustment: ×\(String(format: "%.2f", fgMultiplier)) (F&G: \(fearGreedValue))")

        // 3. Regime Multiplier
        let regimeMultiplier = calculateRegimeMultiplier(regime: regime)
        positionPct *= regimeMultiplier
        reasoning.append("Regime adjustment: ×\(String(format: "%.2f", regimeMultiplier)) (\(regime))")

        // 4. Volatility Multiplier
        let volMultiplier = calculateVolatilityMultiplier(annualizedVol: volatility)
        positionPct *= volMultiplier
        reasoning.append("Volatility adjustment: ×\(String(format: "%.2f", volMultiplier)) (vol: \(String(format: "%.0f", volatility * 100))%)")

        // 5. Conviction Multiplier
        let convictionMultiplier = calculateConvictionMultiplier(conviction: conviction)
        positionPct *= convictionMultiplier
        reasoning.append("Conviction adjustment: ×\(String(format: "%.2f", convictionMultiplier)) (\(String(format: "%.0f", conviction))% conviction)")

        // 6. Action-based scaling
        let actionScale = actionMultiplier(action: action)
        positionPct *= actionScale
        reasoning.append("Action scale: ×\(String(format: "%.2f", actionScale)) (\(action.displayName))")

        // 7. Portfolio-level risk constraints
        let (constrained, constraintReasons) = applyPortfolioConstraints(
            positionPct: positionPct,
            portfolioSnapshot: portfolioSnapshot,
            config: config
        )
        positionPct = constrained
        reasoning.append(contentsOf: constraintReasons)

        // Calculate max allowed
        let maxPct = config.maxSinglePositionPct

        // Cap at maximum
        positionPct = min(positionPct, maxPct)

        // Ensure non-negative
        positionPct = max(positionPct, 0)

        // Dollar amount
        let amountUSD = portfolioSnapshot.totalValueUSD * (positionPct / 100.0)

        return PositionSizing(
            symbol: nil,
            positionPct: positionPct,
            amountUSD: amountUSD,
            maxPct: maxPct,
            fearGreedMultiplier: fgMultiplier,
            regimeMultiplier: regimeMultiplier,
            volatilityMultiplier: volMultiplier,
            convictionMultiplier: convictionMultiplier,
            reasoning: reasoning
        )
    }

    // MARK: - Fear/Greed Multiplier

    /// Contrarian position sizing based on Fear & Greed Index.
    /// - Extreme Fear (0-20): BUY MORE → multiplier up to 1.5x
    /// - Fear (20-40): BUY slightly more → multiplier 1.1-1.3x
    /// - Neutral (40-60): No adjustment → multiplier 1.0x
    /// - Greed (60-80): BUY less → multiplier 0.7-0.9x
    /// - Extreme Greed (80-100): BUY much less → multiplier 0.5x
    ///
    /// For SELL actions, the logic inverts (sell more during greed, less during fear).
    private func calculateFearGreedMultiplier(
        fearGreedValue: Int,
        action: SmartAction,
        config: SmartEngineConfig
    ) -> Double {
        let fg = Double(fearGreedValue)
        let isBuyAction = [SmartAction.strongBuy, .buy, .accumulate].contains(action)

        let rawMultiplier: Double

        if fg <= 10 {
            // Extreme fear — maximum buy boost
            rawMultiplier = config.fearMultiplierMax
        } else if fg <= 25 {
            // Fear zone — significant buy boost
            rawMultiplier = lerp(from: config.fearMultiplierMax, to: 1.2, t: (fg - 10) / 15)
        } else if fg <= 40 {
            // Mild fear — slight boost
            rawMultiplier = lerp(from: 1.2, to: 1.0, t: (fg - 25) / 15)
        } else if fg <= 60 {
            // Neutral — no adjustment
            rawMultiplier = 1.0
        } else if fg <= 75 {
            // Greed zone — reduce
            rawMultiplier = lerp(from: 1.0, to: 0.75, t: (fg - 60) / 15)
        } else if fg <= 90 {
            // High greed — significantly reduce
            rawMultiplier = lerp(from: 0.75, to: config.greedMultiplierMin, t: (fg - 75) / 15)
        } else {
            // Extreme greed — minimum position size
            rawMultiplier = config.greedMultiplierMin
        }

        // Invert for sell actions (sell more during greed, less during fear)
        if !isBuyAction && action != .hold {
            return 2.0 - rawMultiplier // mirrors: 0.5 → 1.5, 1.5 → 0.5
        }

        return rawMultiplier
    }

    // MARK: - Regime Multiplier

    private func calculateRegimeMultiplier(regime: String) -> Double {
        switch regime.lowercased() {
        case "strongtrend":   return 1.2   // Trends are reliable — full size
        case "trending":      return 1.1
        case "weaktrend":     return 0.9
        case "ranging":       return 0.7   // Range-bound — smaller positions
        case "volatile":      return 0.6   // Volatile — reduce exposure
        case "accumulation":  return 1.1   // Smart money accumulating
        case "distribution":  return 0.7   // Distribution phase — caution
        default:              return 1.0
        }
    }

    // MARK: - Volatility Multiplier

    /// Reduce position size for high-volatility assets.
    /// Target: constant risk per trade regardless of volatility.
    private func calculateVolatilityMultiplier(annualizedVol: Double) -> Double {
        // Target vol: 60% annualized (moderate crypto volatility)
        let targetVol = 0.60

        if annualizedVol <= 0.01 { return 1.0 } // avoid division issues

        // Inverse relationship: higher vol → smaller position
        let multiplier = targetVol / annualizedVol

        // Clamp between 0.3x and 1.5x
        return max(0.3, min(1.5, multiplier))
    }

    // MARK: - Conviction Multiplier

    private func calculateConvictionMultiplier(conviction: Double) -> Double {
        switch conviction {
        case 85...100: return 1.3   // Very high conviction — full size
        case 70..<85:  return 1.1
        case 55..<70:  return 1.0   // Standard
        case 40..<55:  return 0.7
        case 25..<40:  return 0.5
        default:       return 0.3   // Low conviction — tiny position
        }
    }

    // MARK: - Action Multiplier

    private func actionMultiplier(action: SmartAction) -> Double {
        switch action {
        case .strongBuy:      return 1.3
        case .buy:            return 1.0
        case .accumulate:     return 0.5  // DCA — smaller chunks
        case .hold:           return 0.0  // No new position
        case .reducePosition: return 0.5  // Trim half
        case .sell:           return 1.0
        case .strongSell:     return 1.3
        }
    }

    // MARK: - Portfolio Constraints

    private func applyPortfolioConstraints(
        positionPct: Double,
        portfolioSnapshot: PortfolioRiskSnapshot,
        config: SmartEngineConfig
    ) -> (Double, [String]) {

        var adjusted = positionPct
        var reasons: [String] = []

        // 1. Drawdown constraint — reduce sizing if portfolio is in drawdown
        if portfolioSnapshot.overallDrawdown > config.maxPortfolioDrawdownPct * 0.5 {
            let drawdownRatio = portfolioSnapshot.overallDrawdown / config.maxPortfolioDrawdownPct
            let drawdownReduction = max(0.3, 1.0 - drawdownRatio)
            adjusted *= drawdownReduction
            reasons.append("Drawdown reduction: ×\(String(format: "%.2f", drawdownReduction)) (DD: \(String(format: "%.1f", portfolioSnapshot.overallDrawdown))%)")
        }

        // 2. If portfolio is critically drawn down, stop trading
        if portfolioSnapshot.overallDrawdown >= config.maxPortfolioDrawdownPct {
            adjusted = 0
            reasons.append("⛔ Trading paused — max drawdown (\(String(format: "%.0f", config.maxPortfolioDrawdownPct))%) exceeded")
        }

        // 3. Concentration limit — don't over-allocate to a single asset
        // (This is handled in the engine when checking existing holdings)

        // 4. Cash constraint — can't invest more than available cash
        let maxFromCash = (portfolioSnapshot.cashAvailableUSD / max(portfolioSnapshot.totalValueUSD, 1)) * 100
        if adjusted > maxFromCash {
            adjusted = maxFromCash
            reasons.append("Cash-limited: capped at \(String(format: "%.1f", maxFromCash))% (available cash)")
        }

        // 5. Recent loss streak — reduce if daily P&L is negative
        if portfolioSnapshot.dailyPnLPct < -3 {
            let lossReduction = max(0.5, 1.0 + portfolioSnapshot.dailyPnLPct / 10.0)
            adjusted *= lossReduction
            reasons.append("Loss reduction: ×\(String(format: "%.2f", lossReduction)) (daily P&L: \(String(format: "%.1f", portfolioSnapshot.dailyPnLPct))%)")
        }

        return (adjusted, reasons)
    }

    // MARK: - Helpers

    private func lerp(from a: Double, to b: Double, t: Double) -> Double {
        a + (b - a) * max(0, min(1, t))
    }

    // MARK: - Bulk Position Sizing

    /// Calculate optimal portfolio allocation across multiple assets.
    /// Returns a rebalancing recommendation.
    public func calculatePortfolioAllocation(
        decisions: [SmartTradingDecision],
        portfolioSnapshot: PortfolioRiskSnapshot,
        config: SmartEngineConfig
    ) -> [PortfolioAllocationRecommendation] {

        var recommendations: [PortfolioAllocationRecommendation] = []
        var totalAllocated: Double = 0

        // Sort by conviction (highest first)
        let sorted = decisions
            .filter { $0.action != .hold }
            .sorted { $0.conviction > $1.conviction }

        for decision in sorted {
            let remainingCapacity = config.maxSinglePositionPct * 3 - totalAllocated // rough portfolio cap
            guard remainingCapacity > 1 else { break }

            let allocation = min(decision.recommendedPositionPct, remainingCapacity)
            totalAllocated += allocation

            // Check existing position
            let existing = portfolioSnapshot.holdings.first {
                $0.symbol.lowercased() == decision.symbol.lowercased()
            }

            let currentAllocation = existing?.allocationPct ?? 0
            let change = allocation - currentAllocation

            let rec = PortfolioAllocationRecommendation(
                symbol: decision.symbol,
                currentAllocationPct: currentAllocation,
                targetAllocationPct: allocation,
                changePct: change,
                action: decision.action,
                conviction: decision.conviction,
                reasoning: "Conviction: \(Int(decision.conviction))% | \(decision.action.displayName)"
            )

            recommendations.append(rec)
        }

        return recommendations
    }
}

// MARK: - Portfolio Allocation Recommendation

public struct PortfolioAllocationRecommendation: Identifiable {
    public let id = UUID()
    public let symbol: String
    public let currentAllocationPct: Double
    public let targetAllocationPct: Double
    public let changePct: Double
    public let action: SmartAction
    public let conviction: Double
    public let reasoning: String

    public var isIncrease: Bool { changePct > 0 }
    public var isDecrease: Bool { changePct < 0 }
    public var needsRebalancing: Bool { abs(changePct) > 1.0 }
}
