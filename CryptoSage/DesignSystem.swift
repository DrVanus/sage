import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - GPU Memory Safety
// MEMORY FIX: Global kill switch for expensive GPU effects (shadow, blur, blendMode).
// Each .shadow() and .blur() creates a GPU offscreen render buffer (~0.5-3 MB each on 3x devices).
// With 200+ shadow/blur calls across the app, this consumed 100-200+ MB of GPU memory,
// pushing total memory past iOS jetsam limits and causing immediate app termination.
// Set to `true` to disable all GPU-heavy effects. Set to `false` to re-enable for testing.
let kDisableExpensiveGPUEffects = true

extension View {
    /// Safe shadow that respects the global GPU memory kill switch.
    /// When kDisableExpensiveGPUEffects is true, shadows are completely removed to save GPU memory.
    @ViewBuilder
    func safeShadow(color: Color = .black.opacity(0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        if kDisableExpensiveGPUEffects {
            self
        } else {
            self.shadow(color: color, radius: radius, x: x, y: y)
        }
    }
    
    /// Safe blur that respects the global GPU memory kill switch.
    @ViewBuilder
    func safeBlur(radius: CGFloat, opaque: Bool = false) -> some View {
        if kDisableExpensiveGPUEffects {
            self
        } else {
            self.blur(radius: radius, opaque: opaque)
        }
    }
}

// MARK: - Adaptive Color Helper
extension Color {
    /// Creates a color that adapts to light/dark mode
    static func adaptive(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #else
        return dark // Fallback to dark on non-UIKit platforms
        #endif
    }
}

// MARK: - Design System Tokens
enum DS {
    enum Fonts {
        // Primary price display (top ticker)
        static let priceXL: Font = .system(size: 28, weight: .bold, design: .rounded)
        // Badge/crosshair price labels
        static let priceBadge: Font = .system(size: 12, weight: .semibold, design: .rounded)
        static let crosshairPrice: Font = .system(size: 14, weight: .semibold, design: .rounded)
        static let crosshairDate: Font = .system(size: 11, weight: .regular, design: .rounded)
        // Axis labels and chips
        static let axis: Font = .caption2
        static let chip: Font = .caption2
        // Order book - compact professional typography
        static let orderBookHeader: Font = .system(size: 10, weight: .medium, design: .rounded)
        static let orderBookColumnHeader: Font = .system(size: 9, weight: .semibold, design: .rounded)
        static let orderBookPrice: Font = .system(size: 12, weight: .medium, design: .rounded)
        static let orderBookPriceBest: Font = .system(size: 12, weight: .semibold, design: .rounded)
        static let orderBookQty: Font = .system(size: 12, weight: .regular, design: .rounded)
        static let orderBookNumber: Font = .system(size: 11, weight: .regular, design: .default)
        static let orderBookControl: Font = .system(size: 10, weight: .medium, design: .rounded)
        static let orderBookImbalance: Font = .system(size: 10, weight: .semibold, design: .rounded)
    }

    enum Spacing {
        // Order book - tight compact spacing
        static let orderBookRowHeight: CGFloat = 20  // Compact rows
        static let orderBookRowSpacing: CGFloat = 0  // No spacing for maximum density
        static let orderBookColumnGap: CGFloat = 4   // Minimal gap between bid/ask columns
        static let orderBookHeaderHeight: CGFloat = 16 // Minimal column header row
        
        // Order book controls
        static let orderBookControlPaddingH: CGFloat = 6
        static let orderBookControlPaddingV: CGFloat = 4
        static let orderBookControlSpacing: CGFloat = 1
        
        // Imbalance bar
        static let orderBookImbalanceHeight: CGFloat = 4
        
        static let chipHorizontal: CGFloat = 14
        static let chipVertical: CGFloat = 6
    }
    
    enum OrderBook {
        // Depth bar opacity - subtle, professional
        static let depthOpacityDark: Double = 0.22
        static let depthOpacityLight: Double = 0.16
        static let depthOpacityBestDark: Double = 0.32
        static let depthOpacityBestLight: Double = 0.24
        
        // Best price row background - very subtle
        static let bestRowBgDark: Double = 0.05
        static let bestRowBgLight: Double = 0.04
        
        // Best price row glow
        static let bestPriceGlowRadius: CGFloat = 2
        static let bestPriceGlowOpacity: Double = 0.20
        
        // Depth bar corner radius
        static let depthBarRadius: CGFloat = 2
    }
    
