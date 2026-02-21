//
//  ProfileAvatarMini.swift
//  CryptoSage
//
//  A premium profile avatar with glassmorphic styling and gold ring accent.
//

import SwiftUI

struct ProfileAvatarMini: View {
    let size: CGFloat
    
    // Auth state - observe for real-time updates
    @ObservedObject private var authManager = AuthenticationManager.shared
    
    // Observe ProfileSyncService so the avatar re-renders when cloud data is restored
    @ObservedObject private var profileSync = ProfileSyncService.shared
    
    // User profile data (synced by AuthenticationManager on sign-in)
    @AppStorage("profile.displayName") private var displayName: String = ""
    
    // Social username — synced by ProfileSyncManager when social profile is created
    @AppStorage("profile.username") private var socialUsername: String = ""
    
    // Avatar preset — synced from social profile when user picks an icon
    @AppStorage("profile.avatarPresetId") private var avatarPresetId: String = ""
    
    // Shimmer animation state
    @State private var shimmerPhase: CGFloat = -1
    // Breathing glow — matches the beacon's "living" quality
    @State private var glowPulse: Double = 0.10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    
    /// Check if user has a real profile (signed in, has display name, or has social profile)
    private var hasUserProfile: Bool {
        // Check if signed in via auth
        if let authName = authManager.currentUser?.displayName, !authName.isEmpty {
            return true
        }
        // Check if user has manually set a display name
        if !displayName.isEmpty {
            return true
        }
        // Check if user has a social profile (username synced from social service)
        return !socialUsername.isEmpty
    }
    
    /// Resolved avatar preset (if user has chosen one)
    private var resolvedPreset: PresetAvatar? {
        guard !avatarPresetId.isEmpty else { return nil }
        return AvatarCatalog.avatar(withId: avatarPresetId)
    }
    
    /// Effective display name - auth data takes priority, then display name, then social username
    private var effectiveDisplayName: String {
        if let authName = authManager.currentUser?.displayName, !authName.isEmpty {
            return authName
        }
        if !displayName.isEmpty {
            return displayName
        }
        // Fall back to social username for initials
        return socialUsername
    }
    
    private var initials: String {
        let components = effectiveDisplayName.split(separator: " ")
        let firstInitial = components.first?.first.map(String.init) ?? ""
        let lastInitial = components.count > 1 ? components.last?.first.map(String.init) ?? "" : ""
        let result = (firstInitial + lastInitial).uppercased()
        return result.isEmpty ? "CS" : result
    }
    
    private var ringWidth: CGFloat { size * 0.065 }
    private var innerSize: CGFloat { size - (ringWidth * 2) }
    private var fontSize: CGFloat { size * 0.38 }
    
