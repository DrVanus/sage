//
//  TradingPairPreferencesService.swift
//  CryptoSage
//
//  Shared service for managing trading pair preferences (favorites, recents).
//  Provides centralized access for both UI and AI context building.
//

import Foundation
import Combine

// MARK: - Lightweight Trading Pair Info for Persistence

/// Lightweight model for storing trading pair preferences
/// Used for persistence and AI context (separate from full TradingPair model)
public struct TradingPairInfo: Codable, Hashable, Identifiable {
    public let id: String
    public let baseSymbol: String
    public let quoteSymbol: String
    public let exchangeID: String
    public let exchangeName: String
    
    public init(
        baseSymbol: String,
        quoteSymbol: String,
        exchangeID: String,
        exchangeName: String
    ) {
        self.id = "\(exchangeID)-\(baseSymbol)-\(quoteSymbol)"
        self.baseSymbol = baseSymbol
        self.quoteSymbol = quoteSymbol
        self.exchangeID = exchangeID
        self.exchangeName = exchangeName
    }
    
    /// Create from a TradingPair
    init(from pair: TradingPair) {
        self.id = pair.id
        self.baseSymbol = pair.baseSymbol
        self.quoteSymbol = pair.quoteSymbol
        self.exchangeID = pair.exchangeID
        self.exchangeName = pair.exchangeName
    }
    
    public var displayPair: String {
        "\(baseSymbol)/\(quoteSymbol)"
    }
    
    public var fullDescription: String {
        "\(baseSymbol)/\(quoteSymbol) on \(exchangeName)"
    }
}

// MARK: - Trading Pair Preferences Service

/// Singleton service for managing trading pair preferences
/// Provides centralized access for both UI and AI context building
@MainActor
public final class TradingPairPreferencesService: ObservableObject {
    public static let shared = TradingPairPreferencesService()
    
    // MARK: - Storage Keys (matches TradingPairPickerViewModel for compatibility)
    
    private static let favoritePairsKey = "trading_favorite_pairs"
    private static let recentPairsKey = "trading_recent_pairs"
    private static let recentPairsInfoKey = "trading_recent_pairs_info"
    
    // MARK: - Published Properties
    
    /// Set of favorite pair IDs (e.g., "binance-BTC-USDT")
    @Published public private(set) var favoritePairIDs: Set<String> = []
    
    /// Recent trading pairs with full info for context
    @Published public private(set) var recentPairs: [TradingPairInfo] = []
    
    // MARK: - Initialization
    
    private init() {
        loadFavorites()
        loadRecentPairs()
    }
    
    // MARK: - Favorites Management
    
    /// Check if a pair ID is favorited
    public func isFavorite(_ pairID: String) -> Bool {
        favoritePairIDs.contains(pairID)
    }
    
    /// Check if a TradingPair is favorited
    func isFavorite(_ pair: TradingPair) -> Bool {
        favoritePairIDs.contains(pair.id)
    }
    
    /// Toggle favorite status for a pair
    public func toggleFavorite(_ pairID: String) {
        if favoritePairIDs.contains(pairID) {
            favoritePairIDs.remove(pairID)
        } else {
            favoritePairIDs.insert(pairID)
        }
        saveFavorites()
    }
    
    /// Toggle favorite status for a TradingPair
    func toggleFavorite(_ pair: TradingPair) {
        toggleFavorite(pair.id)
    }
    
    /// Add a pair to favorites
    public func addFavorite(_ pairID: String) {
        favoritePairIDs.insert(pairID)
        saveFavorites()
    }
    
    /// Remove a pair from favorites
    public func removeFavorite(_ pairID: String) {
        favoritePairIDs.remove(pairID)
        saveFavorites()
    }
    
    /// Get all favorite pair IDs
    public func getAllFavoriteIDs() -> Set<String> {
        favoritePairIDs
    }
    
    // MARK: - Recent Pairs Management
    
    /// Add a pair to recent history (also stores full info for AI context)
    func addToRecent(_ pair: TradingPair) {
        let info = TradingPairInfo(from: pair)
        addToRecent(info)
    }
    
    /// Add pair info to recent history
    public func addToRecent(_ info: TradingPairInfo) {
        // Remove if already exists (to move to front)
        recentPairs.removeAll { $0.id == info.id }
        
        // Add to front
        recentPairs.insert(info, at: 0)
        
        // Keep only last 10
        if recentPairs.count > 10 {
            recentPairs = Array(recentPairs.prefix(10))
        }
        
        saveRecentPairs()
    }
    
    /// Get recent pairs (limited)
    public func getRecentPairs(limit: Int = 5) -> [TradingPairInfo] {
        Array(recentPairs.prefix(limit))
    }
    
    /// Clear all recent pairs
    public func clearRecentPairs() {
        recentPairs = []
        saveRecentPairs()
    }
    
    // MARK: - AI Context Helpers
    
    /// Get favorite pairs parsed into TradingPairInfo (from IDs)
    /// Returns pairs with basic info extracted from ID format: "exchangeID-BASE-QUOTE"
    public func getFavoritePairsInfo() -> [TradingPairInfo] {
        favoritePairIDs.compactMap { id -> TradingPairInfo? in
            let parts = id.split(separator: "-")
            guard parts.count >= 3 else { return nil }
            
            let exchangeID = String(parts[0])
            let baseSymbol = String(parts[1])
            let quoteSymbol = String(parts[2])
            
            return TradingPairInfo(
                baseSymbol: baseSymbol,
                quoteSymbol: quoteSymbol,
                exchangeID: exchangeID,
                exchangeName: exchangeDisplayName(exchangeID)
            )
        }
    }
    
