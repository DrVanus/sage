//
//  AvatarSystem.swift
//  CryptoSage
//
//  Professional avatar system with preset icons and initials support.
//  Users can choose from curated crypto-themed, animal, and abstract icons.
//

import Foundation
import SwiftUI

// MARK: - Avatar Type

/// Represents the type of avatar a user has selected
public enum AvatarType: Codable, Equatable {
    case initials
    case preset(id: String)
    
    // Custom coding for enum with associated value
    private enum CodingKeys: String, CodingKey {
        case type, presetId
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        if type == "preset", let presetId = try container.decodeIfPresent(String.self, forKey: .presetId) {
            self = .preset(id: presetId)
        } else {
            self = .initials
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .initials:
            try container.encode("initials", forKey: .type)
        case .preset(let id):
            try container.encode("preset", forKey: .type)
            try container.encode(id, forKey: .presetId)
        }
    }
}

// MARK: - Avatar Category

/// Categories for organizing preset avatars
public enum AvatarCategory: String, Codable, CaseIterable, Identifiable {
    case crypto = "Crypto"
    case animals = "Animals"
    case abstract = "Abstract"
    case special = "Special"
    case developer = "Developer"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .crypto: return "bitcoinsign.circle.fill"
        case .animals: return "hare.fill"
        case .abstract: return "hexagon.fill"
        case .special: return "star.fill"
        case .developer: return "hammer.fill"
        }
    }
    
    public var description: String {
        switch self {
        case .crypto: return "Cryptocurrency themed icons"
        case .animals: return "Trading spirit animals"
        case .abstract: return "Geometric patterns"
        case .special: return "Exclusive designs"
        case .developer: return "Exclusive developer-only icons"
        }
    }
}

// MARK: - Preset Avatar

