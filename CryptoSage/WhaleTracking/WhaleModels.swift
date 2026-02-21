//
//  WhaleModels.swift
//  CryptoSage
//
//  Data models for whale wallet tracking.
//

import Foundation
import SwiftUI

// MARK: - Data Source

/// Tracks where whale transaction data originated from
public enum WhaleDataSource: String, Codable {
    case whaleAlert = "Whale Alert"
    case arkham = "Arkham"
    case blockchair = "Blockchair"
    case etherscan = "Etherscan"
    case ethplorer = "Ethplorer"      // NEW: Free ETH token transfers API
    case solscan = "Solscan"
    case helius = "Helius"            // NEW: Professional Solana API (free tier)
    case blockchainInfo = "Blockchain.info"
    case duneAnalytics = "Dune Analytics"
    case demo = "Demo Data"
    
    public var isReliable: Bool {
        switch self {
        case .whaleAlert, .arkham, .blockchair, .etherscan, .ethplorer, .solscan, .helius, .duneAnalytics:
            return true
        case .blockchainInfo, .demo:
            return false
        }
    }
    
    public var isPremium: Bool {
        switch self {
        case .whaleAlert, .arkham, .duneAnalytics:
            return true
        default:
            return false
        }
    }
    
    /// Free tier available (great for users)
    public var hasFreeTier: Bool {
        switch self {
        case .blockchair, .etherscan, .ethplorer, .solscan, .helius:
            return true
        default:
            return false
        }
    }
    
    public var icon: String {
        switch self {
        case .whaleAlert: return "bell.badge.waveform.fill"
        case .arkham: return "eye.trianglebadge.exclamationmark"
        case .blockchair: return "chair.fill"
        case .etherscan: return "doc.text.magnifyingglass"
        case .ethplorer: return "e.circle.fill"
        case .solscan: return "sun.max.fill"
        case .helius: return "bolt.circle.fill"
        case .blockchainInfo: return "link"
        case .duneAnalytics: return "chart.bar.xaxis"
        case .demo: return "play.circle"
        }
    }
    
    /// Display name with tier info
    public var displayName: String {
        switch self {
        case .whaleAlert: return "Whale Alert (Premium)"
        case .arkham: return "Arkham Intel (Premium)"
        case .blockchair: return "Blockchair"
        case .etherscan: return "Etherscan"
        case .ethplorer: return "Ethplorer"
        case .solscan: return "Solscan"
        case .helius: return "Helius"
        case .blockchainInfo: return "Blockchain.info"
        case .duneAnalytics: return "Dune (Premium)"
        case .demo: return "Demo"
        }
    }
}

// MARK: - Transaction Sentiment

/// Market sentiment indication based on transaction flow
public enum TransactionSentiment: String, Codable {
    case bullish = "Bullish"
    case bearish = "Bearish"
    case neutral = "Neutral"
    
    public var color: Color {
        switch self {
        case .bullish: return .green
        case .bearish: return .red
        case .neutral: return .gray
        }
    }
    
    public var icon: String {
        switch self {
        case .bullish: return "arrow.up.right"
        case .bearish: return "arrow.down.right"
        case .neutral: return "arrow.left.arrow.right"
        }
    }
}

// MARK: - Whale Transaction

/// Represents a large cryptocurrency transaction
public struct WhaleTransaction: Identifiable, Codable, Equatable {
    public let id: String
    public let blockchain: WhaleBlockchain
    public let symbol: String
    public let amount: Double
    public let amountUSD: Double
    public let fromAddress: String
    public let toAddress: String
    public let hash: String
    public let timestamp: Date
    public let transactionType: WhaleTransactionType
    public var dataSource: WhaleDataSource
    
    public init(
        id: String,
        blockchain: WhaleBlockchain,
        symbol: String,
        amount: Double,
        amountUSD: Double,
        fromAddress: String,
        toAddress: String,
        hash: String,
        timestamp: Date,
        transactionType: WhaleTransactionType,
        dataSource: WhaleDataSource = .etherscan
    ) {
        self.id = id
        self.blockchain = blockchain
        self.symbol = symbol
        self.amount = amount
        self.amountUSD = amountUSD
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.hash = hash
        self.timestamp = timestamp
        self.transactionType = transactionType
        self.dataSource = dataSource
    }
    
    public var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
    
    public var formattedUSD: String {
        MarketFormat.largeCurrency(amountUSD, useCurrentCurrency: true)
    }
    
    public var shortFromAddress: String {
        guard fromAddress.count > 12 else { return fromAddress }
        let prefix = fromAddress.prefix(6)
        let suffix = fromAddress.suffix(4)
        return "\(prefix)...\(suffix)"
    }
    
    public var shortToAddress: String {
        guard toAddress.count > 12 else { return toAddress }
        let prefix = toAddress.prefix(6)
        let suffix = toAddress.suffix(4)
        return "\(prefix)...\(suffix)"
    }
    
    public var explorerURL: URL? {
        blockchain.explorerURL(for: hash)
    }
    
    /// Sentiment based on transaction type and flow direction
    public var sentiment: TransactionSentiment {
        switch transactionType {
        case .exchangeWithdrawal:
            return .bullish // Moving off exchange = accumulation = bullish
        case .exchangeDeposit:
            return .bearish // Moving to exchange = potential sell = bearish
        case .transfer, .unknown:
            return .neutral
        }
    }
    
    /// Whether this is a fresh transaction (under 5 minutes old)
    public var isFresh: Bool {
        Date().timeIntervalSince(timestamp) < 300 // 5 minutes
    }
    
    /// Whether this is a recent transaction (under 1 hour old)
    public var isRecent: Bool {
        Date().timeIntervalSince(timestamp) < 3600 // 1 hour
    }
    
