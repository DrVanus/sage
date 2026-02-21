import SwiftUI

// MARK: - Unified Gold Header Icon
// Used consistently across all section headers on the homepage
// Premium style with gradient ring, shine, and shadow for depth

public struct GoldHeaderGlyph: View {
    @Environment(\.colorScheme) private var colorScheme
    
    public let systemName: String
    public var size: CGFloat = 28
    public var iconSize: CGFloat = 14
    
    public init(systemName: String, size: CGFloat = 28, iconSize: CGFloat = 14) {
        self.systemName = systemName
        self.size = size
        self.iconSize = iconSize
    }
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Gold gradient for the ring stroke
    // Light mode: uses richer goldBase→goldDark (avoids bright goldLight that washes out on white)
    private var ringGradient: LinearGradient {
        isDark
            ? LinearGradient(
                colors: [
                    BrandColors.goldLight.opacity(0.85),
                    BrandColors.goldBase.opacity(0.65),
                    BrandColors.goldDark.opacity(0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            : LinearGradient(
                colors: [
                    BrandColors.goldBase.opacity(0.80),
                    BrandColors.goldDark.opacity(0.65)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
    }
    
    // Icon gradient — light mode uses deep bronze tones for strong contrast on white
    private var iconGradient: LinearGradient {
        isDark
            ? LinearGradient(
                colors: [BrandColors.goldLight, BrandColors.goldBase, BrandColors.goldDark.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            : LinearGradient(
                colors: [BrandColors.goldBase, BrandColors.goldDark, BrandColors.goldDark.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
    }
    
    // Background fill — light mode: warm ivory with gold tint for depth
    private var backgroundFill: some ShapeStyle {
        isDark
            ? LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    BrandColors.goldBase.opacity(0.12),
                    BrandColors.goldDark.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            : LinearGradient(
                colors: [
                    BrandColors.goldBase.opacity(0.10),
                    BrandColors.goldDark.opacity(0.06),
                    BrandColors.goldDark.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
    }

    // Accent for glow/shadow — goldBase in dark, goldDark (bronze) in light for contrast
    private var glowAccent: Color {
        isDark ? BrandColors.goldBase : BrandColors.goldDark
    }
    
    public var body: some View {
        ZStack {
            // ── Layer 1: Radial glow fill (matches beacon/glass button depth) ──
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            glowAccent.opacity(isDark ? 0.18 : 0.14),
                            glowAccent.opacity(isDark ? 0.06 : 0.04),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )
            
            // ── Layer 2: Base gradient fill ──
            Circle()
                .fill(backgroundFill)
            
            // ── Layer 3: Top-highlight glass shine ──
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDark ? 0.15 : 0.40),
                            Color.white.opacity(isDark ? 0.03 : 0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            
            // ── Layer 4: Gold gradient ring stroke ──
            Circle()
                .stroke(ringGradient, lineWidth: isDark ? 1.4 : 1.3)
            
            // ── Layer 5: Luminous icon with gradient + glow ──
            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(iconGradient)
        }
        .frame(width: size, height: size)
        // Gold glow — uses bronze accent in light mode for visibility
        // Depth shadow — warm-tinted in light mode (no cold gray)
        .accessibilityHidden(true)
    }
}

// MARK: - Small variant (for tighter spaces)
public struct GoldHeaderGlyphSmall: View {
    public let systemName: String
    public var size: CGFloat = 24
    public var iconSize: CGFloat = 12

    public init(systemName: String, size: CGFloat = 24, iconSize: CGFloat = 12) {
        self.systemName = systemName
        self.size = size
        self.iconSize = iconSize
    }

    public var body: some View {
        GoldHeaderGlyph(systemName: systemName, size: size, iconSize: iconSize)
    }
}

// MARK: - Compact variant (for card headers where space is tight)
public struct GoldHeaderGlyphCompact: View {
    public let systemName: String
    public var size: CGFloat = 22
    public var iconSize: CGFloat = 11

    public init(systemName: String, size: CGFloat = 22, iconSize: CGFloat = 11) {
        self.systemName = systemName
        self.size = size
        self.iconSize = iconSize
    }

    public var body: some View {
        GoldHeaderGlyph(systemName: systemName, size: size, iconSize: iconSize)
    }
}

// MARK: - Preview
#Preview("Gold Header Icons") {
    VStack(spacing: 24) {
        // Section headers preview
        VStack(alignment: .leading, spacing: 16) {
            Text("Section Headers")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "eye.fill")
                Text("Watchlist")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "globe")
                Text("Market Stats")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "gauge.with.dots.needle.50percent")
                Text("Market Sentiment")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "square.grid.2x2")
                Text("Market Heat Map")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "chart.line.uptrend.xyaxis")
                Text("Market Movers")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "calendar.badge.clock")
                Text("Events & Catalysts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "newspaper.fill")
                Text("Crypto News")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "building.columns.fill")
                Text("Exchange Prices")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            HStack(spacing: 8) {
                GoldHeaderGlyph(systemName: "clock.arrow.circlepath")
                Text("Recent Transactions")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        
        Divider()
        
        // Small variant
        VStack(alignment: .leading, spacing: 12) {
            Text("Small Variant")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                GoldHeaderGlyphSmall(systemName: "chart.bar.fill")
                Text("Compact Header")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
    .padding(20)
    .background(Color(white: 0.08))
    .preferredColorScheme(.dark)
}
