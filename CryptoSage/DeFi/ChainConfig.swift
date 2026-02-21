//
//  ChainConfig.swift
//  CryptoSage
//
//  Multi-chain configuration for blockchain networks.
//

import Foundation
import SwiftUI

// MARK: - Supported Chains

/// Enumeration of supported blockchain networks
public enum Chain: String, Codable, CaseIterable, Identifiable {
    // Layer 1 - Major Networks
    case ethereum = "ethereum"
    case bitcoin = "bitcoin"
    case solana = "solana"
    case avalanche = "avalanche"
    case bsc = "bsc"
    case fantom = "fantom"
    
    // Layer 1 - Newer/Alternative L1s
    case sui = "sui"
    case aptos = "aptos"
    case ton = "ton"
    case near = "near"
    case cosmos = "cosmos"
    case polkadot = "polkadot"
    case cardano = "cardano"
    case tron = "tron"
    
    // Layer 2 - Ethereum Rollups
    case arbitrum = "arbitrum"
    case optimism = "optimism"
    case base = "base"
    case polygon = "polygon"
    case zksync = "zksync"
    case linea = "linea"
    case scroll = "scroll"
    case manta = "manta"
    case mantle = "mantle"
    case blast = "blast"
    case mode = "mode"
    case polygonZkEvm = "polygon_zkevm"
    case starknet = "starknet"
    
    // Cosmos Ecosystem
    case osmosis = "osmosis"
    case injective = "injective"
    case sei = "sei"
    
    public var id: String { rawValue }
    
    /// Display name for the chain
    public var displayName: String {
        switch self {
        // Layer 1 - Major
        case .ethereum: return "Ethereum"
        case .bitcoin: return "Bitcoin"
        case .solana: return "Solana"
        case .avalanche: return "Avalanche"
        case .bsc: return "BNB Chain"
        case .fantom: return "Fantom"
        // Layer 1 - Newer
        case .sui: return "Sui"
        case .aptos: return "Aptos"
        case .ton: return "TON"
        case .near: return "NEAR"
        case .cosmos: return "Cosmos Hub"
        case .polkadot: return "Polkadot"
        case .cardano: return "Cardano"
        case .tron: return "TRON"
        // Layer 2
        case .arbitrum: return "Arbitrum"
        case .optimism: return "Optimism"
        case .base: return "Base"
        case .polygon: return "Polygon"
        case .zksync: return "zkSync Era"
        case .linea: return "Linea"
        case .scroll: return "Scroll"
        case .manta: return "Manta Pacific"
        case .mantle: return "Mantle"
        case .blast: return "Blast"
        case .mode: return "Mode"
        case .polygonZkEvm: return "Polygon zkEVM"
        case .starknet: return "Starknet"
        // Cosmos Ecosystem
        case .osmosis: return "Osmosis"
        case .injective: return "Injective"
        case .sei: return "Sei"
        }
    }
    
    /// Native currency symbol
    public var nativeSymbol: String {
        switch self {
        case .ethereum, .arbitrum, .optimism, .base, .zksync, .linea, .scroll, .blast, .mode, .polygonZkEvm, .starknet: return "ETH"
        case .bitcoin: return "BTC"
        case .solana: return "SOL"
        case .avalanche: return "AVAX"
        case .bsc: return "BNB"
        case .fantom: return "FTM"
        case .polygon: return "MATIC"
        case .sui: return "SUI"
        case .aptos: return "APT"
        case .ton: return "TON"
        case .near: return "NEAR"
        case .cosmos: return "ATOM"
        case .polkadot: return "DOT"
        case .cardano: return "ADA"
        case .tron: return "TRX"
        case .manta: return "MANTA"
        case .mantle: return "MNT"
        case .osmosis: return "OSMO"
        case .injective: return "INJ"
        case .sei: return "SEI"
        }
    }
    
