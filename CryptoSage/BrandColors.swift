import SwiftUI
import UIKit

public enum BrandColors {
    // Classic Gold palette (Option C)
    // Base: #D4AF37, Light: #F3D36D, Dark: #8C6B00
    public static let goldBase: Color = Color(red: 212/255, green: 175/255, blue: 55/255)   // #D4AF37
    public static let goldLight: Color = Color(red: 243/255, green: 211/255, blue: 109/255) // #F3D36D
    public static let goldDark:  Color = Color(red: 140/255, green: 107/255, blue: 0/255)   // #8C6B00
    
    // Lighter gold for light mode buttons (avoids the dark edge)
    public static let goldMid: Color = Color(red: 225/255, green: 190/255, blue: 75/255)   // Between base and light

    // Canonical gold alias (for legacy callers)
    public static var gold: Color { goldBase }

    // Stroke tints
    public static var goldStrokeHighlight: Color { goldLight.opacity(0.9) }
    public static var goldStrokeShadow: Color { goldDark.opacity(0.9) }

    // Border/shadow tints for consistent outlines and shadows
    public static var goldBorder: Color { goldDark.opacity(0.85) }
    public static var goldShadow: Color { goldDark.opacity(0.60) }

    // Dark mode gradients (include dark edge for depth)
    public static var goldHorizontal: LinearGradient {
        LinearGradient(colors: [goldLight, goldBase, goldDark], startPoint: .leading, endPoint: .trailing)
    }
    public static var goldVertical: LinearGradient {
        LinearGradient(colors: [goldLight, goldBase, goldDark], startPoint: .top, endPoint: .bottom)
    }
    public static var goldDiagonalGradient: LinearGradient {
        LinearGradient(colors: [goldLight, goldBase, goldDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    // Light mode gradients (flat, no dark edge - cleaner appearance on white backgrounds)
    public static var goldHorizontalLight: LinearGradient {
        LinearGradient(colors: [goldLight, goldBase], startPoint: .leading, endPoint: .trailing)
    }
    public static var goldVerticalLight: LinearGradient {
        LinearGradient(colors: [goldLight, goldBase], startPoint: .top, endPoint: .bottom)
    }
    public static var goldDiagonalGradientLight: LinearGradient {
        LinearGradient(colors: [goldLight, goldBase], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    // Flat solid gold for completely flat buttons in light mode
    public static var goldFlat: Color { goldBase }

    // UIKit counterparts (for cross UIKit/SwiftUI use)
    public static var uiGoldBase: UIColor { UIColor(red: 212/255, green: 175/255, blue: 55/255, alpha: 1.0) }
    public static var uiGoldLight: UIColor { UIColor(red: 243/255, green: 211/255, blue: 109/255, alpha: 1.0) }
    public static var uiGoldDark: UIColor  { UIColor(red: 140/255, green: 107/255, blue: 0/255, alpha: 1.0) }
    public static var uiGoldBorder: UIColor { uiGoldDark.withAlphaComponent(0.85) }
    public static var uiGoldShadow: UIColor { uiGoldDark.withAlphaComponent(0.60) }
    
    // MARK: - Dark Charcoal Palette (Light Mode Buttons)
    // Professional dark charcoal for high contrast on light backgrounds
    // Light: #5A5A5A, Base: #3D3D3D, Dark: #2A2A2A
    public static let silverLight: Color = Color(red: 90/255, green: 90/255, blue: 90/255)    // #5A5A5A - charcoal light
    public static let silverBase:  Color = Color(red: 61/255, green: 61/255, blue: 61/255)    // #3D3D3D - charcoal base
    public static let silverDark:  Color = Color(red: 42/255, green: 42/255, blue: 42/255)    // #2A2A2A - charcoal dark
    
    // Silver stroke tints
    public static var silverStrokeHighlight: Color { silverLight.opacity(0.9) }
    public static var silverStrokeShadow: Color { silverDark.opacity(0.9) }
    
    // Silver border/shadow tints
    public static var silverBorder: Color { silverDark.opacity(0.85) }
    public static var silverShadow: Color { silverDark.opacity(0.60) }
    
    // Silver gradients for light mode buttons
    public static var silverHorizontal: LinearGradient {
        LinearGradient(colors: [silverLight, silverBase, silverDark], startPoint: .leading, endPoint: .trailing)
    }
    public static var silverVertical: LinearGradient {
        LinearGradient(colors: [silverLight, silverBase, silverDark], startPoint: .top, endPoint: .bottom)
    }
    public static var silverDiagonalGradient: LinearGradient {
        LinearGradient(colors: [silverLight, silverBase, silverDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    // Flat silver (2-stop, no dark edge - cleaner)
    public static var silverHorizontalFlat: LinearGradient {
        LinearGradient(colors: [silverLight, silverBase], startPoint: .leading, endPoint: .trailing)
    }
    public static var silverVerticalFlat: LinearGradient {
        LinearGradient(colors: [silverLight, silverBase], startPoint: .top, endPoint: .bottom)
    }
    
    // UIKit charcoal counterparts
    public static var uiSilverBase: UIColor { UIColor(red: 61/255, green: 61/255, blue: 61/255, alpha: 1.0) }
    public static var uiSilverLight: UIColor { UIColor(red: 90/255, green: 90/255, blue: 90/255, alpha: 1.0) }
    public static var uiSilverDark: UIColor { UIColor(red: 42/255, green: 42/255, blue: 42/255, alpha: 1.0) }
    
    // MARK: - Adaptive CTA Gradients (Gold in dark mode, Silver in light mode)
    /// Horizontal button gradient - gold in dark, silver in light
    public static func ctaHorizontal(isDark: Bool) -> LinearGradient {
        isDark
            ? LinearGradient(colors: [goldLight, goldBase], startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [silverLight, silverBase, silverDark], startPoint: .leading, endPoint: .trailing)
    }
    
    /// Vertical button gradient - gold in dark, silver in light
    public static func ctaVertical(isDark: Bool) -> LinearGradient {
        isDark
            ? LinearGradient(colors: [goldLight, goldBase, goldDark], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [silverLight, silverBase, silverDark], startPoint: .top, endPoint: .bottom)
    }
    
    /// Diagonal button gradient - gold in dark, silver in light
    public static func ctaDiagonal(isDark: Bool) -> LinearGradient {
        isDark
            ? LinearGradient(colors: [goldLight, goldBase, goldDark], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [silverLight, silverBase, silverDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    /// Shadow color for CTA buttons - gold tinted in dark, subtle gray in light
    public static func ctaShadow(isDark: Bool) -> Color {
        isDark ? goldBase.opacity(0.3) : Color.black.opacity(0.2)
    }
    
    /// Text color for CTA buttons - black on gold (dark mode), white on charcoal (light mode)
    public static func ctaTextColor(isDark: Bool) -> Color {
        isDark ? Color.black.opacity(0.92) : Color.white
    }
    
    /// Rim stroke color for CTA buttons - gold tinted in dark, silver tinted in light
    public static func ctaRimStroke(isDark: Bool) -> Color {
        isDark ? goldStrokeHighlight : silverStrokeHighlight
    }
    
    // MARK: - Prediction Market Accent Colors
    
    /// Polymarket purple/indigo accent
    public static let polymarketPurple: Color = Color(red: 99/255, green: 102/255, blue: 241/255)  // #6366F1 - Indigo
    public static let polymarketPurpleLight: Color = Color(red: 139/255, green: 141/255, blue: 255/255)
    public static let polymarketPurpleDark: Color = Color(red: 67/255, green: 56/255, blue: 202/255)
    
    /// Kalshi teal/cyan accent
    public static let kalshiTeal: Color = Color(red: 0/255, green: 178/255, blue: 153/255)  // #00B299 - Teal
    public static let kalshiTealLight: Color = Color(red: 52/255, green: 211/255, blue: 191/255)
    public static let kalshiTealDark: Color = Color(red: 0/255, green: 128/255, blue: 110/255)
    
    /// General prediction markets accent (amber/orange)
    public static let predictionAccent: Color = Color(red: 245/255, green: 158/255, blue: 11/255)  // #F59E0B - Amber
    
    // MARK: - Semantic Feature Accent Colors
    /// Alert/notification action accent (used for non-premium alert controls)
    public static let alertAccent: Color = Color(red: 40/255, green: 168/255, blue: 238/255) // #28A8EE
    public static let alertAccentLight: Color = Color(red: 102/255, green: 197/255, blue: 247/255)
    
    /// Polymarket gradient
    public static var polymarketGradient: LinearGradient {
        LinearGradient(colors: [polymarketPurpleLight, polymarketPurple], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    /// Kalshi gradient
    public static var kalshiGradient: LinearGradient {
        LinearGradient(colors: [kalshiTealLight, kalshiTeal], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    /// Get platform-specific color
    public static func predictionPlatformColor(for platform: String) -> Color {
        switch platform.lowercased() {
        case "polymarket":
            return polymarketPurple
        case "kalshi":
            return kalshiTeal
        default:
            return predictionAccent
        }
    }
}
