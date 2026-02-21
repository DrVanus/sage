import SwiftUI
import UIKit
import Combine
import Foundation

public enum HeatMapSharedLib {
    // MARK: - Lightweight shared haptics
    public enum Haptics {
        public static let light = UIImpactFeedbackGenerator(style: .light)
        public static let medium = UIImpactFeedbackGenerator(style: .medium)
        public static let notify = UINotificationFeedbackGenerator()
    }

    // MARK: - Treemap squarify layout
    public static func squarify(
        items: [HeatMapTile],
        weights: [Double],
        rect: CGRect
    ) -> [CGRect] {
        // SAFETY FIX: Input validation to prevent crashes and invalid layouts
        guard !items.isEmpty else { return [] }
        guard items.count == weights.count else {
            // Mismatched arrays - return empty to prevent crash
            return []
        }
        guard rect.width > 0 && rect.height > 0 && rect.width.isFinite && rect.height.isFinite else {
            // Invalid rect - return empty rectangles for each item
            return Array(repeating: .zero, count: items.count)
        }
        
        var rects: [CGRect] = []
        let pairs = Array(zip(items, weights))
        let totalItems = items.count
        
        // Adaptive thresholds for squarify layout - scales with tile count
        // LAYOUT FIX: Further lowered thresholds for 15-24 coin counts to prevent layout breakage
        // Even lower values allow the algorithm more flexibility in creating balanced layouts
        let adaptiveMinSplit: CGFloat = {
            if totalItems >= 25 { return 16 }
            else if totalItems >= 22 { return 12 }
            else if totalItems >= 18 { return 10 }
            else if totalItems >= 14 { return 8 }
            else if totalItems >= 10 { return 7 }
            else { return 6 }  // For ≤9 tiles, maximum flexibility
        }()
        let adaptiveRowThickness: CGFloat = {
            if totalItems >= 25 { return 14 }
            else if totalItems >= 22 { return 10 }
            else if totalItems >= 18 { return 8 }
            else if totalItems >= 14 { return 6 }
            else if totalItems >= 10 { return 5 }
            else { return 4 }
        }()
        let adaptiveMinRow: CGFloat = {
            if totalItems >= 25 { return 16 }
            else if totalItems >= 22 { return 12 }
            else if totalItems >= 18 { return 10 }
            else if totalItems >= 14 { return 8 }
            else if totalItems >= 10 { return 7 }
            else { return 6 }
        }()
        let adaptiveSliceThickness: CGFloat = {
            if totalItems >= 25 { return 12 }
            else if totalItems >= 22 { return 9 }
            else if totalItems >= 18 { return 7 }
            else if totalItems >= 14 { return 6 }
            else if totalItems >= 10 { return 5 }
            else { return 4 }
        }()

        func normalize(_ slice: ArraySlice<(HeatMapTile, Double)>) -> Double {
            slice.reduce(0.0) { $0 + max(0, $1.1) }
        }

        func worst(_ row: ArraySlice<(HeatMapTile, Double)>, total: Double, in r: CGRect, horizontal: Bool) -> CGFloat {
            let rowTotal = max(1e-12, normalize(row))
            // SAFETY FIX: Protect against zero/invalid dimensions
            let area = max(1e-12, r.width * r.height)
            let side = max(1e-6, horizontal ? r.height : r.width)
            let otherSide = max(1e-6, (horizontal ? r.width : r.height) * CGFloat(rowTotal / total))
            var worst: CGFloat = 0
            for (_, w) in row {
                let tileArea = CGFloat(max(0, w) / total) * area
                let length = max(1e-6, tileArea / max(1e-6, otherSide))
                let ratio = max(length / side, side / length)
                if ratio > worst { worst = ratio }
            }
            return worst == 0 ? .infinity : worst
        }

        func layout(_ list: ArraySlice<(HeatMapTile, Double)>, in r: CGRect) {
            guard !list.isEmpty else { return }
            // SAFETY FIX: Validate rect before proceeding
            guard r.width > 0 && r.height > 0 else { return }
            let total = max(1e-12, normalize(list))
            let minSplitDim: CGFloat = adaptiveMinSplit
            var horizontal = r.width >= r.height
            // Avoid splitting along a tiny dimension: if width is too small, split along height (horizontal = true);
            // if height is too small, split along width (horizontal = false).
            if r.width < minSplitDim && r.height >= minSplitDim { horizontal = true }
            if r.height < minSplitDim && r.width >= minSplitDim { horizontal = false }

            var row: ArraySlice<(HeatMapTile, Double)> = list.prefix(1)
            var remaining = list.dropFirst()

            while !remaining.isEmpty {
                let candidate = row + remaining.prefix(1)
                // Row-level minimum thickness: avoid packing so many items that slices become unreadably thin
                let minThicknessBase: CGFloat = adaptiveRowThickness
                let dim = horizontal ? r.height : r.width
                if CGFloat(candidate.count) * minThicknessBase > dim {
                    break
                }
                if worst(candidate, total: total, in: r, horizontal: horizontal) <= worst(row, total: total, in: r, horizontal: horizontal) {
                    row = candidate
                    remaining = remaining.dropFirst()
                } else {
                    break
                }
            }

            // Lay out the accepted row, but avoid creating a too-thin leftover region
            var rowTotal = max(1e-12, normalize(row))
            var rowFrac = rowTotal / total
            let minRowThickness: CGFloat = adaptiveMinRow
            let leftoverDimEst: CGFloat = horizontal ? (r.width * CGFloat(1 - rowFrac)) : (r.height * CGFloat(1 - rowFrac))
            if leftoverDimEst > 0 && leftoverDimEst < minRowThickness {
                // Expand this row to consume all remaining items to avoid a skinny leftover strip
                row = list
                remaining = list.dropFirst(list.count)
                rowTotal = max(1e-12, normalize(row))
                rowFrac = 1.0
            }
            let rowRect: CGRect
            let leftover: CGRect
            // SAFETY FIX: Clamp rowFrac to [0, 1] and ensure non-negative dimensions
            let clampedRowFrac = max(0, min(1, rowFrac))
            if horizontal {
                let w = r.width * CGFloat(clampedRowFrac)
                rowRect = CGRect(x: r.minX, y: r.minY, width: w, height: r.height)
                leftover = CGRect(x: r.minX + w, y: r.minY, width: max(0, r.width - w), height: r.height)
            } else {
                let h = r.height * CGFloat(clampedRowFrac)
                rowRect = CGRect(x: r.minX, y: r.minY, width: r.width, height: h)
                leftover = CGRect(x: r.minX, y: r.minY + h, width: r.width, height: max(0, r.height - h))
            }

            // Enforce a minimum thickness along the split dimension while preserving coverage
            let fracs: [Double] = row.map { $0.1 / rowTotal }
            let dimension: CGFloat = horizontal ? rowRect.height : rowRect.width
            let minThicknessBase: CGFloat = adaptiveSliceThickness
            // If the row is too small to give everyone min thickness, reduce the effective floor
            let count = CGFloat(fracs.count)
            var minEff = minThicknessBase
            if count * minEff > dimension { minEff = dimension / max(1, count) }
            // Base lengths along the split dimension
            let baseLengths: [CGFloat] = fracs.map { CGFloat($0) * dimension }
            var lengths: [CGFloat] = baseLengths.map { max(minEff, $0) }
            var sumLengths = lengths.reduce(0, +)
            if sumLengths > dimension + 0.5 { // shrink extras proportionally
                let adjustable = lengths.reduce(0) { $0 + max(0, $1 - minEff) }
                if adjustable > 1e-6 {
                    let over = sumLengths - dimension
                    let shrinkFactor = max(0, (adjustable - over) / adjustable)
                    for i in 0..<lengths.count {
                        let extra = max(0, lengths[i] - minEff)
                        lengths[i] = minEff + extra * shrinkFactor
                    }
                    sumLengths = lengths.reduce(0, +)
                } else {
                    // All at floor; distribute equally
                    let equal = dimension / max(1, count)
                    lengths = Array(repeating: equal, count: Int(count))
                    sumLengths = lengths.reduce(0, +)
                }
            }
            // Lay out slices using the adjusted lengths; force the last slice to fill any rounding remainder
            var offset: CGFloat = 0
            for i in 0..<lengths.count {
                let len = (i == lengths.count - 1) ? max(0, dimension - offset) : lengths[i]
                let slice: CGRect
                if horizontal {
                    slice = CGRect(x: rowRect.minX, y: rowRect.minY + offset, width: rowRect.width, height: len)
                } else {
                    slice = CGRect(x: rowRect.minX + offset, y: rowRect.minY, width: len, height: rowRect.height)
                }
                rects.append(slice)
                offset += len
            }

            layout(remaining, in: leftover)
        }

        layout(pairs[...], in: rect)
        return rects
    }

