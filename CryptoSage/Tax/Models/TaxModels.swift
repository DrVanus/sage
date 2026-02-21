//
//  TaxModels.swift
//  CryptoSage
//
//  Core models for tax calculation and reporting.
//

import Foundation

// MARK: - Accounting Methods

/// Cost basis accounting method for tax calculations
public enum AccountingMethod: String, Codable, CaseIterable, Identifiable {
    case fifo = "FIFO"       // First In, First Out (default, most common)
    case lifo = "LIFO"       // Last In, First Out
    case hifo = "HIFO"       // Highest In, First Out (tax optimized)
    case specificId = "SPEC" // Specific Identification (manual selection)
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .fifo: return "First In, First Out (FIFO)"
        case .lifo: return "Last In, First Out (LIFO)"
        case .hifo: return "Highest In, First Out (HIFO)"
        case .specificId: return "Specific Identification"
        }
    }
    
    public var shortDescription: String {
        switch self {
        case .fifo: return "Sell oldest coins first"
        case .lifo: return "Sell newest coins first"
        case .hifo: return "Sell highest cost basis first (minimize taxes)"
        case .specificId: return "Manually select which lots to sell"
        }
    }
    
    /// SF Symbol icon name for visual identification
    public var iconName: String {
        switch self {
        case .fifo: return "arrow.up.arrow.down"
        case .lifo: return "arrow.down.arrow.up"
        case .hifo: return "chart.line.uptrend.xyaxis"
        case .specificId: return "hand.point.up.fill"
        }
    }
}

// MARK: - Tax Lot Source

/// Source of acquired crypto assets
public enum TaxLotSource: String, Codable, CaseIterable {
    case purchase = "purchase"         // Bought with fiat
    case trade = "trade"               // Crypto-to-crypto trade
    case mining = "mining"             // Mining rewards
    case staking = "staking"           // Staking rewards
    case airdrop = "airdrop"           // Airdrops
    case fork = "fork"                 // Hard fork
    case gift = "gift"                 // Received as gift
    case income = "income"             // Payment for services
    case interest = "interest"         // DeFi lending interest
    case rewards = "rewards"           // Protocol rewards
    case transfer = "transfer"         // Transfer from own wallet
    case unknown = "unknown"
    
    public var displayName: String {
        switch self {
        case .purchase: return "Purchase"
        case .trade: return "Trade"
        case .mining: return "Mining"
        case .staking: return "Staking Reward"
        case .airdrop: return "Airdrop"
        case .fork: return "Fork"
        case .gift: return "Gift Received"
        case .income: return "Income"
        case .interest: return "Interest"
        case .rewards: return "Rewards"
        case .transfer: return "Transfer"
        case .unknown: return "Unknown"
        }
    }
    
    /// Whether this source is taxable as income when received
    public var isTaxableOnReceipt: Bool {
        switch self {
        case .mining, .staking, .income, .interest, .rewards:
            return true
        case .airdrop: // Airdrops may be taxable depending on jurisdiction
            return true
        default:
            return false
        }
    }
}

// MARK: - Tax Event Type

/// Type of taxable event
public enum TaxEventType: String, Codable {
    case sale = "sale"                 // Sold for fiat
    case trade = "trade"               // Crypto-to-crypto trade
    case spend = "spend"               // Used to purchase goods/services
    case gift = "gift"                 // Given as gift
    case loss = "loss"                 // Lost/stolen (deductible)
    case income = "income"             // Received as income
    case marginLiquidation = "margin_liquidation"
    
    public var displayName: String {
        switch self {
        case .sale: return "Sale"
        case .trade: return "Trade"
        case .spend: return "Spend"
        case .gift: return "Gift"
        case .loss: return "Loss"
        case .income: return "Income"
        case .marginLiquidation: return "Liquidation"
        }
    }
}

// MARK: - Gain Type

/// Classification of capital gain/loss
public enum GainType: String, Codable {
    case shortTerm = "short_term"      // Held < 1 year
    case longTerm = "long_term"        // Held >= 1 year
    
    public var displayName: String {
        switch self {
        case .shortTerm: return "Short-Term"
        case .longTerm: return "Long-Term"
        }
    }
    
    /// Determine gain type based on holding period
    public static func classify(acquiredDate: Date, disposedDate: Date) -> GainType {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: acquiredDate, to: disposedDate)
        let days = components.day ?? 0
        return days >= 365 ? .longTerm : .shortTerm
    }
}

// MARK: - Tax Lot

/// A tax lot representing an acquisition of crypto
public struct TaxLot: Identifiable, Codable, Equatable {
    public let id: UUID
    public let symbol: String
    public let originalQuantity: Double
    public var remainingQuantity: Double
    public let costBasisPerUnit: Double     // USD cost per unit at acquisition
    public let totalCostBasis: Double       // Total USD cost
    public let acquiredDate: Date
    public let source: TaxLotSource
    public let exchange: String?
    public let txHash: String?
    public let notes: String?
    public let walletId: String?            // Per-wallet cost basis tracking (IRS 2025 requirement)
    public let fee: Double?                 // Gas/transaction fee (added to cost basis)
    
