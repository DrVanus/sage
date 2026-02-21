//
//  UserAvatarView.swift
//  CryptoSage
//
//  Reusable avatar component that displays either a preset icon
//  or user initials with deterministic gradient colors.
//

import SwiftUI

// MARK: - User Avatar View

/// A versatile avatar view that displays either a preset icon or user initials
public struct UserAvatarView: View {
    let username: String
    let avatarPresetId: String?
    let size: CGFloat
    var isVerified: Bool = false
    var showRing: Bool = false
    var ringColor: Color = .yellow
    
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        username: String,
        avatarPresetId: String? = nil,
        size: CGFloat = 42,
        isVerified: Bool = false,
        showRing: Bool = false,
        ringColor: Color = .yellow
    ) {
        self.username = username
        self.avatarPresetId = avatarPresetId
        self.size = size
        self.isVerified = isVerified
        self.showRing = showRing
        self.ringColor = ringColor
    }
    
    public var body: some View {
        ZStack {
            // Main avatar circle
            avatarContent
                .frame(width: size, height: size)
                .clipShape(Circle())
                // Light-mode definition: border prevents dark gradient
                // avatars from looking like opaque blobs on white backgrounds
                .overlay(
                    Circle()
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.08)
                                : Color.black.opacity(hasDarkGradient ? 0.18 : 0.10),
                            lineWidth: colorScheme == .dark ? 0.5 : (hasDarkGradient ? 1.5 : 1.0)
                        )
                )
                // Soft shadow gives depth against light backgrounds
            
            // Optional ring for verified/special users
            if showRing || isVerified {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [ringColor, ringColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: ringWidth
                    )
                    .frame(width: size + ringWidth * 2, height: size + ringWidth * 2)
            }
            
            // Verified badge
            if isVerified {
                verifiedBadge
                    .offset(x: size * 0.35, y: size * 0.35)
            }
        }
    }
    
    // MARK: - Avatar Content
    
    @ViewBuilder
    private var avatarContent: some View {
        if let presetId = avatarPresetId,
           let preset = AvatarCatalog.avatar(withId: presetId) {
            // Preset avatar
            presetAvatarView(preset)
        } else {
            // Initials avatar
            initialsAvatarView
        }
    }
    
    // MARK: - Preset Avatar
    
    private func presetAvatarView(_ preset: PresetAvatar) -> some View {
        ZStack {
            // Background gradient
            preset.gradient
            
            // Light-mode glass highlight — subtle top shine to lift dark gradients
            if colorScheme == .light {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.06),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            
            // Icon: asset image or SF Symbol
            if let assetName = preset.assetImageName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.62, height: size * 0.62)
                    .clipShape(Circle())
            } else {
                Image(systemName: preset.iconName)
                    .font(.system(size: AvatarDisplayHelper.iconSize(for: size), weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Initials Avatar
    
    private var initialsAvatarView: some View {
        ZStack {
            // Background gradient based on username hash
            AvatarGradientGenerator.gradient(for: username)
            
            // Initials text — lighter shadow in light mode
            Text(AvatarDisplayHelper.initials(from: username))
                .font(.system(
                    size: AvatarDisplayHelper.initialsFontSize(for: size),
                    weight: .bold,
                    design: .rounded
                ))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Verified Badge
    
    private var verifiedBadge: some View {
        ZStack {
            Circle()
                .fill(colorScheme == .dark ? Color.black : Color.white)
                .frame(width: badgeSize + 2, height: badgeSize + 2)
            
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: badgeSize, weight: .semibold))
                .foregroundColor(.green)
        }
    }
    
    // MARK: - Computed Properties
    
    private var ringWidth: CGFloat {
        switch size {
        case 0..<30: return 1.5
        case 30..<50: return 2
        case 50..<70: return 2.5
        default: return 3
        }
    }
    
    private var badgeSize: CGFloat {
        size * 0.35
    }
    
    /// Detects whether the current preset avatar has a dark gradient that
    /// needs extra border / shadow treatment in light mode.
    private var hasDarkGradient: Bool {
        guard let presetId = avatarPresetId,
              let preset = AvatarCatalog.avatar(withId: presetId) else {
            return false
        }
        // Check if the average luminance of the gradient colors is low
        return preset.gradientColors.allSatisfy { hex in
            Self.hexLuminance(hex) < 0.25
        }
    }
    
    /// Quick perceived luminance from a hex color string (0 = black, 1 = white).
    private static func hexLuminance(_ hex: String) -> Double {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}

// MARK: - Leaderboard Avatar View

/// Specialized avatar for leaderboard displays with rank-based styling
public struct LeaderboardAvatarView: View {
    let username: String
    let avatarPresetId: String?
    let rank: Int
    let size: CGFloat
    let tradingMode: LeaderboardEntryTradingMode
    
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        username: String,
        avatarPresetId: String? = nil,
        rank: Int,
        size: CGFloat = 42,
        tradingMode: LeaderboardEntryTradingMode = .paper
    ) {
        self.username = username
        self.avatarPresetId = avatarPresetId
        self.rank = rank
        self.size = size
        self.tradingMode = tradingMode
    }
    
    public var body: some View {
        UserAvatarView(
            username: username,
            avatarPresetId: avatarPresetId,
            size: size,
            isVerified: tradingMode == .portfolio,
            showRing: rank <= 3,
            ringColor: rankRingColor
        )
    }
    
    private var rankRingColor: Color {
        switch rank {
        case 1: return Color(hex: "#FFD700") // Gold
        case 2: return Color(hex: "#C0C0C0") // Silver
        case 3: return Color(hex: "#CD7F32") // Bronze
        default: return .clear
        }
    }
}

// MARK: - Compact Avatar View

/// Smaller avatar for inline displays (lists, rows, etc.)
public struct CompactAvatarView: View {
    let username: String
    let avatarPresetId: String?
    let size: CGFloat
    
    public init(
        username: String,
        avatarPresetId: String? = nil,
        size: CGFloat = 28
    ) {
        self.username = username
        self.avatarPresetId = avatarPresetId
        self.size = size
    }
    
    public var body: some View {
        UserAvatarView(
            username: username,
            avatarPresetId: avatarPresetId,
            size: size
        )
    }
}

// MARK: - Avatar with Name View

/// Avatar combined with username display
public struct AvatarWithNameView: View {
    let username: String
    let displayName: String?
    let avatarPresetId: String?
    let avatarSize: CGFloat
    let showAtSymbol: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        username: String,
        displayName: String? = nil,
        avatarPresetId: String? = nil,
        avatarSize: CGFloat = 36,
        showAtSymbol: Bool = true
    ) {
        self.username = username
        self.displayName = displayName
        self.avatarPresetId = avatarPresetId
        self.avatarSize = avatarSize
        self.showAtSymbol = showAtSymbol
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            UserAvatarView(
                username: username,
                avatarPresetId: avatarPresetId,
                size: avatarSize
            )
            
            VStack(alignment: .leading, spacing: 2) {
                if let displayName = displayName {
                    Text(displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text(showAtSymbol ? "@\(username)" : username)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Text(showAtSymbol ? "@\(username)" : username)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
        }
    }
}

// MARK: - Editable Avatar View

/// Avatar with edit overlay for profile editing
public struct EditableAvatarView: View {
    let username: String
    let avatarPresetId: String?
    let size: CGFloat
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        username: String,
        avatarPresetId: String? = nil,
        size: CGFloat = 80,
        onTap: @escaping () -> Void
    ) {
        self.username = username
        self.avatarPresetId = avatarPresetId
        self.size = size
        self.onTap = onTap
    }
    
    public var body: some View {
        Button(action: onTap) {
            ZStack {
                UserAvatarView(
                    username: username,
                    avatarPresetId: avatarPresetId,
                    size: size
                )
                
                // Edit overlay — lighter in light mode, warm tint instead of pure black
                Circle()
                    .fill(
                        colorScheme == .dark
                            ? Color.black.opacity(0.4)
                            : Color(red: 0.15, green: 0.12, blue: 0.08).opacity(0.35)
                    )
                    .frame(width: size, height: size)
                
                Image(systemName: "camera.fill")
                    .font(.system(size: size * 0.25, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Avatar Grid Item

/// Avatar item for selection grids
public struct AvatarGridItem: View {
    let preset: PresetAvatar
    let isSelected: Bool
    let size: CGFloat
    let onSelect: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        preset: PresetAvatar,
        isSelected: Bool = false,
        size: CGFloat = 60,
        onSelect: @escaping () -> Void
    ) {
        self.preset = preset
        self.isSelected = isSelected
        self.size = size
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                ZStack {
                    // Avatar
                    ZStack {
                        preset.gradient
                        
                        if let assetName = preset.assetImageName {
                            Image(assetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: size * 0.62, height: size * 0.62)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: preset.iconName)
                                .font(.system(size: size * 0.4, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    
                    // Selection ring
                    if isSelected {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: size + 6, height: size + 6)
                    }
                    
                    // Premium badge
                    if preset.isPremium {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color.black : Color.white)
                            )
                            .offset(x: size * 0.35, y: -size * 0.35)
                    }
                }
                
                // Name
                Text(preset.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Initials Avatar Option

/// Option to use initials in avatar picker
public struct InitialsAvatarOption: View {
    let username: String
    let isSelected: Bool
    let size: CGFloat
    let onSelect: () -> Void
    
    public init(
        username: String,
        isSelected: Bool = false,
        size: CGFloat = 60,
        onSelect: @escaping () -> Void
    ) {
        self.username = username
        self.isSelected = isSelected
        self.size = size
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                ZStack {
                    UserAvatarView(
                        username: username,
                        avatarPresetId: nil,
                        size: size
                    )
                    
                    if isSelected {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: size + 6, height: size + 6)
                    }
                }
                
                Text("Initials")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview Provider

#if DEBUG
struct UserAvatarView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Dark mode
            VStack(spacing: 20) {
                // Basic avatars
                HStack(spacing: 16) {
                    UserAvatarView(username: "SwiftFox", size: 42)
                    UserAvatarView(username: "BoldWhale", avatarPresetId: "crypto_bitcoin", size: 42)
                    UserAvatarView(username: "CryptoLion", avatarPresetId: "animal_lion", size: 42, isVerified: true)
                }
                
                // Leaderboard avatars
                HStack(spacing: 16) {
                    LeaderboardAvatarView(username: "FirstPlace", rank: 1, size: 56)
                    LeaderboardAvatarView(username: "SecondPlace", rank: 2, size: 56)
                    LeaderboardAvatarView(username: "ThirdPlace", rank: 3, size: 56)
                }
                
                // Dark preset avatars (test visibility)
                HStack(spacing: 16) {
                    UserAvatarView(username: "Vault", avatarPresetId: "crypto_vault", size: 42)
                    UserAvatarView(username: "Wolf", avatarPresetId: "animal_wolf", size: 42)
                    UserAvatarView(username: "Panther", avatarPresetId: "animal_panther", size: 42)
                }
                
                // Avatar with name
                AvatarWithNameView(
                    username: "diamond_hands",
                    displayName: "Diamond Hands",
                    avatarPresetId: "crypto_diamond",
                    avatarSize: 40
                )
                
                // Grid items
                HStack(spacing: 12) {
                    if let preset = AvatarCatalog.avatar(withId: "crypto_bitcoin") {
                        AvatarGridItem(preset: preset, isSelected: true, size: 50) {}
                    }
                    if let preset = AvatarCatalog.avatar(withId: "animal_whale") {
                        AvatarGridItem(preset: preset, isSelected: false, size: 50) {}
                    }
                    InitialsAvatarOption(username: "TestUser", isSelected: false, size: 50) {}
                }
            }
            .padding()
            .background(Color.black)
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark Mode")
            
            // Light mode
            VStack(spacing: 20) {
                // Basic avatars
                HStack(spacing: 16) {
                    UserAvatarView(username: "SwiftFox", size: 42)
                    UserAvatarView(username: "BoldWhale", avatarPresetId: "crypto_bitcoin", size: 42)
                    UserAvatarView(username: "CryptoLion", avatarPresetId: "animal_lion", size: 42, isVerified: true)
                }
                
                // Leaderboard avatars
                HStack(spacing: 16) {
                    LeaderboardAvatarView(username: "FirstPlace", rank: 1, size: 56)
                    LeaderboardAvatarView(username: "SecondPlace", rank: 2, size: 56)
                    LeaderboardAvatarView(username: "ThirdPlace", rank: 3, size: 56)
                }
                
                // Dark preset avatars (test visibility on light background)
                HStack(spacing: 16) {
                    UserAvatarView(username: "Vault", avatarPresetId: "crypto_vault", size: 42)
                    UserAvatarView(username: "Wolf", avatarPresetId: "animal_wolf", size: 42)
                    UserAvatarView(username: "Panther", avatarPresetId: "animal_panther", size: 42)
                }
                
                // Avatar with name
                AvatarWithNameView(
                    username: "diamond_hands",
                    displayName: "Diamond Hands",
                    avatarPresetId: "crypto_diamond",
                    avatarSize: 40
                )
                
                // Grid items
                HStack(spacing: 12) {
                    if let preset = AvatarCatalog.avatar(withId: "crypto_bitcoin") {
                        AvatarGridItem(preset: preset, isSelected: true, size: 50) {}
                    }
                    if let preset = AvatarCatalog.avatar(withId: "animal_whale") {
                        AvatarGridItem(preset: preset, isSelected: false, size: 50) {}
                    }
                    InitialsAvatarOption(username: "TestUser", isSelected: false, size: 50) {}
                }
            }
            .padding()
            .background(Color.white)
            .preferredColorScheme(.light)
            .previewDisplayName("Light Mode")
        }
    }
}
#endif
