//
//  MarketCoin.swift
//  CryptoSage
//

import Foundation

/// Represents a single coin from Coingecko’s `/coins/markets` endpoint,
/// with additional computed fields for compatibility with existing views.
struct MarketCoin: Identifiable, Codable, Sendable, Equatable, Hashable {
    // MARK: - Data Validation Constants
    /// Maximum allowed percentage change (±10,000% to catch obvious API errors)
    private static let maxPercentChange: Double = 10000.0
    
    // MARK: - Validation Helpers
    
    /// Validates and clamps a percentage change to reasonable bounds
    private static func validatePercent(_ value: Double?) -> Double? {
        guard let v = value, v.isFinite else { return nil }
        // Clamp to ±10,000%
        return max(-maxPercentChange, min(maxPercentChange, v))
    }
    
    /// Validates a positive numeric value (returns nil for negative or invalid)
    private static func validatePositive(_ value: Double?) -> Double? {
        guard let v = value, v.isFinite, v >= 0 else { return nil }
        return v
    }
    
    // MARK: - Core JSON fields from CoinGecko
    let id: String
    let symbol: String
    let name: String
    /// URL of the coin’s image
    let imageUrl: URL?
    var priceUsd: Double?
    let marketCap: Double?
    let totalVolume: Double?
    let priceChangePercentage1hInCurrency: Double?
    let priceChangePercentage24hInCurrency: Double?
    let priceChangePercentage7dInCurrency: Double?
    let sparklineIn7d: [Double]
    let marketCapRank: Int?
    let maxSupply: Double?
    let circulatingSupply: Double?
    let totalSupply: Double?

    // MARK: - Legacy compatibility properties
    var volumeUsd24Hr: Double? { totalVolume }
    var changePercent24Hr: Double? { priceChangePercentage24hInCurrency }
    var hourlyChange: Double? { priceChangePercentage1hInCurrency }
    var dailyChange: Double? { priceChangePercentage24hInCurrency }
    var weeklyChange: Double? { priceChangePercentage7dInCurrency }
    var iconUrl: URL? { imageUrl }

    // MARK: - CodingKeys (map Swift names to JSON keys)
    enum CodingKeys: String, CodingKey {
        case id, symbol, name
        case imageUrl = "image"
        case priceUsd = "current_price"
        case marketCap = "market_cap"
        case totalVolume = "total_volume"
        case priceChangePercentage1hInCurrency = "price_change_percentage_1h_in_currency"
        case priceChangePercentage24hInCurrency = "price_change_percentage_24h_in_currency"
        case priceChangePercentage7dInCurrency = "price_change_percentage_7d_in_currency"
        case sparklineIn7d = "sparkline_in_7d"
        case marketCapRank = "market_cap_rank"
        case maxSupply = "max_supply"
        case circulatingSupply = "circulating_supply"
        case totalSupply = "total_supply"
    }
    
    private enum AltKeys: String, CodingKey {
        case price_change_percentage_1h = "price_change_percentage_1h"
        case price_change_percentage_24h = "price_change_percentage_24h"
        case price_change_percentage_7d = "price_change_percentage_7d"
    }

    struct SparklineArray: Codable {
        let price: [Double]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let altContainer = try decoder.container(keyedBy: AltKeys.self)
        id = try container.decode(String.self, forKey: .id)
        symbol = try container.decode(String.self, forKey: .symbol)
        name = try container.decode(String.self, forKey: .name)
        imageUrl = URL(string: (try? container.decode(String.self, forKey: .imageUrl)) ?? "")
        priceUsd = Self.validatePositive(try? container.decode(Double.self, forKey: .priceUsd))
        marketCap = Self.validatePositive(try? container.decode(Double.self, forKey: .marketCap))
        totalVolume = Self.validatePositive(try? container.decode(Double.self, forKey: .totalVolume))

        let oneHDirect = try? container.decode(Double.self, forKey: .priceChangePercentage1hInCurrency)
        let oneHAlt = try? altContainer.decodeIfPresent(Double.self, forKey: .price_change_percentage_1h)
        priceChangePercentage1hInCurrency = Self.validatePercent(oneHDirect ?? oneHAlt)

        let dayDirect = try? container.decode(Double.self, forKey: .priceChangePercentage24hInCurrency)
        let dayAlt = try? altContainer.decodeIfPresent(Double.self, forKey: .price_change_percentage_24h)
        priceChangePercentage24hInCurrency = Self.validatePercent(dayDirect ?? dayAlt)

