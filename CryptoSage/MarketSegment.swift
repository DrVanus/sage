import Foundation
import SwiftUI

// ————————————
// 1) MarketSegment enum
// ————————————
enum MarketSegment: String, CaseIterable, Identifiable {
    case all       = "All"
    case trending  = "Trending"
    case gainers   = "Gainers"
    case losers    = "Losers"
    case favorites = "Favorites"
    case new       = "New"
    var id: String { rawValue }
}

// ————————————
// 1b) MarketCategory enum - sub-categories for filtering by coin type
// ————————————
enum MarketCategory: String, CaseIterable, Identifiable {
    case all           = "All"
    case layer1        = "Layer 1"
    case layer2        = "Layer 2"
    case defi          = "DeFi"
    case meme          = "Meme"
    case solana        = "Solana"
    case stablecoin    = "Stablecoin"
    case gaming        = "Gaming"
    case ai            = "AI"
    case preciousMetals = "Metals"
    
    var id: String { rawValue }
    
    /// Icon for the category
    var icon: String {
        switch self {
        case .all:           return "square.grid.2x2"
        case .layer1:        return "cube.fill"
        case .layer2:        return "cube.transparent"
        case .defi:          return "chart.pie.fill"
        case .meme:          return "face.smiling"
        case .solana:        return "s.circle.fill"
        case .stablecoin:    return "dollarsign.circle"
        case .gaming:        return "gamecontroller.fill"
        case .ai:            return "brain.head.profile"
        case .preciousMetals: return "scalemass.fill"
        }
    }
    