    public init(
        id: UUID = UUID(),
        symbol: String,
        quantity: Double,
        costBasisPerUnit: Double,
        acquiredDate: Date,
        source: TaxLotSource = .purchase,
        exchange: String? = nil,
        txHash: String? = nil,
        notes: String? = nil,
        walletId: String? = nil,
        fee: Double? = nil
    ) {
        self.id = id
        self.symbol = symbol.uppercased()
        self.originalQuantity = quantity
        self.remainingQuantity = quantity
        self.costBasisPerUnit = costBasisPerUnit
        self.totalCostBasis = quantity * costBasisPerUnit
        self.acquiredDate = acquiredDate
        self.source = source
        self.exchange = exchange
        self.txHash = txHash
        self.notes = notes
        self.walletId = walletId
        self.fee = fee
    }
    
    /// Whether this lot is fully depleted
    public var isDepleted: Bool {
        remainingQuantity <= 0.00000001
    }
    
    /// Age of the lot in days
    public var ageInDays: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: acquiredDate, to: Date())
        return components.day ?? 0
    }
    
    /// Whether this lot qualifies for long-term gains
    public var isLongTerm: Bool {
        ageInDays >= 365
    }
    
    /// Remaining cost basis
    public var remainingCostBasis: Double {
        remainingQuantity * costBasisPerUnit
    }
    
    /// Consume quantity from this lot
    public mutating func consume(quantity: Double) -> Double {
        let consumed = min(quantity, remainingQuantity)
        remainingQuantity -= consumed
        return consumed
    }
}

// MARK: - Tax Disposal

/// Record of a disposal (sale/trade) from a tax lot
public struct TaxDisposal: Identifiable, Codable {
    public let id: UUID
    public let lotId: UUID
    public let symbol: String
    public let quantity: Double
    public let costBasisPerUnit: Double
    public let totalCostBasis: Double
    public let proceedsPerUnit: Double
    public let totalProceeds: Double
    public let acquiredDate: Date
    public let disposedDate: Date
    public let gainType: GainType
    public let gain: Double              // Positive = gain, negative = loss
    public let eventType: TaxEventType
    public let exchange: String?
    public let txHash: String?
    
    public init(
        id: UUID = UUID(),
        lotId: UUID,
        symbol: String,
        quantity: Double,
        costBasisPerUnit: Double,
        proceedsPerUnit: Double,
        acquiredDate: Date,
        disposedDate: Date,
        eventType: TaxEventType = .sale,
        exchange: String? = nil,
        txHash: String? = nil
    ) {
        self.id = id
        self.lotId = lotId
        self.symbol = symbol.uppercased()
        self.quantity = quantity
        self.costBasisPerUnit = costBasisPerUnit
        self.totalCostBasis = quantity * costBasisPerUnit
        self.proceedsPerUnit = proceedsPerUnit
        self.totalProceeds = quantity * proceedsPerUnit
        self.acquiredDate = acquiredDate
        self.disposedDate = disposedDate
        self.gainType = GainType.classify(acquiredDate: acquiredDate, disposedDate: disposedDate)
        self.gain = (proceedsPerUnit - costBasisPerUnit) * quantity
        self.eventType = eventType
        self.exchange = exchange
        self.txHash = txHash
    }
    
    /// Whether this is a gain (positive) or loss (negative)
    public var isGain: Bool { gain > 0 }
    public var isLoss: Bool { gain < 0 }
    
    /// Holding period in days
    public var holdingPeriodDays: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: acquiredDate, to: disposedDate)
        return components.day ?? 0
    }
}

// MARK: - Tax Event

/// A taxable event (sale, trade, income, etc.)
public struct TaxEvent: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let type: TaxEventType
    public let symbol: String
    public let quantity: Double
    public let pricePerUnit: Double        // USD price at time of event
    public let totalValue: Double
    public let fee: Double?
    public let exchange: String?
    public let txHash: String?
    public let notes: String?
    public var disposals: [TaxDisposal]    // Generated during processing
    
    public init(
        id: UUID = UUID(),
        date: Date,
        type: TaxEventType,
        symbol: String,
        quantity: Double,
        pricePerUnit: Double,
        fee: Double? = nil,
        exchange: String? = nil,
        txHash: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.symbol = symbol.uppercased()
        self.quantity = quantity
        self.pricePerUnit = pricePerUnit
        self.totalValue = quantity * pricePerUnit
        self.fee = fee
        self.exchange = exchange
        self.txHash = txHash
        self.notes = notes
        self.disposals = []
    }
    
    /// Total gain/loss from this event
    public var totalGain: Double {
        disposals.reduce(0) { $0 + $1.gain }
    }
    
    /// Total cost basis from this event
    public var totalCostBasis: Double {
        disposals.reduce(0) { $0 + $1.totalCostBasis }
    }
}

// MARK: - Income Event