        let weekDirect = try? container.decode(Double.self, forKey: .priceChangePercentage7dInCurrency)
        let weekAlt = try? altContainer.decodeIfPresent(Double.self, forKey: .price_change_percentage_7d)
        priceChangePercentage7dInCurrency = Self.validatePercent(weekDirect ?? weekAlt)

        marketCapRank = try? container.decode(Int.self, forKey: .marketCapRank)
        maxSupply = Self.validatePositive(try? container.decodeIfPresent(Double.self, forKey: .maxSupply))
        circulatingSupply = Self.validatePositive(try? container.decodeIfPresent(Double.self, forKey: .circulatingSupply))
        totalSupply = Self.validatePositive(try? container.decodeIfPresent(Double.self, forKey: .totalSupply))

        // Try to decode sparkline as either a nested object (API) or array (fallback)
        if let sparkObj = try? container.decodeIfPresent(SparklineArray.self, forKey: .sparklineIn7d) {
            sparklineIn7d = sparkObj.price
        } else if let arr = try? container.decodeIfPresent([Double].self, forKey: .sparklineIn7d) {
            sparklineIn7d = arr
        } else {
            sparklineIn7d = []
        }
    }

    /// Creates a MarketCoin from a CoinGeckoCoin model
    init(gecko: CoinGeckoCoin) {
        self.id = gecko.id
        self.symbol = gecko.symbol
        self.name = gecko.name
        self.imageUrl = URL(string: gecko.image)
        self.priceUsd = Self.validatePositive(gecko.currentPrice)
        self.marketCap = Self.validatePositive(gecko.marketCap)
        self.totalVolume = Self.validatePositive(gecko.totalVolume)
        self.priceChangePercentage1hInCurrency = Self.validatePercent(gecko.priceChangePercentage1h)
        self.priceChangePercentage24hInCurrency = Self.validatePercent(gecko.priceChangePercentage24h)
        self.priceChangePercentage7dInCurrency = Self.validatePercent(gecko.priceChangePercentage7d)
        self.sparklineIn7d = gecko.sparklineIn7d?.price ?? []
        self.marketCapRank = gecko.marketCapRank
        self.maxSupply = Self.validatePositive(gecko.maxSupply)
        self.circulatingSupply = Self.validatePositive(gecko.circulatingSupply)
        self.totalSupply = Self.validatePositive(gecko.totalSupply)
    }

    init(
        id: String,
        symbol: String,
        name: String,
        imageUrl: URL?,
        priceUsd: Double?,
        marketCap: Double?,
        totalVolume: Double?,
        priceChangePercentage1hInCurrency: Double?,
        priceChangePercentage24hInCurrency: Double?,
        priceChangePercentage7dInCurrency: Double?,
        sparklineIn7d: [Double],
        marketCapRank: Int?,
        maxSupply: Double?,
        circulatingSupply: Double?,
        totalSupply: Double?
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.imageUrl = imageUrl
        self.priceUsd = priceUsd
        self.marketCap = marketCap
        self.totalVolume = totalVolume
        self.priceChangePercentage1hInCurrency = priceChangePercentage1hInCurrency
        self.priceChangePercentage24hInCurrency = priceChangePercentage24hInCurrency
        self.priceChangePercentage7dInCurrency = priceChangePercentage7dInCurrency
        self.sparklineIn7d = sparklineIn7d
        self.marketCapRank = marketCapRank
        self.maxSupply = maxSupply
        self.circulatingSupply = circulatingSupply
        self.totalSupply = totalSupply
    }
}

extension MarketCoin {
    /// Unified 24h percent change used across the app.
    /// Prefer the value already overlaid into the coin payload; falls back to legacy field.
    var unified24hPercent: Double? {
        priceChangePercentage24hInCurrency ?? changePercent24Hr
    }

    /// Unified 1h percent change used across the app.
    /// Prefer the value already overlaid into the coin payload; falls back to legacy field.
    var unified1hPercent: Double? {
        priceChangePercentage1hInCurrency ?? hourlyChange
    }

    /// Unified 7d percent change used across the app.
    /// Prefer the value already overlaid into the coin payload; falls back to legacy field.
    var unified7dPercent: Double? {
        priceChangePercentage7dInCurrency ?? weeklyChange
    }

    /// Fractions (e.g., 0.051 == 5.1%) derived from unified percents.
    var unified24hFraction: Double? { unified24hPercent.map { $0 / 100.0 } }
    var unified1hFraction: Double? { unified1hPercent.map { $0 / 100.0 } }
    var unified7dFraction: Double? { unified7dPercent.map { $0 / 100.0 } }

    /// True when sparkline has at least two finite positive samples.
    var hasSparkline: Bool {
        sparklineIn7d.count > 1 && sparklineIn7d.allSatisfy { $0.isFinite && $0 > 0 }
    }

