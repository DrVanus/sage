import Foundation
import Combine
import SwiftUI

fileprivate struct RateLimitError: Error {}

// MARK: - Cache Wrapper
private struct HeatMapCache: Codable {
    let savedAt: Date
    let tiles: [HeatMapTile]
}

// MARK: - Tile Model
public struct HeatMapTile: Identifiable, Equatable, Codable {
    public let id: String
    public let symbol: String
    public let pctChange24h: Double
    public let marketCap: Double
    public let volume: Double
    public let pctChange1h: Double?
    public let pctChange7d: Double?

    private enum CodingKeys: String, CodingKey {
        case symbol
        case pctChange1h = "price_change_percentage_1h_in_currency"
        case pctChange24h = "price_change_percentage_24h_in_currency"
        case pctChange7d = "price_change_percentage_7d_in_currency"
        case marketCap    = "market_cap"
        case volume       = "total_volume"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawSymbol = try c.decode(String.self, forKey: .symbol)
        symbol = rawSymbol.uppercased()
        id = symbol
        pctChange1h = (try? c.decode(Double.self, forKey: .pctChange1h))
        pctChange24h = (try? c.decode(Double.self, forKey: .pctChange24h)) ?? 0
        pctChange7d = (try? c.decode(Double.self, forKey: .pctChange7d))
        marketCap    = (try? c.decode(Double.self, forKey: .marketCap))    ?? 0
        volume       = (try? c.decode(Double.self, forKey: .volume))       ?? 0
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(symbol, forKey: .symbol)
        try c.encodeIfPresent(pctChange1h, forKey: .pctChange1h)
        try c.encode(pctChange24h, forKey: .pctChange24h)
        try c.encodeIfPresent(pctChange7d, forKey: .pctChange7d)
        try c.encode(marketCap, forKey: .marketCap)
        try c.encode(volume, forKey: .volume)
    }

    public init(id: String, symbol: String, pctChange24h: Double, marketCap: Double, volume: Double, pctChange1h: Double? = nil, pctChange7d: Double? = nil) {
        self.id = id
        self.symbol = symbol
        self.pctChange24h = pctChange24h
        self.marketCap = marketCap
        self.volume = volume
        self.pctChange1h = pctChange1h
        self.pctChange7d = pctChange7d
    }
}

// MARK: - Numeric sanitizers (local to data layer)
fileprivate func finiteOrZero(_ v: Double?) -> Double {
    guard let x = v, x.isFinite else { return 0 }
    return x
}

fileprivate func nonNegativeFinite(_ v: Double?) -> Double {
    max(0, finiteOrZero(v))
}

fileprivate func clampChange(_ v: Double?, limit: Double) -> Double? {
    guard let x = v, x.isFinite else { return nil }
    return max(-limit, min(limit, x))
}

fileprivate func clampChangeNonNil(_ v: Double, limit: Double) -> Double {
    // Preserve NaN to indicate missing data (triggers colorForMissingData())
    guard v.isFinite else { return v }
    return max(-limit, min(limit, v))
}

/// Approximate market caps for major coins (as of Jan 2026) - used as fallback when API data unavailable
/// These ensure correct relative ordering even when data sources fail
private let fallbackMarketCaps: [String: Double] = [
    "BTC": 1_700_000_000_000,   // ~$1.7T
    "ETH": 400_000_000_000,     // ~$400B
    "XRP": 140_000_000_000,     // ~$140B
    "USDT": 130_000_000_000,    // ~$130B
    "SOL": 100_000_000_000,     // ~$100B
    "BNB": 90_000_000_000,      // ~$90B
    "USDC": 45_000_000_000,     // ~$45B
    "DOGE": 50_000_000_000,     // ~$50B
    "ADA": 35_000_000_000,      // ~$35B
    "TRX": 22_000_000_000,      // ~$22B
    "AVAX": 15_000_000_000,     // ~$15B
    "LINK": 14_000_000_000,     // ~$14B
    "SHIB": 13_000_000_000,     // ~$13B
    "DOT": 11_000_000_000,      // ~$11B
    "LTC": 8_000_000_000,       // ~$8B
    "HBAR": 12_000_000_000,     // ~$12B
    "SUI": 10_000_000_000,      // ~$10B
    "XLM": 14_000_000_000,      // ~$14B
    "ATOM": 4_000_000_000,      // ~$4B
    "UNI": 7_000_000_000,       // ~$7B
]

