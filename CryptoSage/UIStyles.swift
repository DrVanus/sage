import SwiftUI

// Adaptive shadow color for gold buttons - no shadow in light mode for flat appearance
private let adaptiveGoldShadow = Color(UIColor { tc in
    tc.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.25) : UIColor.clear
})

// Button styles
struct CSGoldButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        
        configuration.label
            .font(.caption)
            .foregroundColor(BrandColors.ctaTextColor(isDark: isDark))
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                // Silver gradient in light mode, gold-to-orange in dark mode
                LinearGradient(
                    gradient: Gradient(colors: isDark
                        ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                        : [BrandColors.silverLight, BrandColors.silverBase, BrandColors.silverDark]
                    ),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(), value: configuration.isPressed)
    }
}

struct CSPrimaryCTAButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var height: CGFloat = 36
    var cornerRadius: CGFloat = 12
    
    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(BrandColors.ctaTextColor(isDark: isDark))
            .frame(height: height)
            .padding(.horizontal, 14)
            .background(
                // Silver gradient in light mode, gold-to-orange in dark mode
                LinearGradient(
                    gradient: Gradient(colors: isDark
                        ? [Color(red: 1.0, green: 0.92, blue: 0.3), Color.orange]
                        : [BrandColors.silverLight, BrandColors.silverBase, BrandColors.silverDark]
                    ),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct CSPlainCTAButtonStyle: ButtonStyle {
    var height: CGFloat = 34
    var cornerRadius: CGFloat = 10
    var horizontalPadding: CGFloat = 12
    var font: Font = .subheadline.weight(.semibold)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(DS.Adaptive.textPrimary)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.Adaptive.chipBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.Adaptive.strokeStrong, lineWidth: 1)
                    .opacity(configuration.isPressed ? 0.8 : 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

struct CSNeonCTAStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var accent: Color = .csGoldSolid
    var height: CGFloat = 38
    var cornerRadius: CGFloat = 14
    var horizontalPadding: CGFloat = 16
    var font: Font = .callout.weight(.semibold)

    private func neonBackground(isDark: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [accent.opacity(0.95), Color.orange]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            // Only show stroke in dark mode
            if isDark {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white, lineWidth: 0.5)
                    .opacity(0.2)
            }
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(.black)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(neonBackground(isDark: colorScheme == .dark))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

struct CSGoldPillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var height: CGFloat = 28
    var horizontalPadding: CGFloat = 10
    var font: Font = .caption.weight(.semibold)

    // Use silver gradient in light mode, gold in dark mode
    @ViewBuilder
    private var pillBackground: some View {
        if colorScheme == .dark {
            Capsule().fill(BrandColors.goldHorizontal)
        } else {
            Capsule().fill(BrandColors.silverHorizontal)
        }
    }

    // Subtle highlight stroke - silver tint in light mode
    @ViewBuilder
    private var pillOverlay: some View {
        if colorScheme == .dark {
            ZStack {
                Capsule().stroke(Color.white.opacity(0.45), lineWidth: 0.8)
                Capsule().stroke(Color.black.opacity(0.25), lineWidth: 0.6)
            }
        } else {
            // Subtle silver border in light mode for definition
            Capsule().stroke(BrandColors.silverDark.opacity(0.4), lineWidth: 0.8)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(BrandColors.ctaTextColor(isDark: colorScheme == .dark))
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(pillBackground)
            .overlay(pillOverlay)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

/// Lightweight text link button style for section header actions.
/// Uses gold color in dark mode and a subtle gray in light mode.
/// Much cleaner than pill buttons for secondary navigation actions.
struct CSTextLinkButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var font: Font = .system(size: 12, weight: .semibold)
    var chevronSize: CGFloat = 10
    
    private var linkColor: Color {
        colorScheme == .dark
            ? BrandColors.goldBase
            : Color(red: 0.35, green: 0.35, blue: 0.4) // Subtle gray for light mode
    }
    
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.label
                .font(font)
            Image(systemName: "chevron.right")
                .font(.system(size: chevronSize, weight: .semibold))
        }
        .foregroundStyle(linkColor)
        .opacity(configuration.isPressed ? 0.6 : 1.0)
        .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Modern outlined button style for primary CTAs.
/// Uses neutral/accent styling - clean and professional.
struct CSAccentButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var height: CGFloat = 34
    var horizontalPadding: CGFloat = 14
    var cornerRadius: CGFloat = 10
    
    private var isDark: Bool { colorScheme == .dark }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.Adaptive.textPrimary)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.Adaptive.chipBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// Glass card background and breathing glow modifier
struct GlassCardBackground: View {
    var cornerRadius: CGFloat = 14
    var accent: Color? = nil

    private func accentGradient(_ c: Color) -> LinearGradient {
        LinearGradient(
            colors: [c.opacity(0.35), c.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
            if let accentColor = accent {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(accentGradient(accentColor))
                    .opacity(0.14)
            }
        }
    }
}

struct BreathingGlow: ViewModifier {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var breathe = false
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .scaleEffect(1.0)
        } else {
            content
                // Reduced glow intensity in light mode for cleaner appearance
                .scaleEffect(breathe ? 1.01 : 1.0)
                // PERFORMANCE FIX v21: Scroll-aware breathing (pauses during scroll)
                .scrollAwarePulse(active: $breathe, duration: 1.6, delay: 0.3)
        }
    }
}

extension View {
    func breathingGlow(color: Color) -> some View { self.modifier(BreathingGlow(color: color)) }
}
