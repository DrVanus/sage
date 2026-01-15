import SwiftUI
import UIKit
import Combine

// MARK: - Lightweight shared haptics
enum Haptics {
    static let light = UIImpactFeedbackGenerator(style: .light)
    static let medium = UIImpactFeedbackGenerator(style: .medium)
    static let notify = UINotificationFeedbackGenerator()
}

// MARK: - Treemap squarify layout
func squarify(
    items: [HeatMapTile],
    weights: [Double],
    rect: CGRect
) -> [CGRect] {
    var rects: [CGRect] = []
    let pairs = Array(zip(items, weights))

    func normalize(_ slice: ArraySlice<(HeatMapTile, Double)>) -> Double {
        slice.reduce(0.0) { $0 + max(0, $1.1) }
    }

    func worst(_ row: ArraySlice<(HeatMapTile, Double)>, total: Double, in r: CGRect, horizontal: Bool) -> CGFloat {
        let rowTotal = max(1e-12, normalize(row))
        let area = r.width * r.height
        let side = horizontal ? r.height : r.width
        let otherSide = (horizontal ? r.width : r.height) * CGFloat(rowTotal / total)
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
        let total = max(1e-12, normalize(list))
        let horizontal = r.width >= r.height

        var row: ArraySlice<(HeatMapTile, Double)> = list.prefix(1)
        var remaining = list.dropFirst()

        while !remaining.isEmpty {
            let candidate = row + remaining.prefix(1)
            if worst(candidate, total: total, in: r, horizontal: horizontal) <= worst(row, total: total, in: r, horizontal: horizontal) {
                row = candidate
                remaining = remaining.dropFirst()
            } else {
                break
            }
        }

        let rowTotal = max(1e-12, normalize(row))
        let rowFrac = rowTotal / total
        let rowRect: CGRect
        let leftover: CGRect
        if horizontal {
            let w = r.width * CGFloat(rowFrac)
            rowRect = CGRect(x: r.minX, y: r.minY, width: w, height: r.height)
            leftover = CGRect(x: r.minX + w, y: r.minY, width: r.width - w, height: r.height)
        } else {
            let h = r.height * CGFloat(rowFrac)
            rowRect = CGRect(x: r.minX, y: r.minY, width: r.width, height: h)
            leftover = CGRect(x: r.minX, y: r.minY + h, width: r.width, height: r.height - h)
        }

        var offset: CGFloat = 0
        for (_, w) in row {
            let frac = max(0, w) / rowTotal
            let slice: CGRect
            if horizontal {
                let h = rowRect.height * CGFloat(frac)
                slice = CGRect(x: rowRect.minX, y: rowRect.minY + offset, width: rowRect.width, height: h)
                offset += h
            } else {
                let w = rowRect.width * CGFloat(frac)
                slice = CGRect(x: rowRect.minX + offset, y: rowRect.minY, width: w, height: rowRect.height)
                offset += w
            }
            rects.append(slice)
        }

        layout(remaining, in: leftover)
    }

    layout(pairs[...], in: rect)
    return rects
}

// MARK: - HeatMap timeframe and helpers
enum HeatMapTimeframe: String, CaseIterable, Identifiable {
    case hour1 = "1h", day1 = "24h", day7 = "7d"
    var id: String { rawValue }
}

@inline(__always) func change(for tile: HeatMapTile, tf: HeatMapTimeframe) -> Double {
    switch tf {
    case .hour1: return tile.pctChange1h ?? tile.pctChange24h
    case .day1:  return tile.pctChange24h
    case .day7:  return tile.pctChange7d ?? tile.pctChange24h
    }
}

@inline(__always) func bound(for tf: HeatMapTimeframe) -> Double {
    switch tf {
    case .hour1: return 5
    case .day1:  return 20
    case .day7:  return 50
    }
}

// MARK: - Weighting curve and label density
enum WeightingCurve: String, CaseIterable, Identifiable {
    case linear = "Linear"
    case balanced = "Balanced"
    case compact = "Compact"
    var id: String { rawValue }
    var exponent: Double {
        switch self {
        case .linear: return 1.0
        case .balanced: return 0.7
        case .compact: return 0.5
        }
    }
}

