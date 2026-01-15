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

// Local, robust change computation with fallbacks to avoid 0.0% on 1h
private func changeLocal(for tile: HeatMapTile, tf: HeatMapTimeframe) -> Double {
    switch tf {
    case .hour1:
        if let v = tile.pctChange1h, v.isFinite { return v }
        let d = tile.pctChange24h
        if d.isFinite { return d / 24.0 }
        if let w = tile.pctChange7d, w.isFinite { return w / (7.0 * 24.0) }
        return 0
    case .day1:
        let d = tile.pctChange24h
        if d.isFinite { return d }
        if let h = tile.pctChange1h, h.isFinite { return h * 24.0 }
        if let w = tile.pctChange7d, w.isFinite { return w / 7.0 }
        return 0
    case .day7:
        if let w = tile.pctChange7d, w.isFinite { return w }
        let d = tile.pctChange24h
        if d.isFinite { return d * 7.0 }
        if let h = tile.pctChange1h, h.isFinite { return h * 7.0 * 24.0 }
        return 0
    }
}

// Helper to detect synthetic "Others" tiles (supports suffixed IDs like "Others-87")
private func isOthersID(_ id: String) -> Bool { id.hasPrefix("Others") }

#if DEBUG
private enum HeatMapDebugLog {
    static var lastAt: Date = .distantPast
    static var lastKey: String = ""
    static let minInterval: TimeInterval = 2.0
}
#endif

// MARK: - Info bar shown when a tile is focused
private struct HeatMapInfoBar: View {
    let tile: HeatMapTile
    let timeframe: HeatMapTimeframe
    let capShare: Double?
    let volShare: Double?
    let changeProvider: ((HeatMapTile) -> Double)?
    var onClose: () -> Void
    var onTrade: () -> Void
    var onViewOthers: (() -> Void)? = nil