    /// Best-available market cap, preferring provider value; falls back to price * supply.
    /// Pass a live price if available to improve derivation; otherwise uses `priceUsd`.
    func effectiveMarketCap(usingPrice price: Double? = nil) -> Double? {
        if let cap = marketCap, cap.isFinite, cap > 0 { return cap }
        let p = price ?? priceUsd
        guard let p, p.isFinite, p > 0 else { return nil }
        if let circ = circulatingSupply, circ.isFinite, circ > 0 {
            let v = p * circ; if v.isFinite, v > 0 { return v }
        }
        if let total = totalSupply, total.isFinite, total > 0 {
            let v = p * total; if v.isFinite, v > 0 { return v }
        }
        if let maxS = maxSupply, maxS.isFinite, maxS > 0 {
            let v = p * maxS; if v.isFinite, v > 0 { return v }
        }
        return nil
    }

    /// Best display price from an optional live price or stored provider price.
    /// Returns nil if neither is a positive finite number.
    func bestDisplayPrice(live: Double?) -> Double? {
        if let lp = live, lp.isFinite, lp > 0 { return lp }
        if let p = priceUsd, p.isFinite, p > 0 { return p }
        return nil
    }

    /// Fully diluted valuation derived from the best available supply.
    /// Prefers maxSupply, then totalSupply, then circulatingSupply.
    /// Pass a live price if available; falls back to `priceUsd`.
    func effectiveFDV(usingPrice price: Double? = nil) -> Double? {
        let p = price ?? priceUsd
        guard let p, p.isFinite, p > 0 else { return nil }
        if let maxS = maxSupply, maxS.isFinite, maxS > 0 {
            let v = p * maxS; if v.isFinite, v > 0 { return v }
        }
        if let total = totalSupply, total.isFinite, total > 0 {
            let v = p * total; if v.isFinite, v > 0 { return v }
        }
        if let circ = circulatingSupply, circ.isFinite, circ > 0 {
            let v = p * circ; if v.isFinite, v > 0 { return v }
        }
        return nil
    }

    /// Best-available circulating supply.
    /// Prefers provider `circulatingSupply`; falls back to `marketCap/price` if both available.
    /// Pass a live price and/or explicit market cap to improve derivation.
    func effectiveCirculatingSupply(usingPrice price: Double? = nil, usingMarketCap cap: Double? = nil) -> Double? {
        if let cs = circulatingSupply, cs.isFinite, cs > 0 { return cs }
        let p = price ?? priceUsd
        guard let p, p.isFinite, p > 0 else { return nil }
        let mcap = cap ?? marketCap
        if let m = mcap, m.isFinite, m > 0 {
            let v = m / p
            if v.isFinite, v > 0 { return v }
        }
        return nil
    }

    /// Static set of common stable/pegged symbols (uppercased) for quick membership checks.
    /// This is the canonical source of truth for stablecoin detection across the app.
    static let stableSymbols: Set<String> = [
        // Major stablecoins
        "USDT","USDC","BUSD","DAI","TUSD","USDP","FDUSD","PYUSD","GUSD","FRAX","LUSD",
        // Additional USD-pegged stablecoins
        "USDE","USDF","USDG","USDT0","USYC","UST","USTC","USDX","USDD","USDJ","USDK",
        "CUSD","SUSD","HUSD","EUSD","OUSD","MUSD","ZUSD","RUSD","NUSD","DUSD",
        "USDQ","USDN","USDH","USDL","USDS","USD+","USDZ","USDB","USDA",
        // Staked/Synthetic USD variants (sUSD, eUSD patterns)
        "SUSDE","SUSDS","SUSD","EUSD","CRVUSD","MKUSD","GHUSD","DEUSD",
        "USDM","USDY","USDV","USDW","USDF","USDFL",
        // Ripple/XRP ecosystem stables
        "RLUSD",
        // Syrup/DeFi wrapped stables
        "SYRUPUSDC","SYRUPUSDT",
        // GHO and other DeFi stables
        "GHO","CRVUSD","ALUSD","DOLA","MIM","BEAN","FEI","RAI",
        // Other currency pegged
        "EURS","EURT","EUROC","AGEUR","CEUR","GBPT","XSGD","XIDR","BIDR","IDRT",
        "TRYB","BRLA","MXNT","JEUR","SEUR","PAXG","XAUT"
    ]
    
    /// Subset of stableSymbols for price overlay filtering (excludes some secondary stables).
    static let stableBases: Set<String> = [
        "USDT","USDC","BUSD","DAI","TUSD","USDP","FDUSD","PYUSD"
    ]