    // MARK: - HeatMap timeframe and helpers
    public enum HeatMapTimeframe: String, CaseIterable, Identifiable {
        case hour1 = "1h", day1 = "24h", day7 = "7d"
        public var id: String { rawValue }
    }

    /// Check if actual data is available for the given timeframe.
    /// This helps distinguish between "0% change" (legitimate) and "missing data".
    /// SIMPLIFIED: If the value is finite, we treat it as valid data. 0% is a legitimate value.
    @inline(__always) public static func hasData(for tile: HeatMapTile, tf: HeatMapSharedLib.HeatMapTimeframe) -> Bool {
        switch tf {
        case .hour1:
            // 1h data is optional - check if present and finite
            return tile.pctChange1h != nil && tile.pctChange1h!.isFinite
        case .day1:
            // 24h is the primary field - if it's finite, the tile has valid data
            // A 0% change is legitimate (stablecoins, sideways markets)
            let d = tile.pctChange24h
            if !d.isFinite { return false }
            // SIMPLIFIED: If value is finite, treat as valid data
            // Previously this was too aggressive in marking 0% as "missing"
            return true
        case .day7:
            // 7d data is optional - check if present and finite
            return tile.pctChange7d != nil && tile.pctChange7d!.isFinite
        }
    }
    
    /// Check if tile has ANY valid data across all timeframes.
    /// Returns true if at least one timeframe has valid data.
    /// Used to determine if tile should show "missing data" color vs fallback color.
    @inline(__always) public static func hasAnyData(for tile: HeatMapTile) -> Bool {
        // Check 24h first (primary data source)
        if tile.pctChange24h.isFinite { return true }
        // Check 1h
        if let h = tile.pctChange1h, h.isFinite { return true }
        // Check 7d
        if let d = tile.pctChange7d, d.isFinite { return true }
        return false
    }
    
    /// Get the best available change value for a tile, with fallback chain.
    /// Priority: requested timeframe -> 24h -> 1h -> 7d -> 0
    /// This prevents gray flash when switching timeframes by always returning a usable value.
    @inline(__always) public static func changeWithFallback(for tile: HeatMapTile, tf: HeatMapSharedLib.HeatMapTimeframe) -> (value: Double, isFallback: Bool) {
        // First try the requested timeframe
        switch tf {
        case .hour1:
            if let h = tile.pctChange1h, h.isFinite { return (h, false) }
        case .day1:
            if tile.pctChange24h.isFinite { return (tile.pctChange24h, false) }
        case .day7:
            if let d = tile.pctChange7d, d.isFinite { return (d, false) }
        }
        
        // Fallback chain: 24h is most reliable
        if tile.pctChange24h.isFinite { return (tile.pctChange24h, true) }
        if let h = tile.pctChange1h, h.isFinite { return (h, true) }
        if let d = tile.pctChange7d, d.isFinite { return (d, true) }
        
        // No data at all
        return (0, true)
    }
    