    // MARK: - Depth Chart Design Tokens
    enum DepthChart {
        // Chart dimensions
        static let cornerRadius: CGFloat = 10
        static let chartCornerRadius: CGFloat = 8
        static let depthHeightRatio: CGFloat = 0.90
        
        // Line widths
        static let depthLineWidth: CGFloat = 2.5
        static let gridLineWidth: CGFloat = 0.5
        static let midPriceLineWidth: CGFloat = 1.5
        
        // Marker sizes
        static let bestPriceMarkerSize: CGFloat = 10
        static let bestPriceOuterSize: CGFloat = 18
        static let crosshairDotSize: CGFloat = 10
        static let crosshairOuterSize: CGFloat = 20
        
        // Glow effects
        static let lineGlowRadius: CGFloat = 6
        static let markerGlowRadius: CGFloat = 8
        
        // Typography sizes
        static let headerLabelSize: CGFloat = 9
        static let headerValueSize: CGFloat = 13
        static let axisLabelSize: CGFloat = 9
        static let midPriceLabelSize: CGFloat = 10
        
        // Padding
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 10
        static let headerBottomPadding: CGFloat = 8
        
        // Animation durations
        static let dataUpdateDuration: Double = 0.25
        static let crosshairFadeDuration: Double = 0.15
        static let pulseDuration: Double = 1.5
        
        // Opacity values - Dark mode
        static let bidAreaTopDark: Double = 0.45
        static let bidAreaMidDark: Double = 0.25
        static let bidAreaBottomDark: Double = 0.04
        static let askAreaTopDark: Double = 0.45
        static let askAreaMidDark: Double = 0.25
        static let askAreaBottomDark: Double = 0.04
        static let gridOpacityDark: Double = 0.05
        static let midPriceLineOpacityDark: Double = 0.35
        
        // Opacity values - Light mode
        static let bidAreaTopLight: Double = 0.32
        static let bidAreaMidLight: Double = 0.18
        static let bidAreaBottomLight: Double = 0.02
        static let askAreaTopLight: Double = 0.32
        static let askAreaMidLight: Double = 0.18
        static let askAreaBottomLight: Double = 0.02
        static let gridOpacityLight: Double = 0.04
        static let midPriceLineOpacityLight: Double = 0.20
        
        // Background colors
        static let bgTopDark = Color(white: 0.07)
        static let bgBottomDark = Color(white: 0.03)
        static let bgTopLight = Color(white: 0.98)
        static let bgBottomLight = Color(white: 0.95)
    }

    enum Colors {
        // Text colors - adaptive for light/dark mode
        static let textPrimary = Color.adaptive(light: Color(white: 0.1), dark: Color.white)
        static let textSecondary = Color.adaptive(light: Color.gray, dark: Color.gray.opacity(0.95))
        
        // Grid and axis colors - adaptive for light/dark mode
        // Enhanced visibility: 0.15 dark / 0.10 light for professional chart appearance
        static let grid = Color.adaptive(
            light: Color.black.opacity(0.10),
            dark: Color.white.opacity(0.15)
        )
        static let tick = Color.adaptive(
            light: Color.black.opacity(0.25),
            dark: Color.white.opacity(0.25)
        )
        static let axisLabel = Color.adaptive(
            light: Color(white: 0.4),
            dark: Color(white: 0.6)
        )
        
