import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct WeightedHeatMapView: View {
    public enum OthersMode { case auto, never }

    public let tiles: [HeatMapTile]
    public let weights: [Double]
    public let timeframe: HeatMapTimeframe
    public var selectedID: String? = nil
    public var onTileTap: ((HeatMapTile) -> Void)? = nil
    public var onTileLongPress: ((HeatMapTile) -> Void)? = nil

    public var changeProvider: ((HeatMapTile) -> Double)? = nil
    public var showValues: Bool = false
    public var weightByVolume: Bool = false
    public var boundOverride: Double? = nil
    public var palette: ColorPalette = .cool
    public var forceWhiteLabels: Bool = false
    public var highlightColors: [String: Color] = [:]
    public var strongBorders: Bool = false
    public var labelDensity: LabelDensity = .normal
    public var maxBars: Int = 30
    public var othersMode: OthersMode = .never

    public init(
        tiles: [HeatMapTile],
        weights: [Double],
        timeframe: HeatMapTimeframe,
        selectedID: String? = nil,
        onTileTap: ((HeatMapTile) -> Void)? = nil,
        onTileLongPress: ((HeatMapTile) -> Void)? = nil,
        changeProvider: ((HeatMapTile) -> Double)? = nil,
        showValues: Bool = false,
        weightByVolume: Bool = false,
        boundOverride: Double? = nil,
        palette: ColorPalette = .cool,
        forceWhiteLabels: Bool = false,
        highlightColors: [String: Color] = [:],
        strongBorders: Bool = false,
        labelDensity: LabelDensity = .normal,
        maxBars: Int = 30,
        othersMode: OthersMode = .never
    ) {
        self.tiles = tiles
        self.weights = weights
        self.timeframe = timeframe
        self.selectedID = selectedID
        self.onTileTap = onTileTap
        self.onTileLongPress = onTileLongPress
        self.changeProvider = changeProvider
        self.showValues = showValues
        self.weightByVolume = weightByVolume
        self.boundOverride = boundOverride
        self.palette = palette
        self.forceWhiteLabels = forceWhiteLabels
        self.highlightColors = highlightColors
        self.strongBorders = strongBorders
        self.labelDensity = labelDensity
        self.maxBars = maxBars
        self.othersMode = othersMode
    }

    // MEMORY FIX v8: Memoize aggregateDisplay() results. This function creates dozens of
    // arrays during weight redistribution and capping. Cache the result and only recompute
    // when tile IDs, weights, or container width change.
    @State private var cachedAgg: (tiles: [HeatMapTile], weights: [Double])?
    @State private var cachedAggKey: String = ""
    
    private func aggKey(width: CGFloat) -> String {
        let tileHash = tiles.prefix(20).map { $0.id }.joined(separator: ",")
        let weightHash = weights.prefix(20).map { String(format: "%.0f", $0) }.joined(separator: ",")
        return "\(tileHash)|\(weightHash)|\(Int(width))|\(maxBars)"
    }
    
    public var body: some View {
        GeometryReader { geo in
            let rawCount = min(tiles.count, weights.count)
            // SPACING FIX: Subtle separation between bars for professional look
            // 1.5pt creates clean visual distinction without visible gutters
            let spacing: CGFloat = 1.5
            let useTiles = Array(tiles.prefix(rawCount))
            let useWeights = Array(weights.prefix(rawCount).map { max(0, $0) })

            // MEMORY FIX v8: Use cached aggregation if inputs unchanged
            let key = aggKey(width: geo.size.width)
            let agg: (tiles: [HeatMapTile], weights: [Double]) = {
                if key == cachedAggKey, let cached = cachedAgg {
                    return cached
                }
                let computed = aggregateDisplay(tiles: useTiles, weights: useWeights, containerWidth: geo.size.width, spacing: spacing, maxBars: maxBars, othersMode: othersMode)
                DispatchQueue.main.async {
                    cachedAggKey = key
                    cachedAgg = computed
                }
                return computed
            }()
            let displayTiles = agg.tiles
            let displayWeights = agg.weights
            let totalDisplay = max(1e-9, displayWeights.reduce(0, +))
            // Recompute available width based on final bar count
            let totalSpacing = spacing * CGFloat(max(0, displayTiles.count - 1))
            let availableWidth = max(1, geo.size.width - totalSpacing)

            if displayTiles.isEmpty {
                Color.clear
            } else {
                HStack(spacing: spacing) {
                    ForEach(Array(displayTiles.enumerated()), id: \.1.id) { idx, tile in
                        let w = CGFloat(displayWeights[idx] / totalDisplay) * availableWidth
                        Button {
                            Haptics.light.impactOccurred()
                            onTileTap?(tile)
                        } label: {
                            GeometryReader { proxy in
                                let w = max(0, proxy.size.width)
                                let h = max(0, proxy.size.height)
                                if w.isFinite && h.isFinite && w > 0.01 && h > 0.01 {
                                    BarTile(
                                        tile: tile,
                                        timeframe: timeframe,
                                        selected: selectedID == tile.id,
                                        changeProvider: changeProvider,
                                        showValues: showValues,
                                        weightByVolume: weightByVolume,
                                        boundOverride: boundOverride,
                                        palette: palette,
                                        forceWhiteLabels: forceWhiteLabels,
                                        highlight: highlightColors[tile.id],
                                        strongBorders: strongBorders,
                                        labelDensity: labelDensity,
                                        onLongPress: { onTileLongPress?(tile) }
                                    )
                                    // SMOOTH TRANSITION: Use stable tile identity so SwiftUI can
                                    // animate color changes when timeframe/data updates occur.
                                    // Colors crossfade through neutral which looks professional.
                                    .id("\(tile.id)-\(palette.rawValue)")
                                } else {
                                    Color.clear
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.4)
                                .onEnded { _ in Haptics.medium.impactOccurred(); onTileLongPress?(tile) }
                        )
                        .frame(width: max(1, w))
                    }
                }
            }
        }
    }

    // MARK: - Aggregation helper keeps heavy control flow out of ViewBuilder
    private func aggregateDisplay(tiles: [HeatMapTile], weights: [Double], containerWidth: CGFloat, spacing: CGFloat, maxBars: Int, othersMode: OthersMode) -> (tiles: [HeatMapTile], weights: [Double]) {
        let count = min(tiles.count, weights.count)
        guard count > 0 else { return ([], []) }
        let useTiles = Array(tiles.prefix(count))
        let useWeights = Array(weights.prefix(count).map { max(0, $0) })

        // Compute base metrics against the full list, but space as if we'll show at most maxBars
        _ = max(1e-9, useWeights.reduce(0, +))
        let totalSpacing = spacing * CGFloat(max(0, min(count, maxBars) - 1))
        let availableWidth = max(1, containerWidth - totalSpacing)

        // Threshold for micro bars (avoid ultra-thin slivers). Adaptive to container and bar count.
        // BAR LAYOUT FIX: Balanced minimum - allows more bars while still being readable
        let barsTarget = max(1, min(count, maxBars))
        let avgWidth = availableWidth / CGFloat(barsTarget)
        let minBarPx: CGFloat = max(24, min(32, avgWidth * 0.35))

        var mainTiles: [HeatMapTile] = []
        var mainWeights: [Double] = []

        var othersCount = 0
        var othersWeightSum: Double = 0
        var othersCap: Double = 0
        var othersVol: Double = 0
        // Track weighted sums for ALL timeframes to avoid black tiles when switching
        var othersWeighted1hSum: Double = 0
        var othersWeighted24hSum: Double = 0
        var othersWeighted7dSum: Double = 0
        var othersWeightBaseSum: Double = 0

        func addToOthers(tile t: HeatMapTile, weight w: Double) {
            var addCount = 1
            let s = t.symbol
            if s.hasPrefix("Others ("), s.hasSuffix(")") {
                let start = s.index(s.startIndex, offsetBy: 8)
                let end = s.index(before: s.endIndex)
                addCount = Int(s[start..<end]) ?? 1
            }
            othersCount += addCount
            othersWeightSum += w
            othersCap += t.marketCap
            othersVol += t.volume
            let base = weightByVolume ? t.volume : t.marketCap
            
            // Calculate weighted changes for all three timeframes
            let raw1h = t.pctChange1h ?? 0
            let raw24h = t.pctChange24h
            let raw7d = t.pctChange7d ?? 0
            
            let ch1h = (raw1h.isFinite && abs(raw1h) <= 10_000) ? raw1h : 0
            let ch24h = (raw24h.isFinite && abs(raw24h) <= 10_000) ? raw24h : 0
            let ch7d = (raw7d.isFinite && abs(raw7d) <= 10_000) ? raw7d : 0
            
            othersWeighted1hSum += ch1h * base
            othersWeighted24hSum += ch24h * base
            othersWeighted7dSum += ch7d * base
            othersWeightBaseSum += base
        }

        // Always keep top coins by weight. If .auto, keep (maxBars - 1) + Others; if .never, keep maxBars and drop Others entirely.
        let showOthers = (othersMode == .auto)
        let mainLimit = showOthers ? max(1, maxBars - 1) : maxBars
        let sortedIndices = Array(0..<useTiles.count).sorted { useWeights[$0] > useWeights[$1] }
        for (rank, i) in sortedIndices.enumerated() {
            let t = useTiles[i]
            let w = useWeights[i]

            // Treat any preexisting "Others" specially: fold when .auto, skip when .never
            if t.id == "Others" || t.symbol.hasPrefix("Others (") {
                if showOthers { addToOthers(tile: t, weight: w) }
                continue
            }

            if rank < mainLimit {
                mainTiles.append(t)
                mainWeights.append(w)
            } else {
                if showOthers {
                    addToOthers(tile: t, weight: w)
                } else {
                    // .never: drop extras beyond the top maxBars
                }
            }
        }

        // Second pass: ensure every displayed bar meets a minimum pixel width by moving the smallest bars into Others
        if othersMode == .auto {
            do {
                var guardCount = 0
                while true {
                    // Never drop below the target number of main tiles
                    if mainTiles.count <= mainLimit { break }

                    // How many bars would be shown if we appended Others now?
                    let prospectiveCount = mainTiles.count + (othersCount > 0 ? 1 : 0)
                    if prospectiveCount <= 0 { break }
                    let totalSpacingLocal = spacing * CGFloat(max(0, prospectiveCount - 1))
                    let availableWidthLocal = max(1, containerWidth - totalSpacingLocal)

                    var currentWeights = mainWeights
                    if othersCount > 0 { currentWeights.append(othersWeightSum) }

                    let totalCurrent = max(1e-9, currentWeights.reduce(0, +))
                    let widths = currentWeights.map { CGFloat($0 / totalCurrent) * availableWidthLocal }

                    // Enforce a gentle floor - allow narrower bars to show more coins
                    let floorPx = max(minBarPx * 0.7, 14)

                    // Find the smallest non-Others bar that violates the floor
                    var idxToMove: Int? = nil
                    var minWidth: CGFloat = .greatestFiniteMagnitude
                    for i in 0..<mainTiles.count {
                        let w = widths[i]
                        if w < floorPx && w < minWidth {
                            idxToMove = i
                            minWidth = w
                        }
                    }

                    guard let move = idxToMove else { break }
                    // Move this bar into the Others pool
                    let t = mainTiles.remove(at: move)
                    let w = mainWeights.remove(at: move)
                    addToOthers(tile: t, weight: w)

                    // Prevent pathological loops
                    guardCount += 1
                    if guardCount > 64 { break }
                }
            }
        }

        // Merge Others (if any) and guarantee it's appended once at the end
        if othersMode == .auto && othersCount > 0 {
            // Calculate weighted average for ALL timeframes to prevent black tiles
            let merged1h = othersWeightBaseSum > 0 ? (othersWeighted1hSum / othersWeightBaseSum) : 0
            let merged24h = othersWeightBaseSum > 0 ? (othersWeighted24hSum / othersWeightBaseSum) : 0
            let merged7d = othersWeightBaseSum > 0 ? (othersWeighted7dSum / othersWeightBaseSum) : 0
            let othersTile = HeatMapTile(
                id: "Others",
                symbol: "Others (\(othersCount))",
                pctChange24h: merged24h,
                marketCap: othersCap,
                volume: othersVol,
                pctChange1h: merged1h,
                pctChange7d: merged7d
            )

            // If an Others somehow slipped into mainTiles, merge it with weighted averages
            if let idx = mainTiles.firstIndex(where: { $0.id == "Others" || $0.symbol.hasPrefix("Others (") }) {
                let existing = mainTiles[idx]
                
                // MERGE FIX: Combine existing "Others" data with new tiles using weighted average
                let existingWeight = weightByVolume ? existing.volume : existing.marketCap
                let totalWeight = existingWeight + othersWeightBaseSum
                
                let combined1h: Double? = {
                    if totalWeight <= 0 { return nil }
                    let existingVal = existing.pctChange1h ?? 0
                    return (existingVal * existingWeight + othersWeighted1hSum) / totalWeight
                }()
                
                let combined24h: Double = {
                    if totalWeight <= 0 { return 0 }
                    return (existing.pctChange24h * existingWeight + othersWeighted24hSum) / totalWeight
                }()
                
                let combined7d: Double? = {
                    if totalWeight <= 0 { return nil }
                    let existingVal = existing.pctChange7d ?? 0
                    return (existingVal * existingWeight + othersWeighted7dSum) / totalWeight
                }()
                
                mainTiles[idx] = HeatMapTile(
                    id: "Others",
                    symbol: othersTile.symbol,
                    pctChange24h: combined24h,
                    marketCap: existing.marketCap + othersTile.marketCap,
                    volume: existing.volume + othersTile.volume,
                    pctChange1h: combined1h,
                    pctChange7d: combined7d
                )
                mainWeights[idx] += othersWeightSum
            } else {
                mainTiles.append(othersTile)
                mainWeights.append(othersWeightSum)
            }
        }

        // Soft-cap dominance so BTC/ETH (or the top two) don't swallow the bar
        var weightsCapped = mainWeights
        func cap(_ idx: Int, to maxRatio: Double) {
            guard idx < weightsCapped.count else { return }
            let total = max(1e-9, weightsCapped.reduce(0, +))
            let current = weightsCapped[idx]
            let ratio = current / total
            guard ratio > maxRatio else { return }
            let capped = maxRatio * total
            let delta = current - capped
            weightsCapped[idx] = capped
            // Redistribute delta proportionally across the other bars
            let othersSum = max(1e-9, total - current)
            for j in 0..<weightsCapped.count where j != idx {
                let share = weightsCapped[j] / othersSum
                weightsCapped[j] += delta * share
            }
        }
        // BAR LAYOUT FIX: Reduced caps to prevent BTC/ETH from dominating
        // Previous: 36% + 24% = 60% for top 2, leaving only 40% for rest
        // New: 25% + 18% = 43% for top 2, leaving 57% for better label visibility
        cap(0, to: 0.25)
        cap(1, to: 0.18)

        // Cap the Others bar so it cannot dominate or crowd neighbors
        if let idx = mainTiles.firstIndex(where: { $0.id == "Others" || $0.symbol.hasPrefix("Others (") }) {
            let total = max(1e-9, weightsCapped.reduce(0, +))
            let current = weightsCapped[idx]
            // Adaptive max share for Others by bar count
            let n = mainTiles.count
            // Update othersMinPx from 26 to 32 in readability boost block below, so here is unchanged
            let maxShare: Double = (n <= 8 ? 0.20 : (n <= 12 ? 0.24 : 0.26))
            // Also keep Others below ~86% of the largest named bar
            let maxNonOthers = weightsCapped.enumerated().filter { $0.offset != idx }.map { $0.element }.max() ?? 0
            let relCap = 0.86 * maxNonOthers
            let shareCap = maxShare * total
            let allowed = min(shareCap, relCap)
            if current > allowed && allowed > 0 {
                let delta = current - allowed
                weightsCapped[idx] = allowed
                let denom = max(1e-9, total - current)
                for j in 0..<weightsCapped.count where j != idx {
                    let share = weightsCapped[j] / denom
                    weightsCapped[j] += delta * share
                }
            }
        }

        var finalWeights = weightsCapped

        // In .never mode, enforce a minimum bar width by gently rebalancing shares (no Others tile).
        if othersMode == .never && !mainTiles.isEmpty {
            let n = mainTiles.count
            let totalSpacingLocal = spacing * CGFloat(max(0, n - 1))
            let availableWidthLocal = max(1, containerWidth - totalSpacingLocal)
            let totalFinal = max(1e-9, finalWeights.reduce(0, +))
            let shares = finalWeights.map { $0 / totalFinal }

            // Minimum width floor as a share of available width
            let floorPx: CGFloat = 14
            var floorShare = min(0.22, Double(floorPx / availableWidthLocal))
            if floorShare * Double(n) > 1.0 {
                floorShare = 1.0 / Double(n)
            }

            let sumBelow = shares.reduce(0.0) { $0 + max(0.0, floorShare - $1) }
            let donorsExcess = shares.reduce(0.0) { $0 + max(0.0, $1 - floorShare) }

            if sumBelow > 0.0 {
                var adjustedShares = shares
                if donorsExcess > 0.0 {
                    let scale = max(0.0, 1.0 - sumBelow / donorsExcess)
                    for i in 0..<n {
                        if shares[i] < floorShare {
                            adjustedShares[i] = floorShare
                        } else {
                            adjustedShares[i] = floorShare + (shares[i] - floorShare) * scale
                        }
                    }
                } else {
                    // All bars at/below floor: equalize
                    adjustedShares = Array(repeating: 1.0 / Double(n), count: n)
                }
                // Convert back to weights
                finalWeights = adjustedShares.map { $0 * totalFinal }
            }
        }

        // Readability boost for mid-top bars (indices 2...5):
        // Reallocate a small amount of width from the tail/Others to make 3rd–6th bars legible.
        do {
            let n2 = mainTiles.count
            guard n2 > 0 else { return (mainTiles, finalWeights) }
            let totalSpacingLocal2 = spacing * CGFloat(max(0, n2 - 1))
            let availableWidthLocal2 = max(1, containerWidth - totalSpacingLocal2)
            let totalFinal2 = max(1e-9, finalWeights.reduce(0, +))
            var shares2 = finalWeights.map { $0 / totalFinal2 }
            let widths2 = shares2.map { CGFloat($0) * availableWidthLocal2 }

            // Target minimum pixel widths for top bars (0-based): [BTC, ETH, next, next, next, next]
            let targets: [CGFloat] = [0, 0, 44, 40, 36, 30]
            let limit = min(n2, targets.count)
            var deficitsPx: [CGFloat] = Array(repeating: 0, count: limit)
            var totalDeficitPx: CGFloat = 0
            for i in 0..<limit where targets[i] > 0 {
                let deficit = max(0, targets[i] - widths2[i])
                deficitsPx[i] = deficit
                totalDeficitPx += deficit
            }

            if totalDeficitPx > 0.5 { // only run when there is a real deficit
                let keepMinPx: CGFloat = 15 // do not shrink donors below this
                // Donors: prefer tail bars beyond the first six; include Others only if it has comfortable width
                let othersIdx = mainTiles.firstIndex(where: { $0.id == "Others" || $0.symbol.hasPrefix("Others (") })
                // Update othersMinPx from 36 to 40 here
                let othersMinPx: CGFloat = 40
                var donors: [Int] = []
                for j in 0..<n2 where j >= 4 { donors.append(j) }
                if let oIdx = othersIdx {
                    let ow = widths2[oIdx]
                    if ow > othersMinPx + 6 && !donors.contains(oIdx) {
                        donors.append(oIdx)
                    }
                }

                var donorsAvailablePx: CGFloat = 0
                var donorAvail: [Int: CGFloat] = [:]
                for j in donors {
                    let avail = max(0, widths2[j] - keepMinPx)
                    if avail > 0 {
                        donorsAvailablePx += avail
                        donorAvail[j] = avail
                    }
                }

                // If still not enough to cover deficits, let BTC/ETH donate down to safe floors
                if donorsAvailablePx < totalDeficitPx {
                    let topFloors: [Int: CGFloat] = [0: 86, 1: 76]
                    for (j, floor) in topFloors {
                        if j < n2 && donorAvail[j] == nil {
                            let avail = max(0, widths2[j] - floor)
                            if avail > 0 {
                                donorsAvailablePx += avail
                                donorAvail[j] = avail
                            }
                        }
                    }
                }

                if donorsAvailablePx > 0 {
                    let s = min(1, totalDeficitPx / donorsAvailablePx)
                    // Reduce donors
                    for (j, avail) in donorAvail {
                        let deltaPx = avail * s
                        let deltaShare = Double(deltaPx / availableWidthLocal2)
                        shares2[j] = max(Double(keepMinPx / availableWidthLocal2), shares2[j] - deltaShare)
                    }
                    // Distribute to receivers proportionally to their deficits
                    let sumDef = deficitsPx.reduce(0, +)
                    if sumDef > 0 {
                        for i in 0..<limit where targets[i] > 0 {
                            let addPx = totalDeficitPx * (deficitsPx[i] / sumDef)
                            let addShare = Double(addPx / availableWidthLocal2)
                            shares2[i] += addShare
                        }
                    }
                    // Normalize to preserve total
                    let sumShares = max(1e-9, shares2.reduce(0, +))
                    shares2 = shares2.map { $0 / sumShares }
                    finalWeights = shares2.map { $0 * totalFinal2 }

                    // Ensure the Others bar never collapses below a readable floor
                    if let oIdx = othersIdx {
                        let currentOthersWidth = CGFloat(shares2[oIdx]) * availableWidthLocal2
                        if currentOthersWidth < othersMinPx {
                            let neededPx = othersMinPx - currentOthersWidth
                            // Take from donors excluding Others and avoid BTC/ETH as donors
                            var donorList: [Int] = []
                            for j in 0..<n2 where j != oIdx && j >= 3 { donorList.append(j) }
                            var availSum: CGFloat = 0
                            var availMap: [Int: CGFloat] = [:]
                            for j in donorList {
                                let wpx = CGFloat(shares2[j]) * availableWidthLocal2
                                let avail = max(0, wpx - keepMinPx)
                                if avail > 0 { availMap[j] = avail; availSum += avail }
                            }
                            if availSum > 0 {
                                let s2 = min(1, neededPx / availSum)
                                for (j, avail) in availMap {
                                    let takePx = avail * s2
                                    let takeShare = Double(takePx / availableWidthLocal2)
                                    shares2[j] = max(Double(keepMinPx / availableWidthLocal2), shares2[j] - takeShare)
                                }
                                let addShare = Double(neededPx / availableWidthLocal2)
                                shares2[oIdx] += addShare
                                let sumShares2 = max(1e-9, shares2.reduce(0, +))
                                shares2 = shares2.map { $0 / sumShares2 }
                                finalWeights = shares2.map { $0 * totalFinal2 }
                            }
                        }
                    }
                }
            }
        }

        // Global floor: ensure the Others bar never drops below minimum by gently rebalancing shares
        // BAR LAYOUT FIX: Reduced from 50px to 40px since Others should be smaller
        if let oIdx = mainTiles.firstIndex(where: { $0.id == "Others" || $0.symbol.hasPrefix("Others (") }) {
            let n3 = mainTiles.count
            let totalSpacingLocal3 = spacing * CGFloat(max(0, n3 - 1))
            let availableWidthLocal3 = max(1, containerWidth - totalSpacingLocal3)
            let totalFinal3 = max(1e-9, finalWeights.reduce(0, +))
            var shares3 = finalWeights.map { $0 / totalFinal3 }
            let widths3 = shares3.map { CGFloat($0) * availableWidthLocal3 }
            let othersMinPxGlobal: CGFloat = 40
            let currentOthersWidth = widths3[oIdx]
            if currentOthersWidth < othersMinPxGlobal {
                let neededPx = othersMinPxGlobal - currentOthersWidth
                // Prefer donors from the tail, excluding Others
                var donorList: [Int] = []
                for j in 0..<n3 where j != oIdx && j >= 3 { donorList.append(j) }
                var availSum: CGFloat = 0
                var availMap: [Int: CGFloat] = [:]
                let keepMinPxGeneral: CGFloat = 15
                for j in donorList {
                    let wpx = CGFloat(shares3[j]) * availableWidthLocal3
                    let avail = max(0, wpx - keepMinPxGeneral)
                    if avail > 0 { availMap[j] = avail; availSum += avail }
                }
                // If not enough, allow BTC/ETH to contribute down to safe floors
                if availSum < neededPx {
                    let topFloors: [Int: CGFloat] = [0: 86, 1: 76]
                    for (j, floor) in topFloors {
                        if j < n3 && j != oIdx {
                            let wpx = CGFloat(shares3[j]) * availableWidthLocal3
                            let avail = max(0, wpx - floor)
                            if avail > 0 {
                                if availMap[j] == nil { availMap[j] = 0 }
                                availMap[j]! += avail
                                availSum += avail
                            }
                        }
                    }
                }
                if availSum > 0 {
                    let s3 = min(1, neededPx / availSum)
                    for (j, avail) in availMap {
                        let takePx = avail * s3
                        let takeShare = Double(takePx / availableWidthLocal3)
                        shares3[j] = max(Double(keepMinPxGeneral / availableWidthLocal3), shares3[j] - takeShare)
                    }
                    let addShare = Double(neededPx / availableWidthLocal3)
                    shares3[oIdx] += addShare
                    let sumShares3 = max(1e-9, shares3.reduce(0, +))
                    shares3 = shares3.map { $0 / sumShares3 }
                    finalWeights = shares3.map { $0 * totalFinal3 }
                }
            }
        }

        // Guarantee Others tile stays at the far right
        if let moveIdx = mainTiles.firstIndex(where: { $0.id == "Others" || $0.symbol.hasPrefix("Others (") }), moveIdx != mainTiles.count - 1 {
            let t = mainTiles.remove(at: moveIdx)
            let w = finalWeights.remove(at: moveIdx)
            mainTiles.append(t)
            finalWeights.append(w)
        }

        return (mainTiles, finalWeights)
    }

    private struct BarTile: View {
        let tile: HeatMapTile
        let timeframe: HeatMapTimeframe
        let selected: Bool
        let changeProvider: ((HeatMapTile) -> Double)?
        let showValues: Bool
        let weightByVolume: Bool
        let boundOverride: Double?
        let palette: ColorPalette  // Keep for compatibility but use AppStorage instead
        let forceWhiteLabels: Bool
        let highlight: Color?
        let strongBorders: Bool
        let labelDensity: LabelDensity
        let onLongPress: () -> Void

        @State private var chipPop: Bool = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var colorScheme
        @State private var lastChipText: String = ""
        
        // PALETTE FIX: Read palette directly from AppStorage to bypass parameter chain issues
        @AppStorage("heatmap.palette") private var paletteRaw: String = ColorPalette.cool.rawValue
        private var effectivePalette: ColorPalette { ColorPalette(rawValue: paletteRaw) ?? .cool }
        
        private var isDark: Bool { colorScheme == .dark }

        private func measuredTextWidth(_ text: String, fontSize: CGFloat, weight: UIFont.Weight) -> CGFloat {
            HeatMapSharedLib.measuredTextWidth(text, fontSize: fontSize, weight: weight)
        }
        
        private func fittingFontSize(for text: String, maxFont: CGFloat, minFont: CGFloat, weight: UIFont.Weight, availableWidth: CGFloat, horizontalPadding: CGFloat) -> CGFloat? {
            var font = maxFont
            let avail = max(0, availableWidth - horizontalPadding)
            while font >= minFont {
                let w = measuredTextWidth(text, fontSize: font, weight: weight)
                if w <= avail { return font }
                font -= 0.5
            }
            return nil
        }

        private func barBackground(fill: Color, radius: CGFloat, selected: Bool, highlight: Color?, strongBorders: Bool, isDarkMode: Bool) -> some View {
            let rr = RoundedRectangle(cornerRadius: radius, style: .continuous)
            
            // TIMEFRAME FALLBACK FIX: Use card background as fallback for seamless appearance
            // This ensures tiles blend with container during transitions
            let fallbackNeutral = DS.Adaptive.cardBackground
            
            // Adaptive border colors using DS.Adaptive design system
            let borderColor: Color = strongBorders 
                ? DS.Adaptive.strokeStrong 
                : DS.Adaptive.stroke
            let borderWidth: CGFloat = isDarkMode
                ? (strongBorders ? 1.3 : 0.9)
                : (strongBorders ? 1.4 : 1.2)
            // Balanced inner glow - adds depth without washing out colors
            // LIGHT MODE FIX: Reduced from 0.65 to 0.12 to prevent washing out tile colors
            let innerGlowColor: Color = DS.Adaptive.gradientHighlight.opacity(isDarkMode ? 0.35 : 0.12)
            let selectionBorderColor: Color = isDarkMode 
                ? Color.white.opacity(0.9) 
                : DS.Adaptive.textPrimary.opacity(0.7)
            
            return ZStack {
                // Base fallback color - ensures tile is never black
                rr.fill(fallbackNeutral)
                // Actual calculated fill on top
                rr.fill(fill)
            }
                .overlay(
                    LinearGradient(colors: [innerGlowColor, Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(rr)
                )
                .overlay(
                    rr.stroke(borderColor, lineWidth: borderWidth)
                )
                .overlay(
                    rr.stroke(selectionBorderColor, lineWidth: 2)
                        .opacity(selected ? 1 : 0)
                )
                .overlay(
                    rr.stroke(highlight ?? .clear, lineWidth: (highlight == nil ? 0 : 2))
                )
        }

        private func chipOverlayView(
            text: String,
            fontSize: CGFloat,
            textColor: Color,
            backdrop: Color,
            minW: CGFloat,
            maxW: CGFloat,
            hPad: CGFloat,
            vPad: CGFloat,
            topPad: CGFloat,
            leadPad: CGFloat,
            scale: CGFloat,
            leadEdge: Edge.Set,
            opacity: Double
        ) -> some View {
            SimplePercentChip(
                text: text,
                fontSize: fontSize,
                textColor: textColor,
                backdrop: backdrop,
                minWidth: minW,
                maxWidth: maxW,
                hPad: hPad,
                vPad: vPad
            )
            .scaleEffect(scale)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: chipPop)
            .padding(.top, topPad)
            .padding(leadEdge, leadPad)
            .allowsHitTesting(false)
            .opacity(opacity)
        }

        private func coreTile(
            fill: Color,
            radius: CGFloat,
            selected: Bool,
            highlight: Color?,
            strongBorders: Bool,
            showSymbolLabel: Bool,
            displaySymbol: String,
            symbolFont: CGFloat,
            labelsText: Color,
            labelsBackdrop: Color,
            outlineOpacity: Double,
            labelBackdropOpacityVal: Double,
            microText: String?,
            microFont: CGFloat,
            microBackdropOpacityVal: Double,
            isDarkMode: Bool
        ) -> some View {
            ZStack(alignment: .bottomLeading) {
                barBackground(fill: fill, radius: radius, selected: selected, highlight: highlight, strongBorders: strongBorders, isDarkMode: isDarkMode)

                if showSymbolLabel {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displaySymbol)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .font(.system(size: symbolFont, weight: .heavy))
                            .allowsTightening(true)
                    }
                    .foregroundColor(labelsText)
                    .background(labelsBackdrop.opacity(labelBackdropOpacityVal), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DS.Adaptive.overlay(0.18), lineWidth: 0.6)
                    )
                    // BAR LABEL FIX: Consistent padding across all label types
                    .padding(.leading, 5)
                    .padding(.bottom, 5)
                } else if let text = microText {
                    // BAR LABEL FIX: Consistent micro label styling with symbol labels
                    // TRUNCATION FIX: Added .fixedSize() to guarantee no "..." truncation
                    Text(text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .font(.system(size: microFont, weight: .heavy))
                        .kerning(-0.4)
                        .allowsTightening(true)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(labelsText)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .background(labelsBackdrop.opacity(microBackdropOpacityVal), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(.leading, 5)
                        .padding(.bottom, 5)
                } else {
                    Color.clear
                }
            }
        }

        var body: some View {
            GeometryReader { proxy in
                // TIMEFRAME FALLBACK FIX: Use fallback data when exact timeframe is unavailable
                let (changeValue, _) = HeatMapSharedLib.changeWithFallback(for: tile, tf: timeframe)
                let rawChange = (changeProvider?(tile)) ?? changeValue
                // Sanitize non-finite or obviously invalid changes to avoid misleading UI
                let ch: Double = {
                    if !rawChange.isFinite { return 0 }
                    if abs(rawChange) > 10_000 { return 0 } // defensive clamp against junk payloads
                    return rawChange
                }()
                let isChangeKnown: Bool = HeatMapSharedLib.hasAnyData(for: tile)

                let width = max(0, proxy.size.width)
                let height = max(0, proxy.size.height)
                let aspect = width / max(1, height)
                let radius: CGFloat = max(3, min(9, width * 0.16))

                // Prepare symbol strings early so label logic can use filtered content
                let rawSymbol = (tile.id == "Others" ? tile.symbol : tile.symbol.uppercased())
                let filteredSymbol = rawSymbol.filter { $0.isLetter || $0.isNumber }
                
                // BAR LAYOUT FIX: Lowered threshold from 40px to 34px to show full labels on more bars
                let showSymbolLabelBase = tile.id == "Others" ? (width >= 28) : (width >= 34 && !filteredSymbol.isEmpty)

                let baseSymbolFont = max(10, min(16, width * 0.20))
                let symbolFont = tile.id == "Others" ? max(12, min(17, width * 0.20)) : baseSymbolFont
                let labelBlockH: CGFloat = showSymbolLabelBase ? (6 + symbolFont + 6) : 0

                let displaySymbol: String = {
                    if tile.id == "Others" {
                        var count: String? = nil
                        let s = rawSymbol
                        if let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")"), open < close {
                            count = String(s[s.index(after: open)..<close])
                        }
                        var candidates: [String] = []
                        if let c = count { candidates.append("Others (\(c))") }
                        candidates.append("Others")
                        candidates.append("Other")
                        let externalLeading: CGFloat = 6
                        let margin: CGFloat = 2
                        for cand in candidates {
                            let w = measuredTextWidth(cand, fontSize: symbolFont, weight: .heavy)
                            if w + margin <= max(0, width - externalLeading) { return cand }
                        }
                        return ""
                    } else {
                        return String(filteredSymbol)
                    }
                }()
                let showSymbolLabel: Bool = showSymbolLabelBase && !displaySymbol.isEmpty
                // BAR LABEL FIX: Adaptive font 9-13pt based on available width for better readability
                let microFixedFont: CGFloat = max(9, min(13, width * 0.30))
                let microTextEffective: String? = {
                    if showSymbolLabel { return nil }
                    if tile.id == "Others" { return nil }
                    if width < 12 { return nil }  // Need at least 12px for any label
                    if filteredSymbol.isEmpty { return nil }
                    let count = filteredSymbol.count
                    
                    // BAR LABEL FIX: Build candidates list based on symbol length
                    // For short symbols (≤5 chars), always show full - never truncate BTC, ETH, DOGE, STETH
                    // For longer symbols, try progressively shorter versions
                    var candidates: [String] = []
                    if count <= 5 {
                        // Short symbols (BTC, ETH, SOL, DOGE, STETH): always show full
                        candidates.append(String(filteredSymbol))
                    } else if count == 6 {
                        // 6-letter symbols: try full, then 5, then 4 chars
                        candidates.append(String(filteredSymbol))
                        candidates.append(String(filteredSymbol.prefix(5)))
                        candidates.append(String(filteredSymbol.prefix(4)))
                    } else {
                        // Longer symbols (7+ chars like FIGRHELOC): try 7, 6, 5, 4 chars
                        if count >= 7 { candidates.append(String(filteredSymbol.prefix(7))) }
                        if count >= 6 { candidates.append(String(filteredSymbol.prefix(6))) }
                        if count >= 5 { candidates.append(String(filteredSymbol.prefix(5))) }
                        if count >= 4 { candidates.append(String(filteredSymbol.prefix(4))) }
                    }
                    
                    let externalLeading: CGFloat = 5
                    let internalHPad: CGFloat = 4
                    let margin: CGFloat = 1
                    let available = max(0, width - externalLeading)
                    for cand in candidates {
                        let textW = measuredTextWidth(cand, fontSize: microFixedFont, weight: .heavy)
                        if textW + internalHPad + margin <= available { return cand }
                    }
                    return nil
                }()
                let accessibilityName: String = displaySymbol.isEmpty ? (tile.id == "Others" ? "Others" : tile.symbol.uppercased()) : displaySymbol

                let computedMicroFont: CGFloat = {
                    return microTextEffective == nil ? 0 : microFixedFont
                }()

                let metrics = HeatMapSharedLib.badgeMetrics(width: width, height: height)
                let chipHApprox = metrics.font + metrics.vPad * 2 + 6
                let verticalClearanceOK = (height - (metrics.pad + chipHApprox + 4) - labelBlockH) >= 0
                let alignRight = selected || width > 100 || aspect > 1.6
                let chipAlignment: Alignment = alignRight ? .topTrailing : .topLeading
                let chipLeadEdge: Edge.Set = alignRight ? .trailing : .leading
                let chipScale: CGFloat = chipPop ? 1.06 : 1.0
                let labelBackdropOpacityVal: Double = (tile.id == "Others" ? 1.0 : (width < 80 ? 0.96 : 1.0))
                let microBackdropOpacityVal: Double = (width < 48 ? 0.98 : 1.0)

                let chipAvailableWidth = max(10, min(width - 12, metrics.maxW))
                let chipText = isChangeKnown ? HeatMapSharedLib.condensedPercentString(ch, availableWidth: chipAvailableWidth) : "—"
                let chipTextWidth = HeatMapSharedLib.measuredTextWidth(chipText, fontSize: metrics.font, weight: .semibold)
                let chipVisualWidth = chipTextWidth + (metrics.hPad * 2) + 8
                let accessibilityValueText: String = isChangeKnown ? HeatMapSharedLib.percentStringAdaptive(ch) : "Unknown change"
                let barMinForChip = max(labelDensity.barPercentMinWidth, 56)
                let othersOKForChip = (tile.id != "Others" || width >= 70)
                let symbolWidthBudget: CGFloat = {
                    guard showSymbolLabel else { return 0 }
                    let raw = HeatMapSharedLib.measuredTextWidth(displaySymbol, fontSize: symbolFont, weight: .heavy) + 10
                    return min(raw, width * 0.55)
                }()
                let hasHorizontalRoom = width >= (chipVisualWidth + symbolWidthBudget + (showSymbolLabel ? 10 : 0))
                let chipCanShow = ((((width >= barMinForChip) && othersOKForChip && hasHorizontalRoom) || selected) && verticalClearanceOK)
                let chipOpacity: Double = chipCanShow ? 1 : 0

                // SELECTED STATE FIX: Pass selected parameter for higher contrast colors
                let badgeColors = HeatMapSharedLib.badgeLabelColors(for: ch, bound: boundOverride ?? HeatMapSharedLib.bound(for: timeframe), palette: effectivePalette, forceWhite: forceWhiteLabels, timeframe: timeframe, selected: selected)
                let chipOverlay: AnyView = AnyView(
                    chipOverlayView(
                        text: chipText,
                        fontSize: metrics.font,
                        textColor: badgeColors.text,
                        backdrop: badgeColors.backdrop,
                        minW: metrics.minW,
                        maxW: metrics.maxW,
                        hPad: metrics.hPad,
                        vPad: metrics.vPad,
                        topPad: metrics.pad,
                        leadPad: metrics.lead + 5,
                        scale: chipScale,
                        leadEdge: chipLeadEdge,
                        opacity: chipOpacity
                    )
                )

                // COLOR MATCH FIX: Use ch directly for color to guarantee it matches the displayed percentage
                // Previously used colorWithFallback which recalculated and could get different values
                let isLightMode = colorScheme == .light
                let tileFill = HeatMapSharedLib.color(for: ch, bound: boundOverride ?? HeatMapSharedLib.bound(for: timeframe), palette: effectivePalette, timeframe: timeframe, isLightMode: isLightMode)
                
                // SELECTED STATE FIX: Pass selected parameter for higher contrast colors
                let labelColors = HeatMapSharedLib.labelColors(for: ch, bound: boundOverride ?? HeatMapSharedLib.bound(for: timeframe), palette: effectivePalette, forceWhite: forceWhiteLabels, timeframe: timeframe, selected: selected, isLightMode: isLightMode)
                
                coreTile(
                    fill: tileFill,
                    radius: radius,
                    selected: selected,
                    highlight: highlight,
                    strongBorders: strongBorders,
                    showSymbolLabel: showSymbolLabel,
                    displaySymbol: displaySymbol,
                    symbolFont: symbolFont,
                    labelsText: labelColors.text,
                    labelsBackdrop: labelColors.backdrop,
                    outlineOpacity: HeatMapSharedLib.labelOutlineOpacity(for: ch, bound: boundOverride ?? HeatMapSharedLib.bound(for: timeframe), palette: effectivePalette, timeframe: timeframe, isLightMode: isLightMode),
                    labelBackdropOpacityVal: labelBackdropOpacityVal,
                    microText: microTextEffective,
                    microFont: computedMicroFont,
                    microBackdropOpacityVal: microBackdropOpacityVal,
                    isDarkMode: isDark
                )
                .onAppear {
                    // Defer to avoid "Modifying state during view update"
                    DispatchQueue.main.async { lastChipText = chipText }
                }
                .onChange(of: chipText) { _, newVal in
                    // Defer to avoid "Modifying state during view update"
                    DispatchQueue.main.async {
                        if newVal != lastChipText {
                            if !reduceMotion && chipCanShow {
                                chipPop = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { chipPop = false }
                            }
                            lastChipText = newVal
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityName))
                .accessibilityValue(Text(accessibilityValueText))
                .accessibilityHint(Text("Double tap to select. Long press for options."))
                .overlay(alignment: chipAlignment) {
                    chipOverlay
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .clipped(antialiased: true)
                // SMOOTH COLOR TRANSITION: Animate fill color when timeframe changes or data updates.
                .animation(.easeInOut(duration: 0.45), value: timeframe)
                .animation(.easeInOut(duration: 0.6), value: ch)
                .contentShape(Rectangle())
            }
        }
    }
}