/// Represents a preset avatar option users can select
public struct PresetAvatar: Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let iconName: String  // SF Symbol name or custom asset
    public let category: AvatarCategory
    public let gradientColors: [String]  // Hex colors for gradient
    public let isPremium: Bool
    public let isDeveloperOnly: Bool
    /// Optional asset-catalog image name (used instead of SF Symbol when set)
    public let assetImageName: String?
    
    public init(
        id: String,
        name: String,
        iconName: String,
        category: AvatarCategory,
        gradientColors: [String],
        isPremium: Bool = false,
        isDeveloperOnly: Bool = false,
        assetImageName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.category = category
        self.gradientColors = gradientColors
        self.isPremium = isPremium
        self.isDeveloperOnly = isDeveloperOnly
        self.assetImageName = assetImageName
    }
    
    /// Whether this avatar uses an asset image instead of an SF Symbol
    public var usesAssetImage: Bool { assetImageName != nil }
    
    /// Convert hex colors to SwiftUI Colors
    public var colors: [Color] {
        gradientColors.map { Color(hex: $0) }
    }
    
    /// Primary color for the avatar
    public var primaryColor: Color {
        colors.first ?? .blue
    }
    
    /// Gradient for the avatar background
    public var gradient: LinearGradient {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Avatar Catalog

/// Central catalog of all available preset avatars
public struct AvatarCatalog {
    
    // MARK: - Crypto Icons
    
    public static let cryptoAvatars: [PresetAvatar] = [
        PresetAvatar(id: "crypto_bitcoin", name: "Bitcoin", iconName: "bitcoinsign.circle.fill", category: .crypto, gradientColors: ["#F7931A", "#FFAB40"]),
        PresetAvatar(id: "crypto_ethereum", name: "Ethereum", iconName: "diamond.fill", category: .crypto, gradientColors: ["#627EEA", "#A4B3F7"]),
        PresetAvatar(id: "crypto_rocket", name: "To The Moon", iconName: "airplane", category: .crypto, gradientColors: ["#FF6B6B", "#FFE66D"]),
        PresetAvatar(id: "crypto_moon", name: "Moon", iconName: "moon.fill", category: .crypto, gradientColors: ["#2C3E50", "#4CA1AF"]),
        PresetAvatar(id: "crypto_diamond", name: "Diamond Hands", iconName: "diamond.fill", category: .crypto, gradientColors: ["#00D2FF", "#3A7BD5"]),
        PresetAvatar(id: "crypto_chart", name: "Chart Master", iconName: "chart.line.uptrend.xyaxis", category: .crypto, gradientColors: ["#11998E", "#38EF7D"]),
        PresetAvatar(id: "crypto_lightning", name: "Lightning", iconName: "bolt.fill", category: .crypto, gradientColors: ["#FFD700", "#FFA500"]),
        PresetAvatar(id: "crypto_shield", name: "HODL Shield", iconName: "shield.fill", category: .crypto, gradientColors: ["#667EEA", "#764BA2"]),
        PresetAvatar(id: "crypto_stack", name: "Stacker", iconName: "square.stack.3d.up.fill", category: .crypto, gradientColors: ["#F093FB", "#F5576C"]),
        PresetAvatar(id: "crypto_globe", name: "Global Trader", iconName: "globe.americas.fill", category: .crypto, gradientColors: ["#4FACFE", "#00F2FE"]),
        // New crypto icons
        PresetAvatar(id: "crypto_vault", name: "Vault", iconName: "lock.shield.fill", category: .crypto, gradientColors: ["#0F2027", "#2C5364"]),
        PresetAvatar(id: "crypto_candlestick", name: "Candlestick", iconName: "chart.bar.fill", category: .crypto, gradientColors: ["#43B692", "#0BAB64"]),
        PresetAvatar(id: "crypto_whale_alert", name: "Whale Alert", iconName: "bell.badge.fill", category: .crypto, gradientColors: ["#1CB5E0", "#000046"]),
        PresetAvatar(id: "crypto_defi", name: "DeFi", iconName: "link.circle.fill", category: .crypto, gradientColors: ["#7F00FF", "#E100FF"]),
        PresetAvatar(id: "crypto_miner", name: "Miner", iconName: "cpu.fill", category: .crypto, gradientColors: ["#373B44", "#4286F4"]),
        PresetAvatar(id: "crypto_wallet", name: "Wallet", iconName: "creditcard.fill", category: .crypto, gradientColors: ["#C04848", "#480048"]),
    ]
    
    // MARK: - Animal Icons
    
    public static let animalAvatars: [PresetAvatar] = [
        PresetAvatar(id: "animal_bull", name: "Bull", iconName: "arrow.up.right.circle.fill", category: .animals, gradientColors: ["#00C853", "#69F0AE"]),
        PresetAvatar(id: "animal_bear", name: "Bear", iconName: "arrow.down.right.circle.fill", category: .animals, gradientColors: ["#FF5252", "#FF867C"]),
        PresetAvatar(id: "animal_whale", name: "Whale", iconName: "water.waves", category: .animals, gradientColors: ["#2193B0", "#6DD5ED"]),
        PresetAvatar(id: "animal_fox", name: "Fox", iconName: "hare.fill", category: .animals, gradientColors: ["#FF6B35", "#F7C59F"]),
        PresetAvatar(id: "animal_wolf", name: "Wolf", iconName: "moon.stars.fill", category: .animals, gradientColors: ["#4B6CB7", "#182848"]),
        PresetAvatar(id: "animal_eagle", name: "Eagle", iconName: "bird.fill", category: .animals, gradientColors: ["#8E2DE2", "#4A00E0"]),
        PresetAvatar(id: "animal_shark", name: "Shark", iconName: "tropicalstorm", category: .animals, gradientColors: ["#536976", "#292E49"]),
        PresetAvatar(id: "animal_lion", name: "Lion", iconName: "crown.fill", category: .animals, gradientColors: ["#FFB347", "#FFCC33"]),
        PresetAvatar(id: "animal_owl", name: "Owl", iconName: "eye.fill", category: .animals, gradientColors: ["#614385", "#516395"]),
        PresetAvatar(id: "animal_hawk", name: "Hawk", iconName: "scope", category: .animals, gradientColors: ["#C33764", "#1D2671"]),
        PresetAvatar(id: "animal_tiger", name: "Tiger", iconName: "flame.fill", category: .animals, gradientColors: ["#F46B45", "#EEA849"]),
        PresetAvatar(id: "animal_dragon", name: "Dragon", iconName: "sparkles", category: .animals, gradientColors: ["#8E0E00", "#1F1C18"]),
        // New animal icons
        PresetAvatar(id: "animal_cobra", name: "Cobra", iconName: "bolt.horizontal.fill", category: .animals, gradientColors: ["#134E5E", "#71B280"]),
        PresetAvatar(id: "animal_phoenix", name: "Phoenix", iconName: "wind", category: .animals, gradientColors: ["#ED4264", "#FFEDBC"]),
        PresetAvatar(id: "animal_panther", name: "Panther", iconName: "pawprint.fill", category: .animals, gradientColors: ["#232526", "#414345"]),
        PresetAvatar(id: "animal_dolphin", name: "Dolphin", iconName: "drop.fill", category: .animals, gradientColors: ["#00B4DB", "#0083B0"]),
        PresetAvatar(id: "animal_scorpion", name: "Scorpion", iconName: "ant.fill", category: .animals, gradientColors: ["#870000", "#190A05"]),
        PresetAvatar(id: "animal_raven", name: "Raven", iconName: "moonphase.waxing.crescent", category: .animals, gradientColors: ["#1F1C2C", "#928DAB"]),
    ]
    
    // MARK: - Abstract Icons
    
    public static let abstractAvatars: [PresetAvatar] = [
        PresetAvatar(id: "abstract_hexagon", name: "Hexagon", iconName: "hexagon.fill", category: .abstract, gradientColors: ["#6441A5", "#2A0845"]),
        PresetAvatar(id: "abstract_crystal", name: "Crystal", iconName: "seal.fill", category: .abstract, gradientColors: ["#00C6FB", "#005BEA"]),
        PresetAvatar(id: "abstract_prism", name: "Prism", iconName: "triangle.fill", category: .abstract, gradientColors: ["#A8E063", "#56AB2F"]),
        PresetAvatar(id: "abstract_cube", name: "Cube", iconName: "cube.fill", category: .abstract, gradientColors: ["#DA22FF", "#9733EE"]),
        PresetAvatar(id: "abstract_sphere", name: "Sphere", iconName: "circle.fill", category: .abstract, gradientColors: ["#FF512F", "#DD2476"]),
        PresetAvatar(id: "abstract_spiral", name: "Spiral", iconName: "hurricane", category: .abstract, gradientColors: ["#43CEA2", "#185A9D"]),
        PresetAvatar(id: "abstract_star", name: "Star", iconName: "star.fill", category: .abstract, gradientColors: ["#F7971E", "#FFD200"]),
        PresetAvatar(id: "abstract_wave", name: "Wave", iconName: "waveform.path", category: .abstract, gradientColors: ["#4776E6", "#8E54E9"]),
        PresetAvatar(id: "abstract_atom", name: "Atom", iconName: "atom", category: .abstract, gradientColors: ["#00B4DB", "#0083B0"]),
        PresetAvatar(id: "abstract_infinity", name: "Infinity", iconName: "infinity", category: .abstract, gradientColors: ["#ED213A", "#93291E"]),
        // New abstract icons
        PresetAvatar(id: "abstract_circuit", name: "Circuit", iconName: "circle.grid.cross.fill", category: .abstract, gradientColors: ["#0F2027", "#203A43"]),
        PresetAvatar(id: "abstract_pulse", name: "Pulse", iconName: "waveform.path.ecg", category: .abstract, gradientColors: ["#FC5C7D", "#6A82FB"]),
        PresetAvatar(id: "abstract_matrix", name: "Matrix", iconName: "square.grid.3x3.fill", category: .abstract, gradientColors: ["#0A1A0A", "#0F9B0F"]),
        PresetAvatar(id: "abstract_compass", name: "Compass", iconName: "safari.fill", category: .abstract, gradientColors: ["#C9D6FF", "#E2E2E2"]),
        PresetAvatar(id: "abstract_shield", name: "Shield", iconName: "shield.checkered", category: .abstract, gradientColors: ["#141E30", "#243B55"]),
        PresetAvatar(id: "abstract_nova", name: "Nova", iconName: "sun.max.fill", category: .abstract, gradientColors: ["#FF5F6D", "#FFC371"]),
    ]
    
    // MARK: - Special Icons (Premium/Exclusive)
    
    public static let specialAvatars: [PresetAvatar] = [
        // Row 1 - Top tier premium avatars
        PresetAvatar(
            id: "special_crown",
            name: "Crown",
            iconName: "crown.fill",
            category: .special,
            gradientColors: ["#FFD700", "#B8860B"],
            isPremium: true
        ),
        PresetAvatar(
            id: "special_fire",
            name: "Fire",
            iconName: "flame.fill",
            category: .special,
            gradientColors: ["#FF416C", "#FF4B2B"],
            isPremium: true
        ),
        PresetAvatar(
            id: "special_aurora",
            name: "Aurora",
            iconName: "sparkles",
            category: .special,
            gradientColors: ["#00F260", "#0575E6"],
            isPremium: true
        ),
        PresetAvatar(
            id: "special_nebula",
            name: "Nebula",
            iconName: "staroflife.fill",
            category: .special,
            gradientColors: ["#8360C3", "#2EBF91"],
            isPremium: true
        ),
        PresetAvatar(
            id: "special_quantum",
            name: "Quantum",
            iconName: "waveform.circle.fill",
            category: .special,
            gradientColors: ["#000428", "#004E92"],
            isPremium: true
        ),
        // Row 2 - Achievement-style avatars
        PresetAvatar(
            id: "special_legend",
            name: "Legend",
            iconName: "trophy.fill",
            category: .special,
            gradientColors: ["#F9D423", "#FF4E50"],
            isPremium: true
        ),
        PresetAvatar(
            id: "special_master",
            name: "Master",
            iconName: "graduationcap.fill",
            category: .special,
            gradientColors: ["#5433FF", "#20BDFF"],
            isPremium: true
        ),
        PresetAvatar(
            id: "special_elite",
            name: "Elite",
            iconName: "bolt.shield.fill",
            category: .special,
            gradientColors: ["#C6426E", "#642B73"],
            isPremium: true
        ),
        // Row 3 - New premium avatars
        PresetAvatar(
            id: "special_diamond",
            name: "Diamond",
            iconName: "suit.diamond.fill",
            category: .special,
            gradientColors: ["#89CFF0", "#A8E6CF"],
            isPremium: true
        ),
        PresetAvatar(
            id: "special_phoenix",
            name: "Phoenix",
            iconName: "bird.fill",
            category: .special,
            gradientColors: ["#FF6B35", "#F7931E"],
            isPremium: true
        ),
        PresetAvatar(
            id: "special_galaxy",
            name: "Galaxy",
            iconName: "moon.stars.fill",
            category: .special,
            gradientColors: ["#1A1A2E", "#4A00E0"],
            isPremium: true
        ),
        PresetAvatar(
            id: "special_vortex",
            name: "Vortex",
            iconName: "hurricane",
            category: .special,
            gradientColors: ["#11998E", "#38EF7D"],
            isPremium: true
        ),
        // Row 4 - Ultra premium avatars
        PresetAvatar(
            id: "special_sage",
            name: "Sage",
            iconName: "brain.head.profile",
            category: .special,
            gradientColors: ["#667EEA", "#764BA2"],
            isPremium: true
        ),
        PresetAvatar(
            id: "special_titan",
            name: "Titan",
            iconName: "figure.stand",
            category: .special,
            gradientColors: ["#536976", "#292E49"],
            isPremium: true
        ),
        PresetAvatar(
            id: "special_oracle",
            name: "Oracle",
            iconName: "eye.circle.fill",
            category: .special,
            gradientColors: ["#F093FB", "#F5576C"],
            isPremium: true
        ),
        PresetAvatar(
            id: "special_apex",
            name: "Apex",
            iconName: "arrowtriangle.up.fill",
            category: .special,
            gradientColors: ["#E65C00", "#F9D423"],
            isPremium: true
        )
    ]
    
    // MARK: - Developer-Only Icons (Exclusive)
    
    public static let developerAvatars: [PresetAvatar] = [
        // Ultra-exclusive developer icons — only visible in Developer Mode
        PresetAvatar(
            id: "dev_architect", name: "Architect", iconName: "hammer.fill",
            category: .developer, gradientColors: ["#0F0C29", "#302B63"], isDeveloperOnly: true
        ),
        PresetAvatar(
            id: "dev_terminal", name: "Terminal", iconName: "terminal.fill",
            category: .developer, gradientColors: ["#0A0A0A", "#00FF41"], isDeveloperOnly: true
        ),
        PresetAvatar(
            id: "dev_code", name: "Code", iconName: "chevron.left.forwardslash.chevron.right",
            category: .developer, gradientColors: ["#1A1A2E", "#16213E"], isDeveloperOnly: true
        ),
        PresetAvatar(
            id: "dev_debugger", name: "Debugger", iconName: "ladybug.fill",
            category: .developer, gradientColors: ["#FF0000", "#8B0000"], isDeveloperOnly: true
        ),
        PresetAvatar(
            id: "dev_swift", name: "Swift", iconName: "swift",
            category: .developer, gradientColors: ["#F05138", "#FF6F43"], isDeveloperOnly: true
        ),
        PresetAvatar(
            id: "dev_server", name: "Server", iconName: "server.rack",
            category: .developer, gradientColors: ["#0F2027", "#2C5364"], isDeveloperOnly: true
        ),
        PresetAvatar(
            id: "dev_cipher", name: "Cipher", iconName: "lock.doc.fill",
            category: .developer, gradientColors: ["#1D976C", "#93F9B9"], isDeveloperOnly: true
        ),
        PresetAvatar(
            id: "dev_neural", name: "Neural Net", iconName: "brain",
            category: .developer, gradientColors: ["#8E2DE2", "#4A00E0"], isDeveloperOnly: true
        ),
        PresetAvatar(
            id: "dev_kernel", name: "Kernel", iconName: "memorychip.fill",
            category: .developer, gradientColors: ["#141E30", "#243B55"], isDeveloperOnly: true
        ),
        PresetAvatar(
            id: "dev_root", name: "Root", iconName: "person.badge.key.fill",
            category: .developer, gradientColors: ["#1C1C1E", "#545458"], isDeveloperOnly: true
        ),
        PresetAvatar(
            id: "dev_crypto_sage", name: "CryptoSage", iconName: "wand.and.stars",
            category: .developer, gradientColors: ["#C6A300", "#FFD700"], isDeveloperOnly: true
        ),
        PresetAvatar(
            id: "dev_genesis", name: "Genesis", iconName: "globe.badge.chevron.backward",
            category: .developer, gradientColors: ["#1A1A2E", "#C6A300"], isDeveloperOnly: true
        ),
        PresetAvatar(
            id: "dev_hypersage", name: "HyperSage", iconName: "sparkle",
            category: .developer, gradientColors: ["#1A1A1A", "#2C2C2E"],
            isDeveloperOnly: true, assetImageName: "LaunchLogo"
        ),
    ]
    
    // MARK: - All Avatars
    
    /// All available preset avatars (including developer-only — filter at display time)
    public static var allAvatars: [PresetAvatar] {
        cryptoAvatars + animalAvatars + abstractAvatars + specialAvatars + developerAvatars
    }
    
    /// Get avatars by category
    public static func avatars(for category: AvatarCategory) -> [PresetAvatar] {
        switch category {
        case .crypto: return cryptoAvatars
        case .animals: return animalAvatars
        case .abstract: return abstractAvatars
        case .special: return specialAvatars
        case .developer: return developerAvatars
        }
    }
    
    /// Find a specific avatar by ID (always resolves, even developer-only, so saved avatars display)
    public static func avatar(withId id: String) -> PresetAvatar? {
        allAvatars.first { $0.id == id }
    }
    
    /// Get non-premium avatars only
    public static var freeAvatars: [PresetAvatar] {
        allAvatars.filter { !$0.isPremium && !$0.isDeveloperOnly }
    }
    
    /// Get premium avatars only
    public static var premiumAvatars: [PresetAvatar] {
        allAvatars.filter { $0.isPremium }
    }
    
    /// Get developer-only avatars
    public static var developerOnlyAvatars: [PresetAvatar] {
        allAvatars.filter { $0.isDeveloperOnly }
    }
    
    /// Total count of avatars
    public static var totalCount: Int {
        allAvatars.count
    }
}

// MARK: - Avatar Gradient Generator

/// Generates deterministic gradient colors from a username hash
public struct AvatarGradientGenerator {
    
    /// Predefined gradient palettes for initials-based avatars
    private static let gradientPalettes: [[String]] = [
        ["#667EEA", "#764BA2"],  // Purple blend
        ["#F093FB", "#F5576C"],  // Pink blend
        ["#4FACFE", "#00F2FE"],  // Blue blend
        ["#43E97B", "#38F9D7"],  // Green blend
        ["#FA709A", "#FEE140"],  // Sunset blend
        ["#A8EDEA", "#FED6E3"],  // Soft pastel
        ["#FF9A9E", "#FECFEF"],  // Rose blend
        ["#A18CD1", "#FBC2EB"],  // Lavender blend
        ["#FFD89B", "#19547B"],  // Warm to cool
        ["#C6FFDD", "#FBD786"],  // Fresh blend
        ["#30CFD0", "#330867"],  // Teal to purple
        ["#FF758C", "#FF7EB3"],  // Pink gradient
        ["#6A11CB", "#2575FC"],  // Royal blue
        ["#F857A6", "#FF5858"],  // Hot pink
        ["#00B09B", "#96C93D"],  // Nature blend
        ["#FC466B", "#3F5EFB"],  // Vibrant mix
    ]
    
    /// Generate gradient colors based on username hash
    public static func gradientColors(for username: String) -> [Color] {
        let hash = username.hashValue
        let index = abs(hash) % gradientPalettes.count
        return gradientPalettes[index].map { Color(hex: $0) }
    }
    
    /// Generate a LinearGradient for a username
    public static func gradient(for username: String) -> LinearGradient {
        LinearGradient(
            colors: gradientColors(for: username),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Get primary color for a username
    public static func primaryColor(for username: String) -> Color {
        gradientColors(for: username).first ?? .blue
    }
}

// MARK: - Color Extension for Hex Support

extension Color {
    /// Initialize Color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    /// Convert Color to hex string
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX",
                      lroundf(r * 255),
                      lroundf(g * 255),
                      lroundf(b * 255))
    }
}

// MARK: - Avatar Display Helper

/// Helper struct for avatar display logic
public struct AvatarDisplayHelper {
    
    /// Get initials from a username or display name
    public static func initials(from name: String) -> String {
        let components = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        
        if components.count >= 2 {
            // Two words: use first letter of each
            let first = components[0].prefix(1).uppercased()
            let second = components[1].prefix(1).uppercased()
            return first + second
        } else if let firstComponent = components.first, firstComponent.count >= 2 {
            // Single word with 2+ chars: use first two letters
            return String(firstComponent.prefix(2)).uppercased()
        } else if let firstComponent = components.first {
            // Single short word: use what we have
            return firstComponent.uppercased()
        }
        
        // Fallback
        return "?"
    }
    
    /// Get appropriate font size for initials based on avatar size
    public static func initialsFontSize(for avatarSize: CGFloat) -> CGFloat {
        switch avatarSize {
        case 0..<30: return 10
        case 30..<45: return 13
        case 45..<60: return 16
        case 60..<80: return 20
        default: return 24
        }
    }
    
    /// Get appropriate icon size for preset avatars based on avatar size
    public static func iconSize(for avatarSize: CGFloat) -> CGFloat {
        return avatarSize * 0.5
    }
}
