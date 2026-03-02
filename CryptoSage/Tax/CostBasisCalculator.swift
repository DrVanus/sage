//
//  CostBasisCalculator.swift
//  CryptoSage
//
//  Cost basis calculation using FIFO, LIFO, HIFO, and Specific ID methods.
//

import Foundation

// MARK: - Cost Basis Calculator

/// Calculates cost basis and generates disposals using various accounting methods
public final class CostBasisCalculator {
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Public API
    
    /// Calculate disposals for a sale using the specified accounting method
    /// - Parameters:
    ///   - symbol: The crypto symbol being sold
    ///   - quantity: Amount to sell
    ///   - proceeds: Sale price per unit
    ///   - date: Date of sale
    ///   - lots: Available tax lots (will be modified)
    ///   - method: Accounting method to use
    ///   - walletId: Optional wallet ID for per-wallet cost basis (IRS 2025 requirement)
    ///   - specificLotIds: For Specific ID method, the lots to use
    /// - Returns: Array of disposals and updated lots
    public func calculateDisposals(
        symbol: String,
        quantity: Double,
        proceedsPerUnit: Double,
        date: Date,
        lots: inout [TaxLot],
        method: AccountingMethod,
        eventType: TaxEventType = .sale,
        exchange: String? = nil,
        txHash: String? = nil,
        walletId: String? = nil,
        specificLotIds: [UUID]? = nil,
        usePerWalletBasis: Bool = false
    ) -> [TaxDisposal] {
        
        // Filter lots for this symbol
        let symbolUpper = symbol.uppercased()
        var availableLots: [TaxLot]
        
        // IRS 2025 per-wallet cost basis requirement
        if usePerWalletBasis && walletId != nil {
            availableLots = lots.filter { $0.symbol == symbolUpper && !$0.isDepleted && $0.walletId == walletId }
        } else {
            availableLots = lots.filter { $0.symbol == symbolUpper && !$0.isDepleted }
        }
        
        guard !availableLots.isEmpty else {
            #if DEBUG
            print("⚠️ No available lots for \(symbol)")
            #endif
            return []
        }
        
        // Sort lots based on method
        let sortedLots = sortLots(availableLots, method: method, specificIds: specificLotIds)
        
        var remainingQuantity = quantity
        var disposals: [TaxDisposal] = []
        
        // Process lots until we've disposed of the entire quantity
        for lot in sortedLots {
            guard remainingQuantity > 0.00000001 else { break }
            
            // Find the lot in our main array
            guard let index = lots.firstIndex(where: { $0.id == lot.id }) else { continue }
            
            // Calculate how much to take from this lot
            let available = lots[index].remainingQuantity
            let toConsume = min(remainingQuantity, available)
            
            guard toConsume > 0.00000001 else { continue }
            
            // Create disposal record
            let disposal = TaxDisposal(
                lotId: lot.id,
                symbol: symbolUpper,
                quantity: toConsume,
                costBasisPerUnit: lot.costBasisPerUnit,
                proceedsPerUnit: proceedsPerUnit,
                acquiredDate: lot.acquiredDate,
                disposedDate: date,
                eventType: eventType,
                exchange: exchange,
                txHash: txHash
            )
            disposals.append(disposal)
            
            // Update the lot
            lots[index].remainingQuantity -= toConsume
            remainingQuantity -= toConsume
        }
        
        if remainingQuantity > 0.00000001 {
            #if DEBUG
            print("⚠️ Insufficient lots to cover sale of \(quantity) \(symbol). Remaining: \(remainingQuantity)")
            #endif
        }
        
        return disposals
    }
    
    /// Sort lots based on accounting method
    private func sortLots(_ lots: [TaxLot], method: AccountingMethod, specificIds: [UUID]?) -> [TaxLot] {
        switch method {
        case .fifo:
            // First In, First Out - oldest lots first
            return lots.sorted { $0.acquiredDate < $1.acquiredDate }
            
        case .lifo:
            // Last In, First Out - newest lots first
            return lots.sorted { $0.acquiredDate > $1.acquiredDate }
            
        case .hifo:
            // Highest In, First Out - highest cost basis first (minimizes taxes)
            return lots.sorted { $0.costBasisPerUnit > $1.costBasisPerUnit }
            
        case .specificId:
            // Use specific lots in the order provided
            guard let ids = specificIds else { return lots }
            return ids.compactMap { id in lots.first { $0.id == id } }
        }
    }
    
    /// Calculate tax-optimized lot selection (for decision support)
    /// Returns lots sorted by tax efficiency (highest basis first, then long-term preference)
    public func taxOptimizedLots(
        _ lots: [TaxLot],
        forQuantity quantity: Double
    ) -> [TaxLot] {
        var sorted = lots.filter { !$0.isDepleted }
        
        // Score each lot: prefer high cost basis and long-term status
        sorted.sort { a, b in
            // Long-term gains are taxed at lower rates
            if a.isLongTerm != b.isLongTerm {
                return a.isLongTerm
            }
            // Higher cost basis = lower gain
            return a.costBasisPerUnit > b.costBasisPerUnit
        }
        
        // Return enough lots to cover the quantity
        var remaining = quantity
        var result: [TaxLot] = []
        
        for lot in sorted {
            guard remaining > 0.00000001 else { break }
            result.append(lot)
            remaining -= lot.remainingQuantity
        }
        
        return result
    }
    
