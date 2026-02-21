import Foundation

// MARK: - Color Palette Enum

/// Heat map color palette options
public enum HeatMapColorPalette: String, CaseIterable, Identifiable {
    case cool, classic, warm
    public var id: String { rawValue }
    var displayName: String {
        switch self {
        case .cool: return "Cool (Pro)"    // Modern - Pure vivid colors, gray neutral
        case .classic: return "Classic"    // Terminal - Navy slate, forest green, crimson
        case .warm: return "Warm"          // Premium - Gold neutral, lime, vermillion
        }
    }
    
    /// Deadband percentage - values below this show neutral color
    var deadband: Double {
        switch self {
        case .cool: return 0.08       // Small deadband - colors appear quickly (vivid, reactive)
        case .classic: return 0.15   // Largest deadband - more neutral area (measured, institutional)
        case .warm: return 0.10      // Medium deadband (balanced)
        }
    }
    
    /// Gamma curve for color interpolation (higher = smoother blend)
    var gamma: Double {
        switch self {
        case .cool: return 0.52       // Quick, punchy color emergence (neon, immediate)
        case .classic: return 0.65   // Slowest color emergence (refined, patient)
        case .warm: return 0.58      // Balanced blend (warm, natural)
        }
    }
}

/// Professional heat map color system.
///
/// KEY DESIGN PRINCIPLE:
/// - Each palette has distinct neutral point and color personality
/// - Cool (Pro): Pure gray midpoint, vivid neon greens/reds (Finviz-style)
/// - Classic: Navy-slate midpoint, forest green, deep crimson (Bloomberg-terminal inspired)
/// - Warm: Gold midpoint, lime green, vermillion (premium warm)
///
/// Deadband and gamma per palette ensure smooth, professional blends.
///
public enum HeatMapColors {
    
    /// RGB tuple type (0-1 range)
    public typealias RGB = (Double, Double, Double)
    
    // MARK: - Warm Palette (PREMIUM GOLD - Vibrant warm tones)
    // Theme: Premium warm with clean gold neutral
    // Losses: Vibrant warm red (vermillion/orange-red)
    // Neutral: CLEAN BRIGHT GOLD (premium, not muddy)
    // Gains: Vibrant warm green (lime/chartreuse)
    
    public enum Warm {
        // Dark mode - CLEAN BRIGHT GOLD neutral (premium look)
        public static let darkNeutral: RGB = (0.75, 0.62, 0.25)  // Clean bright gold
        
        // Mild colors - warm transitions
        public static let darkGreenMild: RGB = (0.55, 0.68, 0.30)  // Gold → lime
        public static let darkRedMild: RGB = (0.78, 0.48, 0.25)    // Gold → orange-red
        
        // Base colors - vibrant warm
        public static let darkGreenBase: RGB = (0.35, 0.75, 0.28)  // Lime green
        public static let darkRedBase: RGB = (0.88, 0.28, 0.15)    // Warm red
        
        // Max colors - VIBRANT WARM
        public static let darkGreen: RGB = (0.25, 0.85, 0.25)      // Vibrant lime
        public static let darkRed: RGB = (0.95, 0.18, 0.10)        // Vibrant vermillion
        
        // Light mode
        // SATURATION FIX: Boosted for better visibility on light backgrounds
        public static let lightNeutral: RGB = (0.94, 0.90, 0.72)   // Slightly deeper gold
        public static let lightGreenMild: RGB = (0.80, 0.90, 0.68) // Richer warm green (was 0.88/0.94/0.78)
        public static let lightRedMild: RGB = (0.94, 0.78, 0.68)   // Richer warm red (was 0.96/0.86/0.78)
        public static let lightGreenBase: RGB = (0.45, 0.74, 0.38) // Deeper lime (was 0.60/0.82/0.50)
        public static let lightRedBase: RGB = (0.86, 0.42, 0.32)   // Deeper vermillion (was 0.92/0.52/0.42)
        public static let lightGreen: RGB = (0.25, 0.65, 0.24)     // Rich lime (was 0.30/0.72/0.28)
        public static let lightRed: RGB = (0.82, 0.18, 0.12)       // Rich vermillion (was 0.88/0.22/0.15)
    }
    
    // MARK: - Cool Palette (MODERN PRO - Pure colors, clean gray neutral)
    // Theme: Modern professional - maximum saturation like NASDAQ/Finviz
    // Losses: PURE SATURATED RED
    // Neutral: CLEAN NEUTRAL GRAY (no color cast)
    // Gains: PURE SATURATED GREEN
    
    public enum Cool {
        // Dark mode - DARKER NEUTRAL GRAY for better color contrast
        // WASH-OUT FIX: Reduced from 0.38 to 0.28 for more vivid color differentiation
        public static let darkNeutral: RGB = (0.28, 0.28, 0.28)  // Darker neutral for better contrast
        
