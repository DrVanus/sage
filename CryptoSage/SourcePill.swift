import SwiftUI

/// Small source badge used across news lists.
/// Features source-specific accent colors for major publishers.
struct SourcePill: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    
    /// Normalizes verbose source names to short, clean display names.
    static func displayName(_ source: String) -> String {
        var name = source.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Explicit brand mappings for consistent styling (check these FIRST)
        let brandMappings: [String: String] = [
            // Investing.com variations
            "investing.com crypto opinion and analysis": "Investing.com",
            "investing.com crypto": "Investing.com",
            "investing.com": "Investing.com",
            // Forbes variations
            "forbes digital assets": "Forbes",
            "forbes crypto": "Forbes",
            // CryptoCoin.News
            "cryptocoin.news": "CryptoCoin",
            // Standard mappings
            "amb crypto": "AMBCrypto",
            "ambcrypto": "AMBCrypto",
            "crypto slate": "CryptoSlate",
            "cryptoslate": "CryptoSlate",
            "crypto potato": "CryptoPotato",
            "cryptopotato": "CryptoPotato",
            "daily hodl": "DailyHodl",
            "the daily hodl": "DailyHodl",
            "be in crypto": "BeInCrypto",
            "beincrypto": "BeInCrypto",
            "coin gape": "CoinGape",
            "coingape": "CoinGape",
            "bitcoin magazine": "Bitcoin Magazine",
            "crypto briefing": "CryptoBriefing",
            "u.today": "U.Today",
            "newsbtc": "NewsBTC",
            "bitcoinist": "Bitcoinist",
            "cryptopolitan": "Cryptopolitan",
            "finbold": "Finbold",
            "zycrypto": "ZyCrypto",
            "bitcoin world": "BitcoinWorld",
            "bitcoinworld": "BitcoinWorld"
        ]
        
        // Check exact match first
        if let mapped = brandMappings[name.lowercased()] {
            return mapped
        }
        
        // Check if name contains any known brand (for partial matches)
        for (key, value) in brandMappings {
            if name.lowercased().contains(key) {
                return value
            }
        }
        
        // Strip everything after colon (e.g. "CoinDesk: Bitcoin, Ethereum...")
        if let colonRange = name.range(of: ":") {
            name = String(name[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        
        // Remove common suffixes (order matters - check longer suffixes first)
        let suffixes = [" Crypto Opinion and Analysis", " Opinion and Analysis", " Digital Assets", ".com News", ".com", " News", " RSS", " Feed", " Crypto"]
        for suffix in suffixes {
            if name.lowercased().hasSuffix(suffix.lowercased()) {
                name = String(name.dropLast(suffix.count))
                break // Only remove one suffix
            }
        }
        
        // Final length check - truncate extremely long names
        if name.count > 20 {
            // Try to find a natural break point (space, dot)
            if let spaceIndex = name.prefix(18).lastIndex(of: " ") {
                name = String(name[..<spaceIndex])
            } else if let dotIndex = name.prefix(18).lastIndex(of: ".") {
                name = String(name[...dotIndex])
            } else {
                name = String(name.prefix(16)) + "..."
            }
        }
        
        return name.isEmpty ? source : name
    }
    
    /// Source-specific brand colors for major publishers
    private static let sourceColors: [String: (dark: Color, light: Color)] = [
        // Major crypto publishers
        "coindesk": (Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.15, green: 0.4, blue: 0.75)),       // Blue
        "cointelegraph": (Color(red: 0.2, green: 0.75, blue: 0.5), Color(red: 0.1, green: 0.55, blue: 0.35)), // Green
        "the block": (Color(red: 0.55, green: 0.4, blue: 0.9), Color(red: 0.4, green: 0.25, blue: 0.7)),     // Purple
        "theblock": (Color(red: 0.55, green: 0.4, blue: 0.9), Color(red: 0.4, green: 0.25, blue: 0.7)),
        "decrypt": (Color(red: 0.95, green: 0.5, blue: 0.2), Color(red: 0.75, green: 0.35, blue: 0.1)),      // Orange
        "blockworks": (Color(red: 0.3, green: 0.65, blue: 0.95), Color(red: 0.2, green: 0.5, blue: 0.75)),   // Light Blue
        "bitcoin magazine": (Color(red: 0.95, green: 0.6, blue: 0.15), Color(red: 0.8, green: 0.45, blue: 0.05)), // Bitcoin Orange
        "bitcoinmagazine": (Color(red: 0.95, green: 0.6, blue: 0.15), Color(red: 0.8, green: 0.45, blue: 0.05)),
        
        // Financial news
        "reuters": (Color(red: 0.95, green: 0.45, blue: 0.2), Color(red: 0.8, green: 0.3, blue: 0.1)),       // Reuters Orange
        "bloomberg": (Color(red: 0.2, green: 0.55, blue: 0.85), Color(red: 0.1, green: 0.4, blue: 0.7)),     // Bloomberg Blue
        "cnbc": (Color(red: 0.0, green: 0.55, blue: 0.8), Color(red: 0.0, green: 0.4, blue: 0.6)),           // CNBC Blue
        "forbes": (Color(red: 0.7, green: 0.1, blue: 0.15), Color(red: 0.55, green: 0.05, blue: 0.1)),       // Forbes Red
        "investing.com": (Color(red: 0.95, green: 0.65, blue: 0.1), Color(red: 0.8, green: 0.5, blue: 0.05)), // Investing Orange
        "investing": (Color(red: 0.95, green: 0.65, blue: 0.1), Color(red: 0.8, green: 0.5, blue: 0.05)),
        
        // Other crypto sources
        "cryptoslate": (Color(red: 0.25, green: 0.6, blue: 0.85), Color(red: 0.15, green: 0.45, blue: 0.7)), // Slate Blue
        "beincrypto": (Color(red: 0.95, green: 0.75, blue: 0.2), Color(red: 0.75, green: 0.55, blue: 0.1)),  // Gold
        "ambcrypto": (Color(red: 0.4, green: 0.7, blue: 0.5), Color(red: 0.25, green: 0.55, blue: 0.35)),    // Muted Green
        "messari": (Color(red: 0.3, green: 0.3, blue: 0.85), Color(red: 0.2, green: 0.2, blue: 0.65)),       // Deep Blue
        "bankless": (Color(red: 0.85, green: 0.35, blue: 0.5), Color(red: 0.65, green: 0.2, blue: 0.35)),    // Pink
        "coingape": (Color(red: 0.6, green: 0.45, blue: 0.85), Color(red: 0.45, green: 0.3, blue: 0.65)),    // Lavender
        "cryptocoin": (Color(red: 0.3, green: 0.7, blue: 0.6), Color(red: 0.2, green: 0.55, blue: 0.45)),    // Teal
        "u.today": (Color(red: 0.2, green: 0.6, blue: 0.9), Color(red: 0.1, green: 0.45, blue: 0.7)),        // U.Today Blue
        "newsbtc": (Color(red: 0.95, green: 0.5, blue: 0.3), Color(red: 0.75, green: 0.35, blue: 0.15)),     // NewsBTC Orange
    ]
    
    /// Get the accent color for a source (if available)
    private func accentColor(for source: String) -> Color? {
        let normalized = source.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try exact match first
        if let colors = Self.sourceColors[normalized] {
            return colorScheme == .dark ? colors.dark : colors.light
        }
        
        // Try partial match for variations
        for (key, colors) in Self.sourceColors {
            if normalized.contains(key) || key.contains(normalized) {
                return colorScheme == .dark ? colors.dark : colors.light
            }
        }
        
        return nil
    }
    
    // Adaptive colors for light/dark mode
    private var textColor: Color {
        if let accent = accentColor(for: text) {
            // Use white text on colored background in dark mode
            return colorScheme == .dark ? .white : accent
        }
        return colorScheme == .dark ? Color.white.opacity(0.9) : DS.Adaptive.textPrimary.opacity(0.85)
    }
    
    private var backgroundColor: Color {
        if let accent = accentColor(for: text) {
            return colorScheme == .dark ? accent.opacity(0.25) : accent.opacity(0.12)
        }
        return colorScheme == .dark ? Color.white.opacity(0.10) : DS.Adaptive.chipBackground
    }
    
    private var strokeColor: Color {
        if let accent = accentColor(for: text) {
            return colorScheme == .dark ? accent.opacity(0.45) : accent.opacity(0.35)
        }
        return colorScheme == .dark ? Color.white.opacity(0.18) : DS.Adaptive.strokeStrong
    }
    
    var body: some View {
        Text(Self.displayName(text))
            .font(.caption2.weight(.bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(backgroundColor)
            )
            .overlay(
                Capsule().stroke(strokeColor, lineWidth: 1)
            )
    }
}