    /// Preview gains/losses for a potential sale using different methods
    public func previewSale(
        symbol: String,
        quantity: Double,
        proceedsPerUnit: Double,
        lots: [TaxLot]
    ) -> SalePreview {
        
        let symbolUpper = symbol.uppercased()
        let availableLots = lots.filter { $0.symbol == symbolUpper && !$0.isDepleted }
        
        // Calculate for each method
        let fifoResult = previewForMethod(
            lots: availableLots,
            quantity: quantity,
            proceedsPerUnit: proceedsPerUnit,
            method: .fifo
        )
        
        let lifoResult = previewForMethod(
            lots: availableLots,
            quantity: quantity,
            proceedsPerUnit: proceedsPerUnit,
            method: .lifo
        )
        
        let hifoResult = previewForMethod(
            lots: availableLots,
            quantity: quantity,
            proceedsPerUnit: proceedsPerUnit,
            method: .hifo
        )
        
        return SalePreview(
            symbol: symbolUpper,
            quantity: quantity,
            proceedsPerUnit: proceedsPerUnit,
            totalProceeds: quantity * proceedsPerUnit,
            fifo: fifoResult,
            lifo: lifoResult,
            hifo: hifoResult
        )
    }
    
    private func previewForMethod(
        lots: [TaxLot],
        quantity: Double,
        proceedsPerUnit: Double,
        method: AccountingMethod
    ) -> MethodPreview {
        
        let sortedLots = sortLots(lots, method: method, specificIds: nil)
        
        var remaining = quantity
        var totalCostBasis: Double = 0
        var shortTermGain: Double = 0
        var longTermGain: Double = 0
        
        for lot in sortedLots {
            guard remaining > 0.00000001 else { break }
            
            let toConsume = min(remaining, lot.remainingQuantity)
            let costBasis = toConsume * lot.costBasisPerUnit
            let proceeds = toConsume * proceedsPerUnit
            let gain = proceeds - costBasis
            
            totalCostBasis += costBasis
            
            if lot.isLongTerm {
                longTermGain += gain
            } else {
                shortTermGain += gain
            }
            
            remaining -= toConsume
        }
        
        return MethodPreview(
            method: method,
            costBasis: totalCostBasis,
            shortTermGain: shortTermGain,
            longTermGain: longTermGain,
            totalGain: shortTermGain + longTermGain
        )
    }
}

// MARK: - Sale Preview

/// Preview of potential sale outcomes
public struct SalePreview {
    public let symbol: String
    public let quantity: Double
    public let proceedsPerUnit: Double
    public let totalProceeds: Double
    public let fifo: MethodPreview
    public let lifo: MethodPreview
    public let hifo: MethodPreview
    
    /// The method with the lowest tax burden
    public var recommendedMethod: AccountingMethod {
        let methods = [fifo, lifo, hifo]
        return methods.min { $0.estimatedTax < $1.estimatedTax }?.method ?? .fifo
    }
    
    /// Potential tax savings by using HIFO vs FIFO
    public var hifoSavings: Double {
        fifo.estimatedTax - hifo.estimatedTax
    }
}

/// Preview for a specific accounting method
public struct MethodPreview {
    public let method: AccountingMethod
    public let costBasis: Double
    public let shortTermGain: Double
    public let longTermGain: Double
    public let totalGain: Double
    
    /// Estimated tax (rough estimate using typical rates)
    public var estimatedTax: Double {
        let shortTermRate = 0.32 // Assume 32% marginal rate
        let longTermRate = 0.15  // Assume 15% LTCG rate
        
        let stTax = max(0, shortTermGain) * shortTermRate
        let ltTax = max(0, longTermGain) * longTermRate
        
        // Losses can offset gains
        let stLoss = min(0, shortTermGain)
        let ltLoss = min(0, longTermGain)
        let totalLoss = stLoss + ltLoss
        
        // Simplified: losses reduce tax liability
        return max(0, stTax + ltTax + (totalLoss * shortTermRate))
    }
}

// MARK: - Wash Sale Detector

/// Detects potential wash sales
public final class WashSaleDetector {
    
    private let washSalePeriod: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    
    public init() {}
    
    /// Detect wash sales from disposals and lots
    public func detectWashSales(
        disposals: [TaxDisposal],
        lots: [TaxLot]
    ) -> [WashSale] {
        
        var washSales: [WashSale] = []
        
        // Only check disposals that have losses
        let lossDisposals = disposals.filter { $0.isLoss }
        
        for disposal in lossDisposals {
            // Check if there's a repurchase within 30 days (before or after)
            let windowStart = disposal.disposedDate.addingTimeInterval(-washSalePeriod)
            let windowEnd = disposal.disposedDate.addingTimeInterval(washSalePeriod)
            
            let repurchases = lots.filter { lot in
                lot.symbol == disposal.symbol &&
                lot.acquiredDate >= windowStart &&
                lot.acquiredDate <= windowEnd &&
                lot.acquiredDate != disposal.disposedDate // Not the same transaction
            }
            
            for repurchase in repurchases {
                // Calculate disallowed loss
                let lossQuantity = disposal.quantity
                let repurchaseQuantity = repurchase.originalQuantity
                let affectedQuantity = min(lossQuantity, repurchaseQuantity)
                let disallowedLoss = (disposal.gain / disposal.quantity) * affectedQuantity // gain is negative for losses
                
                let washSale = WashSale(
                    saleDate: disposal.disposedDate,
                    repurchaseDate: repurchase.acquiredDate,
                    symbol: disposal.symbol,
                    saleQuantity: disposal.quantity,
                    repurchaseQuantity: repurchase.originalQuantity,
                    disallowedLoss: abs(disallowedLoss),
                    affectedDisposalId: disposal.id,
                    affectedLotId: repurchase.id
                )
                washSales.append(washSale)
            }
        }
        
        return washSales
    }
}
