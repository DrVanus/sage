import SwiftUI
import Combine
import UIKit

// MARK: - Relative updated string (local to this module)
private func relativeUpdatedString(since date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "" }
    let minutes = seconds / 60
    if minutes < 60 { return "Updated \(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "Updated \(hours)h ago" }
    let days = hours / 24
    return "Updated \(days)d ago"
}

// Local change computation - delegates to shared implementation for consistency
// Each timeframe is independent (a coin can be +10% over 24h but -5% in the last hour)
private func changeLocal(for tile: HeatMapTile, tf: HeatMapTimeframe) -> Double {
    return HeatMapSharedLib.change(for: tile, tf: tf)
}

// Helper to detect synthetic "Others" tiles (supports suffixed IDs like "Others-87")
private func isOthersID(_ id: String) -> Bool { id.hasPrefix("Others") }

#if DEBUG
private enum HeatMapDebugLog {
    static var lastAt: Date = .distantPast
    static var lastKey: String = ""
    static let minInterval: TimeInterval = 60.0 // PERFORMANCE: Reduced to once per minute max
}
#endif

// MARK: - Market Heat Map Section (public)
// Note: HeatMapInfoBar has been extracted to HeatMapInfoBar.swift
public struct MarketHeatMapSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = HeatMapViewModel()
    // PERFORMANCE FIX v19: Removed @ObservedObject for MarketViewModel.
    // It was declared but NEVER used in this view's body, yet caused the entire
    // heat map section to re-render on every MarketViewModel property change (25+ publishers).
    @State private var selected: HeatMapTile? = nil

    private enum Layout: String, CaseIterable, Identifiable { case treemap, grid, bar; var id: String { rawValue } }
    private enum ScaleMode: String, CaseIterable, Identifiable { case perTimeframe, global, locked; var id: String { rawValue } }

    // Height helper to keep consistent layout across devices
    // Adaptive for treemap: scales height based on coin count to prevent layout breakage
    private func mapHeight(for layout: Layout, coinCount: Int? = nil) -> CGFloat {
        switch layout {
        case .treemap:
            // Adaptive height based on coin count - start scaling earlier for better layouts
            // LAYOUT FIX: Increased heights for 15+ coins to give more room for balanced layouts
            let count = coinCount ?? clampedTopN
            if count <= 10 { return 220 }
            else if count <= 14 { return 250 }
            else if count <= 18 { return 280 }
            else if count <= 22 { return 300 }
            else { return 320 }
        case .grid:
            return 184
        case .bar:
            return 168
        }
    }

    @AppStorage("heatmap.layout") private var layoutRaw: String = Layout.treemap.rawValue
    private var selectedLayout: Layout { get { Layout(rawValue: layoutRaw) ?? .treemap } set { layoutRaw = newValue.rawValue } }

    @AppStorage("heatmap.timeframe") private var timeframeRaw: String = HeatMapTimeframe.day1.rawValue
    private var timeframe: HeatMapTimeframe { get { HeatMapTimeframe(rawValue: timeframeRaw) ?? .day1 } set { timeframeRaw = newValue.rawValue } }

    @AppStorage("heatmap.filterStables") private var filterStables: Bool = true
    @AppStorage("heatmap.includeOthers") private var includeOthers: Bool = true
    @AppStorage("heatmap.weightByVolume") private var weightByVolume: Bool = false

    // Inserted @AppStorage properties and computed property
    @AppStorage("heatmap.topN") private var topN: Int = 8

    @AppStorage("heatmap.strongBorders") private var strongBorders: Bool = false
    @AppStorage("heatmap.labelDensity") private var labelDensityRaw: String = LabelDensity.normal.rawValue
    private var labelDensity: LabelDensity { get { LabelDensity(rawValue: labelDensityRaw) ?? .normal } set { labelDensityRaw = newValue.rawValue } }

    @AppStorage("heatmap.showMoverBadges") private var showMoverBadges: Bool = false
    @AppStorage("heatmap.moverBadgeCount") private var moverBadgeCount: Int = 2

    @State private var focusTile: HeatMapTile? = nil

    @AppStorage("heatmap.normalizeByBTC") private var normalizeByBTC: Bool = false
    @AppStorage("heatmap.showValues") private var showValues: Bool = false
    @AppStorage("heatmap.autoHideInfoBar") private var autoHideInfoBar: Bool = true

    @AppStorage("heatmap.scaleMode") private var scaleModeRaw: String = ScaleMode.perTimeframe.rawValue
    // Keep defaults aligned with HeatMapSharedLib.bound(for: .day1) to match legend math.
    @AppStorage("heatmap.globalBound") private var globalBound: Double = HeatMapSharedLib.bound(for: .day1)
    @AppStorage("heatmap.lockedBound") private var lockedBound: Double = HeatMapSharedLib.bound(for: .day1)

    @AppStorage("heatmap.whiteLabels") private var whiteLabelsOnly: Bool = true

    @AppStorage("heatmap.pinBTC") private var pinBTC: Bool = true

    @AppStorage("heatmap.weightingCurve") private var weightingCurveRaw: String = WeightingCurve.balanced.rawValue
    private var weightingCurve: WeightingCurve { get { WeightingCurve(rawValue: weightingCurveRaw) ?? .balanced } set { weightingCurveRaw = newValue.rawValue } }

    @AppStorage("heatmap.autoRefresh") private var autoRefreshEnabled: Bool = true
    @AppStorage("heatmap.minUpdateSeconds") private var minUpdateSeconds: Int = 60
    @AppStorage("heatmap.followLive") private var followLiveUpdates: Bool = true

    @AppStorage("heatmap.grayNeutral") private var grayNeutral: Bool = false
    @AppStorage("heatmap.proGreen") private var proGreen: Bool = false
    @AppStorage("heatmap.saturation") private var saturation: Double = 1.0
    @AppStorage("heatmap.boostSmall") private var boostSmallChanges: Bool = true
    @AppStorage("heatmap.palette") private var paletteRaw: String = ColorPalette.cool.rawValue
    private var palette: ColorPalette { get { ColorPalette(rawValue: paletteRaw) ?? .cool } set { paletteRaw = newValue.rawValue } }

    // Inserted auto-widen global flag
    @AppStorage("heatmap.autoWidenGlobal") private var autoWidenGlobal: Bool = true

    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    @State private var toastWorkItem: DispatchWorkItem? = nil

    @State private var showSettingsDropdown: Bool = false
    @State private var infoBarAutoHideWorkItem: DispatchWorkItem? = nil

    @State private var lastAutoWidenAt: Date? = nil

    @State private var showOthersSheet: Bool = false
    @State private var othersItems: [HeatMapTile] = []

    @State private var showAllGridSheet: Bool = false
    @State private var allGridItems: [HeatMapTile] = []

    @State private var animatedBound: Double = HeatMapSharedLib.bound(for: .day1)
    
    // ANIMATION FIX: Track when timeframe last changed to prevent double-animation
    // smoothSetAnimatedBound is skipped within 350ms of a timeframe change since bound was already snapped
    @State private var lastTimeframeChangeAt: Date = .distantPast

    @State private var didSnapInitialBound: Bool = false
    
    // MARK: - Bound Stabilization Cache
    // Cache bounds per timeframe to prevent jitter when switching
    @State private var cachedBound1h: Double? = nil
    @State private var cachedBound24h: Double? = nil
    @State private var cachedBound7d: Double? = nil
    @State private var lastBoundUpdateSignature: String = ""
    @State private var lastBoundUpdateAt: Date = .distantPast
    
    // MARK: - Tiles Memoization Cache
    // Cache processed tiles to avoid expensive recomputation on every render
    @State private var cachedProcessedTiles: [HeatMapTile] = []
    @State private var cachedTilesInputSignature: String = ""
    @State private var cachedTilesLastUpdate: Date = .distantPast
    private let tilesCacheTTL: TimeInterval = 5.0 // PERFORMANCE: Increased to 5s to reduce recomputations
    
    /// Build a signature from the inputs that affect processedTiles to detect actual changes
    /// Uses coarse-grained values to prevent excessive recomputation from minor fluctuations
    private var tilesInputSignature: String {
        // Include all inputs that affect the processedTiles computation
        let sourceCount = viewModel.tiles.count
        // STABILITY: Only use first 10 IDs - order changes in tail shouldn't trigger full recompute
        let sourceIDs = viewModel.tiles.prefix(10).map { $0.id }.joined(separator: ",")
        // STABILITY: Round to 100 million to reduce sensitivity to minor market cap changes
        let sourceCapSum = viewModel.tiles.prefix(5).reduce(0.0) { $0 + $1.marketCap }
        let roundedCap = Int(sourceCapSum / 100_000_000) // Round to $100M increments
        return "\(sourceCount)|\(sourceIDs)|\(roundedCap)|\(filterStables)|\(clampedTopN)|\(pinBTC)|\(includeOthers)|\(weightByVolume)"
    }
    
    /// Memoized version of processedTiles - only recomputes when inputs actually change
    private var memoizedProcessedTiles: [HeatMapTile] {
        let currentSignature = tilesInputSignature
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(cachedTilesLastUpdate)
        
        // Return cached value if signature matches and we're within TTL
        if currentSignature == cachedTilesInputSignature && timeSinceLastUpdate < tilesCacheTTL && !cachedProcessedTiles.isEmpty {
            return cachedProcessedTiles
        }
        
        // Signature changed or TTL expired - recompute
        // Note: We can't mutate @State in a computed property directly, so we use the raw computation
        // The actual cache update happens in updateTilesCacheIfNeeded() called from onChange handlers
        return computeProcessedTiles()
    }
    
    /// The actual tile processing computation (extracted from original processedTiles)
    private func computeProcessedTiles() -> [HeatMapTile] {
        let stables: Set<String> = ["USDT","USDC","BUSD","DAI","FDUSD","TUSD","USDP","GUSD","FRAX","LUSD"]
        var list = viewModel.tiles
        if filterStables { list.removeAll { stables.contains($0.symbol.uppercased()) } }
        // SAFETY FIX: Early return if no tiles available after filtering
        guard !list.isEmpty else { return [] }
        list.sort { $0.marketCap > $1.marketCap }
        if clampedTopN > 0 {
            var adjustedTop = Array(list.prefix(clampedTopN))
            if pinBTC,
               !adjustedTop.contains(where: { $0.symbol.uppercased() == "BTC" }),
               let btc = list.first(where: { $0.symbol.uppercased() == "BTC" }) {
                adjustedTop.append(btc)
                adjustedTop.sort { $0.marketCap > $1.marketCap }
                if adjustedTop.count > clampedTopN { adjustedTop = Array(adjustedTop.prefix(clampedTopN)) }
            }
            if includeOthers {
                let topIDs = Set(adjustedTop.map { $0.id })
                let rest = list.filter { !topIDs.contains($0.id) }

                // Aggregate tail (may be empty during initial load)
                let capSum = rest.reduce(0.0) { $0 + $1.marketCap }
                let volSum = rest.reduce(0.0) { $0 + $1.volume }

                // If tail hasn't loaded or has zero weight yet, synthesize a small placeholder weight so the tile is visible.
                let topCapSum = adjustedTop.reduce(0.0) { $0 + $1.marketCap }
                let topVolSum = adjustedTop.reduce(0.0) { $0 + $1.volume }
                let finalCap = capSum > 0 ? capSum : max(1.0, 0.01 * topCapSum)
                let finalVol = volSum > 0 ? volSum : max(1.0, 0.01 * topVolSum)

                // Ensure minimum visible weight so treemap/grid don't drop the tile due to tiny area
                let minTopBase = adjustedTop.map { weightByVolume ? max($0.volume, 0) : max($0.marketCap, 0) }.min() ?? 0
                let minVisibleBase = max(1.0, 0.08 * minTopBase) // ~8% of the smallest visible tile (smaller placeholder so Others never looks oversized)

                let visibleCap = weightByVolume ? finalCap : max(finalCap, minVisibleBase)
                let visibleVol = weightByVolume ? max(finalVol, minVisibleBase) : finalVol

                // PERFORMANCE: Debug log moved to updateTilesCacheIfNeeded() to avoid logging during render cycles

                func weightedAvg(_ values: [(val: Double?, w: Double)]) -> Double? {
                    var num: Double = 0, den: Double = 0
                    for (vOpt, w) in values { guard let v = vOpt, v.isFinite, w > 0 else { continue }; num += v * w; den += w }
                    return den > 0 ? (num / den) : nil
                }
                let weightsAndValues1h = rest.map { (val: $0.pctChange1h, w: weightByVolume ? $0.volume : $0.marketCap) }
                let weightsAndValues24h = rest.map { (val: Optional($0.pctChange24h), w: weightByVolume ? $0.volume : $0.marketCap) }
                let weightsAndValues7d = rest.map { (val: $0.pctChange7d, w: weightByVolume ? $0.volume : $0.marketCap) }
                let avg1h = weightedAvg(weightsAndValues1h) ?? 0
                let avg24h = weightedAvg(weightsAndValues24h) ?? 0
                let avg7d = weightedAvg(weightsAndValues7d) ?? 0

                let others = HeatMapTile(
                    id: "Others",
                    symbol: (rest.count > 0 ? "Others (\(rest.count))" : "Others"),
                    pctChange24h: avg24h,
                    marketCap: visibleCap,
                    volume: visibleVol,
                    pctChange1h: avg1h,
                    pctChange7d: avg7d
                )
                var result = adjustedTop
                if result.count > clampedTopN { result = Array(result.prefix(clampedTopN)) }
                return result + [others]
            } else {
                return adjustedTop
            }
        }
        return list
    }
    
    /// Update the tiles cache if needed - call this from onChange handlers, not during body
    private func updateTilesCacheIfNeeded() {
        let currentSignature = tilesInputSignature
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(cachedTilesLastUpdate)
        
        // Only recompute if signature changed or TTL expired
        if currentSignature != cachedTilesInputSignature || timeSinceLastUpdate >= tilesCacheTTL || cachedProcessedTiles.isEmpty {
            cachedProcessedTiles = computeProcessedTiles()
            cachedTilesInputSignature = currentSignature
            cachedTilesLastUpdate = now
            
            #if DEBUG
            // PERFORMANCE: Log only during explicit cache updates, not render cycles
            // Rate-limited to once per minute to reduce console spam
            if now.timeIntervalSince(HeatMapDebugLog.lastAt) >= HeatMapDebugLog.minInterval {
                let tileCount = cachedProcessedTiles.count
                let othersCount = cachedProcessedTiles.filter { isOthersID($0.id) }.first.map { tile -> Int in
                    // Extract count from "Others (N)" format
                    let symbol = tile.symbol
                    if let range = symbol.range(of: "\\(\\d+\\)", options: .regularExpression),
                       let numStr = symbol[range].dropFirst().dropLast().description as String?,
                       let num = Int(numStr) { return num }
                    return 0
                } ?? 0
                print("[HeatMap] Cache updated: \(tileCount) tiles, Others aggregates \(othersCount) coins")
                HeatMapDebugLog.lastAt = now
            }
            #endif
        }
    }

    private var highlightColors: [String: Color] {
        guard showMoverBadges else { return [:] }
        let tiles = processedTiles.filter { !isOthersID($0.id) }
        guard !tiles.isEmpty else { return [:] }
        let pairs: [(id: String, ch: Double)] = tiles.map { t in (t.id, (changeProvider?(t)) ?? changeLocal(for: t, tf: timeframe)) }
        let topUp = pairs.sorted { $0.ch > $1.ch }.prefix(max(0, moverBadgeCount)).map { $0.id }
        let topDown = pairs.sorted { $0.ch < $1.ch }.prefix(max(0, moverBadgeCount)).map { $0.id }
        var map: [String: Color] = [:]
        for id in topUp { map[id] = Color.green.opacity(0.9) }
        for id in topDown { map[id] = Color.red.opacity(0.9) }
        return map
    }

    /// Memoized processed tiles - uses cached value when available, falls back to computation
    private var processedTiles: [HeatMapTile] {
        // Return cached if valid, otherwise compute fresh (cache will be updated in onChange handlers)
        if !cachedProcessedTiles.isEmpty && cachedTilesInputSignature == tilesInputSignature {
            return cachedProcessedTiles
        }
        return computeProcessedTiles()
    }

    // REPLACED weights function as per instructions
    private func weights(for tiles: [HeatMapTile]) -> [Double] {
        let exp = weightingCurve.exponent
        var baseWeights: [Double] = tiles.map { tile in
            let base = weightByVolume ? max(tile.volume, 0) : max(tile.marketCap, 0)
            return pow(base, exp)
        }
        
        // LAYOUT FIX: Cap any single non-Others tile at 25% to prevent BTC from dominating
        // This ensures balanced layouts even with extreme market cap differences
        let singleTileCap: Double = 0.25
        let totalWeightPre = baseWeights.reduce(0, +)
        let maxAllowedSingleWeight = singleTileCap * totalWeightPre / (1.0 - singleTileCap)
        var excessFromSingleCap: Double = 0
        
        for i in 0..<baseWeights.count {
            // Don't cap the "Others" tile here - it has its own cap below
            let tile = tiles[i]
            if !isOthersID(tile.id) && !tile.symbol.hasPrefix("Others (") {
                if baseWeights[i] > maxAllowedSingleWeight {
                    excessFromSingleCap += baseWeights[i] - maxAllowedSingleWeight
                    baseWeights[i] = maxAllowedSingleWeight
                }
            }
        }
        
        // Redistribute excess weight proportionally to non-capped, non-Others tiles
        if excessFromSingleCap > 0 {
            let eligibleIndices = baseWeights.enumerated().filter { idx, w in
                let tile = tiles[idx]
                return w < maxAllowedSingleWeight && !isOthersID(tile.id) && !tile.symbol.hasPrefix("Others (")
            }
            let eligibleTotal = eligibleIndices.reduce(0.0) { $0 + $1.element }
            if eligibleTotal > 0 {
                for (idx, w) in eligibleIndices {
                    let share = w / eligibleTotal
                    baseWeights[idx] += excessFromSingleCap * share
                }
            }
        }
        
        // Cap the "Others" share so it cannot dominate the layout.
        guard let othersIndex = tiles.firstIndex(where: { isOthersID($0.id) || $0.symbol.hasPrefix("Others (") }) else {
            return baseWeights
        }
        var adjusted = baseWeights
        let sumNonOthers = adjusted.enumerated().filter { $0.offset != othersIndex }.reduce(0.0) { $0 + $1.element }
        // Hard cap: at most 15-20% of the total visual area for Others (scaled by coin count)
        // LAYOUT FIX: Reduced caps to prevent Others from dominating the layout
        let cap: Double = {
            if clampedTopN <= 12 { return 0.15 }
            else if clampedTopN <= 18 { return 0.16 }
            else if clampedTopN <= 24 { return 0.18 }
            else { return 0.20 }
        }()
        // We want W' <= cap * (S + W'), solve for W': W' <= cap*S / (1 - cap)
        let limit = (cap * sumNonOthers) / max(1e-9, (1.0 - cap))
        if adjusted[othersIndex] > limit {
            // LAYOUT FIX: Redistribute excess weight to non-Others tiles to preserve total
            let excessFromOthersCap = adjusted[othersIndex] - limit
            adjusted[othersIndex] = limit
            
            // Redistribute excess proportionally to non-Others tiles
            if sumNonOthers > 0 && excessFromOthersCap > 0 {
                for i in 0..<adjusted.count where i != othersIndex {
                    let share = adjusted[i] / sumNonOthers
                    adjusted[i] += excessFromOthersCap * share
                }
            }
        }
        return adjusted
    }

    private func othersConstituents() -> [HeatMapTile] {
        let stables: Set<String> = ["USDT","USDC","BUSD","DAI","FDUSD","TUSD","USDP","GUSD","FRAX","LUSD"]
        var list = viewModel.tiles
        if filterStables { list.removeAll { stables.contains($0.symbol.uppercased()) } }
        list.sort { $0.marketCap > $1.marketCap }
        if clampedTopN > 0 {
            var adjustedTop = Array(list.prefix(clampedTopN))
            if pinBTC,
               !adjustedTop.contains(where: { $0.symbol.uppercased() == "BTC" }),
               let btc = list.first(where: { $0.symbol.uppercased() == "BTC" }) {
                adjustedTop.append(btc)
                adjustedTop.sort { $0.marketCap > $1.marketCap }
                if adjustedTop.count > clampedTopN { adjustedTop = Array(adjustedTop.prefix(clampedTopN)) }
            }
            let topIDs = Set(adjustedTop.map { $0.id })
            return list.filter { !topIDs.contains($0.id) }
        }
        return []
    }

    // CONSISTENCY FIX: Always provide a live change provider that fetches from LivePriceManager
    // This ensures Heat Map tiles show the same percentages as Watchlist and Market View
    private var changeProvider: ((HeatMapTile) -> Double)? {
        let tf = timeframe
        
        // Helper to get live value from LivePriceManager
        let liveChange: (HeatMapTile) -> Double = { tile in
            let symbol = tile.symbol.uppercased()
            
            // Try to get live value from LivePriceManager
            let liveVal: Double?
            switch tf {
            case .hour1:
                liveVal = LivePriceManager.shared.bestChange1hPercent(for: symbol)
            case .day1:
                liveVal = LivePriceManager.shared.bestChange24hPercent(for: symbol)
            case .day7:
                liveVal = LivePriceManager.shared.bestChange7dPercent(for: symbol)
            }
            
            // Use live value if available, otherwise fall back to tile value
            if let live = liveVal, live.isFinite {
                return live
            }
            return changeLocal(for: tile, tf: tf)
        }
        
        if normalizeByBTC {
            // Get BTC's live value for normalization
            let btcRef: Double
            switch tf {
            case .hour1:
                btcRef = LivePriceManager.shared.bestChange1hPercent(for: "btc") ?? 0
            case .day1:
                btcRef = LivePriceManager.shared.bestChange24hPercent(for: "btc") ?? 0
            case .day7:
                btcRef = LivePriceManager.shared.bestChange7dPercent(for: "btc") ?? 0
            }
            return { tile in liveChange(tile) - btcRef }
        }
        
        // Always return live change provider for consistency
        return liveChange
    }

    // Added helper functions after changeProvider
    // SYNCED with HeatMapSharedLib.bound(for:) - these MUST match!
    private func defaultCap(for timeframe: HeatMapTimeframe) -> Double {
        HeatMapSharedLib.bound(for: timeframe)
    }

    // Scale steps for auto-widening
    private func scaleStep(for timeframe: HeatMapTimeframe) -> Double {
        let cap = defaultCap(for: timeframe)
        // Scale steps in proportion to the per-timeframe cap to keep legend/tiles aligned.
        if cap <= 3.0 { return 0.5 }
        if cap <= 5.0 { return 1.0 }
        return 2.0
    }

    // Auto-widen safeguard for Global mode: if a meaningful share of the weighted market is off-scale,
    // increase the global bound by one step (capped at the timeframe default). Locked mode is never touched.
    private func maybeAutoWidenGlobal(tiles: [HeatMapTile]) {
        guard autoWidenGlobal else { return }
        guard ScaleMode(rawValue: scaleModeRaw) == .global else { return }
        // Cooldown to avoid repeated nudges on the same dataset
        if let last = lastAutoWidenAt, Date().timeIntervalSince(last) < 10 { return }

        // Exclude synthetic aggregate to avoid overweighting the tail
        let evalTiles = tiles.filter { !isOthersID($0.id) }
        let sourceTiles = evalTiles.isEmpty ? tiles : evalTiles

        var totalW: Double = 0
        var overW: Double = 0
        let b = max(0.0001, globalBound)
        for t in sourceTiles {
            let raw = (changeProvider?(t)) ?? changeLocal(for: t, tf: timeframe)
            guard raw.isFinite else { continue }
            let base = weightByVolume ? max(0, t.volume) : max(0, t.marketCap)
            guard base > 0 else { continue }
            totalW += base
            if abs(raw) > b { overW += base }
        }
        guard totalW > 0 else { return }
        let share = overW / totalW

        // If ~7%+ of weighted market is saturating, widen one step.
        if share >= 0.07 {
            let step = scaleStep(for: timeframe)
            let cap = defaultCap(for: timeframe)
            let widened = min(cap, b + step)
            if widened > globalBound {
                globalBound = widened
                lastAutoWidenAt = Date()
                presentToast(String(format: "Widened global range to ±%.0f%% to avoid clipping", widened))
            }
        }
    }

    // REPLACED autoBound function - AGGRESSIVE TIGHT SCALING for better color differentiation
    private func autoBound(for timeframe: HeatMapTimeframe, tiles: [HeatMapTile]) -> Double {
        let defaultB = HeatMapSharedLib.bound(for: timeframe)
        // Exclude the synthetic "Others" aggregate from estimation to avoid over-weighting the tail.
        let evalTiles = tiles.filter { !isOthersID($0.id) }
        let sourceTiles = evalTiles.isEmpty ? tiles : evalTiles

        // Collect absolute changes with weights (cap or volume) so micro caps don't skew the scale
        struct Pair { let mag: Double; let w: Double }
        var pairs: [Pair] = []
        pairs.reserveCapacity(sourceTiles.count)
        for t in sourceTiles {
            let raw = (changeProvider?(t)) ?? changeLocal(for: t, tf: timeframe)
            guard raw.isFinite else { continue }
            let base = weightByVolume ? max(0, t.volume) : max(0, t.marketCap)
            guard base > 0 else { continue }
            pairs.append(Pair(mag: abs(raw), w: base))
        }
        guard !pairs.isEmpty else { return defaultB }

        // Sort by magnitude for percentile scans
        let sorted = pairs.sorted { $0.mag < $1.mag }
        let totalW = sorted.reduce(0.0) { $0 + $1.w }
        @inline(__always) func wPercentile(_ p: Double) -> Double {
            let target = max(0, min(1, p)) * totalW
            var cum = 0.0
            for s in sorted { cum += s.w; if cum >= target { return s.mag } }
            return sorted.last?.mag ?? 0
        }

        // Use STABLE percentiles for consistent color spread
        let p50 = wPercentile(0.50)
        let p75 = wPercentile(0.75)  // Primary lower target
        let p80 = wPercentile(0.80)  // Primary target (stable)
        let p95 = wPercentile(0.95)  // Maximum bound reference

        // Weighted Median Absolute Deviation (MAD) around the median
        let devs = sorted.map { (d: abs($0.mag - p50), w: $0.w) }.sorted { $0.d < $1.d }
        let totalW2 = devs.reduce(0.0) { $0 + $1.w }
        var cum2: Double = 0
        var mad: Double = devs.last?.d ?? 0
        let target2 = 0.50 * totalW2
        for e in devs { cum2 += e.w; if cum2 >= target2 { mad = e.d; break } }
        let robustCap = p50 + 3.0 * mad // Stable ~3-sigma robust cap

        // Timeframe-tuned multiplier - STABLE for consistent display
        let pFactor: Double
        switch timeframe {
        case .hour1: pFactor = 1.15  // slightly wider for stability
        case .day1:  pFactor = 1.20  // balanced
        case .day7:  pFactor = 1.25  // wider for 7d volatility
        }

        // STABLE: Target p80 as primary, allow down to p75, cap at p90
        // This ensures consistent colors without over-saturation
        let lower = max(p75 * pFactor, p50 * 1.3)  // At least 30% above median
        let upper = min(p95, robustCap)
        let candidate = min(defaultB, max(lower, min(upper, p80 * pFactor)))

        // HARMONIZED minimum floors - MUST match HeatMapSharedLib.bound(for:) defaults
        // These ensure the autoBound never produces a tighter bound than the per-timeframe defaults.
        // The defaults are optimized for typical crypto volatility:
        // - 1h: 3% (small hourly moves reach full color at ±3%)
        // - 24h: 5% (daily moves reach full color at ±5%)
        // - 7d: 10% (weekly moves reach full color at ±10%)
        // When normalizeByBTC is on, BTC-relative moves are smaller, so we use tighter floors.
        let minFloor: Double
        switch timeframe {
        case .hour1: minFloor = normalizeByBTC ? 2.0 : 3.0    // Match default 3%, BTC-relative 2%
        case .day1:  minFloor = normalizeByBTC ? 3.5 : 5.0    // Match default 5%, BTC-relative 3.5%
        case .day7:  minFloor = normalizeByBTC ? 7.0 : 10.0   // Match default 10%, BTC-relative 7%
        }
        let floorB = min(defaultB, minFloor)

        // Respect floor, then snap to friendly steps per timeframe
        let step = scaleStep(for: timeframe)
        @inline(__always) func snap(_ x: Double, step: Double) -> Double { (x / step).rounded() * step }
        let raw = max(floorB, candidate)
        var snapped = snap(raw, step: step)

        // RELAXED anti-saturation: only widen if >15% of weighted market is clipping (was 6%)
        // We WANT some saturation at extremes - it shows which coins are moving most
        let overWeight = pairs.reduce(0.0) { $0 + (($1.mag > snapped) ? $1.w : 0.0) }
        let overShare = overWeight / max(1e-9, totalW)
        if overShare >= 0.15 {
            snapped = min(defaultB, snapped + step)
        }

        return min(defaultB, max(floorB, snapped))
    }

    // MARK: - Bound Stabilization with Hysteresis
    
    /// Generate a lightweight signature of tile data to detect significant changes
    /// Uses top 10 coins' percentage changes (rounded) to avoid reacting to micro-fluctuations
    private func tileDataSignature(for tiles: [HeatMapTile], tf: HeatMapTimeframe) -> String {
        let top = tiles.prefix(10)
        let parts = top.map { t -> String in
            let ch = changeLocal(for: t, tf: tf)
            // Round to 0.5% increments to reduce noise
            let rounded = (ch * 2).rounded() / 2
            return "\(t.symbol):\(rounded)"
        }
        return parts.joined(separator: "|")
    }
    
    /// Get cached bound for the given timeframe, or nil if not cached
    private func getCachedBound(for tf: HeatMapTimeframe) -> Double? {
        switch tf {
        case .hour1: return cachedBound1h
        case .day1: return cachedBound24h
        case .day7: return cachedBound7d
        }
    }
    
    /// Store bound in cache for the given timeframe
    private func setCachedBound(_ value: Double, for tf: HeatMapTimeframe) {
        switch tf {
        case .hour1: cachedBound1h = value
        case .day1: cachedBound24h = value
        case .day7: cachedBound7d = value
        }
    }
    
    /// Update cached bound with hysteresis - call this from onChange handlers, not during body
    private func updateCachedBoundIfNeeded(for tf: HeatMapTimeframe, tiles: [HeatMapTile]) {
        let newComputed = autoBound(for: tf, tiles: tiles)
        let signature = tileDataSignature(for: tiles, tf: tf)
        
        // Check if we have a cached bound for this timeframe
        if let cached = getCachedBound(for: tf) {
            // Check if the signature has materially changed
            let signatureChanged = (signature != lastBoundUpdateSignature)
            
            // Calculate relative difference
            let relativeDiff = abs(newComputed - cached) / max(0.1, cached)
            
            // Hysteresis: only update if difference exceeds 40% AND signature changed
            // OR if more than 120 seconds have passed since last update
            // This prevents jittery scale changes during normal browsing
            let timeSinceUpdate = Date().timeIntervalSince(lastBoundUpdateAt)
            let shouldUpdate = (signatureChanged && relativeDiff > 0.40) || timeSinceUpdate > 120
            
            if shouldUpdate {
                setCachedBound(newComputed, for: tf)
                lastBoundUpdateSignature = signature
                lastBoundUpdateAt = Date()
            }
        } else {
            // No cached bound - initialize it
            setCachedBound(newComputed, for: tf)
            lastBoundUpdateSignature = signature
            lastBoundUpdateAt = Date()
        }
    }
    
    private func targetBound(for tiles: [HeatMapTile]) -> Double {
        switch ScaleMode(rawValue: scaleModeRaw) ?? .perTimeframe {
        case .locked:
            return lockedBound
        case .global:
            return globalBound
        case .perTimeframe:
            // Use cached bound if available, otherwise compute fresh
            if let cached = getCachedBound(for: timeframe) {
                return cached
            }
            // Fallback to fresh computation (will be cached via onChange)
            return autoBound(for: timeframe, tiles: tiles)
        }
    }
    
    private var currentTargetBound: Double { targetBound(for: processedTiles) }
    private var currentTiles: [HeatMapTile] { processedTiles }
    private var currentPalette: ColorPalette { ColorPalette(rawValue: paletteRaw) ?? .cool }
    private var currentLegendNote: String {
        var parts: [String] = []
        if normalizeByBTC { parts.append("vs BTC") }
        switch ScaleMode(rawValue: scaleModeRaw) ?? .perTimeframe {
        case .locked: parts.append("Locked")
        case .global: parts.append("Global")
        case .perTimeframe: parts.append("Auto scale (stable)")
        }
        return parts.joined(separator: " • ")
    }

    /// STABILITY: Coarse signature to prevent excessive bound recalculations
    /// Only changes when the TOP coins change, not when tail coins shuffle
    private var tilesSignature: String {
        // Only track first 8 coins - changes in tail shouldn't trigger bound updates
        currentTiles.prefix(8).map { $0.id }.joined(separator: ",")
    }

    // Clamp user-configured topN to a sane range to avoid pathological layouts
    private var clampedTopN: Int { max(1, min(24, topN)) }

    // Factored helpers to reduce type-checking complexity
    private func mapSectionContent(
        tilesVal: [HeatMapTile],
        boundVal: Double,
        paletteVal: ColorPalette,
        selectedIDVal: String?,
        weightsVal: [Double],
        onTapTile: @escaping (HeatMapTile) -> Void,
        onLongTile: @escaping (HeatMapTile) -> Void
    ) -> AnyView {
        switch selectedLayout {
        case .treemap:
            return AnyView(
                TreemapView(
                    tiles: tilesVal,
                    weights: weightsVal,
                    timeframe: timeframe,
                    selectedID: selectedIDVal,
                    onTileTap: onTapTile,
                    onTileLongPress: onLongTile,
                    changeProvider: changeProvider,
                    showValues: showValues,
                    weightByVolume: weightByVolume,
                    boundOverride: boundVal,
                    palette: paletteVal,
                    forceWhiteLabels: whiteLabelsOnly,
                    highlightColors: highlightColors,
                    strongBorders: strongBorders,
                    labelDensity: labelDensity,
                    isSettling: viewModel.isSettling
                )
                .padding(.bottom, 4)
                .frame(height: mapHeight(for: .treemap, coinCount: tilesVal.count))
                .id("treemap-\(scaleModeRaw)-\(normalizeByBTC)-\(tilesVal.count)")
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            )
        case .grid:
            return AnyView(
                GridHeatMapView(
                    tiles: tilesVal,
                    timeframe: timeframe,
                    selectedID: selectedIDVal,
                    onTileTap: onTapTile,
                    onTileLongPress: onLongTile,
                    changeProvider: changeProvider,
                    showValues: showValues,
                    weightByVolume: weightByVolume,
                    boundOverride: boundVal,
                    palette: paletteVal,
                    forceWhiteLabels: whiteLabelsOnly,
                    highlightColors: [:],
                    strongBorders: strongBorders,
                    labelDensity: labelDensity,
                    onShowAll: { allGridItems = tilesVal; showAllGridSheet = true }
                )
                .padding(.bottom, 4)
                .padding(.top, 0)
                .frame(height: mapHeight(for: .grid))
                .id("grid-\(scaleModeRaw)-\(normalizeByBTC)-\(tilesVal.count)")
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            )
        case .bar:
            return AnyView(
                WeightedHeatMapView(
                    tiles: tilesVal,
                    weights: weightsVal,
                    timeframe: timeframe,
                    selectedID: selectedIDVal,
                    onTileTap: onTapTile,
                    onTileLongPress: onLongTile,
                    changeProvider: changeProvider,
                    showValues: showValues,
                    weightByVolume: weightByVolume,
                    boundOverride: boundVal,
                    palette: paletteVal,
                    forceWhiteLabels: whiteLabelsOnly,
                    highlightColors: [:],
                    strongBorders: strongBorders,
                    labelDensity: labelDensity,
                    // Keep bar-mode Others behavior aligned with settings:
                    // - includeOthers=true: merge/pin Others at tail in bar layout logic
                    // - includeOthers=false: disable synthetic Others entirely
                    maxBars: tilesVal.count,
                    othersMode: includeOthers ? .auto : .never
                )
                .padding(.bottom, 4)
                .frame(height: mapHeight(for: .bar))
                .id("bar-\(scaleModeRaw)-\(normalizeByBTC)-\(tilesVal.count)")
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            )
        }
    }

    private func infoBarOverlayView(tilesVal: [HeatMapTile], timeframe: HeatMapTimeframe) -> AnyView {
        if let t = focusTile {
            let onCloseBar: () -> Void = { withAnimation { focusTile = nil } }
            let onViewDetailsBar: () -> Void = {
                if !isOthersID(t.id) {
                    // Navigate to CoinDetailView via handleTap which sets selected
                    handleTap(t)
                }
            }
            let onViewOthersBar: (() -> Void)? = isOthersID(t.id) ? { othersItems = othersConstituents(); showOthersSheet = true } : nil

            return AnyView(
                HeatMapInfoBar(
                    tile: t,
                    timeframe: timeframe,
                    changeProvider: changeProvider,
                    onClose: onCloseBar,
                    onViewDetails: onViewDetailsBar,
                    onViewOthers: onViewOthersBar
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
                .transition(AnyTransition.opacity.combined(with: AnyTransition.move(edge: .bottom)))
                .zIndex(1000)
                .id(t.id) // Force view recreation when tile changes
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    private func dimmingOverlayView() -> AnyView {
        if focusTile != nil {
            return AnyView(
                Color.black.opacity(0.06)
                    .allowsHitTesting(false)
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    private func toastOverlay() -> AnyView {
        if showToast {
            return AnyView(
                HeatMapToastView(text: toastMessage)
                    .padding(.bottom, 18)
                    .transition(AnyTransition.move(edge: .bottom).combined(with: AnyTransition.opacity))
            )
        } else {
            return AnyView(EmptyView())
        }
    }
    
    private func mapCard(tilesVal: [HeatMapTile], boundVal: Double, paletteVal: ColorPalette, targetBoundVal: Double) -> AnyView {
        AnyView(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.Adaptive.stroke, lineWidth: 1))
                VStack(spacing: 8) {
                    // RESET FIX: Show shimmer if either viewModel tiles are empty OR processed tiles are empty
                    // This handles the case during reset when cache is cleared but viewModel still has data
                    if viewModel.tiles.isEmpty || tilesVal.isEmpty {
                        HeatMapShimmerPlaceholder(height: mapHeight(for: selectedLayout, coinCount: clampedTopN))
                            .padding(.vertical, 6)
                    } else {
                        let weightsVal: [Double] = weights(for: tilesVal)
                        let selectedIDVal: String? = focusTile?.id
                        let onTapTile: (HeatMapTile) -> Void = { tile in
                            // ANIMATION FIX: Wrap in withAnimation so the info bar overlay
                            // slides in with its .transition(.opacity + .move) instead of
                            // appearing abruptly. The close action already used withAnimation.
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                focusTile = tile
                            }
                            scheduleInfoBarAutoHide()
                        }
                        let onLongTile: (HeatMapTile) -> Void = { tile in
                            presentActions(for: tile)
                        }
                        mapSectionContent(
                            tilesVal: tilesVal,
                            boundVal: boundVal,
                            paletteVal: paletteVal,
                            selectedIDVal: selectedIDVal,
                            weightsVal: weightsVal,
                            onTapTile: onTapTile,
                            onLongTile: onLongTile
                        )
                        LegendView(bound: boundVal, note: nil, palette: paletteVal, timeframe: timeframe)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 0)
                            .animation(.easeInOut(duration: 0.35), value: paletteVal)
                            .animation(.easeInOut(duration: 0.35), value: timeframe)
                        Color.clear
                            .frame(height: 0)
                            .onAppear { animatedBound = targetBoundVal }
                            .onChange(of: targetBoundVal) { _, new in
                                // PERFORMANCE FIX: Throttle to prevent "update multiple times per frame" warning
                                // Only update if value changed significantly (0.01 = 1% threshold)
                                guard abs(new - animatedBound) > 0.01 else { return }
                                smoothSetAnimatedBound(to: new)
                            }
                    }
                }
                .padding(8)
                .padding(.top, 0)
                .overlay(dimmingOverlayView())
                .contentShape(Rectangle())
            }
            .overlay(
                Group {
                    infoBarOverlayView(tilesVal: tilesVal, timeframe: timeframe)
                }, alignment: .bottom
            )
            .clipped()
        )
    }

    @ViewBuilder
    private func settingsSheetScrollView() -> some View {
        ScrollView {
            let weightingCurveBinding = Binding<WeightingCurve>(get: { weightingCurve }, set: { weightingCurveRaw = $0.rawValue })
            let labelDensityBinding = Binding<LabelDensity>(get: { labelDensity }, set: { labelDensityRaw = $0.rawValue })
            // PALETTE FIX: Removed paletteBinding - settings panel now reads/writes AppStorage directly

            let boundPreviewVal = currentTargetBound
            let legendNoteTextVal = currentLegendNote
            EnhancedHeatMapSettingsPanelHost(
                isPresented: $showSettingsDropdown,
                filterStables: $filterStables,
                includeOthers: $includeOthers,
                weightByVolume: $weightByVolume,
                normalizeByBTC: $normalizeByBTC,
                showValues: $showValues,
                pinBTC: $pinBTC,
                autoHideInfoBar: $autoHideInfoBar,
                whiteLabelsOnly: $whiteLabelsOnly,
                followLiveUpdates: $followLiveUpdates,
                autoRefreshEnabled: $autoRefreshEnabled,
                strongBorders: $strongBorders,
                grayNeutral: $grayNeutral,
                proGreen: $proGreen,
                saturation: $saturation,
                boostSmallChanges: $boostSmallChanges,
                topN: $topN,
                scaleModeRaw: $scaleModeRaw,
                globalBound: $globalBound,
                minUpdateSeconds: $minUpdateSeconds,
                weightingCurve: weightingCurveBinding,
                labelDensity: labelDensityBinding,
                boundPreview: boundPreviewVal,
                legendNoteText: legendNoteTextVal,
                onRestoreDefaults: {
                    Haptics.medium.impactOccurred()
                    // Dismiss settings before resetting to avoid mid-layout geometry churn
                    showSettingsDropdown = false
                    DispatchQueue.main.async {
                        resetHeatMapDefaults()
                        presentToast("Heat map reset to defaults")
                    }
                }
            )
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func allCoinsHeatMapSheetView() -> some View {
        AllCoinsHeatMapSheet(
            tiles: allGridItems,
            timeframe: timeframe,
            bound: currentTargetBound,
            lastUpdated: viewModel.lastUpdated,
            palette: currentPalette,
            showValues: showValues,
            weightByVolume: weightByVolume,
            forceWhiteLabels: whiteLabelsOnly,
            strongBorders: strongBorders,
            labelDensity: labelDensity,
            changeProvider: changeProvider,
            onSelect: { tile in selected = tile }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func othersListSheetView() -> some View {
        // Use full-screen heat map instead of list view for "Others" coins
        AllCoinsHeatMapSheet(
            tiles: othersItems,
            timeframe: timeframe,
            bound: animatedBound,
            lastUpdated: viewModel.lastUpdated,
            palette: palette,
            showValues: showValues,
            weightByVolume: weightByVolume,
            forceWhiteLabels: whiteLabelsOnly,
            strongBorders: strongBorders,
            labelDensity: labelDensity,
            changeProvider: changeProvider,
            onSelect: { tile in selected = tile },
            title: "Other Coins (\(othersItems.count))"
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func actionsDialogView() -> some View {
        if let t = actionTile {
            if isOthersID(t.id) {
                Button("View Coins") {
                    othersItems = othersConstituents()
                    showOthersSheet = true
                }
            } else {
                Button("View Details") {
                    handleTap(t)
                }
            }
        }
        Button("Cancel", role: .cancel) { }
    }

    private var dialogTitle: String { actionTile?.symbol ?? "Actions" }

    @ViewBuilder
    private func coinDetailSheetView(tile: HeatMapTile) -> some View {
        // Find the corresponding MarketCoin for the tile
        if let coin = MarketViewModel.shared.allCoins.first(where: { $0.symbol.uppercased() == tile.symbol.uppercased() }) {
            NavigationStack {
                CoinDetailView(coin: coin)
            }
        } else {
            // Fallback: create a minimal coin representation
            NavigationStack {
                VStack(spacing: 16) {
                    Text(tile.symbol)
                        .font(.title.bold())
                    Text("Coin details unavailable")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Adaptive.background)
            }
        }
    }

    // Added helper function for smoothed animatedBound updates
    private func smoothSetAnimatedBound(to new: Double) {
        // ANIMATION FIX: Skip if we just changed timeframes - bound was already snapped instantly
        // This prevents the "colors get brighter then change again" issue caused by:
        // 1. Instant snap on timeframe change (line ~1367)
        // 2. This function's blending logic producing an intermediate value
        if Date().timeIntervalSince(lastTimeframeChangeAt) < 0.35 {
            return
        }
        
        let step: Double
        switch timeframe {
        case .hour1: step = 0.2
        case .day1:  step = 0.5
        case .day7:  step = 1.0
        }
        let delta = abs(new - animatedBound)
        // Ignore tiny noise
        if delta < step * 0.5 { return }
        // Snap immediately on large jumps (about 6 steps)
        let snapThreshold = step * 6 // 1h: 1.2%, 24h: 3.0%, 7d: 6.0%
        if delta >= snapThreshold {
            withAnimation(.easeInOut(duration: 0.25)) { animatedBound = new }
            return
        }
        // SMOOTH SPRING: Use a proper spring animation for natural-feeling bound transitions
        // instead of manual alpha blending which created a stepping effect.
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { animatedBound = new }
    }

    private func presentToast(_ message: String, duration: TimeInterval = 1.6) {
        toastWorkItem?.cancel(); toastMessage = message
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showToast = true }
        let work = DispatchWorkItem { withAnimation(.easeOut(duration: 0.25)) { showToast = false } }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func scheduleInfoBarAutoHide(after seconds: TimeInterval = 6.0) {
        infoBarAutoHideWorkItem?.cancel(); guard autoHideInfoBar else { return }
        let work = DispatchWorkItem { withAnimation { focusTile = nil } }
        infoBarAutoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
    
    private func resetHeatMapDefaults() {
        // Preserve user's current layout (Treemap/Grid/Bar) and timeframe (1h/24h/7d)
        // Only reset the heat map visual/data settings, not navigation state
        
        // Data filtering / weighting
        filterStables = true
        includeOthers = true
        weightByVolume = false        // default to market cap weighting for stable layout
        normalizeByBTC = false

        // Labels & values
        showValues = false            // hide raw values by default (keeps tiles cleaner)
        whiteLabelsOnly = true
        strongBorders = false

        // Layout density & selection
        weightingCurveRaw = WeightingCurve.balanced.rawValue
        labelDensityRaw = LabelDensity.normal.rawValue
        topN = 8                      // default to 8 coins shown
        pinBTC = true

        // Legend/behavior
        autoHideInfoBar = true
        scaleModeRaw = ScaleMode.perTimeframe.rawValue

        // Palette & saturation
        paletteRaw = ColorPalette.cool.rawValue
        grayNeutral = false
        proGreen = false
        saturation = 0.95
        boostSmallChanges = true

        // Clear cached bounds to force fresh computation after reset
        // This prevents stale cached bounds from overriding the reset
        cachedBound1h = nil
        cachedBound24h = nil
        cachedBound7d = nil
        lastBoundUpdateSignature = ""
        lastBoundUpdateAt = .distantPast
        didSnapInitialBound = false

        // Bounds: clamp to a safe, finite value and defer animated update to avoid transient layout churn
        let base = HeatMapSharedLib.bound(for: .day1)
        let safeBound = max(2.0, min(100.0, base.isFinite ? base : 20.0))
        globalBound = safeBound
        lockedBound = safeBound

        DispatchQueue.main.async { [self] in
            smoothSetAnimatedBound(to: safeBound)
        }

        // Badges
        showMoverBadges = false
        moverBadgeCount = 2

        // Clear selection to avoid overlay layout during reset
        focusTile = nil
        
        // RESET FIX: Clear tiles cache so it gets recomputed with new settings
        cachedProcessedTiles = []
        cachedTilesInputSignature = ""
        cachedTilesLastUpdate = .distantPast
        
        // DATA ACCURACY FIX: Force refresh with hysteresis clear to get completely fresh data
        // This ensures the reset truly resets all values, not just settings
        viewModel.forceRefresh(reason: "User reset settings", clearHysteresis: true)
        
        // RESET FIX: Update tiles cache after reset to ensure tiles are computed with new settings
        DispatchQueue.main.async { [self] in
            updateTilesCacheIfNeeded()
        }
    }

    // <-- MODIFIED controlBarView START
    @ViewBuilder
    private func controlBarView() -> some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(HeatMapTimeframe.allCases, id: \.id) { tf in
                            CapsuleChip(title: tf.rawValue, selected: timeframe == tf, size: .small) {
                                Haptics.light.impactOccurred()
                                // ANIMATION FIX: Wrap in withAnimation so the entire view tree
                                // receives an explicit animation transaction. Previously, the
                                // @AppStorage change often lost the animation context, causing
                                // tiles to snap to new colors instead of crossfading smoothly.
                                withAnimation(.easeInOut(duration: 0.45)) {
                                    timeframeRaw = tf.rawValue
                                }
                            }
                        }
                    }
                    Rectangle().fill(DS.Adaptive.divider).frame(width: 1, height: 14).cornerRadius(1)
                    HStack(spacing: 6) {
                        // ANIMATION FIX: Wrap layout changes in withAnimation so the
                        // .transition(.opacity) on each layout view fires reliably.
                        // Previously layout changes had no animation context, causing
                        // an abrupt swap instead of a smooth crossfade.
                        CapsuleChip(title: "Treemap", selected: selectedLayout == .treemap, size: .small, systemImage: "square.grid.3x3.fill") {
                            Haptics.light.impactOccurred()
                            withAnimation(.easeInOut(duration: 0.3)) { layoutRaw = Layout.treemap.rawValue }
                        }
                        CapsuleChip(title: "Grid", selected: selectedLayout == .grid, size: .small, systemImage: "square.grid.2x2") {
                            Haptics.light.impactOccurred()
                            withAnimation(.easeInOut(duration: 0.3)) { layoutRaw = Layout.grid.rawValue }
                        }
                        CapsuleChip(title: "Bar", selected: selectedLayout == .bar, size: .small, systemImage: "rectangle.split.3x1.fill") {
                            Haptics.light.impactOccurred()
                            withAnimation(.easeInOut(duration: 0.3)) { layoutRaw = Layout.bar.rawValue }
                        }
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { Haptics.light.impactOccurred(); withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { showSettingsDropdown.toggle() } } label: {
                let isDark = colorScheme == .dark
                ZStack {
                    Circle()
                        .fill(TintedChipStyle.selectedBackground(isDark: isDark))
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isDark ? 0.12 : 0.45), Color.white.opacity(0)],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: isDark
                                    ? [BrandColors.goldLight.opacity(0.35), TintedChipStyle.selectedStroke(isDark: true).opacity(0.6)]
                                    : [BrandColors.goldBase.opacity(0.45), TintedChipStyle.selectedStroke(isDark: false).opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    Image(systemName: "slider.horizontal.3")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TintedChipStyle.selectedText(isDark: isDark))
                }
                .frame(width: 30, height: 30)
            }
            .padding(.leading, 4)
            .padding(.trailing, 2)
            .buttonStyle(PressableStyle())
            .accessibilityLabel(Text("Settings"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .padding(.bottom, 2)
        .background(DS.Adaptive.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.Adaptive.stroke, lineWidth: 1))
        .zIndex(showSettingsDropdown ? 1000 : 50)
    }

    // MARK: - Body
    public var body: some View {
        bodyContent
            .onAppear {
                viewModel.forceRefresh(reason: "section appear")
                // Initialize tile cache and cached bound for current timeframe on appear
                DispatchQueue.main.async {
                    updateTilesCacheIfNeeded()
                    updateCachedBoundIfNeeded(for: timeframe, tiles: processedTiles)
                }
            }
            .modifier(PrimaryChangeHandlers(
                viewModel: viewModel,
                timeframeRaw: timeframeRaw,
                getCurrentTargetBound: { currentTargetBound },
                getCurrentTiles: { currentTiles },
                didSnapInitialBound: $didSnapInitialBound,
                animatedBound: $animatedBound,
                selected: $selected,  // DATA SYNC FIX: Pass selected binding
                lastTimeframeChangeAt: $lastTimeframeChangeAt,  // ANIMATION FIX: Track timeframe change timing
                maybeAutoWidenGlobal: maybeAutoWidenGlobal,
                updateCachedBound: { updateCachedBoundIfNeeded(for: timeframe, tiles: processedTiles) },
                updateTilesCache: { updateTilesCacheIfNeeded() }
            ))
            .modifier(SecondaryChangeHandlers(
                viewModel: viewModel,
                followLiveUpdates: followLiveUpdates,
                minUpdateSeconds: minUpdateSeconds,
                autoRefreshEnabled: autoRefreshEnabled,
                scaleModeRaw: scaleModeRaw,
                globalBound: globalBound,
                lockedBound: lockedBound,
                paletteRaw: paletteRaw,
                normalizeByBTC: normalizeByBTC,
                topN: topN,
                getCurrentTargetBound: { currentTargetBound },
                getCurrentTiles: { currentTiles },
                smoothSetAnimatedBound: smoothSetAnimatedBound,
                maybeAutoWidenGlobal: maybeAutoWidenGlobal,
                updateTilesCache: { updateTilesCacheIfNeeded() },
                updateTilesCacheIfNeeded: { updateTilesCacheIfNeeded() },
                grayNeutral: $grayNeutral
            ))
            .modifier(TertiaryChangeHandlers(
                includeOthers: includeOthers,
                tilesSignature: tilesSignature,
                weightByVolume: weightByVolume,
                filterStables: filterStables,
                pinBTC: pinBTC,
                getCurrentTargetBound: { currentTargetBound },
                getCurrentTiles: { currentTiles },
                smoothSetAnimatedBound: smoothSetAnimatedBound,
                maybeAutoWidenGlobal: maybeAutoWidenGlobal,
                updateTilesCache: { updateTilesCacheIfNeeded() },
                animatedBound: $animatedBound
            ))
            .sheet(isPresented: $showSettingsDropdown) {
                NavigationStack {
                    settingsSheetScrollView()
                        .navigationTitle("Heat Map Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                CSNavButton(icon: "xmark", action: { showSettingsDropdown = false }, accessibilityText: "Close", compact: true)
                            }
                        }
                        .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $selected) { tile in
                coinDetailSheetView(tile: tile)
            }
            .sheet(isPresented: $showOthersSheet) {
                othersListSheetView()
            }
            .sheet(isPresented: $showAllGridSheet) {
                allCoinsHeatMapSheetView()
            }
            .confirmationDialog(dialogTitle, isPresented: $showActions, titleVisibility: .visible) {
                actionsDialogView()
            }
            // STABILITY FIX: Disable animations during settling period to prevent visual flickering
            .animation(viewModel.isSettling ? nil : .snappy, value: selectedLayout)
            .overlay(toastOverlay(), alignment: .bottom)
    }
    
    @ViewBuilder
    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Integrated header - consistent with other sections
            HStack(alignment: .center, spacing: 8) {
                GoldHeaderGlyph(systemName: "square.grid.2x2")
                
                Text("Market Heat Map")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            
            let boundVal = animatedBound
            // PALETTE FIX: Read paletteRaw directly to ensure SwiftUI tracks this dependency
            let paletteVal = ColorPalette(rawValue: paletteRaw) ?? .cool
            let tilesVal = currentTiles
            let targetBoundVal = currentTargetBound

            controlBarView()

            mapCard(tilesVal: tilesVal, boundVal: boundVal, paletteVal: paletteVal, targetBoundVal: targetBoundVal)
                .animation(.easeInOut(duration: 0.4), value: paletteRaw)
        }
    }

    private func handleTap(_ tile: HeatMapTile) {
        // ANIMATION FIX: Wrap in withAnimation so the tile's selection scale effect
        // (.scaleEffect(selected ? 1.02 : 1.0)) animates reliably via the explicit
        // transaction rather than depending solely on the implicit .animation(_, value: selected).
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selected = tile
        }
    }
    @State private var actionTile: HeatMapTile? = nil
    @State private var showActions: Bool = false
    private func presentActions(for tile: HeatMapTile) { actionTile = tile; showActions = true }
}

// MARK: - ViewModifiers to break up body complexity for Swift type-checker

private struct PrimaryChangeHandlers: ViewModifier {
    let viewModel: HeatMapViewModel
    let timeframeRaw: String
    let getCurrentTargetBound: () -> Double
    let getCurrentTiles: () -> [HeatMapTile]
    @Binding var didSnapInitialBound: Bool
    @Binding var animatedBound: Double
    @Binding var selected: HeatMapTile?  // DATA SYNC FIX: Track selected tile
    @Binding var lastTimeframeChangeAt: Date  // ANIMATION FIX: Track timeframe change timing
    let maybeAutoWidenGlobal: ([HeatMapTile]) -> Void
    let updateCachedBound: () -> Void
    let updateTilesCache: () -> Void
    
    /// DATA SYNC FIX: Update selected tile to fresh version from processedTiles
    /// This ensures the info bar displays the same data as the rendered tile
    private func syncSelectedTile() {
        guard let currentSelected = selected else { return }
        let freshTiles = getCurrentTiles()
        // Find matching tile by symbol (more reliable than id for heat map tiles)
        if let freshTile = freshTiles.first(where: { $0.symbol == currentSelected.symbol }) {
            // Only update if the percentage value has actually changed
            if freshTile.pctChange24h != currentSelected.pctChange24h ||
               freshTile.pctChange1h != currentSelected.pctChange1h ||
               freshTile.pctChange7d != currentSelected.pctChange7d {
                selected = freshTile
            }
        }
    }
    
    func body(content: Content) -> some View {
        content
            .onChange(of: timeframeRaw) { _, _ in
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    // Update tile cache and cached bound for new timeframe
                    updateTilesCache()
                    updateCachedBound()
                    // Tiles already contain all 1H/24H/7D data, so switching reuses existing views.
                    // Just trigger a refresh without clearing to get any updated percentages.
                    viewModel.forceRefresh(reason: "timeframe change", clearHysteresis: false)
                    // Record timestamp to prevent smoothSetAnimatedBound from double-animating
                    lastTimeframeChangeAt = Date()
                    // SMOOTH TRANSITION: Animate bound change when switching timeframes.
                    // The tiles now stay stable (not recreated) and colors crossfade smoothly,
                    // so the bound should also transition smoothly for a cohesive animation.
                    let newBound = getCurrentTargetBound()
                    withAnimation(.easeInOut(duration: 0.4)) {
                        animatedBound = newBound
                    }
                    maybeAutoWidenGlobal(getCurrentTiles())
                    // DATA SYNC FIX: Sync selected tile after timeframe change
                    syncSelectedTile()
                }
            }
            .onChange(of: viewModel.tiles.count) { _, newCount in
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    // Update tile cache and cached bound when tiles change
                    updateTilesCache()
                    updateCachedBound()
                    if !didSnapInitialBound && newCount > 0 {
                        animatedBound = getCurrentTargetBound()
                        didSnapInitialBound = true
                    }
                    maybeAutoWidenGlobal(getCurrentTiles())
                    // DATA SYNC FIX: Sync selected tile when tiles change
                    syncSelectedTile()
                }
            }
            .onChange(of: viewModel.lastUpdated) { _, _ in
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    // Update tile cache and cached bound when data refreshes
                    updateTilesCache()
                    updateCachedBound()
                    if !didSnapInitialBound && !viewModel.tiles.isEmpty {
                        animatedBound = getCurrentTargetBound()
                        didSnapInitialBound = true
                    }
                    maybeAutoWidenGlobal(getCurrentTiles())
                    // DATA SYNC FIX: Sync selected tile when data refreshes
                    syncSelectedTile()
                }
            }
    }
}

private struct SecondaryChangeHandlers: ViewModifier {
    let viewModel: HeatMapViewModel
    let followLiveUpdates: Bool
    let minUpdateSeconds: Int
    let autoRefreshEnabled: Bool
    let scaleModeRaw: String
    let globalBound: Double
    let lockedBound: Double
    let paletteRaw: String
    let normalizeByBTC: Bool
    let topN: Int
    let getCurrentTargetBound: () -> Double
    let getCurrentTiles: () -> [HeatMapTile]
    let smoothSetAnimatedBound: (Double) -> Void
    let maybeAutoWidenGlobal: ([HeatMapTile]) -> Void
    let updateTilesCache: () -> Void
    let updateTilesCacheIfNeeded: () -> Void
    @Binding var grayNeutral: Bool
    
    private enum ScaleMode: String { case perTimeframe, global, locked }
    
    func body(content: Content) -> some View {
        content
            .onChange(of: followLiveUpdates) { _, v in
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async { viewModel.setFollowLiveUpdates(v) }
            }
            .onChange(of: minUpdateSeconds) { _, v in
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async { viewModel.setMinAdoptionInterval(v) }
            }
            .onChange(of: autoRefreshEnabled) { _, v in
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async { viewModel.updateAutoRefreshTimer(enabled: v) }
            }
            .onChange(of: scaleModeRaw) { _, _ in
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async { smoothSetAnimatedBound(getCurrentTargetBound()) }
            }
            .onChange(of: globalBound) { _, _ in
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    if ScaleMode(rawValue: scaleModeRaw) == .global {
                        smoothSetAnimatedBound(globalBound)
                    }
                }
            }
            .onChange(of: lockedBound) { _, _ in
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    if ScaleMode(rawValue: scaleModeRaw) == .locked {
                        smoothSetAnimatedBound(lockedBound)
                    }
                }
            }
            .onChange(of: paletteRaw) { _, newRaw in
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    if ColorPalette(rawValue: newRaw) == .warm {
                        grayNeutral = false
                    }
                    updateTilesCacheIfNeeded()
                }
            }
            .onChange(of: normalizeByBTC) { _, _ in
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    smoothSetAnimatedBound(getCurrentTargetBound())
                    maybeAutoWidenGlobal(getCurrentTiles())
                }
            }
            .onChange(of: topN) { _, _ in
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    updateTilesCache()
                    viewModel.forceRefresh(reason: "topN change")
                    smoothSetAnimatedBound(getCurrentTargetBound())
                    maybeAutoWidenGlobal(getCurrentTiles())
                }
            }
    }
}