    /// Native currency name
    public var nativeName: String {
        switch self {
        case .ethereum, .arbitrum, .optimism, .base, .zksync, .linea, .scroll, .blast, .mode, .polygonZkEvm, .starknet: return "Ethereum"
        case .bitcoin: return "Bitcoin"
        case .solana: return "Solana"
        case .avalanche: return "Avalanche"
        case .bsc: return "BNB"
        case .fantom: return "Fantom"
        case .polygon: return "Polygon"
        case .sui: return "Sui"
        case .aptos: return "Aptos"
        case .ton: return "Toncoin"
        case .near: return "NEAR"
        case .cosmos: return "Cosmos"
        case .polkadot: return "Polkadot"
        case .cardano: return "Cardano"
        case .tron: return "TRON"
        case .manta: return "Manta"
        case .mantle: return "Mantle"
        case .osmosis: return "Osmosis"
        case .injective: return "Injective"
        case .sei: return "Sei"
        }
    }
    
    /// Chain ID (for EVM chains)
    public var chainId: Int? {
        switch self {
        // EVM Mainnets
        case .ethereum: return 1
        case .arbitrum: return 42161
        case .optimism: return 10
        case .base: return 8453
        case .polygon: return 137
        case .bsc: return 56
        case .avalanche: return 43114
        case .fantom: return 250
        case .zksync: return 324
        case .linea: return 59144
        case .scroll: return 534352
        case .manta: return 169
        case .mantle: return 5000
        case .blast: return 81457
        case .mode: return 34443
        case .polygonZkEvm: return 1101
        // Non-EVM chains
        case .bitcoin, .solana, .sui, .aptos, .ton, .near, .cosmos, .polkadot, .cardano, .tron, .starknet, .osmosis, .injective, .sei: return nil
        }
    }
    
    /// Number of decimals for native currency
    public var nativeDecimals: Int {
        switch self {
        case .bitcoin: return 8
        case .solana, .sui: return 9
        case .aptos: return 8
        case .ton: return 9
        case .near: return 24
        case .cosmos, .osmosis, .injective, .sei: return 6
        case .polkadot: return 10
        case .cardano: return 6
        case .tron: return 6
        default: return 18 // EVM chains
        }
    }
    
    /// Whether this chain is EVM-compatible
    public var isEVM: Bool {
        switch self {
        case .bitcoin, .solana, .sui, .aptos, .ton, .near, .cosmos, .polkadot, .cardano, .starknet, .osmosis, .injective, .sei: return false
        case .tron: return true // TRON has EVM compatibility
        default: return true
        }
    }
    
    /// Brand color for the chain
    public var brandColor: Color {
        switch self {
        // Layer 1 Major
        case .ethereum: return Color(red: 0.39, green: 0.49, blue: 0.94)
        case .bitcoin: return Color(red: 0.95, green: 0.61, blue: 0.07)
        case .solana: return Color(red: 0.57, green: 0.20, blue: 0.94)
        case .avalanche: return Color(red: 0.89, green: 0.26, blue: 0.34)
        case .bsc: return Color(red: 0.94, green: 0.73, blue: 0.15)
        case .fantom: return Color(red: 0.07, green: 0.47, blue: 0.98)
        // Layer 1 Newer
        case .sui: return Color(red: 0.29, green: 0.56, blue: 0.89)
        case .aptos: return Color(red: 0.13, green: 0.82, blue: 0.72)
        case .ton: return Color(red: 0.13, green: 0.59, blue: 0.95)
        case .near: return Color(red: 0.0, green: 0.0, blue: 0.0)
        case .cosmos: return Color(red: 0.18, green: 0.11, blue: 0.36)
        case .polkadot: return Color(red: 0.90, green: 0.05, blue: 0.38)
        case .cardano: return Color(red: 0.0, green: 0.20, blue: 0.55)
        case .tron: return Color(red: 0.92, green: 0.07, blue: 0.13)
        // Layer 2
        case .arbitrum: return Color(red: 0.16, green: 0.44, blue: 0.84)
        case .optimism: return Color(red: 1.0, green: 0.04, blue: 0.18)
        case .base: return Color(red: 0.0, green: 0.32, blue: 1.0)
        case .polygon: return Color(red: 0.51, green: 0.27, blue: 0.90)
        case .zksync: return Color(red: 0.28, green: 0.28, blue: 0.87)
        case .linea: return Color(red: 0.38, green: 0.38, blue: 0.38)
        case .scroll: return Color(red: 1.0, green: 0.87, blue: 0.73)
        case .manta: return Color(red: 0.0, green: 0.80, blue: 0.80)
        case .mantle: return Color(red: 0.0, green: 0.0, blue: 0.0)
        case .blast: return Color(red: 0.99, green: 0.99, blue: 0.0)
        case .mode: return Color(red: 0.87, green: 1.0, blue: 0.0)
        case .polygonZkEvm: return Color(red: 0.51, green: 0.27, blue: 0.90)
        case .starknet: return Color(red: 0.0, green: 0.0, blue: 0.47)
        // Cosmos Ecosystem
        case .osmosis: return Color(red: 0.38, green: 0.0, blue: 0.65)
        case .injective: return Color(red: 0.0, green: 0.72, blue: 0.94)
        case .sei: return Color(red: 0.6, green: 0.12, blue: 0.20)
        }
    }
    
