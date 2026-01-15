// Shared helpers for Market Heat Map views

import SwiftUI

public struct HeatMapSharedLib {
    // MARK: - Public Enums
    
    /// Timeframe options for heatmap data aggregation
    public enum HeatMapTimeframe: String, CaseIterable, Identifiable {
        case hour1 = "1h"
        case day1 = "24h"
        case day7 = "7d"
        public var id: String { rawValue }
    }
    
    /// Weighting curves for data representation
    public enum WeightingCurve: String, CaseIterable, Identifiable {
        case linear = "Linear"
        case balanced = "Balanced"
        case compact = "Compact"
        public var id: String { rawValue }
        public var exponent: Double {
            switch self {
            case .linear: return 1.0
            case .balanced: return 0.7
            case .compact: return 0.5
            }
        }
    }
    
    /// Label density options affecting layout sizes
    public enum LabelDensity: String, CaseIterable, Identifiable {
        case compact = "Compact"
        case normal = "Normal"
        case detailed = "Detailed"
        public var id: String { rawValue }
        
        public var treemapPercentMinSide: CGFloat {
            switch self {
            case .compact: return 64
            case .normal: return 52
            case .detailed: return 40
            }
        }
        public var treemapValuesMinSide: CGFloat {
            switch self {
            case .compact: return 120
            case .normal: return 92
            case .detailed: return 70
            }
        }
        public var treemapPercentMinWidth: CGFloat {
            switch self {
            case .compact: return 62
            case .normal: return 50
            case .detailed: return 40
            }
        }
        public var barPercentMinWidth: CGFloat {
            switch self {
            case .compact: return 80
            case .normal: return 62
            case .detailed: return 48
            }
        }
        public var barValuesMinWidth: CGFloat {
            switch self {
            case .compact: return 150
            case .normal: return 110
            case .detailed: return 90
            }
        }
        public var gridPercentMinWidth: CGFloat {
            switch self {
            case .compact: return 90
            case .normal: return 110
            case .detailed: return 80
            }
        }
        public var gridValuesMinWidth: CGFloat {
            switch self {
            case .compact: return 120
            case .normal: return 140
            case .detailed: return 100
            }
        }
    }
    
    /// Color palettes available for heat maps
    public enum ColorPalette: String, CaseIterable, Identifiable {
        case warm
        case cool
        case classic
        public var id: String { rawValue }
        
        public var displayName: String {
            switch self {
            case .warm: return "Warm"
            case .cool: return "Cool"
            case .classic: return "Classic"
            }
        }
        
        public static func fromAnyRaw(_ raw: String) -> ColorPalette {
            switch raw.lowercased() {
            case "standard", "warm": return .warm
            case "colorblind", "cool": return .cool
            case "pro", "classic": return .classic
            default: return .warm
            }
        }
    }
    
    // MARK: - Public Static Methods
    
    /// Returns the timeframe change multiplier for the given timeframe
    /// Uses 24h as fallback for 1h and 7d if nil.
    public static func change(for value: Double?, tf: HeatMapTimeframe) -> Double {
        guard let value = value else {
            switch tf {
            case .hour1:
                return 24
            case .day1:
                return 1
            case .day7:
                return 24 * 7
            }
        }
        return value
    }
    
    /// Returns the bound value for a given timeframe
    public static func bound(for tf: HeatMapTimeframe) -> Double {
        switch tf {
        case .hour1: return 5
        case .day1: return 20
        case .day7: return 50
        }
    }
    
