import SwiftUI
import Foundation

public enum HomeSection: String, Hashable, CaseIterable {
    case portfolio
    case aiInsights
    case aiPredictions      // AI Price Predictions
    case stocksOverview     // Stocks & ETFs quick overview (when enabled)
    case stockWatchlist     // Stock watchlist (favorited stocks)
    case commoditiesOverview // Commodities & Precious Metals overview
    case watchlist
    case marketStats
    case sentiment
    case heatmap
    case promos
    case trending
    case arbitrage
    case whaleActivity      // Whale tracking preview
    case events
    case news
    case transactions
    case community          // Social Trading preview
    case communityLinks     // Discord, X, Telegram links
    case footer
}

// MARK: - Display Metadata

extension HomeSection {
    /// Human-readable title for the customization screen
    var displayName: String {
        switch self {
        case .portfolio:           return "Portfolio"
        case .aiInsights:          return "AI Insights"
        case .aiPredictions:       return "AI Price Predictions"
        case .stocksOverview:      return "Stock Market"
        case .stockWatchlist:      return "Stock Watchlist"
        case .commoditiesOverview: return "Commodities & Metals"
        case .watchlist:           return "Watchlist"
        case .marketStats:         return "Market Stats"
        case .sentiment:           return "Market Sentiment"
        case .heatmap:             return "Heat Map"
        case .promos:              return "Action Center"
        case .trending:            return "Market Movers"
        case .arbitrage:           return "Exchange Prices"
        case .whaleActivity:       return "Whale Activity"
        case .events:              return "Events & Catalysts"
        case .news:                return "News"
        case .transactions:        return "Recent Activity"
        case .community:           return "Community"
        case .communityLinks:      return "Community Links"
        case .footer:              return "Footer"
        }
    }
    
    /// SF Symbol icon name
    var icon: String {
        switch self {
        case .portfolio:           return "chart.pie.fill"
        case .aiInsights:          return "lightbulb.fill"
        case .aiPredictions:       return "chart.line.uptrend.xyaxis"
        case .stocksOverview:      return "building.2.fill"
        case .stockWatchlist:      return "star.square.on.square"
        case .commoditiesOverview: return "shippingbox.fill"
        case .watchlist:           return "eye.fill"
        case .marketStats:         return "globe"
        case .sentiment:           return "gauge.with.dots.needle.50percent"
        case .heatmap:             return "square.grid.2x2"
        case .promos:              return "shield.lefthalf.filled"
        case .trending:            return "chart.line.uptrend.xyaxis"
        case .arbitrage:           return "building.columns.fill"
        case .whaleActivity:       return "water.waves"
        case .events:              return "calendar.badge.clock"
        case .news:                return "newspaper.fill"
        case .transactions:        return "clock.arrow.circlepath"
        case .community:           return "bubble.left.and.bubble.right.fill"
        case .communityLinks:      return "link"
        case .footer:              return "doc.text"
        }
    }
    
    /// Short description for the customization row
    var sectionDescription: String {
        switch self {
        case .portfolio:           return "Balance, holdings, and performance chart"
        case .aiInsights:          return "Personalized AI-powered analysis and tips"
        case .aiPredictions:       return "AI-powered price forecasts with confidence levels"
        case .stocksOverview:      return "Stock market overview and top movers"
        case .stockWatchlist:      return "Your favorited stocks to track"
        case .commoditiesOverview: return "Gold, silver, platinum and other commodities"
        case .watchlist:           return "Your favorite coins and quick access"
        case .marketStats:         return "Detailed market stats (also on Market tab)"
        case .sentiment:           return "Fear & Greed index and market mood"
        case .heatmap:             return "Visual market performance overview"
        case .promos:              return "Risk scan, alerts, and quick actions"
        case .trending:            return "Trending, top gainers and top losers"
        case .arbitrage:           return "Compare prices across major exchanges"
        case .whaleActivity:       return "Large transactions and whale movements"
        case .events:              return "Upcoming crypto events and launches"
        case .news:                return "Latest cryptocurrency news"
        case .transactions:        return "Your recent transactions and trades"
        case .community:           return "Social trading and community insights"
        case .communityLinks:      return "Discord, X, Telegram links"
        case .footer:              return "App footer"
        }
    }
    
    /// Accent color for the icon circle in the customization screen
    var accentColor: Color {
        // Gold (#D4AF37) for brand-accent sections; matches BrandColors.goldBase
        let gold = Color(red: 212/255, green: 175/255, blue: 55/255)
        switch self {
        case .portfolio:           return gold
        case .aiInsights:          return .purple
        case .aiPredictions:       return gold
        case .stocksOverview:      return .blue
        case .stockWatchlist:      return .blue
        case .commoditiesOverview: return .yellow
        case .watchlist:           return gold
        case .marketStats:         return .blue
        case .sentiment:           return .orange
        case .heatmap:             return .green
        case .promos:              return gold
        case .trending:            return .red
        case .arbitrage:           return .cyan
        case .whaleActivity:       return .indigo
        case .events:              return .mint
        case .news:                return .teal
        case .transactions:        return .gray
        case .community:           return .pink
        case .communityLinks:      return .blue
        case .footer:              return .gray
        }
    }
}

