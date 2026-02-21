//
//  TaxLot.swift
//  CryptoSage
//
//  Tax lot tracking and management.
//

import Foundation
import Combine

// MARK: - Tax Lot Manager

/// Manages tax lots for a portfolio
public final class TaxLotManager: ObservableObject {
    public static let shared = TaxLotManager()
    
    // MARK: - Published Properties
    
    @Published public private(set) var lots: [TaxLot] = []
    @Published public private(set) var disposals: [TaxDisposal] = []
    @Published public private(set) var incomeEvents: [IncomeEvent] = []
    @Published public private(set) var washSales: [WashSale] = []
    
    // MARK: - Private Properties
    
    private let storageKey = "CryptoSage.TaxLots"
    private let disposalsKey = "CryptoSage.TaxDisposals"
    private let incomeKey = "CryptoSage.IncomeEvents"
    private let washSalesKey = "CryptoSage.WashSales"
    
    // MARK: - Initialization
    
    private init() {
        loadData()
    }
    
    // MARK: - Public API
    
    /// Add a new tax lot (acquisition)
    public func addLot(_ lot: TaxLot) {
        lots.append(lot)
        lots.sort { $0.acquiredDate < $1.acquiredDate }
        saveData()
    }
    
    /// Add multiple lots
    public func addLots(_ newLots: [TaxLot]) {
        lots.append(contentsOf: newLots)
        lots.sort { $0.acquiredDate < $1.acquiredDate }
        saveData()
    }
    
    /// Create a lot from a purchase transaction
    public func createLotFromPurchase(
        symbol: String,
        quantity: Double,
        pricePerUnit: Double,
        date: Date,
        exchange: String? = nil,
        txHash: String? = nil,
        fee: Double? = nil,
        walletId: String? = nil
    ) -> TaxLot {
        // Add fee to cost basis if present
        let adjustedCostBasis = fee != nil && fee! > 0 ? pricePerUnit + (fee! / quantity) : pricePerUnit
        
        let lot = TaxLot(
            symbol: symbol,
            quantity: quantity,
            costBasisPerUnit: adjustedCostBasis,
            acquiredDate: date,
            source: .purchase,
            exchange: exchange,
            txHash: txHash,
            walletId: walletId,
            fee: fee
        )
        addLot(lot)
        return lot
    }
    
    /// Create a lot from income (mining, staking, etc.)
    public func createLotFromIncome(
        symbol: String,
        quantity: Double,
        fairMarketValue: Double,
        date: Date,
        source: TaxLotSource,
        exchange: String? = nil,
        txHash: String? = nil,
        walletId: String? = nil
    ) -> TaxLot {
        // Record income event
        let incomeEvent = IncomeEvent(
            date: date,
            source: source,
            symbol: symbol,
            quantity: quantity,
            fairMarketValuePerUnit: fairMarketValue,
            exchange: exchange,
            txHash: txHash
        )
        incomeEvents.append(incomeEvent)
        
        // Create lot with FMV as cost basis
        let lot = TaxLot(
            symbol: symbol,
            quantity: quantity,
            costBasisPerUnit: fairMarketValue,
            acquiredDate: date,
            source: source,
            exchange: exchange,
            txHash: txHash,
            walletId: walletId
        )
        addLot(lot)
        saveData()
        
        return lot
    }
    
    /// Get available lots for a symbol
    public func availableLots(for symbol: String) -> [TaxLot] {
        lots.filter { $0.symbol.uppercased() == symbol.uppercased() && !$0.isDepleted }
    }
    
    /// Get total available quantity for a symbol
    public func availableQuantity(for symbol: String) -> Double {
        availableLots(for: symbol).reduce(0) { $0 + $1.remainingQuantity }
    }
    
    /// Get average cost basis for a symbol
    public func averageCostBasis(for symbol: String) -> Double? {
        let available = availableLots(for: symbol)
        guard !available.isEmpty else { return nil }
        
        let totalCost = available.reduce(0) { $0 + $1.remainingCostBasis }
        let totalQty = available.reduce(0) { $0 + $1.remainingQuantity }
        
        return totalQty > 0 ? totalCost / totalQty : nil
    }
    
    /// Get all unique symbols
    public var symbols: [String] {
        Array(Set(lots.map { $0.symbol })).sorted()
    }
    