    /// Returns a Color for the given bound and palette
    public static func color(for bound: Double, palette: ColorPalette) -> Color {
        let rgb = fillRGB(pct: bound, bound: bound, palette: palette)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
    
    /// Returns label text and backdrop colors with WCAG contrast logic
    /// forceWhite overrides text color to white for better contrast
    public static func labelColors(for bound: Double, palette: ColorPalette, forceWhite: Bool) -> (text: Color, backdrop: Color) {
        let baseColor = color(for: bound, palette: palette)
        let textColor: Color
        let backdropColor: Color
        
        let baseRGB = fillRGB(pct: bound, bound: bound, palette: palette)
        let baseLuminance = relativeLuminance(r: baseRGB.r, g: baseRGB.g, b: baseRGB.b)
        
        // forceWhite overrides text color for better contrast
        if forceWhite {
            textColor = Color.white
            backdropColor = baseColor.opacity(0.3)
        } else {
            // If base luminance is low, use white text, otherwise black
            if baseLuminance < 0.5 {
                textColor = Color.white
                backdropColor = baseColor.opacity(0.3)
            } else {
                textColor = Color.black
                backdropColor = baseColor.opacity(0.1)
            }
        }
        
        return (textColor, backdropColor)
    }
    
    /// Returns outline opacity for label based on bound and palette
    public static func labelOutlineOpacity(for bound: Double, palette: ColorPalette) -> Double {
        let rgb = fillRGB(pct: bound, bound: bound, palette: palette)
        let lum = relativeLuminance(r: rgb.r, g: rgb.g, b: rgb.b)
        // subtle outline if contrast is low
        return lum > 0.6 ? 0.15 : 0.3
    }
    
    /// Returns badge label colors same as labelColors
    public static func badgeLabelColors(for bound: Double, palette: ColorPalette, forceWhite: Bool) -> (text: Color, backdrop: Color) {
        return labelColors(for: bound, palette: palette, forceWhite: forceWhite)
    }
    
    /// Formats a number into abbreviated string with $k, $M, $B, $T
    public static func valueAbbrev(_ value: Double) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 1_000_000_000_000...:
            return "\(sign)$\(formatNumber(absValue / 1_000_000_000_000))T"
        case 1_000_000_000...:
            return "\(sign)$\(formatNumber(absValue / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)$\(formatNumber(absValue / 1_000_000))M"
        case 1_000...:
            return "\(sign)$\(formatNumber(absValue / 1_000))k"
        default:
            return "\(sign)$\(formatNumber(absValue))"
        }
    }
    
    /// Formats a percent value with specified decimals and percent sign (e.g. "12.3%")
    public static func percentString(_ value: Double, decimals: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? "\(value * 100)%"
    }
    
    /// Formats a percent value with adaptive decimals based on magnitude
    public static func percentStringAdaptive(_ value: Double) -> String {
        let absVal = abs(value)
        let decimals: Int
        if absVal >= 0.1 {
            decimals = 1
        } else if absVal >= 0.01 {
            decimals = 2
        } else if absVal >= 0.001 {
            decimals = 3
        } else {
            decimals = 4
        }
        return percentString(value, decimals: decimals)
    }
    
    /// Returns a condensed percent string based on available width
    /// Uses width tiers >=54 adaptive, >=42 1d/0d, >=28 1d/0d with <1 special-case, else 1d/0d
    public static func condensedPercentString(_ value: Double, availableWidth: CGFloat) -> String {
        if availableWidth >= 54 {
            return percentStringAdaptive(value)
        } else if availableWidth >= 42 {
            return percentString(value, decimals: 1)
        } else if availableWidth >= 28 {
            // special case for <1%
            if abs(value) < 0.01 {
                return "<1%"
            }
            return percentString(value, decimals: 1)
        } else {
            return percentString(value, decimals: 0)
        }
    }
    
    /// Returns badge metrics tuple (font, minW, maxW, pad, lead, hPad, vPad) based on width and height
    public static func badgeMetrics(width: CGFloat, height: CGFloat) -> (font: CGFloat, minW: CGFloat, maxW: CGFloat, pad: CGFloat, lead: CGFloat, hPad: CGFloat, vPad: CGFloat) {
        // Thresholds and values copied as per app logic from provided content
        let font: CGFloat
        let minW: CGFloat
        let maxW: CGFloat
        let pad: CGFloat
        let lead: CGFloat
        let hPad: CGFloat
        let vPad: CGFloat
        
        if width >= 100 {
            font = 16
            minW = 80
            maxW = 150
            pad = 12
            lead = 10
            hPad = 16
            vPad = 6
        } else if width >= 60 {
            font = 12
            minW = 48
            maxW = 110
            pad = 10
            lead = 8
            hPad = 12
            vPad = 4
        } else {
            font = 10
            minW = 36
            maxW = 90
            pad = 8
            lead = 6
            hPad = 8
            vPad = 2
        }
        
        return (font, minW, maxW, pad, lead, hPad, vPad)
    }
    
    /// Squarified treemap layout algorithm
    /// Takes items, their weights, and a rect to fill, returns array of CGRects for layout
    public static func squarify(items: [Any], weights: [Double], rect: CGRect) -> [CGRect] {
        guard items.count == weights.count, items.count > 0 else { return [] }
        
        var rects: [CGRect] = []
        var remainingRect = rect
        var remainingWeights = weights
        var remainingItems = items
        
        func worstAspectRatio(_ row: [Double], _ w: Double) -> Double {
            guard !row.isEmpty else { return Double.infinity }
            let s = row.reduce(0, +)
            let maxVal = row.max() ?? 0
            let minVal = row.min() ?? 0
            let sSquared = s * s
            let wSquared = w * w
            return max((wSquared * maxVal) / sSquared,
                       sSquared / (wSquared * minVal))
        }
        
        func layoutRow(_ rowItems: [Any], _ rowWeights: [Double], _ rect: CGRect, _ horizontal: Bool) -> [CGRect] {
            var rects: [CGRect] = []
            let totalWeight = rowWeights.reduce(0, +)
            var offset: CGFloat = 0
            for w in rowWeights {
                let ratio = CGFloat(w / totalWeight)
                if horizontal {
                    let width = rect.width * ratio
                    let r = CGRect(x: rect.minX + offset, y: rect.minY, width: width, height: rect.height)
                    rects.append(r)
                    offset += width
                } else {
                    let height = rect.height * ratio
                    let r = CGRect(x: rect.minX, y: rect.minY + offset, width: rect.width, height: height)
                    rects.append(r)
                    offset += height
                }
            }
            return rects
        }
        
        func squarifyRecursive(_ items: [Any], _ weights: [Double], _ rect: CGRect) {
            if items.isEmpty { return }
            if items.count == 1 {
                rects.append(rect)
                return
            }
            var row: [Double] = []
            var rowItems: [Any] = []
            var remainingItems = items
            var remainingWeights = weights
            
            var horizontalSplit = rect.width >= rect.height
            
            func layoutCurrentRow() {
                let rowRects = layoutRow(rowItems, row, rect, horizontalSplit)
                rects.append(contentsOf: rowRects)
            }
            
            var w = horizontalSplit ? Double(rect.height) : Double(rect.width)
            var i = 0
            
            while i < remainingWeights.count {
                let nextWeight = remainingWeights[i]
                let newRow = row + [nextWeight]
                let newWorst = worstAspectRatio(newRow, w)
                let oldWorst = worstAspectRatio(row, w)
                if i == 0 || newWorst <= oldWorst {
                    row.append(nextWeight)
                    rowItems.append(remainingItems[i])
                    i += 1
                } else {
                    break
                }
            }
            
            if row.isEmpty {
                row.append(remainingWeights[0])
                rowItems.append(remainingItems[0])
                i = 1
            }
            
            // Layout the row
            let totalRowWeight = row.reduce(0, +)
            let totalWeight = weights.reduce(0, +)
            let ratio = CGFloat(totalRowWeight / totalWeight)
            
            if horizontalSplit {
                let rowRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * ratio)
                let subRects = layoutRow(rowItems, row, rowRect, true)
                rects.append(contentsOf: subRects)
                let newRect = CGRect(x: rect.minX, y: rect.minY + rowRect.height, width: rect.width, height: rect.height - rowRect.height)
                squarifyRecursive(Array(remainingItems[i...]), Array(remainingWeights[i...]), newRect)
            } else {
                let rowRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width * ratio, height: rect.height)
                let subRects = layoutRow(rowItems, row, rowRect, false)
                rects.append(contentsOf: subRects)
                let newRect = CGRect(x: rect.minX + rowRect.width, y: rect.minY, width: rect.width - rowRect.width, height: rect.height)
                squarifyRecursive(Array(remainingItems[i...]), Array(remainingWeights[i...]), newRect)
            }
        }
        
        squarifyRecursive(remainingItems, remainingWeights, remainingRect)
        return rects
    }
    
    // MARK: - Private/ Fileprivate Helpers
    
    fileprivate static func clamp01(_ val: Double) -> Double {
        return min(max(val, 0), 1)
    }
    
    fileprivate static func srgbToLinear(_ c: Double) -> Double {
        if c <= 0.04045 {
            return c / 12.92
        } else {
            return pow((c + 0.055) / 1.055, 2.4)
        }
    }
    
    fileprivate static func linearToSrgb(_ c: Double) -> Double {
        if c <= 0.0031308 {
            return 12.92 * c
        } else {
            return 1.055 * pow(c, 1.0 / 2.4) - 0.055
        }
    }
    
    fileprivate static func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        // Use linearized sRGB values
        let R = srgbToLinear(r)
        let G = srgbToLinear(g)
        let B = srgbToLinear(b)
        // Rec 709 luminance coefficients
        return 0.2126 * R + 0.7152 * G + 0.0722 * B
    }
    
    fileprivate static func contrastRatio(l1: Double, l2: Double) -> Double {
        // l1 should be lighter luminance, l2 darker luminance
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
    
    fileprivate static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = clamp01((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }
    
    // MARK: - Oklab conversions
    
    fileprivate static func rgbToOklab(r: Double, g: Double, b: Double) -> (L: Double, a: Double, b: Double) {
        // Convert sRGB [0..1] to linear RGB
        let R = srgbToLinear(r)
        let G = srgbToLinear(g)
        let B = srgbToLinear(b)
        
        // Linear RGB to LMS
        let l = 0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B
        let m = 0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B
        let s = 0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B
        
        // Non-linear transform
        let l_ = pow(l, 1.0/3.0)
        let m_ = pow(m, 1.0/3.0)
        let s_ = pow(s, 1.0/3.0)
        
        // Oklab
        let L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        let a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        let b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        
        return (L, a, b)
    }
    
    fileprivate static func oklabToRgb(L: Double, a: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        // Convert back to LMS cube roots
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        
        let l = l_ * l_ * l_
        let m = m_ * m_ * m_
        let s = s_ * s_ * s_
        
        let R = +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let G = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let B = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        
        // Convert linear RGB to sRGB
        let r = linearToSrgb(R)
        let g = linearToSrgb(G)
        let b = linearToSrgb(B)
        
        return (r, g, b)
    }
    
    fileprivate static func oklabLerp(a: (L: Double, a: Double, b: Double), b: (L: Double, a: Double, b: Double), t: Double) -> (L: Double, a: Double, b: Double) {
        let L = a.L + (b.L - a.L) * t
        let aa = a.a + (b.a - a.a) * t
        let bb = a.b + (b.b - a.b) * t
        return (L, aa, bb)
    }
    
    // GaugeGreen constant
    fileprivate static let GaugeGreen: (r: Double, g: Double, b: Double) = (0.02, 0.66, 0.38)
    
    /// Reads current saturation factor from UserDefaults with clamped range 0.6...1.4
    fileprivate static func currentSaturation() -> Double {
        let val = UserDefaults.standard.double(forKey: "heatmap.saturation")
        if val == 0 { return 0.95 } // default if not set
        return min(max(val, 0.6), 1.4)
    }
    
    /// Reads current gray neutral flag from UserDefaults
    fileprivate static func currentGrayNeutral() -> Bool {
        return UserDefaults.standard.bool(forKey: "heatmap.grayNeutral")
    }
    
    /// Applies saturation factor to given rgb triplet
    fileprivate static func applySaturation(to rgb: (r: Double, g: Double, b: Double), factor: Double) -> (r: Double, g: Double, b: Double) {
        // Convert to Oklab
        let lab = rgbToOklab(r: rgb.r, g: rgb.g, b: rgb.b)
        // Interpolate a, b by factor (1.0 = original)
        let newLab = (L: lab.L, a: lab.a * factor, b: lab.b * factor)
        // Convert back to RGB
        let newRGB = oklabToRgb(L: newLab.L, a: newLab.a, b: newLab.b)
        return (clamp01(newRGB.r), clamp01(newRGB.g), clamp01(newRGB.b))
    }
    
    // MARK: - Palette Spec
    
    fileprivate struct PaletteSpec {
        let green: (r: Double, g: Double, b: Double)
        let yellow: (r: Double, g: Double, b: Double)
        let red: (r: Double, g: Double, b: Double)
        let grayNeutral: Bool
    }
    
    fileprivate static func paletteSpec(for palette: ColorPalette) -> PaletteSpec {
        switch palette {
        case .warm:
            return PaletteSpec(
                green: (0.11, 0.61, 0.34),
                yellow: (0.95, 0.75, 0.05),
                red: (0.84, 0.25, 0.14),
                grayNeutral: currentGrayNeutral()
            )
        case .cool:
            return PaletteSpec(
                green: (0.19, 0.58, 0.45),
                yellow: (0.94, 0.73, 0.11),
                red: (0.79, 0.28, 0.39),
                grayNeutral: currentGrayNeutral()
            )
        case .classic:
            return PaletteSpec(
                green: (0.02, 0.66, 0.38),
                yellow: (0.98, 0.75, 0.20),
                red: (0.84, 0.25, 0.14),
                grayNeutral: false
            )
        }
    }
    
    // MARK: - Color Fill Logic
    
    fileprivate static func normalizedSignedAmount(_ pct: Double, bound: Double) -> Double {
        // Clamp between -1 and 1 and scale by bound
        let norm = pct / bound
        return max(min(norm, 1), -1)
    }
    
    fileprivate static func fillRGB_strictRYG(_ val: Double, spec: PaletteSpec) -> (r: Double, g: Double, b: Double) {
        let amount = val
        if amount < 0 {
            // Interpolate between green and yellow
            let t = 1 + amount // amount negative, so t in [0,1]
            let r = spec.green.r * t + spec.yellow.r * (1 - t)
            let g = spec.green.g * t + spec.yellow.g * (1 - t)
            let b = spec.green.b * t + spec.yellow.b * (1 - t)
            return (r, g, b)
        } else {
            // Interpolate between yellow and red
            let t = amount
            let r = spec.yellow.r * (1 - t) + spec.red.r * t
            let g = spec.yellow.g * (1 - t) + spec.red.g * t
            let b = spec.yellow.b * (1 - t) + spec.red.b * t
            return (r, g, b)
        }
    }
    
    fileprivate static func fillRGB_classicNoLime(_ val: Double, spec: PaletteSpec) -> (r: Double, g: Double, b: Double) {
        // Classic palette without lime green
        let amount = val
        if amount < 0 {
            // Interpolate green to gray neutral or black
            let t = 1 + amount
            if spec.grayNeutral {
                // Interpolate green to gray neutral 0.5 gray
                let gray = 0.5
                let r = spec.green.r * t + gray * (1 - t)
                let g = spec.green.g * t + gray * (1 - t)
                let b = spec.green.b * t + gray * (1 - t)
                return (r, g, b)
            } else {
                // Interpolate green to black
                let r = spec.green.r * t
                let g = spec.green.g * t
                let b = spec.green.b * t
                return (r, g, b)
            }
        } else {
            // Interpolate yellow to red
            let t = amount
            let r = spec.yellow.r * (1 - t) + spec.red.r * t
            let g = spec.yellow.g * (1 - t) + spec.red.g * t
            let b = spec.yellow.b * (1 - t) + spec.red.b * t
            return (r, g, b)
        }
    }
    
    fileprivate static func fillRGB(pct: Double, bound: Double, palette: ColorPalette) -> (r: Double, g: Double, b: Double) {
        let spec = paletteSpec(for: palette)
        let normalized = normalizedSignedAmount(pct, bound: bound)
        
        var rgb: (r: Double, g: Double, b: Double)
        switch palette {
        case .warm:
            rgb = fillRGB_strictRYG(normalized, spec: spec)
        case .cool:
            rgb = fillRGB_strictRYG(normalized, spec: spec)
        case .classic:
            rgb = fillRGB_classicNoLime(normalized, spec: spec)
        }
        
        // Apply gamma shaping for smooth color transitions
        rgb = (
            r: pow(rgb.r, 1.0 / 2.2),
            g: pow(rgb.g, 1.0 / 2.2),
            b: pow(rgb.b, 1.0 / 2.2)
        )
        
        // Apply saturation factor
        let saturationFactor = currentSaturation()
        rgb = applySaturation(to: rgb, factor: saturationFactor)
        
        return (
            r: clamp01(rgb.r),
            g: clamp01(rgb.g),
            b: clamp01(rgb.b)
        )
    }
    
    // MARK: - Helpers
    
    private static func formatNumber(_ num: Double) -> String {
        if num >= 100 {
            return String(format: "%.0f", num)
        } else if num >= 10 {
            return String(format: "%.1f", num)
        } else {
            return String(format: "%.2f", num)
        }
    }
}