/// PERFORMANCE FIX v21: Fast version that uses pre-built O(1) dictionaries instead of linear scans.
/// Reduces bestCapForCoin from O(n) per call to O(1), saving ~62,500 iterations per heatmap update.
@MainActor fileprivate func bestCapForCoinFast(_ c: MarketCoin, liveCoinsLookup: [String: MarketCoin], allCoinsLookup: [String: MarketCoin]) -> Double {
    let sym = c.symbol.uppercased()
    
    // 1. Try the coin's own market cap
    if let cap = c.marketCap, cap.isFinite, cap > 0 {
        return cap
    }
    
    // 2. Try calculating from price * supply
    let bestPrice = MarketViewModel.shared.bestPrice(for: c.id) ?? c.priceUsd
    if let price = bestPrice, price.isFinite, price > 0 {
        if let circ = c.circulatingSupply, circ.isFinite, circ > 0 {
            let cap = price * circ
            if cap.isFinite, cap > 0 { return cap }
        }
        if let total = c.totalSupply, total.isFinite, total > 0 {
            let cap = price * total
            if cap.isFinite, cap > 0 { return cap }
        }
        if let maxSup = c.maxSupply, maxSup.isFinite, maxSup > 0 {
            let cap = price * maxSup
            if cap.isFinite, cap > 0 { return cap }
        }
    }
    
    // 3. O(1) lookup from LivePriceManager (was O(n) linear scan)
    if let fullCoin = liveCoinsLookup[sym] {
        if let cap = fullCoin.marketCap, cap.isFinite, cap > 0 {
            return cap
        }
        let fullBestPrice = MarketViewModel.shared.bestPrice(for: fullCoin.id) ?? fullCoin.priceUsd ?? bestPrice
        if let price = fullBestPrice, price.isFinite, price > 0 {
            if let circ = fullCoin.circulatingSupply, circ.isFinite, circ > 0 {
                let cap = price * circ
                if cap.isFinite, cap > 0 { return cap }
            }
        }
    }
    
    // 4. O(1) lookup from MarketViewModel (was O(n) linear scan)
    if let fullCoin = allCoinsLookup[sym] {
        if let cap = fullCoin.marketCap, cap.isFinite, cap > 0 {
            return cap
        }
        let fullBestPrice = MarketViewModel.shared.bestPrice(for: fullCoin.id) ?? fullCoin.priceUsd ?? bestPrice
        if let price = fullBestPrice, price.isFinite, price > 0 {
            if let circ = fullCoin.circulatingSupply, circ.isFinite, circ > 0 {
                let cap = price * circ
                if cap.isFinite, cap > 0 { return cap }
            }
        }
    }
    
    // 5. Use hardcoded fallback for major coins
    if let fallback = fallbackMarketCaps[sym] {
        return fallback
    }
    
    return 0
}

/// Best available market cap: prefer reported, else price * supply, else lookup, else fallback
/// This ensures correct ordering even when Binance data (which lacks market cap) is the source.
/// PRICE CONSISTENCY FIX: Uses bestPrice() for consistent pricing when calculating from price * supply
/// NOTE: This is the original O(n) version kept for backward compatibility. Prefer bestCapForCoinFast() in hot paths.
@MainActor fileprivate func bestCapForCoin(_ c: MarketCoin) -> Double {
    let sym = c.symbol.uppercased()
    
    // 1. Try the coin's own market cap
    if let cap = c.marketCap, cap.isFinite, cap > 0 {
        return cap
    }
    
    // 2. Try calculating from price * supply
    // PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing
    let bestPrice = MarketViewModel.shared.bestPrice(for: c.id) ?? c.priceUsd
    if let price = bestPrice, price.isFinite, price > 0 {
        if let circ = c.circulatingSupply, circ.isFinite, circ > 0 {
            let cap = price * circ
            if cap.isFinite, cap > 0 { return cap }
        }
        if let total = c.totalSupply, total.isFinite, total > 0 {
            let cap = price * total
            if cap.isFinite, cap > 0 { return cap }
        }
        if let maxSup = c.maxSupply, maxSup.isFinite, maxSup > 0 {
            let cap = price * maxSup
            if cap.isFinite, cap > 0 { return cap }
        }
    }
    
    // 3. Look up from LivePriceManager's currentCoinsList (has CoinGecko data with market cap)
    let liveCoins = LivePriceManager.shared.currentCoinsList
    if let fullCoin = liveCoins.first(where: { $0.symbol.uppercased() == sym }) {
        if let cap = fullCoin.marketCap, cap.isFinite, cap > 0 {
            return cap
        }
        // Use bestPrice for consistency
        let fullBestPrice = MarketViewModel.shared.bestPrice(for: fullCoin.id) ?? fullCoin.priceUsd ?? bestPrice
        if let price = fullBestPrice, price.isFinite, price > 0 {
            if let circ = fullCoin.circulatingSupply, circ.isFinite, circ > 0 {
                let cap = price * circ
                if cap.isFinite, cap > 0 { return cap }
            }
        }
    }
    
    // 4. Look up from MarketViewModel.shared.allCoins (alternative source)
    let allCoins = MarketViewModel.shared.allCoins
    if let fullCoin = allCoins.first(where: { $0.symbol.uppercased() == sym }) {
        if let cap = fullCoin.marketCap, cap.isFinite, cap > 0 {
            return cap
        }
        // Use bestPrice for consistency
        let fullBestPrice = MarketViewModel.shared.bestPrice(for: fullCoin.id) ?? fullCoin.priceUsd ?? bestPrice
        if let price = fullBestPrice, price.isFinite, price > 0 {
            if let circ = fullCoin.circulatingSupply, circ.isFinite, circ > 0 {
                let cap = price * circ
                if cap.isFinite, cap > 0 { return cap }
            }
        }
    }
    
    // 5. Use hardcoded fallback for major coins - ensures correct ordering even when all else fails
    if let fallback = fallbackMarketCaps[sym] {
        return fallback
    }
    
    return 0
}