    /// SF Symbol icon name
    public var iconName: String {
        switch self {
        // Layer 1 Major
        case .ethereum: return "diamond.fill"
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .solana: return "sun.max.fill"
        case .avalanche: return "mountain.2.fill"
        case .bsc: return "b.circle.fill"
        case .fantom: return "f.circle.fill"
        // Layer 1 Newer
        case .sui: return "drop.fill"
        case .aptos: return "a.circle.fill"
        case .ton: return "t.circle.fill"
        case .near: return "n.circle.fill"
        case .cosmos: return "atom"
        case .polkadot: return "circle.dotted"
        case .cardano: return "c.circle.fill"
        case .tron: return "t.square.fill"
        // Layer 2
        case .arbitrum: return "a.circle.fill"
        case .optimism: return "o.circle.fill"
        case .base: return "b.square.fill"
        case .polygon: return "hexagon.fill"
        case .zksync: return "z.circle.fill"
        case .linea: return "l.circle.fill"
        case .scroll: return "scroll.fill"
        case .manta: return "m.circle.fill"
        case .mantle: return "m.square.fill"
        case .blast: return "bolt.fill"
        case .mode: return "m.circle"
        case .polygonZkEvm: return "hexagon"
        case .starknet: return "star.fill"
        // Cosmos Ecosystem
        case .osmosis: return "drop.triangle.fill"
        case .injective: return "i.circle.fill"
        case .sei: return "s.circle.fill"
        }
    }
    
    /// CoinGecko platform ID for token price lookup
    public var coingeckoPlatform: String? {
        switch self {
        // Layer 1 Major
        case .ethereum: return "ethereum"
        case .solana: return "solana"
        case .bsc: return "binance-smart-chain"
        case .avalanche: return "avalanche"
        case .fantom: return "fantom"
        // Layer 1 Newer
        case .sui: return "sui"
        case .aptos: return "aptos"
        case .ton: return "the-open-network"
        case .near: return "near-protocol"
        case .cosmos: return "cosmos"
        case .polkadot: return "polkadot"
        case .cardano: return "cardano"
        case .tron: return "tron"
        // Layer 2
        case .arbitrum: return "arbitrum-one"
        case .optimism: return "optimistic-ethereum"
        case .base: return "base"
        case .polygon: return "polygon-pos"
        case .zksync: return "zksync"
        case .linea: return "linea"
        case .scroll: return "scroll"
        case .manta: return "manta-pacific"
        case .mantle: return "mantle"
        case .blast: return "blast"
        case .mode: return "mode"
        case .polygonZkEvm: return "polygon-zkevm"
        case .starknet: return "starknet"
        // Cosmos Ecosystem
        case .osmosis: return "osmosis"
        case .injective: return "injective"
        case .sei: return "sei-network"
        // No platform
        case .bitcoin: return nil
        }
    }
    