        // Mild colors - quick punch into color
        public static let darkGreenMild: RGB = (0.28, 0.48, 0.32)  // Gray → green (faster)
        public static let darkRedMild: RGB = (0.52, 0.28, 0.26)    // Gray → red (faster)
        
        // Base colors - saturated stock colors
        public static let darkGreenBase: RGB = (0.10, 0.75, 0.30)  // Bright green
        public static let darkRedBase: RGB = (0.88, 0.15, 0.12)    // Bright red
        
        // Max colors - MAXIMUM SATURATION
        public static let darkGreen: RGB = (0.02, 0.88, 0.32)      // VIVID PURE GREEN
        public static let darkRed: RGB = (0.94, 0.06, 0.04)        // VIVID PURE RED
        
        // Light mode - SATURATION FIX: Boosted from pastel to medium-vivid for actual visibility.
        // Previous values were so pale that tiles all looked the same washed-out green/gray.
        // Now uses richer colors that are clearly distinguishable on light backgrounds.
        public static let lightNeutral: RGB = (0.88, 0.88, 0.88)   // Slightly darker gray for contrast
        public static let lightGreenMild: RGB = (0.72, 0.90, 0.74) // Visible light green (was 0.80/0.92/0.82)
        public static let lightRedMild: RGB = (0.92, 0.74, 0.74)   // Visible light red (was 0.94/0.82/0.82)
        public static let lightGreenBase: RGB = (0.30, 0.72, 0.40) // Rich medium green (was 0.45/0.80/0.50)
        public static let lightRedBase: RGB = (0.85, 0.35, 0.32)   // Rich medium red (was 0.92/0.45/0.42)
        public static let lightGreen: RGB = (0.05, 0.62, 0.28)     // Deep green (was 0.05/0.70/0.30)
        public static let lightRed: RGB = (0.82, 0.12, 0.10)       // Deep red (was 0.88/0.15/0.12)
    }
    
    // MARK: - Classic Palette (BLOOMBERG TERMINAL - Navy slate, institutional)
    // Theme: Bloomberg-inspired institutional terminal
    // The navy-slate neutral is the key differentiator from Cool's pure gray.
    // Losses: DEEP CRIMSON (rich, not neon - think stock exchange boards)
    // Neutral: NAVY SLATE (subtle blue undertone, instantly distinguishable)
    // Gains: FOREST GREEN (rich depth with subtle teal, institutional feel)
    
    public enum Classic {
        // Dark mode - NAVY SLATE neutral (Bloomberg-inspired, clearly distinct from Cool's gray)
        public static let darkNeutral: RGB = (0.20, 0.22, 0.33)    // Cooler navy slate for stronger separation from Cool
        
        // Mild colors - blue-tinted transitions from slate
        public static let darkGreenMild: RGB = (0.20, 0.36, 0.37)  // Slate → forest tint
        public static let darkRedMild: RGB = (0.38, 0.20, 0.30)    // Slate → wine tint
        
        // Base colors - rich institutional tones
        public static let darkGreenBase: RGB = (0.08, 0.56, 0.42)  // Deep forest green
        public static let darkRedBase: RGB = (0.68, 0.14, 0.22)    // Deep crimson
        
        // Max colors - INSTITUTIONAL (rich depth, not neon)
        public static let darkGreen: RGB = (0.05, 0.72, 0.38)      // Rich forest green
        public static let darkRed: RGB = (0.82, 0.08, 0.18)        // Rich crimson
        
        // Light mode - blue-tinted light tones
        // SATURATION FIX: Boosted for better visibility on light backgrounds
        public static let lightNeutral: RGB = (0.82, 0.84, 0.91)   // Slightly cooler blue-gray for better palette identity
        public static let lightGreenMild: RGB = (0.70, 0.85, 0.78) // Richer forest tint (was 0.78/0.88/0.85)
        public static let lightRedMild: RGB = (0.90, 0.74, 0.77)   // Richer wine tint (was 0.92/0.82/0.84)
        public static let lightGreenBase: RGB = (0.22, 0.58, 0.44) // Deeper forest (was 0.35/0.66/0.52)
        public static let lightRedBase: RGB = (0.70, 0.28, 0.34)   // Deeper crimson (was 0.76/0.36/0.40)
        public static let lightGreen: RGB = (0.06, 0.50, 0.34)     // Rich deep forest (was 0.08/0.56/0.38)
        public static let lightRed: RGB = (0.68, 0.10, 0.18)       // Rich deep crimson (was 0.72/0.14/0.22)
    }
    
    // MARK: - Color Anchors
    