    /// Get preferred exchanges based on favorites and recents
    /// Returns exchanges sorted by usage frequency
    public func getPreferredExchanges() -> [String] {
        var exchangeCounts: [String: Int] = [:]
        
        // Count from favorites
        for info in getFavoritePairsInfo() {
            exchangeCounts[info.exchangeID, default: 0] += 2 // Weight favorites higher
        }
        
        // Count from recents
        for info in recentPairs {
            exchangeCounts[info.exchangeID, default: 0] += 1
        }
        
        // Sort by count descending
        return exchangeCounts
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }
    
    /// Get preferred quote currency based on usage
    /// Returns "USD" or "USDT" based on what user trades most
    public func getPreferredQuoteCurrency() -> String {
        var quoteCounts: [String: Int] = [:]
        
        // Count from favorites
        for info in getFavoritePairsInfo() {
            quoteCounts[info.quoteSymbol, default: 0] += 2
        }
        
        // Count from recents
        for info in recentPairs {
            quoteCounts[info.quoteSymbol, default: 0] += 1
        }
        
        // Find most common quote
        let sorted = quoteCounts.sorted { $0.value > $1.value }
        return sorted.first?.key ?? "USDT"
    }
    
    /// Get most traded base assets based on favorites and recents
    public func getMostTradedAssets() -> [String] {
        var assetCounts: [String: Int] = [:]
        
        // Count from favorites
        for info in getFavoritePairsInfo() {
            assetCounts[info.baseSymbol, default: 0] += 2
        }
        
        // Count from recents
        for info in recentPairs {
            assetCounts[info.baseSymbol, default: 0] += 1
        }
        
        // Sort by count descending, take top 10
        return assetCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
    }
    
    /// Build a summary for AI context
    public func buildAIContextSummary() -> String? {
        let favorites = getFavoritePairsInfo()
        let recents = getRecentPairs(limit: 5)
        
        // Return nil if no data
        guard !favorites.isEmpty || !recents.isEmpty else {
            return nil
        }
        
        var lines: [String] = ["TRADING PAIR PREFERENCES:"]
        
        // Favorite pairs
        if !favorites.isEmpty {
            let favoritesList = favorites.prefix(5).map { $0.fullDescription }.joined(separator: ", ")
            lines.append("- Favorite Pairs: \(favoritesList)")
            if favorites.count > 5 {
                lines.append("  (and \(favorites.count - 5) more)")
            }
        }
        
        // Recent pairs
        if !recents.isEmpty {
            let recentsList = recents.map { $0.displayPair }.joined(separator: ", ")
            lines.append("- Recent Pairs: \(recentsList)")
        }
        
        // Preferred quote currency
        let preferredQuote = getPreferredQuoteCurrency()
        lines.append("- Preferred Quote Currency: \(preferredQuote)")
        
        // Preferred exchanges
        let preferredExchanges = getPreferredExchanges()
        if !preferredExchanges.isEmpty {
            let exchangesList = preferredExchanges.prefix(3).map { exchangeDisplayName($0) }.joined(separator: ", ")
            lines.append("- Preferred Exchanges: \(exchangesList)")
        }
        
        // Most traded assets
        let tradedAssets = getMostTradedAssets()
        if !tradedAssets.isEmpty {
            let assetsList = tradedAssets.prefix(5).joined(separator: ", ")
            lines.append("- Frequently Traded: \(assetsList)")
        }
        
        // Add usage note for AI
        lines.append("")
        lines.append("When recommending trades:")
        lines.append("- Prefer user's favorite pairs when suggesting trades")
        lines.append("- Use their preferred exchange (\(preferredExchanges.first.map { exchangeDisplayName($0) } ?? "Binance"))")
        lines.append("- Default to \(preferredQuote) as quote currency unless they specify otherwise")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Persistence
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: Self.favoritePairsKey),
           let ids = try? JSONDecoder().decode(Set<String>.self, from: data) {
            favoritePairIDs = ids
        }
    }
    
    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favoritePairIDs) {
            UserDefaults.standard.set(data, forKey: Self.favoritePairsKey)
        }
    }
    
    private func loadRecentPairs() {
        // Try loading from new info key first
        if let data = UserDefaults.standard.data(forKey: Self.recentPairsInfoKey),
           let pairs = try? JSONDecoder().decode([TradingPairInfo].self, from: data) {
            recentPairs = pairs
            return
        }
        
        // Fallback: try loading from legacy TradingPair key and convert
        if let data = UserDefaults.standard.data(forKey: Self.recentPairsKey),
           let pairs = try? JSONDecoder().decode([TradingPair].self, from: data) {
            recentPairs = pairs.map { TradingPairInfo(from: $0) }
            // Save to new format
            saveRecentPairs()
        }
    }
    
    private func saveRecentPairs() {
        if let data = try? JSONEncoder().encode(recentPairs) {
            UserDefaults.standard.set(data, forKey: Self.recentPairsInfoKey)
        }
    }
    
    // MARK: - Helpers
    
    private func exchangeDisplayName(_ id: String) -> String {
        switch id.lowercased() {
        case "binance": return "Binance"
        case "binance_us": return "Binance US"
        case "coinbase": return "Coinbase"
        case "kraken": return "Kraken"
        case "kucoin": return "KuCoin"
        default: return id.capitalized
        }
    }
}