    @inline(__always) public static func change(for tile: HeatMapTile, tf: HeatMapSharedLib.HeatMapTimeframe) -> Double {
        // Return actual data only - no faulty estimation fallbacks
        // Each timeframe is independent (a coin can be +10% over 24h but -5% in the last hour)
        switch tf {
        case .hour1:
            if let h = tile.pctChange1h, h.isFinite { return h }
            return 0  // No estimate - actual 1h value unavailable
        case .day1:
            let d = tile.pctChange24h
            if d.isFinite { return d }
            return 0  // No estimate - actual 24h value unavailable
        case .day7:
            if let w = tile.pctChange7d, w.isFinite { return w }
            return 0  // No estimate - actual 7d value unavailable
        }
    }
    
    /// Returns the change value, or nil if data is not actually available.
    /// Use this when you need to distinguish "0% change" from "missing data".
    @inline(__always) public static func changeOrNil(for tile: HeatMapTile, tf: HeatMapSharedLib.HeatMapTimeframe) -> Double? {
        guard hasData(for: tile, tf: tf) else { return nil }
        return change(for: tile, tf: tf)
    }

    @inline(__always) public static func bound(for tf: HeatMapSharedLib.HeatMapTimeframe) -> Double {
        // Visual bound model determines when colors reach full saturation
        // A coin at ±bound% will show maximum red/green color
        //
        // Modes (UserDefaults key: heatmap.scaleMode):
        // - "pertf" (default): each timeframe has its own bound optimized for typical moves
        // - "global": one shared bound for all timeframes (heatmap.globalBound, default ±5)
        // - "locked": user-locked bound (heatmap.lockedBound)
        switch currentScaleMode() {
        case "locked":
            return lockedScaleBound()
        case "global":
            return globalScaleBound()
        default: // "pertf"
            // Bounds optimized for typical crypto volatility in each timeframe:
            // - 1h: Small moves matter, ±3% reaches full color (typical hourly swing)
            // - 24h: ±5% reaches full color (typical daily move)  
            // - 7d: ±10% reaches full color (typical weekly move)
            // Anything beyond these bounds shows max color intensity
            switch tf {
            case .hour1: return 3
            case .day1:  return 5
            case .day7:  return 10
            }
        }
    }

    // Color scale mode and bounds
    // heatmap.scaleMode: "pertf" (default), "global", or "locked"
    private static func currentScaleMode() -> String {
        let raw = (UserDefaults.standard.string(forKey: "heatmap.scaleMode") ?? "pertf").lowercased()
        switch raw {
        case "pertf", "per_tf", "per-timeframe", "pertimeframe", "per timeframe", "pertime":
            return "pertf"
        case "global":
            return "global"
        case "locked":
            return "locked"
        default:
            // Be safe and treat unknown values as per-timeframe
            return "pertf"
        }
    }
    private static func globalScaleBound() -> Double {
        let v = UserDefaults.standard.double(forKey: "heatmap.globalBound")
        return v > 0 ? v : 5.0 // default global visual bound ±5% (matches 24h default)
    }
    private static func lockedScaleBound() -> Double {
        let v = UserDefaults.standard.double(forKey: "heatmap.lockedBound")
        return v > 0 ? v : globalScaleBound()
    }

    @inline(__always) private static func effectiveVisualBound(_ passed: Double) -> Double {
        switch currentScaleMode() {
        case "pertf":
            return passed
        case "locked":
            return lockedScaleBound()
        default:
            return globalScaleBound()
        }
    }

    @inline(__always) private static func boostSmall() -> Bool { UserDefaults.standard.object(forKey: "heatmap.boostSmall") as? Bool ?? true }

    // MARK: - Weighting curve and label density
    public enum WeightingCurve: String, CaseIterable, Identifiable {
        case linear = "Linear"
        case balanced = "Balanced"
        case compact = "Compact"
        public var id: String { rawValue }
        var exponent: Double {
            switch self {
            case .linear: return 1.0
            case .balanced: return 0.7
            case .compact: return 0.5
            }
        }
    }

    public enum LabelDensity: String, CaseIterable, Identifiable {
        case compact = "Compact"
        case normal = "Normal"
        case detailed = "Detailed"
        public var id: String { rawValue }
        var treemapPercentMinSide: CGFloat { switch self { case .compact: return 64; case .normal: return 52; case .detailed: return 40 } }
        var treemapValuesMinSide: CGFloat { switch self { case .compact: return 120; case .normal: return 92; case .detailed: return 70 } }
        var treemapPercentMinWidth: CGFloat { switch self { case .compact: return 62; case .normal: return 50; case .detailed: return 40 } }
        var barPercentMinWidth: CGFloat { switch self { case .compact: return 80; case .normal: return 62; case .detailed: return 48 } }
        var barValuesMinWidth: CGFloat { switch self { case .compact: return 150; case .normal: return 110; case .detailed: return 90 } }
        var gridPercentMinWidth: CGFloat { switch self { case .compact: return 90; case .normal: return 110; case .detailed: return 80 } }
        var gridValuesMinWidth: CGFloat { switch self { case .compact: return 120; case .normal: return 140; case .detailed: return 100 } }
    }

    // MARK: - Color palette (uses HeatMapColorPalette from HeatMapColors.swift)
    public typealias ColorPalette = HeatMapColorPalette
    
    /// Parse raw string to ColorPalette
    /// Cool = Modern Pro style, Classic = Traditional, Warm = Amber
    public static func colorPaletteFromAnyRaw(_ raw: String) -> ColorPalette {
        switch raw.lowercased() {
        // Cool = Modern Pro - Pure Red → Gray → Pure Green
        case "cool", "pro", "nasdaq", "finviz", "default", "gray", "grey", "modern": return .cool
        // Classic = Bloomberg Terminal - Crimson → Navy Slate → Forest Green
        case "classic", "bloomberg", "terminal", "stock", "exchange", "traditional": return .classic
        // Warm = Contemporary warm - Coral → Amber → Teal
        case "warm", "amber", "bronze", "gold", "premium", "yellow": return .warm
        default: return .cool
        }
    }

