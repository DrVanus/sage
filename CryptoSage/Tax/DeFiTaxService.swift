//
//  DeFiTaxService.swift
//  CryptoSage
//
//  DeFi positions tax tracking and integration.
//

import Foundation

// MARK: - DeFi Tax Event Type

/// Types of taxable DeFi events
public enum DeFiTaxEventType: String, Codable, CaseIterable {
    case lpEntry = "lp_entry"           // Adding liquidity
    case lpExit = "lp_exit"             // Removing liquidity
    case lpReward = "lp_reward"         // LP trading fees earned
    case stakingEntry = "staking_entry" // Staking tokens
    case stakingExit = "staking_exit"   // Unstaking tokens
    case stakingReward = "staking_reward" // Staking rewards
    case lendingDeposit = "lending_deposit"
    case lendingWithdraw = "lending_withdraw"
    case lendingInterest = "lending_interest"
    case borrowStart = "borrow_start"
    case borrowRepay = "borrow_repay"
    case liquidation = "liquidation"
    case swap = "swap"                  // DEX swap
    case yieldClaim = "yield_claim"     // Claiming yield/rewards
    case impermanentLoss = "impermanent_loss" // IL realization on exit
    
    public var displayName: String {
        switch self {
        case .lpEntry: return "Add Liquidity"
        case .lpExit: return "Remove Liquidity"
        case .lpReward: return "LP Rewards"
        case .stakingEntry: return "Stake"
        case .stakingExit: return "Unstake"
        case .stakingReward: return "Staking Reward"
        case .lendingDeposit: return "Lend"
        case .lendingWithdraw: return "Withdraw Lending"
        case .lendingInterest: return "Interest Earned"
        case .borrowStart: return "Borrow"
        case .borrowRepay: return "Repay Loan"
        case .liquidation: return "Liquidation"
        case .swap: return "Swap"
        case .yieldClaim: return "Claim Rewards"
        case .impermanentLoss: return "Impermanent Loss"
        }
    }
    
    /// Whether this event type is taxable as income
    public var isTaxableIncome: Bool {
        switch self {
        case .lpReward, .stakingReward, .lendingInterest, .yieldClaim:
            return true
        default:
            return false
        }
    }
    
    /// Whether this event type triggers a disposal (capital gains)
    public var isDisposal: Bool {
        switch self {
        case .lpExit, .stakingExit, .lendingWithdraw, .swap, .liquidation:
            return true
        default:
            return false
        }
    }
    
    /// Convert to TaxLotSource for income events
    public var taxLotSource: TaxLotSource? {
        switch self {
        case .lpReward: return .rewards
        case .stakingReward: return .staking
        case .lendingInterest: return .interest
        case .yieldClaim: return .rewards
        default: return nil
        }
    }
}

// MARK: - DeFi Tax Event

/// A taxable DeFi event
public struct DeFiTaxEvent: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let type: DeFiTaxEventType
    public let protocolName: String
    public let chain: String
    public let tokens: [DeFiTaxToken]
    public let valueUSD: Double
    public let gasFeeUSD: Double?
    public let txHash: String?
    public let notes: String?
    
    public init(
        id: UUID = UUID(),
        date: Date,
        type: DeFiTaxEventType,
        protocolName: String,
        chain: String,
        tokens: [DeFiTaxToken],
        valueUSD: Double,
        gasFeeUSD: Double? = nil,
        txHash: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.protocolName = protocolName
        self.chain = chain
        self.tokens = tokens
        self.valueUSD = valueUSD
        self.gasFeeUSD = gasFeeUSD
        self.txHash = txHash
        self.notes = notes
    }
}

/// Token involved in a DeFi tax event
public struct DeFiTaxToken: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let quantity: Double
    public let priceUSD: Double
    public let isOutgoing: Bool // true = sent/sold, false = received
    
    public init(
        id: UUID = UUID(),
        symbol: String,
        quantity: Double,
        priceUSD: Double,
        isOutgoing: Bool
    ) {
        self.id = id
        self.symbol = symbol
        self.quantity = quantity
        self.priceUSD = priceUSD
        self.isOutgoing = isOutgoing
    }
    
    public var valueUSD: Double {
        quantity * priceUSD
    }
}

