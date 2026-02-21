import SwiftUI

// MARK: - Shared Color Tokens
extension Color {
    static var gold: Color { BrandColors.goldBase }
}

// MARK: - Adaptive Gradient Helpers
// These provide color-scheme aware gradients for light mode support

/// Namespace for adaptive gradient tokens that respond to light/dark mode
enum AdaptiveGradients {
    /// Gold button gradient - black in light mode, gold in dark mode
    /// Matches the market page segment chip style in light mode
    static func goldButton(isDark: Bool) -> LinearGradient {
        if isDark {
            // Dark mode: 3-stop gold gradient with depth
            return SwiftUI.LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: BrandColors.goldLight, location: 0.0),
                    .init(color: BrandColors.goldBase,  location: 0.52),
                    .init(color: BrandColors.goldDark,  location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            // Light mode: black gradient — clean, high-contrast, matches market page style
            return SwiftUI.LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(white: 0.18), location: 0.0),
                    .init(color: Color(white: 0.10), location: 0.52),
                    .init(color: Color(white: 0.04), location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    /// Chip gradient - brand gold in dark mode, clean black in light mode
    /// Dark mode: goldLight → goldBase → goldDark (bright on dark backgrounds)
    /// Light mode: black gradient — matches market page segment chips for consistency
    static func chipGold(isDark: Bool) -> LinearGradient {
        if isDark {
            return SwiftUI.LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: BrandColors.goldLight, location: 0.0),
                    .init(color: BrandColors.goldBase,  location: 0.55),
                    .init(color: BrandColors.goldDark,  location: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // Light mode: clean black-to-charcoal gradient — same visual language as
            // Market page segment chips (SegmentChipStyle). Avoids muddy gold-on-white
            // and ensures high-contrast, professional look.
            return SwiftUI.LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(white: 0.12), location: 0.0),
                    .init(color: Color(white: 0.05), location: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    /// CTA bottom shade - transparent in light mode to avoid dark edge
    static func ctaBottomShade(isDark: Bool) -> LinearGradient {
        if isDark {
            return SwiftUI.LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.12)],
                startPoint: .center,
                endPoint: .bottom
            )
        } else {
            // Light mode: completely transparent for flat appearance
            return SwiftUI.LinearGradient(
                colors: [Color.clear, Color.clear],
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }
    
    /// CTA rim stroke - adapts for light/dark
    static func ctaRimStroke(isDark: Bool) -> LinearGradient {
        if isDark {
            return SwiftUI.LinearGradient(
                colors: [Color.white.opacity(0.45), Color.white.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            // Light mode: neutral dark stroke — clean edge definition without gold tint
            return SwiftUI.LinearGradient(
                colors: [Color.white.opacity(0.35), Color.black.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Legacy Global Gradient Tokens (for backwards compatibility)
// These use the dark mode variants by default; prefer AdaptiveGradients in new code

var goldButtonGradient: LinearGradient {
    SwiftUI.LinearGradient(
        gradient: Gradient(stops: [
            .init(color: BrandColors.goldLight, location: 0.0),
            .init(color: BrandColors.goldBase,  location: 0.52),
            .init(color: BrandColors.goldDark,  location: 1.0)
        ]),
        startPoint: .top,
        endPoint: .bottom
    )
}

/// Light mode variant - silver gradient for clean appearance
var goldButtonGradientLight: LinearGradient {
    SwiftUI.LinearGradient(
        gradient: Gradient(stops: [
            .init(color: BrandColors.silverLight, location: 0.0),
            .init(color: BrandColors.silverBase,  location: 0.52),
            .init(color: BrandColors.silverDark,  location: 1.0)
        ]),
        startPoint: .top,
        endPoint: .bottom
    )
}

var redButtonGradient: LinearGradient {
    SwiftUI.LinearGradient(
        gradient: Gradient(stops: [
            .init(color: Color(red: 0.95, green: 0.25, blue: 0.25), location: 0.0),
            .init(color: Color(red: 0.88, green: 0.12, blue: 0.12), location: 0.52),
            .init(color: Color(red: 0.70, green: 0.05, blue: 0.05), location: 1.0)
        ]),
        startPoint: .top,
        endPoint: .bottom
    )
}

var chipGoldGradient: LinearGradient {
    SwiftUI.LinearGradient(
        gradient: Gradient(stops: [
            .init(color: BrandColors.goldLight, location: 0.0),
            .init(color: BrandColors.goldBase,  location: 0.55),
            .init(color: BrandColors.goldDark,  location: 1.0)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Light mode variant - silver chip gradient
var chipGoldGradientLight: LinearGradient {
    SwiftUI.LinearGradient(
        gradient: Gradient(stops: [
            .init(color: BrandColors.silverLight, location: 0.0),
            .init(color: BrandColors.silverBase,  location: 0.55),
            .init(color: BrandColors.silverDark,  location: 1.0)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

var ctaRimStrokeGradient: LinearGradient {
    SwiftUI.LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom)
}

var ctaRimStrokeGradientRed: LinearGradient {
    SwiftUI.LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.35, blue: 0.35).opacity(0.55),
            Color(red: 1.0, green: 0.35, blue: 0.35).opacity(0.18)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

var ctaBottomShade: LinearGradient {
    SwiftUI.LinearGradient(colors: [Color.clear, Color.black.opacity(0.12)], startPoint: .center, endPoint: .bottom)
}

/// Light mode variant - completely transparent
var ctaBottomShadeLight: LinearGradient {
    SwiftUI.LinearGradient(colors: [Color.clear, Color.clear], startPoint: .center, endPoint: .bottom)
}

func ctaBottomShade(height: CGFloat = 28) -> LinearGradient {
    // Height-aware variant; currently returns the same gradient.
    SwiftUI.LinearGradient(colors: [Color.clear, Color.black.opacity(0.12)], startPoint: .center, endPoint: .bottom)
}

func ctaBottomShade(height: CGFloat = 28, isDark: Bool) -> LinearGradient {
    // Color-scheme aware variant
    if isDark {
        return SwiftUI.LinearGradient(colors: [Color.clear, Color.black.opacity(0.12)], startPoint: .center, endPoint: .bottom)
    } else {
        return SwiftUI.LinearGradient(colors: [Color.clear, Color.clear], startPoint: .center, endPoint: .bottom)
    }
}