    /// DeBank chain ID for API calls
    public var debankChainId: String? {
        switch self {
        case .ethereum: return "eth"
        case .bsc: return "bsc"
        case .polygon: return "matic"
        case .arbitrum: return "arb"
        case .optimism: return "op"
        case .base: return "base"
        case .avalanche: return "avax"
        case .fantom: return "ftm"
        case .zksync: return "era"
        case .linea: return "linea"
        case .scroll: return "scrl"
        case .manta: return "manta"
        case .mantle: return "mnt"
        case .blast: return "blast"
        case .mode: return "mode"
        case .polygonZkEvm: return "pze"
        case .tron: return "tron"
        default: return nil // Non-DeBank supported chains
        }
    }
}

// MARK: - Chain Configuration

/// Configuration for a blockchain network
public struct ChainConfiguration: Identifiable {
    public let id: Chain
    public let rpcEndpoints: [String]
    public let explorerURL: String
    public let explorerAPIURL: String?
    public let explorerAPIKey: String?
    public let wsEndpoint: String?
    
    public init(
        chain: Chain,
        rpcEndpoints: [String],
        explorerURL: String,
        explorerAPIURL: String? = nil,
        explorerAPIKey: String? = nil,
        wsEndpoint: String? = nil
    ) {
        self.id = chain
        self.rpcEndpoints = rpcEndpoints
        self.explorerURL = explorerURL
        self.explorerAPIURL = explorerAPIURL
        self.explorerAPIKey = explorerAPIKey
        self.wsEndpoint = wsEndpoint
    }
    
    /// Get the best available RPC endpoint
    public var primaryRPC: String? {
        rpcEndpoints.first
    }
}

// MARK: - Chain Registry

/// Registry of all chain configurations
public final class ChainRegistry {
    public static let shared = ChainRegistry()
    
    private var configurations: [Chain: ChainConfiguration] = [:]
    private var apiKeys: [String: String] = [:]
    
    private init() {
        setupDefaultConfigurations()
    }
    
    // MARK: - Setup
    
