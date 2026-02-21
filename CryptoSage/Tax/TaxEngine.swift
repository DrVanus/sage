//
//  TaxEngine.swift
//  CryptoSage
//
//  Core tax calculation engine.
//

import Foundation
import Combine

// MARK: - Tax Engine

/// Main tax calculation engine
public final class TaxEngine: ObservableObject {
    public static let shared = TaxEngine()
    
    // MARK: - Published Properties
    
    @Published public private(set) var isProcessing = false
    @Published public private(set) var lastReport: TaxReport?
    @Published public var accountingMethod: AccountingMethod = .fifo
    
    // MARK: - Dependencies
    
    private let lotManager = TaxLotManager.shared
    private let costBasisCalculator = CostBasisCalculator()
    private let washSaleDetector = WashSaleDetector()
    
    // MARK: - Initialization
    
    private init() {
        // Load saved accounting method preference
        if let saved = UserDefaults.standard.string(forKey: "TaxEngine.AccountingMethod"),
           let method = AccountingMethod(rawValue: saved) {
            accountingMethod = method
        }
    }
    
    // MARK: - Public API
    
    /// Set the accounting method
    public func setAccountingMethod(_ method: AccountingMethod) {
        accountingMethod = method
        UserDefaults.standard.set(method.rawValue, forKey: "TaxEngine.AccountingMethod")
    }
    
    /// Process a sale transaction
    @discardableResult
    public func processSale(
        symbol: String,
        quantity: Double,
        proceedsPerUnit: Double,
        date: Date,
        exchange: String? = nil,
        txHash: String? = nil,
        walletId: String? = nil,
        fee: Double? = nil,
        specificLotIds: [UUID]? = nil
    ) -> [TaxDisposal] {
        
        var lots = lotManager.lots
        
        // Adjust proceeds for fees (fees reduce net proceeds)
        let adjustedProceeds = fee != nil && fee! > 0 ? proceedsPerUnit - (fee! / quantity) : proceedsPerUnit
        
        // Check if per-wallet cost basis is enabled
        let usePerWallet = UserDefaults.standard.bool(forKey: "Tax.PerWalletCostBasis")
        
        let disposals = costBasisCalculator.calculateDisposals(
            symbol: symbol,
            quantity: quantity,
            proceedsPerUnit: adjustedProceeds,
            date: date,
            lots: &lots,
            method: specificLotIds != nil ? .specificId : accountingMethod,
            eventType: .sale,
            exchange: exchange,
            txHash: txHash,
            walletId: walletId,
            specificLotIds: specificLotIds,
            usePerWalletBasis: usePerWallet
        )
        
        // Update lots in manager
        for disposal in disposals {
            lotManager.addDisposal(disposal)
        }
        
        // Detect wash sales
        let allDisposals = lotManager.disposals
        let washSales = washSaleDetector.detectWashSales(
            disposals: allDisposals,
            lots: lots
        )
        for washSale in washSales where !lotManager.washSales.contains(where: { $0.id == washSale.id }) {
            lotManager.recordWashSale(washSale)
        }
        
        return disposals
    }
    
    /// Process a crypto-to-crypto trade
    @discardableResult
    public func processTrade(
        fromSymbol: String,
        fromQuantity: Double,
        fromPriceUSD: Double,
        toSymbol: String,
        toQuantity: Double,
        toPriceUSD: Double,
        date: Date,
        exchange: String? = nil,
        txHash: String? = nil
    ) -> [TaxDisposal] {
        
        // First, process the "sale" of the from-asset
        var lots = lotManager.lots
        
        let disposals = costBasisCalculator.calculateDisposals(
            symbol: fromSymbol,
            quantity: fromQuantity,
            proceedsPerUnit: fromPriceUSD,
            date: date,
            lots: &lots,
            method: accountingMethod,
            eventType: .trade,
            exchange: exchange,
            txHash: txHash
        )
        
        for disposal in disposals {
            lotManager.addDisposal(disposal)
        }
        
        // Then, create a new lot for the to-asset
        _ = lotManager.createLotFromPurchase(
            symbol: toSymbol,
            quantity: toQuantity,
            pricePerUnit: toPriceUSD,
            date: date,
            exchange: exchange,
            txHash: txHash
        )
        
        return disposals
    }
    
    /// Preview a sale to compare accounting methods
    public func previewSale(
        symbol: String,
        quantity: Double,
        proceedsPerUnit: Double
    ) -> SalePreview {
        return costBasisCalculator.previewSale(
            symbol: symbol,
            quantity: quantity,
            proceedsPerUnit: proceedsPerUnit,
            lots: lotManager.lots
        )
    }
    