private struct TertiaryChangeHandlers: ViewModifier {
    let includeOthers: Bool
    let tilesSignature: String
    let weightByVolume: Bool
    let filterStables: Bool
    let pinBTC: Bool
    let getCurrentTargetBound: () -> Double
    let getCurrentTiles: () -> [HeatMapTile]
    let smoothSetAnimatedBound: (Double) -> Void
    let maybeAutoWidenGlobal: ([HeatMapTile]) -> Void
    let updateTilesCache: () -> Void
    @Binding var animatedBound: Double
    
    func body(content: Content) -> some View {
        content
            .onChange(of: includeOthers) { _, _ in
                DispatchQueue.main.async {
                    updateTilesCache()
                    animatedBound = getCurrentTargetBound()
                }
                maybeAutoWidenGlobal(getCurrentTiles())
            }
            .onChange(of: tilesSignature) { _, _ in
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    smoothSetAnimatedBound(getCurrentTargetBound())
                }
            }
            .onChange(of: weightByVolume) { _, _ in
                DispatchQueue.main.async {
                    updateTilesCache()
                    animatedBound = getCurrentTargetBound()
                }
                maybeAutoWidenGlobal(getCurrentTiles())
            }
            .onChange(of: filterStables) { _, _ in
                DispatchQueue.main.async {
                    updateTilesCache()
                    animatedBound = getCurrentTargetBound()
                }
                maybeAutoWidenGlobal(getCurrentTiles())
            }
            .onChange(of: pinBTC) { _, _ in
                DispatchQueue.main.async {
                    updateTilesCache()
                    animatedBound = getCurrentTargetBound()
                }
                maybeAutoWidenGlobal(getCurrentTiles())
            }
    }
}