    private func formatCap(_ v: Double) -> String {
        switch v {
        case 1_000_000_000_000...: return String(format: "$%.1fT", v/1_000_000_000_000)
        case 1_000_000_000...: return String(format: "$%.1fB", v/1_000_000_000)
        case 1_000_000...: return String(format: "$%.1fM", v/1_000_000)
        default: return String(format: "$%.0f", v)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                let ch = (changeProvider?(tile)) ?? changeLocal(for: tile, tf: timeframe)
                Text(tile.symbol)
                    .font(.headline)
                Text(percentStringAdaptive(ch))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(ch >= 0 ? .green : .red)
                HStack(spacing: 12) {
                    Text("Cap: \(formatCap(tile.marketCap))").font(.caption)
                    Text("Vol: \(formatCap(tile.volume))").font(.caption)
                }
                .foregroundStyle(.secondary)
                if capShare != nil || volShare != nil {
                    HStack(spacing: 12) {
                        if let s = capShare { Text(String(format: "Share: %.1f%% cap", s * 100)).font(.caption) }
                        if let s = volShare { Text(String(format: "%.1f%% vol", s * 100)).font(.caption) }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isOthersID(tile.id), let onViewOthers {
                Button(action: { Haptics.light.impactOccurred(); onViewOthers() }) {
                    HStack(spacing: 6) { Text("View Coins"); Image(systemName: "list.bullet") }
                }
                .buttonStyle(GoldCapsuleButtonStyle(height: 34, horizontalPadding: 14))
            } else {
                Button(action: { Haptics.light.impactOccurred(); onTrade() }) {
                    HStack(spacing: 6) { Text("Trade"); Image(systemName: "arrow.right") }
                }
                .buttonStyle(GoldCapsuleButtonStyle(height: 34, horizontalPadding: 18))
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Market Heat Map Section (public)
public struct MarketHeatMapSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = HeatMapViewModel()
    @ObservedObject private var marketVM = MarketViewModel.shared
    @State private var selected: HeatMapTile? = nil

    private enum Layout: String, CaseIterable, Identifiable { case treemap, grid, bar; var id: String { rawValue } }
    private enum ScaleMode: String, CaseIterable, Identifiable { case perTimeframe, global, locked; var id: String { rawValue } }

    // Height helper to keep consistent layout across devices
    private func mapHeight(for layout: Layout) -> CGFloat {
        switch layout { case .treemap: return 220; case .grid: return 184; case .bar: return 168 }
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
    @AppStorage("heatmap.globalBound") private var globalBound: Double = 20
    @AppStorage("heatmap.lockedBound") private var lockedBound: Double = 20

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
    @AppStorage("heatmap.palette") private var paletteRaw: String = ColorPalette.warm.rawValue

    // Inserted auto-widen global flag
    @AppStorage("heatmap.autoWidenGlobal") private var autoWidenGlobal: Bool = true

    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    @State private var toastWorkItem: DispatchWorkItem? = nil

    @State private var showSettingsDropdown: Bool = false
    @State private var infoBarAutoHideWorkItem: DispatchWorkItem? = nil

    // Removed @State private var didForceBootstrapRefresh: Bool = false per instruction

    @State private var lastAutoWidenAt: Date? = nil

    @State private var showOthersSheet: Bool = false
    @State private var othersItems: [HeatMapTile] = []

    @State private var showAllGridSheet: Bool = false
    @State private var allGridItems: [HeatMapTile] = []

    // Pinch-to-scale states
    // Removed per instructions:
    // @State private var pinchStartBound: Double = 20
    // @State private var showScaleHUD: Bool = false
    // @State private var pinchActive: Bool = false
    @State private var animatedBound: Double = 20

    @State private var didSnapInitialBound: Bool = false

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

    private var processedTiles: [HeatMapTile] {
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

                #if DEBUG
                let placeholderUsed = rest.isEmpty || (capSum <= 0 && volSum <= 0)
                let key = "\(rest.count)|\(Int(visibleCap.rounded()))|\(Int(visibleVol.rounded()))|\(placeholderUsed ? 1 : 0)"
                let now = Date()
                if now.timeIntervalSince(HeatMapDebugLog.lastAt) >= HeatMapDebugLog.minInterval || HeatMapDebugLog.lastKey != key {
                    if placeholderUsed {
                        print("[HeatMap] Others synthesized placeholder — rest=\(rest.count), topCap=\(topCapSum), finalCap=\(finalCap), visibleCap=\(visibleCap), topVol=\(topVolSum), finalVol=\(finalVol), visibleVol=\(visibleVol)")
                    } else {
                        print("[HeatMap] Others aggregated from \(rest.count) coins — capSum=\(capSum), visibleCap=\(visibleCap), volSum=\(volSum), visibleVol=\(visibleVol)")
                    }
                    HeatMapDebugLog.lastAt = now
                    HeatMapDebugLog.lastKey = key
                }
                #endif

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

    // REPLACED weights function as per instructions
    private func weights(for tiles: [HeatMapTile]) -> [Double] {
        let exp = weightingCurve.exponent
        let baseWeights: [Double] = tiles.map { tile in
            let base = weightByVolume ? max(tile.volume, 0) : max(tile.marketCap, 0)
            return pow(base, exp)
        }
        // Cap the "Others" share so it cannot dominate the layout.
        guard let othersIndex = tiles.firstIndex(where: { isOthersID($0.id) || $0.symbol.hasPrefix("Others (") }) else {
            return baseWeights
        }
        var adjusted = baseWeights
        let sumNonOthers = adjusted.enumerated().filter { $0.offset != othersIndex }.reduce(0.0) { $0 + $1.element }
        // Hard cap: at most 30% of the total visual area for Others.
        let cap: Double = {
            if clampedTopN <= 16 { return 0.22 }
            else if clampedTopN <= 28 { return 0.24 }
            else if clampedTopN <= 48 { return 0.26 }
            else { return 0.28 }
        }()
        // We want W' <= cap * (S + W'), solve for W': W' <= cap*S / (1 - cap)
        let limit = (cap * sumNonOthers) / max(1e-9, (1.0 - cap))
        if adjusted[othersIndex] > limit {
            adjusted[othersIndex] = limit
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

    private var changeProvider: ((HeatMapTile) -> Double)? {
        guard normalizeByBTC else { return nil }
        let tiles = processedTiles
        if let btc = tiles.first(where: { $0.symbol.uppercased() == "BTC" }) {
            let ref = changeLocal(for: btc, tf: timeframe)
            return { tile in changeLocal(for: tile, tf: timeframe) - ref }
        }
        return nil
    }

    // Added helper functions after changeProvider
    private func defaultCap(for timeframe: HeatMapTimeframe) -> Double {
        switch timeframe {
        case .hour1: return 5
        case .day1:  return 20
        case .day7:  return 50
        }
    }

    private func scaleStep(for timeframe: HeatMapTimeframe) -> Double {
        switch timeframe {
        case .hour1: return 0.2
        case .day1:  return 0.5
        case .day7:  return 1.0
        }
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

    // REPLACED autoBound function per instructions
    private func autoBound(for timeframe: HeatMapTimeframe, tiles: [HeatMapTile]) -> Double {
        let defaultB = bound(for: timeframe)
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
            return sorted.last!.mag
        }

        let p50 = wPercentile(0.50)
        let p80 = wPercentile(0.80)
        let p90 = wPercentile(0.90)
        let p95 = wPercentile(0.95)
        let p98 = wPercentile(0.98)

        // Weighted Median Absolute Deviation (MAD) around the median
        let devs = sorted.map { (d: abs($0.mag - p50), w: $0.w) }.sorted { $0.d < $1.d }
        let totalW2 = devs.reduce(0.0) { $0 + $1.w }
        var cum2: Double = 0
        var mad: Double = devs.last!.d
        let target2 = 0.50 * totalW2
        for e in devs { cum2 += e.w; if cum2 >= target2 { mad = e.d; break } }
        let robustCap = p50 + 3.0 * mad // ~3-sigma robust cap

        // Timeframe-tuned p80 factor (keeps scale responsive without being too tight)
        let p80Factor: Double
        switch timeframe {
        case .hour1: p80Factor = 1.10
        case .day1:  p80Factor = 1.20
        case .day7:  p80Factor = 1.30
        }

        // Target a range between a lower (>= p90) and an upper (<= p98 & robust cap) to reduce hard clipping
        let lower = max(p90, p80 * p80Factor)
        let upper = min(p98, robustCap * 1.05)
        var candidate = min(defaultB, max(lower, min(upper, p95)))

        // Timeframe-specific minimum floors (lower when normalizing to BTC)
        let minFloor: Double
        switch timeframe {
        case .hour1: minFloor = normalizeByBTC ? 0.6 : 0.9
        case .day1:  minFloor = normalizeByBTC ? 2.0 : 2.5
        case .day7:  minFloor = normalizeByBTC ? 4.5 : 6.0
        }
        let floorB = min(defaultB, minFloor)

        // Respect floor, then snap to friendly steps per timeframe
        let step: Double
        switch timeframe { case .hour1: step = 0.2; case .day1: step = 0.5; case .day7: step = 1.0 }
        @inline(__always) func snap(_ x: Double, step: Double) -> Double { (x / step).rounded() * step }
        let raw = max(floorB, candidate)
        var snapped = snap(raw, step: step)

        // Anti-saturation guard: if too much weight lies beyond the bound, widen by one step (but never past default cap)
        let overWeight = pairs.reduce(0.0) { $0 + (($1.mag > snapped) ? $1.w : 0.0) }
        let overShare = overWeight / max(1e-9, totalW)
        if overShare >= 0.06 { // ~6% of weighted market saturating is a bit much visually
            snapped = min(defaultB, snapped + step)
        }

        return min(defaultB, max(floorB, snapped))
    }

    private func targetBound(for tiles: [HeatMapTile]) -> Double {
        switch ScaleMode(rawValue: scaleModeRaw) ?? .perTimeframe {
        case .locked:
            return lockedBound
        case .global:
            return globalBound
        case .perTimeframe:
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
        case .perTimeframe: parts.append("Auto scale (robust)")
        }
        return parts.joined(separator: " • ")
    }

    private var tilesSignature: String {
        currentTiles.map { $0.id }.joined(separator: ",")
    }

    // Clamp user-configured topN to a sane range to avoid pathological layouts
    private var clampedTopN: Int { max(1, min(100, topN)) }

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
                    labelDensity: labelDensity
                )
                .padding(.bottom, 4)
                .frame(height: mapHeight(for: .treemap))
                .id("\(timeframe.rawValue)-\(scaleModeRaw)-\(normalizeByBTC)-\(tilesVal.map { $0.id }.joined(separator: ","))")
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
                .id("\(timeframeRaw)-\(scaleModeRaw)-\(normalizeByBTC)-\(tilesVal.map { $0.id }.joined(separator: ","))")
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
                    maxBars: clampedTopN,
                    othersMode: .auto
                )
                .padding(.bottom, 4)
                .frame(height: mapHeight(for: .bar))
                .id("\(timeframeRaw)-\(scaleModeRaw)-\(normalizeByBTC)-\(tilesVal.map { $0.id }.joined(separator: ","))")
            )
        }
    }

    private func infoBarOverlayView(tilesVal: [HeatMapTile], timeframe: HeatMapTimeframe) -> AnyView {
        if let t = focusTile {
            let totalCap = tilesVal.filter { !isOthersID($0.id) }.reduce(0.0) { $0 + $1.marketCap }
            let totalVol = tilesVal.filter { !isOthersID($0.id) }.reduce(0.0) { $0 + $1.volume }
            let capS: Double? = (isOthersID(t.id) || totalCap <= 0) ? nil : t.marketCap / totalCap
            let volS: Double? = (isOthersID(t.id) || totalVol <= 0) ? nil : t.volume / totalVol
            let onCloseBar: () -> Void = { withAnimation { focusTile = nil } }
            let onTradeBar: () -> Void = { if !isOthersID(t.id) { handleTap(t) } }
            let onViewOthersBar: (() -> Void)? = isOthersID(t.id) ? { othersItems = othersConstituents(); showOthersSheet = true } : nil

            return AnyView(
                HeatMapInfoBar(
                    tile: t,
                    timeframe: timeframe,
                    capShare: capS,
                    volShare: volS,
                    changeProvider: changeProvider,
                    onClose: onCloseBar,
                    onTrade: onTradeBar,
                    onViewOthers: onViewOthersBar
                )
                .padding(12)
                .transition(AnyTransition.opacity.combined(with: AnyTransition.move(edge: .bottom)))
                .zIndex(1000)
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
                    if viewModel.tiles.isEmpty {
                        HeatMapShimmerPlaceholder(height: mapHeight(for: selectedLayout))
                            .padding(.vertical, 6)
                    } else {
                        let weightsVal: [Double] = weights(for: tilesVal)
                        let selectedIDVal: String? = focusTile?.id
                        let onTapTile: (HeatMapTile) -> Void = { tile in
                            focusTile = tile
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
                        LegendView(bound: boundVal, note: nil, palette: paletteVal)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 0)
                        Color.clear
                            .frame(height: 0)
                            .onAppear { animatedBound = targetBoundVal }
                            .onChange(of: targetBoundVal) { new in smoothSetAnimatedBound(to: new) }
                    }
                }
                .padding(8)
                .padding(.top, 0)
                .overlay(dimmingOverlayView())
                // Removed the on-map scale HUD overlay:
                //.overlay(scaleHUDOverlay(boundVal: boundVal), alignment: .topTrailing)
                .contentShape(Rectangle())
                // Removed pinch-to-lock gesture:
                /*
                .simultaneousGesture(
                    pinchGesture(),
                    including: .gesture
                )
                */
            }
            // Removed loading hint overlay per instructions:
            /*
            .overlay(alignment: .topLeading) {
                let minRequired = max(12, clampedTopN / 2)
                let nonOthersCount = tilesVal.filter { !isOthersID($0.id) }.count
                if nonOthersCount < minRequired {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.8)
                        Text("Loading full market…")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.8))
                    .padding(10)
                }
            }
            */
            .overlay(
                Group {
                    infoBarOverlayView(tilesVal: tilesVal, timeframe: timeframe)
                }, alignment: .bottomLeading
            )
        )
    }

    @ViewBuilder
    private func settingsSheetScrollView() -> some View {
        ScrollView {
            let weightingCurveBinding = Binding<WeightingCurve>(get: { weightingCurve }, set: { weightingCurveRaw = $0.rawValue })
            let labelDensityBinding = Binding<LabelDensity>(get: { labelDensity }, set: { labelDensityRaw = $0.rawValue })
            let paletteBinding = Binding<ColorPalette>(get: { ColorPalette(rawValue: paletteRaw) ?? .cool }, set: { newVal in paletteRaw = newVal.rawValue })

            // Inserted Bindings
            // Removed lockBinding and manualBoundBinding per instructions

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
                palette: paletteBinding,
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
        OthersListSheet(
            tiles: othersItems,
            timeframe: timeframe,
            lastUpdated: viewModel.lastUpdated,
            changeProvider: changeProvider,
            onSelect: { tile in selected = tile }
        )
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
                Button("Trade") {
                    handleTap(t)
                }
            }
        }
        Button("Cancel", role: .cancel) { }
    }

    private var dialogTitle: String { actionTile?.symbol ?? "Actions" }

    @ViewBuilder
    private func tradeSheetView(tile: HeatMapTile) -> some View {
        TradeView(symbol: tile.symbol, showBackButton: true)
            .environmentObject(MarketViewModel.shared)
    }

    // Added helper function for smoothed animatedBound updates
    private func smoothSetAnimatedBound(to new: Double) {
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
            withAnimation(.easeInOut(duration: 0.2)) { animatedBound = new }
            return
        }
        // Otherwise, blend toward the target
        let alpha = 0.35 // take ~35% of the jump per update
        let blended = alpha * new + (1 - alpha) * animatedBound
        withAnimation(.easeInOut(duration: 0.2)) { animatedBound = blended }
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
    
    // Removed entire maybeForceBootstrapRefreshIfSmall function per instructions
    
    private func resetHeatMapDefaults() {
        // Visual & data defaults (match the original look and improve readability)
        layoutRaw = Layout.treemap.rawValue
        timeframeRaw = HeatMapTimeframe.day1.rawValue

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

        // Bounds: clamp to a safe, finite value and defer animated update to avoid transient layout churn
        let base = bound(for: .day1)
        let safeBound = max(2.0, min(100.0, base.isFinite ? base : 20.0))
        globalBound = safeBound
        lockedBound = safeBound

        DispatchQueue.main.async { smoothSetAnimatedBound(to: safeBound) }

        // Badges
        showMoverBadges = false
        moverBadgeCount = 2

        // Clear selection to avoid overlay layout during reset
        focusTile = nil
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
                                Haptics.light.impactOccurred(); timeframeRaw = tf.rawValue
                            }
                        }
                    }
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 14).cornerRadius(1)
                    HStack(spacing: 6) {
                        CapsuleChip(title: "Treemap", selected: selectedLayout == .treemap, size: .small, systemImage: "square.grid.3x3.fill") { Haptics.light.impactOccurred(); layoutRaw = Layout.treemap.rawValue }
                        CapsuleChip(title: "Grid", selected: selectedLayout == .grid, size: .small, systemImage: "square.grid.2x2") { Haptics.light.impactOccurred(); layoutRaw = Layout.grid.rawValue }
                        CapsuleChip(title: "Bar", selected: selectedLayout == .bar, size: .small, systemImage: "rectangle.split.3x1.fill") { Haptics.light.impactOccurred(); layoutRaw = Layout.bar.rawValue }
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { Haptics.light.impactOccurred(); withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { showSettingsDropdown.toggle() } } label: {
                ZStack {
                    Circle()
                        .fill(colorScheme == .dark ? BrandColors.goldVertical : BrandColors.goldVerticalLight)
                        .overlay(colorScheme == .dark ? Circle().inset(by: 0.6).stroke(BrandColors.goldStrokeHighlight, lineWidth: 0.8) : nil)
                        .overlay(colorScheme == .dark ? Circle().stroke(BrandColors.goldStrokeShadow, lineWidth: 0.6) : Circle().stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 0.8))
                        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.25) : Color.clear, radius: 3, x: 0, y: 1)
                    Image(systemName: "slider.horizontal.3")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.black.opacity(0.92))
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
    // <-- MODIFIED controlBarView END

    // Removed per instructions:
    /*
    private func scaleHUDOverlay(boundVal: Double) -> AnyView {
        if showScaleHUD {
            return AnyView(
                Text("±\(Int(boundVal))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.12))
                    .padding(10)
                    .transition(AnyTransition.opacity.combined(with: AnyTransition.scale))
            )
        } else {
            return AnyView(EmptyView())
        }
    }
    */

    // Removed per instructions:
    /*
    private func pinchGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if !pinchActive {
                    if abs(scale - 1.0) < 0.08 { return }
                    pinchActive = true
                    pinchStartBound = animatedBound
                    scaleModeRaw = ScaleMode.locked.rawValue
                    showScaleHUD = true
                }
                let newBound = max(2.0, min(100.0, pinchStartBound * Double(scale)))
                animatedBound = newBound
                lockedBound = newBound
            }
            .onEnded { _ in
                if pinchActive { lockedBound = animatedBound }
                pinchActive = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    withAnimation(.easeOut(duration: 0.2)) { showScaleHUD = false }
                }
            }
    }
    */

    // MARK: - Body
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let boundVal = animatedBound
            let paletteVal = currentPalette
            let tilesVal = currentTiles
            let targetBoundVal = currentTargetBound

            controlBarView()

            mapCard(tilesVal: tilesVal, boundVal: boundVal, paletteVal: paletteVal, targetBoundVal: targetBoundVal)
        }
        // Replaced .onAppear with force refresh per instructions
        .onAppear { viewModel.forceRefresh(reason: "section appear") }
        .onChange(of: timeframeRaw) { _ in
            // Removed didForceBootstrapRefresh reset and fetchData() replaced with forceRefresh
            viewModel.forceRefresh(reason: "timeframe change")
            // Snap to the new target bound on timeframe change to keep colors consistent immediately
            animatedBound = currentTargetBound
            maybeAutoWidenGlobal(tiles: currentTiles)
        }
        .onChange(of: viewModel.tiles.count) { newCount in
            if !didSnapInitialBound && newCount > 0 {
                // First real dataset: snap so initial colors match the final auto-scale
                animatedBound = currentTargetBound
                didSnapInitialBound = true
            } else {
                smoothSetAnimatedBound(to: currentTargetBound)
            }
            maybeAutoWidenGlobal(tiles: currentTiles)
            // Removed maybeForceBootstrapRefreshIfSmall() call per instructions
        }
        .onChange(of: viewModel.lastUpdated) { _ in
            if !didSnapInitialBound && !viewModel.tiles.isEmpty {
                animatedBound = currentTargetBound
                didSnapInitialBound = true
            } else {
                smoothSetAnimatedBound(to: currentTargetBound)
            }
            maybeAutoWidenGlobal(tiles: currentTiles)
            // Removed maybeForceBootstrapRefreshIfSmall() call per instructions
        }
        .onChange(of: followLiveUpdates) { v in viewModel.setFollowLiveUpdates(v) }
        .onChange(of: minUpdateSeconds) { v in viewModel.setMinAdoptionInterval(v) }
        .onChange(of: autoRefreshEnabled) { v in viewModel.updateAutoRefreshTimer(enabled: v) }
        .onChange(of: scaleModeRaw) { _ in smoothSetAnimatedBound(to: currentTargetBound) }
        .onChange(of: globalBound) { _ in if (ScaleMode(rawValue: scaleModeRaw) == .global) { smoothSetAnimatedBound(to: globalBound) } }
        .onChange(of: lockedBound) { _ in if (ScaleMode(rawValue: scaleModeRaw) == .locked) { smoothSetAnimatedBound(to: lockedBound) } }
        .onChange(of: paletteRaw) { newRaw in if ColorPalette(rawValue: newRaw) == .warm { grayNeutral = false } }
        .onChange(of: normalizeByBTC) { _ in smoothSetAnimatedBound(to: currentTargetBound); maybeAutoWidenGlobal(tiles: currentTiles) }
        .onChange(of: topN) { _ in
            // Replaced fetchData with forceRefresh per instructions
            viewModel.forceRefresh(reason: "topN change")
            smoothSetAnimatedBound(to: currentTargetBound)
            maybeAutoWidenGlobal(tiles: currentTiles)
        }
        .onChange(of: includeOthers) { _ in
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                animatedBound = currentTargetBound
            }
            maybeAutoWidenGlobal(tiles: currentTiles)
        }
        .onChange(of: tilesSignature) { _ in
            smoothSetAnimatedBound(to: currentTargetBound)
        }
        .onChange(of: weightByVolume) { _ in
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                animatedBound = currentTargetBound
            }
            maybeAutoWidenGlobal(tiles: currentTiles)
        }
        .onChange(of: filterStables) { _ in
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                animatedBound = currentTargetBound
            }
            maybeAutoWidenGlobal(tiles: currentTiles)
        }
        .onChange(of: pinBTC) { _ in
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                animatedBound = currentTargetBound
            }
            maybeAutoWidenGlobal(tiles: currentTiles)
        }
        .sheet(isPresented: $showSettingsDropdown) {
            NavigationStack {
                settingsSheetScrollView()
                    .navigationTitle("Heat Map Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showSettingsDropdown = false } } }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selected) { tile in
            tradeSheetView(tile: tile)
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
        .animation(.snappy, value: selectedLayout)
        .overlay(toastOverlay(), alignment: .bottom)
    }

    private func handleTap(_ tile: HeatMapTile) { selected = tile }
    @State private var actionTile: HeatMapTile? = nil
    @State private var showActions: Bool = false
    private func presentActions(for tile: HeatMapTile) { actionTile = tile; showActions = true }
}

// MARK: - CapsuleChip used in control bars
private enum ChipSize { case regular, small }
private struct CapsuleChip: View {
    let title: String
    let selected: Bool
    let size: ChipSize
    let systemImage: String?
    let action: () -> Void

    init(title: String, selected: Bool, size: ChipSize, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.selected = selected; self.size = size; self.systemImage = systemImage; self.action = action
    }

    var body: some View {
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
            .foregroundColor(selected ? Color.black.opacity(0.96) : DS.Adaptive.textPrimary)
            .background(
                Group {
                    if selected {
                        Capsule()
                            .fill(chipGoldGradient)
                            .overlay(LinearGradient(colors: [Color.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center).clipShape(Capsule()))
                            .overlay(Capsule().stroke(ctaRimStrokeGradient, lineWidth: 0.8))
                            .overlay(ctaBottomShade(height: height).clipShape(Capsule()))
                    } else {
                        DS.Adaptive.chipBackground
                    }
                }
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
            .overlay(Capsule().stroke(selected ? Color.clear : DS.Adaptive.strokeStrong, lineWidth: 0.8))
            .shadow(color: (selected ? DS.Colors.gold.opacity(0.22) : Color.clear), radius: selected ? 6 : 0, x: 0, y: 2)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Shimmer placeholder and Toast
private struct ShimmerView: View {
    @State private var animate = false
    var body: some View {
        ZStack {
            DS.Adaptive.chipBackground
            LinearGradient(colors: [Color.clear, DS.Adaptive.strokeStrong, Color.clear], startPoint: .leading, endPoint: .trailing)
                .offset(x: animate ? 240 : -240)
        }
        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: animate)
        .onAppear { animate = true }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct HeatMapShimmerPlaceholder: View {
    let height: CGFloat
    var body: some View {
        ShimmerView()
            .frame(height: height)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 16)
    }
}

private struct HeatMapToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill").foregroundColor(.yellow)
            Text(text).font(.subheadline.weight(.semibold)).foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
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
    var palette: Binding<ColorPalette>

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
            palette: palette,
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
            .navigationTitle("Others")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let date = lastUpdated { let rel = relativeUpdatedString(since: date); if !rel.isEmpty { Text(rel).font(.caption).foregroundStyle(.secondary) } }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
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
                    if let date = lastUpdated { let rel = relativeUpdatedString(since: date); if !rel.isEmpty { Text(rel).font(.caption).foregroundStyle(.secondary) } }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
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

    init(tiles: [HeatMapTile], timeframe: HeatMapTimeframe, bound: Double, lastUpdated: Date?, palette: ColorPalette, showValues: Bool, weightByVolume: Bool, forceWhiteLabels: Bool, strongBorders: Bool, labelDensity: LabelDensity, changeProvider: ((HeatMapTile) -> Double)?, onSelect: @escaping (HeatMapTile) -> Void) {
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
                        LegendView(bound: bound, note: nil, palette: palette)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                    }
                    .padding(10)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 0)
            }
            .navigationTitle("All Coins Heat Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