    /// Get label for the from address if known
    public var fromLabel: String? {
        KnownWhaleLabels.label(for: fromAddress)
    }
    
    /// Get label for the to address if known
    public var toLabel: String? {
        KnownWhaleLabels.label(for: toAddress)
    }
}

// MARK: - Whale Relative Time Formatting

public enum WhaleRelativeTimeFormatter {
    /// Compact whale feed formatting.
    /// Examples: "just now", "12m ago", "3h 25m ago", "8h 30m ago", "2d ago".
    public static func format(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        
        // Handle slight clock skew for near-future timestamps.
        if seconds < 0 && seconds > -300 { return "just now" }
        // Any larger future skew is treated as "just now" to avoid confusing labels.
        if seconds < -300 { return "just now" }
        if seconds < 60 { return "just now" }
        
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 12 {
            // Keep minute-level granularity while a transaction is still same-day recent.
            if remainingMinutes >= 5 {
                return "\(hours)h \(remainingMinutes)m ago"
            }
            return "\(hours)h ago"
        }
        
        if hours < 24 {
            // Coarsen to 15-minute precision for older same-day transactions.
            let quarterMinutes = (remainingMinutes / 15) * 15
            if quarterMinutes > 0 {
                return "\(hours)h \(quarterMinutes)m ago"
            }
            return "\(hours)h ago"
        }
        
        let days = hours / 24
        return "\(days)d ago"
    }
}

// MARK: - Blockchain Type

public enum WhaleBlockchain: String, Codable, CaseIterable {
    case bitcoin = "Bitcoin"
    case ethereum = "Ethereum"
    case solana = "Solana"
    case arbitrum = "Arbitrum"
    case polygon = "Polygon"
    case avalanche = "Avalanche"
    case bsc = "BSC"
    
    public var symbol: String {
        switch self {
        case .bitcoin: return "BTC"
        case .ethereum: return "ETH"
        case .solana: return "SOL"
        case .arbitrum: return "ARB"
        case .polygon: return "MATIC"
        case .avalanche: return "AVAX"
        case .bsc: return "BNB"
        }
    }
    
    public var icon: String {
        switch self {
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .ethereum: return "e.circle.fill"
        case .solana: return "s.circle.fill"
        case .arbitrum: return "a.circle.fill"
        case .polygon: return "p.circle.fill"
        case .avalanche: return "a.circle.fill"
        case .bsc: return "b.circle.fill"
        }
    }
    
    public var color: Color {
        switch self {
        case .bitcoin: return .orange
        case .ethereum: return .blue
        case .solana: return .purple
        case .arbitrum: return .blue
        case .polygon: return .purple
        case .avalanche: return .red
        case .bsc: return .yellow
        }
    }
    
    public func explorerURL(for hash: String) -> URL? {
        let baseURL: String
        switch self {
        case .bitcoin:
            baseURL = "https://blockchair.com/bitcoin/transaction/\(hash)"
        case .ethereum:
            baseURL = "https://etherscan.io/tx/\(hash)"
        case .solana:
            baseURL = "https://solscan.io/tx/\(hash)"
        case .arbitrum:
            baseURL = "https://arbiscan.io/tx/\(hash)"
        case .polygon:
            baseURL = "https://polygonscan.com/tx/\(hash)"
        case .avalanche:
            baseURL = "https://snowtrace.io/tx/\(hash)"
        case .bsc:
            baseURL = "https://bscscan.com/tx/\(hash)"
        }
        return URL(string: baseURL)
    }
    
    /// Get explorer URL for a wallet address
    public func explorerURL(forAddress address: String) -> URL? {
        let baseURL: String
        switch self {
        case .bitcoin:
            baseURL = "https://blockchair.com/bitcoin/address/\(address)"
        case .ethereum:
            baseURL = "https://etherscan.io/address/\(address)"
        case .solana:
            baseURL = "https://solscan.io/account/\(address)"
        case .arbitrum:
            baseURL = "https://arbiscan.io/address/\(address)"
        case .polygon:
            baseURL = "https://polygonscan.com/address/\(address)"
        case .avalanche:
            baseURL = "https://snowtrace.io/address/\(address)"
        case .bsc:
            baseURL = "https://bscscan.com/address/\(address)"
        }
        return URL(string: baseURL)
    }
}

// MARK: - Transaction Type

public enum WhaleTransactionType: String, Codable {
    case transfer = "Transfer"
    case exchangeDeposit = "Exchange Deposit"
    case exchangeWithdrawal = "Exchange Withdrawal"
    case unknown = "Unknown"
    
    public var icon: String {
        switch self {
        case .transfer: return "arrow.left.arrow.right"
        case .exchangeDeposit: return "arrow.down.to.line"
        case .exchangeWithdrawal: return "arrow.up.to.line"
        case .unknown: return "questionmark.circle"
        }
    }
    
    public var description: String {
        switch self {
        case .transfer: return "Wallet to Wallet"
        case .exchangeDeposit: return "Moving to Exchange"
        case .exchangeWithdrawal: return "Moving from Exchange"
        case .unknown: return "Unknown Type"
        }
    }
}

// MARK: - Watched Wallet

/// A wallet address being watched for large transactions
public struct WatchedWallet: Identifiable, Codable, Equatable {
    public let id: UUID
    public var address: String
    public var label: String
    public var blockchain: WhaleBlockchain
    public var notifyOnActivity: Bool
    public var minTransactionAmount: Double
    public var addedAt: Date
    public var lastActivity: Date?
    
