import Foundation
import Combine
import SwiftUI

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

// MARK: - ViewModel (data + caching)
@MainActor public final class HeatMapViewModel: ObservableObject {
    @Published public var lastUpdated: Date? = nil

    private static let cacheFile = "heatmap_tiles.json"
    
    /// Fallback sample data if network fails or times out
    private static let sampleTiles: [HeatMapTile] = [
        HeatMapTile(id: "BTC", symbol: "BTC", pctChange24h: 2.3, marketCap: 800_000_000_000, volume: 25_000_000_000),
        HeatMapTile(id: "ETH", symbol: "ETH", pctChange24h: -1.1, marketCap: 350_000_000_000, volume: 18_000_000_000),
        HeatMapTile(id: "SOL", symbol: "SOL", pctChange24h: 3.8, marketCap: 60_000_000_000, volume: 3_000_000_000),
        HeatMapTile(id: "ADA", symbol: "ADA", pctChange24h: 1.5, marketCap: 40_000_000_000, volume: 5_000_000_000),
        HeatMapTile(id: "DOT", symbol: "DOT", pctChange24h: -0.8, marketCap: 30_000_000_000, volume: 2_000_000_000),
        HeatMapTile(id: "DOGE", symbol: "DOGE", pctChange24h: 10.2, marketCap: 20_000_000_000, volume: 8_000_000_000)
    ]
    @Published public var tiles: [HeatMapTile] = []
    @Published public var isLoading: Bool = false
    @Published public var fetchError: Error? = nil
    private var cancellables = Set<AnyCancellable>()
    private var fetchCancellable: AnyCancellable? = nil
    private let decoder = JSONDecoder()
    
    // Gate how often we adopt new tiles to avoid noisy UI updates from frequent publishers
    private var lastAdoptedAt: Date = .distantPast
    private var minAdoptionInterval: TimeInterval = 45 // seconds (configurable)

    // Whether to follow live updates from MarketViewModel
    var followLiveUpdates: Bool = true

    // Optional auto-refresh timer (90s cadence) that can be toggled on/off
    private var timerCancellable: AnyCancellable? = nil

    private func canAdoptNow() -> Bool {
        Date().timeIntervalSince(lastAdoptedAt) >= minAdoptionInterval
    }

    private func adoptTiles(_ newTiles: [HeatMapTile], cache: Bool) {
        self.tiles = newTiles
        if cache { self.saveCache(newTiles) }
        self.lastAdoptedAt = Date()
    }

    // Public controls for configuration from the View
    func setMinAdoptionInterval(_ seconds: Int) {
        self.minAdoptionInterval = TimeInterval(max(1, seconds))
    }

    func setFollowLiveUpdates(_ enabled: Bool) {
        self.followLiveUpdates = enabled
    }

    func updateAutoRefreshTimer(enabled: Bool) {
        // Cancel any existing timer first
        timerCancellable?.cancel()
        timerCancellable = nil
        guard enabled else { return }
        // Recreate a 90s safety-net refresh
        timerCancellable = Timer.publish(every: 90, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.fetchData() }
    }