fileprivate func isEffectivelyEqual(_ a: [HeatMapTile], _ b: [HeatMapTile]) -> Bool {
    // Build safe per-symbol maps (resolve duplicates by keeping higher market cap)
    let aBySymbol: [String: HeatMapTile] = Dictionary(
        a.map { ($0.symbol.uppercased(), $0) },
        uniquingKeysWith: { lhs, rhs in lhs.marketCap >= rhs.marketCap ? lhs : rhs }
    )
    let bBySymbol: [String: HeatMapTile] = Dictionary(
        b.map { ($0.symbol.uppercased(), $0) },
        uniquingKeysWith: { lhs, rhs in lhs.marketCap >= rhs.marketCap ? lhs : rhs }
    )

    // Quick checks based on deduped sets
    guard aBySymbol.count == bBySymbol.count else { return false }
    guard aBySymbol.keys == bBySymbol.keys else { return false }

    // DATA ACCURACY FIX: Lowered thresholds and minimum diff count for more responsive updates.
    // Previously required 15% of tiles to differ which caused stale 1H data when only a few coins changed.
    // Now uses lower thresholds and requires only 1 tile to differ for top coins.
    var significantDiffs = 0
    var topCoinDiff = false  // Track if any top 10 coin has a significant difference
    
    // Lower thresholds for more accurate data - user reports stale 1H values
    let threshold24h: Double = 0.5   // 0.5pp for 24h (was 1.2) - more responsive
    let threshold1h: Double = 0.3    // 0.3pp for 1h (was 0.8) - much more responsive for 1H
    let threshold7d: Double = 1.5    // 1.5pp for 7d (was 2.5)
    let thresholdCap: Double = 0.05  // 5% market cap change (was 8%)
    
    // Get top 10 coins by market cap for priority updates
    let topSymbols = Set(aBySymbol.values.sorted { $0.marketCap > $1.marketCap }.prefix(10).map { $0.symbol })
    
    for (sym, lhs) in aBySymbol {
        guard let rhs = bBySymbol[sym] else { return false }
        var tileIsDifferent = false
        
        // Check 24h change
        if abs(lhs.pctChange24h - rhs.pctChange24h) > threshold24h {
            tileIsDifferent = true
        }
        // Check 1h change - DATA ACCURACY FIX: Use lower threshold for 1H
        if let lhs1h = lhs.pctChange1h, let rhs1h = rhs.pctChange1h {
            if abs(lhs1h - rhs1h) > threshold1h {
                tileIsDifferent = true
            }
        }
        // Check 7d change
        if let lhs7d = lhs.pctChange7d, let rhs7d = rhs.pctChange7d {
            if abs(lhs7d - rhs7d) > threshold7d {
                tileIsDifferent = true
            }
        }
        // Check market cap
        let denom = max(1.0, max(lhs.marketCap, rhs.marketCap))
        if abs(lhs.marketCap - rhs.marketCap) / denom > thresholdCap {
            tileIsDifferent = true
        }
        
        if tileIsDifferent {
            significantDiffs += 1
            // DATA ACCURACY FIX: If a top coin differs, mark for immediate update
            if topSymbols.contains(sym) {
                topCoinDiff = true
            }
        }
    }
    
    // DATA ACCURACY FIX: If ANY top coin has significant change, allow update immediately
    // This ensures BTC, ETH etc. always show fresh data
    if topCoinDiff {
        return false  // Top coin differs - allow update
    }
    
    // For non-top coins, still require at least 1 tile to differ (was 15% minimum 2)
    if significantDiffs >= 1 {
        return false  // At least one tile differs - allow update
    }

    // Ensure top constituents (by cap) didn't change materially
    let topA = Set(aBySymbol.values.sorted { $0.marketCap > $1.marketCap }.prefix(10).map { $0.symbol })
    let topB = Set(bBySymbol.values.sorted { $0.marketCap > $1.marketCap }.prefix(10).map { $0.symbol })
    if topA != topB { return false }
    
    return true  // Tiles are effectively equal - skip update
}

// Helper to dedupe and keep highest market cap per symbol
fileprivate func dedupeBySymbolKeepBest(_ tiles: [HeatMapTile]) -> [HeatMapTile] {
    var bestBySymbol: [String: HeatMapTile] = [:]
    for t in tiles {
        if let existing = bestBySymbol[t.symbol], existing.marketCap >= t.marketCap {
            continue
        }
        bestBySymbol[t.symbol] = t
    }
    // CONSISTENCY FIX: Sort by market cap with symbol tiebreaker for deterministic order across devices
    return Array(bestBySymbol.values).sorted {
        if $0.marketCap == $1.marketCap {
            return $0.symbol < $1.symbol  // Deterministic tiebreaker
        }
        return $0.marketCap > $1.marketCap
    }
}

// MARK: - Percentage Derivation
// NOTE: All percentage derivation now delegates to LivePriceManager.bestChange*Percent() methods
// to ensure consistency across Watchlist, Market View, and Heat Map.
// The LivePriceManager uses Binance sparkline data as the primary source and applies
// consistent blending/clamping logic across all timeframes.

// MARK: - ViewModel (data + caching)
@MainActor public final class HeatMapViewModel: ObservableObject {
    @Published public var lastUpdated: Date? = nil

    private static let cacheFile = "heatmap_tiles.json"
    
    /// Throttle for clearAllSidecarCaches() to avoid excessive clearing
    private var lastSidecarCacheClear: Date = .distantPast
    private let sidecarCacheClearMinInterval: TimeInterval = 30.0
    
    // DATA CONSISTENCY FIX: Removed hardcoded sampleTiles that contained fake percentages.
    // Previously this caused different devices to show inconsistent data (e.g. BTC +2.3% vs real -0.6%)
    // when network requests failed or during app startup.
    // Now the app will show a loading state or use only cached real data - never fake percentages.
    @Published public var tiles: [HeatMapTile] = []
    @Published public var isLoading: Bool = false
    @Published public var fetchError: Error? = nil
    
    /// STABILITY FIX: True when heat map is still settling (first few seconds after init)
    /// Views should disable animations when this is true to prevent visual flickering
    @Published public var isSettling: Bool = true
    private var cancellables = Set<AnyCancellable>()
    private var fetchCancellable: AnyCancellable? = nil
    private let decoder = JSONDecoder()
    
    // Gate how often we adopt new tiles to avoid noisy UI updates from frequent publishers
    private var lastAdoptedAt: Date = .distantPast
    // PERFORMANCE FIX v21: Increased from 2s to 5s to reduce main-thread heatmap recomputations.
    // Logs show "Cache updated: 9 tiles" appearing every few seconds, each triggering 250-coin
    // processing. 5s is still fast enough for visual updates while halving CPU work.
    private var minAdoptionInterval: TimeInterval = 5 // seconds
    