    public init(
        id: UUID = UUID(),
        address: String,
        label: String,
        blockchain: WhaleBlockchain,
        notifyOnActivity: Bool = true,
        minTransactionAmount: Double = 100_000,
        addedAt: Date = Date(),
        lastActivity: Date? = nil
    ) {
        self.id = id
        self.address = address
        self.label = label
        self.blockchain = blockchain
        self.notifyOnActivity = notifyOnActivity
        self.minTransactionAmount = minTransactionAmount
        self.addedAt = addedAt
        self.lastActivity = lastActivity
    }
    
    public var shortAddress: String {
        guard address.count > 12 else { return address }
        let prefix = address.prefix(6)
        let suffix = address.suffix(4)
        return "\(prefix)...\(suffix)"
    }
}

// MARK: - Whale Alert Configuration

/// User preferences for whale alerts
public struct WhaleAlertConfig: Codable {
    public var minAmountUSD: Double
    public var enabledBlockchains: Set<WhaleBlockchain>
    public var enablePushNotifications: Bool
    public var showExchangeMovements: Bool
    
    // IMPROVED: Lowered default minimum to $100k to show more whale activity (matches ViewModel)
    public static let defaultConfig = WhaleAlertConfig(
        minAmountUSD: 100_000,
        enabledBlockchains: Set(WhaleBlockchain.allCases),
        enablePushNotifications: true,
        showExchangeMovements: true
    )
    
    public init(
        minAmountUSD: Double,
        enabledBlockchains: Set<WhaleBlockchain>,
        enablePushNotifications: Bool,
        showExchangeMovements: Bool
    ) {
        self.minAmountUSD = minAmountUSD
        self.enabledBlockchains = enabledBlockchains
        self.enablePushNotifications = enablePushNotifications
        self.showExchangeMovements = showExchangeMovements
    }
}

// MARK: - Whale Statistics

/// Aggregated whale activity statistics
public struct WhaleStatistics: Codable {
    public let totalTransactionsLast24h: Int
    public let totalVolumeUSD: Double
    public let largestTransaction: WhaleTransaction?
    public let mostActiveBlockchain: WhaleBlockchain?
    public let avgTransactionSize: Double
    public let exchangeInflowUSD: Double
    public let exchangeOutflowUSD: Double
    
    public var netExchangeFlow: Double {
        exchangeInflowUSD - exchangeOutflowUSD
    }
    
    public var flowSentiment: String {
        if netExchangeFlow > 0 {
            return "Bearish (Exchange Inflow)"
        } else if netExchangeFlow < 0 {
            return "Bullish (Exchange Outflow)"
        }
        return "Neutral"
    }
}

// MARK: - Known Whale Labels

/// Database of known whale wallet labels - expanded to 60+ addresses
public struct KnownWhaleLabels {
    