    private func setupDefaultConfigurations() {
        // Ethereum Mainnet
        configurations[.ethereum] = ChainConfiguration(
            chain: .ethereum,
            rpcEndpoints: [
                "https://eth-mainnet.g.alchemy.com/v2/demo",
                "https://cloudflare-eth.com",
                "https://rpc.ankr.com/eth"
            ],
            explorerURL: "https://etherscan.io",
            explorerAPIURL: "https://api.etherscan.io/api"
        )
        
        // Bitcoin
        configurations[.bitcoin] = ChainConfiguration(
            chain: .bitcoin,
            rpcEndpoints: [],
            explorerURL: "https://blockchain.com",
            explorerAPIURL: "https://blockchain.info"
        )
        
        // Solana
        configurations[.solana] = ChainConfiguration(
            chain: .solana,
            rpcEndpoints: [
                "https://api.mainnet-beta.solana.com",
                "https://solana-mainnet.g.alchemy.com/v2/demo"
            ],
            explorerURL: "https://solscan.io",
            explorerAPIURL: "https://api.helius.xyz"
        )
        
        // Arbitrum
        configurations[.arbitrum] = ChainConfiguration(
            chain: .arbitrum,
            rpcEndpoints: [
                "https://arb1.arbitrum.io/rpc",
                "https://arbitrum-mainnet.infura.io/v3/demo"
            ],
            explorerURL: "https://arbiscan.io",
            explorerAPIURL: "https://api.arbiscan.io/api"
        )
        
        // Optimism
        configurations[.optimism] = ChainConfiguration(
            chain: .optimism,
            rpcEndpoints: [
                "https://mainnet.optimism.io",
                "https://optimism-mainnet.infura.io/v3/demo"
            ],
            explorerURL: "https://optimistic.etherscan.io",
            explorerAPIURL: "https://api-optimistic.etherscan.io/api"
        )
        
        // Base
        configurations[.base] = ChainConfiguration(
            chain: .base,
            rpcEndpoints: [
                "https://mainnet.base.org",
                "https://base-mainnet.g.alchemy.com/v2/demo"
            ],
            explorerURL: "https://basescan.org",
            explorerAPIURL: "https://api.basescan.org/api"
        )
        
        // Polygon
        configurations[.polygon] = ChainConfiguration(
            chain: .polygon,
            rpcEndpoints: [
                "https://polygon-rpc.com",
                "https://rpc.ankr.com/polygon"
            ],
            explorerURL: "https://polygonscan.com",
            explorerAPIURL: "https://api.polygonscan.com/api"
        )
        
        // BSC
        configurations[.bsc] = ChainConfiguration(
            chain: .bsc,
            rpcEndpoints: [
                "https://bsc-dataseed.binance.org",
                "https://rpc.ankr.com/bsc"
            ],
            explorerURL: "https://bscscan.com",
            explorerAPIURL: "https://api.bscscan.com/api"
        )
        
        // Avalanche
        configurations[.avalanche] = ChainConfiguration(
            chain: .avalanche,
            rpcEndpoints: [
                "https://api.avax.network/ext/bc/C/rpc",
                "https://rpc.ankr.com/avalanche"
            ],
            explorerURL: "https://snowtrace.io",
            explorerAPIURL: "https://api.snowtrace.io/api"
        )
        
        // Fantom
        configurations[.fantom] = ChainConfiguration(
            chain: .fantom,
            rpcEndpoints: [
                "https://rpc.ftm.tools",
                "https://rpc.ankr.com/fantom"
            ],
            explorerURL: "https://ftmscan.com",
            explorerAPIURL: "https://api.ftmscan.com/api"
        )
        
        // zkSync
        configurations[.zksync] = ChainConfiguration(
            chain: .zksync,
            rpcEndpoints: [
                "https://mainnet.era.zksync.io"
            ],
            explorerURL: "https://explorer.zksync.io",
            explorerAPIURL: "https://block-explorer-api.mainnet.zksync.io/api"
        )
        
        // Linea
        configurations[.linea] = ChainConfiguration(
            chain: .linea,
            rpcEndpoints: [
                "https://rpc.linea.build",
                "https://linea-mainnet.infura.io/v3/demo"
            ],
            explorerURL: "https://lineascan.build",
            explorerAPIURL: "https://api.lineascan.build/api"
        )
        
        // Scroll
        configurations[.scroll] = ChainConfiguration(
            chain: .scroll,
            rpcEndpoints: [
                "https://rpc.scroll.io",
                "https://rpc.ankr.com/scroll"
            ],
            explorerURL: "https://scrollscan.com",
            explorerAPIURL: "https://api.scrollscan.com/api"
        )
        
        // Manta Pacific
        configurations[.manta] = ChainConfiguration(
            chain: .manta,
            rpcEndpoints: [
                "https://pacific-rpc.manta.network/http"
            ],
            explorerURL: "https://pacific-explorer.manta.network",
            explorerAPIURL: nil
        )
        
        // Mantle
        configurations[.mantle] = ChainConfiguration(
            chain: .mantle,
            rpcEndpoints: [
                "https://rpc.mantle.xyz",
                "https://rpc.ankr.com/mantle"
            ],
            explorerURL: "https://explorer.mantle.xyz",
            explorerAPIURL: "https://api.mantlescan.xyz/api"
        )
        
        // Blast
        configurations[.blast] = ChainConfiguration(
            chain: .blast,
            rpcEndpoints: [
                "https://rpc.blast.io",
                "https://rpc.ankr.com/blast"
            ],
            explorerURL: "https://blastscan.io",
            explorerAPIURL: "https://api.blastscan.io/api"
        )
        
        // Mode
        configurations[.mode] = ChainConfiguration(
            chain: .mode,
            rpcEndpoints: [
                "https://mainnet.mode.network"
            ],
            explorerURL: "https://explorer.mode.network",
            explorerAPIURL: nil
        )
        
        // Polygon zkEVM
        configurations[.polygonZkEvm] = ChainConfiguration(
            chain: .polygonZkEvm,
            rpcEndpoints: [
                "https://zkevm-rpc.com",
                "https://rpc.ankr.com/polygon_zkevm"
            ],
            explorerURL: "https://zkevm.polygonscan.com",
            explorerAPIURL: "https://api-zkevm.polygonscan.com/api"
        )
        
        // Starknet
        configurations[.starknet] = ChainConfiguration(
            chain: .starknet,
            rpcEndpoints: [
                "https://starknet-mainnet.public.blastapi.io"
            ],
            explorerURL: "https://starkscan.co",
            explorerAPIURL: nil
        )
        
        // Sui
        configurations[.sui] = ChainConfiguration(
            chain: .sui,
            rpcEndpoints: [
                "https://fullnode.mainnet.sui.io:443"
            ],
            explorerURL: "https://suiscan.xyz",
            explorerAPIURL: nil
        )
        
        // Aptos
        configurations[.aptos] = ChainConfiguration(
            chain: .aptos,
            rpcEndpoints: [
                "https://fullnode.mainnet.aptoslabs.com/v1"
            ],
            explorerURL: "https://explorer.aptoslabs.com",
            explorerAPIURL: nil
        )
        
        // TON
        configurations[.ton] = ChainConfiguration(
            chain: .ton,
            rpcEndpoints: [
                "https://toncenter.com/api/v2"
            ],
            explorerURL: "https://tonscan.org",
            explorerAPIURL: "https://toncenter.com/api/v2"
        )
        
        // NEAR
        configurations[.near] = ChainConfiguration(
            chain: .near,
            rpcEndpoints: [
                "https://rpc.mainnet.near.org"
            ],
            explorerURL: "https://nearblocks.io",
            explorerAPIURL: nil
        )
        
        // Cosmos Hub
        configurations[.cosmos] = ChainConfiguration(
            chain: .cosmos,
            rpcEndpoints: [
                "https://cosmos-rpc.publicnode.com:443"
            ],
            explorerURL: "https://www.mintscan.io/cosmos",
            explorerAPIURL: nil
        )
        
        // Polkadot
        configurations[.polkadot] = ChainConfiguration(
            chain: .polkadot,
            rpcEndpoints: [
                "wss://rpc.polkadot.io"
            ],
            explorerURL: "https://polkadot.subscan.io",
            explorerAPIURL: "https://polkadot.api.subscan.io"
        )
        
        // Cardano
        configurations[.cardano] = ChainConfiguration(
            chain: .cardano,
            rpcEndpoints: [],
            explorerURL: "https://cardanoscan.io",
            explorerAPIURL: nil
        )
        
        // TRON
        configurations[.tron] = ChainConfiguration(
            chain: .tron,
            rpcEndpoints: [
                "https://api.trongrid.io"
            ],
            explorerURL: "https://tronscan.org",
            explorerAPIURL: "https://apilist.tronscan.org/api"
        )
        
        // Osmosis
        configurations[.osmosis] = ChainConfiguration(
            chain: .osmosis,
            rpcEndpoints: [
                "https://osmosis-rpc.publicnode.com:443"
            ],
            explorerURL: "https://www.mintscan.io/osmosis",
            explorerAPIURL: nil
        )
        
        // Injective
        configurations[.injective] = ChainConfiguration(
            chain: .injective,
            rpcEndpoints: [
                "https://sentry.tm.injective.network:443"
            ],
            explorerURL: "https://explorer.injective.network",
            explorerAPIURL: nil
        )
        
        // Sei
        configurations[.sei] = ChainConfiguration(
            chain: .sei,
            rpcEndpoints: [
                "https://sei-rpc.publicnode.com:443"
            ],
            explorerURL: "https://www.seiscan.app",
            explorerAPIURL: nil
        )
    }
    