    // Adaptive inner background colors
    private var innerBackgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [Color(white: 0.18), Color(white: 0.12)]
        } else {
            // Light mode: warm cream/ivory gradient with subtle depth
            // More neutral base helps gold initials pop while still feeling premium
            return [
                Color(red: 0.98, green: 0.96, blue: 0.92),      // Warm ivory top
                Color(red: 0.94, green: 0.90, blue: 0.84)       // Subtle cream bottom
            ]
        }
    }
    
    // Adaptive glass highlight opacity
    private var glassHighlightOpacities: (top: Double, mid: Double) {
        if colorScheme == .dark {
            return (0.15, 0.05)
        } else {
            // Light mode: subtle highlight for premium metallic feel
            return (0.35, 0.12)
        }
    }
    
    // Adaptive shadow color - warm gold tint in light mode, no black
    private var outerShadowColor: Color {
        colorScheme == .dark 
            ? Color.black.opacity(0.3) 
            : BrandColors.goldDark.opacity(0.15)  // Gold-tinted shadow, no black
    }
    
    // Adaptive inner border for definition
    private var innerBorderColor: Color {
        colorScheme == .dark ? Color.clear : BrandColors.goldBase.opacity(0.45)
    }
    
    // Shimmer blend mode - overlay works great on dark, plusLighter for light
    private var shimmerBlendMode: BlendMode {
        colorScheme == .dark ? .overlay : .plusLighter
    }
    
    // Inner gold glow opacity - creates warm reflected light from the ring
    private var innerGlowOpacity: Double {
        colorScheme == .dark ? 0.3 : 0.35
    }
    
    // Inner shadow for depth in light mode - uses gold tint instead of brown/black
    private var innerShadowOpacity: Double {
        colorScheme == .dark ? 0.0 : 0.12
    }
    
    var body: some View {
        ZStack {
            // Outer gold ring with gradient
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            BrandColors.goldLight,
                            BrandColors.goldBase,
                            BrandColors.goldDark,
                            BrandColors.goldBase,
                            BrandColors.goldLight
                        ],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    )
                )
                .frame(width: size, height: size)
            
            // Shimmer overlay on ring - blend mode adapts to color scheme
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.4),
                            .clear
                        ],
                        startPoint: UnitPoint(x: shimmerPhase - 0.3, y: shimmerPhase - 0.3),
                        endPoint: UnitPoint(x: shimmerPhase + 0.3, y: shimmerPhase + 0.3)
                    )
                )
                .frame(width: size, height: size)
            
            // Inner glass background - adaptive to light/dark mode
            Circle()
                .fill(
                    LinearGradient(
                        colors: innerBackgroundGradientColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: innerSize, height: innerSize)
                .overlay(
                    // Subtle gold-tinted inner border
                    Circle()
                        .stroke(innerBorderColor, lineWidth: colorScheme == .dark ? 0.5 : 1.0)
                )
            
            // Glass highlight arc at top - creates glassy shine like a pearl
            Circle()
                .trim(from: 0.0, to: 0.5)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(glassHighlightOpacities.top),
                            Color.white.opacity(glassHighlightOpacities.mid),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .frame(width: innerSize, height: innerSize)
                .rotationEffect(.degrees(180))
            
            // Subtle inner edge shadow for depth (light mode only)
            // Uses gold tint instead of black/brown for cohesive premium look
            if colorScheme == .light {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                BrandColors.goldDark.opacity(innerShadowOpacity),
                                Color.clear,
                                Color.clear,
                                BrandColors.goldLight.opacity(0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2
                    )
                    .frame(width: innerSize - 2, height: innerSize - 2)
            }
            
            // Inner glow from gold ring - subtle reflection effect
            Circle()
                .stroke(
                    RadialGradient(
                        colors: [BrandColors.goldBase.opacity(innerGlowOpacity * 0.7), .clear],
                        center: .center,
                        startRadius: innerSize * 0.42,
                        endRadius: innerSize * 0.5
                    ),
                    lineWidth: innerSize * 0.08
                )
                .frame(width: innerSize, height: innerSize)
            
            // Content: preset icon > initials > sparkles placeholder
            if let preset = resolvedPreset {
                // User has chosen a preset avatar — show its icon with gradient background
                ZStack {
                    // Preset gradient fills the inner circle
                    Circle()
                        .fill(preset.gradient)
                        .frame(width: innerSize, height: innerSize)
                    
                    // Preset icon or asset image — lighter shadow in light mode
                    if let assetName = preset.assetImageName {
                        Image(assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: innerSize * 0.62, height: innerSize * 0.62)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: preset.iconName)
                            .font(.system(size: fontSize * 0.9, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            } else if hasUserProfile {
                // Has profile but no preset — show initials
                Text(initials)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [BrandColors.goldLight, BrandColors.goldBase]
                                : [
                                    Color(red: 0.612, green: 0.475, blue: 0.118),
                                    Color(red: 0.478, green: 0.357, blue: 0.039)
                                  ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                // No profile — sparkles placeholder
                Image(systemName: "sparkles")
                    .font(.system(size: fontSize * 0.95, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [BrandColors.goldLight, BrandColors.goldBase]
                                : [
                                    Color(red: 0.612, green: 0.475, blue: 0.118),
                                    Color(red: 0.478, green: 0.357, blue: 0.039)
                                  ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        // Subtle outer stroke for definition in light mode
        .overlay(
            Circle()
                .stroke(
                    colorScheme == .dark
                        ? Color.clear
                        : BrandColors.goldDark.opacity(0.15),
                    lineWidth: 0.5
                )
                .frame(width: size, height: size)
        )
        // Breathing gold glow — pulsing outer glow that matches the beacon's living quality
        // Light mode: uses goldDark (bronze) so the glow is visible against white backgrounds
        // Soft drop shadow for depth — warm-tinted in light mode
        .onAppear {
            guard !reduceMotion else { return }
            // Shimmer sweep on the gold ring
            withAnimation(
                .easeInOut(duration: 2.5)
                .repeatForever(autoreverses: false)
                .delay(1)
            ) {
                shimmerPhase = 2
            }
            // Breathing glow — synced cadence with beacon (2.8s cycle)
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                glowPulse = colorScheme == .dark ? 0.35 : 0.18
            }
        }
    }
}

#Preview("Dark Mode") {
    VStack(spacing: 20) {
        ProfileAvatarMini(size: 38)
        ProfileAvatarMini(size: 48)
        ProfileAvatarMini(size: 56)
    }
    .padding()
    .background(DS.Adaptive.background)
    .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    VStack(spacing: 20) {
        ProfileAvatarMini(size: 38)
        ProfileAvatarMini(size: 48)
        ProfileAvatarMini(size: 56)
    }
    .padding()
    .background(DS.Adaptive.background)
    .preferredColorScheme(.light)
}