    /// Get lots for a specific tax year
    public func lots(for taxYear: TaxYear) -> [TaxLot] {
        lots.filter { taxYear.contains($0.acquiredDate) }
    }
    
    /// Get disposals for a specific tax year
    public func disposals(for taxYear: TaxYear) -> [TaxDisposal] {
        disposals.filter { taxYear.contains($0.disposedDate) }
    }
    
    /// Add a disposal record
    public func addDisposal(_ disposal: TaxDisposal) {
        disposals.append(disposal)
        disposals.sort { $0.disposedDate < $1.disposedDate }
        saveData()
    }
    
    /// Record a wash sale
    public func recordWashSale(_ washSale: WashSale) {
        washSales.append(washSale)
        saveData()
    }
    
    /// Clear all data
    public func clearAll() {
        lots.removeAll()
        disposals.removeAll()
        incomeEvents.removeAll()
        washSales.removeAll()
        saveData()
    }
    
    /// Delete a specific lot
    public func deleteLot(_ lot: TaxLot) {
        lots.removeAll { $0.id == lot.id }
        saveData()
    }
    
    /// Delete a specific disposal
    public func deleteDisposal(_ disposal: TaxDisposal) {
        disposals.removeAll { $0.id == disposal.id }
        saveData()
    }
    
    /// Delete a specific income event
    public func deleteIncomeEvent(_ income: IncomeEvent) {
        incomeEvents.removeAll { $0.id == income.id }
        // Also delete the associated lot if it exists
        lots.removeAll { $0.symbol == income.symbol && $0.acquiredDate == income.date && $0.source == income.source }
        saveData()
    }
    
    /// Update a lot
    public func updateLot(_ lot: TaxLot) {
        if let index = lots.firstIndex(where: { $0.id == lot.id }) {
            lots[index] = lot
            saveData()
        }
    }
    