    // MARK: - Public API
    
    /// Get configuration for a chain
    public func configuration(for chain: Chain) -> ChainConfiguration? {
        configurations[chain]
    }
    
    /// Get all supported chains
    public var supportedChains: [Chain] {
        Array(configurations.keys).sorted { $0.displayName < $1.displayName }
    }
    
    /// Get EVM chains only
    public var evmChains: [Chain] {
        supportedChains.filter { $0.isEVM }
    }
    
    /// Set API key for a service
    public func setAPIKey(_ key: String, for service: String) {
        apiKeys[service] = key
    }
    
    /// Get API key for a service
    public func apiKey(for service: String) -> String? {
        apiKeys[service]
    }
    
    /// Set explorer API key for a chain
    public func setExplorerAPIKey(_ key: String, for chain: Chain) {
        guard let config = configurations[chain] else { return }
        configurations[chain] = ChainConfiguration(
            chain: chain,
            rpcEndpoints: config.rpcEndpoints,
            explorerURL: config.explorerURL,
            explorerAPIURL: config.explorerAPIURL,
            explorerAPIKey: key,
            wsEndpoint: config.wsEndpoint
        )
    }
    
    /// Detect chain from wallet address
    public func detectChain(from address: String) -> Chain? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ethereum/EVM - starts with 0x and 40 hex chars
        if trimmed.hasPrefix("0x") && trimmed.count == 42 {
            return .ethereum // Default to mainnet, but address works on all EVM
        }
        