public struct FeatureFlags {
    public var arbitrageEnabled: Bool = true
    
    public init(arbitrageEnabled: Bool = true) {
        self.arbitrageEnabled = arbitrageEnabled
    }
}

public struct HomeContext {
    public var hasWatchlistItems: Bool
    public var featureFlags: FeatureFlags
    
    public init(hasWatchlistItems: Bool, featureFlags: FeatureFlags) {
        self.hasWatchlistItems = hasWatchlistItems
        self.featureFlags = featureFlags
    }
}

// MARK: - Section Visibility Preferences

public struct HomeSectionPreferences {
    private static let defaults = UserDefaults.standard
    
    public static var showPortfolio: Bool {
        defaults.object(forKey: "Home.showPortfolio") as? Bool ?? true
    }
    
    public static var showWatchlist: Bool {
        defaults.object(forKey: "Home.showWatchlist") as? Bool ?? true
    }
    
    public static var showMarketStats: Bool {
        // Default to false - Market Stats now displays on the Market page header
        defaults.object(forKey: "Home.showMarketStats") as? Bool ?? false
    }
    
    public static var showSentiment: Bool {
        defaults.object(forKey: "Home.showSentiment") as? Bool ?? true
    }
    
    public static var showHeatmap: Bool {
        defaults.object(forKey: "Home.showHeatmap") as? Bool ?? true
    }
    
    public static var showTrending: Bool {
        defaults.object(forKey: "Home.showTrending") as? Bool ?? true
    }
    
    public static var showArbitrage: Bool {
        defaults.object(forKey: "Home.showArbitrage") as? Bool ?? true
    }
    
    public static var showEvents: Bool {
        defaults.object(forKey: "Home.showEvents") as? Bool ?? true
    }
    
    public static var showNews: Bool {
        defaults.object(forKey: "Home.showNews") as? Bool ?? true
    }
    
    public static var showAIInsights: Bool {
        defaults.object(forKey: "Home.showAIInsights") as? Bool ?? true
    }
    
    public static var showAIPredictions: Bool {
        defaults.object(forKey: "Home.showAIPredictions") as? Bool ?? true
    }
    
    public static var showCommunity: Bool {
        defaults.object(forKey: "Home.showCommunity") as? Bool ?? true
    }
    
    public static var showTransactions: Bool {
        defaults.object(forKey: "Home.showTransactions") as? Bool ?? true
    }
    
    public static var showPromos: Bool {
        defaults.object(forKey: "Home.showPromos") as? Bool ?? true
    }
    
    public static var showStocksOverview: Bool {
        // Show independently from portfolio asset toggles so users can always enable this section.
        defaults.object(forKey: "Home.showStocksOverview") as? Bool ?? true
    }
    
    public static var showStockWatchlist: Bool {
        // Show stock watchlist if enabled (visible when user has favorited stocks)
        let stocksEnabled = defaults.object(forKey: "showStocksInPortfolio") as? Bool ?? false
        return stocksEnabled && (defaults.object(forKey: "Home.showStockWatchlist") as? Bool ?? true)
    }
    
    public static var showCommoditiesOverview: Bool {
        // Show commodities section by default (gold, silver, oil, etc.)
        defaults.object(forKey: "Home.showCommoditiesOverview") as? Bool ?? true
    }
}

public struct HomeSectionPreferencesExtended {
    private static let defaults = UserDefaults.standard
    
    public static var showWhaleActivity: Bool {
        defaults.object(forKey: "Home.showWhaleActivity") as? Bool ?? true
    }
}

// MARK: - Section Order Manager

public final class HomeSectionOrderManager {
    public static let shared = HomeSectionOrderManager()
    private let orderKey = "Home.sectionOrder"
    private let versionKey = "Home.sectionOrderVersion"
    
    private init() {}
    
    /// Default order for the customizable sections (matches original priority ranking).
    /// These appear in the customization screen and can be reordered + toggled.
    public static let defaultOrder: [HomeSection] = [
        // Core experience
        .portfolio,
        .aiInsights,
        .aiPredictions,
        
        // Watchlist & market overview
        .watchlist,
        .trending,
        .sentiment,
        .heatmap,
        
        // Timely information
        .news,
        .events,
        
        // Additional assets
        .stocksOverview,
        .commoditiesOverview,
        
        // Specialized features
        .whaleActivity,
        .arbitrage,
        .marketStats,
        
        // Engagement & utility
        .promos,
        .transactions,
        .community
    ]
    
    /// Sections always pinned at the bottom (not shown in customization UI)
    public static let fixedBottomSections: [HomeSection] = [.communityLinks, .footer]
    
