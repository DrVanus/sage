//
//  NFTTaxService.swift
//  CryptoSage
//
//  NFT tax tracking service for buy/sell capital gains and royalty income.
//

import Foundation

// MARK: - NFT Tax Event Type

/// Types of taxable NFT events
public enum NFTTaxEventType: String, Codable, CaseIterable {
    case purchase = "purchase"      // Bought NFT
    case sale = "sale"              // Sold NFT
    case mint = "mint"              // Minted (created)
    case royalty = "royalty"        // Royalty income received
    case airdrop = "airdrop"        // Received as airdrop
    case gift = "gift"              // Received as gift
    case burn = "burn"              // Destroyed/burned
    case transfer = "transfer"      // Transferred (no value exchange)
    
    public var displayName: String {
        switch self {
        case .purchase: return "Purchase"
        case .sale: return "Sale"
        case .mint: return "Mint"
        case .royalty: return "Royalty"
        case .airdrop: return "Airdrop"
        case .gift: return "Gift Received"
        case .burn: return "Burn"
        case .transfer: return "Transfer"
        }
    }
    
    /// Whether this is a taxable acquisition
    public var isAcquisition: Bool {
        switch self {
        case .purchase, .mint, .airdrop, .gift:
            return true
        default:
            return false
        }
    }
    
    /// Whether this is a taxable disposal
    public var isDisposal: Bool {
        switch self {
        case .sale, .burn, .gift:
            return true
        default:
            return false
        }
    }
    
    /// Whether this generates income (not capital gains)
    public var isIncome: Bool {
        switch self {
        case .royalty, .airdrop:
            return true
        default:
            return false
        }
    }
}

// MARK: - NFT Tax Lot

/// A tax lot for an NFT
public struct NFTTaxLot: Identifiable, Codable {
    public let id: UUID
    public let contractAddress: String
    public let tokenId: String
    public let chain: String
    public let collectionName: String?
    public let nftName: String?
    public let acquiredDate: Date
    public let costBasisUSD: Double
    public let acquiredVia: NFTTaxEventType
    public let marketplace: String?
    public let txHash: String?
    public var disposedDate: Date?
    public var proceedsUSD: Double?
    public var isDisposed: Bool
    
    public init(
        id: UUID = UUID(),
        contractAddress: String,
        tokenId: String,
        chain: String,
        collectionName: String? = nil,
        nftName: String? = nil,
        acquiredDate: Date,
        costBasisUSD: Double,
        acquiredVia: NFTTaxEventType,
        marketplace: String? = nil,
        txHash: String? = nil
    ) {
        self.id = id
        self.contractAddress = contractAddress.lowercased()
        self.tokenId = tokenId
        self.chain = chain
        self.collectionName = collectionName
        self.nftName = nftName
        self.acquiredDate = acquiredDate
        self.costBasisUSD = costBasisUSD
        self.acquiredVia = acquiredVia
        self.marketplace = marketplace
        self.txHash = txHash
        self.disposedDate = nil
        self.proceedsUSD = nil
        self.isDisposed = false
    }
    
    /// Unique identifier for matching
    public var nftIdentifier: String {
        "\(chain):\(contractAddress):\(tokenId)"
    }
    
    /// Display name
    public var displayName: String {
        nftName ?? collectionName ?? "NFT #\(tokenId.prefix(8))"
    }
    
    /// Age in days
    public var ageInDays: Int {
        let calendar = Calendar.current
        let endDate = disposedDate ?? Date()
        let components = calendar.dateComponents([.day], from: acquiredDate, to: endDate)
        return components.day ?? 0
    }
    
    /// Whether qualifies for long-term gains
    public var isLongTerm: Bool {
        ageInDays >= 365
    }
    
    /// Capital gain/loss (if disposed)
    public var gain: Double? {
        guard let proceeds = proceedsUSD, isDisposed else { return nil }
        return proceeds - costBasisUSD
    }
}

// MARK: - NFT Royalty Event

/// Royalty income from NFT sales
public struct NFTRoyaltyEvent: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let contractAddress: String
    public let tokenId: String?
    public let collectionName: String?
    public let chain: String
    public let amountUSD: Double
    public let amountCrypto: Double?
    public let cryptoSymbol: String?
    public let salePrice: Double?
    public let royaltyPercent: Double?
    public let marketplace: String?
    public let txHash: String?
    
    public init(
        id: UUID = UUID(),
        date: Date,
        contractAddress: String,
        tokenId: String? = nil,
        collectionName: String? = nil,
        chain: String,
        amountUSD: Double,
        amountCrypto: Double? = nil,
        cryptoSymbol: String? = nil,
        salePrice: Double? = nil,
        royaltyPercent: Double? = nil,
        marketplace: String? = nil,
        txHash: String? = nil
    ) {
        self.id = id
        self.date = date
        self.contractAddress = contractAddress.lowercased()
        self.tokenId = tokenId
        self.collectionName = collectionName
        self.chain = chain
        self.amountUSD = amountUSD
        self.amountCrypto = amountCrypto
        self.cryptoSymbol = cryptoSymbol
        self.salePrice = salePrice
        self.royaltyPercent = royaltyPercent
        self.marketplace = marketplace
        self.txHash = txHash
    }
}