    /// True for common stable/pegged symbols.
    var isStable: Bool {
        Self.stableSymbols.contains(symbol.uppercased()) || Self.looksLikeStablecoin(symbol: symbol, price: priceUsd)
    }
    
    /// Static helper to check if a symbol is a stablecoin.
    static func isStableSymbol(_ symbol: String) -> Bool {
        stableSymbols.contains(symbol.uppercased())
    }
    
    /// Heuristic: detects likely stablecoins by symbol pattern and price
    static func looksLikeStablecoin(symbol: String, price: Double?) -> Bool {
        let upper = symbol.uppercased()
        
        // Check for common USD-related patterns in symbol
        let usdPatterns = ["USD", "USDC", "USDT", "USDE", "USDS"]
        let hasUsdPattern = usdPatterns.contains { upper.contains($0) }
        
        // Check for staked/synthetic USD patterns
        let stakedPatterns = ["SUSD", "EUSD", "CUSD", "MUSD", "AUSD", "BUSD"]
        let hasStakedPattern = stakedPatterns.contains { upper.hasPrefix($0) || upper.hasSuffix($0) }
        
        // If symbol contains USD pattern or staked pattern AND price is ~$1
        if (hasUsdPattern || hasStakedPattern) {
            if let p = price, p >= 0.95 && p <= 1.05 {
                return true
            }
        }
        
        // Also check for symbols ending in USD/USDC/USDT with price ~$1
        if (upper.hasSuffix("USD") || upper.hasSuffix("USDC") || upper.hasSuffix("USDT")) {
            if let p = price, p >= 0.95 && p <= 1.05 {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Wrapped/Pegged Coin Detection
    
    /// Prefixes that indicate a wrapped or bridged version of a canonical coin.
    /// These should be filtered out when the canonical coin already exists.
    static let wrappedPrefixes: [String] = [
        "binance-peg-", "wrapped-", "bridged-", "wormhole-", "multichain-",
        "axelar-", "celer-", "anyswap-", "synapse-", "stargate-"
    ]
    
    /// Known duplicate coin IDs that should be excluded when their canonical version exists.
    /// Format: duplicate ID -> canonical symbol (uppercased)
    static let knownDuplicateIDs: [String: String] = [
        "binance-peg-dogecoin": "DOGE",
        "binance-peg-bitcoin": "BTC",
        "binance-peg-ethereum": "ETH",
        "binance-peg-cardano": "ADA",
        "binance-peg-polkadot": "DOT",
        "binance-peg-litecoin": "LTC",
        "binance-peg-xrp": "XRP",
        "wrapped-bitcoin": "BTC",
        "wrapped-ether": "ETH",
        // Wrapped ETH variants
        "weth": "ETH",
        "wrapped-eeth": "ETH",
        "wrapped-steth": "ETH",
        "coinbase-wrapped-staked-eth": "ETH",
        "rocket-pool-eth": "ETH",
        "lido-staked-ether": "ETH",
        "frax-ether": "ETH",
        "mantle-staked-ether": "ETH",
        "renzo-restaked-eth": "ETH",
        "kelp-dao-restaked-eth": "ETH",
        "binance-staked-eth": "ETH",
        // Wrapped BTC variants
        "wbtc": "BTC",
        "tbtc": "BTC",
        "renbtc": "BTC",
        "sbtc": "BTC",
        "btcb": "BTC",
        "hbtc": "BTC"
    ]
    
    /// Wrapped symbol patterns (symbols that start with W followed by a known crypto symbol)
    static let wrappedSymbolPatterns: Set<String> = [
        "WETH", "WBTC", "WBNB", "WMATIC", "WAVAX", "WFTM", "WCRO", "WSOL",
        "WBETH", "WEETH", "WSTETH", "CBETH", "RETH", "STETH", "FRXETH", "METH",
        "TBTC", "RENBTC", "SBTC", "BTCB", "HBTC"
    ]
    
    /// Returns true if this coin ID represents a wrapped/pegged variant.
    static func isWrappedCoin(id: String) -> Bool {
        let lowerId = id.lowercased()
        // Check against known prefixes
        if wrappedPrefixes.contains(where: { lowerId.hasPrefix($0) }) {
            return true
        }
        // Check against known duplicate IDs
        return knownDuplicateIDs.keys.contains(lowerId)
    }
    
    /// Returns true if this symbol looks like a wrapped token
    static func isWrappedSymbol(_ symbol: String) -> Bool {
        wrappedSymbolPatterns.contains(symbol.uppercased())
    }
    
    /// Returns true if this coin is a wrapped/pegged variant.
    var isWrapped: Bool {
        Self.isWrappedCoin(id: id)
    }
    
    /// Returns the canonical symbol if this is a known wrapped coin, otherwise nil.
    static func canonicalSymbol(forWrappedId id: String) -> String? {
        knownDuplicateIDs[id.lowercased()]
    }

    /// Convenience copy-with updater to avoid reconstructing by hand.
    /// Pass new values to update fields; nil means "keep existing value".
    func updating(
        priceUsd: Double? = nil,
        marketCap: Double? = nil,
        totalVolume: Double? = nil,
        priceChangePercentage1hInCurrency: Double? = nil,
        priceChangePercentage24hInCurrency: Double? = nil,
        priceChangePercentage7dInCurrency: Double? = nil,
        sparklineIn7d: [Double]? = nil,
        marketCapRank: Int? = nil,
        maxSupply: Double? = nil,
        circulatingSupply: Double? = nil,
        totalSupply: Double? = nil
    ) -> MarketCoin {
        MarketCoin(
            id: self.id,
            symbol: self.symbol,
            name: self.name,
            imageUrl: self.imageUrl,
            priceUsd: priceUsd ?? self.priceUsd,
            marketCap: marketCap ?? self.marketCap,
            totalVolume: totalVolume ?? self.totalVolume,
            priceChangePercentage1hInCurrency: priceChangePercentage1hInCurrency ?? self.priceChangePercentage1hInCurrency,
            priceChangePercentage24hInCurrency: priceChangePercentage24hInCurrency ?? self.priceChangePercentage24hInCurrency,
            priceChangePercentage7dInCurrency: priceChangePercentage7dInCurrency ?? self.priceChangePercentage7dInCurrency,
            sparklineIn7d: sparklineIn7d ?? self.sparklineIn7d,
            marketCapRank: marketCapRank ?? self.marketCapRank,
            maxSupply: maxSupply ?? self.maxSupply,
            circulatingSupply: circulatingSupply ?? self.circulatingSupply,
            totalSupply: totalSupply ?? self.totalSupply
        )
    }
    
    /// Shorthand to update just the price.
    func withPrice(_ price: Double?) -> MarketCoin {
        updating(priceUsd: price)
    }
    
    /// Shorthand to update just the 24h percent change.
    func with24hChange(_ change: Double?) -> MarketCoin {
        updating(priceChangePercentage24hInCurrency: change)
    }
    
    /// Shorthand to update just the 1h percent change.
    func with1hChange(_ change: Double?) -> MarketCoin {
        updating(priceChangePercentage1hInCurrency: change)
    }
    
    /// Shorthand to update just the 7d percent change.
    func with7dChange(_ change: Double?) -> MarketCoin {
        updating(priceChangePercentage7dInCurrency: change)
    }
    
    /// Shorthand to update just the sparkline.
    func withSparkline(_ sparkline: [Double]) -> MarketCoin {
        updating(sparklineIn7d: sparkline)
    }
    
    /// Shorthand to update just the volume.
    func withVolume(_ volume: Double?) -> MarketCoin {
        updating(totalVolume: volume)
    }
    
    /// Explicit update allowing setting values to nil.
    /// Use this when you need to clear a field rather than keep the existing value.
    func withExplicit(
        priceUsd: Double?? = nil,
        priceChangePercentage1hInCurrency: Double?? = nil,
        priceChangePercentage24hInCurrency: Double?? = nil,
        priceChangePercentage7dInCurrency: Double?? = nil,
        totalVolume: Double?? = nil,
        sparklineIn7d: [Double]? = nil
    ) -> MarketCoin {
        MarketCoin(
            id: self.id,
            symbol: self.symbol,
            name: self.name,
            imageUrl: self.imageUrl,
            priceUsd: priceUsd ?? self.priceUsd,
            marketCap: self.marketCap,
            totalVolume: totalVolume ?? self.totalVolume,
            priceChangePercentage1hInCurrency: priceChangePercentage1hInCurrency ?? self.priceChangePercentage1hInCurrency,
            priceChangePercentage24hInCurrency: priceChangePercentage24hInCurrency ?? self.priceChangePercentage24hInCurrency,
            priceChangePercentage7dInCurrency: priceChangePercentage7dInCurrency ?? self.priceChangePercentage7dInCurrency,
            sparklineIn7d: sparklineIn7d ?? self.sparklineIn7d,
            marketCapRank: self.marketCapRank,
            maxSupply: self.maxSupply,
            circulatingSupply: self.circulatingSupply,
            totalSupply: self.totalSupply
        )
    }
}