    // CONSISTENCY FIX: Reduced startup interval to 1s for faster initial sync
    private let startupMinAdoptionInterval: TimeInterval = 1.0 // seconds - faster during warmup

    // Whether to follow live updates from MarketViewModel
    var followLiveUpdates: Bool = true

    // Optional auto-refresh timer (90s cadence) that can be toggled on/off
    private var timerCancellable: AnyCancellable? = nil

    // Adaptive backoff for REST fetches when rate-limited
    private var backoffUntil: Date = .distantPast
    private var backoffSeconds: TimeInterval = 0
    private let backoffBase: TimeInterval = 90 // start with 90s when rate-limited
    private let backoffMax: TimeInterval = 300 // cap backoff at 5 minutes

    // Cache freshness window - local cache is used as a fallback only.
    // Primary data source is Firestore real-time listener (marketData/heatmap).
    // Cache is used when:
    // 1. App launches before Firestore connects (brief moment)
    // 2. Firestore is unavailable (offline mode)
    // 3. Network errors prevent fresh data from being fetched
    private let cacheFreshnessWindow: TimeInterval = 60 * 5 // 5 minutes (reduced from 30)

    // STABILITY FIX: Reduced warmup to 3 seconds - just enough to accept first real data
    // Previously 12 seconds which caused too much flickering during startup
    private let warmupInterval: TimeInterval = 3 // seconds (reduced from 12)
    private var warmupUntil: Date = .distantPast
    
    // STABILITY FIX: Track if we've received our first "good" data set
    // Once we have good data, we become more conservative about updates
    private var hasReceivedGoodData: Bool = false

    // Clamp ranges for color mapping to keep gradients consistent (aligned with LivePriceManager)
    // Values match LivePriceManager to ensure consistency across all views
    private let clamp24h: Double = 50  // ±50% range for 24h (matches LivePriceManager)
    private let clamp1h: Double = 20   // ±20% range for 1h (matches LivePriceManager)
    private let clamp7d: Double = 80   // ±80% range for 7d (matches LivePriceManager)

    // Weighting & layout tuning for the heat map
    private let weightsExponent: Double = 0.98      // >1.0 favors large caps; <1.0 compresses range
    private let tailStartRank: Int = 12             // ranks >= 12 are considered tail
    private let tailCompression: Double = 0.40      // additional compression for tail items
    private let maxTailShare: Double = 0.35         // hard cap on tail share to prevent oversized 'Others'

    // STABILITY FIX: Reduced bootstrap window from 90s to 10s
    // Bootstrap is only for escaping an empty/tiny initial state, not for rapid updates
    private var bootstrapUntil: Date = .distantPast
    private let minViableCountBootstrap: Int = 16
    private func isBootstrapPhase() -> Bool { Date() < bootstrapUntil && !hasReceivedGoodData }

    private func canAdoptNow() -> Bool {
        let now = Date()
        let timeSinceLastAdopt = now.timeIntervalSince(lastAdoptedAt)
        
        // STABILITY FIX: Always enforce minimum interval to prevent flickering
        // Even during warmup, don't adopt faster than every 2 seconds
        if timeSinceLastAdopt < startupMinAdoptionInterval {
            return false
        }
        
        // If we currently have nothing, adopt immediately (first data)
        if tiles.isEmpty { return true }
        
        // During warm-up (first 3 seconds), allow faster adoption but still respect minimum
        if now < warmupUntil { return true }
        
        // During bootstrap (before we have good data), allow adoption if we need more tiles
        if isBootstrapPhase() && tiles.count < minViableCountBootstrap { return true }
        
        // STABILITY FIX: Once we have good data, be conservative about updates
        // Respect the full throttle interval
        return timeSinceLastAdopt >= minAdoptionInterval
    }

    // If the incoming tile set differs significantly (count or top constituents), bypass throttle.
    // STABILITY FIX: Made this more conservative to reduce flickering
    private func shouldForceAdopt(_ newTiles: [HeatMapTile]) -> Bool {
        // Never force adopt if we just adopted (prevent rapid flickering)
        let timeSinceLastAdopt = Date().timeIntervalSince(lastAdoptedAt)
        if timeSinceLastAdopt < startupMinAdoptionInterval {
            return false
        }
        
        // If we have nothing, always adopt
        if tiles.isEmpty { return true }
        
        // During bootstrap, only force adopt if we're escaping a tiny set
        if isBootstrapPhase() && !hasReceivedGoodData {
            if newTiles.count >= minViableCountBootstrap && tiles.count < minViableCountBootstrap { 
                return true 
            }
        }
        
        // STABILITY FIX: Reduced sensitivity - only force adopt for major changes
        // Previously triggered on 5 tile difference or 15% change, now requires 20% or 10 tiles
        let diff = abs(newTiles.count - tiles.count)
        if diff >= 10 || Double(diff) / Double(max(1, tiles.count)) >= 0.20 { return true }
        
        // STABILITY FIX: Only force adopt if top 5 (not 12) symbols changed significantly
        let currentTop = Set(tiles.prefix(5).map { $0.symbol })
        let newTop = Set(newTiles.prefix(5).map { $0.symbol })
        let delta = currentTop.symmetricDifference(newTop).count
        return delta >= 3  // Major reshuffle of top 5
    }

