import SwiftUI

// Adaptive neutral tokens for surfaces, strokes, dividers, and chip/field backgrounds.
// These use a dynamic UIColor provider so they automatically flip with system appearance
// and with any app-wide PreferredScheme overrides.
extension DS {
    struct Neutral {
        // Elevated card/surface background (used for cards, chart containers, etc.)
        static let surface: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.05)
            : UIColor.black.withAlphaComponent(0.04)
        })

        // Standard subtle stroke around cards/controls
        static let stroke: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.08)
        })

        // Generic background tint for chips/fields/segmented controls at a given opacity
        static func bg(_ opacity: Double) -> Color {
            Color(UIColor { tc in
                tc.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(CGFloat(opacity))
                : UIColor.black.withAlphaComponent(CGFloat(opacity))
            })
        }

        // Divider/hairline color at a given opacity
        static func divider(_ opacity: Double = 0.08) -> Color {
            Color(UIColor { tc in
                tc.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(CGFloat(opacity))
                : UIColor.black.withAlphaComponent(CGFloat(opacity))
            })
        }
    }
    
    // MARK: - Adaptive Color Tokens for Light/Dark Mode
    // These colors automatically flip based on the current color scheme,
    // providing proper light mode support throughout the app.
    struct Adaptive {
        // Main screen background - black in dark mode, white in light mode
        static let background: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.black
            : UIColor.white
        })
        
        // Slightly elevated background for secondary areas
        static let backgroundSecondary: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.08, alpha: 1.0)
            : UIColor(white: 0.96, alpha: 1.0)
        })
        
        // Card/elevated surface background
        // Light mode: warm cream for premium feel (avoids harsh pure white)
        static let cardBackground: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.05)
            : UIColor(red: 1.0, green: 0.992, blue: 0.973, alpha: 1.0) // Warm cream #FFFDF8
        })
        
        // More prominent card background for emphasis
        // Light mode: very subtle warm tint for depth without gray muddiness
        static let cardBackgroundElevated: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor(red: 0.99, green: 0.99, blue: 0.98, alpha: 1.0)
        })
        
        // Primary text color - white in dark, black in light
        static let textPrimary: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor.black
        })
        
        // Secondary/muted text color
        static let textSecondary: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.70)
            : UIColor.black.withAlphaComponent(0.60)
        })
        
        // Tertiary/hint text color
        static let textTertiary: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.50)
            : UIColor.black.withAlphaComponent(0.45)
        })
        
        // Border/stroke color for cards and controls
        // Light mode: warm brown-tinted stroke for softer appearance
        static let stroke: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor(red: 0.55, green: 0.50, blue: 0.45, alpha: 0.12) // Warm brown stroke
        })
        
        // Stronger stroke for emphasis
        static let strokeStrong: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.18)
            : UIColor.black.withAlphaComponent(0.15)
        })
        
        // Divider/separator color
        // Light mode: warm tinted divider for cohesive appearance
        static let divider: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor(red: 0.55, green: 0.50, blue: 0.45, alpha: 0.08) // Warm divider
        })
        
        // Surface overlay for glassmorphism effects
        static let surfaceOverlay: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.04)
            : UIColor.black.withAlphaComponent(0.03)
        })
        
        // Gradient overlay colors for cards (top highlight)
        static let gradientHighlight: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.white.withAlphaComponent(0.80)
        })
        
        // Shadow color - black with varying opacity (default values)
        static let shadow: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.40)
            : UIColor.black.withAlphaComponent(0.12)
        })
        
        /// Adaptive shadow with custom opacity values for dark and light modes.
        /// Light mode opacity defaults to 40% of dark mode opacity if not specified.
        /// Usage: .shadow(color: .clear, radius: 0)
        static func shadowWith(_ darkOpacity: Double, light lightOpacity: Double? = nil) -> Color {
            Color(UIColor { tc in
                let opacity = tc.userInterfaceStyle == .dark
                    ? darkOpacity
                    : (lightOpacity ?? darkOpacity * 0.4)
                return UIColor.black.withAlphaComponent(CGFloat(opacity))
            })
        }
        
        /// Soft shadow preset - suitable for cards and elevated surfaces
        static let shadowSoft: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.25)
            : UIColor.black.withAlphaComponent(0.08)
        })
        
        /// Medium shadow preset - suitable for buttons and interactive elements
        static let shadowMedium: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.35)
            : UIColor.black.withAlphaComponent(0.12)
        })
        
        // MARK: - Warm Shadows for Light Mode
        // These use warm brown tints instead of black for a softer, more premium look in light mode
        
        /// Warm soft shadow - for cards and surfaces (warm brown-tan in light mode)
        static let shadowWarmSoft: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.25)
            : UIColor(red: 0.55, green: 0.45, blue: 0.33, alpha: 0.10) // Warm brown #8B7355 @ 10%
        })
        
        /// Warm medium shadow - for elevated elements (slightly stronger)
        static let shadowWarmMedium: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.35)
            : UIColor(red: 0.55, green: 0.45, blue: 0.33, alpha: 0.14) // Warm brown @ 14%
        })
        
        /// Adaptive warm shadow with custom opacity
        /// Usage: .shadow(color: .clear, radius: 0)
        static func shadowWarmWith(_ darkOpacity: Double, light lightOpacity: Double? = nil) -> Color {
            Color(UIColor { tc in
                if tc.userInterfaceStyle == .dark {
                    return UIColor.black.withAlphaComponent(CGFloat(darkOpacity))
                } else {
                    // Warm brown shadow for light mode
                    let opacity = lightOpacity ?? (darkOpacity * 0.35)
                    return UIColor(red: 0.55, green: 0.45, blue: 0.33, alpha: CGFloat(opacity))
                }
            })
        }
        
        // Chip/pill background
        // Light mode: warm cream-gray for visibility without cold harshness
        static let chipBackground: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor(red: 0.96, green: 0.95, blue: 0.94, alpha: 1.0) // Warm gray #F5F3F0
        })
        
        // Selected/active chip background
        static let chipBackgroundActive: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.15)
            : UIColor(red: 0.93, green: 0.91, blue: 0.89, alpha: 1.0) // Warmer gray for active
        })
        
        // Configurable opacity background (like DS.Neutral.bg but for foreground-aware usage)
        static func overlay(_ opacity: Double) -> Color {
            Color(UIColor { tc in
                tc.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(CGFloat(opacity))
                : UIColor.black.withAlphaComponent(CGFloat(opacity))
            })
        }
        
        // MARK: - Adaptive Gold/Yellow Colors for Light Mode Readability
        // These colors use bright gold in dark mode and darker amber/brown in light mode
        // to ensure text readability on light backgrounds while maintaining the gold theme.
        
        /// Gold accent color - bright gold in dark mode, dark amber in light mode
        /// Use for decorative elements, icons, and non-text accents
        static let gold: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.9647, green: 0.8275, blue: 0.3961, alpha: 1.0) // #F6D365 bright gold
            : UIColor(red: 0.545, green: 0.412, blue: 0.078, alpha: 1.0)   // #8B6914 dark amber
        })
        
        /// Gold text color - optimized for text readability with high contrast
        /// Use for gold-colored text that needs to be readable on light/dark backgrounds
        static let goldText: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.9647, green: 0.8275, blue: 0.3961, alpha: 1.0) // #F6D365 bright gold
            : UIColor(red: 0.478, green: 0.357, blue: 0.039, alpha: 1.0)   // #7A5B0A darker amber for better contrast
        })
        
        /// Gold text light variant - slightly brighter than goldText for larger text
        /// Use for headings or larger text where slightly less contrast is acceptable
        static let goldTextLight: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.9647, green: 0.8275, blue: 0.3961, alpha: 1.0) // #F6D365 bright gold
            : UIColor(red: 0.612, green: 0.475, blue: 0.118, alpha: 1.0)   // #9C791E medium amber
        })
        
        /// Neutral yellow for sentiment indicators - readable amber in light mode
        /// Replaces .yellow for "Neutral" sentiment state
        static let neutralYellow: Color = Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)         // #FFFF00 pure yellow
            : UIColor(red: 0.722, green: 0.525, blue: 0.043, alpha: 1.0)   // #B8860B dark goldenrod
        })
        
        /// Gold gradient colors for adaptive gradients
        /// Returns (light, dark) color pair based on color scheme
        static func goldGradientColors(isDark: Bool) -> (light: Color, dark: Color) {
            if isDark {
                return (
                    Color(red: 0.9647, green: 0.8275, blue: 0.3961), // #F6D365
                    Color(red: 0.8314, green: 0.6863, blue: 0.2157)  // #D4AF37
                )
            } else {
                return (
                    Color(red: 0.612, green: 0.475, blue: 0.118),    // #9C791E
                    Color(red: 0.478, green: 0.357, blue: 0.039)     // #7A5B0A
                )
            }
        }
    }
}
