# CryptoSage AI Trading App Architecture

> **Last Updated:** January 2026  
> **Platform:** iOS (SwiftUI, Swift 5.9+)  
> **Minimum iOS Version:** iOS 17.0+

---

## Table of Contents

1. [Overview](#overview)
2. [App Entry Point & Navigation](#app-entry-point--navigation)
3. [Core Architecture Patterns](#core-architecture-patterns)
4. [Module Structure](#module-structure)
5. [Data Layer](#data-layer)
6. [Services Layer](#services-layer)
7. [View Layer](#view-layer)
8. [State Management](#state-management)
9. [Key Data Models](#key-data-models)
10. [External Integrations](#external-integrations)
11. [File Organization](#file-organization)
12. [Important Singletons](#important-singletons)
13. [Design System](#design-system)
14. [Caching Strategy](#caching-strategy)
15. [AI Agent Guidelines](#ai-agent-guidelines)

---

## Overview

CryptoSage is an iOS cryptocurrency trading and portfolio management app featuring:

- **Real-time market data** from CoinGecko, Binance, and Coinbase
- **Portfolio tracking** with manual entries and exchange syncing
- **AI-powered insights** for trading recommendations
- **Technical analysis** with TradingView integration
- **Market sentiment** (Fear & Greed Index)
- **Heat maps** and market visualization
- **Crypto news** aggregation
- **Trading interface** with order book visualization
- **Watchlist** management with favorites

---

## App Entry Point & Navigation

### Entry Point
```
CryptoSage/CryptoSageAIApp.swift
```

The `@main` entry point is `CryptoSageAIApp` (not `CryptoSageApp.swift` which is a legacy placeholder).

### Tab Navigation Structure
```swift
enum CustomTab {
    case home      // HomeView - Dashboard with portfolio, watchlist, news
    case market    // MarketView - Full market data, heatmaps
    case trade     // TradeView - Trading interface
    case portfolio // PortfolioView - Holdings and transactions
    case ai        // AITabView - AI chat and insights
}
```

### Key Navigation Files
| File | Purpose |
|------|---------|
| `CryptoSageAIApp.swift` | App entry, environment injection, tab setup |
| `CustomTabBar.swift` | Custom bottom tab bar UI |
| `HomeView.swift` | Main dashboard with sections |
| `HomeSectionsLayout.swift` | Section ordering logic for HomeView |

---

## Core Architecture Patterns

### 1. MVVM (Model-View-ViewModel)
The app follows MVVM with SwiftUI. ViewModels are `@MainActor` marked and use `@Published` properties.

```
View (SwiftUI) → ViewModel (ObservableObject) → Services/Repository → Data Sources
```

### 2. Repository Pattern
Used for portfolio data to abstract data sources:
```
PortfolioViewModel → PortfolioRepository → ManualService / LiveService / PriceService
```

### 3. Singleton Services
Core services use shared singletons for global state:
- `MarketViewModel.shared`
- `LivePriceManager.shared`
- `CryptoAPIService.shared`
- `FavoritesManager.shared`
- `CacheManager.shared`

### 4. Combine Publishers
Reactive data flow using Combine for:
- Live price updates
- Portfolio holdings changes
- Market data polling

### 5. Swift Concurrency
Async/await with `@MainActor` for thread-safe UI updates:
```swift
@MainActor
final class MarketViewModel: ObservableObject {
    func loadAllData() async { ... }
}
```

---

## Module Structure

```
CryptoSage/
├── Core App
│   ├── CryptoSageAIApp.swift      # @main entry point
│   ├── AppSettings.swift           # User preferences
│   └── Theme.swift                 # App theming
│
├── Models
│   ├── Models.swift                # Core data models (Holding, Transaction, etc.)
│   ├── MarketCoin.swift            # Market coin model (in MarketModels.swift)
│   ├── MarketModels.swift          # Market-related models
│   ├── CoinPaprikaData.swift       # Alternative API models
│   └── CryptoNewsArticle.swift     # News article model
│
├── ViewModels
│   ├── HomeViewModel.swift         # Home dashboard state
│   ├── MarketViewModel.swift       # Market data & watchlist (2700+ lines)
│   ├── PortfolioViewModel.swift    # Portfolio holdings & transactions
│   ├── ChatViewModel.swift         # AI chat state
│   ├── TradeViewModel.swift        # Trading interface state
│   ├── TechnicalsViewModel.swift   # Technical analysis state
│   └── OrderBookViewModel.swift    # Order book data
│
├── Services
│   ├── CryptoAPIService.swift      # CoinGecko API wrapper
│   ├── BinanceService.swift        # Binance API (prices, sparklines)
│   ├── CoinbaseService.swift       # Coinbase API adapter
│   ├── LivePriceManager.swift      # Centralized price polling (2000+ lines)
│   ├── CryptoNewsService.swift     # News fetching
│   ├── AIInsightService.swift      # AI endpoint integration
│   ├── PriceService.swift          # Price service protocol
│   ├── CandleService.swift         # Candlestick data
│   └── ExchangeService.swift       # Exchange protocol
│
├── Repository
│   ├── PortfolioRepository.swift   # Unifies manual/live/priced holdings
│   ├── PortfolioDataService.swift  # Portfolio data protocol
│   ├── ManualPortfolioDataService.swift
│   └── LivePortfolioDataService.swift
│
├── Views
│   ├── Home/
│   ├── Market/
│   ├── Trade/
│   ├── Portfolio/
│   ├── AI/
│   └── Components/
│
├── Design System
│   ├── DesignSystem.swift          # Core DS tokens
│   ├── DesignSystem+Buttons.swift  # Button styles
│   ├── DesignSystem+Gradients.swift
│   ├── DesignSystem+Neutrals.swift
│   ├── DesignSystem+Pills.swift
│   ├── BrandColors.swift
│   ├── BrandStyles.swift
│   └── PremiumStyles.swift
│
└── Utilities
    ├── CacheManager.swift          # Disk caching
    ├── FormatterCache.swift        # Number formatter cache
    ├── NumberFormatting.swift      # Price/percent formatting
    ├── NetworkReachability.swift   # Connectivity monitoring
    └── UIShims.swift               # UI compatibility helpers
```

---

## Data Layer

### Core Data Models

#### `Holding` (Models.swift)
```swift
struct Holding: Identifiable, Codable, Equatable {
    var id: UUID
    var coinName: String
    var coinSymbol: String
    var quantity: Double
    var currentPrice: Double
    var costBasis: Double
    var imageUrl: String?
    var isFavorite: Bool
    var dailyChange: Double
    var purchaseDate: Date
    
    var currentValue: Double { quantity * currentPrice }
    var profitLoss: Double { (currentPrice - costBasis) * quantity }
}
```

#### `Transaction` (Models.swift)
```swift
struct Transaction: Identifiable, Codable {
    let id: UUID
    let coinSymbol: String
    let quantity: Double
    let pricePerUnit: Double
    let date: Date
    let isBuy: Bool
    let isManual: Bool  // true = user-entered, false = synced from exchange
}
```

#### `MarketCoin` (MarketModels.swift)
```swift
struct MarketCoin: Identifiable, Codable, Hashable {
    let id: String           // CoinGecko ID (e.g., "bitcoin")
    let symbol: String       // Ticker (e.g., "BTC")
    let name: String
    var imageUrl: URL?
    var priceUsd: Double?
    var marketCap: Double?
    var totalVolume: Double?
    var priceChangePercentage1hInCurrency: Double?
    var priceChangePercentage24hInCurrency: Double?
    var priceChangePercentage7dInCurrency: Double?
    var sparklineIn7d: [Double]
    var marketCapRank: Int?
    // ... additional fields
}
```

#### `ChatMessage` (Models.swift)
```swift
struct ChatMessage: Identifiable, Codable {
    var id: UUID
    var sender: String      // "user" or "ai"
    var text: String
    var timestamp: Date
    var isError: Bool
    var imagePath: String?  // Persisted image path
    var imageData: Data?    // Transient runtime data
}
```

---

## Services Layer

### LivePriceManager (Single Source of Truth for Prices)
**File:** `LivePriceManager.swift`

The most critical service - manages all live price data:

```swift
final class LivePriceManager {
    static let shared = LivePriceManager()
    
    // Publishers
    var publisher: AnyPublisher<[MarketCoin], Never>
    
    // Core methods
    func startPolling(interval: TimeInterval = 120)
    func stopPolling()
    func update(symbol: String, price: Double, change24h: Double?)
    
    // Best-available data accessors
    @MainActor func bestChange1hPercent(for coin: MarketCoin) -> Double?
    @MainActor func bestChange24hPercent(for coin: MarketCoin) -> Double?
    @MainActor func bestChange7dPercent(for coin: MarketCoin) -> Double?
    @MainActor func bestVolumeUSD(for coin: MarketCoin) -> Double?
}
```

**Key Behaviors:**
- Polls CoinGecko every 120s for full market data
- Overlays Binance 24hr ticker every 5-60s for price freshness
- Maintains sidecar caches for 1h/24h/7d percent changes
- Derives missing percent values from sparkline data
- Coalesces emissions to reduce UI churn
- Handles rate limiting with exponential backoff

### CryptoAPIService
**File:** `CryptoAPIService.swift`

Wrapper for CoinGecko API:

```swift
final class CryptoAPIService {
    static let shared = CryptoAPIService()
    
    func fetchCoinMarkets() async throws -> [MarketCoin]
    func fetchCoins(ids: [String]) async -> [MarketCoin]
    func fetchSpotPrice(coin: String) async throws -> Double
    func fetchGlobalData() async throws -> GlobalMarketData
    func fetchPriceHistory(coinID: String, timeframe: ChartTimeframe) async -> [Double]
}
```

### BinanceService
**File:** `BinanceService.swift`

Binance API integration with multi-endpoint failover:

```swift
actor BinanceService {
    static func fetchSparkline(symbol: String) async -> [Double]
    static func fetch24hrStats(symbols: [String]) async throws -> [CoinPrice]
}
```

**Features:**
- Multi-endpoint fallover (api.binance.com, api1-3.binance.com, api.binance.us)
- Rate limiting with token bucket
- Endpoint health tracking
- Coinbase fallback for sparklines

### MarketViewModel
**File:** `MarketViewModel.swift` (2700+ lines)

Central market data manager:

```swift
@MainActor
final class MarketViewModel: ObservableObject {
    static let shared = MarketViewModel()
    
    @Published var state: LoadingState<[MarketCoin]>
    @Published var favoriteIDs: Set<String>
    @Published var watchlistCoins: [MarketCoin]
    
    var coins: [MarketCoin]  // All loaded coins
    var allCoins: [MarketCoin]  // Alias for coins
    
    func loadAllData() async
    func toggleFavorite(_ coin: MarketCoin)
}
```

---

## View Layer

### HomeView Structure
**File:** `HomeView.swift` (1400+ lines)

Sections displayed in order (configurable via `HomeSectionsLayout`):

1. **Portfolio Section** - Total value, pie chart, P/L metrics
2. **AI Insights** - Premium AI insight card with prompts
3. **Watchlist** - Favorited coins with sparklines
4. **Market Stats** - Global market cap, volume, dominance
5. **Sentiment** - Fear & Greed gauge
6. **Heatmap** - Market heat map visualization
7. **Action Center** - Risk scan, portfolio analysis
8. **Trending** - Trending coins carousel
9. **Arbitrage** - Arbitrage opportunities (feature-flagged)
10. **Events** - Crypto calendar events
11. **Explore** - Discover new coins
12. **News** - Crypto news feed
13. **Transactions** - Recent transaction history
14. **Community** - Social features

### Key View Components

| Component | File | Purpose |
|-----------|------|---------|
| `WatchlistSection` | `WatchlistSection.swift` | Favorites list with reordering |
| `MarketSentimentView` | `MarketSentimentView.swift` | Fear & Greed gauge |
| `MarketHeatMapSection` | `MarketHeatMapSection.swift` | Grid/treemap heatmap |
| `CoinDetailView` | `CoinDetailView.swift` | Coin details page |
| `TechnicalsGaugeView` | `TechnicalsViews.swift` | Technical analysis gauge |
| `OrderBookView` | `OrderBookView.swift` | Trading order book |
| `PortfolioChartView` | `PortfolioChartView.swift` | Portfolio value chart |
| `SparklineView` | `SparklineView.swift` | Mini 7-day chart |

---

## State Management

### Environment Objects
Injected at app root in `CryptoSageAIApp`:

```swift
.environmentObject(appState)        // AppState - selected tab, dark mode
.environmentObject(marketVM)        // MarketViewModel - market data
.environmentObject(portfolioVM)     // PortfolioViewModel - holdings
.environmentObject(newsVM)          // CryptoNewsFeedViewModel - news
.environmentObject(segmentVM)       // MarketSegmentViewModel - market segments
.environmentObject(dataModeManager) // DataModeManager - live/demo mode
.environmentObject(homeVM)          // HomeViewModel - home state
.environmentObject(chatVM)          // ChatViewModel - AI chat
```

### AppStorage Keys
User preferences persisted via `@AppStorage`:

```swift
@AppStorage("App.Appearance")       // "system", "dark", "light"
@AppStorage("demoModeEnabled")      // Demo portfolio toggle
@AppStorage("aiAskBarHidden")       // AI input bar visibility
@AppStorage("Settings.DarkMode")    // Legacy dark mode key
```

### FavoritesManager
**File:** `FavoritesManager.swift`

Centralized favorites/watchlist management:

```swift
class FavoritesManager {
    static let shared = FavoritesManager()
    
    var favoriteIDs: Set<String>
    
    func add(id: String)
    func remove(id: String)
    func toggle(id: String)
    func isFavorite(id: String) -> Bool
    func getOrder() -> [String]
    func reorder(from: IndexSet, to: Int)
}
```

---

## Key Data Models

### GlobalMarketData
```swift
struct GlobalMarketData: Codable {
    let totalMarketCap: [String: Double]    // "usd" -> value
    let totalVolume: [String: Double]
    let marketCapPercentage: [String: Double]  // "btc" -> dominance %
    let marketCapChangePercentage24hUsd: Double?
}
```

### CoinPrice (BinanceService)
```swift
struct CoinPrice {
    let symbol: String
    let lastPrice: Double
    let openPrice: Double
    let highPrice: Double
    let lowPrice: Double
    let volume: Double?
    let change24h: Double
}
```

### TechnicalsSummary
```swift
struct TechnicalsSummary: Codable {
    let score01: Double           // 0-1 needle position
    let verdict: TechnicalVerdict // strongSell → strongBuy
    let sellCount, neutralCount, buyCount: Int
    let maSell, maNeutral, maBuy: Int
    let oscSell, oscNeutral, oscBuy: Int
    let indicators: [IndicatorSignal]
}
```

---

## External Integrations

### APIs

| API | Purpose | Files |
|-----|---------|-------|
| CoinGecko | Market data, prices, global stats | `CryptoAPIService.swift` |
| Binance | Real-time prices, 24hr stats, sparklines | `BinanceService.swift` |
| Coinbase | Fallback prices, sparklines | `CoinbaseService.swift`, `BinanceService.swift` |
| TradingView | Technical analysis widgets | `TradingViewChartWebView.swift`, `TechnicalsViews.swift` |
| 3Commas | Trading bots | `ThreeCommasService.swift`, `ThreeCommasAPI.swift` |

### Exchange Adapters
Protocol-based exchange integration:

```swift
protocol ExchangeService {
    func fetchHoldings(completion: @escaping (Result<[Holding], Error>) -> Void)
}

// Implementations
class CoinbaseIntegration: ExchangeService
class BinanceExchangeAdapter
class CoinbaseExchangeAdapter
```

### Wallet Address Tracking
**File:** `BlockchainConnectionProvider.swift`

For tracking wallet balances via public blockchain APIs (Etherscan, Blockchain.com, Solana RPC). Read-only - no private keys required.

---

## File Organization

### Naming Conventions
- **Views:** `*View.swift` (e.g., `HomeView.swift`, `MarketView.swift`)
- **ViewModels:** `*ViewModel.swift` (e.g., `MarketViewModel.swift`)
- **Services:** `*Service.swift` (e.g., `CryptoAPIService.swift`)
- **Models:** Grouped in `Models.swift` or `*Models.swift`
- **Extensions:** `ClassName+Extension.swift` (e.g., `HomeView+Subviews.swift`)

### Large Files (>500 lines)
These files are complex and may need semantic search:

| File | Lines | Purpose |
|------|-------|---------|
| `MarketViewModel.swift` | 2700+ | Market data management |
| `LivePriceManager.swift` | 2000+ | Price polling & caching |
| `HomeView.swift` | 1400+ | Home dashboard |
| `CryptoAPIService.swift` | 1280+ | CoinGecko API |
| `BinanceService.swift` | 900+ | Binance API |
| `PortfolioViewModel.swift` | 740+ | Portfolio logic |
| `TechnicalsViews.swift` | 580+ | Technical analysis UI |

---

## Important Singletons

| Singleton | Access | Purpose |
|-----------|--------|---------|
| `MarketViewModel.shared` | Market data, watchlist, coins | Central market state |
| `LivePriceManager.shared` | Price polling, percent changes | Single source of truth for prices |
| `CryptoAPIService.shared` | API calls to CoinGecko | External API wrapper |
| `FavoritesManager.shared` | Favorite coin IDs | Watchlist management |
| `CacheManager.shared` | Disk caching | Persistent data storage |
| `NotificationsManager.shared` | Push notifications | Alert management |
| `ComplianceManager.shared` | Geo-restrictions | Regional compliance |
| `ExchangeHostPolicy.shared` | Binance endpoint selection | API routing |

---

## Design System

### Color Tokens (DesignSystem.swift)
```swift
enum DS {
    enum Colors {
        static let gold = Color(red: 0.98, green: 0.82, blue: 0.20)
        static let positive = Color.green
        static let negative = Color.red
    }
    
    enum Neutral {
        static func bg(_ opacity: Double) -> Color
        static func text(_ opacity: Double) -> Color
    }
}
```

### Common UI Patterns
- **Cards:** Rounded rectangles with `Color.white.opacity(0.05)` background
- **Pills/Chips:** Capsule shapes with gradients
- **Gauges:** Half-circle gauges for sentiment/technicals
- **Sparklines:** Mini 7-day price charts
- **Shimmer:** Loading placeholder animation

---

## Caching Strategy

### CacheManager
**File:** `CacheManager.swift`

Generic JSON caching to Documents directory:

```swift
class CacheManager {
    static let shared = CacheManager()
    
    func save<T: Encodable>(_ data: T, to filename: String) -> Bool
    func load<T: Decodable>(_ type: T.Type, from filename: String) -> T?
}
```

### Cache Files
| File | Contents | TTL |
|------|----------|-----|
| `coins_cache.json` | Market coins | Updated on each successful fetch |
| `watchlist_cache.json` | Watchlist coins | Updated on fetch |
| `global_cache.json` | Global market data | Updated on fetch |
| `percent_1h_sidecar.json` | 1h change cache | Debounced saves |
| `percent_24h_sidecar.json` | 24h change cache | Debounced saves |
| `percent_7d_sidecar.json` | 7d change cache | Debounced saves |
| `binance_supported_bases.json` | Binance pairs | 6 hour refresh |

---

## AI Agent Guidelines

### When Working on This Codebase

1. **Start with Entry Point:** Read `CryptoSageAIApp.swift` to understand the app structure.

2. **For Market Data Issues:** Check in order:
   - `LivePriceManager.swift` (price source of truth)
   - `MarketViewModel.swift` (UI state)
   - `CryptoAPIService.swift` (CoinGecko)
   - `BinanceService.swift` (Binance overlay)

3. **For Portfolio Features:** Check:
   - `PortfolioViewModel.swift`
   - `PortfolioRepository.swift`
   - `Models.swift` (Holding, Transaction)

4. **For UI Changes:** 
   - Views are in `CryptoSage/` with `*View.swift` naming
   - Design tokens in `DesignSystem*.swift` files
   - Large views (Home, Market, Trade) have subview files

5. **Environment Objects Required:**
   Most views need these injected:
   ```swift
   @EnvironmentObject var marketVM: MarketViewModel
   @EnvironmentObject var portfolioVM: PortfolioViewModel
   ```

6. **MainActor Requirement:**
   - All ViewModels are `@MainActor`
   - UI updates must happen on main thread
   - Use `Task { @MainActor in ... }` for async UI updates

7. **Rate Limiting Awareness:**
   - CoinGecko has aggressive rate limits
   - Code uses cooldowns and caching extensively
   - Check `lastMarketsRateLimitAt` patterns

8. **Search Strategy for Large Files:**
   - `MarketViewModel.swift` and `LivePriceManager.swift` are too large to read fully
   - Use semantic search or grep for specific functionality
   - Key methods are well-documented with comments

### Common Modification Patterns

**Adding a new coin metric:**
1. Add field to `MarketCoin` in `MarketModels.swift`
2. Parse in `MarketCoin(gecko:)` initializer
3. Add to `LivePriceManager` if real-time updates needed
4. Update relevant views

**Adding a new HomeView section:**
1. Add case to `HomeSectionsLayout.HomeSection`
2. Implement view in `homeContentStack` switch statement
3. Add visibility logic in `HomeSectionsLayout.visibleSections`

**Adding exchange integration:**
1. Implement `ExchangeService` protocol
2. Add adapter in `ExchangeAdapters.swift`
3. Wire into `PortfolioRepository`

---

## Quick Reference

### Key Imports
```swift
import SwiftUI
import Combine
import Foundation
```

### Common ViewModel Pattern
```swift
@MainActor
final class MyViewModel: ObservableObject {
    @Published var data: [MyModel] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    func load() async {
        // Async data loading
    }
}
```

### Environment Injection Pattern
```swift
struct MyView: View {
    @EnvironmentObject var marketVM: MarketViewModel
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    
    var body: some View { ... }
}
```

---

## Common Issues & Solutions

### Rate Limiting
CoinGecko free tier has aggressive rate limits (~10-50 calls/minute). The app handles this via:
- **Cooldown periods**: 180s for markets endpoint, 300s for global endpoint
- **Request deduplication**: In-flight requests are reused via `inflight_fetchCoinMarkets`
- **Cache fallbacks**: Cached data is returned when rate-limited
- **Multiple endpoint fallbacks**: Binance, Coinbase, bundled snapshots

### SwiftUI "Modifying state during view update" Warnings
This warning occurs when `@Published` properties change during view body computation. Solutions:
1. Wrap state changes in `DispatchQueue.main.async { }` to defer to next run loop
2. Extract Combine sink callbacks to separate methods
3. Use `publishOnNextRunLoop` helper in ViewModels

### Stale Cache Data
Sidecar caches (`percent_1h_sidecar.json`, etc.) can persist stale data across sessions:
- `LivePriceManager` checks `percent_sidecar_timestamp` in UserDefaults
- Caches older than 10 minutes (`sidecarCacheMaxAge`) are not loaded on startup
- Fresh API data repopulates the caches

### Market Cap Cross-Validation
CoinGecko sometimes returns incorrect market cap values. The app validates by:
1. Computing expected total market cap from BTC market cap / BTC dominance
2. If API value is <60% of derived value, use the derived value instead

### Console Log Noise Reduction
- `CacheUtils` logs "not found" only once per filename to avoid spam
- Rate limit logs include cooldown duration for debugging
- System-level warnings (nw_connection, IOSurface) can be ignored

---

## Version History

- **v1.1** - Added Common Issues & Solutions section (January 2026)
- **v1.0** - Initial architecture documentation (January 2026)

---

*This document is intended for AI agents and developers working on the CryptoSage codebase. Keep it updated as the architecture evolves.*