    /// Import lots from transactions
    func importFromTransactions(_ transactions: [Transaction]) {
        for tx in transactions {
            if tx.isBuy {
                _ = createLotFromPurchase(
                    symbol: tx.coinSymbol,
                    quantity: tx.quantity,
                    pricePerUnit: tx.pricePerUnit,
                    date: tx.date
                )
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveData() {
        if let lotsData = try? JSONEncoder().encode(lots) {
            UserDefaults.standard.set(lotsData, forKey: storageKey)
        }
        if let disposalsData = try? JSONEncoder().encode(disposals) {
            UserDefaults.standard.set(disposalsData, forKey: disposalsKey)
        }
        if let incomeData = try? JSONEncoder().encode(incomeEvents) {
            UserDefaults.standard.set(incomeData, forKey: incomeKey)
        }
        if let washData = try? JSONEncoder().encode(washSales) {
            UserDefaults.standard.set(washData, forKey: washSalesKey)
        }
    }
    
    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let loaded = try? JSONDecoder().decode([TaxLot].self, from: data) {
            lots = loaded
        }
        if let data = UserDefaults.standard.data(forKey: disposalsKey),
           let loaded = try? JSONDecoder().decode([TaxDisposal].self, from: data) {
            disposals = loaded
        }
        if let data = UserDefaults.standard.data(forKey: incomeKey),
           let loaded = try? JSONDecoder().decode([IncomeEvent].self, from: data) {
            incomeEvents = loaded
        }
        if let data = UserDefaults.standard.data(forKey: washSalesKey),
           let loaded = try? JSONDecoder().decode([WashSale].self, from: data) {
            washSales = loaded
        }
    }
}

// MARK: - Lot Grouping

extension TaxLotManager {
    
    /// Group lots by symbol
    public var lotsBySymbol: [String: [TaxLot]] {
        Dictionary(grouping: lots) { $0.symbol }
    }
    
    /// Group lots by source
    public var lotsBySource: [TaxLotSource: [TaxLot]] {
        Dictionary(grouping: lots) { $0.source }
    }
    
    /// Group lots by year
    public var lotsByYear: [Int: [TaxLot]] {
        Dictionary(grouping: lots) { Calendar.current.component(.year, from: $0.acquiredDate) }
    }
    
    /// Group lots by wallet (for per-wallet cost basis tracking - IRS 2025 requirement)
    public var lotsByWallet: [String: [TaxLot]] {
        var result: [String: [TaxLot]] = [:]
        for lot in lots {
            let walletKey = lot.walletId ?? "default"
            result[walletKey, default: []].append(lot)
        }
        return result
    }
    
    /// Get all unique wallet IDs
    public var walletIds: [String] {
        let ids = Set(lots.compactMap { $0.walletId })
        return Array(ids).sorted()
    }
    
    /// Get available lots for a symbol in a specific wallet
    public func availableLots(for symbol: String, walletId: String?) -> [TaxLot] {
        lots.filter {
            $0.symbol.uppercased() == symbol.uppercased() &&
            !$0.isDepleted &&
            $0.walletId == walletId
        }
    }
    
    /// Get cost basis summary by wallet
    public func costBasisByWallet(for symbol: String) -> [String: Double] {
        var result: [String: Double] = [:]
        for lot in availableLots(for: symbol) {
            let walletKey = lot.walletId ?? "default"
            result[walletKey, default: 0] += lot.remainingCostBasis
        }
        return result
    }
    
    /// Get per-wallet cost basis summary
    public func perWalletSummary() -> [WalletCostBasisSummary] {
        var summaries: [WalletCostBasisSummary] = []
        
        for (walletId, walletLots) in lotsByWallet {
            let activeLots = walletLots.filter { !$0.isDepleted }
            let totalBasis = activeLots.reduce(0) { $0 + $1.remainingCostBasis }
            let symbols = Set(activeLots.map { $0.symbol })
            
            summaries.append(WalletCostBasisSummary(
                walletId: walletId,
                totalCostBasis: totalBasis,
                lotCount: activeLots.count,
                symbols: Array(symbols).sorted()
            ))
        }
        
        return summaries.sorted { $0.totalCostBasis > $1.totalCostBasis }
    }
    
    /// Summary of unrealized gains/losses
    public func unrealizedSummary(currentPrices: [String: Double]) -> UnrealizedSummary {
        var totalCostBasis: Double = 0
        var totalCurrentValue: Double = 0
        var shortTermBasis: Double = 0
        var shortTermValue: Double = 0
        var longTermBasis: Double = 0
        var longTermValue: Double = 0
        
        for lot in lots where !lot.isDepleted {
            let currentPrice = currentPrices[lot.symbol] ?? 0
            let basis = lot.remainingCostBasis
            let value = lot.remainingQuantity * currentPrice
            
            totalCostBasis += basis
            totalCurrentValue += value
            
            if lot.isLongTerm {
                longTermBasis += basis
                longTermValue += value
            } else {
                shortTermBasis += basis
                shortTermValue += value
            }
        }
        
        return UnrealizedSummary(
            totalCostBasis: totalCostBasis,
            totalCurrentValue: totalCurrentValue,
            totalUnrealizedGain: totalCurrentValue - totalCostBasis,
            shortTermBasis: shortTermBasis,
            shortTermValue: shortTermValue,
            shortTermUnrealizedGain: shortTermValue - shortTermBasis,
            longTermBasis: longTermBasis,
            longTermValue: longTermValue,
            longTermUnrealizedGain: longTermValue - longTermBasis
        )
    }
}

// MARK: - Unrealized Summary

public struct UnrealizedSummary {
    public let totalCostBasis: Double
    public let totalCurrentValue: Double
    public let totalUnrealizedGain: Double
    public let shortTermBasis: Double
    public let shortTermValue: Double
    public let shortTermUnrealizedGain: Double
    public let longTermBasis: Double
    public let longTermValue: Double
    public let longTermUnrealizedGain: Double
    
    public var totalUnrealizedPercent: Double {
        guard totalCostBasis > 0 else { return 0 }
        return (totalUnrealizedGain / totalCostBasis) * 100
    }
}

// MARK: - Wallet Cost Basis Summary

/// Summary of cost basis for a specific wallet (IRS 2025 per-wallet requirement)
public struct WalletCostBasisSummary: Identifiable {
    public let walletId: String
    public let totalCostBasis: Double
    public let lotCount: Int
    public let symbols: [String]
    
    public var id: String { walletId }
    
    public var displayName: String {
        walletId == "default" ? "Default Wallet" : walletId
    }
}