enum LabelDensity: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case normal = "Normal"
    case detailed = "Detailed"
    var id: String { rawValue }
    var treemapPercentMinSide: CGFloat { switch self { case .compact: return 64; case .normal: return 52; case .detailed: return 40 } }
    var treemapValuesMinSide: CGFloat { switch self { case .compact: return 120; case .normal: return 92; case .detailed: return 70 } }
    var treemapPercentMinWidth: CGFloat { switch self { case .compact: return 62; case .normal: return 50; case .detailed: return 40 } }
    var barPercentMinWidth: CGFloat { switch self { case .compact: return 80; case .normal: return 62; case .detailed: return 48 } }
    var barValuesMinWidth: CGFloat { switch self { case .compact: return 150; case .normal: return 110; case .detailed: return 90 } }
    var gridPercentMinWidth: CGFloat { switch self { case .compact: return 90; case .normal: return 110; case .detailed: return 80 } }
    var gridValuesMinWidth: CGFloat { switch self { case .compact: return 120; case .normal: return 140; case .detailed: return 100 } }
}

// MARK: - Color palette
enum ColorPalette: String, CaseIterable, Identifiable {
    case warm, cool, classic
    var id: String { rawValue }
    var displayName: String {
        switch self { case .warm: return "Warm"; case .cool: return "Cool"; case .classic: return "Classic" }
    }
    static func fromAnyRaw(_ raw: String) -> ColorPalette {
        switch raw.lowercased() {
        case "standard", "warm": return .warm
        case "colorblind", "cool": return .cool
        case "pro", "classic": return .classic
        default: return .warm
        }
    }
}

// MARK: - Color math helpers (sRGB, Oklab, contrast)
@inline(__always) private func clamp01(_ x: Double) -> Double { min(1.0, max(0.0, x)) }
@inline(__always) private func srgbToLinear(_ c: Double) -> Double { c <= 0.04045 ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4) }
@inline(__always) private func linearToSrgb(_ c: Double) -> Double { c <= 0.0031308 ? (12.92 * c) : (1.055 * pow(c, 1.0/2.4) - 0.055) }
@inline(__always) private func relativeLuminance(_ rgb: (Double, Double, Double)) -> Double {
    let r = srgbToLinear(rgb.0), g = srgbToLinear(rgb.1), b = srgbToLinear(rgb.2)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}
@inline(__always) private func contrastRatio(_ fg: (Double, Double, Double), _ bg: (Double, Double, Double)) -> Double {
    let L1 = relativeLuminance(fg), L2 = relativeLuminance(bg)
    let (a, b) = L1 > L2 ? (L1, L2) : (L2, L1)
    return (a + 0.05) / (b + 0.05)
}
@inline(__always) private func smoothstep(_ x: Double) -> Double { let t = max(0, min(1, x)); return t * t * (3 - 2 * t) }

