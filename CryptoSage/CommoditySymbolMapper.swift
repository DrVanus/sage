//
//  CommoditySymbolMapper.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/30/26.
//  Maps commodity symbols between different data sources:
//  - Coinbase: XAU, XAG, XPT, XPD, XCU
//  - Yahoo Finance: GC=F, SI=F, PL=F, PA=F, HG=F
//  - TradingView: COMEX:GC1!, COMEX:SI1!, NYMEX:PL1!, etc.
//

import Foundation

// MARK: - Commodity Type

/// Represents different types of commodities
enum CommodityType: String, CaseIterable, Identifiable {
    case preciousMetal = "Precious Metal"
    case industrialMetal = "Industrial Metal"
    case energy = "Energy"
    case agriculture = "Agriculture"
    case livestock = "Livestock"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .preciousMetal: return "sparkles"
        case .industrialMetal: return "hammer.fill"
        case .energy: return "bolt.fill"
        case .agriculture: return "leaf.fill"
        case .livestock: return "hare.fill"
        }
    }
}

// MARK: - Commodity Info

/// Complete information about a commodity
struct CommodityInfo: Identifiable, Hashable {
    let id: String                    // Canonical ID (e.g., "gold", "silver")
    let name: String                  // Display name (e.g., "Gold", "Silver")
    let type: CommodityType           // Category
    let coinbaseSymbol: String?       // Coinbase symbol (e.g., "XAU")
    let yahooSymbol: String           // Yahoo Finance futures symbol (e.g., "GC=F")
    let tradingViewSymbol: String     // TradingView symbol (e.g., "COMEX:GC1!")
    let tradingViewAltSymbols: [String] // Alternative TradingView symbols
    let unit: String                  // Unit of measurement (e.g., "oz", "lb", "barrel")
    let currencyCode: String?         // ISO 4217 code if applicable (e.g., "XAU")
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CommodityInfo, rhs: CommodityInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Commodity Symbol Mapper

/// Central mapper for converting commodity symbols between different data sources
enum CommoditySymbolMapper {
    
    // MARK: - All Commodities Database
    
