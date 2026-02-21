import SwiftUI
import Combine
import UIKit

public struct TreemapView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    // PALETTE FIX: Read palette from AppStorage to match TreemapTile behavior
    @AppStorage("heatmap.palette") private var paletteRaw: String = ColorPalette.cool.rawValue
    private var effectivePalette: ColorPalette { ColorPalette(rawValue: paletteRaw) ?? .cool }
    
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
    public var tileFilter: ((HeatMapTile) -> Bool)? = nil
    public var portfolioIDs: Set<String>? = nil
    public var interactionsEnabled: Bool = true
    
    /// STABILITY FIX: When true, animations are disabled to prevent visual flickering during initial load
    public var isSettling: Bool = false

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
        tileFilter: ((HeatMapTile) -> Bool)? = nil,
        portfolioIDs: Set<String>? = nil,
        interactionsEnabled: Bool = true,
        isSettling: Bool = false
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
        self.tileFilter = tileFilter
        self.portfolioIDs = portfolioIDs
        self.interactionsEnabled = interactionsEnabled
        self.isSettling = isSettling
    }

    private func computeLayout(in rect: CGRect) -> (tiles: [HeatMapTile], rects: [CGRect], defaultPercentIDs: Set<String>, forceAllPercents: Bool) {
        let count = min(tiles.count, weights.count)
        let pairs = Array(zip(tiles.prefix(count), weights.prefix(count)))
        let filteredPairs = pairs.filter { pair in
            let (tile, _) = pair
            let idPass = portfolioIDs == nil || portfolioIDs!.contains(tile.id)
            let predPass = tileFilter?(tile) ?? true
            return idPass && predPass
        }
        let useTiles = filteredPairs.map { $0.0 }
        let rawWeights = filteredPairs.map { max(0, $0.1) }
        let maxW = rawWeights.max() ?? 1
        let minWPos = rawWeights.filter { $0 > 0 }.min() ?? maxW
        let ratio = maxW / max(minWPos, 1e-9)
        // LAYOUT FIX: More aggressive compression to prevent single-tile dominance
        // Lower exponents = more compression, creating more balanced layouts
        // Previous values (0.78-1.0) allowed BTC to dominate with 40%+ of area
        let visualExp: Double = (ratio > 50 ? 0.55 : (ratio > 25 ? 0.65 : (ratio > 12 ? 0.75 : 0.85)))
        var compressed = rawWeights.map { pow($0, visualExp) }
        
        // LAYOUT FIX: Cap single-tile share at 30% to prevent any coin from dominating
        // This ensures a balanced layout even with extreme market cap differences (BTC vs altcoins)
        let totalCompressedPre = compressed.reduce(0, +)
        let maxTileShare: Double = 0.30  // No single tile should exceed 30% of total area
        let maxAllowedWeight = maxTileShare * totalCompressedPre / (1.0 - maxTileShare)
        var excessWeight: Double = 0
        for i in 0..<compressed.count {
            if compressed[i] > maxAllowedWeight {
                excessWeight += compressed[i] - maxAllowedWeight
                compressed[i] = maxAllowedWeight
            }
        }
        // Redistribute excess weight proportionally to non-capped tiles
        if excessWeight > 0 {
            let nonCappedTotal = compressed.filter { $0 < maxAllowedWeight }.reduce(0, +)
            if nonCappedTotal > 0 {
                for i in 0..<compressed.count where compressed[i] < maxAllowedWeight {
                    let share = compressed[i] / nonCappedTotal
                    compressed[i] += excessWeight * share
                }
            }
        }
        let totalCompressed = compressed.reduce(0, +)
        let totalArea = max(1.0, Double(rect.width * rect.height))
        // Adaptive minimum visible area per tile based on container size and target tile count
        // Balanced: 7% gives small tiles reasonable weight without over-inflating
        let targetCount = max(8, min(30, useTiles.count))
        let adaptiveMinArea = max(48.0, min(72.0, (totalArea / Double(max(targetCount, 1))) * 0.07))
        let minAreaPx: Double = adaptiveMinArea
        let minWeight = totalCompressed * (minAreaPx / totalArea)
        let floored = compressed.map { max($0, minWeight) }
        let flooredTotal = floored.reduce(0, +)
        let useWeights = floored.map { $0 * (totalCompressed / max(1e-9, flooredTotal)) }

        // First layout pass to detect thin tiles
        let firstRects = HeatMapSharedLib.squarify(items: useTiles, weights: useWeights, rect: rect)
        // Minimum thickness for readable tiles
        // LAYOUT FIX: Further lowered thresholds to support 18-24 coins without collapse
        // Previous thresholds were still too aggressive for larger tile counts
        let microMinThickness: CGFloat = {
            if targetCount >= 25 { return 14 }
            else if targetCount >= 22 { return 12 }
            else if targetCount >= 18 { return 10 }
            else if targetCount >= 14 { return 9 }
            else if targetCount >= 10 { return 8 }
            else { return 7 }  // For ≤9 tiles, maximum flexibility
        }()
        var thinIDs = Set<String>()
        for (idx, r) in firstRects.enumerated() {
            if min(r.width, r.height) < microMinThickness {
                thinIDs.insert(useTiles[idx].id)
            }
        }
        thinIDs.remove("Others")
        
        // Hard cap: force aggregation if we have too many non-Others tiles
        // LAYOUT FIX: Raised from 14 to 24 to support displaying more coins without forced aggregation
        // Combined with better weight compression, this allows up to 24 individual tiles
        let maxNonOthersTiles = 24
        let currentNonOthers = useTiles.filter { $0.id != "Others" && !$0.symbol.hasPrefix("Others (") }
        if currentNonOthers.count > maxNonOthersTiles && thinIDs.isEmpty {
            // Force the smallest tiles into Others even if they passed thickness check
            let sortedByWeight = useTiles.enumerated()
                .filter { $0.element.id != "Others" && !$0.element.symbol.hasPrefix("Others (") }
                .sorted { useWeights[$0.offset] > useWeights[$1.offset] }
            let toCollapse = sortedByWeight.dropFirst(maxNonOthersTiles)
            for item in toCollapse {
                thinIDs.insert(item.element.id)
            }
        }

        var layoutTiles: [HeatMapTile]
        var layoutWeights: [Double]
        var layoutWeightsPreFloor: [Double]

        if !thinIDs.isEmpty {
            // Build using PRE-FLOOR (compressed) weights to avoid inflating "Others"
            // by the minimum-area floor that was applied per tile in the first pass.
            var mergedCompressedWeight: Double = 0
            var mergedCap: Double = 0
            var mergedVol: Double = 0
            // Track weighted sums for ALL timeframes to avoid black tiles when switching
            var mergedWeighted1hSum: Double = 0
            var mergedWeighted24hSum: Double = 0
            var mergedWeighted7dSum: Double = 0
            var mergedWeightBaseSum: Double = 0

            // Filter out thin tiles and keep their compressed weights for merging
            var tiles2: [HeatMapTile] = []
            var weights2: [Double] = []
            for (idx, t) in useTiles.enumerated() where !thinIDs.contains(t.id) {
                tiles2.append(t)
                weights2.append(compressed[idx])
            }

            for (idx, tile) in useTiles.enumerated() where thinIDs.contains(tile.id) {
                let compW = compressed[idx]
                mergedCompressedWeight += compW
                mergedCap += tile.marketCap
                mergedVol += tile.volume
                let wt = weightByVolume ? tile.volume : tile.marketCap
                
                // Calculate weighted changes for all three timeframes
                let raw1h = tile.pctChange1h ?? 0
                let raw24h = tile.pctChange24h
                let raw7d = tile.pctChange7d ?? 0
                
                let ch1h = (raw1h.isFinite && abs(raw1h) <= 10_000) ? raw1h : 0
                let ch24h = (raw24h.isFinite && abs(raw24h) <= 10_000) ? raw24h : 0
                let ch7d = (raw7d.isFinite && abs(raw7d) <= 10_000) ? raw7d : 0
                
                mergedWeighted1hSum += ch1h * wt
                mergedWeighted24hSum += ch24h * wt
                mergedWeighted7dSum += ch7d * wt
                mergedWeightBaseSum += wt
            }
            
            // Calculate weighted averages for all timeframes
            let merged1h = mergedWeightBaseSum > 0 ? (mergedWeighted1hSum / mergedWeightBaseSum) : 0
            let merged24h = mergedWeightBaseSum > 0 ? (mergedWeighted24hSum / mergedWeightBaseSum) : 0
            let merged7d = mergedWeightBaseSum > 0 ? (mergedWeighted7dSum / mergedWeightBaseSum) : 0

            let parseOthersCount: (String) -> Int? = { symbol in
                guard symbol.hasPrefix("Others ("), symbol.hasSuffix(")") else { return nil }
                let startIdx = symbol.index(symbol.startIndex, offsetBy: 8)
                let endIdx = symbol.index(before: symbol.endIndex)
                let numberString = String(symbol[startIdx..<endIdx])
                return Int(numberString)
            }

            if let othersIndex = tiles2.firstIndex(where: { $0.id == "Others" }) {
                let existing = tiles2[othersIndex]
                var newCount = thinIDs.count
                if let currentCount = parseOthersCount(existing.symbol) { newCount += currentCount }
                
                // MERGE FIX: Combine existing "Others" data with collapsed tiles using weighted average
                // instead of replacing (which lost the original data)
                let existingWeight = weightByVolume ? existing.volume : existing.marketCap
                let totalWeight = existingWeight + mergedWeightBaseSum
                
                // Calculate combined weighted averages for all timeframes
                let combined1h: Double? = {
                    if totalWeight <= 0 { return nil }
                    let existingVal = existing.pctChange1h ?? 0
                    return (existingVal * existingWeight + mergedWeighted1hSum) / totalWeight
                }()
                
                let combined24h: Double = {
                    if totalWeight <= 0 { return 0 }
                    return (existing.pctChange24h * existingWeight + mergedWeighted24hSum) / totalWeight
                }()
                
                let combined7d: Double? = {
                    if totalWeight <= 0 { return nil }
                    let existingVal = existing.pctChange7d ?? 0
                    return (existingVal * existingWeight + mergedWeighted7dSum) / totalWeight
                }()
                
                let updatedOthers = HeatMapTile(
                    id: "Others",
                    symbol: "Others (\(newCount))",
                    pctChange24h: combined24h,
                    marketCap: existing.marketCap + mergedCap,
                    volume: existing.volume + mergedVol,
                    pctChange1h: combined1h,
                    pctChange7d: combined7d
                )
                tiles2[othersIndex] = updatedOthers
                // Add the merged COMPRESSED weight to the existing Others compressed weight
                weights2[othersIndex] = weights2[othersIndex] + mergedCompressedWeight
            } else {
                let othersTile = HeatMapTile(
                    id: "Others",
                    symbol: "Others (\(thinIDs.count))",
                    pctChange24h: merged24h,
                    marketCap: mergedCap,
                    volume: mergedVol,
                    pctChange1h: merged1h,
                    pctChange7d: merged7d
                )
                tiles2.append(othersTile)
                weights2.append(mergedCompressedWeight)
            }

            layoutTiles = tiles2
            layoutWeightsPreFloor = weights2
        } else {
            // No merge necessary; carry forward original tiles with PRE-FLOOR compressed weights
            layoutTiles = useTiles
            layoutWeightsPreFloor = compressed
        }

        // Re-apply the minimum-area floor AFTER merging so the group weight is fair,
        // then renormalize to the original compressed total to preserve proportions.
        let floored2 = layoutWeightsPreFloor.map { max($0, minWeight) }
        let flooredTotal2 = floored2.reduce(0, +)
        layoutWeights = floored2.map { $0 * (totalCompressed / max(1e-9, flooredTotal2)) }

        // Post-merge cap: ensure the synthetic Others doesn't dominate the treemap
        if let idx = layoutTiles.firstIndex(where: { $0.id == "Others" || $0.symbol.hasPrefix("Others (") }) {
            let total = max(1e-9, layoutWeights.reduce(0, +))
            var othersW = layoutWeights[idx]
            let nonOthers = total - othersW
            
            // Aggressive total-share cap for Others to prevent it from dominating
            // LAYOUT FIX: Further reduced caps to keep Others small and give individual coins more space
            let cap: Double = {
                let n = layoutTiles.count
                if n <= 10 { return 0.12 }
                else if n <= 14 { return 0.11 }
                else if n <= 18 { return 0.10 }
                else if n <= 24 { return 0.09 }
                else { return 0.08 }
            }()

            // Convert the total-share cap into an absolute weight limit
            let limitByShare = (cap * nonOthers) / max(1e-9, (1.0 - cap))

            // Additional relative-to-top cap so Others never visually overshadows the largest named tile
            let maxNonOthers = layoutWeights.enumerated()
                .filter { $0.offset != idx }
                .map { $0.element }
                .max() ?? 0
            // Tighter relative cap - Others should never visually overshadow named coins
            // LAYOUT FIX: Reduced relative cap so Others is always smaller than top coins
            let relK: Double = {
                let n = layoutTiles.count
                if n <= 12 { return 0.50 }
                else if n <= 18 { return 0.45 }
                else if n <= 24 { return 0.40 }
                else { return 0.35 }
            }()
            let limitByTop = relK * maxNonOthers

            let finalLimit = min(limitByShare, limitByTop)

            if othersW > finalLimit {
                let delta = othersW - finalLimit
                othersW = finalLimit
                layoutWeights[idx] = othersW
                // Redistribute the excess proportionally across non-Others to keep total constant
                let denom = max(1e-9, nonOthers)
                for i in 0..<layoutWeights.count where i != idx {
                    let share = layoutWeights[i] / denom
                    layoutWeights[i] += delta * share
                }
            }
        }

        var rects = HeatMapSharedLib.squarify(items: layoutTiles, weights: layoutWeights, rect: rect)
        
        // Second-pass safety check: if any tiles are still degenerate after all processing,
        // mark them for removal and run one more aggregation cycle
        // Very low threshold - only catches truly unreadable tiles (under 8px)
        let finalMinThickness: CGFloat = 8
        var degenerateIndices: Set<Int> = []
        for (idx, r) in rects.enumerated() {
            let tile = layoutTiles[idx]
            if tile.id != "Others" && !tile.symbol.hasPrefix("Others (") {
                if min(r.width, r.height) < finalMinThickness || r.width < 1 || r.height < 1 {
                    degenerateIndices.insert(idx)
                }
            }
        }
        
        // If we found degenerate tiles in final pass, collapse them into Others
        if !degenerateIndices.isEmpty {
            var finalTiles: [HeatMapTile] = []
            var finalWeights: [Double] = []
            var collapsedCap: Double = 0
            var collapsedVol: Double = 0
            var collapsedCount: Int = 0
            
            // Track weighted sums for proper average calculation
            var collapsed1hSum: Double = 0
            var collapsed1hWeight: Double = 0
            var collapsed24hSum: Double = 0
            var collapsed24hWeight: Double = 0
            var collapsed7dSum: Double = 0
            var collapsed7dWeight: Double = 0
            
            for (idx, tile) in layoutTiles.enumerated() {
                if degenerateIndices.contains(idx) {
                    let weight = tile.marketCap
                    collapsedCap += tile.marketCap
                    collapsedVol += tile.volume
                    collapsedCount += 1
                    
                    // Accumulate weighted changes for all timeframes
                    if let h = tile.pctChange1h, h.isFinite {
                        collapsed1hSum += h * weight
                        collapsed1hWeight += weight
                    }
                    if tile.pctChange24h.isFinite {
                        collapsed24hSum += tile.pctChange24h * weight
                        collapsed24hWeight += weight
                    }
                    if let d = tile.pctChange7d, d.isFinite {
                        collapsed7dSum += d * weight
                        collapsed7dWeight += weight
                    }
                } else {
                    finalTiles.append(tile)
                    finalWeights.append(layoutWeights[idx])
                }
            }
            
            // Calculate weighted averages for collapsed tiles
            let collapsed1h: Double? = collapsed1hWeight > 0 ? (collapsed1hSum / collapsed1hWeight) : nil
            let collapsed24h: Double = collapsed24hWeight > 0 ? (collapsed24hSum / collapsed24hWeight) : 0
            let collapsed7d: Double? = collapsed7dWeight > 0 ? (collapsed7dSum / collapsed7dWeight) : nil
            
            // Add collapsed to existing Others or create new one
            if let othersIdx = finalTiles.firstIndex(where: { $0.id == "Others" || $0.symbol.hasPrefix("Others (") }) {
                let existing = finalTiles[othersIdx]
                var existingCount = 0
                if existing.symbol.hasPrefix("Others ("), existing.symbol.hasSuffix(")") {
                    let start = existing.symbol.index(existing.symbol.startIndex, offsetBy: 8)
                    let end = existing.symbol.index(before: existing.symbol.endIndex)
                    existingCount = Int(String(existing.symbol[start..<end])) ?? 0
                }
                
                // Merge collapsed averages with existing Others using combined weights
                let existingWeight = existing.marketCap
                let totalWeight = existingWeight + collapsedCap
                
                let merged1h: Double? = {
                    let e1h = existing.pctChange1h
                    if let e = e1h, let c = collapsed1h {
                        return (e * existingWeight + c * collapsedCap) / totalWeight
                    }
                    return e1h ?? collapsed1h
                }()
                
                let merged24h: Double = {
                    return (existing.pctChange24h * existingWeight + collapsed24h * collapsedCap) / totalWeight
                }()
                
                let merged7d: Double? = {
                    let e7d = existing.pctChange7d
                    if let e = e7d, let c = collapsed7d {
                        return (e * existingWeight + c * collapsedCap) / totalWeight
                    }
                    return e7d ?? collapsed7d
                }()
                
                let updatedOthers = HeatMapTile(
                    id: "Others",
                    symbol: "Others (\(existingCount + collapsedCount))",
                    pctChange24h: merged24h,
                    marketCap: existing.marketCap + collapsedCap,
                    volume: existing.volume + collapsedVol,
                    pctChange1h: merged1h,
                    pctChange7d: merged7d
                )
                finalTiles[othersIdx] = updatedOthers
            } else if collapsedCount > 0 {
                let newOthers = HeatMapTile(
                    id: "Others",
                    symbol: "Others (\(collapsedCount))",
                    pctChange24h: collapsed24h,
                    marketCap: collapsedCap,
                    volume: collapsedVol,
                    pctChange1h: collapsed1h,
                    pctChange7d: collapsed7d
                )
                finalTiles.append(newOthers)
                finalWeights.append(collapsedCap) // Use raw cap as weight
            }
            
            layoutTiles = finalTiles
            layoutWeights = finalWeights
            rects = HeatMapSharedLib.squarify(items: layoutTiles, weights: layoutWeights, rect: rect)
        }
        
        let areas = rects.map { $0.width * $0.height }
        let sortedIndices = areas.enumerated().sorted(by: { $0.element > $1.element }).map { $0.offset }
        // Changed fraction from 0.4 to 0.5 and upper cap from 5 to 6
        let defaultCount = min(6, max(3, Int(round(Double(layoutTiles.count) * 0.5))))
        let defaultPercentIDs: Set<String> = Set(sortedIndices.prefix(defaultCount).map { layoutTiles[$0].id })
        let forceAllPercents = layoutTiles.count <= 6

        return (layoutTiles, rects, defaultPercentIDs, forceAllPercents)
    }

    // MEMORY FIX v8: Memoize heavy layout computation. computeLayout() runs the squarify
    // algorithm, creates multiple arrays, and performs weight compression. Previously this
    // ran on EVERY body evaluation (triggered by GeometryReader size changes, data updates,
    // and animation ticks). Now we cache the result and only recompute when inputs change.
    @State private var cachedLayout: (tiles: [HeatMapTile], rects: [CGRect], defaultPercentIDs: Set<String>, forceAllPercents: Bool)?
    @State private var cachedLayoutKey: String = ""
    
    private func layoutKey(size: CGSize) -> String {
        let tileHash = tiles.map { $0.id }.joined(separator: ",")
        let weightHash = weights.prefix(20).map { String(format: "%.0f", $0) }.joined(separator: ",")
        return "\(tileHash)|\(weightHash)|\(Int(size.width))x\(Int(size.height))|\(timeframe)"
    }
    
    public var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let key = layoutKey(size: geo.size)
            // Use cached layout if inputs haven't changed
            let layout: (tiles: [HeatMapTile], rects: [CGRect], defaultPercentIDs: Set<String>, forceAllPercents: Bool) = {
                if key == cachedLayoutKey, let cached = cachedLayout {
                    return cached
                }
                let computed = computeLayout(in: rect)
                DispatchQueue.main.async {
                    cachedLayoutKey = key
                    cachedLayout = computed
                }
                return computed
            }()

            ZStack(alignment: .topLeading) {
                // Container background matches card for seamless appearance
                // Gaps between tiles blend invisibly with this background
                DS.Adaptive.cardBackground
                    .cornerRadius(8)
                
                let displayCount = min(layout.tiles.count, layout.rects.count)
                ForEach(0..<displayCount, id: \.self) { idx in
                    let tile = layout.tiles[idx]
                    let r = layout.rects[idx]
                    // SPACING FIX: Subtle separation - 0.75pt creates professional look
                    // without visible "gutters", matching premium financial apps
                    let inset: CGFloat = 0.75
                    // Clamp insets so we never produce negative sizes
                    let insetX = min(inset, max(0, r.width * 0.5))
                    let insetY = min(inset, max(0, r.height * 0.5))
                    let sliceRaw = r.insetBy(dx: insetX, dy: insetY)
                    // Ensure finite, non-negative geometry before passing to SwiftUI/CALayer
                    let safeW = max(0, sliceRaw.width.isFinite ? sliceRaw.width : 0)
                    let safeH = max(0, sliceRaw.height.isFinite ? sliceRaw.height : 0)
                    let centerX = sliceRaw.midX.isFinite ? sliceRaw.midX : 0
                    let centerY = sliceRaw.midY.isFinite ? sliceRaw.midY : 0

                    Group {
                        if safeW > 0.01 && safeH > 0.01 && centerX.isFinite && centerY.isFinite {
                            let slice = CGRect(x: sliceRaw.minX, y: sliceRaw.minY, width: safeW, height: safeH)
                            TreemapTile(
                                tile: tile,
                                frame: slice,
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
                                onTap: { onTileTap?(tile) },
                                onLongPress: { onTileLongPress?(tile) },
                                defaultShowPercent: layout.defaultPercentIDs.contains(tile.id),
                                forceAllPercents: layout.forceAllPercents
                            )
                            .frame(width: safeW, height: safeH)
                            .position(x: centerX, y: centerY)
                            .clipped()
                            // SMOOTH TRANSITION: Use stable tile identity so SwiftUI can
                            // animate color changes when timeframe/data updates occur.
                            // Colors crossfade through neutral which looks professional.
                            .id("\(tile.id)-\(palette.rawValue)")
                        } else {
                            // Skip rendering invalid/degenerate tiles to avoid NaN in CALayer
                            Color.clear.frame(width: 0, height: 0)
                        }
                    }
                }
            }
            .allowsHitTesting(interactionsEnabled)
            // STABILITY FIX: Disable all animations during settling to prevent visual flickering
            .transaction { transaction in
                if isSettling {
                    transaction.animation = nil
                }
            }
        }
    }

    private struct TreemapTile: View {
        let tile: HeatMapTile
        let frame: CGRect
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
        let onTap: () -> Void
        let onLongPress: () -> Void
        let defaultShowPercent: Bool
        let forceAllPercents: Bool
        
        @State private var chipPop: Bool = false
        @Environment(\.colorScheme) private var colorScheme
        
        // PALETTE FIX: Read palette directly from AppStorage to bypass parameter chain issues
        @AppStorage("heatmap.palette") private var paletteRaw: String = ColorPalette.cool.rawValue
        private var effectivePalette: ColorPalette { ColorPalette(rawValue: paletteRaw) ?? .cool }
        
        private var isDark: Bool { colorScheme == .dark }

        var body: some View {
            // TIMEFRAME FALLBACK FIX: Use fallback data when exact timeframe is unavailable
            // This prevents gray flash when switching timeframes
            let (changeValue, isFallback) = HeatMapSharedLib.changeWithFallback(for: tile, tf: timeframe)
            // SAFETY FIX: Ensure change value is finite to prevent NaN colors/labels
            let rawCh = (changeProvider?(tile)) ?? changeValue
            let ch = rawCh.isFinite ? rawCh : 0
            // SAFETY FIX: Validate boundOverride - must be finite and positive
            let b: Double = {
                if let override = boundOverride, override.isFinite && override > 0 {
                    return override
                }
                return HeatMapSharedLib.bound(for: timeframe)
            }()
            let isLightMode = colorScheme == .light
            // COLOR MATCH FIX: Use ch directly for color to guarantee it matches the displayed percentage
            // Previously used colorWithFallback which recalculated and could get different values
            let fill = HeatMapSharedLib.color(for: ch, bound: b, palette: effectivePalette, timeframe: timeframe, isLightMode: isLightMode)
            let labels = HeatMapSharedLib.labelColors(for: ch, bound: b, palette: effectivePalette, forceWhite: forceWhiteLabels, timeframe: timeframe, selected: selected, isLightMode: isLightMode)
            let badgeLabels = HeatMapSharedLib.badgeLabelColors(for: ch, bound: b, palette: effectivePalette, forceWhite: forceWhiteLabels, timeframe: timeframe, selected: selected, isLightMode: isLightMode)
            let outlineOpacity = HeatMapSharedLib.labelOutlineOpacity(for: ch, bound: b, palette: effectivePalette, timeframe: timeframe, isLightMode: isLightMode)
            let _ = isFallback // Silence unused warning
            let symbol = tile.id == "Others" ? tile.symbol : tile.symbol.uppercased()
            // SAFETY FIX: Handle NaN in accessibility label
            let accessibilityPercent = ch.isFinite ? String(format: "%+.1f%%", ch) : "N/A"
            
            // Adaptive border colors using DS.Adaptive design system
            let borderColor: Color = strongBorders 
                ? DS.Adaptive.strokeStrong 
                : DS.Adaptive.stroke
            let borderWidth: CGFloat = isDark
                ? (strongBorders ? 1.3 : 0.9)
                : (strongBorders ? 1.4 : 1.2)
            // Balanced inner glow - adds depth without washing out colors
            // LIGHT MODE FIX: Drastically reduced from 0.65 to 0.12 in light mode.
            // The previous 0.65 opacity white overlay was washing out all tile colors,
            // making everything look like the same pale green/gray.
            let innerGlowColor: Color = DS.Adaptive.gradientHighlight.opacity(isDark ? 0.35 : 0.12)
            let selectionBorderColor: Color = isDark 
                ? Color.white.opacity(0.95) 
                : DS.Adaptive.textPrimary.opacity(0.6)
            let selectionInnerColor: Color = isDark 
                ? Color.black.opacity(0.22) 
                : Color.white.opacity(0.4)

            // TIMEFRAME FALLBACK FIX: Use card background as fallback for seamless appearance
            // This ensures tiles blend with container during transitions
            let fallbackNeutral = DS.Adaptive.cardBackground
            
            let background: AnyView = AnyView(
                ZStack {
                    // Base fallback color - ensures tile is never black during transitions
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(fallbackNeutral)
                    // Actual calculated fill on top (uses colorWithFallback for smooth transitions)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(fill)
                }
                    .overlay(
                        LinearGradient(colors: [innerGlowColor, Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(borderColor, lineWidth: borderWidth)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .inset(by: 1)
                            .stroke(highlight ?? .clear, lineWidth: (highlight == nil ? 0 : 2))
                    )
                    .overlay(
                        Group {
                            if selected {
                                // Crisp inner highlight - adaptive for light mode
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .inset(by: 0.8)
                                    .stroke(selectionBorderColor, lineWidth: 1.6)
                                // Subtle inner separator for contrast
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .inset(by: 1.8)
                                    .stroke(selectionInnerColor, lineWidth: 0.9)
                            }
                        }
                    )
            )

            ZStack(alignment: .bottomLeading) {
                background

                GeometryReader { proxy in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    let minSide = min(width, height)
                    let safeInset = max(3, min(9, minSide * 0.12))
                    let aspect = width / max(1, height)
                    let useVerticalStack = (width <= 18 && height > width * 2.2) || aspect < 0.16 || minSide <= 24
                    let microMode = !selected && minSide <= 38
                    let overlayPadding: CGFloat = microMode ? 3 : (minSide > 100 ? 10 : (minSide > 85 ? 8 : 5))

                    // Percent chip metrics
                    let metrics = HeatMapSharedLib.badgeMetrics(width: width, height: height)
                    let chipHeight = metrics.font + metrics.vPad * 2 + 6

                    // Estimate label footprint
                    let estSymbolH: CGFloat = {
                        let s = min(width, height)
                        if s > 120 { return 22 }
                        if s < 28  { return 12 }
                        return 18
                    }()
                    let valueH: CGFloat = (showValues && minSide > labelDensity.treemapValuesMinSide) ? max(10, estSymbolH * 0.6) : 0
                    let hasSymbolLabel = !useVerticalStack && minSide > 24
                    let showsValueLine = showValues && minSide > labelDensity.treemapValuesMinSide && hasSymbolLabel
                    let labelHeight: CGFloat = hasSymbolLabel ? (overlayPadding + estSymbolH + (showsValueLine ? (2 + valueH) : 0) + overlayPadding) : 0

                    let hasVerticalClearance = (height - overlayPadding * 2) >= (chipHeight + labelHeight + 4)
                    let hasWidthForChipBase = (width - safeInset * 2) >= max(labelDensity.treemapPercentMinWidth, metrics.minW + metrics.hPad * 2)

                    let hasMinSideForPercent = (minSide >= labelDensity.treemapPercentMinSide)
                    // Keep "default percent" tiles readable; do not force chips into tiny cells.
                    let baseShow = defaultShowPercent && hasMinSideForPercent && minSide >= 42
                    // forceMicroChip removed – no longer referenced
                    // Estimate the height of the micro center label (used when useVerticalStack == true)
                    let microLettersFont: CGFloat = max(8, min(14, width * 0.70))
                    let microLabelHeightEst: CGFloat = microLettersFont + 4 // 2pt top/bottom padding
                    let microClearanceOK = (height - safeInset * 2) >= (chipHeight + (useVerticalStack && !selected ? microLabelHeightEst : 0) + 2)
                    let clearanceOK = useVerticalStack ? microClearanceOK : hasVerticalClearance

                    // Show percent. If selected, always show; we'll hide the micro name to avoid overlap in vertical mode.
                    let showPercent: Bool = {
                        if selected { return true }
                        return forceAllPercents || baseShow || (hasMinSideForPercent && hasWidthForChipBase && clearanceOK)
                    }()

                    // 1) Replacement for `needsMicro` line:
                    let needsMicro = ((!hasSymbolLabel) || useVerticalStack) && !selected

                    // Consistent label positioning for professional look:
                    // - Percent chip: always top-right
                    // - Symbol/micro name: always bottom-left
                    let cornerClearX = max(6, min(14, width * 0.06))
                    let edgeClearY = max(3, min(10, height * 0.06))

                    let horizontalPad = max(safeInset + 3, 6)
                    let borderClearance: CGFloat = selected ? 4 : 1.5

                    let hCornerPadPre = max(horizontalPad + borderClearance, cornerClearX + borderClearance)

                    // Symbol label - show on larger tiles (original behavior)
                    // Calculate font size to ensure symbol fits within available width
                    let symbolPadding: CGFloat = safeInset * 2 + 8  // Account for safeInset on both sides + background padding
                    let availableSymbolWidth = max(12, width - symbolPadding)
                    let charWidthRatioSymbol: CGFloat = 0.72  // Heavy weight chars are roughly 72% of font size
                    let maxFontForSymbol = availableSymbolWidth / (charWidthRatioSymbol * CGFloat(max(1, symbol.count)))
                    let symbolFont = max(8, min(16, maxFontForSymbol))
                    
                    let symbolOverlay: AnyView = AnyView(
                        Group {
                            if hasSymbolLabel && !selected {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(symbol)
                                        .font(.system(size: symbolFont, weight: .heavy))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                        .allowsTightening(true)
                                }
                                .foregroundColor(labels.text)
                                .background(labels.backdrop.opacity(1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(DS.Adaptive.overlay(0.18), lineWidth: 0.6)
                                )
                                .padding(safeInset)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            }
                        }
                    )

                    // Micro name for smaller tiles (original behavior)
                    let microOverlay: AnyView = AnyView(
                        Group {
                            if needsMicro && !selected {
                                let filtered = (tile.id == "Others" ? tile.symbol : tile.symbol.uppercased()).filter { $0.isLetter || $0.isNumber }
                                // Always show full symbol for short names (≤5 chars) - never truncate ADA, SOL, BTC, DOGE, etc.
                                let maxChars: Int = min(filtered.count, filtered.count <= 5 ? filtered.count : (width <= 10 ? 2 : (width <= 14 ? 3 : (width <= 20 ? 4 : 6))))
                                let letters = String(filtered.prefix(maxChars))
                                
                                // Calculate font size to fit text within tile width
                                // Account for: tile padding (safeInset*2), text background padding (6px), and character width ratio (~0.7 for heavy fonts)
                                let availableTextWidth = max(8, width - 6)  // 6px total padding for micro label background
                                let charWidthRatio: CGFloat = 0.72  // Heavy weight chars are roughly 72% of font size
                                let maxFontForFit = availableTextWidth / (charWidthRatio * CGFloat(max(1, letters.count)))
                                let microFont = max(5, min(13, maxFontForFit))
                                
                                let microAlignment: Alignment = useVerticalStack ? .center : .topLeading
                                MicroNameOverlayView(
                                    letters: letters,
                                    font: microFont,
                                    textColor: labels.text,
                                    backdrop: labels.backdrop,
                                    outlineOpacity: outlineOpacity
                                )
                                .padding(.top, useVerticalStack ? 0 : max(1, safeInset))
                                .padding(.leading, useVerticalStack ? 0 : max(1, safeInset))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: microAlignment)
                            }
                        }
                    )

                    // Percent chip calculations
                    let safeWidthBase = max(4, width - 2 * hCornerPadPre)
                    let availableBase = safeWidthBase
                    let maxWSelected = min(metrics.maxW * 1.25, safeWidthBase)
                    let available = min(availableBase, selected ? maxWSelected : metrics.maxW)
                    let compressionBase = available / max(metrics.minW, 1)
                    let compression = (availableBase < (metrics.minW + metrics.hPad * 2)) ? 0.62 : max(0.72, min(1.0, compressionBase))
                    let hPadEff = max(2, min(6, metrics.hPad * compression * 0.85))
                    let vPadEff = max(1.5, min(4, metrics.vPad * compression * 0.85))
                    let fontEff = max(9, min(13, metrics.font * (0.92 + 0.08 * min(1.0, compression))))
                    let chipText = HeatMapSharedLib.condensedPercentString(ch, availableWidth: max(4, available - (hPadEff * 2 + 4)))
                    let chipTextWidth = HeatMapSharedLib.measuredTextWidth(chipText, fontSize: fontEff, weight: .semibold)
                    let chipVisualWidth = chipTextWidth + (hPadEff * 2) + 8

                    // Hide percent on narrow tiles (< 30px) where it won't fit properly
                    let tooNarrowForPercent = width < 30
                    let preShow = selected ? true : (showPercent && (useVerticalStack ? microClearanceOK : hasVerticalClearance))
                    let chipHApprox = fontEff + vPadEff * 2 + 6
                    let minHeightOK = (height - 2 * safeInset) >= (chipHApprox + edgeClearY + borderClearance)
                    let minWidthOK = safeWidthBase >= max(12, chipVisualWidth)
                    // Reserve horizontal breathing room when symbol labels are visible.
                    let fitWithSymbolOK = !hasSymbolLabel || (width >= chipVisualWidth + 30)
                    
                    let showPercentChip = preShow && minHeightOK && minWidthOK && fitWithSymbolOK && !tooNarrowForPercent && !selected
                    let showCenterMicroChip = selected

                    // Percent chip positioning
                    let chipPad = max(3, safeInset)
                    let chipOverlay: AnyView = AnyView(
                        Group {
                            if showPercentChip {
                                SimplePercentChip(
                                    text: chipText,
                                    fontSize: fontEff,
                                    textColor: badgeLabels.text,
                                    backdrop: badgeLabels.backdrop,
                                    minWidth: 0,
                                    maxWidth: available,
                                    hPad: hPadEff,
                                    vPad: vPadEff
                                )
                                .scaleEffect(chipPop ? 1.08 : 1.0)
                                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: chipPop)
                                .transition(.asymmetric(insertion: .offset(y: -6).combined(with: .opacity), removal: .opacity))
                                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showPercentChip)
                                .padding(.top, chipPad)
                                .padding(.trailing, chipPad)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .allowsHitTesting(false)
                            }
                        }
                    )
                    
                    let centerChipOverlay: AnyView = AnyView(
                        Group {
                            if showCenterMicroChip {
                                let centerAvailW = max(4, width - 2 * safeInset)
                                let centerAvailH = max(4, height - 2 * safeInset)
                                let microHPad: CGFloat = max(1, min(4, centerAvailW * 0.08))
                                let microVPad: CGFloat = max(0.8, min(3, centerAvailH * 0.08))
                                let microFont = max(7, min(13, min(centerAvailW, centerAvailH) * 0.45))
                                let microText = HeatMapSharedLib.condensedPercentString(ch, availableWidth: max(3, centerAvailW - (microHPad * 2 + 4)))
                                SimplePercentChip(
                                    text: microText,
                                    fontSize: microFont,
                                    textColor: badgeLabels.text,
                                    backdrop: badgeLabels.backdrop,
                                    minWidth: 0,
                                    maxWidth: centerAvailW,
                                    hPad: microHPad,
                                    vPad: microVPad
                                )
                                .scaleEffect(chipPop ? 1.08 : 1.0)
                                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: chipPop)
                                .transition(.scale.combined(with: .opacity))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                .allowsHitTesting(false)
                            }
                        }
                    )

                    // Replaced overlays with mask:
                    let overlays: AnyView = AnyView(
                        ZStack {
                            symbolOverlay
                            microOverlay
                            chipOverlay
                            centerChipOverlay
                        }
                        .mask(RoundedRectangle(cornerRadius: 8, style: .continuous).inset(by: selected ? 2.0 : 1.0))
                    )

                    overlays
                }
            }
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .clipped(antialiased: true)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selected)
            // SMOOTH COLOR TRANSITION: Animate fill color when timeframe changes or data updates.
            // Colors crossfade through neutral gray which looks professional (like Bloomberg/Finviz).
            .animation(.easeInOut(duration: 0.45), value: timeframe)
            .animation(.easeInOut(duration: 0.6), value: ch)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(symbol))
            .accessibilityValue(Text(accessibilityPercent))
            .accessibilityHint(Text("Tap to select. Long-press for actions."))
            .accessibilityAddTraits(.isButton)
            .allowsHitTesting(true)
            .onTapGesture {
                Haptics.light.impactOccurred()
                chipPop = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { chipPop = false }
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                Haptics.medium.impactOccurred()
                onLongPress()
            }
            .onChange(of: selected) { _, isSelected in
                if isSelected {
                    chipPop = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { chipPop = false }
                }
            }
        }

        private struct ChipOverlayView: View {
            let chipText: String
            let fontSize: CGFloat
            let textColor: Color
            let backdrop: Color
            let minWidth: CGFloat
            let maxWidth: CGFloat
            let hPad: CGFloat
            let vPad: CGFloat
            let alignment: Alignment
            let topPadding: CGFloat
            let horizontalPadding: CGFloat

            var body: some View {
                ZStack {
                    SimplePercentChip(
                        text: chipText,
                        fontSize: fontSize,
                        textColor: textColor,
                        backdrop: backdrop,
                        minWidth: minWidth,
                        maxWidth: maxWidth,
                        hPad: hPad,
                        vPad: vPad
                    )
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .padding(.top, topPadding)
                .padding(.horizontal, horizontalPadding)
                .clipped(antialiased: true)
            }
        }

        private struct MicroNameOverlayView: View {
            let letters: String
            let font: CGFloat
            let textColor: Color
            let backdrop: Color
            let outlineOpacity: Double

            var body: some View {
                // LABEL FIX: Removed truncationMode to prevent "..." appearing in labels
                // Text length is already controlled by maxChars calculation
                // TRUNCATION FIX: Added .fixedSize() to guarantee no "..." truncation
                Text(letters)
                    .font(.system(size: font, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(textColor)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(backdrop, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
    }
}