@inline(__always) private func rgbToOklab(_ rgb: (Double, Double, Double)) -> (L: Double, a: Double, b: Double) {
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
@inline(__always) private func oklabToRgb(_ lab: (L: Double, a: Double, b: Double)) -> (Double, Double, Double) {
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
@inline(__always) private func oklabLerp(_ aRGB: (Double, Double, Double), _ bRGB: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
    let a = rgbToOklab(aRGB), b = rgbToOklab(bRGB)
    let L = a.L + (b.L - a.L) * t
    let A = a.a + (b.a - a.a) * t
    let B = a.b + (b.b - a.b) * t
    return oklabToRgb((L, A, B))
}

// Shared emerald to match sentiment gauge
private let GaugeGreen: (Double, Double, Double) = (0.02, 0.66, 0.38)

private func currentSaturation() -> Double {
    let v = UserDefaults.standard.double(forKey: "heatmap.saturation")
    let base = (v == 0) ? 0.95 : v
    return min(1.4, max(0.6, base))
}
private func currentGrayNeutral() -> Bool { UserDefaults.standard.bool(forKey: "heatmap.grayNeutral") }
private func applySaturation(to rgb: (Double, Double, Double), factor: Double) -> (Double, Double, Double) {
    let lum = 0.2126 * rgb.0 + 0.7152 * rgb.1 + 0.0722 * rgb.2
    let gray = (lum, lum, lum)
    let r = clamp01(gray.0 + (rgb.0 - gray.0) * factor)
    let g = clamp01(gray.1 + (rgb.1 - gray.1) * factor)
    let b = clamp01(gray.2 + (rgb.2 - gray.2) * factor)
    return (r, g, b)
}

private struct PaletteSpec { let neg:(Double,Double,Double); let neu:(Double,Double,Double); let pos:(Double,Double,Double); let deadband: Double; let gamma: Double }
private func paletteSpec(for palette: ColorPalette) -> PaletteSpec {
    switch palette {
    case .warm:
        return PaletteSpec(neg: (0.88, 0.22, 0.12), neu: (1.00, 0.74, 0.12), pos: GaugeGreen, deadband: 0.00, gamma: 1.12)
    case .classic:
        return PaletteSpec(neg: (0.90, 0.18, 0.18), neu: (1.00, 0.88, 0.10), pos: GaugeGreen, deadband: 0.00, gamma: 1.05)
    case .cool:
        return PaletteSpec(neg: (0.86, 0.16, 0.16), neu: (0.55, 0.55, 0.55), pos: GaugeGreen, deadband: 0.02, gamma: 1.02)
    }
}

@inline(__always) private func normalizedSignedAmount(_ pct: Double, bound: Double, deadband: Double) -> Double {
    let n0 = max(-1.0, min(1.0, pct / max(0.0001, bound)))
    if abs(n0) < deadband { return 0 }
    let sign = n0 >= 0 ? 1.0 : -1.0
    let m = (abs(n0) - deadband) / (1.0 - deadband)
    return sign * m
}

@inline(__always) private func fillRGB_strictRYG(pct: Double, bound: Double) -> (Double, Double, Double) {
    let n0 = max(-1.0, min(1.0, pct / max(0.0001, bound)))
    let m = abs(n0)
    let red:(Double,Double,Double) = (0.87, 0.13, 0.13)
    let yellow:(Double,Double,Double) = (1.00, 0.93, 0.10)
    let green:(Double,Double,Double) = GaugeGreen
    func lerp(_ a:(Double,Double,Double), _ b:(Double,Double,Double), _ t: Double) -> (Double,Double,Double) {
        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }
    let t = pow(m, 0.68)
    let base: (Double,Double,Double) = (n0 < 0) ? lerp(yellow, red, t) : (n0 > 0 ? lerp(yellow, green, t) : yellow)
    let satBase = min(1.10, max(0.85, currentSaturation()))
    let intensity = pow(m, 0.85)
    let sat = satBase * (0.80 + 0.20 * intensity)
    return applySaturation(to: base, factor: sat)
}

@inline(__always) private func fillRGB(pct: Double, bound: Double, palette: ColorPalette) -> (Double, Double, Double) {
    if palette == .classic { return fillRGB_strictRYG(pct: pct, bound: bound) }
    var spec = paletteSpec(for: palette)
    if palette == .warm && currentGrayNeutral() {
        spec = PaletteSpec(neg: spec.neg, neu: (0.46,0.46,0.46), pos: spec.pos, deadband: max(spec.deadband, 0.03), gamma: spec.gamma * 1.02)
    }
    let n = normalizedSignedAmount(pct, bound: bound, deadband: spec.deadband)
    let mag = abs(n)
    let gammaPos: Double
    let gammaNeg: Double
    if palette == .warm && !currentGrayNeutral() { gammaPos = 1.10; gammaNeg = 1.24 } else { gammaPos = spec.gamma; gammaNeg = spec.gamma }
    let easedMag = pow(smoothstep(mag), (n >= 0 ? gammaPos : gammaNeg))
    let signed = (n >= 0 ? easedMag : -easedMag)
    let t = (signed + 1.0) * 0.5
    let baseRGB: (Double, Double, Double) = (t < 0.5) ? oklabLerp(spec.neg, spec.neu, t / 0.5) : oklabLerp(spec.neu, spec.pos, (t - 0.5) / 0.5)
    let intensity = min(1.0, abs(pct) / max(0.0001, bound))
    let satBase = currentSaturation()
    let sat = min(1.15, max(0.80, satBase * (0.85 + 0.15 * pow(intensity, 0.9))))
    return applySaturation(to: baseRGB, factor: sat)
}

func color(for pct: Double, bound: Double) -> Color { color(for: pct, bound: bound, palette: .warm) }
func color(for pct: Double, bound: Double, palette: ColorPalette) -> Color {
    let rgb = fillRGB(pct: pct, bound: bound, palette: palette)
    return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
}

// MARK: - Label contrast helpers
func labelColors(for pct: Double, bound: Double, palette: ColorPalette, forceWhite: Bool = false) -> (text: Color, backdrop: Color) {
    let rgb = fillRGB(pct: pct, bound: bound, palette: palette)
    if forceWhite {
        let L = relativeLuminance(rgb)
        var opacity: Double
        if L >= 0.82 { opacity = 0.42 }
        else if L >= 0.72 { opacity = 0.36 }
        else if L >= 0.60 { opacity = 0.30 }
        else { opacity = 0.24 }
        let intensity = min(1.0, abs(pct / max(0.0001, bound)))
        opacity = min(0.55, opacity + 0.12 * intensity)
        return (.white, Color.black.opacity(opacity))
    }
    let white:(Double,Double,Double) = (1,1,1), black:(Double,Double,Double) = (0,0,0)
    let cWhite = contrastRatio(white, rgb), cBlack = contrastRatio(black, rgb)
    let useWhite = cWhite >= cBlack
    let text = useWhite ? Color.white : Color.black
    let flat = (palette == .warm || palette == .classic)
    let target: Double = 4.5
    let current = max(cWhite, cBlack)
    let shortfall = max(0.0, target - current)
    let base: Double = useWhite ? (flat ? 0.10 : 0.20) : (flat ? 0.12 : 0.22)
    let extra = min(flat ? 0.20 : 0.28, shortfall * (flat ? 0.04 : 0.06))
    let intensity = min(1.0, abs(pct / max(0.0001, bound)))
    let alpha = min(flat ? 0.30 : 0.50, base + extra + 0.10 * intensity)
    let backdrop = (useWhite ? Color.black.opacity(alpha) : Color.white.opacity(alpha))
    return (text, backdrop)
}

func labelOutlineOpacity(for pct: Double, bound: Double, palette: ColorPalette) -> Double {
    let rgb = fillRGB(pct: pct, bound: bound, palette: palette)
    let cW = contrastRatio((1,1,1), rgb), cB = contrastRatio((0,0,0), rgb)
    let best = max(cW, cB)
    if best >= 4.5 { return 0.0 }
    if best <= 2.0 { return 0.22 }
    let t = (best - 2.0) / (4.5 - 2.0)
    return 0.22 - 0.14 * t
}

func badgeLabelColors(for pct: Double, bound: Double, palette: ColorPalette, forceWhite: Bool = false) -> (text: Color, backdrop: Color) {
    return labelColors(for: pct, bound: bound, palette: palette, forceWhite: forceWhite)
}

// MARK: - Legend
struct LegendView: View {
    let bound: Double
    var note: String? = nil
    var palette: ColorPalette = .warm
    var lockState: Bool? = nil
    var onToggleLock: (() -> Void)? = nil
    var onReset: (() -> Void)? = nil

    var gradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: color(for: -bound, bound: bound, palette: palette), location: 0.0),
                .init(color: color(for: 0.0, bound: bound, palette: palette), location: 0.5),
                .init(color: color(for: bound, bound: bound, palette: palette), location: 1.0)
            ]),
            startPoint: .leading, endPoint: .trailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(String(format: "-%.0f%%", bound))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(gradient)
                    .frame(height: 2)
                    .cornerRadius(3)
                    .contentShape(Rectangle())
                    .onTapGesture { if let _ = lockState, let toggle = onToggleLock { Haptics.light.impactOccurred(); toggle() } }
                    .onLongPressGesture(minimumDuration: 0.5) { if let reset = onReset { Haptics.medium.impactOccurred(); reset() } }
                Text(String(format: "+%.0f%%", bound))
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
        .accessibilityValue(Text({ let lockStr = (lockState ?? false) ? "Locked" : "Unlocked"; return "\(lockStr) at ±\(Int(bound))%" }()))
    }
}