// MARK: - NFT Tax Service

/// Service for NFT tax tracking
public final class NFTTaxService: ObservableObject {
    
    public static let shared = NFTTaxService()
    
    private let lotsKey = "CryptoSage.NFTTaxLots"
    private let royaltiesKey = "CryptoSage.NFTRoyalties"
    
    @Published public private(set) var nftLots: [NFTTaxLot] = []
    @Published public private(set) var royaltyEvents: [NFTRoyaltyEvent] = []
    
    private init() {
        loadData()
    }
    
    // MARK: - Public API
    
    /// Record an NFT acquisition
    public func recordAcquisition(
        contractAddress: String,
        tokenId: String,
        chain: String,
        collectionName: String? = nil,
        nftName: String? = nil,
        date: Date,
        costBasisUSD: Double,
        acquiredVia: NFTTaxEventType,
        marketplace: String? = nil,
        txHash: String? = nil
    ) {
        let lot = NFTTaxLot(
            contractAddress: contractAddress,
            tokenId: tokenId,
            chain: chain,
            collectionName: collectionName,
            nftName: nftName,
            acquiredDate: date,
            costBasisUSD: costBasisUSD,
            acquiredVia: acquiredVia,
            marketplace: marketplace,
            txHash: txHash
        )
        nftLots.append(lot)
        saveData()
        
        // If acquired via airdrop, also record as income
        if acquiredVia == .airdrop {
            let lotManager = TaxLotManager.shared
            // Create a fungible lot for the value received
            _ = lotManager.createLotFromIncome(
                symbol: "NFT-\(collectionName ?? contractAddress.prefix(8).description)",
                quantity: 1,
                fairMarketValue: costBasisUSD,
                date: date,
                source: .airdrop,
                exchange: marketplace,
                txHash: txHash
            )
        }
    }
    
    /// Record an NFT sale
    public func recordSale(
        contractAddress: String,
        tokenId: String,
        chain: String,
        date: Date,
        proceedsUSD: Double,
        marketplace: String? = nil,
        txHash: String? = nil
    ) -> NFTSaleResult? {
        // Find the matching lot
        let identifier = "\(chain):\(contractAddress.lowercased()):\(tokenId)"
        guard let index = nftLots.firstIndex(where: { $0.nftIdentifier == identifier && !$0.isDisposed }) else {
            print("⚠️ No matching NFT lot found for \(identifier)")
            return nil
        }
        
        var lot = nftLots[index]
        lot.disposedDate = date
        lot.proceedsUSD = proceedsUSD
        lot.isDisposed = true
        nftLots[index] = lot
        saveData()
        
        // Create disposal record in tax system
        let gain = proceedsUSD - lot.costBasisUSD
        let gainType = GainType.classify(acquiredDate: lot.acquiredDate, disposedDate: date)
        
        // Add to tax disposals
        let disposal = TaxDisposal(
            lotId: lot.id,
            symbol: "NFT",
            quantity: 1,
            costBasisPerUnit: lot.costBasisUSD,
            proceedsPerUnit: proceedsUSD,
            acquiredDate: lot.acquiredDate,
            disposedDate: date,
            eventType: .sale,
            exchange: marketplace,
            txHash: txHash
        )
        TaxLotManager.shared.addDisposal(disposal)
        
        return NFTSaleResult(
            nft: lot,
            proceedsUSD: proceedsUSD,
            costBasisUSD: lot.costBasisUSD,
            gain: gain,
            gainType: gainType,
            holdingPeriodDays: lot.ageInDays
        )
    }
    
    /// Record royalty income
    public func recordRoyalty(
        contractAddress: String,
        tokenId: String? = nil,
        collectionName: String? = nil,
        chain: String,
        date: Date,
        amountUSD: Double,
        amountCrypto: Double? = nil,
        cryptoSymbol: String? = nil,
        salePrice: Double? = nil,
        royaltyPercent: Double? = nil,
        marketplace: String? = nil,
        txHash: String? = nil
    ) {
        let event = NFTRoyaltyEvent(
            date: date,
            contractAddress: contractAddress,
            tokenId: tokenId,
            collectionName: collectionName,
            chain: chain,
            amountUSD: amountUSD,
            amountCrypto: amountCrypto,
            cryptoSymbol: cryptoSymbol,
            salePrice: salePrice,
            royaltyPercent: royaltyPercent,
            marketplace: marketplace,
            txHash: txHash
        )
        royaltyEvents.append(event)
        saveData()
        
        // Record as income
        if let crypto = amountCrypto, let symbol = cryptoSymbol {
            let lotManager = TaxLotManager.shared
            _ = lotManager.createLotFromIncome(
                symbol: symbol,
                quantity: crypto,
                fairMarketValue: amountUSD / crypto,
                date: date,
                source: .income,
                exchange: marketplace ?? "NFT Royalty",
                txHash: txHash
            )
        }
    }
    