// MARK: - DeFi Tax Service

/// Service for tracking and calculating DeFi taxes
public final class DeFiTaxService {
    
    public static let shared = DeFiTaxService()
    
    private let lotManager = TaxLotManager.shared
    private let taxEngine = TaxEngine.shared
    
    private let storageKey = "CryptoSage.DeFiTaxEvents"
    
    @Published public private(set) var events: [DeFiTaxEvent] = []
    
    private init() {
        loadEvents()
    }
    
    // MARK: - Public API
    
    /// Process a DeFi event for tax purposes
    public func processDeFiEvent(_ event: DeFiTaxEvent) {
        events.append(event)
        
        // Convert to tax lots or disposals based on event type
        switch event.type {
        case .lpReward, .stakingReward, .lendingInterest, .yieldClaim:
            // Income event - create lots with FMV as cost basis
            for token in event.tokens where !token.isOutgoing {
                _ = lotManager.createLotFromIncome(
                    symbol: token.symbol,
                    quantity: token.quantity,
                    fairMarketValue: token.priceUSD,
                    date: event.date,
                    source: event.type.taxLotSource ?? .rewards,
                    exchange: event.protocolName,
                    txHash: event.txHash
                )
            }
            
        case .lpEntry, .stakingEntry, .lendingDeposit:
            // No taxable event on entry (just a transfer of value)
            // But track for cost basis when exiting
            break
            
        case .lpExit, .stakingExit, .lendingWithdraw:
            // Disposal event - calculate gains/losses
            for token in event.tokens where token.isOutgoing {
                _ = taxEngine.processSale(
                    symbol: token.symbol,
                    quantity: token.quantity,
                    proceedsPerUnit: token.priceUSD,
                    date: event.date,
                    exchange: event.protocolName,
                    txHash: event.txHash,
                    fee: event.gasFeeUSD
                )
            }
            
            // Create new lots for any received tokens
            for token in event.tokens where !token.isOutgoing {
                _ = lotManager.createLotFromPurchase(
                    symbol: token.symbol,
                    quantity: token.quantity,
                    pricePerUnit: token.priceUSD,
                    date: event.date,
                    exchange: event.protocolName,
                    txHash: event.txHash
                )
            }
            
        case .swap:
            // DEX swap is a taxable trade
            let outgoingTokens = event.tokens.filter { $0.isOutgoing }
            let incomingTokens = event.tokens.filter { !$0.isOutgoing }
            
            for outToken in outgoingTokens {
                _ = taxEngine.processSale(
                    symbol: outToken.symbol,
                    quantity: outToken.quantity,
                    proceedsPerUnit: outToken.priceUSD,
                    date: event.date,
                    exchange: event.protocolName,
                    txHash: event.txHash,
                    fee: event.gasFeeUSD
                )
            }
            
            for inToken in incomingTokens {
                _ = lotManager.createLotFromPurchase(
                    symbol: inToken.symbol,
                    quantity: inToken.quantity,
                    pricePerUnit: inToken.priceUSD,
                    date: event.date,
                    exchange: event.protocolName,
                    txHash: event.txHash
                )
            }
            
        case .liquidation:
            // Forced sale - treated as disposal
            for token in event.tokens where token.isOutgoing {
                let lots = lotManager.lots
                
                let disposal = TaxDisposal(
                    lotId: lots.first(where: { $0.symbol == token.symbol && !$0.isDepleted })?.id ?? UUID(),
                    symbol: token.symbol,
                    quantity: token.quantity,
                    costBasisPerUnit: lots.first(where: { $0.symbol == token.symbol })?.costBasisPerUnit ?? 0,
                    proceedsPerUnit: token.priceUSD,
                    acquiredDate: lots.first(where: { $0.symbol == token.symbol })?.acquiredDate ?? event.date,
                    disposedDate: event.date,
                    eventType: .marginLiquidation,
                    exchange: event.protocolName,
                    txHash: event.txHash
                )
                lotManager.addDisposal(disposal)
            }
            
        case .borrowStart, .borrowRepay:
            // Borrowing is not a taxable event
            break
            
        case .impermanentLoss:
            // IL is realized on exit - already handled by lpExit
            break
        }
        
        saveEvents()
    }
    