    private func sanitizeTiles(_ tiles: [HeatMapTile]) -> [HeatMapTile] {
        tiles.map { t in
            let c1h: Double? = clampChange((t.pctChange1h?.isFinite == true) ? t.pctChange1h : nil, limit: clamp1h)
            let c24: Double  = clampChangeNonNil(t.pctChange24h.isFinite ? t.pctChange24h : 0, limit: clamp24h)
            let c7d: Double? = clampChange((t.pctChange7d?.isFinite == true) ? t.pctChange7d : nil, limit: clamp7d)
            let cap = max(0, t.marketCap.isFinite ? t.marketCap : 0)
            let vol = max(0, t.volume.isFinite ? t.volume : 0)
            return HeatMapTile(
                id: t.id,
                symbol: t.symbol,
                pctChange24h: c24,
                marketCap: cap,
                volume: vol,
                pctChange1h: c1h,
                pctChange7d: c7d
            )
        }
    }

    private func adoptTiles(_ newTiles: [HeatMapTile], cache: Bool) {
        var cleaned = dedupeBySymbolKeepBest(sanitizeTiles(newTiles))

        // Skip adoption if the incoming set is effectively the same as current
        if !self.tiles.isEmpty && isEffectivelyEqual(self.tiles, cleaned) {
            return
        }

        // If too many coins arrived with tiny caps (likely a degraded frame), repair using cache caps.
        let tinyCapThreshold = 1.0
        let tinyCount = cleaned.filter { $0.marketCap <= tinyCapThreshold }.count
        if tinyCount >= max(20, cleaned.count / 3), let cached = self.loadCache(), !cached.isEmpty {
            let cachedBySymbol: [String: HeatMapTile] = Dictionary(
                sanitizeTiles(cached).map { ($0.symbol, $0) },
                uniquingKeysWith: { lhs, rhs in lhs.marketCap >= rhs.marketCap ? lhs : rhs }
            )
            cleaned = cleaned.map { t in
                guard t.marketCap <= tinyCapThreshold, let c = cachedBySymbol[t.symbol], c.marketCap > tinyCapThreshold else { return t }
                // Keep latest change percentages but restore a reasonable cap/volume from cache.
                return HeatMapTile(
                    id: t.id,
                    symbol: t.symbol,
                    pctChange24h: t.pctChange24h,
                    marketCap: c.marketCap,
                    volume: max(t.volume, c.volume),
                    pctChange1h: t.pctChange1h ?? c.pctChange1h,
                    pctChange7d: t.pctChange7d ?? c.pctChange7d
                )
            }
        }

        // Prefer healthy data when available
        let healthy = HeatMapViewModel.isUsableNetworkTiles(cleaned) && HeatMapViewModel.hasHealthyShortFrames(cleaned)
        if healthy {
            self.tiles = cleaned
            self.lastUpdated = Date()
            if cache { self.saveCache(cleaned) }
            self.lastAdoptedAt = Date()
            // STABILITY FIX: Mark that we have good data - become more conservative about future updates
            if cleaned.count >= minViableCountBootstrap {
                self.hasReceivedGoodData = true
            }
            return
        }

        // Best-effort path: still adopt something so the UI never appears "broken".
        if !cleaned.isEmpty {
            // Start with network tiles and blend with cache/sample to reach a reasonable count.
            var blendedBySymbol: [String: HeatMapTile] = Dictionary(
                cleaned.map { ($0.symbol, $0) },
                uniquingKeysWith: { lhs, rhs in lhs.marketCap >= rhs.marketCap ? lhs : rhs }
            )

            func merge(_ extras: [HeatMapTile]) {
                for t in extras {
                    if blendedBySymbol[t.symbol] == nil {
                        blendedBySymbol[t.symbol] = t
                    }
                }
            }

            // DATA CONSISTENCY FIX: Only blend with cached data, never fake sample data
            // This ensures all devices show real market data or nothing at all
            if blendedBySymbol.count < 20 {
                if let cached = self.loadCache(), !cached.isEmpty {
                    merge(sanitizeTiles(cached))
                }
                // No fallback to fake data - better to show fewer real tiles than fake percentages
            }

            self.tiles = Array(blendedBySymbol.values)
            self.lastUpdated = Date()
            self.lastAdoptedAt = Date()
            // Do not cache best-effort sets
            return
        }

        // DATA CONSISTENCY FIX: Only fall back to cached real data, never fake sample data
        // If network provided nothing and cache is empty, keep tiles empty and show loading state
        if self.tiles.isEmpty {
            if let cached = self.loadCache(), !cached.isEmpty {
                self.tiles = dedupeBySymbolKeepBest(sanitizeTiles(cached))
                self.lastUpdated = Date()
            }
            // No fallback to fake data - isLoading will indicate data is being fetched
        }
    }

    // Public controls for configuration from the View
    func setMinAdoptionInterval(_ seconds: Int) {
        self.minAdoptionInterval = TimeInterval(max(1, seconds))
        // STABILITY FIX: Only brief warmup, no long bootstrap
        self.warmupUntil = Date().addingTimeInterval(self.warmupInterval)
    }

    func setFollowLiveUpdates(_ enabled: Bool) {
        self.followLiveUpdates = enabled
        // STABILITY FIX: Only brief warmup, no long bootstrap
        self.warmupUntil = Date().addingTimeInterval(self.warmupInterval)
    }