    /// Complete list of supported commodities with all symbol mappings
    static let allCommodities: [CommodityInfo] = [
        // Precious Metals
        // Note: coinbaseSymbol set to nil because Coinbase Exchange doesn't support
        // precious metal trading pairs (XAU-USD, XAG-USD, etc.). Uses Yahoo Finance directly.
        CommodityInfo(
            id: "gold",
            name: "Gold",
            type: .preciousMetal,
            coinbaseSymbol: nil,  // Coinbase doesn't support XAU-USD
            yahooSymbol: "GC=F",
            tradingViewSymbol: "COMEX:GC1!",
            tradingViewAltSymbols: ["TVC:GOLD", "OANDA:XAUUSD", "FOREXCOM:XAUUSD"],
            unit: "oz",
            currencyCode: "XAU"
        ),
        CommodityInfo(
            id: "silver",
            name: "Silver",
            type: .preciousMetal,
            coinbaseSymbol: nil,  // Coinbase doesn't support XAG-USD
            yahooSymbol: "SI=F",
            tradingViewSymbol: "COMEX:SI1!",
            tradingViewAltSymbols: ["TVC:SILVER", "OANDA:XAGUSD", "FOREXCOM:XAGUSD"],
            unit: "oz",
            currencyCode: "XAG"
        ),
        CommodityInfo(
            id: "platinum",
            name: "Platinum",
            type: .preciousMetal,
            coinbaseSymbol: nil,  // Coinbase doesn't support XPT-USD
            yahooSymbol: "PL=F",
            tradingViewSymbol: "NYMEX:PL1!",
            tradingViewAltSymbols: ["TVC:PLATINUM", "OANDA:XPTUSD"],
            unit: "oz",
            currencyCode: "XPT"
        ),
        CommodityInfo(
            id: "palladium",
            name: "Palladium",
            type: .preciousMetal,
            coinbaseSymbol: nil,  // Coinbase doesn't support XPD-USD
            yahooSymbol: "PA=F",
            tradingViewSymbol: "NYMEX:PA1!",
            tradingViewAltSymbols: ["TVC:PALLADIUM", "OANDA:XPDUSD"],
            unit: "oz",
            currencyCode: "XPD"
        ),
        // Note: Rhodium, Iridium, and Ruthenium are not available as futures/forex on
        // Yahoo Finance. They can only be tracked via TradingView or specialty data providers.
        // We omit them here to avoid showing "no data" placeholders.
        
        // Industrial Metals
        CommodityInfo(
            id: "copper",
            name: "Copper",
            type: .industrialMetal,
            coinbaseSymbol: nil,  // Coinbase doesn't support XCU-USD
            yahooSymbol: "HG=F",
            tradingViewSymbol: "COMEX:HG1!",
            tradingViewAltSymbols: ["TVC:COPPER", "OANDA:XCUUSD"],
            unit: "lb",
            currencyCode: "XCU"
        ),
        CommodityInfo(
            id: "aluminum",
            name: "Aluminum",
            type: .industrialMetal,
            coinbaseSymbol: nil,
            yahooSymbol: "ALI=F",
            tradingViewSymbol: "COMEX:ALI1!",
            tradingViewAltSymbols: ["TVC:ALUMINUM"],
            unit: "lb",
            currencyCode: nil
        ),
        // Note: Zinc (LME:ZINC1!), Nickel (LME:NI1!), Steel (HRC=F), and Uranium (UX=F)
        // do not have reliable Yahoo Finance data. They can be tracked via TradingView
        // but are omitted here to avoid showing "no data" placeholders.
        
        // Energy
        CommodityInfo(
            id: "crude_oil",
            name: "Crude Oil WTI",
            type: .energy,
            coinbaseSymbol: nil,
            yahooSymbol: "CL=F",
            tradingViewSymbol: "NYMEX:CL1!",
            tradingViewAltSymbols: ["TVC:USOIL", "OANDA:WTICOUSD"],
            unit: "barrel",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "brent_oil",
            name: "Brent Crude Oil",
            type: .energy,
            coinbaseSymbol: nil,
            yahooSymbol: "BZ=F",
            tradingViewSymbol: "NYMEX:BZ1!",
            tradingViewAltSymbols: ["TVC:UKOIL", "OANDA:BCOUSD"],
            unit: "barrel",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "natural_gas",
            name: "Natural Gas",
            type: .energy,
            coinbaseSymbol: nil,
            yahooSymbol: "NG=F",
            tradingViewSymbol: "NYMEX:NG1!",
            tradingViewAltSymbols: ["TVC:NATURALGAS"],
            unit: "MMBtu",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "heating_oil",
            name: "Heating Oil",
            type: .energy,
            coinbaseSymbol: nil,
            yahooSymbol: "HO=F",
            tradingViewSymbol: "NYMEX:HO1!",
            tradingViewAltSymbols: [],
            unit: "gallon",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "gasoline",
            name: "RBOB Gasoline",
            type: .energy,
            coinbaseSymbol: nil,
            yahooSymbol: "RB=F",
            tradingViewSymbol: "NYMEX:RB1!",
            tradingViewAltSymbols: [],
            unit: "gallon",
            currencyCode: nil
        ),
        // Note: Ethanol (EH=F) has unreliable data on Yahoo Finance. Omitted.
        
        // Agriculture
        CommodityInfo(
            id: "corn",
            name: "Corn",
            type: .agriculture,
            coinbaseSymbol: nil,
            yahooSymbol: "ZC=F",
            tradingViewSymbol: "CBOT:ZC1!",
            tradingViewAltSymbols: ["TVC:CORN"],
            unit: "bushel",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "soybeans",
            name: "Soybeans",
            type: .agriculture,
            coinbaseSymbol: nil,
            yahooSymbol: "ZS=F",
            tradingViewSymbol: "CBOT:ZS1!",
            tradingViewAltSymbols: ["TVC:SOYBEAN"],
            unit: "bushel",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "wheat",
            name: "Wheat",
            type: .agriculture,
            coinbaseSymbol: nil,
            yahooSymbol: "ZW=F",
            tradingViewSymbol: "CBOT:ZW1!",
            tradingViewAltSymbols: ["TVC:WHEAT"],
            unit: "bushel",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "coffee",
            name: "Coffee",
            type: .agriculture,
            coinbaseSymbol: nil,
            yahooSymbol: "KC=F",
            tradingViewSymbol: "ICEUS:KC1!",
            tradingViewAltSymbols: ["TVC:COFFEE"],
            unit: "lb",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "cocoa",
            name: "Cocoa",
            type: .agriculture,
            coinbaseSymbol: nil,
            yahooSymbol: "CC=F",
            tradingViewSymbol: "ICEUS:CC1!",
            tradingViewAltSymbols: ["TVC:COCOA"],
            unit: "ton",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "cotton",
            name: "Cotton",
            type: .agriculture,
            coinbaseSymbol: nil,
            yahooSymbol: "CT=F",
            tradingViewSymbol: "ICEUS:CT1!",
            tradingViewAltSymbols: ["TVC:COTTON"],
            unit: "lb",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "sugar",
            name: "Sugar",
            type: .agriculture,
            coinbaseSymbol: nil,
            yahooSymbol: "SB=F",
            tradingViewSymbol: "ICEUS:SB1!",
            tradingViewAltSymbols: ["TVC:SUGAR"],
            unit: "lb",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "oats",
            name: "Oats",
            type: .agriculture,
            coinbaseSymbol: nil,
            yahooSymbol: "ZO=F",
            tradingViewSymbol: "CBOT:ZO1!",
            tradingViewAltSymbols: ["TVC:OATS"],
            unit: "bushel",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "rice",
            name: "Rough Rice",
            type: .agriculture,
            coinbaseSymbol: nil,
            yahooSymbol: "ZR=F",
            tradingViewSymbol: "CBOT:ZR1!",
            tradingViewAltSymbols: [],
            unit: "cwt",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "orange_juice",
            name: "Orange Juice",
            type: .agriculture,
            coinbaseSymbol: nil,
            yahooSymbol: "OJ=F",
            tradingViewSymbol: "ICEUS:OJ1!",
            tradingViewAltSymbols: [],
            unit: "lb",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "lumber",
            name: "Lumber",
            type: .agriculture,
            coinbaseSymbol: nil,
            yahooSymbol: "LBS=F",
            tradingViewSymbol: "CME:LBS1!",
            tradingViewAltSymbols: [],
            unit: "bdft",
            currencyCode: nil
        ),
        
        // Livestock
        CommodityInfo(
            id: "live_cattle",
            name: "Live Cattle",
            type: .livestock,
            coinbaseSymbol: nil,
            yahooSymbol: "LE=F",
            tradingViewSymbol: "CME:LE1!",
            tradingViewAltSymbols: [],
            unit: "lb",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "lean_hogs",
            name: "Lean Hogs",
            type: .livestock,
            coinbaseSymbol: nil,
            yahooSymbol: "HE=F",
            tradingViewSymbol: "CME:HE1!",
            tradingViewAltSymbols: [],
            unit: "lb",
            currencyCode: nil
        ),
        CommodityInfo(
            id: "feeder_cattle",
            name: "Feeder Cattle",
            type: .livestock,
            coinbaseSymbol: nil,
            yahooSymbol: "GF=F",
            tradingViewSymbol: "CME:GF1!",
            tradingViewAltSymbols: [],
            unit: "lb",
            currencyCode: nil
        )
    ]
    