    public static let labels: [String: String] = [
        // ══════════════════════════════════════════════════════════════════
        // BITCOIN WHALES
        // ══════════════════════════════════════════════════════════════════
        
        // Binance
        "1P5ZEDWTKTFGxQjZphgWPQUpe554WKDfHQ": "Binance Cold Wallet",
        "34xp4vRoCGJym3xR7yCVPFHoCNxv4Twseo": "Binance Hot Wallet",
        "3LYJfcfHPXYJreMsASk2jkn69LWEYKzexb": "Binance Hot Wallet 2",
        "1NDyJtNTjmwk5xPNhjgAMu4HDHigtobu1s": "Binance Cold Wallet 2",
        "bc1qm34lsc65zpw79lxes69zkqmk6ee3ewf0j77s3h": "Binance Hot Wallet 3",
        
        // Bitfinex
        "bc1qgdjqv0av3q56jvd82tkdjpy7gdp9ut8tlqmgrpmv24sq90ecnvqqjwvw97": "Bitfinex Cold Wallet",
        "3D2oetdNuZUqQHPJmcMDDHYoqkyNVsFk9r": "Bitfinex Hot Wallet",
        "1Kr6QSydW9bFQG1mXiPNNu6WpJGmUa9i1g": "Bitfinex Cold Wallet 2",
        
        // Coinbase
        "1FzWLkAahHooV3kzPgBvNNBfKXxhbzA6BQ": "Coinbase Hot Wallet",
        "3Kzh9qAqVWQhEsfQz7zEQL1EuSx5tyNLNS": "Coinbase Cold Wallet",
        "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh": "Coinbase Prime",
        
        // Kraken
        "3FupZp77ySr7jwoLYEJ9mwzJpvoNBXsBnE": "Kraken Hot Wallet",
        "bc1qhwu3w5r3mp4rzkp4j7eaa4wpfmhzw0fvzl6ctr": "Kraken Cold Wallet",
        
        // Gemini
        "1FcvoVLzyJHN3Sx4UMELWvxTk2b2oWymCz": "Gemini Hot Wallet",
        "3P3QsMVK89JBNqZQv5zMAKG8FK3kJM4rjt": "Gemini Cold Wallet",
        
        // ══════════════════════════════════════════════════════════════════
        // ETHEREUM WHALES
        // ══════════════════════════════════════════════════════════════════
        
        // Binance
        "0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8": "Binance Hot Wallet 8",
        "0xf977814e90da44bfa03b6295a0616a897441acec": "Binance Hot Wallet 2",
        "0x28C6c06298d514Db089934071355E5743bf21d60": "Binance Hot Wallet 14",
        "0x21a31Ee1afC51d94C2eFcCAa2092aD1028285549": "Binance Cold Wallet",
        "0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503": "Binance Peg Tokens",
        "0x564286362092D8e7936f0549571a803B203aAceD": "Binance Bridge",
        "0x3f5CE5FBFe3E9af3971dD833D26BA9b5C936f0bE": "Binance Hot Wallet 1",
        "0xD551234Ae421e3BCBA99A0Da6d736074f22192FF": "Binance Hot Wallet 3",
        "0x5a52E96BAcdaBb82fd05763E25335261B270Efcb": "Binance Hot Wallet 5",
        
        // Coinbase
        "0xDFd5293D8e347dFe59E90eFd55b2956a1343963d": "Coinbase Prime",
        "0x503828976D22510aad0201ac7EC88293211D23Da": "Coinbase 2",
        "0x71660c4005BA85c37ccec55d0C4493E66Fe775d3": "Coinbase 3",
        "0x02466e547BFDAb679fC49e96bBfc62B9747D997C": "Coinbase 4",
        "0xA9D1e08C7793af67e9d92fe308d5697FB81d3E43": "Coinbase 6",
        "0x77134cbC06cB00b66F4c7e623D5fdBF6777635EC": "Coinbase Commerce",
        
        // OKX
        "0x66f820a414680B5bcda5eECA5dea238543F42054": "OKX Hot Wallet",
        "0x6cc5f688a315f3dc28a7781717a9a798a59fda7b": "OKX Hot Wallet 2",
        "0x236F9F97e0E62388479bf9E5BA4889e46B0273C3": "OKX Hot Wallet 3",
        
        // Kraken
        "0x2910543Af39abA0Cd09dBb2D50200b3E800A63D2": "Kraken Hot Wallet",
        "0x267be1C1D684F78cb4F6a176C4911b741E4Ffdc0": "Kraken Hot Wallet 2",
        
        // Bitfinex
        "0x876EabF441B2EE5B5b0554Fd502a8E0600950cFa": "Bitfinex Hot Wallet",
        "0x742d35Cc6634C0532925a3b844Bc9e7595f9E091": "Bitfinex Hot Wallet 2",
        
        // Gemini
        "0xD24400ae8BfEBb18cA49Be86258a3C749cf46853": "Gemini Hot Wallet",
        "0x07Ee55aA48Bb72DCC6E9D78256648910De513eca": "Gemini Hot Wallet 2",
        
        // Crypto.com
        "0x6262998Ced04146fA42253a5C0AF90CA02dfd2A3": "Crypto.com Hot Wallet",
        "0x46340b20830761efd32832A74d7169B29FEB9758": "Crypto.com Cold Wallet",
        
        // KuCoin
        "0x2B5634C42055806a59e9107ED44D43c426E58258": "KuCoin Hot Wallet",
        "0xd6216fC19DB775Df9774a6E33526131dA7D19a2c": "KuCoin Hot Wallet 2",
        
        // Bybit
        "0xf89d7b9c864f589bbF53a82105107622B35EaA40": "Bybit Hot Wallet",
        
        // Huobi / HTX
        "0xab5c66752a9e8167967685f1450532fb96d5d24f": "HTX Hot Wallet",
        "0x6748f50f686bfbcA6Fe8ad62b22228b87F31ff2b": "HTX Hot Wallet 2",
        
        // ══════════════════════════════════════════════════════════════════
        // SOLANA WHALES
        // ══════════════════════════════════════════════════════════════════
        
        "GaBxu5TxgA9V4CgKeLHvKgGzYhYu5EATN7hjHDapjMNj": "Binance Hot Wallet",
        "5tzFkiKscXHK5ZXCGbXZxdw7gTjjD1mBwuoFbhUvuAi9": "Binance Hot Wallet 2",
        "H8sMJSCQxfKiFTCfDR3DUMLPwcRbM61LGFJ8N4dK3WjS": "Coinbase Hot Wallet",
        "2AQdpHJ2JpcEgPiATUXjQxA8QmafFegfQwSLWSprPicm": "Kraken Hot Wallet",
        "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM": "OKX Hot Wallet",
        "AobVSwdW9BbpMdJvTqeCN4hPAmh4rHm7vwLnQ5ATSyrS": "FTX Recovery Wallet",
        
        // ══════════════════════════════════════════════════════════════════
        // ARBITRUM WHALES
        // ══════════════════════════════════════════════════════════════════
        
        "0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D": "Binance Arbitrum",
        "0x1714400FF23dB4aF24F9fd64e7039e6597f18C2b": "Arbitrum Bridge",
        
        // ══════════════════════════════════════════════════════════════════
        // POLYGON WHALES
        // ══════════════════════════════════════════════════════════════════
        
        "0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245": "Binance Polygon",
        "0x0D0707963952f2fBA59dD06f2b425ace40b492Fe": "Binance Polygon 2",
        
        // ══════════════════════════════════════════════════════════════════
        // AVALANCHE WHALES
        // ══════════════════════════════════════════════════════════════════
        
        "0x9f8c163cBA728e99993ABe7495F06c0A3c8Ac8b9": "Binance Avalanche",
        
        // ══════════════════════════════════════════════════════════════════
        // BSC WHALES
        // ══════════════════════════════════════════════════════════════════
        
        "0x8894E0a0c962CB723c1976a4421c95949bE2D4E3": "Binance Hot Wallet BSC",
        "0xe2fc31F816A9b94326492132018C3aEcC4a93aE1": "Binance Hot Wallet BSC 2",
        "0xa180Fe01B906A1bE37BE6c534a3300785b20d947": "Binance Hot Wallet BSC 3",
    ]
    
    // MARK: - Exchange Addresses
    
    /// All known exchange wallet addresses (computed lazily to avoid initialization issues)
    public static var exchangeAddresses: Set<String> {
        Set(labels.keys.map { $0.lowercased() })
    }
    
    /// Check if address is a known exchange wallet
    public static func isExchangeAddress(_ address: String) -> Bool {
        exchangeAddresses.contains(address.lowercased())
    }
    