/// Income event (mining, staking, airdrops, etc.)
public struct IncomeEvent: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let source: TaxLotSource
    public let symbol: String
    public let quantity: Double
    public let fairMarketValuePerUnit: Double
    public let totalValue: Double
    public let exchange: String?
    public let txHash: String?
    public let notes: String?
    
    public init(
        id: UUID = UUID(),
        date: Date,
        source: TaxLotSource,
        symbol: String,
        quantity: Double,
        fairMarketValuePerUnit: Double,
        exchange: String? = nil,
        txHash: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.source = source
        self.symbol = symbol.uppercased()
        self.quantity = quantity
        self.fairMarketValuePerUnit = fairMarketValuePerUnit
        self.totalValue = quantity * fairMarketValuePerUnit
        self.exchange = exchange
        self.txHash = txHash
        self.notes = notes
    }
}

// MARK: - Wash Sale

/// Potential wash sale (buying back within 30 days of a loss)
public struct WashSale: Identifiable, Codable {
    public let id: UUID
    public let saleDate: Date
    public let repurchaseDate: Date
    public let symbol: String
    public let saleQuantity: Double
    public let repurchaseQuantity: Double
    public let disallowedLoss: Double
    public let affectedDisposalId: UUID
    public let affectedLotId: UUID
    
    public init(
        id: UUID = UUID(),
        saleDate: Date,
        repurchaseDate: Date,
        symbol: String,
        saleQuantity: Double,
        repurchaseQuantity: Double,
        disallowedLoss: Double,
        affectedDisposalId: UUID,
        affectedLotId: UUID
    ) {
        self.id = id
        self.saleDate = saleDate
        self.repurchaseDate = repurchaseDate
        self.symbol = symbol.uppercased()
        self.saleQuantity = saleQuantity
        self.repurchaseQuantity = repurchaseQuantity
        self.disallowedLoss = disallowedLoss
        self.affectedDisposalId = affectedDisposalId
        self.affectedLotId = affectedLotId
    }
    
    /// Days between sale and repurchase
    public var daysBetween: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: saleDate, to: repurchaseDate)
        return abs(components.day ?? 0)
    }
}

// MARK: - Tax Year

/// Tax year for reporting
public struct TaxYear: Identifiable, Codable, Hashable {
    public let year: Int
    
    public var id: Int { year }
    
    public init(_ year: Int) {
        self.year = year
    }
    
    public var startDate: Date {
        let components = DateComponents(year: year, month: 1, day: 1)
        return Calendar.current.date(from: components) ?? Date()
    }
    
    public var endDate: Date {
        let components = DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59)
        return Calendar.current.date(from: components) ?? Date()
    }
    
    public var displayName: String {
        "Tax Year \(year)"
    }
    
    /// Check if a date falls within this tax year
    public func contains(_ date: Date) -> Bool {
        date >= startDate && date <= endDate
    }
    
    public static var current: TaxYear {
        TaxYear(Calendar.current.component(.year, from: Date()))
    }
    
    public static var previous: TaxYear {
        TaxYear(Calendar.current.component(.year, from: Date()) - 1)
    }
}

// MARK: - Form 8949 Row

/// Single row for IRS Form 8949
public struct Form8949Row: Identifiable, Codable {
    public let id: UUID
    public let description: String        // (a) Description of property
    public let dateAcquired: Date         // (b) Date acquired
    public let dateSold: Date             // (c) Date sold or disposed of
    public let proceeds: Double           // (d) Proceeds
    public let costBasis: Double          // (e) Cost or other basis
    public let adjustmentCode: String?    // (f) Code (W for wash sale, etc.)
    public let adjustmentAmount: Double?  // (g) Amount of adjustment
    public let gainOrLoss: Double         // (h) Gain or (loss)
    public let isShortTerm: Bool          // Part I (short-term) or Part II (long-term)
    
    public init(
        id: UUID = UUID(),
        description: String,
        dateAcquired: Date,
        dateSold: Date,
        proceeds: Double,
        costBasis: Double,
        adjustmentCode: String? = nil,
        adjustmentAmount: Double? = nil
    ) {
        self.id = id
        self.description = description
        self.dateAcquired = dateAcquired
        self.dateSold = dateSold
        self.proceeds = proceeds
        self.costBasis = costBasis
        self.adjustmentCode = adjustmentCode
        self.adjustmentAmount = adjustmentAmount
        
        let adjustedBasis = costBasis + (adjustmentAmount ?? 0)
        self.gainOrLoss = proceeds - adjustedBasis
        self.isShortTerm = GainType.classify(acquiredDate: dateAcquired, disposedDate: dateSold) == .shortTerm
    }
    
    /// Create from a TaxDisposal
    public static func from(disposal: TaxDisposal, washSaleAdjustment: Double? = nil) -> Form8949Row {
        Form8949Row(
            description: "\(disposal.quantity) \(disposal.symbol)",
            dateAcquired: disposal.acquiredDate,
            dateSold: disposal.disposedDate,
            proceeds: disposal.totalProceeds,
            costBasis: disposal.totalCostBasis,
            adjustmentCode: washSaleAdjustment != nil ? "W" : nil,
            adjustmentAmount: washSaleAdjustment
        )
    }
}