    /// Get the current section order (custom or default)
    public func getOrder() -> [HomeSection] {
        guard let saved = UserDefaults.standard.stringArray(forKey: orderKey) else {
            return Self.defaultOrder
        }
        
        var sections = saved.compactMap { HomeSection(rawValue: $0) }
        
        // Future-proofing: add any new sections not in saved order
        let existing = Set(sections)
        for section in Self.defaultOrder where !existing.contains(section) {
            sections.append(section)
        }
        
        // Remove sections that are no longer in the customizable list
        let validSet = Set(Self.defaultOrder)
        sections = sections.filter { validSet.contains($0) }
        
        return sections
    }
    
    /// Save a custom section order and bump version to notify observers
    public func saveOrder(_ sections: [HomeSection]) {
        let rawValues = sections.map(\.rawValue)
        UserDefaults.standard.set(rawValues, forKey: orderKey)
        bumpVersion()
    }
    
    /// Reset to default order and bump version
    public func resetOrder() {
        UserDefaults.standard.removeObject(forKey: orderKey)
        bumpVersion()
    }
    
    private func bumpVersion() {
        let current = UserDefaults.standard.integer(forKey: versionKey)
        UserDefaults.standard.set(current + 1, forKey: versionKey)
    }
}

// MARK: - Section Layout

public struct HomeSectionsLayout {
    // Legacy static order (kept for reference; custom order takes precedence)
    public static let order: [HomeSection] = [
        // Core experience - what users care about most
        .portfolio,
        .aiInsights,
        // .aiPredictions - now integrated into Watchlist section as CTA button
        .watchlist,
        .trending,          // Gainers/Losers are immediately actionable
        .sentiment,         // Market sentiment context
        .heatmap,           // Visual market overview
        
        // Timely information - news and events that matter
        .news,              // Breaking news can trigger immediate decisions
        .events,            // Upcoming catalysts to prepare for
        
        // Secondary assets
        .stocksOverview,    // Stocks & ETFs holdings overview
        .stockWatchlist,    // Stock watchlist (favorited stocks to track)
        .commoditiesOverview, // Commodities & Precious Metals (gold, silver, oil, etc.)
        
        // Specialized features - lower priority for most users
        .whaleActivity,     // Advanced signals for power users
        .arbitrage,         // Niche: most users don't trade across exchanges
        .marketStats,       // Detailed stats (off by default)
        
        // Engagement and footer
        .promos,
        .transactions,
        .community,
        .communityLinks,
        .footer
    ]
    
    public static func visibleSections(context: HomeContext) -> [HomeSection] {
        // Use custom order (from drag-and-drop reorder) instead of hardcoded order
        let customOrder = HomeSectionOrderManager.shared.getOrder()
        
        // Filter to only visible sections based on user preferences
        var result = customOrder.filter { section in
            isVisible(section, context: context)
        }
        
        // Insert auto-managed sections not currently exposed in customization UI.
        if HomeSectionPreferences.showStockWatchlist {
            let insertIdx: Int
            if result.contains(.stockWatchlist) {
                insertIdx = result.endIndex
            } else if let stocksIdx = result.firstIndex(of: .stocksOverview) {
                insertIdx = stocksIdx + 1
            } else if let commoditiesIdx = result.firstIndex(of: .commoditiesOverview) {
                insertIdx = commoditiesIdx + 1
            } else {
                insertIdx = result.endIndex
            }
            result.insert(.stockWatchlist, at: insertIdx)
        }
        
        // Append fixed-bottom sections
        result.append(contentsOf: HomeSectionOrderManager.fixedBottomSections)
        
        return result
    }
    
    private static func isVisible(_ section: HomeSection, context: HomeContext) -> Bool {
        switch section {
        case .portfolio:
            return HomeSectionPreferences.showPortfolio
        case .aiInsights:
            return HomeSectionPreferences.showAIInsights
        case .aiPredictions:
            // AI Predictions now integrated into Watchlist section - never show as standalone
            return false
        case .stocksOverview:
            return HomeSectionPreferences.showStocksOverview
        case .stockWatchlist:
            return HomeSectionPreferences.showStockWatchlist
        case .commoditiesOverview:
            return HomeSectionPreferences.showCommoditiesOverview
        case .watchlist:
            return HomeSectionPreferences.showWatchlist
        case .marketStats:
            return HomeSectionPreferences.showMarketStats
        case .sentiment:
            return HomeSectionPreferences.showSentiment
        case .heatmap:
            return HomeSectionPreferences.showHeatmap
        case .trending:
            return HomeSectionPreferences.showTrending
        case .arbitrage:
            return context.featureFlags.arbitrageEnabled && HomeSectionPreferences.showArbitrage
        case .whaleActivity:
            return HomeSectionPreferencesExtended.showWhaleActivity
        case .events:
            return HomeSectionPreferences.showEvents
        case .news:
            return HomeSectionPreferences.showNews
        case .promos:
            return HomeSectionPreferences.showPromos
        case .transactions:
            return HomeSectionPreferences.showTransactions
        case .community:
            return HomeSectionPreferences.showCommunity
        case .communityLinks, .footer:
            return true
        }
    }
}
