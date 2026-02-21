//
//  NFTModels.swift
//  CryptoSage
//
//  Models for NFT tracking and valuation.
//

import Foundation
import SwiftUI

// MARK: - NFT Model

/// Represents a single NFT
public struct NFT: Identifiable, Codable, Equatable {
    public let id: String
    public let contractAddress: String
    public let tokenId: String
    public let chain: Chain
    public let name: String?
    public let description: String?
    public let imageURL: String?
    public let animationURL: String?
    public let externalURL: String?
    public let attributes: [NFTAttribute]
    public let collection: NFTCollection?
    
    // Valuation
    public let lastSalePrice: Double?
    public let lastSaleCurrency: String?
    public let estimatedValueUSD: Double?
    
    // Metadata
    public let tokenStandard: NFTTokenStandard
    public let ownerAddress: String?
    public let creatorAddress: String?
    public let mintDate: Date?
    public let lastTransferDate: Date?
    
    public init(
        id: String = UUID().uuidString,
        contractAddress: String,
        tokenId: String,
        chain: Chain,
        name: String? = nil,
        description: String? = nil,
        imageURL: String? = nil,
        animationURL: String? = nil,
        externalURL: String? = nil,
        attributes: [NFTAttribute] = [],
        collection: NFTCollection? = nil,
        lastSalePrice: Double? = nil,
        lastSaleCurrency: String? = nil,
        estimatedValueUSD: Double? = nil,
        tokenStandard: NFTTokenStandard = .erc721,
        ownerAddress: String? = nil,
        creatorAddress: String? = nil,
        mintDate: Date? = nil,
        lastTransferDate: Date? = nil
    ) {
        self.id = id
        self.contractAddress = contractAddress
        self.tokenId = tokenId
        self.chain = chain
        self.name = name
        self.description = description
        self.imageURL = imageURL
        self.animationURL = animationURL
        self.externalURL = externalURL
        self.attributes = attributes
        self.collection = collection
        self.lastSalePrice = lastSalePrice
        self.lastSaleCurrency = lastSaleCurrency
        self.estimatedValueUSD = estimatedValueUSD
        self.tokenStandard = tokenStandard
        self.ownerAddress = ownerAddress
        self.creatorAddress = creatorAddress
        self.mintDate = mintDate
        self.lastTransferDate = lastTransferDate
    }
    
    /// Display name (fallback to token ID)
    public var displayName: String {
        name ?? "#\(tokenId)"
    }
    
    /// Unique identifier combining contract and token ID
    public var uniqueKey: String {
        "\(chain.rawValue):\(contractAddress.lowercased()):\(tokenId)"
    }
    
    /// Explorer URL for this NFT
    public var explorerURL: URL? {
        chain.tokenExplorerURL(for: contractAddress)
    }
}

// MARK: - NFT Token Standard

public enum NFTTokenStandard: String, Codable, CaseIterable {
    case erc721 = "ERC721"
    case erc1155 = "ERC1155"
    case spl = "SPL"              // Solana
    case metaplex = "METAPLEX"    // Solana Metaplex
    case unknown = "UNKNOWN"
    