// MARK: - CapsuleChip used in control bars
private enum ChipSize { case regular, small }
private struct CapsuleChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let selected: Bool
    let size: ChipSize
    let systemImage: String?
    let action: () -> Void

    init(title: String, selected: Bool, size: ChipSize, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.selected = selected; self.size = size; self.systemImage = systemImage; self.action = action
    }

    var body: some View {
        let isDark = colorScheme == .dark
        Button(action: action) {
            let height: CGFloat = (size == .small ? 26 : 34)
            let fontSize: CGFloat = (size == .small ? 11.0 : 13.5)
            let hPad: CGFloat = (size == .small ? 8 : 12)
            let vPad: CGFloat = (size == .small ? 2 : 4)
            HStack(spacing: 6) {
                if let system = systemImage { Image(systemName: system).font(.system(size: fontSize - 1, weight: .semibold)) }
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .frame(height: height)
            .foregroundColor(selected ? TintedChipStyle.selectedText(isDark: isDark) : DS.Adaptive.textPrimary)
            .tintedCapsuleChip(isSelected: selected, isDark: isDark)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Shimmer placeholder and Toast
private struct HeatMapShimmerView: View {
    @State private var animate = false
    var body: some View {
        ZStack {
            DS.Adaptive.chipBackground
            LinearGradient(colors: [Color.clear, DS.Adaptive.strokeStrong, Color.clear], startPoint: .leading, endPoint: .trailing)
                .offset(x: animate ? 240 : -240)
        }
        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: animate)
        .onAppear {
            // PERFORMANCE FIX: Delay animation start during scroll
            if ScrollStateManager.shared.shouldBlockHeavyOperation() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    animate = true
                }
            } else {
                animate = true
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct HeatMapShimmerPlaceholder: View {
    let height: CGFloat
    var body: some View {
        HeatMapShimmerView()
            .frame(height: height)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 16)
    }
}

private struct HeatMapToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundColor(DS.Adaptive.gold)
            Text(text).font(.subheadline.weight(.semibold)).foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // PERFORMANCE FIX v19: Replaced .ultraThinMaterial with solid color
        .background(
            ZStack {
                Capsule().fill(DS.Adaptive.chipBackground)
                Capsule().fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        )
    }
}

// A lightweight wrapper to isolate the heavy generic instantiation of EnhancedHeatMapSettingsPanel
private struct EnhancedHeatMapSettingsPanelHost: View {
    @Binding var isPresented: Bool
    @Binding var filterStables: Bool
    @Binding var includeOthers: Bool
    @Binding var weightByVolume: Bool
    @Binding var normalizeByBTC: Bool
    @Binding var showValues: Bool
    @Binding var pinBTC: Bool
    @Binding var autoHideInfoBar: Bool
    @Binding var whiteLabelsOnly: Bool
    @Binding var followLiveUpdates: Bool
    @Binding var autoRefreshEnabled: Bool
    @Binding var strongBorders: Bool
    @Binding var grayNeutral: Bool
    @Binding var proGreen: Bool
    @Binding var saturation: Double
    @Binding var boostSmallChanges: Bool
    @Binding var topN: Int
    @Binding var scaleModeRaw: String
    @Binding var globalBound: Double
    @Binding var minUpdateSeconds: Int

    var weightingCurve: Binding<WeightingCurve>
    var labelDensity: Binding<LabelDensity>
    // PALETTE FIX: Removed palette binding - settings panel reads AppStorage directly

    let boundPreview: Double
    let legendNoteText: String
    let onRestoreDefaults: () -> Void

    var body: some View {
        EnhancedHeatMapSettingsPanel(
            isPresented: $isPresented,
            filterStables: $filterStables,
            includeOthers: $includeOthers,
            weightByVolume: $weightByVolume,
            normalizeByBTC: $normalizeByBTC,
            showValues: $showValues,
            pinBTC: $pinBTC,
            autoHideInfoBar: $autoHideInfoBar,
            whiteLabelsOnly: $whiteLabelsOnly,
            followLiveUpdates: $followLiveUpdates,
            autoRefreshEnabled: $autoRefreshEnabled,
            strongBorders: $strongBorders,
            grayNeutral: $grayNeutral,
            proGreen: $proGreen,
            saturation: $saturation,
            boostSmallChanges: $boostSmallChanges,
            topN: $topN,
            minUpdateSeconds: $minUpdateSeconds,
            weightingCurve: weightingCurve,
            labelDensity: labelDensity,
            scaleModeRaw: $scaleModeRaw,
            globalBound: $globalBound,
            boundPreview: boundPreview,
            legendNoteText: legendNoteText,
            onRestoreDefaults: onRestoreDefaults
        )
    }
}

// MARK: - Sheets
struct OthersListSheet: View {
    let tiles: [HeatMapTile]
    let timeframe: HeatMapTimeframe
    let lastUpdated: Date?
    let changeProvider: ((HeatMapTile) -> Double)?
    var onSelect: (HeatMapTile) -> Void

    init(tiles: [HeatMapTile], timeframe: HeatMapTimeframe, lastUpdated: Date?, changeProvider: ((HeatMapTile) -> Double)? = nil, onSelect: @escaping (HeatMapTile) -> Void) {
        self.tiles = tiles
        self.timeframe = timeframe
        self.lastUpdated = lastUpdated
        self.changeProvider = changeProvider
        self.onSelect = onSelect
    }

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var sortOption: SortOption = .marketCap
    @FocusState private var isSearchFocused: Bool
    
    private enum SortOption: String, CaseIterable {
        case marketCap = "Market Cap"
        case change = "Change"
        case volume = "Volume"
        case name = "Name"
    }
    
    // Lookup coin data from MarketViewModel
    private func coinData(for symbol: String) -> MarketCoin? {
        MarketViewModel.shared.allCoins.first { $0.symbol.uppercased() == symbol.uppercased() }
    }
    
    private func coinName(for symbol: String) -> String {
        coinData(for: symbol)?.name ?? symbol
    }
    
    private func coinImageURL(for symbol: String) -> URL? {
        coinData(for: symbol)?.imageUrl
    }
    
    private var filteredAndSortedTiles: [HeatMapTile] {
        var result = tiles
        
        // Filter by search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { tile in
                tile.symbol.lowercased().contains(query) ||
                coinName(for: tile.symbol).lowercased().contains(query)
            }
        }
        
        // Sort
        switch sortOption {
        case .marketCap:
            result.sort { $0.marketCap > $1.marketCap }
        case .change:
            result.sort { abs(changeValue(for: $0)) > abs(changeValue(for: $1)) }
        case .volume:
            result.sort { $0.volume > $1.volume }
        case .name:
            result.sort { coinName(for: $0.symbol).lowercased() < coinName(for: $1.symbol).lowercased() }
        }
        
        return result
    }
    
    private func changeValue(for tile: HeatMapTile) -> Double {
        (changeProvider?(tile)) ?? changeLocal(for: tile, tf: timeframe)
    }
    
    private func formatCap(_ v: Double) -> String {
        switch v {
        case 1_000_000_000_000...: return String(format: "$%.2fT", v/1_000_000_000_000)
        case 1_000_000_000...: return String(format: "$%.2fB", v/1_000_000_000)
        case 1_000_000...: return String(format: "$%.1fM", v/1_000_000)
        case 1_000...: return String(format: "$%.1fK", v/1_000)
        default: return String(format: "$%.0f", v)
        }
    }
    
    private func changeColor(_ ch: Double) -> Color {
        ch >= 0 ? Color(red: 0.2, green: 0.78, blue: 0.45) : Color(red: 0.95, green: 0.3, blue: 0.3)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header stats
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(tiles.count) Coins")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        if let date = lastUpdated {
                            let rel = relativeUpdatedString(since: date)
                            if !rel.isEmpty {
                                Text("Updated \(rel)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    Spacer()
                    // Total market cap of Others
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Total Cap")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        Text(formatCap(tiles.reduce(0) { $0 + $1.marketCap }))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                
                // Search bar
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                        TextField("Search coins...", text: $searchText)
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isSearchFocused = true
                    }
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                
                // Sort options
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Button(action: { Haptics.light.impactOccurred(); sortOption = option }) {
                                let isSel = sortOption == option
                                HStack(spacing: 4) {
                                    if isSel {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    Text(option.rawValue)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundColor(isSel ? .white : .white.opacity(0.6))
                                .background(
                                    ZStack {
                                        Capsule()
                                            .fill(isSel ? Color.white.opacity(0.15) : Color.white.opacity(0.06))
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(isSel ? 0.12 : 0.04), Color.white.opacity(0)],
                                                    startPoint: .top,
                                                    endPoint: .center
                                                )
                                            )
                                    }
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(isSel ? 0.3 : 0.12), Color.white.opacity(isSel ? 0.1 : 0.04)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                                )
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 12)
                
                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                
                // Coin list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredAndSortedTiles) { tile in
                            Button {
                                Haptics.light.impactOccurred()
                                onSelect(tile)
                                dismiss()
                            } label: {
                                coinRow(tile: tile)
                            }
                            .buttonStyle(PressableRowStyle())
                            
                            // Row divider
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 68)
                        }
                    }
                }
                .refreshable {
                    // Pull to refresh - trigger a data reload
                    Haptics.light.impactOccurred()
                }
            }
            .background(Color(white: 0.08))
            .navigationTitle("Other Coins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CSNavButton(icon: "xmark", action: { dismiss() }, accessibilityText: "Close", compact: true)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
        }
    }
    
    @ViewBuilder
    private func coinRow(tile: HeatMapTile) -> some View {
        let ch = changeValue(for: tile)
        
        HStack(spacing: 12) {
            // Coin logo
            CoinImageView(symbol: tile.symbol, url: coinImageURL(for: tile.symbol), size: 40)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            
            // Name and symbol
            VStack(alignment: .leading, spacing: 3) {
                Text(tile.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text(coinName(for: tile.symbol))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Market cap
            VStack(alignment: .trailing, spacing: 3) {
                Text(formatCap(tile.marketCap))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                
                // Change badge
                HStack(spacing: 3) {
                    Image(systemName: ch >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(percentStringAdaptive(ch))
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundColor(ch >= 0 ? .black : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(changeColor(ch), in: Capsule())
            }
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// Custom row press style
private struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.06) : Color.clear)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct AllCoinsListSheet: View {
    let tiles: [HeatMapTile]
    let timeframe: HeatMapTimeframe
    let lastUpdated: Date?
    let changeProvider: ((HeatMapTile) -> Double)?
    var onSelect: (HeatMapTile) -> Void

    init(tiles: [HeatMapTile], timeframe: HeatMapTimeframe, lastUpdated: Date?, changeProvider: ((HeatMapTile) -> Double)? = nil, onSelect: @escaping (HeatMapTile) -> Void) {
        self.tiles = tiles
        self.timeframe = timeframe
        self.lastUpdated = lastUpdated
        self.changeProvider = changeProvider
        self.onSelect = onSelect
    }

    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(tiles) { tile in
                Button { Haptics.light.impactOccurred(); onSelect(tile); dismiss() } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.symbol).font(.headline)
                            Text(valueAbbrev(tile.marketCap)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        let ch = (changeProvider?(tile)) ?? changeLocal(for: tile, tf: timeframe)
                        Text(percentStringAdaptive(ch)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(ch >= 0 ? .green : .red)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("All Coins")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let date = lastUpdated { let rel = relativeUpdatedString(since: date); if !rel.isEmpty { Text(rel).font(.caption).foregroundStyle(DS.Adaptive.textSecondary) } }
                }
                ToolbarItem(placement: .cancellationAction) {
                    CSNavButton(icon: "xmark", action: { dismiss() }, accessibilityText: "Close", compact: true)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
        }
    }
}

struct AllCoinsHeatMapSheet: View {
    let tiles: [HeatMapTile]
    let timeframe: HeatMapTimeframe
    let bound: Double
    let lastUpdated: Date?
    let palette: ColorPalette
    let showValues: Bool
    let weightByVolume: Bool
    let forceWhiteLabels: Bool
    let strongBorders: Bool
    let labelDensity: LabelDensity
    let changeProvider: ((HeatMapTile) -> Double)?
    var onSelect: (HeatMapTile) -> Void
    var title: String = "All Coins Heat Map"

    init(tiles: [HeatMapTile], timeframe: HeatMapTimeframe, bound: Double, lastUpdated: Date?, palette: ColorPalette, showValues: Bool, weightByVolume: Bool, forceWhiteLabels: Bool, strongBorders: Bool, labelDensity: LabelDensity, changeProvider: ((HeatMapTile) -> Double)?, onSelect: @escaping (HeatMapTile) -> Void, title: String = "All Coins Heat Map") {
        self.tiles = tiles
        self.timeframe = timeframe
        self.bound = bound
        self.lastUpdated = lastUpdated
        self.palette = palette
        self.showValues = showValues
        self.weightByVolume = weightByVolume
        self.forceWhiteLabels = forceWhiteLabels
        self.strongBorders = strongBorders
        self.labelDensity = labelDensity
        self.changeProvider = changeProvider
        self.onSelect = onSelect
        self.title = title
    }

    @Environment(\.dismiss) private var dismiss

    private enum SheetLayout: String, CaseIterable, Identifiable { case treemap, grid, bar; var id: String { rawValue } }
    @State private var layout: SheetLayout = .grid

    @AppStorage("heatmap.weightingCurve") private var weightingCurveRaw: String = WeightingCurve.balanced.rawValue
    private var weightingCurve: WeightingCurve { WeightingCurve(rawValue: weightingCurveRaw) ?? .balanced }

    private func weights(for tiles: [HeatMapTile]) -> [Double] {
        let exp = weightingCurve.exponent
        return tiles.map { tile in let base = weightByVolume ? max(tile.volume, 0) : max(tile.marketCap, 0); return pow(base, exp) }
    }

    @ViewBuilder private func heatMapContent() -> some View {
        switch layout {
        case .treemap:
            TreemapView(tiles: tiles, weights: weights(for: tiles), timeframe: timeframe, onTileTap: { t in onSelect(t); dismiss() }, changeProvider: changeProvider, showValues: showValues, weightByVolume: weightByVolume, boundOverride: bound, palette: palette, forceWhiteLabels: forceWhiteLabels, strongBorders: strongBorders, labelDensity: labelDensity)
                .frame(height: 420)
        case .grid:
            GridHeatMapView(tiles: tiles, timeframe: timeframe, onTileTap: { t in onSelect(t); dismiss() }, changeProvider: changeProvider, showValues: showValues, weightByVolume: weightByVolume, boundOverride: bound, palette: palette, forceWhiteLabels: forceWhiteLabels, strongBorders: strongBorders, labelDensity: labelDensity)
                .frame(height: 360)
        case .bar:
            WeightedHeatMapView(tiles: tiles, weights: weights(for: tiles), timeframe: timeframe, onTileTap: { t in onSelect(t); dismiss() }, changeProvider: changeProvider, showValues: showValues, weightByVolume: weightByVolume, boundOverride: bound, palette: palette, forceWhiteLabels: forceWhiteLabels, strongBorders: strongBorders, labelDensity: labelDensity, othersMode: .auto)
                .frame(height: 260)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    CapsuleChip(title: "Treemap", selected: layout == .treemap, size: .small, systemImage: "square.grid.3x3.fill") { layout = .treemap }
                    CapsuleChip(title: "Grid", selected: layout == .grid, size: .small, systemImage: "square.grid.2x2") { layout = .grid }
                    CapsuleChip(title: "Bar", selected: layout == .bar, size: .small, systemImage: "rectangle.split.3x1.fill") { layout = .bar }
                    Spacer()
                    if let date = lastUpdated { let rel = relativeUpdatedString(since: date); if !rel.isEmpty { Text(rel).font(.caption).foregroundStyle(.secondary) } }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 16)

                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    VStack(spacing: 8) {
                        heatMapContent()
                        LegendView(bound: bound, note: nil, palette: palette, timeframe: timeframe)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                    }
                    .padding(10)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 0)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CSNavButton(icon: "xmark", action: { dismiss() }, accessibilityText: "Close", compact: true)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
        }
    }
}