        // Sui/Aptos/Starknet - 0x + 64 hex chars
        if trimmed.hasPrefix("0x") && trimmed.count == 66 {
            return .sui // Default to Sui, could be Aptos or Starknet
        }
        
        // Bitcoin - starts with 1, 3, or bc1
        if trimmed.hasPrefix("bc1") || (trimmed.hasPrefix("1") && trimmed.count >= 26) || (trimmed.hasPrefix("3") && trimmed.count >= 26) {
            return .bitcoin
        }
        
        // TON - EQ or UQ prefix
        if trimmed.hasPrefix("EQ") || trimmed.hasPrefix("UQ") {
            return .ton
        }
        
        // NEAR - .near suffix or 64 hex chars
        if trimmed.hasSuffix(".near") {
            return .near
        }
        
        // Cosmos - cosmos1 prefix
        if trimmed.hasPrefix("cosmos1") {
            return .cosmos
        }
        
        // Osmosis - osmo1 prefix
        if trimmed.hasPrefix("osmo1") {
            return .osmosis
        }
        
        // Injective - inj1 prefix
        if trimmed.hasPrefix("inj1") {
            return .injective
        }
        
        // Sei - sei1 prefix
        if trimmed.hasPrefix("sei1") {
            return .sei
        }
        
        // Cardano - addr1 prefix
        if trimmed.hasPrefix("addr1") || trimmed.hasPrefix("Ae2") {
            return .cardano
        }
        
        // TRON - T prefix + 33 chars
        if trimmed.hasPrefix("T") && trimmed.count == 34 {
            return .tron
        }
        
        // Polkadot - starts with 1 and is 48 chars
        if trimmed.hasPrefix("1") && trimmed.count == 48 {
            return .polkadot
        }
        
        // Solana - Base58, 32-44 chars
        if trimmed.count >= 32 && trimmed.count <= 44 &&
           !trimmed.hasPrefix("0x") && !trimmed.hasPrefix("EQ") && !trimmed.hasPrefix("UQ") {
            return .solana
        }
        
        return nil
    }
    
    /// Get all EVM chains that an address is valid on
    public func validEVMChains(for address: String) -> [Chain] {
        guard address.hasPrefix("0x") && address.count == 42 else { return [] }
        return evmChains
    }
}

// MARK: - API Keys Configuration

/// Service identifiers for API keys
public enum ChainAPIService: String {
    case etherscan = "etherscan"
    case arbiscan = "arbiscan"
    case optimisticEtherscan = "optimistic_etherscan"
    case basescan = "basescan"
    case polygonscan = "polygonscan"
    case bscscan = "bscscan"
    case snowtrace = "snowtrace"
    case ftmscan = "ftmscan"
    case alchemy = "alchemy"
    case infura = "infura"
    case helius = "helius"
    case moralis = "moralis"
}

// MARK: - Address Validation

