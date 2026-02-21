//
//  CapitalGainsReport.swift
//  CryptoSage
//
//  Capital gains aggregation and analysis.
//

import Foundation

// MARK: - Capital Gains Report

/// Detailed capital gains analysis
public struct CapitalGainsReport {
    public let taxYear: TaxYear
    public let disposals: [TaxDisposal]
    
    // MARK: - Aggregates
    
    public var totalProceeds: Double {
        disposals.reduce(0) { $0 + $1.totalProceeds }
    }
    
    public var totalCostBasis: Double {
        disposals.reduce(0) { $0 + $1.totalCostBasis }
    }
    
    public var totalGain: Double {
        disposals.reduce(0) { $0 + $1.gain }
    }
    
    public var totalGains: Double {
        disposals.filter { $0.isGain }.reduce(0) { $0 + $1.gain }
    }
    
    public var totalLosses: Double {
        disposals.filter { $0.isLoss }.reduce(0) { $0 + abs($1.gain) }
    }
    
    // MARK: - Short-Term
    
    public var shortTermDisposals: [TaxDisposal] {
        disposals.filter { $0.gainType == .shortTerm }
    }
    
    public var shortTermGain: Double {
        shortTermDisposals.reduce(0) { $0 + $1.gain }
    }
    
    public var shortTermGains: Double {
        shortTermDisposals.filter { $0.isGain }.reduce(0) { $0 + $1.gain }
    }
    
    public var shortTermLosses: Double {
        shortTermDisposals.filter { $0.isLoss }.reduce(0) { $0 + abs($1.gain) }
    }
    
    // MARK: - Long-Term
    
    public var longTermDisposals: [TaxDisposal] {
        disposals.filter { $0.gainType == .longTerm }
    }
    
    public var longTermGain: Double {
        longTermDisposals.reduce(0) { $0 + $1.gain }
    }
    
    public var longTermGains: Double {
        longTermDisposals.filter { $0.isGain }.reduce(0) { $0 + $1.gain }
    }
    
    public var longTermLosses: Double {
        longTermDisposals.filter { $0.isLoss }.reduce(0) { $0 + abs($1.gain) }
    }
    
    // MARK: - By Symbol
    
    public var gainsBySymbol: [String: Double] {
        var result: [String: Double] = [:]
        for disposal in disposals {
            result[disposal.symbol, default: 0] += disposal.gain
        }
        return result
    }
    
    public var volumeBySymbol: [String: Double] {
        var result: [String: Double] = [:]
        for disposal in disposals {
            result[disposal.symbol, default: 0] += disposal.totalProceeds
        }
        return result
    }
    
    // MARK: - By Month
    
    public var gainsByMonth: [Int: Double] {
        var result: [Int: Double] = [:]
        let calendar = Calendar.current
        for disposal in disposals {
            let month = calendar.component(.month, from: disposal.disposedDate)
            result[month, default: 0] += disposal.gain
        }
        return result
    }
    
    // MARK: - Statistics
    
    public var transactionCount: Int {
        disposals.count
    }
    
    public var averageGainPerTransaction: Double {
        guard transactionCount > 0 else { return 0 }
        return totalGain / Double(transactionCount)
    }
    
    public var averageHoldingPeriod: Double {
        guard transactionCount > 0 else { return 0 }
        let totalDays = disposals.reduce(0) { $0 + $1.holdingPeriodDays }
        return Double(totalDays) / Double(transactionCount)
    }
    
    public var uniqueAssets: Int {
        Set(disposals.map { $0.symbol }).count
    }
    
    /// Top gainers by asset
    public var topGainers: [(symbol: String, gain: Double)] {
        gainsBySymbol
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ($0.key, $0.value) }
    }
    
    /// Top losers by asset
    public var topLosers: [(symbol: String, loss: Double)] {
        gainsBySymbol
            .filter { $0.value < 0 }
            .sorted { $0.value < $1.value }
            .prefix(10)
            .map { ($0.key, abs($0.value)) }
    }
    
    // MARK: - Initialization
    
    public init(taxYear: TaxYear, disposals: [TaxDisposal]) {
        self.taxYear = taxYear
        self.disposals = disposals.filter { taxYear.contains($0.disposedDate) }
    }
}

// MARK: - Tax Loss Harvesting Analysis

/// Analysis for tax loss harvesting opportunities
public struct TaxLossHarvestingAnalysis {
    public let symbol: String
    public let currentPrice: Double
    public let lots: [TaxLot]
    
    /// Lots that would generate a loss if sold now
    public var lotsWithUnrealizedLosses: [TaxLot] {
        lots.filter { !$0.isDepleted && $0.costBasisPerUnit > currentPrice }
    }
    
    /// Total unrealized loss available for harvesting
    public var totalUnrealizedLoss: Double {
        lotsWithUnrealizedLosses.reduce(0) { total, lot in
            total + (lot.costBasisPerUnit - currentPrice) * lot.remainingQuantity
        }
    }
    
    /// Short-term lots with losses (higher tax benefit)
    public var shortTermLossLots: [TaxLot] {
        lotsWithUnrealizedLosses.filter { !$0.isLongTerm }
    }
    