    // MARK: - Lookup Dictionaries (Computed once)
    
    /// Lookup by Coinbase symbol (XAU, XAG, etc.)
    private static let byCoinbaseSymbol: [String: CommodityInfo] = {
        var dict: [String: CommodityInfo] = [:]
        for commodity in allCommodities {
            if let symbol = commodity.coinbaseSymbol {
                dict[symbol.uppercased()] = commodity
            }
        }
        // Add common variations
        dict["GOLD"] = dict["XAU"]
        dict["GLD"] = dict["XAU"]
        dict["SILVER"] = dict["XAG"]
        dict["SLV"] = dict["XAG"]
        dict["PLATINUM"] = dict["XPT"]
        dict["PLT"] = dict["XPT"]
        dict["PLAT"] = dict["XPT"]
        dict["PALLADIUM"] = dict["XPD"]
        dict["PAL"] = dict["XPD"]
        dict["COPPER"] = dict["XCU"]
        dict["CU"] = dict["XCU"]
        dict["COPR"] = dict["XCU"]
        return dict
    }()
    
    /// Lookup by Yahoo Finance symbol (GC=F, SI=F, etc.)
    private static let byYahooSymbol: [String: CommodityInfo] = {
        var dict: [String: CommodityInfo] = [:]
        for commodity in allCommodities {
            dict[commodity.yahooSymbol.uppercased()] = commodity
        }
        return dict
    }()
    
    /// Lookup by TradingView symbol
    private static let byTradingViewSymbol: [String: CommodityInfo] = {
        var dict: [String: CommodityInfo] = [:]
        for commodity in allCommodities {
            dict[commodity.tradingViewSymbol.uppercased()] = commodity
            for alt in commodity.tradingViewAltSymbols {
                dict[alt.uppercased()] = commodity
            }
        }
        return dict
    }()
    