extension Chain {
    /// Validate address format for this chain
    public func isValidAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch self {
        case .bitcoin:
            // Bitcoin addresses: Legacy (1...), SegWit (3...), Native SegWit (bc1...)
            let legacyPattern = "^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$"
            let bech32Pattern = "^bc1[a-zA-HJ-NP-Z0-9]{39,59}$"
            return matches(trimmed, pattern: legacyPattern) || matches(trimmed, pattern: bech32Pattern)
            
        case .solana:
            // Solana: Base58, 32-44 characters
            let pattern = "^[1-9A-HJ-NP-Za-km-z]{32,44}$"
            return matches(trimmed, pattern: pattern)
            
        case .sui:
            // Sui: 0x + 64 hex characters
            let pattern = "^0x[a-fA-F0-9]{64}$"
            return matches(trimmed, pattern: pattern)
            
        case .aptos:
            // Aptos: 0x + 64 hex characters
            let pattern = "^0x[a-fA-F0-9]{64}$"
            return matches(trimmed, pattern: pattern)
            
        case .ton:
            // TON: EQ or UQ prefix + 46 base64 characters
            let pattern = "^(EQ|UQ)[A-Za-z0-9_-]{46}$"
            return matches(trimmed, pattern: pattern)
            
        case .near:
            // NEAR: Named accounts (e.g., user.near) or implicit accounts (64 hex chars)
            let namedPattern = "^[a-z0-9._-]+\\.near$"
            let implicitPattern = "^[a-fA-F0-9]{64}$"
            return matches(trimmed, pattern: namedPattern) || matches(trimmed, pattern: implicitPattern)
            
        case .cosmos, .osmosis:
            // Cosmos: cosmos1 + 38 bech32 characters
            let atomPattern = "^cosmos1[a-z0-9]{38}$"
            let osmoPattern = "^osmo1[a-z0-9]{38}$"
            return matches(trimmed, pattern: atomPattern) || matches(trimmed, pattern: osmoPattern)
            
        case .polkadot:
            // Polkadot: SS58 format (starts with 1)
            let pattern = "^1[a-zA-Z0-9]{47}$"
            return matches(trimmed, pattern: pattern)
            
        case .cardano:
            // Cardano: addr1 (Shelley) or Ae2 (Byron)
            let shelleyPattern = "^addr1[a-z0-9]{50,}$"
            let byronPattern = "^Ae2[a-zA-Z0-9]{50,}$"
            return matches(trimmed, pattern: shelleyPattern) || matches(trimmed, pattern: byronPattern)
            
        case .tron:
            // TRON: T + 33 base58 characters
            let pattern = "^T[a-km-zA-HJ-NP-Z1-9]{33}$"
            return matches(trimmed, pattern: pattern)
            
        case .injective:
            // Injective: inj1 + 38 bech32 characters
            let pattern = "^inj1[a-z0-9]{38}$"
            return matches(trimmed, pattern: pattern)
            
        case .sei:
            // Sei: sei1 + 38 bech32 characters
            let pattern = "^sei1[a-z0-9]{38}$"
            return matches(trimmed, pattern: pattern)
            
        case .starknet:
            // Starknet: 0x + 64 hex characters
            let pattern = "^0x[a-fA-F0-9]{64}$"
            return matches(trimmed, pattern: pattern)
            
        default:
            // EVM chains: 0x + 40 hex characters
            let pattern = "^0x[a-fA-F0-9]{40}$"
            return matches(trimmed, pattern: pattern)
        }
    }
    
    private func matches(_ string: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: string.utf16.count)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }
}

// MARK: - Explorer URLs

extension Chain {
    /// Generate explorer URL for an address
    public func explorerURL(for address: String) -> URL? {
        guard let config = ChainRegistry.shared.configuration(for: self) else { return nil }
        return URL(string: "\(config.explorerURL)/address/\(address)")
    }
    
    /// Generate explorer URL for a transaction
    public func txExplorerURL(for txHash: String) -> URL? {
        guard let config = ChainRegistry.shared.configuration(for: self) else { return nil }
        return URL(string: "\(config.explorerURL)/tx/\(txHash)")
    }
    
    /// Generate explorer URL for a token contract
    public func tokenExplorerURL(for contractAddress: String) -> URL? {
        guard let config = ChainRegistry.shared.configuration(for: self) else { return nil }
        return URL(string: "\(config.explorerURL)/token/\(contractAddress)")
    }
}
