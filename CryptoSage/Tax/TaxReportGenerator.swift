//
//  TaxReportGenerator.swift
//  CryptoSage
//
//  Generate formatted tax reports including Form 8949 / Schedule D.
//

import Foundation
import SwiftUI

// MARK: - Tax Report Generator

/// Generates formatted tax reports
public final class TaxReportGenerator {
    
    public static let shared = TaxReportGenerator()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter
    }()
    
    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    private init() {}
    
    // MARK: - Form 8949 Generation
    
    /// Generate Form 8949 data structure
    public func generateForm8949(from report: TaxReport) -> Form8949 {
        let shortTermRows = report.form8949Rows.filter { $0.isShortTerm }
        let longTermRows = report.form8949Rows.filter { !$0.isShortTerm }
        
        return Form8949(
            taxYear: report.taxYear,
            partI: Form8949Part(
                type: .shortTerm,
                rows: shortTermRows,
                totalProceeds: shortTermRows.reduce(0) { $0 + $1.proceeds },
                totalCostBasis: shortTermRows.reduce(0) { $0 + $1.costBasis },
                totalAdjustments: shortTermRows.compactMap { $0.adjustmentAmount }.reduce(0, +),
                totalGainLoss: report.shortTermGain
            ),
            partII: Form8949Part(
                type: .longTerm,
                rows: longTermRows,
                totalProceeds: longTermRows.reduce(0) { $0 + $1.proceeds },
                totalCostBasis: longTermRows.reduce(0) { $0 + $1.costBasis },
                totalAdjustments: longTermRows.compactMap { $0.adjustmentAmount }.reduce(0, +),
                totalGainLoss: report.longTermGain
            ),
            generatedAt: Date()
        )
    }
    
    /// Generate Schedule D summary
    public func generateScheduleD(from report: TaxReport) -> ScheduleD {
        return ScheduleD(
            taxYear: report.taxYear,
            shortTermGainFromForm8949: report.shortTermGain,
            shortTermCarryover: 0, // Would need prior year data
            totalShortTermGainLoss: report.shortTermGain,
            longTermGainFromForm8949: report.longTermGain,
            longTermCarryover: 0,
            totalLongTermGainLoss: report.longTermGain,
            netCapitalGainLoss: report.netCapitalGain,
            generatedAt: Date()
        )
    }
    
    /// Generate a text summary of the tax report
    public func generateTextSummary(from report: TaxReport) -> String {
        var lines: [String] = []
        
        lines.append("═══════════════════════════════════════════════════════════════")
        lines.append("                    CRYPTO TAX REPORT")
        lines.append("                     Tax Year \(report.taxYear.year)")
        lines.append("═══════════════════════════════════════════════════════════════")
        lines.append("")
        lines.append("Generated: \(dateFormatter.string(from: report.generatedAt))")
        lines.append("Accounting Method: \(report.accountingMethod.displayName)")
        lines.append("")
        
        // Capital Gains Summary
        lines.append("───────────────────────────────────────────────────────────────")
        lines.append("                    CAPITAL GAINS SUMMARY")
        lines.append("───────────────────────────────────────────────────────────────")
        lines.append("")
        lines.append("SHORT-TERM (held < 1 year)")
        lines.append("  Transactions: \(report.shortTermCount)")
        lines.append("  Net Gain/Loss: \(formatCurrency(report.shortTermGain))")
        lines.append("")
        lines.append("LONG-TERM (held >= 1 year)")
        lines.append("  Transactions: \(report.longTermCount)")
        lines.append("  Net Gain/Loss: \(formatCurrency(report.longTermGain))")
        lines.append("")
        
        if report.hasWashSales {
            lines.append("WASH SALE ADJUSTMENTS")
            lines.append("  Disallowed Losses: \(formatCurrency(report.washSaleAdjustment))")
            lines.append("")
        }
        
        lines.append("───────────────────────────────────────────────────────────────")
        lines.append("NET CAPITAL GAIN/LOSS: \(formatCurrency(report.netCapitalGain))")
        lines.append("───────────────────────────────────────────────────────────────")
        lines.append("")
        
        // Income Summary
        if report.totalIncome > 0 {
            lines.append("───────────────────────────────────────────────────────────────")
            lines.append("                      INCOME SUMMARY")
            lines.append("───────────────────────────────────────────────────────────────")
            lines.append("")
            lines.append("Total Crypto Income: \(formatCurrency(report.totalIncome))")
            
            // Group by source
            let incomeBySource = Dictionary(grouping: report.incomeEvents) { $0.source }
            for (source, events) in incomeBySource.sorted(by: { $0.key.displayName < $1.key.displayName }) {
                let total = events.reduce(0) { $0 + $1.totalValue }
                lines.append("  \(source.displayName): \(formatCurrency(total))")
            }
            lines.append("")
        }
        
        // Transaction Details
        lines.append("───────────────────────────────────────────────────────────────")
        lines.append("                   TRANSACTION DETAILS")
        lines.append("───────────────────────────────────────────────────────────────")
        lines.append("")
        
        if !report.disposals.isEmpty {
            lines.append(String(format: "%-10s %-8s %12s %12s %12s %-10s",
                                "Date", "Asset", "Proceeds", "Cost Basis", "Gain/Loss", "Type"))
            lines.append(String(repeating: "-", count: 66))
            
            for disposal in report.disposals.prefix(50) { // Limit to 50 for readability
                let line = String(format: "%-10s %-8s %12s %12s %12s %-10s",
                                  shortDate(disposal.disposedDate),
                                  disposal.symbol,
                                  formatCurrency(disposal.totalProceeds),
                                  formatCurrency(disposal.totalCostBasis),
                                  formatCurrency(disposal.gain),
                                  disposal.gainType.displayName)
                lines.append(line)
            }
            
            if report.disposals.count > 50 {
                lines.append("... and \(report.disposals.count - 50) more transactions")
            }
        }
        
        lines.append("")
        lines.append("═══════════════════════════════════════════════════════════════")
        lines.append("                       END OF REPORT")
        lines.append("═══════════════════════════════════════════════════════════════")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Tax Optimization Report
    
    /// Generate tax optimization suggestions
    public func generateOptimizationReport(
        lots: [TaxLot],
        currentPrices: [String: Double]
    ) -> TaxOptimizationReport {
        
        var harvestingOpportunities: [TaxLossHarvestingAnalysis] = []
        var lotsApproachingLongTerm: [TaxLot] = []
        var highGainLots: [TaxLot] = []
        
        // Group lots by symbol
        let lotsBySymbol = Dictionary(grouping: lots.filter { !$0.isDepleted }) { $0.symbol }
        
        for (symbol, symbolLots) in lotsBySymbol {
            guard let price = currentPrices[symbol] else { continue }
            
            // Check for tax loss harvesting opportunities
            let analysis = TaxLossHarvestingAnalysis(
                symbol: symbol,
                currentPrice: price,
                lots: symbolLots
            )
            if analysis.isHarvestingRecommended {
                harvestingOpportunities.append(analysis)
            }
            
            // Check for lots approaching long-term status
            for lot in symbolLots {
                let daysToLongTerm = 365 - lot.ageInDays
                if daysToLongTerm > 0 && daysToLongTerm <= 30 {
                    lotsApproachingLongTerm.append(lot)
                }
            }
            
            // Check for high unrealized gains
            for lot in symbolLots {
                let unrealizedGain = (price - lot.costBasisPerUnit) * lot.remainingQuantity
                if unrealizedGain > 1000 { // Significant gain
                    highGainLots.append(lot)
                }
            }
        }
        
        return TaxOptimizationReport(
            harvestingOpportunities: harvestingOpportunities.sorted { $0.totalUnrealizedLoss > $1.totalUnrealizedLoss },
            lotsApproachingLongTerm: lotsApproachingLongTerm.sorted { $0.ageInDays > $1.ageInDays },
            highGainLots: highGainLots.sorted { a, b in
                let priceA = currentPrices[a.symbol] ?? 0
                let priceB = currentPrices[b.symbol] ?? 0
                let gainA = (priceA - a.costBasisPerUnit) * a.remainingQuantity
                let gainB = (priceB - b.costBasisPerUnit) * b.remainingQuantity
                return gainA > gainB
            },
            generatedAt: Date()
        )
    }
    
    // MARK: - Helpers
    
    private func formatCurrency(_ amount: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    private func shortDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

// MARK: - Form 8949 Structure

/// IRS Form 8949 data structure
public struct Form8949: Identifiable {
    public let id = UUID()
    public let taxYear: TaxYear
    public let partI: Form8949Part   // Short-term
    public let partII: Form8949Part  // Long-term
    public let generatedAt: Date
    
    public var totalTransactions: Int {
        partI.rows.count + partII.rows.count
    }
}

public struct Form8949Part {
    public let type: GainType
    public let rows: [Form8949Row]
    public let totalProceeds: Double
    public let totalCostBasis: Double
    public let totalAdjustments: Double
    public let totalGainLoss: Double
    
    public var title: String {
        switch type {
        case .shortTerm: return "Part I - Short-Term Capital Gains and Losses"
        case .longTerm: return "Part II - Long-Term Capital Gains and Losses"
        }
    }
}

// MARK: - Schedule D Structure

/// IRS Schedule D summary
public struct ScheduleD: Identifiable {
    public let id = UUID()
    public let taxYear: TaxYear
    
    // Part I - Short-Term
    public let shortTermGainFromForm8949: Double
    public let shortTermCarryover: Double
    public var totalShortTermGainLoss: Double
    
    // Part II - Long-Term
    public let longTermGainFromForm8949: Double
    public let longTermCarryover: Double
    public var totalLongTermGainLoss: Double
    
    // Part III - Summary
    public var netCapitalGainLoss: Double
    
    public let generatedAt: Date
    
    /// Line 16: If both parts are gains
    public var isBothGains: Bool {
        totalShortTermGainLoss > 0 && totalLongTermGainLoss > 0
    }
    
    /// Whether there's a net loss
    public var hasNetLoss: Bool {
        netCapitalGainLoss < 0
    }
    
    /// Capital loss carryover (max $3,000 deduction per year)
    public var capitalLossDeduction: Double {
        guard hasNetLoss else { return 0 }
        return min(abs(netCapitalGainLoss), 3000)
    }
    
    /// Loss to carry forward to next year
    public var lossCarryforward: Double {
        guard hasNetLoss else { return 0 }
        return max(0, abs(netCapitalGainLoss) - 3000)
    }
}

// MARK: - Tax Optimization Report

public struct TaxOptimizationReport {
    public let harvestingOpportunities: [TaxLossHarvestingAnalysis]
    public let lotsApproachingLongTerm: [TaxLot]
    public let highGainLots: [TaxLot]
    public let generatedAt: Date
    
    public var hasRecommendations: Bool {
        !harvestingOpportunities.isEmpty ||
        !lotsApproachingLongTerm.isEmpty ||
        !highGainLots.isEmpty
    }
    
    public var totalHarvestingPotential: Double {
        harvestingOpportunities.reduce(0) { $0 + $1.totalUnrealizedLoss }
    }
}