    func updateAutoRefreshTimer(enabled: Bool) {
        // Cancel any existing timer first
        timerCancellable?.cancel()
        timerCancellable = nil
        guard enabled else { return }
        // PERFORMANCE FIX: Increased refresh interval to 120s to reduce update frequency
        // PERFORMANCE FIX v19: Changed .common to .default so timer pauses during scroll
        if #available(iOS 15.0, macOS 12.0, *) {
            timerCancellable = Timer.publish(every: 120, tolerance: 10, on: .main, in: .default)
                .autoconnect()
                .sink { [weak self] _ in
                    // PERFORMANCE FIX: Skip fetch during scroll
                    guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                    self?.fetchData()
                }
        } else {
            timerCancellable = Timer.publish(every: 120, on: .main, in: .default)
                .autoconnect()
                .sink { [weak self] _ in
                    // PERFORMANCE FIX: Skip fetch during scroll
                    guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                    self?.fetchData()
                }
        }
    }

    private func saveCache(_ tiles: [HeatMapTile]) {
        let wrapper = HeatMapCache(savedAt: Date(), tiles: dedupeBySymbolKeepBest(sanitizeTiles(tiles)))
        CacheManager.shared.save(wrapper, to: Self.cacheFile)
        self.lastUpdated = wrapper.savedAt
    }

    /// Load cache only if it is recent enough to be trusted for initial display.
    private func loadFreshCache(maxAge: TimeInterval? = nil) -> [HeatMapTile]? {
        let maxAgeSec = maxAge ?? cacheFreshnessWindow
        if let wrapper: HeatMapCache = CacheManager.shared.load(HeatMapCache.self, from: Self.cacheFile) {
            // Record timestamp regardless for attribution
            self.lastUpdated = wrapper.savedAt
            // Only adopt if the cache is still fresh and looks usable
            let age = Date().timeIntervalSince(wrapper.savedAt)
            if age <= maxAgeSec {
                return wrapper.tiles
            }
        }
        return nil
    }

    private func loadCache() -> [HeatMapTile]? {
        if let wrapper: HeatMapCache = CacheManager.shared.load(HeatMapCache.self, from: Self.cacheFile) {
            self.lastUpdated = wrapper.savedAt
            return wrapper.tiles
        }
        if let legacy: [HeatMapTile] = CacheManager.shared.load([HeatMapTile].self, from: Self.cacheFile) {
            return legacy
        }
        return nil
    }

    private func mapCoinsToTiles(_ coins: [MarketCoin]) -> [HeatMapTile] {
        let existingBySymbol: [String: HeatMapTile] = Dictionary(
            self.tiles.map { ($0.symbol.uppercased(), $0) },
            uniquingKeysWith: { lhs, rhs in
                if lhs.marketCap != rhs.marketCap { return lhs.marketCap > rhs.marketCap ? lhs : rhs }
                return rhs // prefer most recent when equal
            }
        )
        
        // PERFORMANCE FIX v21: Pre-build O(1) lookup dictionaries for bestCapForCoin().
        // Previously, bestCapForCoin() did linear scans (O(n)) over LivePriceManager.currentCoinsList
        // and MarketViewModel.allCoins for EACH of 250 coins = O(n^2) total, ~62,500 iterations.
        // Building dictionaries once reduces this to O(n) total.
        let liveCoinsLookup: [String: MarketCoin] = Dictionary(
            LivePriceManager.shared.currentCoinsList.map { ($0.symbol.uppercased(), $0) },
            uniquingKeysWith: { lhs, _ in lhs }
        )
        let allCoinsLookup: [String: MarketCoin] = Dictionary(
            MarketViewModel.shared.allCoins.map { ($0.symbol.uppercased(), $0) },
            uniquingKeysWith: { lhs, _ in lhs }
        )
        
        // Sort by best available market cap (includes MarketViewModel lookup for Binance-sourced coins)
        let sortedByCap = coins.sorted { bestCapForCoinFast($0, liveCoinsLookup: liveCoinsLookup, allCoinsLookup: allCoinsLookup) > bestCapForCoinFast($1, liveCoinsLookup: liveCoinsLookup, allCoinsLookup: allCoinsLookup) }
        
        let top = Array(sortedByCap.prefix(250))
        let mapped: [HeatMapTile] = top.map { c in
            let sym = c.symbol.uppercased()
            let prev = existingBySymbol[sym]
            
            // Use LivePriceManager as the single source of truth for all percentages
            // This ensures consistency with Watchlist, Market View, and CoinRowView
            // LivePriceManager handles:
            // 1. Binance sparkline derivation (primary, freshest data)
            // 2. Provider data blending
            // 3. Consistent clamping for stablecoins
            //
            // CONSISTENCY FIX: Removed hysteresis filtering to ensure Heat Map shows
            // identical values to Watchlist. Both views now use raw LivePriceManager values.
            
            // 24h change - from LivePriceManager (raw, no smoothing)
            let best24h = LivePriceManager.shared.bestChange24hPercent(for: c)
            let change24h: Double = best24h ?? .nan  // NaN indicates missing data
            let change = clampChangeNonNil(change24h, limit: clamp24h)
            
            // 1h change - from LivePriceManager (raw, no smoothing)
            let best1h = LivePriceManager.shared.bestChange1hPercent(for: c)
            let ch1h: Double? = clampChange(best1h, limit: clamp1h)
            
            // 7d change - from LivePriceManager (raw, no smoothing)
            let best7d = LivePriceManager.shared.bestChange7dPercent(for: c)
            let ch7d: Double? = clampChange(best7d, limit: clamp7d)

            // Use bestCapForCoinFast which calculates from price * supply when direct cap unavailable
            // This ensures BTC/ETH are correctly ordered even when Binance (no market cap) is the source
            let capPrimary = bestCapForCoinFast(c, liveCoinsLookup: liveCoinsLookup, allCoinsLookup: allCoinsLookup)
            let prevCap = nonNegativeFinite(prev?.marketCap)
            let volRaw = nonNegativeFinite(c.totalVolume ?? c.volumeUsd24Hr)
            let volProxy = volRaw * 8
            
            // Priority: calculated best cap -> previous cached cap -> volume proxy (last resort)
            let cap: Double
            if capPrimary > 0 {
                cap = capPrimary
            } else if prevCap > 0 {
                cap = prevCap
            } else {
                cap = max(1, volProxy)
            }
            let vol = max(1, volRaw)

            return HeatMapTile(
                id: sym,
                symbol: sym,
                pctChange24h: change,
                marketCap: cap,
                volume: vol,
                pctChange1h: ch1h,
                pctChange7d: ch7d
            )
        }.filter { $0.marketCap > 0 }

        // Deduplicate by symbol, keep the highest market cap entry
        var bestBySymbol: [String: HeatMapTile] = [:]
        for t in mapped {
            if let existing = bestBySymbol[t.symbol], existing.marketCap >= t.marketCap {
                continue
            }
            bestBySymbol[t.symbol] = t
        }
        
        // CRITICAL: Re-sort by market cap after deduplication to maintain proper order
        // (Dictionary iteration order is not guaranteed)
        // CONSISTENCY FIX: Add secondary sort by symbol to ensure deterministic ordering across devices
        return Array(bestBySymbol.values).sorted { 
            if $0.marketCap == $1.marketCap {
                return $0.symbol < $1.symbol  // Deterministic tiebreaker
            }
            return $0.marketCap > $1.marketCap 
        }
    }

    public init() {
        // PERFORMANCE FIX v18: Defer cache loading to after first frame renders.
        // Previously this loaded and processed heatmap cache synchronously during
        // HomeViewModel.init() → CryptoSageAIApp.init(), blocking the splash screen.
        // The heatmap section is far down the home screen scroll.
        self.tiles = []
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // Small yield to let splash render
            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms
            
            // COLD START FIX: First try to seed from LivePriceManager's current coins.
            // HeatMapViewModel is lazily initialized (when user scrolls to it), so by then
            // LivePriceManager has already emitted through coinSubject (PassthroughSubject).
            // Since PassthroughSubject doesn't replay, late subscribers miss the initial data.
            // Seeding from currentCoinsList ensures immediate tile display.
            let liveCoins = LivePriceManager.shared.currentCoinsList
            if !liveCoins.isEmpty {
                let mapped = self.mapCoinsToTiles(liveCoins)
                if !mapped.isEmpty {
                    self.adoptTiles(mapped, cache: true)
                    return // Got good live data, skip cache
                }
            }
            
            if let fresh = self.loadFreshCache() {
                let cachedTiles = dedupeBySymbolKeepBest(self.sanitizeTiles(fresh))
                self.tiles = cachedTiles
                if cachedTiles.count >= self.minViableCountBootstrap {
                    self.hasReceivedGoodData = true
                }
            } else if let stale = self.loadCache(), !stale.isEmpty {
                let cachedTiles = dedupeBySymbolKeepBest(self.sanitizeTiles(stale))
                self.tiles = cachedTiles
                if cachedTiles.count >= self.minViableCountBootstrap {
                    self.hasReceivedGoodData = true
                }
            }
        }

        // STABILITY FIX: Short warm-up period (3 seconds) to accept first real data
        self.warmupUntil = Date().addingTimeInterval(self.warmupInterval)
        // STABILITY FIX: Reduced bootstrap from 90s to 10s - only for escaping empty state
        self.bootstrapUntil = Date().addingTimeInterval(10)

        // SINGLE SOURCE OF TRUTH: Use only LivePriceManager.publisher
        // This eliminates race conditions between two publishers that caused random color switching.
        // 
        // LivePriceManager data sources (in priority order):
        // 1. Firestore real-time listener (marketData/heatmap) - ensures all devices see identical data
        //    - Backend syncs Binance data to Firestore every 1 minute
        //    - iOS uses addSnapshotListener for instant cross-device updates
        // 2. HTTP polling (Binance/CoinGecko via Firebase proxy) - fallback when Firestore unavailable
        // 3. Local cache - used only during app launch before network connects
        //
        // STABILITY FIX: Use slowPublisher (2s throttle) to prevent rapid visual changes
        // This gives time for multiple data sources to settle before updating the UI
        // PERFORMANCE FIX: Using pre-throttled publisher reduces processing overhead
        LivePriceManager.shared.slowPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coins in
                guard let self = self else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    guard self.followLiveUpdates else { return }
                    guard !coins.isEmpty else { return }
                    
                    // PERFORMANCE FIX: Skip tile processing during scroll to prevent main thread blocking
                    // The tiles will be refreshed when scroll ends
                    if ScrollStateManager.shared.shouldBlockHeavyOperation() {
                        return
                    }
                    
                    let mapped = self.mapCoinsToTiles(coins)
                    guard !mapped.isEmpty else {
                        // DATA CONSISTENCY FIX: Only use cached real data, never fake sample data
                        // If we have no mapped tiles and no cache, keep loading state active
                        if self.tiles.isEmpty {
                            if let cached = self.loadCache(), !cached.isEmpty {
                                self.adoptTiles(cached, cache: false)
                            }
                            // No fallback to fake data - better to show empty/loading than inconsistent fake percentages
                        }
                        return
                    }
                    if !(self.shouldForceAdopt(mapped) || self.canAdoptNow()) { return }
                    self.adoptTiles(mapped, cache: true)
                }
            }
            .store(in: &cancellables)

        // Kick a one-shot refresh via LivePriceManager (Binance data)
        // This triggers the existing subscriptions above to receive fresh data
        fetchData()

        // Auto-refresh timer supplements Firestore real-time updates
        // - Primary: Firestore listener provides instant cross-device sync
        // - Secondary: Timer polls Binance/CoinGecko if Firestore is slow or unavailable
        updateAutoRefreshTimer(enabled: true)
        
        // STABILITY FIX: Mark settling period done after warmup completes
        // This allows views to re-enable animations after the initial data load
        Task { @MainActor in
            // Wait for warmup period plus a bit extra for data to settle
            try? await Task.sleep(nanoseconds: UInt64((warmupInterval + 2) * 1_000_000_000))
            self.isSettling = false
        }
    }

    public func forceRefresh(reason: String? = nil, clearHysteresis: Bool = false) {
        // STABILITY FIX: Short warmup window for accepting next data
        self.warmupUntil = Date().addingTimeInterval(self.warmupInterval)
        // STABILITY FIX: Only use bootstrap if we need to escape empty state
        if tiles.isEmpty || tiles.count < minViableCountBootstrap {
            self.bootstrapUntil = Date().addingTimeInterval(10)
        }
        
        // DATA ACCURACY FIX: Optionally clear existing tiles to bypass hysteresis
        // This forces fresh data to be adopted without comparison to potentially stale values
        if clearHysteresis {
            // Keep structure but invalidate percentages so hysteresis doesn't prevent updates
            self.tiles = []
            self.hasReceivedGoodData = false
        }
        
        // Trigger LivePriceManager to poll fresh Binance data instead of using CoinGecko
        self.triggerLivePriceRefresh()
    }

    /// Triggers a refresh by requesting LivePriceManager to poll fresh data.
    /// HeatMap now relies entirely on LivePriceManager/MarketViewModel subscriptions (Binance data).
    /// NO LONGER USES COINGECKO DIRECTLY.
    public func fetchData() {
        triggerLivePriceRefresh()
    }
    
    /// Internal method to trigger LivePriceManager refresh.
    /// This ensures the HeatMap gets fresh Binance-sourced data through the existing subscriptions.
    private func triggerLivePriceRefresh() {
        isLoading = true
        
        // Throttled clear of staleness tracking - only if at least 30s since last clear
        let now = Date()
        if now.timeIntervalSince(lastSidecarCacheClear) >= sidecarCacheClearMinInterval {
            LivePriceManager.shared.clearAllSidecarCaches()
            lastSidecarCacheClear = now
        }
        
        // Trigger a poll of market data which will emit to our subscription
        Task {
            // Use the existing LivePriceManager polling mechanism which now uses Binance
            await LivePriceManager.shared.pollMarketCoinsPublic()
            
            // After polling, the data will flow through our existing subscriptions
            // (MarketViewModel.$allCoins and LivePriceManager.publisher)
            await MainActor.run {
                // DATA CONSISTENCY FIX: Only use cached real data as fallback, never fake sample data
                // If we still have no tiles after polling and no cache, keep isLoading true
                // to indicate we're still waiting for real data from Firestore/API
                if self.tiles.isEmpty {
                    if let cached = self.loadCache(), !cached.isEmpty {
                        self.adoptTiles(cached, cache: false)
                        self.isLoading = false
                    }
                    // Keep isLoading = true if no cache available - will be cleared when Firestore data arrives
                } else {
                    self.isLoading = false
                }
            }
        }
    }

    /// Exponentially weight marketCap for layout
    public func weights() -> [Double] {
        // Rank coins by market cap (desc) but return weights in the original order
        let rankedSymbols: [String] = tiles.sorted { $0.marketCap > $1.marketCap }.map { $0.symbol }
        var rankBySymbol: [String: Int] = [:]
        for (idx, sym) in rankedSymbols.enumerated() { rankBySymbol[sym] = idx }

        struct Item { let rank: Int; let weight: Double }

        // First pass: base weights with tail compression
        let prelim: [Item] = tiles.map { t in
            let rank = rankBySymbol[t.symbol] ?? Int.max
            let base = pow(max(t.marketCap, 1), weightsExponent)
            let factor = (rank >= tailStartRank) ? tailCompression : 1.0
            let w = max(1, base * factor)
            return Item(rank: rank, weight: w)
        }

        // If the tail dominates, cap the combined tail share to `maxTailShare`.
        let total = prelim.reduce(0.0) { $0 + $1.weight }
        guard total > 0 else { return Array(repeating: 1, count: tiles.count) }
        let tailWeight = prelim.filter { $0.rank >= tailStartRank }.reduce(0.0) { $0 + $1.weight }

        let scaled: [Item]
        if tailWeight > 0, (tailWeight / total) > maxTailShare {
            let allowedTail = maxTailShare * total
            let scale = allowedTail / tailWeight
            scaled = prelim.map { item in
                if item.rank >= tailStartRank {
                    return Item(rank: item.rank, weight: max(1, item.weight * scale))
                } else {
                    return item
                }
            }
        } else {
            scaled = prelim
        }

        return scaled.map { $0.weight }
    }

    private static func isUsableNetworkTiles(_ tiles: [HeatMapTile]) -> Bool {
        // Minimal sanity: need some entries and some with usable 24h change and positive cap.
        guard tiles.count >= 5 else { return false }
        let valid = tiles.filter { $0.marketCap > 0 && $0.pctChange24h.isFinite }
        // Require at least 10% of the set (or 5, whichever is larger) to be valid.
        return valid.count >= max(5, tiles.count / 10)
    }

    /// Ensure short timeframes (1h/24h) have enough coverage and variance so we don't show bad-data windows.
    private static func hasHealthyShortFrames(_ tiles: [HeatMapTile]) -> Bool {
        // Lenient gating to avoid "broken" state: only require some 24h coverage in the top slice.
        let top = tiles.sorted { $0.marketCap > $1.marketCap }
        let slice = Array(top.prefix(max(20, tiles.count / 2)))
        let vals24h = slice.map { $0.pctChange24h }.filter { $0.isFinite }
        // Need a modest amount of coverage; 1h is optional and no variance requirement.
        return vals24h.count >= max(5, slice.count / 5)
    }
}