    /// Long-term lots with losses
    public var longTermLossLots: [TaxLot] {
        lotsWithUnrealizedLosses.filter { $0.isLongTerm }
    }
    
    /// Estimated tax savings from harvesting all losses
    public func estimatedTaxSavings(shortTermRate: Double = 0.32, longTermRate: Double = 0.15) -> Double {
        let stLoss = shortTermLossLots.reduce(0) { total, lot in
            total + (lot.costBasisPerUnit - currentPrice) * lot.remainingQuantity
        }
        let ltLoss = longTermLossLots.reduce(0) { total, lot in
            total + (lot.costBasisPerUnit - currentPrice) * lot.remainingQuantity
        }
        
        // Short-term losses can offset short-term gains (taxed at ordinary rates)
        // Long-term losses offset long-term gains first
        return (stLoss * shortTermRate) + (ltLoss * longTermRate)
    }
    
    /// Whether harvesting makes sense (significant loss available)
    public var isHarvestingRecommended: Bool {
        totalUnrealizedLoss > 100 // At least $100 in losses
    }
    
    public init(symbol: String, currentPrice: Double, lots: [TaxLot]) {
        self.symbol = symbol
        self.currentPrice = currentPrice
        self.lots = lots.filter { $0.symbol.uppercased() == symbol.uppercased() }
    }
}

// MARK: - Portfolio Tax Summary

/// Tax summary for entire portfolio
public struct PortfolioTaxSummary {
    public let holdings: [HoldingTaxInfo]
    public let totalCostBasis: Double
    public let totalCurrentValue: Double
    public let totalUnrealizedGain: Double
    public let shortTermUnrealized: Double
    public let longTermUnrealized: Double
    
    /// Holdings sorted by unrealized gain
    public var holdingsByGain: [HoldingTaxInfo] {
        holdings.sorted { $0.unrealizedGain > $1.unrealizedGain }
    }
    
    /// Holdings sorted by unrealized loss
    public var holdingsByLoss: [HoldingTaxInfo] {
        holdings.sorted { $0.unrealizedGain < $1.unrealizedGain }
    }
    
    /// Tax loss harvesting opportunities
    public var harvestingOpportunities: [HoldingTaxInfo] {
        holdings.filter { $0.unrealizedGain < 0 && abs($0.unrealizedGain) > 100 }
    }
    
    public init(holdings: [HoldingTaxInfo]) {
        self.holdings = holdings
        self.totalCostBasis = holdings.reduce(0) { $0 + $1.costBasis }
        self.totalCurrentValue = holdings.reduce(0) { $0 + $1.currentValue }
        self.totalUnrealizedGain = holdings.reduce(0) { $0 + $1.unrealizedGain }
        self.shortTermUnrealized = holdings.reduce(0) { $0 + $1.shortTermUnrealized }
        self.longTermUnrealized = holdings.reduce(0) { $0 + $1.longTermUnrealized }
    }
}

/// Tax info for a single holding
public struct HoldingTaxInfo: Identifiable {
    public let id: String
    public let symbol: String
    public let quantity: Double
    public let currentPrice: Double
    public let currentValue: Double
    public let costBasis: Double
    public let unrealizedGain: Double
    public let shortTermBasis: Double
    public let shortTermValue: Double
    public let shortTermUnrealized: Double
    public let longTermBasis: Double
    public let longTermValue: Double
    public let longTermUnrealized: Double
    public let lots: [TaxLot]
    
    public var unrealizedPercent: Double {
        guard costBasis > 0 else { return 0 }
        return (unrealizedGain / costBasis) * 100
    }
    
    public init(
        symbol: String,
        currentPrice: Double,
        lots: [TaxLot]
    ) {
        self.id = symbol
        self.symbol = symbol
        self.currentPrice = currentPrice
        self.lots = lots.filter { $0.symbol.uppercased() == symbol.uppercased() && !$0.isDepleted }
        
        self.quantity = self.lots.reduce(0) { $0 + $1.remainingQuantity }
        self.currentValue = quantity * currentPrice
        self.costBasis = self.lots.reduce(0) { $0 + $1.remainingCostBasis }
        self.unrealizedGain = currentValue - costBasis
        
        let shortTermLots = self.lots.filter { !$0.isLongTerm }
        let longTermLots = self.lots.filter { $0.isLongTerm }
        
        self.shortTermBasis = shortTermLots.reduce(0) { $0 + $1.remainingCostBasis }
        let shortTermQty = shortTermLots.reduce(0) { $0 + $1.remainingQuantity }
        self.shortTermValue = shortTermQty * currentPrice
        self.shortTermUnrealized = shortTermValue - shortTermBasis
        
        self.longTermBasis = longTermLots.reduce(0) { $0 + $1.remainingCostBasis }
        let longTermQty = longTermLots.reduce(0) { $0 + $1.remainingQuantity }
        self.longTermValue = longTermQty * currentPrice
        self.longTermUnrealized = longTermValue - longTermBasis
    }
}