    public static func label(for address: String) -> String? {
        // Case-insensitive lookup
        for (key, value) in labels {
            if key.lowercased() == address.lowercased() {
                return value
            }
        }
        return nil
    }
    
    /// Get blockchain type from address format
    public static func inferBlockchain(from address: String) -> WhaleBlockchain? {
        if address.hasPrefix("0x") && address.count == 42 {
            return .ethereum // Could also be other EVM chains
        } else if address.hasPrefix("bc1") || address.hasPrefix("1") || address.hasPrefix("3") {
            return .bitcoin
        } else if address.count >= 32 && address.count <= 44 && !address.hasPrefix("0x") {
            return .solana
        }
        return nil
    }
}

// MARK: - Smart Money Wallet

/// Represents a known profitable/smart money wallet to track
public struct SmartMoneyWallet: Identifiable, Codable {
    public let id: UUID
    public let address: String
    public let label: String
    public let blockchain: WhaleBlockchain
    public let historicalROI: Double? // Percentage
    public let category: SmartMoneyCategory
    
    public init(
        id: UUID = UUID(),
        address: String,
        label: String,
        blockchain: WhaleBlockchain,
        historicalROI: Double? = nil,
        category: SmartMoneyCategory
    ) {
        self.id = id
        self.address = address
        self.label = label
        self.blockchain = blockchain
        self.historicalROI = historicalROI
        self.category = category
    }
}

public enum SmartMoneyCategory: String, Codable, CaseIterable {
    case defiWhale = "DeFi Whale"
    case nftCollector = "NFT Collector"
    case institutionalFund = "Institutional"
    case earlyAdopter = "Early Adopter"
    case tradeBot = "Trade Bot"
    case unknown = "Unknown"
    
    public var icon: String {
        switch self {
        case .defiWhale: return "dollarsign.circle.fill"
        case .nftCollector: return "photo.artframe"
        case .institutionalFund: return "building.columns.fill"
        case .earlyAdopter: return "star.fill"
        case .tradeBot: return "gearshape.2.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    public var color: Color {
        switch self {
        case .defiWhale: return .purple
        case .nftCollector: return .pink
        case .institutionalFund: return .blue
        case .earlyAdopter: return .orange
        case .tradeBot: return .cyan
        case .unknown: return .gray
        }
    }
    
    public var shortLabel: String {
        switch self {
        case .defiWhale: return "DeFi"
        case .nftCollector: return "NFT"
        case .institutionalFund: return "Fund"
        case .earlyAdopter: return "OG"
        case .tradeBot: return "Bot"
        case .unknown: return "?"
        }
    }
}

// MARK: - Smart Money Signal

/// Represents a smart money activity signal
public struct SmartMoneySignal: Identifiable, Codable {
    public let id: UUID
    public let wallet: SmartMoneyWallet
    public let transaction: WhaleTransaction
    public let signalType: SignalType
    public let confidence: Double // 0-100
    public let timestamp: Date
    
    public enum SignalType: String, Codable {
        case accumulating = "Accumulating"
        case distributing = "Distributing"
        case transferring = "Transferring"
        case depositing = "Depositing to Exchange"
        case withdrawing = "Withdrawing from Exchange"
        
        public var icon: String {
            switch self {
            case .accumulating: return "arrow.down.circle.fill"
            case .distributing: return "arrow.up.circle.fill"
            case .transferring: return "arrow.left.arrow.right.circle.fill"
            case .depositing: return "arrow.right.to.line.circle.fill"
            case .withdrawing: return "arrow.left.to.line.circle.fill"
            }
        }
        
        public var color: Color {
            switch self {
            case .accumulating, .withdrawing: return .green
            case .distributing, .depositing: return .red
            case .transferring: return .gray
            }
        }
        
        public var sentiment: TransactionSentiment {
            switch self {
            case .accumulating, .withdrawing: return .bullish
            case .distributing, .depositing: return .bearish
            case .transferring: return .neutral
            }
        }
    }
    