    /// Calculate impermanent loss for an LP position
    public func calculateImpermanentLoss(
        entryPrice0: Double,
        entryPrice1: Double,
        currentPrice0: Double,
        currentPrice1: Double,
        entryValue: Double
    ) -> ImpermanentLossResult {
        // Price ratio change
        let entryRatio = entryPrice0 / entryPrice1
        let currentRatio = currentPrice0 / currentPrice1
        let ratioChange = currentRatio / entryRatio
        
        // IL formula: 2 * sqrt(ratioChange) / (1 + ratioChange) - 1
        let sqrtRatio = sqrt(ratioChange)
        let ilPercent = 2 * sqrtRatio / (1 + ratioChange) - 1
        
        // Value if held vs LP
        let holdValue = entryValue * (1 + (currentPrice0 / entryPrice0 - 1 + currentPrice1 / entryPrice1 - 1) / 2)
        let lpValue = entryValue * (1 + ilPercent)
        let ilAmount = holdValue - lpValue
        
        return ImpermanentLossResult(
            ilPercent: abs(ilPercent) * 100,
            ilAmountUSD: abs(ilAmount),
            holdValueUSD: holdValue,
            lpValueUSD: lpValue
        )
    }
    
    /// Get DeFi income for a tax year
    public func defiIncome(for taxYear: TaxYear) -> Double {
        events
            .filter { taxYear.contains($0.date) && $0.type.isTaxableIncome }
            .reduce(0) { $0 + $1.valueUSD }
    }
    
    /// Get DeFi events for a tax year
    public func events(for taxYear: TaxYear) -> [DeFiTaxEvent] {
        events.filter { taxYear.contains($0.date) }
    }
    
    /// Get events by type
    public func events(ofType type: DeFiTaxEventType) -> [DeFiTaxEvent] {
        events.filter { $0.type == type }
    }
    
    /// Get events by protocol
    public func events(forProtocol protocolName: String) -> [DeFiTaxEvent] {
        events.filter { $0.protocolName.lowercased() == protocolName.lowercased() }
    }
    
    /// Clear all DeFi events
    public func clearAllEvents() {
        events.removeAll()
        saveEvents()
    }
    
    /// Delete a specific event
    public func deleteEvent(_ event: DeFiTaxEvent) {
        events.removeAll { $0.id == event.id }
        saveEvents()
    }
    
    // MARK: - Persistence
    
    private func saveEvents() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadEvents() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let loaded = try? JSONDecoder().decode([DeFiTaxEvent].self, from: data) {
            events = loaded
        }
    }
}

// MARK: - Impermanent Loss Result

public struct ImpermanentLossResult {
    public let ilPercent: Double
    public let ilAmountUSD: Double
    public let holdValueUSD: Double
    public let lpValueUSD: Double
    
    public var hasSignificantLoss: Bool {
        ilPercent > 1 // More than 1% IL
    }
}

// MARK: - DeFi Tax Summary

/// Summary of DeFi tax implications
public struct DeFiTaxSummary {
    public let totalIncome: Double
    public let lpRewards: Double
    public let stakingRewards: Double
    public let interestEarned: Double
    public let swapCount: Int
    public let realizedIL: Double
    public let events: [DeFiTaxEvent]
    
    public init(from events: [DeFiTaxEvent]) {
        self.events = events
        
        self.lpRewards = events
            .filter { $0.type == .lpReward }
            .reduce(0) { $0 + $1.valueUSD }
        
        self.stakingRewards = events
            .filter { $0.type == .stakingReward }
            .reduce(0) { $0 + $1.valueUSD }
        
        self.interestEarned = events
            .filter { $0.type == .lendingInterest }
            .reduce(0) { $0 + $1.valueUSD }
        
        self.totalIncome = lpRewards + stakingRewards + interestEarned + events
            .filter { $0.type == .yieldClaim }
            .reduce(0) { $0 + $1.valueUSD }
        
        self.swapCount = events.filter { $0.type == .swap }.count
        
        self.realizedIL = events
            .filter { $0.type == .impermanentLoss }
            .reduce(0) { $0 + $1.valueUSD }
    }
}