// MARK: - Formatting helpers
func valueAbbrev(_ v: Double) -> String {
    switch abs(v) {
    case 1_000_000_000_000...: return String(format: "$%.1fT", v/1_000_000_000_000)
    case 1_000_000_000...:     return String(format: "$%.1fB", v/1_000_000_000)
    case 1_000_000...:         return String(format: "$%.1fM", v/1_000_000)
    case 1_000...:             return String(format: "$%.1fk", v/1_000)
    default:                   return String(format: "$%.0f", v)
    }
}

func percentString(_ v: Double, decimals: Int = 1) -> String {
    let pow10 = pow(10.0, Double(decimals))
    let rounded = (v * pow10).rounded() / pow10
    let cleaned = (rounded == -0.0) ? 0.0 : rounded
    let withSignFmt = "%+.\(decimals)f%%"
    let noSignFmt = "% .\(decimals)f%%".replacingOccurrences(of: " ", with: "")
    if cleaned == 0 { return String(format: noSignFmt, 0.0) }
    return String(format: withSignFmt, cleaned)
}

func percentStringAdaptive(_ v: Double) -> String {
    let absV = abs(v)
    let decimals = absV < 1 ? 2 : (absV < 10 ? 1 : 0)
    return percentString(v, decimals: decimals)
}

