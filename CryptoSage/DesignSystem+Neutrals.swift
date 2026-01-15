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
}