    /// Lookup by canonical ID
    private static let byId: [String: CommodityInfo] = {
        var dict: [String: CommodityInfo] = [:]
        for commodity in allCommodities {
            dict[commodity.id] = commodity
        }
        return dict
    }()
    
    // MARK: - Public API
    
    /// Get commodity info by any symbol type
    static func getCommodity(for symbol: String) -> CommodityInfo? {
        let upper = symbol.uppercased()
        
        // Try Coinbase symbol first (most common in our app)
        if let commodity = byCoinbaseSymbol[upper] {
            return commodity
        }
        
        // Try Yahoo symbol
        if let commodity = byYahooSymbol[upper] {
            return commodity
        }
        
        // Try TradingView symbol
        if let commodity = byTradingViewSymbol[upper] {
            return commodity
        }
        
        // Try canonical ID
        if let commodity = byId[symbol.lowercased()] {
            return commodity
        }
        
        return nil
    }
    
    /// Get commodity info by Coinbase symbol
    static func getCommodityByCoinbase(_ symbol: String) -> CommodityInfo? {
        byCoinbaseSymbol[symbol.uppercased()]
    }
    
    /// Get commodity info by Yahoo Finance symbol
    static func getCommodityByYahoo(_ symbol: String) -> CommodityInfo? {
        byYahooSymbol[symbol.uppercased()]
    }
    
    /// Get commodity info by TradingView symbol
    static func getCommodityByTradingView(_ symbol: String) -> CommodityInfo? {
        byTradingViewSymbol[symbol.uppercased()]
    }
    
    /// Get commodity info by canonical ID
    static func getCommodityById(_ id: String) -> CommodityInfo? {
        byId[id.lowercased()]
    }
    
    // MARK: - Symbol Conversion
    
    /// Convert any symbol to Yahoo Finance format
    static func toYahooSymbol(_ symbol: String) -> String? {
        getCommodity(for: symbol)?.yahooSymbol
    }
    
    /// Convert any symbol to TradingView format
    static func toTradingViewSymbol(_ symbol: String) -> String? {
        getCommodity(for: symbol)?.tradingViewSymbol
    }
    
    /// Convert any symbol to Coinbase format (returns nil if not available on Coinbase)
    static func toCoinbaseSymbol(_ symbol: String) -> String? {
        getCommodity(for: symbol)?.coinbaseSymbol
    }
    
    /// Get all TradingView symbols (primary + alternatives) for fallback chain
    static func getTradingViewSymbols(_ symbol: String) -> [String] {
        guard let commodity = getCommodity(for: symbol) else { return [] }
        return [commodity.tradingViewSymbol] + commodity.tradingViewAltSymbols
    }
    
    // MARK: - Commodity Lists
    
    /// Get all commodities available on Coinbase
    static var coinbaseCommodities: [CommodityInfo] {
        allCommodities.filter { $0.coinbaseSymbol != nil }
    }
    
    /// Get all precious metals
    static var preciousMetals: [CommodityInfo] {
        allCommodities.filter { $0.type == .preciousMetal }
    }
    
    /// Get commodities by type
    static func commodities(ofType type: CommodityType) -> [CommodityInfo] {
        allCommodities.filter { $0.type == type }
    }
    
    // MARK: - Validation
    
    /// Check if a symbol represents a known commodity
    static func isCommodity(_ symbol: String) -> Bool {
        getCommodity(for: symbol) != nil
    }
    
    /// Check if a symbol is available on Coinbase
    static func isAvailableOnCoinbase(_ symbol: String) -> Bool {
        getCommodity(for: symbol)?.coinbaseSymbol != nil
    }
    
    // MARK: - Display Helpers
    
    /// Get display name for any symbol
    static func displayName(for symbol: String) -> String {
        getCommodity(for: symbol)?.name ?? symbol
    }
    
    /// Get commodity type for any symbol
    static func commodityType(for symbol: String) -> CommodityType? {
        getCommodity(for: symbol)?.type
    }
    
    /// Get unit of measurement for any symbol
    static func unit(for symbol: String) -> String {
        getCommodity(for: symbol)?.unit ?? "unit"
    }
}

// MARK: - Extensions

extension CommodityInfo {
    /// Check if this commodity has live Coinbase data available
    var hasCoinbaseData: Bool {
        coinbaseSymbol != nil
    }
    
    /// Get the best display symbol for the UI
    var displaySymbol: String {
        coinbaseSymbol ?? yahooSymbol.replacingOccurrences(of: "=F", with: "")
    }
}