    // MARK: - Color math helpers (sRGB, Oklab, contrast)
    @inline(__always) private static func clamp01(_ x: Double) -> Double { min(1.0, max(0.0, x)) }
    @inline(__always) private static func srgbToLinear(_ c: Double) -> Double { c <= 0.04045 ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4) }
    @inline(__always) private static func linearToSrgb(_ c: Double) -> Double { c <= 0.0031308 ? (12.92 * c) : (1.055 * pow(c, 1.0/2.4) - 0.055) }
    @inline(__always) private static func relativeLuminance(_ rgb: (Double, Double, Double)) -> Double {
        let r = srgbToLinear(rgb.0), g = srgbToLinear(rgb.1), b = srgbToLinear(rgb.2)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    @inline(__always) private static func contrastRatio(_ fg: (Double, Double, Double), _ bg: (Double, Double, Double)) -> Double {
        let L1 = relativeLuminance(fg), L2 = relativeLuminance(bg)
        let (a, b) = L1 > L2 ? (L1, L2) : (L2, L1)
        return (a + 0.05) / (b + 0.05)
    }
    @inline(__always) private static func smoothstep(_ x: Double) -> Double { let t = max(0, min(1, x)); return t * t * (3 - 2 * t) }

    @inline(__always) private static func rgbToOklab(_ rgb: (Double, Double, Double)) -> (L: Double, a: Double, b: Double) {
        let rLin = srgbToLinear(rgb.0), gLin = srgbToLinear(rgb.1), bLin = srgbToLinear(rgb.2)
        let l = 0.4122214708*rLin + 0.5363325363*gLin + 0.0514459929*bLin
        let m = 0.2119034982*rLin + 0.6806995451*gLin + 0.1073969566*bLin
        let s = 0.0883024619*rLin + 0.2817188376*gLin + 0.6299787005*bLin
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        let L = 0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_
        let a = 1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_
        let b = 0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_
        return (L, a, b)
    }
    @inline(__always) private static func oklabToRgb(_ lab: (L: Double, a: Double, b: Double)) -> (Double, Double, Double) {
        let l_ = lab.L + 0.3963377774*lab.a + 0.2158037573*lab.b
        let m_ = lab.L - 0.1055613458*lab.a - 0.0638541728*lab.b
        let s_ = lab.L - 0.0894841775*lab.a - 1.2914855480*lab.b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        var r =  4.0767416621*l - 3.3077115913*m + 0.2309699292*s
        var g = -1.2684380046*l + 2.6097574011*m - 0.3413193965*s
        var b =  0.0041960863*l - 0.7034186147*m + 1.6990626434*s
        r = linearToSrgb(r); g = linearToSrgb(g); b = linearToSrgb(b)
        return (clamp01(r), clamp01(g), clamp01(b))
    }
    @inline(__always) private static func oklabLerp(_ aRGB: (Double, Double, Double), _ bRGB: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
        let a = rgbToOklab(aRGB), b = rgbToOklab(bRGB)
        let L = a.L + (b.L - a.L) * t
        let A = a.a + (b.a - a.a) * t
        let B = a.b + (b.b - a.b) * t
        return oklabToRgb((L, A, B))
    }

    // Shared emerald to match sentiment gauge
    private static let GaugeGreen: (Double, Double, Double) = HeatMapColors.GaugeGreen

    /// Auto-detect whether we're in light mode by checking the current UITraitCollection.
    /// Falls back to the manual "heatmap.grayNeutral" setting if detection fails.
    @inline(__always) private static func isCurrentlyLightMode() -> Bool {
        // First check if user has manually overridden via settings
        if UserDefaults.standard.object(forKey: "heatmap.grayNeutral") != nil {
            return UserDefaults.standard.bool(forKey: "heatmap.grayNeutral")
        }
        // Auto-detect from system appearance
        #if canImport(UIKit)
        return UITraitCollection.current.userInterfaceStyle == .light
        #else
        return false
        #endif
    }

    private static func currentSaturation() -> Double {
        let v = UserDefaults.standard.double(forKey: "heatmap.saturation")
        let base = (v == 0) ? 0.95 : v
        return min(1.4, max(0.6, base))
    }
    @inline(__always) private static func applySaturation(to rgb: (Double, Double, Double), factor: Double) -> (Double, Double, Double) {
        let lum = 0.2126 * rgb.0 + 0.7152 * rgb.1 + 0.0722 * rgb.2
        let gray = (lum, lum, lum)
        let r = clamp01(gray.0 + (rgb.0 - gray.0) * factor)
        let g = clamp01(gray.1 + (rgb.1 - gray.1) * factor)
        let b = clamp01(gray.2 + (rgb.2 - gray.2) * factor)
        return (r, g, b)
    }

    // MARK: - Simple Linear Interpolation
    
    /// Direct linear interpolation between two colors
    @inline(__always) private static func lerp(
        _ a: (Double, Double, Double),
        _ b: (Double, Double, Double),
        _ t: Double
    ) -> (Double, Double, Double) {
        let clamped = clamp01(t)
        return (
            a.0 + (b.0 - a.0) * clamped,
            a.1 + (b.1 - a.1) * clamped,
            a.2 + (b.2 - a.2) * clamped
        )
    }

    // MARK: - Unified Fill Function
    
    /// Heat map color calculation with proper scaling per timeframe.
    ///
    /// DESIGN PRINCIPLE: Each palette has its own distinct personality:
    /// - Cool (Pro): Gray midpoint, vivid neon greens/reds, quick punch (Finviz-style)
    /// - Classic: Navy-slate midpoint, forest green/crimson, slow refined emergence (Bloomberg-style)
    /// - Warm: Gold midpoint, lime/vermillion, natural blends (premium warm)
    ///
    /// Uses palette-specific deadband and gamma for smooth, professional blends.
    /// 3-zone interpolation: Neutral → Mild/Base → Max
    @inline(__always) public static func fillRGB(pct: Double, bound: Double, palette: HeatMapSharedLib.ColorPalette, timeframe: HeatMapTimeframe? = nil, isLightMode: Bool? = nil) -> (Double, Double, Double) {
        let vBound = effectiveVisualBound(bound)
        let lightMode = isLightMode ?? isCurrentlyLightMode()
        let anchors = HeatMapColors.anchors(for: palette, isLightMode: lightMode)
        
        // Handle invalid input
        guard pct.isFinite else {
            return anchors.neutral
        }
        
        let absPct = abs(pct)
        
        // Get palette-specific deadband and gamma
        let deadband = palette.deadband  // Values below this show neutral
        let gamma = palette.gamma        // Higher = smoother blend curve
        
        // 3-ZONE COLOR SYSTEM with palette-specific tuning:
        // Zone 1 (0-deadband): Neutral (unchanged)
        // Zone 2 (deadband-midpoint): Neutral → Base (color emerges smoothly)
        // Zone 3 (midpoint-bound): Base → Max (saturation intensifies)
        
        let neutralThreshold: Double = deadband
        let midThreshold: Double = max(deadband * 3, vBound * 0.30)  // ~30% of bound for tint zone
        let maxThreshold: Double = max(1.0, vBound)  // Use actual bound for full saturation
        
        let rgb: (Double, Double, Double)
        
        if absPct <= neutralThreshold {
            // Zone 1: Within deadband - show neutral color
            rgb = anchors.neutral
        } else if absPct <= midThreshold {
            // Zone 2: Small change - interpolate from neutral to base
            let t = (absPct - neutralThreshold) / (midThreshold - neutralThreshold)
            // Use palette gamma for smooth color emergence
            let curvedT = pow(t, gamma)
            
            if pct > 0 {
                rgb = oklabLerp(anchors.neutral, anchors.greenBase, curvedT)
            } else {
                rgb = oklabLerp(anchors.neutral, anchors.redBase, curvedT)
            }
        } else {
            // Zone 3: Larger change - interpolate from base to max
            let t = min(1.0, (absPct - midThreshold) / (maxThreshold - midThreshold))
            // Use slightly lower gamma for saturation ramp
            let curvedT = pow(t, gamma * 0.85)
            
            if pct > 0 {
                rgb = oklabLerp(anchors.greenBase, anchors.greenMax, curvedT)
            } else {
                rgb = oklabLerp(anchors.redBase, anchors.redMax, curvedT)
            }
        }
        
        // Apply user saturation setting
        let satFactor = currentSaturation()
        return applySaturation(to: rgb, factor: satFactor)
    }
    
    /// Legacy fillRGB without timeframe - defaults to 24h behavior
    @inline(__always) public static func fillRGB(pct: Double, bound: Double, palette: HeatMapSharedLib.ColorPalette, isLightMode: Bool? = nil) -> (Double, Double, Double) {
        return fillRGB(pct: pct, bound: bound, palette: palette, timeframe: .day1, isLightMode: isLightMode)
    }

    // MARK: - OLED Safety: Minimum brightness floor
    
    /// Ensure color is never too dark for OLED screens
    /// Returns RGB with minimum brightness guarantee
    /// 16% minimum luminance ensures visibility without washing out colors
    @inline(__always) private static func ensureOLEDVisible(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        // Calculate luminance
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        // Balanced minimum luminance: 16% ensures visibility without washing out colors
        let minLum: Double = 0.16
        if lum < minLum && lum > 0.001 {
            let scale = minLum / lum
            return (min(1.0, r * scale), min(1.0, g * scale), min(1.0, b * scale))
        } else if lum <= 0.001 {
            // Pure black - return color matching Cool palette neutral
            return (0.28, 0.28, 0.28)
        }
        return (r, g, b)
    }

    public static func color(for pct: Double, bound: Double, isLightMode: Bool? = nil) -> Color { color(for: pct, bound: bound, palette: .cool, isLightMode: isLightMode) }
    public static func color(for pct: Double, bound: Double, palette: HeatMapSharedLib.ColorPalette, isLightMode: Bool? = nil) -> Color {
        let lightMode = isLightMode ?? isCurrentlyLightMode()
        let rgb = fillRGB(pct: pct, bound: bound, palette: palette, isLightMode: lightMode)
        let r = rgb.0.isFinite ? rgb.0 : 0.35
        let g = rgb.1.isFinite ? rgb.1 : 0.35
        let b = rgb.2.isFinite ? rgb.2 : 0.35
        // OLED SAFETY: Only apply brightness floor in dark mode
        if lightMode {
            return Color(red: r, green: g, blue: b)
        }
        let safe = ensureOLEDVisible(r, g, b)
        return Color(red: safe.0, green: safe.1, blue: safe.2)
    }
    
    /// Color with timeframe-aware intensity boost
    public static func color(for pct: Double, bound: Double, palette: HeatMapSharedLib.ColorPalette, timeframe: HeatMapTimeframe, isLightMode: Bool? = nil) -> Color {
        let lightMode = isLightMode ?? isCurrentlyLightMode()
        let rgb = fillRGB(pct: pct, bound: bound, palette: palette, timeframe: timeframe, isLightMode: lightMode)
        let r = rgb.0.isFinite ? rgb.0 : 0.35
        let g = rgb.1.isFinite ? rgb.1 : 0.35
        let b = rgb.2.isFinite ? rgb.2 : 0.35
        // OLED SAFETY: Only apply brightness floor in dark mode.
        // LIGHT MODE FIX: Skip in light mode - it's not needed and can push
        // already-light colors even lighter, reducing contrast between tiles.
        if lightMode {
            return Color(red: r, green: g, blue: b)
        }
        let safe = ensureOLEDVisible(r, g, b)
        return Color(red: safe.0, green: safe.1, blue: safe.2)
    }
    
    /// Distinct color for tiles with MISSING data (vs "0% change" which is valid data)
    /// Returns a muted lavender-gray that's clearly distinguishable from ALL palette neutrals:
    /// - Cool neutral: pure gray (0.28, 0.28, 0.28)
    /// - Classic neutral: navy slate (0.22, 0.24, 0.30)
    /// - Warm neutral: gold (0.75, 0.62, 0.25)
    /// This color is INTENTIONALLY different from all neutrals to visually indicate "no data"
    public static func colorForMissingData() -> Color {
        // Muted lavender-gray - distinct from Cool gray, Classic navy, and Warm gold
        return Color(red: 0.48, green: 0.44, blue: 0.56)
    }
    
    /// Color for a tile with graceful fallback when requested timeframe data is missing.
    /// If the exact timeframe data is missing but other data exists, uses fallback with reduced saturation.
    /// Only shows "missing data" color if NO data exists at all.
    /// - Parameter isLightMode: Optional explicit light mode flag. If nil, uses auto-detection.
    public static func colorWithFallback(for tile: HeatMapTile, bound: Double, palette: HeatMapSharedLib.ColorPalette, timeframe: HeatMapTimeframe, isLightMode: Bool? = nil) -> Color {
        let (changeValue, isFallback) = changeWithFallback(for: tile, tf: timeframe)
        
        // If we have no data at all, show missing data color
        if !hasAnyData(for: tile) {
            return colorForMissingData()
        }
        
        // Calculate the color
        let baseColor = color(for: changeValue, bound: bound, palette: palette, timeframe: timeframe, isLightMode: isLightMode)
        
        // If using fallback data, slightly reduce saturation to indicate it's not exact
        // But keep it subtle so the transition is smooth
        if isFallback {
            // Apply 90% saturation to indicate fallback (subtle but noticeable)
            return desaturate(baseColor, factor: 0.90)
        }
        
        return baseColor
    }
    
    /// Desaturate a color by blending toward gray
    private static func desaturate(_ color: Color, factor: Double) -> Color {
        // Convert to RGB components
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // Calculate luminance
        let lum = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
        
        // Blend toward gray based on factor
        let newR = lum + (Double(r) - lum) * factor
        let newG = lum + (Double(g) - lum) * factor
        let newB = lum + (Double(b) - lum) * factor
        
        return Color(red: newR, green: newG, blue: newB)
        #else
        return color
        #endif
    }
    
    /// Color for a tile, accounting for missing data
    /// Returns a distinct "missing data" color if data is unavailable for the timeframe
    public static func colorForTile(_ tile: HeatMapTile, bound: Double, palette: HeatMapSharedLib.ColorPalette, timeframe: HeatMapTimeframe) -> Color {
        // Check if data is actually available for this timeframe
        guard hasData(for: tile, tf: timeframe) else {
            return colorForMissingData()
        }
        let pct = change(for: tile, tf: timeframe)
        return color(for: pct, bound: bound, palette: palette, timeframe: timeframe)
    }

    // MARK: - Label contrast helpers
    
    // Premium text colors for optimal readability
    // Light text: #F3F4F6 for dark tiles
    // Dark text: #101114 for bright tiles
    private static let lightTextColor = Color(red: 0.953, green: 0.957, blue: 0.965)  // #F3F4F6
    private static let darkTextColor = Color(red: 0.063, green: 0.067, blue: 0.078)   // #101114
    
    public static func labelColors(for pct: Double, bound: Double, palette: HeatMapSharedLib.ColorPalette, forceWhite: Bool = false, timeframe: HeatMapTimeframe? = nil, selected: Bool = false, isLightMode: Bool? = nil) -> (text: Color, backdrop: Color) {
        let vBound = effectiveVisualBound(bound)
        let rgb = fillRGB(pct: pct, bound: vBound, palette: palette, timeframe: timeframe, isLightMode: isLightMode)
        let L = relativeLuminance(rgb)
        
        // SELECTED STATE FIX: Force high contrast for selected tiles
        if selected {
            // For selected tiles, always use white text with strong dark backdrop
            return (Color(red: 0.98, green: 0.98, blue: 1.0), Color.black.opacity(0.70))
        }
        
        // NEUTRAL FIX: For 0% values, use a solid contrasting chip
        // Works across all palettes (Cool gray ~28%, Classic navy ~24%, Warm gold ~62%)
        let isNeutral = abs(pct) < 0.02
        if isNeutral {
            // LIGHT MODE FIX: In light mode, neutral tiles are bright so use dark text
            let lightMode = isLightMode ?? isCurrentlyLightMode()
            if lightMode {
                return (darkTextColor, Color.white.opacity(0.65))
            }
            return (lightTextColor, Color.black.opacity(0.55))
        }
        
        if forceWhite {
            var opacity: Double
            if L >= 0.82 { opacity = 0.42 }
            else if L >= 0.72 { opacity = 0.36 }
            else if L >= 0.60 { opacity = 0.30 }
            else { opacity = 0.24 }
            let intensityRaw = min(1.0, abs(pct / max(0.0001, vBound)))
            let intensity = boostSmall() ? min(1.0, max(intensityRaw, intensityRaw * 0.9 + 0.1 * min(1.0, intensityRaw / 0.35))) : intensityRaw
            opacity = min(0.55, opacity + 0.12 * intensity)
            return (lightTextColor, Color.black.opacity(opacity))
        }
        
        // Auto-pick text color based on tile brightness
        // LIGHT MODE FIX: Use a higher luminance threshold in light mode because tiles
        // are generally brighter. This ensures dark text is used for most light-mode tiles.
        // Dark mode: L < 0.40 → light text (most tiles are dark)
        // Light mode: L < 0.52 → light text (only truly dark tiles get light text)
        let lightMode = isLightMode ?? isCurrentlyLightMode()
        let luminanceThreshold: Double = lightMode ? 0.52 : 0.40
        let useLightText = L < luminanceThreshold
        
        let white:(Double,Double,Double) = (0.953, 0.957, 0.965)  // #F3F4F6
        let black:(Double,Double,Double) = (0.063, 0.067, 0.078)  // #101114
        let cWhite = contrastRatio(white, rgb), cBlack = contrastRatio(black, rgb)
        
        // Use contrast ratio as a secondary check
        let useWhiteFinal = useLightText || cWhite >= cBlack
        let text = useWhiteFinal ? lightTextColor : darkTextColor
        
        // Calculate backdrop opacity for readability - MORE SOLID
        let target: Double = 4.5
        let current = useWhiteFinal ? cWhite : cBlack
        let shortfall = max(0.0, target - current)
        
        // Adaptive backdrop: more opaque for better visibility
        // Only Warm is "flat" (bright gold neutral needs less backdrop).
        // Classic (navy-slate) is darker than Cool, so it needs full backdrop strength.
        let flat = (palette == .warm)
        let base: Double = useWhiteFinal ? (flat ? 0.25 : 0.35) : (flat ? 0.22 : 0.30)
        let extra = min(flat ? 0.20 : 0.25, shortfall * (flat ? 0.04 : 0.06))
        let intensityRaw = min(1.0, abs(pct / max(0.0001, vBound)))
        let intensity = boostSmall() ? min(1.0, max(intensityRaw, intensityRaw * 0.9 + 0.1 * min(1.0, intensityRaw / 0.35))) : intensityRaw
        let alpha = min(flat ? 0.50 : 0.60, base + extra + 0.10 * intensity)
        let backdrop = useWhiteFinal ? Color.black.opacity(alpha) : Color.white.opacity(alpha)
        
        return (text, backdrop)
    }

    public static func labelOutlineOpacity(for pct: Double, bound: Double, palette: HeatMapSharedLib.ColorPalette, timeframe: HeatMapTimeframe? = nil, isLightMode: Bool? = nil) -> Double {
        let vBound = effectiveVisualBound(bound)
        let rgb = fillRGB(pct: pct, bound: vBound, palette: palette, timeframe: timeframe, isLightMode: isLightMode)
        let cW = contrastRatio((1,1,1), rgb), cB = contrastRatio((0,0,0), rgb)
        let best = max(cW, cB)
        if best >= 4.5 { return 0.0 }
        if best <= 2.0 { return 0.22 }
        let t = (best - 2.0) / (4.5 - 2.0)
        return 0.22 - 0.14 * t
    }

    public static func badgeLabelColors(for pct: Double, bound: Double, palette: HeatMapSharedLib.ColorPalette, forceWhite: Bool = false, timeframe: HeatMapTimeframe? = nil, selected: Bool = false, isLightMode: Bool? = nil) -> (text: Color, backdrop: Color) {
        let baseColors = labelColors(for: pct, bound: effectiveVisualBound(bound), palette: palette, forceWhite: forceWhite, timeframe: timeframe, selected: false, isLightMode: isLightMode)
        
        // SELECTED STATE FIX: Boost contrast for better readability when selected
        if selected {
            // For selected tiles, use higher contrast colors
            // Force white text with darker backdrop for guaranteed readability
            let boostedBackdrop = Color.black.opacity(0.75)
            let boostedText = Color(red: 0.98, green: 0.98, blue: 1.0) // Near-white
            return (boostedText, boostedBackdrop)
        }
        
        return baseColors
    }

    // MARK: - Legend
    public struct LegendView: View {
        let bound: Double
        var note: String? = nil
        var palette: HeatMapSharedLib.ColorPalette = .cool  // Keep for compatibility but use AppStorage instead
        var lockState: Bool? = nil
        var onToggleLock: (() -> Void)? = nil
        var onReset: (() -> Void)? = nil
        var timeframe: HeatMapTimeframe? = nil  // Optional timeframe for per-timeframe color matching
        
        // PALETTE FIX: Read palette directly from AppStorage to bypass parameter chain issues
        @AppStorage("heatmap.palette") private var paletteRaw: String = ColorPalette.cool.rawValue
        private var effectivePalette: ColorPalette { ColorPalette(rawValue: paletteRaw) ?? .cool }

        /// Creates a clean gradient that matches our timeframe-aware color interpolation
        /// Uses 9 stops for smooth transition: max red → neutral → max green
        /// Now properly reflects the per-timeframe intensity boosts
        private func scaleGradient(for b: Double) -> LinearGradient {
            // PALETTE FIX: Use effectivePalette from AppStorage instead of parameter
            let stops: [Gradient.Stop] = [
                // Red side (negative) - use timeframe-aware color
                .init(color: HeatMapSharedLib.color(for: -b, bound: b, palette: effectivePalette, timeframe: timeframe ?? .day1), location: 0.0),      // -100% = full red
                .init(color: HeatMapSharedLib.color(for: -b * 0.75, bound: b, palette: effectivePalette, timeframe: timeframe ?? .day1), location: 0.125),
                .init(color: HeatMapSharedLib.color(for: -b * 0.50, bound: b, palette: effectivePalette, timeframe: timeframe ?? .day1), location: 0.25),   // -50%
                .init(color: HeatMapSharedLib.color(for: -b * 0.25, bound: b, palette: effectivePalette, timeframe: timeframe ?? .day1), location: 0.375),
                // Center (neutral)
                .init(color: HeatMapSharedLib.color(for: 0.0, bound: b, palette: effectivePalette, timeframe: timeframe ?? .day1), location: 0.5),     // 0% = neutral
                // Green side (positive) - use timeframe-aware color
                .init(color: HeatMapSharedLib.color(for: b * 0.25, bound: b, palette: effectivePalette, timeframe: timeframe ?? .day1), location: 0.625),
                .init(color: HeatMapSharedLib.color(for: b * 0.50, bound: b, palette: effectivePalette, timeframe: timeframe ?? .day1), location: 0.75),    // +50%
                .init(color: HeatMapSharedLib.color(for: b * 0.75, bound: b, palette: effectivePalette, timeframe: timeframe ?? .day1), location: 0.875),
                .init(color: HeatMapSharedLib.color(for: b, bound: b, palette: effectivePalette, timeframe: timeframe ?? .day1), location: 1.0)        // +100% = full green
            ]
            return LinearGradient(gradient: Gradient(stops: stops), startPoint: .leading, endPoint: .trailing)
        }

        public var body: some View {
            let b = HeatMapSharedLib.effectiveVisualBound(bound)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(String(format: "-%.0f%%", b))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(scaleGradient(for: b))
                        .frame(height: 5)
                        .cornerRadius(2.5)
                        .contentShape(Rectangle())
                        .onTapGesture { if let _ = lockState, let toggle = onToggleLock { HeatMapSharedLib.Haptics.light.impactOccurred(); toggle() } }
                        .onLongPressGesture(minimumDuration: 0.5) { if let reset = onReset { HeatMapSharedLib.Haptics.medium.impactOccurred(); reset() } }
                        // PALETTE FIX: Force gradient re-render when palette changes
                        .id("legend-\(palette.rawValue)-\(b)")
                    Text(String(format: "+%.0f%%", b))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if let locked = lockState, let toggle = onToggleLock {
                        Button(action: toggle) {
                            Image(systemName: locked ? "lock.fill" : "lock.open")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.yellow)
                                .padding(6)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(locked ? "Unlock color scale" : "Lock color scale"))
                    }
                }
                if let note = note, !note.isEmpty {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 0)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Color scale"))
            .accessibilityValue(Text({ let lockStr = (lockState ?? false) ? "Locked" : "Unlocked"; return "\(lockStr) at ±\(Int(b))%" }()))
        }
    }

    // MARK: - Formatting helpers
    public static func valueAbbrev(_ v: Double) -> String {
        return MarketFormat.largeCurrency(v)
    }

    public static func percentString(_ v: Double, decimals: Int = 1) -> String {
        let pow10 = pow(10.0, Double(decimals))
        let rounded = (v * pow10).rounded() / pow10
        let cleaned = (rounded == -0.0) ? 0.0 : rounded
        let withSignFmt = "%+.\(decimals)f%%"
        let noSignFmt = "% .\(decimals)f%%".replacingOccurrences(of: " ", with: "")
        if cleaned == 0 { return String(format: noSignFmt, 0.0) }
        return String(format: withSignFmt, cleaned)
    }

    public static func percentStringAdaptive(_ v: Double) -> String {
        let absV = abs(v)
        let decimals = absV < 1 ? 2 : (absV < 10 ? 1 : 0)
        return percentString(v, decimals: decimals)
    }

    public static func condensedPercentString(_ v: Double, availableWidth: CGFloat) -> String {
        let absV = abs(v)
        if availableWidth >= 54 { return percentStringAdaptive(v) }
        // Show 1 decimal for values < 10 to maintain precision (e.g., +2.4% instead of +2%)
        if availableWidth >= 42 { let d = absV < 10 ? 1 : 0; return percentString(v, decimals: d) }
        // Improved: show 1 decimal for values < 10 even at smaller widths for better consistency
        if availableWidth >= 28 { let d = absV < 10 ? 1 : 0; return percentString(v, decimals: d) }
        // Smallest tiles: 1 decimal for small values, 0 for large
        if absV < 10 { return percentString(v, decimals: 1) }
        return percentString(v, decimals: 0)
    }

    /// Measures text width for tile fit decisions.
    public static func measuredTextWidth(_ text: String, fontSize: CGFloat, weight: UIFont.Weight = .semibold) -> CGFloat {
        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attributes).width
        #else
        return CGFloat(text.count) * fontSize * 0.62
        #endif
    }

    // MARK: - Percent badge metrics + view
    public static func badgeMetrics(width: CGFloat, height: CGFloat) -> (font: CGFloat, minW: CGFloat, maxW: CGFloat, pad: CGFloat, lead: CGFloat, hPad: CGFloat, vPad: CGFloat) {
        let base = min(width, height)
        let font: CGFloat
        let maxW: CGFloat
        // No minWidth - let badge size naturally based on text content
        let minW: CGFloat = 0
        let pad: CGFloat
        let lead: CGFloat
        let hPad: CGFloat
        let vPad: CGFloat
        // Compact chip metrics - badge sizes to fit text, maxW prevents overflow
        if base < 32 {
            font = max(9, min(10, base * 0.28))
            maxW = min(width * 0.70, 60)
            pad = 2; lead = 2; hPad = 4; vPad = 2
        } else if base < 60 {
            font = max(10, min(11, base * 0.22))
            maxW = min(width * 0.65, 75)
            pad = 3; lead = 3; hPad = 5; vPad = 2
        } else {
            font = max(11, min(12, base * 0.18))
            maxW = min(width * 0.60, 85)
            pad = 4; lead = 4; hPad = 6; vPad = 2.5
        }
        return (font, minW, maxW, pad, lead, hPad, vPad)
    }

    // MARK: - Misc
    public static func erasedToAnyView<V: View>(_ view: V) -> AnyView { AnyView(view) }

    // MARK: - SimplePercentChip View (added or assumed present)
    public struct SimplePercentChip: View {
        let text: String
        let fontSize: CGFloat
        let textColor: Color
        let backdrop: Color
        let minWidth: CGFloat
        let maxWidth: CGFloat
        let hPad: CGFloat
        let vPad: CGFloat

        public var body: some View {
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)  // More aggressive scaling for small tiles
                .allowsTightening(true)
                .padding(.horizontal, max(4, hPad))
                .padding(.vertical, max(2, vPad))
                .frame(maxWidth: maxWidth)
                .fixedSize(horizontal: true, vertical: false)
                .background(backdrop, in: Capsule())
                .overlay(Capsule().stroke(DS.Adaptive.overlay(0.18), lineWidth: 0.6))
        }
    }
}

public typealias HeatMapTimeframe = HeatMapSharedLib.HeatMapTimeframe
public typealias ColorPalette = HeatMapSharedLib.ColorPalette
public typealias LabelDensity = HeatMapSharedLib.LabelDensity
public typealias WeightingCurve = HeatMapSharedLib.WeightingCurve
public typealias LegendView = HeatMapSharedLib.LegendView
public typealias Haptics = HeatMapSharedLib.Haptics