    /// Get active (undisposed) NFT lots
    public var activeNFTs: [NFTTaxLot] {
        nftLots.filter { !$0.isDisposed }
    }
    
    /// Get disposed NFT lots
    public var disposedNFTs: [NFTTaxLot] {
        nftLots.filter { $0.isDisposed }
    }
    
    /// Get NFT lots for a tax year
    public func disposals(for taxYear: TaxYear) -> [NFTTaxLot] {
        nftLots.filter {
            guard let disposed = $0.disposedDate else { return false }
            return taxYear.contains(disposed)
        }
    }
    
    /// Get royalties for a tax year
    public func royalties(for taxYear: TaxYear) -> [NFTRoyaltyEvent] {
        royaltyEvents.filter { taxYear.contains($0.date) }
    }
    
    /// Get total royalty income for a tax year
    public func totalRoyaltyIncome(for taxYear: TaxYear) -> Double {
        royalties(for: taxYear).reduce(0) { $0 + $1.amountUSD }
    }
    
    /// Get capital gains summary for a tax year
    public func capitalGainsSummary(for taxYear: TaxYear) -> NFTCapitalGainsSummary {
        let yearDisposals = disposals(for: taxYear)
        
        let shortTermGains = yearDisposals
            .filter { !$0.isLongTerm && ($0.gain ?? 0) > 0 }
            .reduce(0) { $0 + ($1.gain ?? 0) }
        
        let shortTermLosses = yearDisposals
            .filter { !$0.isLongTerm && ($0.gain ?? 0) < 0 }
            .reduce(0) { $0 + abs($1.gain ?? 0) }
        
        let longTermGains = yearDisposals
            .filter { $0.isLongTerm && ($0.gain ?? 0) > 0 }
            .reduce(0) { $0 + ($1.gain ?? 0) }
        
        let longTermLosses = yearDisposals
            .filter { $0.isLongTerm && ($0.gain ?? 0) < 0 }
            .reduce(0) { $0 + abs($1.gain ?? 0) }
        
        return NFTCapitalGainsSummary(
            shortTermGains: shortTermGains,
            shortTermLosses: shortTermLosses,
            longTermGains: longTermGains,
            longTermLosses: longTermLosses,
            totalProceeds: yearDisposals.reduce(0) { $0 + ($1.proceedsUSD ?? 0) },
            totalCostBasis: yearDisposals.reduce(0) { $0 + $1.costBasisUSD },
            transactionCount: yearDisposals.count
        )
    }
    
    /// Delete an NFT lot
    public func deleteLot(_ lot: NFTTaxLot) {
        nftLots.removeAll { $0.id == lot.id }
        saveData()
    }
    
    /// Delete a royalty event
    public func deleteRoyalty(_ event: NFTRoyaltyEvent) {
        royaltyEvents.removeAll { $0.id == event.id }
        saveData()
    }
    
    /// Clear all data
    public func clearAll() {
        nftLots.removeAll()
        royaltyEvents.removeAll()
        saveData()
    }
    
    // MARK: - Persistence
    
    private func saveData() {
        if let lotsData = try? JSONEncoder().encode(nftLots) {
            UserDefaults.standard.set(lotsData, forKey: lotsKey)
        }
        if let royaltiesData = try? JSONEncoder().encode(royaltyEvents) {
            UserDefaults.standard.set(royaltiesData, forKey: royaltiesKey)
        }
    }
    
    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: lotsKey),
           let loaded = try? JSONDecoder().decode([NFTTaxLot].self, from: data) {
            nftLots = loaded
        }
        if let data = UserDefaults.standard.data(forKey: royaltiesKey),
           let loaded = try? JSONDecoder().decode([NFTRoyaltyEvent].self, from: data) {
            royaltyEvents = loaded
        }
    }
}

// MARK: - NFT Sale Result

public struct NFTSaleResult {
    public let nft: NFTTaxLot
    public let proceedsUSD: Double
    public let costBasisUSD: Double
    public let gain: Double
    public let gainType: GainType
    public let holdingPeriodDays: Int
    
    public var isGain: Bool { gain > 0 }
    public var isLoss: Bool { gain < 0 }
}

// MARK: - NFT Capital Gains Summary

public struct NFTCapitalGainsSummary {
    public let shortTermGains: Double
    public let shortTermLosses: Double
    public let longTermGains: Double
    public let longTermLosses: Double
    public let totalProceeds: Double
    public let totalCostBasis: Double
    public let transactionCount: Int
    
    public var netShortTerm: Double { shortTermGains - shortTermLosses }
    public var netLongTerm: Double { longTermGains - longTermLosses }
    public var totalNetGain: Double { netShortTerm + netLongTerm }
}