    public var displayName: String {
        switch self {
        case .erc721: return "ERC-721"
        case .erc1155: return "ERC-1155"
        case .spl: return "Solana SPL"
        case .metaplex: return "Metaplex"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - NFT Attribute

public struct NFTAttribute: Codable, Equatable, Identifiable {
    public var id: String { "\(traitType):\(value)" }
    public let traitType: String
    public let value: String
    public let displayType: String?
    public let maxValue: Double?
    public let rarity: Double?      // Percentage of collection with this trait
    
    public init(
        traitType: String,
        value: String,
        displayType: String? = nil,
        maxValue: Double? = nil,
        rarity: Double? = nil
    ) {
        self.traitType = traitType
        self.value = value
        self.displayType = displayType
        self.maxValue = maxValue
        self.rarity = rarity
    }
}

// MARK: - NFT Collection

public struct NFTCollection: Codable, Equatable, Identifiable {
    public let id: String
    public let contractAddress: String
    public let chain: Chain
    public let name: String
    public let description: String?
    public let imageURL: String?
    public let bannerImageURL: String?
    public let externalURL: String?
    
    // Collection stats
    public let totalSupply: Int?
    public let ownerCount: Int?
    public let floorPrice: Double?
    public let floorPriceCurrency: String?
    public let totalVolume: Double?
    public let volumeCurrency: String?
    
    // Social links
    public let twitterUsername: String?
    public let discordURL: String?
    
    // Verification
    public let isVerified: Bool
    public let safelistStatus: String?
    
    public init(
        id: String = UUID().uuidString,
        contractAddress: String,
        chain: Chain,
        name: String,
        description: String? = nil,
        imageURL: String? = nil,
        bannerImageURL: String? = nil,
        externalURL: String? = nil,
        totalSupply: Int? = nil,
        ownerCount: Int? = nil,
        floorPrice: Double? = nil,
        floorPriceCurrency: String? = nil,
        totalVolume: Double? = nil,
        volumeCurrency: String? = nil,
        twitterUsername: String? = nil,
        discordURL: String? = nil,
        isVerified: Bool = false,
        safelistStatus: String? = nil
    ) {
        self.id = id
        self.contractAddress = contractAddress
        self.chain = chain
        self.name = name
        self.description = description
        self.imageURL = imageURL
        self.bannerImageURL = bannerImageURL
        self.externalURL = externalURL
        self.totalSupply = totalSupply
        self.ownerCount = ownerCount
        self.floorPrice = floorPrice
        self.floorPriceCurrency = floorPriceCurrency
        self.totalVolume = totalVolume
        self.volumeCurrency = volumeCurrency
        self.twitterUsername = twitterUsername
        self.discordURL = discordURL
        self.isVerified = isVerified
        self.safelistStatus = safelistStatus
    }
    
    /// Floor price in USD (if available)
    public var floorPriceUSD: Double? {
        guard let floor = floorPrice else { return nil }
        // Would need price conversion for non-USD currencies
        return floor
    }
}

// MARK: - NFT Portfolio

/// Aggregated NFT portfolio for a wallet
public struct NFTPortfolio: Identifiable, Codable {
    public let id: String
    public let address: String
    public var nfts: [NFT]
    public var collections: [NFTCollection]
    public var totalEstimatedValueUSD: Double
    public var lastUpdated: Date
    
    public init(
        id: String = UUID().uuidString,
        address: String,
        nfts: [NFT] = [],
        collections: [NFTCollection] = [],
        totalEstimatedValueUSD: Double = 0,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.address = address
        self.nfts = nfts
        self.collections = collections
        self.totalEstimatedValueUSD = totalEstimatedValueUSD
        self.lastUpdated = lastUpdated
    }
    
    /// NFTs grouped by collection
    public var nftsByCollection: [String: [NFT]] {
        Dictionary(grouping: nfts) { $0.collection?.id ?? $0.contractAddress }
    }
    
    /// NFTs grouped by chain
    public var nftsByChain: [Chain: [NFT]] {
        Dictionary(grouping: nfts) { $0.chain }
    }
    
    /// Total NFT count
    public var totalCount: Int {
        nfts.count
    }
    
    /// Collection count
    public var collectionCount: Int {
        Set(nfts.compactMap { $0.collection?.id ?? $0.contractAddress }).count
    }
    
    /// Calculate total value from floor prices
    public mutating func recalculateTotalValue() {
        totalEstimatedValueUSD = nfts.compactMap { $0.estimatedValueUSD }.reduce(0, +)
    }
}

// MARK: - NFT Transfer

/// Represents an NFT transfer event (for tax tracking)
public struct NFTTransfer: Identifiable, Codable {
    public let id: String
    public let txHash: String
    public let blockNumber: Int
    public let timestamp: Date
    public let from: String
    public let to: String
    public let contractAddress: String
    public let tokenId: String
    public let chain: Chain
    public let transferType: NFTTransferType
    public let priceETH: Double?
    public let priceUSD: Double?
    public let marketplace: String?
    
    public init(
        id: String = UUID().uuidString,
        txHash: String,
        blockNumber: Int,
        timestamp: Date,
        from: String,
        to: String,
        contractAddress: String,
        tokenId: String,
        chain: Chain,
        transferType: NFTTransferType,
        priceETH: Double? = nil,
        priceUSD: Double? = nil,
        marketplace: String? = nil
    ) {
        self.id = id
        self.txHash = txHash
        self.blockNumber = blockNumber
        self.timestamp = timestamp
        self.from = from
        self.to = to
        self.contractAddress = contractAddress
        self.tokenId = tokenId
        self.chain = chain
        self.transferType = transferType
        self.priceETH = priceETH
        self.priceUSD = priceUSD
        self.marketplace = marketplace
    }
    
    /// Determine transfer direction for an address
    public func direction(for address: String) -> TransferDirection {
        let addr = address.lowercased()
        if to.lowercased() == addr {
            return .incoming
        } else if from.lowercased() == addr {
            return .outgoing
        }
        return .unknown
    }
}

public enum NFTTransferType: String, Codable {
    case mint = "mint"
    case sale = "sale"
    case transfer = "transfer"
    case burn = "burn"
    case airdrop = "airdrop"
}

// MARK: - API Response Models

/// OpenSea NFT response
public struct OpenSeaNFTResponse: Codable {
    public let nfts: [OpenSeaNFT]?
    public let next: String?
}

public struct OpenSeaNFT: Codable {
    public let identifier: String
    public let collection: String
    public let contract: String
    public let token_standard: String
    public let name: String?
    public let description: String?
    public let image_url: String?
    public let animation_url: String?
    public let metadata_url: String?
    public let traits: [OpenSeaTrait]?
}

public struct OpenSeaTrait: Codable {
    public let trait_type: String
    public let value: String
    public let display_type: String?
}

/// OpenSea collection response
public struct OpenSeaCollectionResponse: Codable {
    public let collection: String
    public let name: String
    public let description: String?
    public let image_url: String?
    public let banner_image_url: String?
    public let owner: String?
    public let safelist_status: String?
    public let category: String?
    public let is_disabled: Bool?
    public let is_nsfw: Bool?
    public let trait_offers_enabled: Bool?
    public let collection_offers_enabled: Bool?
    public let opensea_url: String?
    public let project_url: String?
    public let wiki_url: String?
    public let discord_url: String?
    public let telegram_url: String?
    public let twitter_username: String?
    public let instagram_username: String?
    public let total_supply: Int?
}

/// Alchemy NFT response
public struct AlchemyNFTResponse: Codable {
    public let ownedNfts: [AlchemyNFT]
    public let totalCount: Int
    public let pageKey: String?
}

public struct AlchemyNFT: Codable {
    public let contract: AlchemyContract
    public let tokenId: String
    public let tokenType: String
    public let name: String?
    public let description: String?
    public let tokenUri: AlchemyTokenUri?
    public let media: [AlchemyMedia]?
    public let balance: String?
    
    public struct AlchemyContract: Codable {
        public let address: String
        public let name: String?
        public let symbol: String?
        public let tokenType: String?
        public let openSea: AlchemyOpenSeaMetadata?
    }
    
    public struct AlchemyOpenSeaMetadata: Codable {
        public let floorPrice: Double?
        public let collectionName: String?
        public let safelistRequestStatus: String?
        public let imageUrl: String?
        public let description: String?
        public let externalUrl: String?
        public let twitterUsername: String?
        public let discordUrl: String?
    }
    
    public struct AlchemyTokenUri: Codable {
        public let gateway: String?
        public let raw: String?
    }
    
    public struct AlchemyMedia: Codable {
        public let gateway: String?
        public let thumbnail: String?
        public let raw: String?
        public let format: String?
    }
}

/// Helius (Solana) NFT response
public struct HeliusNFTResponse: Codable {
    public let items: [HeliusNFT]
    public let total: Int?
    public let limit: Int?
    public let page: Int?
}

public struct HeliusNFT: Codable {
    public let id: String
    public let content: HeliusContent?
    public let authorities: [HeliusAuthority]?
    public let compression: HeliusCompression?
    public let grouping: [HeliusGrouping]?
    public let royalty: HeliusRoyalty?
    public let creators: [HeliusCreator]?
    public let ownership: HeliusOwnership?
    
    public struct HeliusContent: Codable {
        public let schema: String?
        public let json_uri: String?
        public let files: [HeliusFile]?
        public let metadata: HeliusMetadata?
        public let links: HeliusLinks?
    }
    
    public struct HeliusFile: Codable {
        public let uri: String?
        public let cdn_uri: String?
        public let mime: String?
    }
    
    public struct HeliusMetadata: Codable {
        public let name: String?
        public let symbol: String?
        public let description: String?
        public let attributes: [HeliusAttribute]?
    }
    
    public struct HeliusAttribute: Codable {
        public let trait_type: String?
        public let value: String?
    }
    
    public struct HeliusLinks: Codable {
        public let image: String?
        public let external_url: String?
        public let animation_url: String?
    }
    
    public struct HeliusAuthority: Codable {
        public let address: String
        public let scopes: [String]?
    }
    
    public struct HeliusCompression: Codable {
        public let eligible: Bool?
        public let compressed: Bool?
        public let data_hash: String?
        public let creator_hash: String?
    }
    
    public struct HeliusGrouping: Codable {
        public let group_key: String?
        public let group_value: String?
    }
    
    public struct HeliusRoyalty: Codable {
        public let royalty_model: String?
        public let target: String?
        public let percent: Double?
        public let basis_points: Int?
    }
    
    public struct HeliusCreator: Codable {
        public let address: String
        public let share: Int?
        public let verified: Bool?
    }
    
    public struct HeliusOwnership: Codable {
        public let frozen: Bool?
        public let delegated: Bool?
        public let delegate: String?
        public let ownership_model: String?
        public let owner: String
    }
}