    /// Generate a complete tax report for a tax year
    public func generateReport(for taxYear: TaxYear) -> TaxReport {
        isProcessing = true
        defer { isProcessing = false }
        
        let yearDisposals = lotManager.disposals(for: taxYear)
        let yearIncome = lotManager.incomeEvents.filter { taxYear.contains($0.date) }
        let yearWashSales = lotManager.washSales.filter { taxYear.contains($0.saleDate) }
        
        // Calculate gains by type
        let shortTermDisposals = yearDisposals.filter { $0.gainType == .shortTerm }
        let longTermDisposals = yearDisposals.filter { $0.gainType == .longTerm }
        
        let shortTermGain = shortTermDisposals.reduce(0) { $0 + $1.gain }
        let longTermGain = longTermDisposals.reduce(0) { $0 + $1.gain }
        
        // Calculate income
        let totalIncome = yearIncome.reduce(0) { $0 + $1.totalValue }
        
        // Wash sale adjustments
        let washSaleAdjustment = yearWashSales.reduce(0) { $0 + $1.disallowedLoss }
        
        // Generate Form 8949 rows
        var form8949Rows: [Form8949Row] = []
        for disposal in yearDisposals {
            let washSaleAdj = yearWashSales
                .first { $0.affectedDisposalId == disposal.id }
                .map { $0.disallowedLoss }
            
            form8949Rows.append(Form8949Row.from(disposal: disposal, washSaleAdjustment: washSaleAdj))
        }
        
        let report = TaxReport(
            taxYear: taxYear,
            accountingMethod: accountingMethod,
            shortTermGain: shortTermGain,
            longTermGain: longTermGain,
            totalIncome: totalIncome,
            washSaleAdjustment: washSaleAdjustment,
            disposals: yearDisposals,
            incomeEvents: yearIncome,
            washSales: yearWashSales,
            form8949Rows: form8949Rows,
            generatedAt: Date()
        )
        
        lastReport = report
        return report
    }
    
    /// Import transactions and generate lots
    func importTransactions(_ transactions: [Transaction]) {
        // Sort by date
        let sorted = transactions.sorted { $0.date < $1.date }
        
        for tx in sorted {
            if tx.isBuy {
                // Create a lot
                _ = lotManager.createLotFromPurchase(
                    symbol: tx.coinSymbol,
                    quantity: tx.quantity,
                    pricePerUnit: tx.pricePerUnit,
                    date: tx.date
                )
            } else {
                // Process as sale
                processSale(
                    symbol: tx.coinSymbol,
                    quantity: tx.quantity,
                    proceedsPerUnit: tx.pricePerUnit,
                    date: tx.date
                )
            }
        }
    }
    
    /// Get tax summary for multiple years
    public func multiYearSummary(years: [TaxYear]) -> [TaxYear: TaxYearSummary] {
        var summaries: [TaxYear: TaxYearSummary] = [:]
        
        for year in years {
            let disposals = lotManager.disposals(for: year)
            let income = lotManager.incomeEvents.filter { year.contains($0.date) }
            
            let shortTermGain = disposals.filter { $0.gainType == .shortTerm }.reduce(0) { $0 + $1.gain }
            let longTermGain = disposals.filter { $0.gainType == .longTerm }.reduce(0) { $0 + $1.gain }
            let totalIncome = income.reduce(0) { $0 + $1.totalValue }
            
            summaries[year] = TaxYearSummary(
                year: year,
                shortTermGain: shortTermGain,
                longTermGain: longTermGain,
                totalIncome: totalIncome,
                transactionCount: disposals.count
            )
        }
        
        return summaries
    }
}

// MARK: - Tax Report

/// Complete tax report for a year
public struct TaxReport: Codable, Identifiable {
    public let id: UUID
    public let taxYear: TaxYear
    public let accountingMethod: AccountingMethod
    public let shortTermGain: Double
    public let longTermGain: Double
    public let totalIncome: Double
    public let washSaleAdjustment: Double
    public let disposals: [TaxDisposal]
    public let incomeEvents: [IncomeEvent]
    public let washSales: [WashSale]
    public let form8949Rows: [Form8949Row]
    public let generatedAt: Date
    
    public init(
        id: UUID = UUID(),
        taxYear: TaxYear,
        accountingMethod: AccountingMethod,
        shortTermGain: Double,
        longTermGain: Double,
        totalIncome: Double,
        washSaleAdjustment: Double,
        disposals: [TaxDisposal],
        incomeEvents: [IncomeEvent],
        washSales: [WashSale],
        form8949Rows: [Form8949Row],
        generatedAt: Date
    ) {
        self.id = id
        self.taxYear = taxYear
        self.accountingMethod = accountingMethod
        self.shortTermGain = shortTermGain
        self.longTermGain = longTermGain
        self.totalIncome = totalIncome
        self.washSaleAdjustment = washSaleAdjustment
        self.disposals = disposals
        self.incomeEvents = incomeEvents
        self.washSales = washSales
        self.form8949Rows = form8949Rows
        self.generatedAt = generatedAt
    }
    
    /// Net capital gain/loss (after wash sale adjustment)
    public var netCapitalGain: Double {
        shortTermGain + longTermGain + washSaleAdjustment
    }
    
    /// Total taxable amount (capital gains + income)
    public var totalTaxable: Double {
        netCapitalGain + totalIncome
    }
    
    /// Number of short-term transactions
    public var shortTermCount: Int {
        form8949Rows.filter { $0.isShortTerm }.count
    }
    