    /// Known coin symbols for each category - extensively expanded for better coverage
    static let categorySymbols: [MarketCategory: Set<String>] = [
        // Layer 1 blockchains - major base layer protocols
        .layer1: [
            "BTC", "ETH", "SOL", "ADA", "AVAX", "DOT", "ATOM", "NEAR", "APT", "SUI",
            "TON", "XLM", "ALGO", "HBAR", "ICP", "FTM", "FLOW", "KAS", "XRP", "TRX",
            "ETC", "SEI", "TIA", "INJ", "KAVA", "ROSE", "EGLD", "MINA", "CFX", "VET",
            "ONE", "THETA", "NEO", "WAVES", "ZIL", "ICX", "QTUM", "ZEN", "XTZ", "EOS",
            "IOTA", "XEC", "BCH", "LTC", "DASH", "ZEC", "DCR", "RVN", "BTG", "DGB"
        ],
        
        // Layer 2 scaling solutions
        .layer2: [
            "MATIC", "POL", "ARB", "OP", "IMX", "MNT", "STRK", "ZK", "LRC", "METIS",
            "BOBA", "BLAST", "MODE", "SCROLL", "SKL", "CELR", "CTSI", "CELO", "MOVR",
            "GLMR", "ASTR", "SDN"
        ],
        
        // DeFi protocols - decentralized finance
        .defi: [
            "UNI", "AAVE", "LINK", "MKR", "LDO", "CRV", "COMP", "SNX", "SUSHI", "YFI",
            "BAL", "1INCH", "DYDX", "GRT", "INJ", "RUNE", "GMX", "PENDLE", "JUP", "RAY",
            "ORCA", "DRIFT", "BANANA", "CAKE", "JOE", "SPELL", "CVX", "FXS", "RPL", "SSV",
            "LQTY", "PERP", "ALPHA", "BADGER", "BOND", "ALCX", "TRIBE", "TOKE", "RBN",
            "KNC", "ZRX", "REEF", "CREAM", "BNT", "KAVA", "OSMO", "KUJI", "MNDE", "STEP"
        ],
        
        // Meme coins - community-driven tokens
        .meme: [
            "DOGE", "SHIB", "PEPE", "BONK", "FLOKI", "WIF", "MEME", "ELON", "BABYDOGE",
            "SAMO", "COQ", "MYRO", "POPCAT", "BRETT", "MOG", "NEIRO", "TURBO", "PNUT",
            "FARTCOIN", "BOME", "WEN", "SLERF", "GIGA", "MICHI", "DOGWIFHAT", "SPX",
            "TRUMP", "ANDY", "TOSHI", "PONKE", "SNEK", "LADYS", "WOJAK", "PEPE2",
            "HPOS10I", "AIDOGE", "VOLT", "KISHU", "AKITA", "HUSKY", "CATE", "DOGELON",
            // Additional trending memes
            "GOAT", "ACT", "CHILLGUY", "MOODENG", "RETARDIO", "SUNDOG", "MINI", "MUMU",
            "BILLY", "HIGHER", "DEGEN", "NORMIE", "TYBG", "BENJI", "SKI", "KEYCAT",
            "CRASHED", "DOGINME", "BALD", "PENGU", "MEW", "GRASS", "USUAL", "AI16Z",
            "ZEREBRO", "ARC", "SWARMS"
        ],
        
        // Solana ecosystem tokens
        .solana: [
            "SOL", "JUP", "RAY", "ORCA", "BONK", "WIF", "PYTH", "JTO", "DRIFT", "TENSOR",
            "MNDE", "MSOL", "JITOSOL", "POPCAT", "BOME", "WEN", "SLERF", "SAMO", "RNDR",
            "HNT", "MOBILE", "IOT", "FIDA", "SRM", "STEP", "COPE", "TULIP", "SUNNY",
            "PORT", "SLND", "LARIX", "MANGO", "MEDIA", "GRAPE", "GENE", "SHDW", "DUST",
            "FORGE", "MEAN", "UXD", "HAWK", "BERN", "CROWN", "GOFX", "HXRO", "HONEY",
            "PUMP", "PONKE", "MYRO", "SILLY", "GME", "MOTHER", "TREMP", "DADDY"
        ],
        
        // Stablecoins
        .stablecoin: [
            "USDT", "USDC", "BUSD", "DAI", "TUSD", "USDP", "FDUSD", "PYUSD", "GUSD",
            "FRAX", "LUSD", "USDD", "CRVUSD", "GHO", "EURC", "EURT", "USDS", "MIM",
            "USDJ", "SUSD", "USTC", "RSV", "CUSD", "XSGD", "EURS"
        ],
        
        // Gaming and metaverse tokens
        .gaming: [
            "AXS", "SAND", "MANA", "ENJ", "GALA", "ILV", "ALICE", "YGG", "MAGIC", "PRIME",
            "RON", "RONIN", "IMX", "BEAM", "PIXEL", "PORTAL", "SUPER", "PYR", "GODS",
            "HERO", "WILD", "UFO", "STARL", "ATLAS", "POLIS", "SLP", "WEMIX", "XPRT",
            "JEWEL", "DFK", "LOKA", "HIGH", "RACA", "MBOX", "TLM", "MOBOX", "DAR",
            "GHST", "REVV", "TOWER", "SKILL", "CHESS", "SIDUS", "DPET", "ZOON", "KART",
            "MAVIA", "NAKA", "ACE", "BIGTIME", "SHRAP", "XAI", "MYRIA", "GMT", "GST"
        ],
        
        // AI and machine learning tokens
        .ai: [
            "FET", "AGIX", "OCEAN", "RNDR", "TAO", "AKT", "ARKM", "WLD", "CTXC", "NMR",
            "ORAI", "NEAR", "GRT", "AIOZ", "PHB", "OLAS", "IO", "VIRTUAL", "GRIFFAIN",
            "ALI", "RSS3", "CGPT", "PAAL", "AIMX", "VAIOT", "COVAL", "DBC", "MASA",
            "PRIME", "GLM", "DIMO", "ALEPH", "NOIA", "LPT", "ANKR", "RLC", "STORJ",
            "AR", "FIL", "THETA", "TFUEL", "NKN", "FLUX", "HNS", "SC", "BTT",
            // Additional AI tokens
            "AI16Z", "ZEREBRO", "ARC", "SWARMS", "GRASS", "GOAT", "ACT", "EIGEN",
            "ZRO", "AEVO", "DRIFT", "TNSR", "KMNO", "HYPE"
        ],
        
        // Precious Metals - gold-backed tokens and Coinbase metals
        .preciousMetals: [
            // Gold-backed crypto tokens
            "PAXG", "XAUT", "DGX", "PMGT", "AWG", "GLC", "CACHE", "GOLD",
            // Silver-backed tokens
            "SLV", "SLVT", "LODE", "SILVER",
            // Coinbase precious metals (ISO currency codes and common symbols)
            "XAU", "XAG", "XPT", "XPD", "XCU",
            // Coinbase naming variations
            "PLATINUM", "PLT", "PALLADIUM", "PAL", "COPPER", "CU", "COPR",
            // Other commodity-backed tokens
            "TCAP", "DPI", "MVI"
        ]
    ]
    
    /// Check if a coin symbol belongs to this category
    func contains(symbol: String) -> Bool {
        if self == .all { return true }
        return Self.categorySymbols[self]?.contains(symbol.uppercased()) ?? false
    }
}

// ————————————
// 2) SortField enum
// ————————————
enum SortField: String, CaseIterable, Identifiable {
    case coin        = "Coin"
    case price       = "Price"
    case dailyChange = "24h"
    case volume      = "Volume"
    case marketCap   = "Market Cap"
    var id: String { rawValue }
}

// ————————————
// 3) SortDirection enum
// ————————————
enum SortDirection: String, CaseIterable, Identifiable {
    case asc  = "Ascending"
    case desc = "Descending"
    var id: String { rawValue }
}

// ————————————
// 4) MarketSegmentViewModel
// ————————————
final class MarketSegmentViewModel: ObservableObject {
    @Published var selectedSegment: MarketSegment = .all
    @Published var sortField: SortField = .marketCap
    @Published var sortDirection: SortDirection = .desc

    func updateSegment(_ seg: MarketSegment) {
        selectedSegment = seg
    }

    func toggleSort(for field: SortField) {
        if sortField == field {
            sortDirection = (sortDirection == .asc ? .desc : .asc)
        } else {
            sortField = field
            sortDirection = .desc
        }
    }
}