        // Badge colors - adaptive for light/dark mode
        static let badgeBackground = Color.adaptive(
            light: Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.95),
            dark: Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.95)
        )
        static let badgeStroke = Color.adaptive(
            light: Color(red: 0.831, green: 0.686, blue: 0.216).opacity(0.4),  // Brand gold for light mode
            dark: Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.5)        // Bright gold for dark mode
        )
        
        // Premium chart fill gradient - adaptive for light/dark mode
        // Dark mode: Rich amber/gold with cinematic glow
        // Light mode: Deeper amber tones that complement the light background
        static let chartFillTop = Color.adaptive(
            light: Color(red: 0.831, green: 0.686, blue: 0.216).opacity(0.35),
            dark: Color(red: 1.0, green: 0.85, blue: 0.0).opacity(0.48)
        )
        static let chartFillMid = Color.adaptive(
            light: Color(red: 0.80, green: 0.65, blue: 0.18).opacity(0.22),
            dark: Color(red: 0.98, green: 0.78, blue: 0.0).opacity(0.32)
        )
        static let chartFillLow = Color.adaptive(
            light: Color(red: 0.77, green: 0.61, blue: 0.14).opacity(0.12),
            dark: Color(red: 0.95, green: 0.70, blue: 0.0).opacity(0.18)
        )
        static let chartFillBottom = Color.adaptive(
            light: Color(red: 0.74, green: 0.58, blue: 0.12).opacity(0.04),
            dark: Color(red: 0.90, green: 0.65, blue: 0.0).opacity(0.06)
        )
        static let chartFillZero = Color.clear
        
        // Chart background - adaptive gradient for light/dark mode
        // Dark mode: Deep charcoal for professional trading look
        // Light mode: Warm off-white that blends seamlessly with card background (#FFFDF8)
        // to prevent the Y-axis area from looking disconnected from the chart
        static let chartBgTop = Color.adaptive(
            light: Color(red: 0.985, green: 0.98, blue: 0.965),     // Warm off-white matching card tone
            dark: Color(red: 0.055, green: 0.055, blue: 0.075)
        )
        static let chartBgBottom = Color.adaptive(
            light: Color(red: 0.965, green: 0.96, blue: 0.945),     // Slightly deeper warm tone for depth
            dark: Color(red: 0.015, green: 0.015, blue: 0.03)
        )
        
        // Price line - adaptive gold aligned with BrandColors.goldBase (#D4AF37)
        // Dark mode: Bright, saturated gold for high contrast on dark backgrounds
        // Light mode: Deeper, richer gold that pops against warm off-white chart background
        static let gold = Color.adaptive(
            light: Color(red: 0.75, green: 0.60, blue: 0.12),     // Deeper gold for better contrast on warm bg
            dark: Color(red: 1.0, green: 0.85, blue: 0.05)        // Bright gold (unchanged)
        )
        static let goldGlow = Color.adaptive(
            light: Color(red: 0.75, green: 0.60, blue: 0.12).opacity(0.30),
            dark: Color(red: 1.0, green: 0.82, blue: 0.0).opacity(0.38)
        )
        static let goldGlowOuter = Color.adaptive(
            light: Color(red: 0.75, green: 0.60, blue: 0.12).opacity(0.15),
            dark: Color(red: 1.0, green: 0.80, blue: 0.0).opacity(0.18)
        )
        
        // Order book colors - clean, professional (Binance-style)
        static let bid = Color(red: 0.05, green: 0.78, blue: 0.50)  // Clean teal-green
        static let ask = Color(red: 0.96, green: 0.28, blue: 0.36)  // Clean coral-red
        
        // Enhanced indicator colors - vibrant and distinct (adaptive for light/dark)
        static let smaLine = Color.adaptive(
            light: Color(red: 0.15, green: 0.45, blue: 0.90),  // Deeper blue for light backgrounds
            dark: Color(red: 0.35, green: 0.65, blue: 1.0)     // Bright sky blue
        )
        static let emaLine = Color.adaptive(
            light: Color(red: 0.90, green: 0.45, blue: 0.08),  // Deeper orange for light backgrounds
            dark: Color(red: 1.0, green: 0.55, blue: 0.15)     // Warm orange
        )
        static let bbLine = Color.adaptive(
            light: Color(red: 0.50, green: 0.30, blue: 0.88),  // Deeper purple for light backgrounds
            dark: Color(red: 0.65, green: 0.45, blue: 1.0)     // Soft purple
        )
        static let rsiLine = Color.adaptive(
            light: Color(red: 0.10, green: 0.60, blue: 0.55),  // Deeper teal for light backgrounds
            dark: Color(red: 0.3, green: 0.85, blue: 0.75)     // Teal/mint
        )
        static let macdLine = Color.adaptive(
            light: Color(red: 0.12, green: 0.58, blue: 0.32),  // Deeper green for light backgrounds
            dark: Color(red: 0.25, green: 0.75, blue: 0.45)    // Fresh green
        )
        static let macdSignal = Color.adaptive(
            light: Color(red: 0.88, green: 0.30, blue: 0.30),  // Deeper coral for light backgrounds
            dark: Color(red: 1.0, green: 0.45, blue: 0.45)     // Soft coral
        )
    }
}

// MARK: - Numeric text helpers
struct NumericText: ViewModifier {
    let font: Font
    let color: Color
    let tracking: CGFloat
    func body(content: Content) -> some View {
        content
            .font(font)
            .monospacedDigit()
            .foregroundColor(color)
            .tracking(tracking)
    }
}

extension View {
    func numeric(_ font: Font = DS.Fonts.orderBookNumber, color: Color = DS.Colors.textPrimary, tracking: CGFloat = -0.4) -> some View {
        modifier(NumericText(font: font, color: color, tracking: tracking))
    }
}