    /// Number of long-term transactions
    public var longTermCount: Int {
        form8949Rows.filter { !$0.isShortTerm }.count
    }
    
    /// Whether there were any wash sales
    public var hasWashSales: Bool {
        !washSales.isEmpty
    }
}

// MARK: - Tax Year Summary

/// Summary for a single tax year
public struct TaxYearSummary: Identifiable {
    public let year: TaxYear
    public let shortTermGain: Double
    public let longTermGain: Double
    public let totalIncome: Double
    public let transactionCount: Int
    
    public var id: Int { year.year }
    
    public var totalGain: Double {
        shortTermGain + longTermGain
    }
}

// MARK: - Estimated Tax Calculator

extension TaxEngine {
    
    /// Estimate federal tax liability
    public func estimateFederalTax(
        shortTermGain: Double,
        longTermGain: Double,
        ordinaryIncome: Double,
        filingStatus: FilingStatus = .single
    ) -> EstimatedTax {
        
        let taxableIncome = ordinaryIncome + shortTermGain // Short-term taxed as ordinary income
        
        // 2024 tax brackets (simplified)
        let ordinaryTax = calculateOrdinaryTax(taxableIncome, status: filingStatus)
        
        // Long-term capital gains brackets
        let ltcgTax = calculateLTCGTax(longTermGain, ordinaryIncome: taxableIncome, status: filingStatus)
        
        // Net Investment Income Tax (3.8% for high earners)
        let niit = calculateNIIT(
            investmentIncome: shortTermGain + longTermGain,
            magi: taxableIncome + longTermGain,
            status: filingStatus
        )
        
        return EstimatedTax(
            shortTermTax: ordinaryTax,
            longTermTax: ltcgTax,
            niit: niit,
            totalEstimatedTax: ordinaryTax + ltcgTax + niit,
            effectiveRate: (ordinaryTax + ltcgTax + niit) / max(1, taxableIncome + longTermGain)
        )
    }
    
    private func calculateOrdinaryTax(_ income: Double, status: FilingStatus) -> Double {
        // 2024 brackets (simplified for single filer)
        let brackets: [(threshold: Double, rate: Double)] = [
            (11600, 0.10),
            (47150, 0.12),
            (100525, 0.22),
            (191950, 0.24),
            (243725, 0.32),
            (609350, 0.35),
            (Double.infinity, 0.37)
        ]
        
        var tax: Double = 0
        var remaining = income
        var previousThreshold: Double = 0
        
        for bracket in brackets {
            let taxableAtRate = min(remaining, bracket.threshold - previousThreshold)
            if taxableAtRate > 0 {
                tax += taxableAtRate * bracket.rate
                remaining -= taxableAtRate
            }
            previousThreshold = bracket.threshold
            if remaining <= 0 { break }
        }
        
        return max(0, tax)
    }
    
    private func calculateLTCGTax(_ gain: Double, ordinaryIncome: Double, status: FilingStatus) -> Double {
        guard gain > 0 else { return 0 }
        
        // 2024 LTCG brackets (single filer)
        let zeroRateThreshold: Double = 47025
        let fifteenRateThreshold: Double = 518900
        
        let totalIncome = ordinaryIncome + gain
        
        if totalIncome <= zeroRateThreshold {
            return 0
        } else if totalIncome <= fifteenRateThreshold {
            let taxableGain = min(gain, totalIncome - zeroRateThreshold)
            return max(0, taxableGain) * 0.15
        } else {
            let gainAt15 = max(0, fifteenRateThreshold - ordinaryIncome)
            let gainAt20 = gain - gainAt15
            return (gainAt15 * 0.15) + (max(0, gainAt20) * 0.20)
        }
    }
    
    private func calculateNIIT(investmentIncome: Double, magi: Double, status: FilingStatus) -> Double {
        // NIIT threshold for single filers
        let threshold: Double = 200000
        
        guard magi > threshold else { return 0 }
        
        let excessMAGI = magi - threshold
        let taxableAmount = min(investmentIncome, excessMAGI)
        
        return max(0, taxableAmount) * 0.038
    }
}

// MARK: - Filing Status

public enum FilingStatus: String, Codable, CaseIterable {
    case single = "single"
    case marriedFilingJointly = "married_jointly"
    case marriedFilingSeparately = "married_separately"
    case headOfHousehold = "head_of_household"
    
    public var displayName: String {
        switch self {
        case .single: return "Single"
        case .marriedFilingJointly: return "Married Filing Jointly"
        case .marriedFilingSeparately: return "Married Filing Separately"
        case .headOfHousehold: return "Head of Household"
        }
    }
    
    /// Abbreviated display name for compact UI elements like segmented pickers
    public var shortDisplayName: String {
        switch self {
        case .single: return "Single"
        case .marriedFilingJointly: return "Married Joint"
        case .marriedFilingSeparately: return "Married Sep."
        case .headOfHousehold: return "Head of House"
        }
    }
}

// MARK: - Estimated Tax

public struct EstimatedTax {
    public let shortTermTax: Double
    public let longTermTax: Double
    public let niit: Double
    public let totalEstimatedTax: Double
    public let effectiveRate: Double
}