func condensedPercentString(_ v: Double, availableWidth: CGFloat) -> String {
    let absV = abs(v)
    if availableWidth >= 54 { return percentStringAdaptive(v) }
    if availableWidth >= 42 { let d = absV < 10 ? 1 : 0; return percentString(v, decimals: d) }
    if availableWidth >= 28 { if absV < 1 { return percentString(v, decimals: 1) }; return percentString(v, decimals: 0) }
    if absV < 1 { return percentString(v, decimals: 1) }
    return percentString(v, decimals: 0)
}

// MARK: - Percent badge metrics + view
func badgeMetrics(width: CGFloat, height: CGFloat) -> (font: CGFloat, minW: CGFloat, maxW: CGFloat, pad: CGFloat, lead: CGFloat, hPad: CGFloat, vPad: CGFloat) {
    let base = min(width, height)
    let font: CGFloat
    let maxW: CGFloat
    let minW: CGFloat = max(12, min(28, width - 10))
    let pad: CGFloat
    let lead: CGFloat
    let hPad: CGFloat
    let vPad: CGFloat
    if base < 32 { font = max(9, min(11, base * 0.24)); maxW = min(width * 0.42, 72); pad = 2; lead = 2; hPad = 4; vPad = 2 }
    else if base < 60 { font = max(9, min(12, base * 0.22)); maxW = min(width * 0.48, 90); pad = 4; lead = max(2, min(5, base * 0.07)); hPad = 6; vPad = 3 }
    else { font = max(10, min(12, base * 0.20)); maxW = min(width * 0.5, 100); pad = 6; lead = max(3, min(6, base * 0.06)); hPad = 6; vPad = 3 }
    return (font, minW, maxW, pad, lead, hPad, vPad)
}

struct SimplePercentChip: View {
    let text: String
    let fontSize: CGFloat
    let textColor: Color
    let backdrop: Color
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let hPad: CGFloat
    let vPad: CGFloat
    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(textColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(backdrop, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Buttons & brand fallbacks
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var opacity: Double = 0.9
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? opacity : 1)
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// Brand fallbacks (non-conflicting simple definitions)
struct BrandColors {
    static let goldVertical = LinearGradient(colors: [Color.yellow.opacity(0.95), Color.orange.opacity(0.95)], startPoint: .top, endPoint: .bottom)
    static let goldStrokeHighlight = Color.white.opacity(0.45)
    static let goldStrokeShadow = Color.black.opacity(0.25)
}
struct DS { struct Colors { static let gold = Color.yellow } }
let chipGoldGradient = LinearGradient(colors: [Color.yellow.opacity(0.95), Color.orange.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
let ctaRimStrokeGradient = LinearGradient(colors: [Color.white.opacity(0.35), Color.black.opacity(0.2)], startPoint: .top, endPoint: .bottom)
let ctaBottomShade = LinearGradient(colors: [Color.black.opacity(0.18), .clear], startPoint: .bottom, endPoint: .center)

struct GoldCapsuleButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    var horizontalPadding: CGFloat = 18
    var pressedScale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Color.black.opacity(0.92))
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(
                Capsule()
                    .fill(BrandColors.goldVertical)
                    .overlay(LinearGradient(colors: [Color.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center).clipShape(Capsule()))
                    .overlay(Capsule().stroke(BrandColors.goldStrokeHighlight, lineWidth: 0.8))
                    .overlay(Capsule().stroke(BrandColors.goldStrokeShadow, lineWidth: 0.6))
            )
            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Misc
extension View { func erasedToAnyView() -> AnyView { AnyView(self) } }