    private func saveCache(_ tiles: [HeatMapTile]) {
        let wrapper = HeatMapCache(savedAt: Date(), tiles: tiles)
        CacheManager.shared.save(wrapper, to: Self.cacheFile)
        self.lastUpdated = wrapper.savedAt
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
        let existingBySymbol: [String: HeatMapTile] = Dictionary(uniqueKeysWithValues: self.tiles.map { ($0.symbol.uppercased(), $0) })
        let mapped: [HeatMapTile] = coins.prefix(50).map { c in
            let change = finiteOrZero(c.priceChangePercentage24hInCurrency ?? c.changePercent24Hr)
            let cap = nonNegativeFinite(c.marketCap)
            let vol = nonNegativeFinite(c.totalVolume ?? c.volumeUsd24Hr)
            let prev = existingBySymbol[c.symbol.uppercased()]
            let ch1h: Double? = {
                if let v = c.priceChangePercentage1hInCurrency, v.isFinite { return v }
                if let p = prev?.pctChange1h, p.isFinite { return p }
                return nil
            }()
            let ch7d: Double? = {
                if let v = c.priceChangePercentage7dInCurrency, v.isFinite { return v }
                if let p = prev?.pctChange7d, p.isFinite { return p }
                return nil
            }()
            return HeatMapTile(
                id: c.symbol.uppercased(),
                symbol: c.symbol.uppercased(),
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
        return Array(bestBySymbol.values)
    }

    public init() {
        // Seed with cached or sample so UI isn't empty, then adopt live coins when available
        self.tiles = loadCache() ?? Self.sampleTiles

        // Observe MarketViewModel coins (preferred source) to build tiles
        MarketViewModel.shared.$allCoins
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] coins in
                guard let self = self else { return }
                guard self.followLiveUpdates else { return }
                guard !coins.isEmpty else { return }
                let mapped = self.mapCoinsToTiles(coins)
                guard !mapped.isEmpty else { return }
                guard self.canAdoptNow() else { return }
                self.adoptTiles(mapped, cache: true)
            }
            .store(in: &cancellables)

        // Kick a one-shot fetch as a fallback (if MVVM hasn't loaded yet)
        fetchData()

        // Periodic refresh as a safety net (can be toggled later)
        updateAutoRefreshTimer(enabled: true)
    }

    public func fetchData() {
        isLoading = true

        guard let url = URL(string:
            "https://api.coingecko.com/api/v3/coins/markets?" +
            "vs_currency=usd&order=market_cap_desc&per_page=50" +
            "&page=1&sparkline=false&price_change_percentage=1h,24h,7d"
        ) else {
            // Ensure loading state resets even if URL construction fails
            isLoading = false
            return
        }

        fetchCancellable?.cancel()

        var request = URLRequest(url: url)
        request.timeoutInterval = 6  // fail faster

        // Capture a local decoder so we don't touch `self` off the main actor.
        let decoder = self.decoder

        fetchCancellable = URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { output -> [HeatMapTile] in
                let tiles = try decoder.decode([HeatMapTile].self, from: output.data)
                if !HeatMapViewModel.isUsableNetworkTiles(tiles) {
                    throw URLError(.badServerResponse)
                }
                return tiles
            }
            .retry(1)
            // Mark successful network results so we can decide whether to cache
            .map { tiles in (tiles, true) }
            // Ensure subsequent operators run on the main actor before touching `self`
            .receive(on: DispatchQueue.main)
            // On any error, use cache first; if no cache, fall back to sample. Do not overwrite cache in this path.
            .catch { [weak self] error -> Just<([HeatMapTile], Bool)> in
                self?.fetchError = error
                let fallback: [HeatMapTile]
                if let cached = self?.loadCache(), !cached.isEmpty {
                    fallback = cached
                } else {
                    fallback = Self.sampleTiles
                }
                return Just((fallback, false))
            }
            .sink { [weak self] result in
                guard let self = self else { return }
                let (newTiles, shouldCache) = result
                self.adoptTiles(newTiles, cache: shouldCache)
                self.isLoading = false
            }
    }

    /// Exponentially weight marketCap for layout
    public func weights() -> [Double] {
        tiles.map { pow($0.marketCap, 0.7) }
    }

    private static func isUsableNetworkTiles(_ tiles: [HeatMapTile]) -> Bool {
        // Require a reasonable number of entries
        guard tiles.count >= 5 else { return false }
        // Require most entries to have a finite, non-identical 24h change and positive market cap
        let valid = tiles.filter { $0.marketCap > 0 && $0.pctChange24h.isFinite }
        guard valid.count >= max(3, tiles.count / 3) else { return false }
        // If almost all changes are zero (or nearly zero), consider it unusable
        let nearZero = valid.filter { abs($0.pctChange24h) < 0.001 }.count
        if nearZero >= valid.count - 1 { return false }
        // Check for variance: if all values are the same to 3 decimals, reject
        let rounded = Set(valid.map { Double((($0.pctChange24h * 1000).rounded()) / 1000) })
        if rounded.count <= 1 { return false }
        return true
    }
}