    /// 7-color anchor system: neutral, mild tints, base colors, and full saturation
    /// Creates 3 distinct zones for better visual differentiation:
    /// - Zone 1 (0-1%): Neutral gray
    /// - Zone 2 (1-2.5%): Mild tint (barely colored)
    /// - Zone 3 (2.5%+): Base to max saturation
    public struct Anchors {
        public let neutral: RGB
        public let redMild: RGB      // For tiny negative changes (1-2.5%)
        public let redBase: RGB      // For small negative changes (2.5-4%)
        public let redMax: RGB       // For large negative changes (4%+)
        public let greenMild: RGB    // For tiny positive changes (1-2.5%)
        public let greenBase: RGB    // For small positive changes (2.5-4%)
        public let greenMax: RGB     // For large positive changes (4%+)
        
        public init(neutral: RGB, redMild: RGB, redBase: RGB, redMax: RGB, greenMild: RGB, greenBase: RGB, greenMax: RGB) {
            self.neutral = neutral
            self.redMild = redMild
            self.redBase = redBase
            self.redMax = redMax
            self.greenMild = greenMild
            self.greenBase = greenBase
            self.greenMax = greenMax
        }
    }
    
    /// Get color anchors for a palette
    public static func anchors(for palette: HeatMapColorPalette, isLightMode: Bool) -> Anchors {
        switch palette {
        case .cool:
            return isLightMode
                ? Anchors(neutral: Cool.lightNeutral, redMild: Cool.lightRedMild, redBase: Cool.lightRedBase, redMax: Cool.lightRed, greenMild: Cool.lightGreenMild, greenBase: Cool.lightGreenBase, greenMax: Cool.lightGreen)
                : Anchors(neutral: Cool.darkNeutral, redMild: Cool.darkRedMild, redBase: Cool.darkRedBase, redMax: Cool.darkRed, greenMild: Cool.darkGreenMild, greenBase: Cool.darkGreenBase, greenMax: Cool.darkGreen)
        case .classic:
            return isLightMode
                ? Anchors(neutral: Classic.lightNeutral, redMild: Classic.lightRedMild, redBase: Classic.lightRedBase, redMax: Classic.lightRed, greenMild: Classic.lightGreenMild, greenBase: Classic.lightGreenBase, greenMax: Classic.lightGreen)
                : Anchors(neutral: Classic.darkNeutral, redMild: Classic.darkRedMild, redBase: Classic.darkRedBase, redMax: Classic.darkRed, greenMild: Classic.darkGreenMild, greenBase: Classic.darkGreenBase, greenMax: Classic.darkGreen)
        case .warm:
            return isLightMode
                ? Anchors(neutral: Warm.lightNeutral, redMild: Warm.lightRedMild, redBase: Warm.lightRedBase, redMax: Warm.lightRed, greenMild: Warm.lightGreenMild, greenBase: Warm.lightGreenBase, greenMax: Warm.lightGreen)
                : Anchors(neutral: Warm.darkNeutral, redMild: Warm.darkRedMild, redBase: Warm.darkRedBase, redMax: Warm.darkRed, greenMild: Warm.darkGreenMild, greenBase: Warm.darkGreenBase, greenMax: Warm.darkGreen)
        }
    }
    
    // MARK: - Legacy Compatibility
    
    /// Legacy tuning struct (for backward compatibility)
    public struct Tuning {
        public let neg: RGB
        public let neu: RGB
        public let pos: RGB
        public let deadband: Double
        public let curveBoost: Double
        public let satMin: Double
        public let satMax: Double

        public init(neg: RGB, neu: RGB, pos: RGB, deadband: Double, curveBoost: Double, satMin: Double, satMax: Double) {
            self.neg = neg
            self.neu = neu
            self.pos = pos
            self.deadband = deadband
            self.curveBoost = curveBoost
            self.satMin = satMin
            self.satMax = satMax
        }
    }
    
    /// Legacy tuning (for backward compatibility)
    public static func tuning(for palette: HeatMapColorPalette, grayNeutral isLightMode: Bool) -> Tuning {
        let a = anchors(for: palette, isLightMode: isLightMode)
        return Tuning(
            neg: a.redMax,
            neu: a.neutral,
            pos: a.greenMax,
            deadband: 0.01,
            curveBoost: 0.0,
            satMin: 1.0,
            satMax: 1.0
        )
    }
    
    // MARK: - Shared Constants
    
    /// Vibrant green for sentiment gauge
    public static let GaugeGreen: RGB = (0.10, 0.85, 0.45)
    
    /// Tile border settings
    public static let tileBorderOpacity: Double = 0.08
    public static let tileBorderWidthDark: Double = 0.8
    public static let tileBorderWidthLight: Double = 1.0
}