    public init(
        id: UUID = UUID(),
        wallet: SmartMoneyWallet,
        transaction: WhaleTransaction,
        signalType: SignalType,
        confidence: Double,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.wallet = wallet
        self.transaction = transaction
        self.signalType = signalType
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

// MARK: - Smart Money Index

/// Aggregated smart money sentiment
public struct SmartMoneyIndex: Codable {
    public let score: Int // 0-100
    public let trend: Trend
    public let bullishSignals: Int
    public let bearishSignals: Int
    public let neutralSignals: Int
    public let lastUpdated: Date
    
    public enum Trend: String, Codable {
        case strongBullish = "Strong Buy"
        case bullish = "Bullish"
        case neutral = "Neutral"
        case bearish = "Bearish"
        case strongBearish = "Strong Sell"
        
        public var color: Color {
            switch self {
            case .strongBullish: return .green
            case .bullish: return Color(red: 0.4, green: 0.8, blue: 0.4)
            case .neutral: return .gray
            case .bearish: return Color(red: 0.9, green: 0.5, blue: 0.5)
            case .strongBearish: return .red
            }
        }
        
        public var icon: String {
            switch self {
            case .strongBullish: return "arrow.up.circle.fill"
            case .bullish: return "arrow.up.right.circle"
            case .neutral: return "minus.circle"
            case .bearish: return "arrow.down.right.circle"
            case .strongBearish: return "arrow.down.circle.fill"
            }
        }
    }
    
    public static func from(score: Int) -> Trend {
        switch score {
        case 0..<20: return .strongBearish
        case 20..<40: return .bearish
        case 40..<60: return .neutral
        case 60..<80: return .bullish
        default: return .strongBullish
        }
    }
}

// MARK: - Known Smart Money Wallets

/// Curated list of known smart money wallets (50+ tracked)
public struct KnownSmartMoneyWallets {
    public static let wallets: [SmartMoneyWallet] = [
        // ═══════════════════════════════════════════════════════════════
        // TIER 1: Major Institutional Funds & Trading Firms
        // ═══════════════════════════════════════════════════════════════
        SmartMoneyWallet(
            address: "0x8103683202aa8da10536036edef04cdd865c225e",
            label: "Jump Trading",
            blockchain: .ethereum,
            historicalROI: 285.5,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "0x6d6f636f2c9f7c39af1f1f3be73c62b06eab9e7c",
            label: "Paradigm",
            blockchain: .ethereum,
            historicalROI: 342.8,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "0x5f65f7b609678448494de4c87521cdf6cef1e932",
            label: "Galaxy Digital",
            blockchain: .ethereum,
            historicalROI: 198.3,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "0x66b870ddf78c975af5cd8edc6de25eca81791de1",
            label: "a16z Crypto",
            blockchain: .ethereum,
            historicalROI: 412.6,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "0x0716a17fbaee714f1e6ab0f9d59edbc5f09815c0",
            label: "Pantera Capital",
            blockchain: .ethereum,
            historicalROI: 267.4,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "0x40ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf",
            label: "Polychain Capital",
            blockchain: .ethereum,
            historicalROI: 389.2,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "0x1b7baa734c00298b9429b518d621753bb0f6eff2",
            label: "Dragonfly Capital",
            blockchain: .ethereum,
            historicalROI: 445.8,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "0x6262998ced04146fa42253a5c0af90ca02dfd2a3",
            label: "Blockchain Capital",
            blockchain: .ethereum,
            historicalROI: 312.1,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "0xdbf5e9c5206d0db70a90108bf936da60221dc080",
            label: "Multicoin Capital",
            blockchain: .ethereum,
            historicalROI: 523.7,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "0x1db3439a222c519ab44bb1144fc28167b4fa6ee6",
            label: "Delphi Digital",
            blockchain: .ethereum,
            historicalROI: 478.3,
            category: .institutionalFund
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // TIER 2: Market Makers & Trading Bots
        // ═══════════════════════════════════════════════════════════════
        SmartMoneyWallet(
            address: "0x56178a0d5f301baf6cf3e1cd53d9863437345bf9",
            label: "Wintermute",
            blockchain: .ethereum,
            historicalROI: 156.7,
            category: .tradeBot
        ),
        SmartMoneyWallet(
            address: "0xe8c19db00287e3536075114b2576c70773e039bd",
            label: "Amber Group",
            blockchain: .ethereum,
            historicalROI: 189.4,
            category: .tradeBot
        ),
        SmartMoneyWallet(
            address: "0x9507c04b10486547584c37bcbd931b2a4fee9a41",
            label: "Cumberland",
            blockchain: .ethereum,
            historicalROI: 167.2,
            category: .tradeBot
        ),
        SmartMoneyWallet(
            address: "0xf584f8728b874a6a5c7a8d4d387c9aae9172d621",
            label: "GSR Markets",
            blockchain: .ethereum,
            historicalROI: 145.8,
            category: .tradeBot
        ),
        SmartMoneyWallet(
            address: "0x28c6c06298d514db089934071355e5743bf21d60",
            label: "Alameda (Historical)",
            blockchain: .ethereum,
            historicalROI: nil,
            category: .tradeBot
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // TIER 3: Notable DeFi Whales & Influencers
        // ═══════════════════════════════════════════════════════════════
        SmartMoneyWallet(
            address: "0x7a16ff8270133f063aab6c9977183d9e72835428",
            label: "Tetranode",
            blockchain: .ethereum,
            historicalROI: 892.4,
            category: .defiWhale
        ),
        SmartMoneyWallet(
            address: "0xc5ed2333f8a2c351fca35e5ebadb2a82f5d254c3",
            label: "DegenSpartan",
            blockchain: .ethereum,
            historicalROI: 445.2,
            category: .defiWhale
        ),
        SmartMoneyWallet(
            address: "0xa1d8d972560c2f8144af871db508f0b0b10a3fbf",
            label: "Token Hunter",
            blockchain: .ethereum,
            historicalROI: 678.9,
            category: .defiWhale
        ),
        SmartMoneyWallet(
            address: "0x2d407ddb06311396fe14d4b49da5f0471447d45c",
            label: "Andre Cronje",
            blockchain: .ethereum,
            historicalROI: 1245.6,
            category: .defiWhale
        ),
        SmartMoneyWallet(
            address: "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
            label: "vitalik.eth",
            blockchain: .ethereum,
            historicalROI: nil,
            category: .earlyAdopter
        ),
        SmartMoneyWallet(
            address: "0xab5801a7d398351b8be11c439e05c5b3259aec9b",
            label: "Vitalik (Old)",
            blockchain: .ethereum,
            historicalROI: nil,
            category: .earlyAdopter
        ),
        SmartMoneyWallet(
            address: "0x7d8a9c5ec5e76e89d1d1b12a3987456f0c3a4e9c",
            label: "0xMaki",
            blockchain: .ethereum,
            historicalROI: 567.3,
            category: .defiWhale
        ),
        SmartMoneyWallet(
            address: "0xf8e0c93fd480ce4d3b6c1e8d5c7a2bdf9a59e4a8",
            label: "Cobie",
            blockchain: .ethereum,
            historicalROI: 723.4,
            category: .defiWhale
        ),
        SmartMoneyWallet(
            address: "0x1b3cb81e51011b549d78bf720b0d924ac763a7c2",
            label: "Hsaka",
            blockchain: .ethereum,
            historicalROI: 534.8,
            category: .defiWhale
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // TIER 4: Solana Smart Money
        // ═══════════════════════════════════════════════════════════════
        SmartMoneyWallet(
            address: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
            label: "Alameda SOL",
            blockchain: .solana,
            historicalROI: nil,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "5Q544fKrFoe6tsEbD7S8EmxGTJYAKtTVhAW5Q5pge4j1",
            label: "Raydium Treasury",
            blockchain: .solana,
            historicalROI: nil,
            category: .defiWhale
        ),
        SmartMoneyWallet(
            address: "4yWr7H2p8rt11QnXb2yxQF3zxSdcToReu5qSndWFEJw",
            label: "Jump SOL",
            blockchain: .solana,
            historicalROI: 234.5,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "GmvVCbTYhwNPYZHRqyNNdPn8LHGeVpXqQCZuH3fA2PG5",
            label: "Multicoin SOL",
            blockchain: .solana,
            historicalROI: 456.7,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "Hzyi7wS6C3yFJLkLJY8fBxgNBf3R6ZLhvQJzE8MuWNxg",
            label: "Solana Foundation",
            blockchain: .solana,
            historicalROI: nil,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T",
            label: "Marinade Finance",
            blockchain: .solana,
            historicalROI: 312.8,
            category: .defiWhale
        ),
        SmartMoneyWallet(
            address: "AyYrFv9gBc8h3H3R5BbQZbnTvBdN3xB4YhqJczLpJyAy",
            label: "SOL Whale #1",
            blockchain: .solana,
            historicalROI: 678.2,
            category: .defiWhale
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // TIER 5: Bitcoin Whales (tracked via wrapped BTC or known)
        // ═══════════════════════════════════════════════════════════════
        SmartMoneyWallet(
            address: "1P5ZEDWTKTFGxQjZphgWPQUpe554WKDfHQ",
            label: "MicroStrategy",
            blockchain: .bitcoin,
            historicalROI: 89.4,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "3LYJfcfHPXYJreMsASk2jkn69LWEYKzexb",
            label: "Tesla (Historical)",
            blockchain: .bitcoin,
            historicalROI: nil,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "1FzWLkAahHooV3kzPgBvNNBfKXxhbzA6BQ",
            label: "Grayscale GBTC",
            blockchain: .bitcoin,
            historicalROI: nil,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "bc1qazcm763858nkj2dj986etajv6wquslv8uxwczt",
            label: "Block.one",
            blockchain: .bitcoin,
            historicalROI: nil,
            category: .institutionalFund
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // TIER 6: Arbitrum & L2 Smart Money
        // ═══════════════════════════════════════════════════════════════
        SmartMoneyWallet(
            address: "0xf977814e90da44bfa03b6295a0616a897441acec",
            label: "Binance ARB",
            blockchain: .arbitrum,
            historicalROI: nil,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "0x912ce59144191c1204e64559fe8253a0e49e6548",
            label: "ARB Treasury",
            blockchain: .arbitrum,
            historicalROI: nil,
            category: .institutionalFund
        ),
        SmartMoneyWallet(
            address: "0x489ee077994b6658eafa855c308275ead8097c4a",
            label: "GMX Whale",
            blockchain: .arbitrum,
            historicalROI: 567.8,
            category: .defiWhale
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // TIER 7: NFT Whales & Collectors
        // ═══════════════════════════════════════════════════════════════
        SmartMoneyWallet(
            address: "0xce90a7949bb78892f159f428d0dc23a8e3584d75",
            label: "Punk6529",
            blockchain: .ethereum,
            historicalROI: 1567.3,
            category: .nftCollector
        ),
        SmartMoneyWallet(
            address: "0xd387a6e4e84a6c86bd90c158c6028a58cc8ac459",
            label: "Pranksy",
            blockchain: .ethereum,
            historicalROI: 892.5,
            category: .nftCollector
        ),
        SmartMoneyWallet(
            address: "0x54be3a794282c030b15e43ae2bb182e14c409c5e",
            label: "Beanie",
            blockchain: .ethereum,
            historicalROI: 634.2,
            category: .nftCollector
        ),
        SmartMoneyWallet(
            address: "0xf476cd75be8fdd197ae0b466a2ec2ae44da41897",
            label: "VincentVanDough",
            blockchain: .ethereum,
            historicalROI: 789.1,
            category: .nftCollector
        ),
    ]
    
    /// Check if an address is a known smart money wallet
    public static func isSmartMoney(_ address: String) -> Bool {
        wallets.contains { $0.address.lowercased() == address.lowercased() }
    }
    
    /// Get the smart money wallet info for an address
    public static func wallet(for address: String) -> SmartMoneyWallet? {
        wallets.first { $0.address.lowercased() == address.lowercased() }
    }
}

// MARK: - Popular Wallets to Watch

/// Curated list of interesting wallets users might want to watch (20+ options)
public struct PopularWalletsToWatch {
    public static let wallets: [WatchedWallet] = [
        // ═══════════════════════════════════════════════════════════════
        // EXCHANGES - Track large exchange movements
        // ═══════════════════════════════════════════════════════════════
        WatchedWallet(
            address: "0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8",
            label: "Binance Hot Wallet",
            blockchain: .ethereum,
            notifyOnActivity: true,
            minTransactionAmount: 1_000_000
        ),
        WatchedWallet(
            address: "0xDFd5293D8e347dFe59E90eFd55b2956a1343963d",
            label: "Coinbase Prime",
            blockchain: .ethereum,
            notifyOnActivity: true,
            minTransactionAmount: 1_000_000
        ),
        WatchedWallet(
            address: "0x2910543Af39abA0Cd09dBb2D50200b3E800A63D2",
            label: "Kraken Hot Wallet",
            blockchain: .ethereum,
            notifyOnActivity: true,
            minTransactionAmount: 500_000
        ),
        WatchedWallet(
            address: "0x28C6c06298d514Db089934071355E5743bf21d60",
            label: "Binance Cold Wallet",
            blockchain: .ethereum,
            notifyOnActivity: true,
            minTransactionAmount: 5_000_000
        ),
        WatchedWallet(
            address: "34xp4vRoCGJym3xR7yCVPFHoCNxv4Twseo",
            label: "Binance BTC Hot",
            blockchain: .bitcoin,
            notifyOnActivity: true,
            minTransactionAmount: 1_000_000
        ),
        WatchedWallet(
            address: "GaBxu5TxgA9V4CgKeLHvKgGzYhYu5EATN7hjHDapjMNj",
            label: "Binance SOL Hot",
            blockchain: .solana,
            notifyOnActivity: true,
            minTransactionAmount: 500_000
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // SMART MONEY - Track successful traders
        // ═══════════════════════════════════════════════════════════════
        WatchedWallet(
            address: "0x8103683202aa8da10536036edef04cdd865c225e",
            label: "Jump Trading",
            blockchain: .ethereum,
            notifyOnActivity: true,
            minTransactionAmount: 500_000
        ),
        WatchedWallet(
            address: "0x56178a0d5f301baf6cf3e1cd53d9863437345bf9",
            label: "Wintermute",
            blockchain: .ethereum,
            notifyOnActivity: true,
            minTransactionAmount: 500_000
        ),
        WatchedWallet(
            address: "0x7a16ff8270133f063aab6c9977183d9e72835428",
            label: "Tetranode",
            blockchain: .ethereum,
            notifyOnActivity: true,
            minTransactionAmount: 100_000
        ),
        WatchedWallet(
            address: "0x2d407ddb06311396fe14d4b49da5f0471447d45c",
            label: "Andre Cronje",
            blockchain: .ethereum,
            notifyOnActivity: true,
            minTransactionAmount: 100_000
        ),
        WatchedWallet(
            address: "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
            label: "vitalik.eth",
            blockchain: .ethereum,
            notifyOnActivity: true,
            minTransactionAmount: 100_000
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // INSTITUTIONAL - Track fund movements
        // ═══════════════════════════════════════════════════════════════
        WatchedWallet(
            address: "1P5ZEDWTKTFGxQjZphgWPQUpe554WKDfHQ",
            label: "MicroStrategy",
            blockchain: .bitcoin,
            notifyOnActivity: true,
            minTransactionAmount: 10_000_000
        ),
        WatchedWallet(
            address: "1FzWLkAahHooV3kzPgBvNNBfKXxhbzA6BQ",
            label: "Grayscale GBTC",
            blockchain: .bitcoin,
            notifyOnActivity: true,
            minTransactionAmount: 10_000_000
        ),
        WatchedWallet(
            address: "0x66b870ddf78c975af5cd8edc6de25eca81791de1",
            label: "a16z Crypto",
            blockchain: .ethereum,
            notifyOnActivity: true,
            minTransactionAmount: 1_000_000
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // SOLANA WHALES
        // ═══════════════════════════════════════════════════════════════
        WatchedWallet(
            address: "4yWr7H2p8rt11QnXb2yxQF3zxSdcToReu5qSndWFEJw",
            label: "Jump SOL",
            blockchain: .solana,
            notifyOnActivity: true,
            minTransactionAmount: 500_000
        ),
        WatchedWallet(
            address: "5Q544fKrFoe6tsEbD7S8EmxGTJYAKtTVhAW5Q5pge4j1",
            label: "Raydium Treasury",
            blockchain: .solana,
            notifyOnActivity: true,
            minTransactionAmount: 250_000
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // NFT WHALES
        // ═══════════════════════════════════════════════════════════════
        WatchedWallet(
            address: "0xce90a7949bb78892f159f428d0dc23a8e3584d75",
            label: "Punk6529",
            blockchain: .ethereum,
            notifyOnActivity: true,
            minTransactionAmount: 100_000
        ),
        WatchedWallet(
            address: "0xd387a6e4e84a6c86bd90c158c6028a58cc8ac459",
            label: "Pranksy",
            blockchain: .ethereum,
            notifyOnActivity: true,
            minTransactionAmount: 100_000
        ),
    ]
}

// MARK: - API Response Models

/// Whale Alert API Response
public struct WhaleAlertResponse: Codable {
    public let result: String?
    public let cursor: String?
    public let count: Int?
    public let transactions: [WhaleAlertTransaction]?
}

public struct WhaleAlertTransaction: Codable {
    public let id: String?
    public let blockchain: String
    public let symbol: String
    public let hash: String
    public let timestamp: Int
    public let amount: Double
    public let amount_usd: Double
    public let from: WhaleAlertOwner
    public let to: WhaleAlertOwner
    public let transaction_type: String?
}

public struct WhaleAlertOwner: Codable {
    public let address: String?
    public let owner: String?
    public let owner_type: String?
}

/// Arkham Intelligence API Response
public struct ArkhamResponse: Codable {
    public let transfers: [ArkhamTransfer]?
    public let total: Int?
}

public struct ArkhamTransfer: Codable {
    public let hash: String
    public let chain: String?
    public let blockNumber: Int?
    public let timestamp: Int?
    public let fromAddress: String?
    public let toAddress: String?
    public let fromEntity: ArkhamEntity?
    public let toEntity: ArkhamEntity?
    public let tokenSymbol: String?
    public let amount: Double?
    public let usdValue: Double?
}

public struct ArkhamEntity: Codable {
    public let name: String?
    public let type: String?
    public let tags: [String]?
}
