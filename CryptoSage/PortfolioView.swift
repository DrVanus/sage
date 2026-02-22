import SwiftUI
import Charts

private enum HoldingsSort: String, CaseIterable {
    case valueDesc
    case plPercentDesc
    case change24hDesc
    case alpha
    
    var displayName: String {
        switch self {
        case .valueDesc: return "Value"
        case .plPercentDesc: return "P/L %"
        case .change24hDesc: return "24h %"
        case .alpha: return "A–Z"
        }
    }
}

// MARK: - Holdings Sort Picker (Grid-style, matching app design)
private struct HoldingsSortPicker: View {
    @Binding var isPresented: Bool
    @Binding var selection: HoldingsSort
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        
        VStack(spacing: 4) {
            // Header
            HStack {
                Text("Sort by")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DS.Adaptive.textSecondary)
                Spacer(minLength: 6)
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(height: 1)
                .padding(.horizontal, 6)
            
            // Grid of sort options
            let spacing: CGFloat = 5
            let horizontalPadding: CGFloat = 6
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: spacing), GridItem(.flexible(), spacing: spacing)],
                alignment: .center,
                spacing: spacing
            ) {
                ForEach(HoldingsSort.allCases, id: \.self) { sort in
                    sortChip(for: sort, isDark: isDark)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 2)
            .padding(.bottom, 2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(4)
        // PERFORMANCE FIX v19: Replaced .ultraThinMaterial
        .background(DS.Adaptive.chipBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            LinearGradient(
                colors: [DS.Adaptive.gradientHighlight.opacity(isDark ? 0.10 : 0.40), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 0.75)
                .allowsHitTesting(false)
        )
        .tint(DS.Colors.gold)
        .frame(minWidth: 160, maxWidth: 200)
    }
    
    @ViewBuilder
    private func sortChip(for sort: HoldingsSort, isDark: Bool) -> some View {
        let selected = (sort == selection)
        
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                selection = sort
            }
            isPresented = false
        } label: {
            Text(sort.displayName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .foregroundStyle(selected ? Color.black : DS.Adaptive.textPrimary)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack {
                        Capsule()
                            .fill(selected ? AnyShapeStyle(AdaptiveGradients.chipGold(isDark: isDark)) : AnyShapeStyle(DS.Adaptive.chipBackground))
                        // Top gloss
                        Capsule()
                            .fill(LinearGradient(
                                colors: [
                                    isDark 
                                        ? Color.white.opacity(selected ? 0.18 : 0.10)
                                        : Color.white.opacity(selected ? 0.60 : 0.40),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            ))
                        // Rim
                        Capsule()
                            .stroke(selected ? AnyShapeStyle(ctaRimStrokeGradient) : AnyShapeStyle(DS.Adaptive.stroke), lineWidth: 0.8)
                    }
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(sort.displayName))
        .accessibilityAddTraits(selection == sort ? .isSelected : [])
    }
}

// Temporary extension to add a default accountName property to Holding.
// When your API provides actual account info, update this accordingly.
extension Holding {
    var accountName: String {
        return "Default"
    }
}

private let brandAccent = Color.brandAccent

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct CompactChartModeToggle: View {
    @Binding var chartMode: ChartViewType
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        HStack(spacing: 0) {
            modeButton(.line, systemImage: "chart.line.uptrend.xyaxis")
            modeButton(.pie, systemImage: "chart.pie.fill")
        }
        .frame(height: 32)
        .background(
            ZStack {
                Capsule(style: .continuous)
                    .fill(DS.Adaptive.chipBackground)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(isDark ? 0.04 : 0.15), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: isDark
                                ? [BrandColors.goldBase.opacity(0.15), DS.Adaptive.stroke.opacity(0.5)]
                                : [BrandColors.goldDark.opacity(0.12), DS.Adaptive.stroke.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isDark ? 0.8 : 1
                    )
            )
        )
        .clipShape(Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart mode")
    }

    @ViewBuilder
    private func modeButton(_ mode: ChartViewType, systemImage: String) -> some View {
        let isSelected = chartMode == mode
        
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { chartMode = mode }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 36, height: 32)
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(LinearGradient(
                            colors: isDark ? [BrandColors.goldLight, BrandColors.goldBase] : [BrandColors.goldBase, BrandColors.goldDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          ))
                        : AnyShapeStyle(DS.Adaptive.textSecondary)
                )
                .background(
                    Group {
                        if isSelected {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                (isDark ? BrandColors.goldBase : BrandColors.goldDark).opacity(isDark ? 0.10 : 0.06),
                                                Color.clear
                                            ],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 20
                                        )
                                    )
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(isDark ? 0.08 : 0.22), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: isDark
                                                ? [BrandColors.goldLight.opacity(0.35), BrandColors.goldBase.opacity(0.12)]
                                                : [BrandColors.goldDark.opacity(0.25), BrandColors.goldBase.opacity(0.08)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: isDark ? 1 : 1.2
                                    )
                            )
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

struct PortfolioView: View {
    @EnvironmentObject var homeVM: HomeViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    private var portfolioVM: PortfolioViewModel { homeVM.portfolioVM }
    @State private var displayedTotal: Double = 0
    @AppStorage("hideBalances") private var hideBalances: Bool = false
    @AppStorage("showStocksInPortfolio") private var showStocksInPortfolio: Bool = false
    
    // Demo mode manager
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    
    // Paper Trading manager
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    
    // Search
    @State private var showSearchBar = false
    @State private var searchTerm = ""
    @State private var isSearchFocused = false  // Tracks search field focus state
    
    // Chart mode state lifted up for parent-level management (persisted across app launches)
    @AppStorage("portfolio.chartMode") private var chartModeRaw: String = ChartViewType.line.rawValue
    private var chartMode: ChartViewType {
        get { ChartViewType(rawValue: chartModeRaw) ?? .line }
        nonmutating set { chartModeRaw = newValue.rawValue }
    }
    private var chartModeBinding: Binding<ChartViewType> {
        Binding(
            get: { ChartViewType(rawValue: chartModeRaw) ?? .line },
            set: { chartModeRaw = $0.rawValue }
        )
    }
    // Shared selected range with chart (persisted) - used for consistent display in header
    @AppStorage("portfolio_selected_range") private var selectedRangeRaw: String = "1W"
    
    /// The selected timeframe for portfolio chart
    private var selectedRange: HomeView.PortfolioRange {
        HomeView.PortfolioRange(rawValue: selectedRangeRaw) ?? .week
    }
    
    /// Calculate the change percent for the selected timeframe from portfolio history
    private var selectedRangeChangePercent: Double {
        let history = effectiveChartHistory
        guard !history.isEmpty else { return 0 }
        
        let filtered = history.filtered(for: selectedRange)
        guard let first = filtered.first?.value, let last = filtered.last?.value, first > 0 else { return 0 }
        return ((last - first) / first) * 100
    }
    
    /// Calculate the change amount for the selected timeframe
    private var selectedRangeChangeAmount: Double {
        let history = effectiveChartHistory
        guard !history.isEmpty else { return 0 }
        
        let filtered = history.filtered(for: selectedRange)
        guard let first = filtered.first?.value, let last = filtered.last?.value else { return 0 }
        return last - first
    }
    
    /// Get the effective chart history (paper trading or portfolio)
    private var effectiveChartHistory: [ChartPoint] {
        if paperTradingManager.isPaperTradingEnabled {
            return paperTradingChartHistory
        }
        return portfolioVM.history
    }
    
    /// Format the selected range label for display (e.g., "Today", "1 Week", "1 Month")
    private var selectedRangeLabel: String {
        selectedRangeLabelFull
    }
    
    /// Human-readable label for the selected range (e.g., "Today", "1 Week", "1 Month")
    private var selectedRangeLabelFull: String {
        switch selectedRange {
        case .day: return "Today"
        case .week: return "1 Week"
        case .month: return "1 Month"
        case .year: return "1 Year"
        case .all: return "All Time"
        }
    }
    
    // Sort and filters for holdings
    @State private var sortMode: HoldingsSort = .valueDesc
    @State private var showOnlyFavorites: Bool = false
    @State private var showSortPicker: Bool = false
    
    // Asset type filter (All, Crypto, Stocks)
    @State private var selectedAssetType: AssetType? = nil  // nil = All
    
    // Sheets
    @State private var showDeFiDashboard = false
    @State private var showTaxReport = false
    
    // Navigation
    @State private var navigateToPaymentMethods = false
    @State private var navigateToCSVImport = false
    @State private var selectedPerformerCoin: MarketCoin? = nil
    @State private var selectedStockHolding: Holding? = nil
    @State private var selectedCryptoHolding: Holding? = nil
    
    // Tooltip
    @State private var showTooltip = false
    @State private var shineTrigger: Bool = false
    @State private var totalValueScale: CGFloat = 1.0
    @State private var lastTotalValue: Double = 0
    @State private var lastTotalAnimationAt: Date = .distantPast
    
    // FIX: Track initial layout completion to prevent blank screen on cold start
    // When LazyView initializes PortfolioView after a long background period, GeometryReader
    // can return zero size on first layout pass, causing content to not render
    @State private var didCompleteInitialLayout: Bool = false
    // PERFORMANCE FIX: Track initial data load to skip redundant work on tab switches
    @State private var didInitialDataLoad: Bool = false
    
    // PERFORMANCE FIX: Cached holdings and prices to avoid heavy computation during view body
    // These are updated via onChange handlers instead of being computed on every render
    @State private var cachedDisplayedHoldings: [Holding] = []
    @State private var cachedPaperTradingPrices: [String: Double] = [:]
    @State private var lastHoldingsCacheAt: Date = .distantPast
    
    // PERFORMANCE FIX v2: Debounced work item to consolidate multiple rapid onChange events
    // Instead of 5 separate onChange handlers each triggering updateCachedHoldings(),
    // we now batch them with a 100ms debounce to reduce redundant recomputations
    @State private var holdingsUpdateWorkItem: DispatchWorkItem?
    
    // Filtered holdings to display: Filter by asset type, search term, favorites, and sorting.
    // PERFORMANCE: Returns cached value if available, falls back to computation
    private var displayedHoldings: [Holding] {
        // Use cache if available and fresh (< 500ms)
        if !cachedDisplayedHoldings.isEmpty && Date().timeIntervalSince(lastHoldingsCacheAt) < 0.5 {
            return cachedDisplayedHoldings
        }
        return computeDisplayedHoldings()
    }
    
    // PERFORMANCE FIX: Actual computation extracted to separate function
    private func computeDisplayedHoldings() -> [Holding] {
        var base = portfolioVM.holdings
        
        // If stocks feature is disabled, filter out stocks/ETFs but KEEP crypto AND commodities
        // Commodities (precious metals from Coinbase) should always be visible
        if !showStocksInPortfolio {
            base = base.filter { $0.assetType == .crypto || $0.assetType == .commodity }
        }
        
        // Filter by asset type (only when stocks are enabled)
        if showStocksInPortfolio, let assetType = selectedAssetType {
            base = base.filter { $0.assetType == assetType }
        }
        
        // Filter by search
        if showSearchBar, !searchTerm.isEmpty {
            base = base.filter {
                $0.displayName.lowercased().contains(searchTerm.lowercased()) ||
                $0.displaySymbol.lowercased().contains(searchTerm.lowercased())
            }
        }
        // Favorites filter
        if showOnlyFavorites {
            base = base.filter { $0.isFavorite }
        }
        // Sorting
        switch sortMode {
        case .valueDesc:
            base.sort { $0.currentValue > $1.currentValue }
        case .plPercentDesc:
            let p: (Holding) -> Double = { h in
                let cost = h.costBasis * h.quantity
                return cost > 0 ? ((h.currentValue - cost) / cost * 100) : 0
            }
            base.sort { p($0) > p($1) }
        case .change24hDesc:
            base.sort { $0.dailyChangePercent > $1.dailyChangePercent }
        case .alpha:
            base.sort { $0.displaySymbol < $1.displaySymbol }
        }
        return base
    }
    
    // MARK: - Paper Trading Helpers
    
    /// Get current market prices for Paper Trading calculations
    /// PERFORMANCE FIX: Returns cached value if available to avoid iterating allCoins during body
    private var paperTradingPrices: [String: Double] {
        if !cachedPaperTradingPrices.isEmpty {
            return cachedPaperTradingPrices
        }
        return computePaperTradingPrices()
    }
    
    /// PERFORMANCE FIX: Actual computation extracted to separate function
    /// BUG FIX: Now includes fallback to lastKnownPrices when live prices are unavailable (API rate limiting)
    /// NOTE: Does NOT update cache here to avoid "Publishing changes from within view updates" warnings
    /// PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing across all views
    private func computePaperTradingPrices() -> [String: Double] {
        var prices: [String: Double] = [:]
        
        // First, get all available live prices from market data
        // PRICE CONSISTENCY FIX: Use bestPrice() which checks LivePriceManager first
        for coin in MarketViewModel.shared.allCoins {
            let symbol = coin.symbol.uppercased()
            // Priority: bestPrice() > coin.priceUsd (fallback)
            if let price = MarketViewModel.shared.bestPrice(for: coin.id), price > 0 {
                prices[symbol] = price
            } else if let price = coin.priceUsd, price > 0 {
                prices[symbol] = price
            }
        }
        
        // FIX: For any assets in paperBalances not yet resolved, try bestPrice(forSymbol:)
        // This catches cases where allCoins hasn't loaded yet but LivePriceManager has data
        for (asset, _) in paperTradingManager.paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let symbolPrice = MarketViewModel.shared.bestPrice(forSymbol: symbol), symbolPrice > 0 {
                    prices[symbol] = symbolPrice
                }
            }
        }
        
        // Fallback: For any assets still without live prices,
        // use lastKnownPrices from PaperTradingManager — but only if fresh (< 30 min old)
        for (asset, _) in paperTradingManager.paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let cachedPrice = paperTradingManager.lastKnownPrices[symbol], cachedPrice > 0,
                   paperTradingManager.isCachedPriceFresh(for: symbol) {
                    prices[symbol] = cachedPrice
                }
            }
        }
        
        // Stablecoins are always 1:1 with USD
        prices["USDT"] = 1.0
        prices["USD"] = 1.0
        prices["USDC"] = 1.0
        
        // Push fresh prices to PaperTradingManager cache (with timestamps)
        paperTradingManager.updateLastKnownPrices(prices)
        
        return prices
    }
    
    /// PERFORMANCE FIX: Updates cached holdings - called from onChange handlers
    private func updateCachedHoldings() {
        let newHoldings = computeDisplayedHoldings()
        // Only update if meaningfully different
        if newHoldings.count != cachedDisplayedHoldings.count ||
           zip(newHoldings, cachedDisplayedHoldings).contains(where: { $0.id != $1.id }) {
            cachedDisplayedHoldings = newHoldings
            lastHoldingsCacheAt = Date()
        }
    }
    
    /// PERFORMANCE FIX v2: Debounced holdings update to consolidate multiple rapid onChange events
    /// Cancels any pending update and schedules a new one after 100ms debounce
    private func scheduleHoldingsUpdate() {
        // Cancel any pending work item
        holdingsUpdateWorkItem?.cancel()
        
        // Create new debounced work item
        let workItem = DispatchWorkItem { [self] in
            updateCachedHoldings()
        }
        holdingsUpdateWorkItem = workItem
        
        // Schedule with 100ms debounce - batches rapid changes together
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
    
    /// PERFORMANCE FIX: Updates cached prices - called from onChange handlers
    private func updateCachedPrices() {
        cachedPaperTradingPrices = computePaperTradingPrices()
    }
    
    /// Calculate Paper Trading portfolio total value
    private var paperTradingTotalValue: Double {
        paperTradingManager.calculatePortfolioValue(prices: paperTradingPrices)
    }
    
    /// Calculate Paper Trading P&L
    private var paperTradingProfitLoss: Double {
        paperTradingManager.calculateProfitLoss(prices: paperTradingPrices)
    }
    
    /// Calculate Paper Trading P&L percentage
    private var paperTradingProfitLossPercent: Double {
        paperTradingManager.calculateProfitLossPercent(prices: paperTradingPrices)
    }
    
    /// Paper Trading holdings as displayable items
    private var paperTradingHoldings: [(symbol: String, amount: Double, value: Double, percent: Double)] {
        let totalValue = paperTradingTotalValue
        guard totalValue > 0 else { return [] }
        
        let prices = paperTradingPrices
        var holdings: [(symbol: String, amount: Double, value: Double, percent: Double)] = []
        
        for (asset, amount) in paperTradingManager.paperBalances where amount > 0.000001 {
            let assetValue: Double
            if asset == "USDT" || asset == "USD" || asset == "USDC" {
                assetValue = amount
            } else if let price = prices[asset] {
                assetValue = amount * price
            } else {
                continue
            }
            
            let percent = (assetValue / totalValue) * 100
            holdings.append((symbol: asset, amount: amount, value: assetValue, percent: percent))
        }
        
        return holdings.sorted { $0.value > $1.value }
    }
    
    /// Paper Trading allocation data for pie chart (converts paperTradingHoldings to AllocationSlice format)
    private var paperTradingAllocationData: [PortfolioViewModel.AllocationSlice] {
        paperTradingHoldings.map { holding in
            PortfolioViewModel.AllocationSlice(
                symbol: holding.symbol,
                percent: holding.percent,
                color: portfolioVM.color(for: holding.symbol)
            )
        }
    }
    
    /// Generate a deterministic UUID from a symbol for stable SwiftUI identity.
    /// This ensures Paper Trading holdings maintain stable IDs across re-renders,
    /// allowing SwiftUI to preserve @State (like isExpanded) and complete image loading.
    private func stableUUID(for symbol: String) -> UUID {
        // Create a deterministic hash from a fixed prefix + symbol
        let input = "paper-trading-\(symbol.uppercased())"
        var bytes = [UInt8](repeating: 0, count: 16)
        
        // Use a simple but deterministic hash algorithm
        // FNV-1a inspired approach for consistent results across app launches
        var hash1: UInt64 = 14695981039346656037  // FNV offset basis
        var hash2: UInt64 = 14695981039346656037
        
        for (index, char) in input.utf8.enumerated() {
            if index % 2 == 0 {
                hash1 ^= UInt64(char)
                hash1 &*= 1099511628211  // FNV prime
            } else {
                hash2 ^= UInt64(char)
                hash2 &*= 1099511628211
            }
        }
        
        // Fill the UUID bytes from our two hashes
        withUnsafeBytes(of: hash1.bigEndian) { ptr in
            for i in 0..<8 { bytes[i] = ptr[i] }
        }
        withUnsafeBytes(of: hash2.bigEndian) { ptr in
            for i in 0..<8 { bytes[i + 8] = ptr[i] }
        }
        
        // Set UUID version (4) and variant bits for RFC 4122 compliance
        bytes[6] = (bytes[6] & 0x0F) | 0x40  // Version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // Variant 1
        
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                          bytes[4], bytes[5], bytes[6], bytes[7],
                          bytes[8], bytes[9], bytes[10], bytes[11],
                          bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    
    /// Paper Trading balances converted to Holding objects for use with PortfolioCoinRow
    /// Uses the same reliable CoinGecko URLs as PortfolioCoinRow's CoinIconFallbacks
    private var paperTradingAsHoldings: [Holding] {
        let marketCoins = MarketViewModel.shared.allCoins
        
        // Known-good CoinGecko image URLs - same as CoinIconFallbacks in PortfolioCoinRow
        let knownCoinImageURLs: [String: String] = [
            "btc": "https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png",
            "eth": "https://coin-images.coingecko.com/coins/images/279/large/ethereum.png",
            "sol": "https://coin-images.coingecko.com/coins/images/4128/large/solana.png",
            "xrp": "https://coin-images.coingecko.com/coins/images/44/large/xrp-symbol-white-128.png",
            "bnb": "https://coin-images.coingecko.com/coins/images/825/large/binance-coin-logo.png",
            "ada": "https://coin-images.coingecko.com/coins/images/975/large/cardano.png",
            "doge": "https://coin-images.coingecko.com/coins/images/5/large/dogecoin.png",
            "ltc": "https://coin-images.coingecko.com/coins/images/2/large/litecoin.png",
            "dot": "https://coin-images.coingecko.com/coins/images/12171/large/polkadot.png",
            "usdt": "https://coin-images.coingecko.com/coins/images/325/large/Tether.png",
            "usdc": "https://coin-images.coingecko.com/coins/images/6319/large/USD_Coin_icon.png",
            "avax": "https://coin-images.coingecko.com/coins/images/12559/large/Avalanche_Circle_RedWhite_Trans.png",
            "link": "https://coin-images.coingecko.com/coins/images/877/large/chainlink-new-logo.png",
            "matic": "https://coin-images.coingecko.com/coins/images/4713/large/polygon.png",
            "atom": "https://coin-images.coingecko.com/coins/images/1481/large/cosmos_hub.png",
            "uni": "https://coin-images.coingecko.com/coins/images/12504/large/uniswap-logo.png",
            "shib": "https://coin-images.coingecko.com/coins/images/11939/large/shiba.png",
            "trx": "https://coin-images.coingecko.com/coins/images/1094/large/tron-logo.png",
            "xlm": "https://coin-images.coingecko.com/coins/images/100/large/Stellar_symbol_black_RGB.png",
            "near": "https://coin-images.coingecko.com/coins/images/10365/large/near.jpg",
            "apt": "https://coin-images.coingecko.com/coins/images/26455/large/aptos_round.png",
            "arb": "https://coin-images.coingecko.com/coins/images/16547/large/photo_2023-03-29_21.47.00.jpeg",
            "op": "https://coin-images.coingecko.com/coins/images/25244/large/Optimism.png",
            "sui": "https://coin-images.coingecko.com/coins/images/26375/large/sui_asset.jpeg",
            "fil": "https://coin-images.coingecko.com/coins/images/12817/large/filecoin.png",
            "inj": "https://coin-images.coingecko.com/coins/images/12882/large/Secondary_Symbol.png",
            "hbar": "https://coin-images.coingecko.com/coins/images/3688/large/hbar.png",
            "algo": "https://coin-images.coingecko.com/coins/images/4380/large/download.png",
            "vet": "https://coin-images.coingecko.com/coins/images/1167/large/VeChain-Logo-768x725.png",
            "ftm": "https://coin-images.coingecko.com/coins/images/4001/large/Fantom_round.png",
            "pepe": "https://coin-images.coingecko.com/coins/images/29850/large/pepe-token.jpeg",
            "wbtc": "https://coin-images.coingecko.com/coins/images/7598/large/wrapped_bitcoin_wbtc.png",
            "dai": "https://coin-images.coingecko.com/coins/images/9956/large/Badge_Dai.png",
            "busd": "https://coin-images.coingecko.com/coins/images/9576/large/BUSD.png",
            "fdusd": "https://coin-images.coingecko.com/coins/images/31079/large/firstdigitalusd.jpeg",
            "usd": "https://coin-images.coingecko.com/coins/images/325/large/Tether.png"
        ]
        
        return paperTradingHoldings.map { item in
            let lowerSymbol = item.symbol.lowercased()
            
            // Priority 1: Use known-good CoinGecko URLs (most reliable - always have a URL)
            // Priority 2: Market data image URL  
            // Priority 3: CoinCap CDN fallback (always generates a valid URL)
            let knownGoodUrl: String? = knownCoinImageURLs[lowerSymbol]
            let marketImageUrl: String? = marketCoins
                .first(where: { $0.symbol.uppercased() == item.symbol.uppercased() })?
                .imageUrl?.absoluteString
            // CoinCap CDN as final fallback - always returns a URL
            let coincapUrl: String = "https://assets.coincap.io/assets/icons/\(lowerSymbol)@2x.png"
            
            // Use known URL first, then market data, then CoinCap CDN
            let imageUrl: String = knownGoodUrl ?? marketImageUrl ?? coincapUrl
            
            // Look up daily change from market data
            let dailyChange = marketCoins
                .first(where: { $0.symbol.uppercased() == item.symbol.uppercased() })?
                .dailyChange ?? 0
            
            return Holding(
                id: stableUUID(for: item.symbol),  // Stable ID for consistent SwiftUI identity
                coinName: CoinNameMapping.name(for: item.symbol),
                coinSymbol: item.symbol,
                quantity: item.amount,
                currentPrice: paperTradingPrices[item.symbol] ?? 0,
                costBasis: 0,
                imageUrl: imageUrl,  // Always non-nil now
                isFavorite: false,
                dailyChange: dailyChange,
                purchaseDate: Date()
            )
        }
    }
    
    /// Stablecoin symbols to exclude from top/worst performer calculation
    private var stablecoinSymbols: Set<String> { ["USDC", "USDT", "DAI", "TUSD", "BUSD", "USD", "FDUSD"] }
    
    /// True when paper account has market exposure beyond idle cash.
    private var hasPaperTradingExposure: Bool {
        // Any non-stable balance means we should chart real/derived P&L movement.
        let hasNonStableBalance = paperTradingManager.paperBalances.contains { asset, amount in
            amount > 0.000001 && !stablecoinSymbols.contains(asset.uppercased())
        }
        // If user has traded before, keep non-flat history behavior.
        return hasNonStableBalance || !paperTradingManager.paperTradeHistory.isEmpty
    }
    
    /// Generate chart history data for Paper Trading mode
    /// Creates realistic-looking chart with smooth curves similar to demo mode
    private var paperTradingChartHistory: [ChartPoint] {
        let initialValue = paperTradingManager.initialPortfolioValue
        let currentValue = paperTradingTotalValue
        
        // Cash-only paper account (e.g. fresh $100k, no trades) should be visually flat.
        if !hasPaperTradingExposure {
            let anchor = max(1, currentValue > 0 ? currentValue : initialValue)
            return flatPaperTradingHistory(value: anchor, days: 90)
        }
        
        // Generate realistic history similar to demo mode
        return generatePaperTradingHistory(
            initialValue: initialValue,
            currentValue: currentValue,
            days: 90  // 3 months of history for paper trading
        )
    }
    
    /// Flat baseline history used for fresh cash-only paper accounts.
    private func flatPaperTradingHistory(value: Double, days: Int = 90) -> [ChartPoint] {
        let now = Date()
        let calendar = Calendar.current
        var points: [ChartPoint] = []
        points.reserveCapacity(days + 49)
        
        // Daily anchors for long-range views
        for d in stride(from: days, through: 1, by: -1) {
            if let date = calendar.date(byAdding: .day, value: -d, to: now) {
                points.append(ChartPoint(date: date, value: value))
            }
        }
        // Hourly anchors for short-range smoothness
        for h in stride(from: 48, through: 0, by: -1) {
            if let date = calendar.date(byAdding: .hour, value: -h, to: now) {
                points.append(ChartPoint(date: date, value: value))
            }
        }
        
        points.sort { $0.date < $1.date }
        return points
    }
    
    /// Generates realistic portfolio history for Paper Trading with smooth, natural-looking curves.
    /// Uses Brownian motion for organic movement similar to demo mode.
    private func generatePaperTradingHistory(
        initialValue: Double,
        currentValue: Double,
        days: Int = 90
    ) -> [ChartPoint] {
        let today = Date()
        let calendar = Calendar.current
        
        // Calculate P&L for determining chart direction
        let pnlPercent = initialValue > 0 ? ((currentValue - initialValue) / initialValue) * 100 : 0
        
        // Calculate yesterday's value based on P&L trend (yesterday should be slightly less if we're up)
        let dailyVariation = pnlPercent >= 0 ? -0.15 : 0.15  // Small daily change
        let yesterdayValue = currentValue * (1.0 + dailyVariation / 100.0)
        
        // Starting value should be the initial portfolio value
        let startValue = initialValue
        
        var points: [ChartPoint] = []
        
        // Use a seeded random for consistent results within a session
        // Seed based on initial value so chart is stable but unique per portfolio
        var rng = PaperTradingRNG(seed: UInt64(initialValue.bitPattern) ^ UInt64(days))
        
        // Brownian motion state for smooth correlated movements
        var randomWalk: Double = 0
        
        // Pre-generate random walk values
        var walkValues: [Double] = []
        for _ in 0..<days {
            let step = Double.random(in: -0.0012...0.0012, using: &rng)
            randomWalk += step
            randomWalk *= 0.96  // Gentle mean reversion
            walkValues.append(randomWalk)
        }
        
        // Apply smoothing pass to reduce jaggedness
        var smoothedWalk: [Double] = walkValues
        for i in 1..<(walkValues.count - 1) {
            smoothedWalk[i] = (walkValues[i-1] + walkValues[i] + walkValues[i+1]) / 3.0
        }
        
        // Ease function for natural growth/decline curve
        func easeInOutQuad(_ t: Double) -> Double {
            t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        }
        
        // Generate daily points for days 2 and older
        for d in stride(from: days, through: 2, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -d, to: today) else { continue }
            
            let dayIndex = days - d
            let progress = Double(dayIndex) / Double(days)
            
            // Smooth baseline growth/decline using ease-in-out curve
            let baseline = startValue + (currentValue - startValue) * easeInOutQuad(progress)
            
            // Apply smoothed random walk for organic micro-movements
            let walkIndex = min(dayIndex, smoothedWalk.count - 1)
            let noise = smoothedWalk[max(0, walkIndex)]
            
            let value = baseline * (1 + noise)
            points.append(ChartPoint(date: date, value: max(1, value)))
        }
        
        // Generate smooth hourly points for last 48 hours
        let twoDaysAgoValue: Double = points.last?.value ?? (currentValue * 0.998)
        
        // Hermite smoothstep for natural easing
        func smoothStep(_ t: Double) -> Double {
            t * t * (3 - 2 * t)
        }
        
        var hourlyWalk: Double = 0
        
        for hoursAgo in stride(from: 48, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .hour, value: -hoursAgo, to: today) else { continue }
            
            let hourlyStep = Double.random(in: -0.0002...0.0002, using: &rng)
            hourlyWalk += hourlyStep
            hourlyWalk *= 0.90
            
            let value: Double
            if hoursAgo > 24 {
                let progress = smoothStep(Double(48 - hoursAgo) / 24.0)
                let baseValue = twoDaysAgoValue + (yesterdayValue - twoDaysAgoValue) * progress
                value = baseValue * (1 + hourlyWalk)
            } else if hoursAgo == 24 {
                value = yesterdayValue
            } else if hoursAgo == 0 {
                value = currentValue
            } else {
                let progress = smoothStep(Double(24 - hoursAgo) / 24.0)
                let baseValue = yesterdayValue + (currentValue - yesterdayValue) * progress
                value = baseValue * (1 + hourlyWalk)
            }
            
            points.append(ChartPoint(date: date, value: max(1, value)))
        }
        
        // Sort by date ascending
        points.sort { $0.date < $1.date }
        
        // Ensure exact endpoint values
        if let lastIdx = points.indices.last {
            points[lastIdx] = ChartPoint(date: today, value: currentValue)
        }
        
        // Fix the 24-hours-ago point
        if let yDate = calendar.date(byAdding: .hour, value: -24, to: today) {
            if let idx = points.firstIndex(where: {
                abs($0.date.timeIntervalSince(yDate)) < 1800
            }) {
                points[idx] = ChartPoint(date: yDate, value: yesterdayValue)
            }
        }
        
        return points
    }
    
    /// Paper Trading performers - returns sorted candidates for display
    private var paperTradingPerformanceCandidates: [(symbol: String, change: Double)] {
        let marketCoins = MarketViewModel.shared.allCoins
        return paperTradingHoldings
            .filter { !stablecoinSymbols.contains($0.symbol.uppercased()) }
            .map { holding -> (symbol: String, change: Double) in
                let change = marketCoins
                    .first(where: { $0.symbol.uppercased() == holding.symbol.uppercased() })?
                    .best24hPercent ?? 0
                return (symbol: holding.symbol, change: change)
            }
            .sorted { $0.change > $1.change } // Sort by change descending
    }
    
    /// Paper Trading top performer string (best 24h change among non-stablecoin holdings)
    private var paperTradingTopPerformerString: String {
        guard let top = paperTradingPerformanceCandidates.first else { return "--" }
        let sign = top.change >= 0 ? "+" : ""
        return "\(top.symbol) \(sign)\(String(format: "%.1f", top.change))%"
    }
    
    /// Paper Trading worst performer string (worst 24h change among non-stablecoin holdings)
    /// Returns "--" if there's only one non-stablecoin asset (same as top performer)
    private var paperTradingWorstPerformerString: String {
        let candidates = paperTradingPerformanceCandidates
        // Need at least 2 candidates to have a meaningful worst performer
        guard candidates.count >= 2, let worst = candidates.last else { return "--" }
        let sign = worst.change >= 0 ? "+" : ""
        return "\(worst.symbol) \(sign)\(String(format: "%.1f", worst.change))%"
    }
    
    /// Current display total (Paper Trading or regular)
    private var currentDisplayTotal: Double {
        if paperTradingManager.isPaperTradingEnabled {
            return paperTradingTotalValue
        }
        return portfolioVM.totalValue
    }
    
    var body: some View {
        ZStack {
            FuturisticBackground()
            
            overviewTab
        }
        .onAppear {
            // MEMORY FIX v7: Defer state mutations to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Sync displayedTotal immediately (lightweight)
                displayedTotal = portfolioVM.totalValue
                
                // Skip heavy cache initialization on tab switches after first load
                guard !didInitialDataLoad else { return }
                didInitialDataLoad = true
                
                // Initialize caches on first load only
                updateCachedHoldings()
                updateCachedPrices()
            }
        }
        .onDisappear {
            // No cleanup needed; subscriptions are tied to the VM lifecycle
        }
        // PERFORMANCE FIX v2: Consolidated onChange handlers with debouncing
        // Instead of 5 separate handlers each calling updateCachedHoldings() immediately,
        // we now use a debounced approach that batches rapid changes (e.g., typing in search)
        .onChange(of: sortMode) { _, _ in scheduleHoldingsUpdate() }
        .onChange(of: showOnlyFavorites) { _, _ in scheduleHoldingsUpdate() }
        .onChange(of: searchTerm) { _, _ in scheduleHoldingsUpdate() }
        .onChange(of: selectedAssetType) { _, _ in scheduleHoldingsUpdate() }
        .onChange(of: portfolioVM.holdings.count) { _, _ in scheduleHoldingsUpdate() }
        // FIX: Immediately update when stocks toggle changes (user expects instant feedback)
        .onChange(of: showStocksInPortfolio) { _, _ in
            // Clear cache and force immediate recomputation
            cachedDisplayedHoldings = []
            lastHoldingsCacheAt = .distantPast
            scheduleHoldingsUpdate()
        }
        .onChange(of: paperTradingManager.isPaperTradingEnabled) { _, _ in
            scheduleHoldingsUpdate()
            DispatchQueue.main.async { updateCachedPrices() }
        }
        .onChange(of: portfolioVM.totalValue) { _, newValue in
            // STARTUP FIX v25: Allow significant corrections during startup.
            // Previously blocked ALL updates for 4 seconds, showing stale portfolio total.
            let significantCorrection = displayedTotal > 0 ? abs(newValue - displayedTotal) / displayedTotal > 0.01 : newValue > 0
            
            if isInGlobalStartupPhase() && !significantCorrection { return }
            // PERFORMANCE FIX v2: Skip during scroll OR initialization phase
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() || significantCorrection else { return }
            // Update displayed total for regular portfolio mode
            guard !paperTradingManager.isPaperTradingEnabled else { return }
            DispatchQueue.main.async {
                if significantCorrection && isInGlobalStartupPhase() {
                    // During startup, update instantly without animation
                    displayedTotal = newValue
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        displayedTotal = newValue
                        shineTrigger.toggle()
                    }
                }
            }
        }
        .onChange(of: currentDisplayTotal) { _, newValue in
            // STARTUP FIX v25: Allow significant corrections during startup.
            let significantCorrection = lastTotalValue > 0 ? abs(newValue - lastTotalValue) / lastTotalValue > 0.01 : newValue > 0
            
            if isInGlobalStartupPhase() && !significantCorrection { return }
            // PERFORMANCE FIX v2: Skip during scroll OR initialization phase
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() || significantCorrection else { return }
            // Handle scale animation for both regular and paper trading modes
            DispatchQueue.main.async {
                let now = Date()
                let tooSoon = now.timeIntervalSince(lastTotalAnimationAt) < 0.4
                
                // Calculate change significance
                let delta = abs(newValue - lastTotalValue)
                let pctChange = delta / max(lastTotalValue, 1e-9)
                
                // Only animate scale if change is significant and not too frequent
                let shouldAnimateScale = !tooSoon && pctChange > 0.0001 && lastTotalValue > 0
                
                if shouldAnimateScale {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        totalValueScale = pctChange > 0.01 ? 1.018 : 1.01
                    }
                    
                    lastTotalAnimationAt = now
                    // Quick reset for snappier feel
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            totalValueScale = 1.0
                        }
                    }
                }
                
                lastTotalValue = newValue
            }
        }
        .sheet(isPresented: $showDeFiDashboard) {
            DeFiDashboardView()
        }
        .sheet(isPresented: $showTaxReport) {
            TaxReportView()
        }
        .navigationDestination(isPresented: $navigateToPaymentMethods) {
            PortfolioPaymentMethodsView(onStockAdded: { holding in
                portfolioVM.addStockHolding(holding)
            })
        }
        .navigationDestination(isPresented: $navigateToCSVImport) {
            CSVImportView().environmentObject(portfolioVM)
        }
        // Navigation to performer coin detail
        .navigationDestination(isPresented: Binding(
            get: { selectedPerformerCoin != nil },
            set: { if !$0 { selectedPerformerCoin = nil } }
        )) {
            if let coin = selectedPerformerCoin {
                CoinDetailView(coin: coin)
            } else {
                EmptyView()
            }
        }
        // Navigation to stock/commodity detail
        .navigationDestination(isPresented: Binding(
            get: { selectedStockHolding != nil },
            set: { if !$0 { selectedStockHolding = nil } }
        )) {
            if let stock = selectedStockHolding {
                // Route commodities to CommodityDetailView
                if stock.assetType == .commodity,
                   let info = CommoditySymbolMapper.getCommodity(for: stock.coinSymbol) {
                    CommodityDetailView(commodityInfo: info, holding: stock)
                        .environmentObject(portfolioVM)
                } else {
                    // Stocks and ETFs go to StockDetailView
                    StockDetailView(
                        ticker: stock.displaySymbol,
                        companyName: stock.displayName,
                        assetType: stock.assetType,
                        holding: stock
                    )
                }
            }
        }
        // Navigation to crypto holding detail
        .navigationDestination(isPresented: Binding(
            get: { selectedCryptoHolding != nil },
            set: { if !$0 { selectedCryptoHolding = nil } }
        )) {
            if let crypto = selectedCryptoHolding {
                // Try to find the coin in market data first
                if let coin = MarketViewModel.shared.allCoins.first(where: { $0.symbol.uppercased() == crypto.coinSymbol.uppercased() }) {
                    CoinDetailView(coin: coin)
                } else {
                    // Create a fallback MarketCoin from holding data
                    CoinDetailView(coin: MarketCoin(
                        id: crypto.coinSymbol.lowercased(),
                        symbol: crypto.coinSymbol,
                        name: crypto.coinName,
                        imageUrl: crypto.imageUrl.flatMap { URL(string: $0) },
                        priceUsd: crypto.currentPrice,
                        marketCap: nil,
                        totalVolume: nil,
                        priceChangePercentage1hInCurrency: nil,
                        priceChangePercentage24hInCurrency: crypto.dailyChange,
                        priceChangePercentage7dInCurrency: nil,
                        sparklineIn7d: [],
                        marketCapRank: nil,
                        maxSupply: nil,
                        circulatingSupply: nil,
                        totalSupply: nil
                    ))
                }
            } else {
                EmptyView()
            }
        }
        .preferredColorScheme(AppTheme.currentColorScheme)
        .navigationBarHidden(true)
        // Pop-to-root: Clear detail views when Portfolio tab is tapped while already on Portfolio
        // This handles the case where NavigationPath is reset but legacy NavigationLink states aren't
        .onChange(of: appState.portfolioNavPath) { _, newPath in
            // If nav path is now empty (user tapped Portfolio tab to return to root)
            // but we still have a detail view selected, clear all selections
            if newPath.isEmpty {
                DispatchQueue.main.async {
                    if selectedPerformerCoin != nil { selectedPerformerCoin = nil }
                    if selectedStockHolding != nil { selectedStockHolding = nil }
                    if selectedCryptoHolding != nil { selectedCryptoHolding = nil }
                    if navigateToPaymentMethods { navigateToPaymentMethods = false }
                }
            }
        }
    }
}

// MARK: - PortfolioView Subviews
extension PortfolioView {
    
    /// Returns true when we should show the empty state (no special mode AND no holdings)
    private var shouldShowEmptyState: Bool {
        !demoModeManager.isDemoMode && !paperTradingManager.isPaperTradingEnabled && portfolioVM.holdings.isEmpty
    }
    
    private var overviewTab: some View {
        GeometryReader { geometry in
            // FIX: Guard against zero-frame GeometryReader on LazyView cold start
            // This can happen when the app returns from background after a long period
            // and LazyView initializes PortfolioView - the first layout pass may return zero size
            let hasValidFrame = geometry.size.width > 0 && geometry.size.height > 0
            
            if hasValidFrame || didCompleteInitialLayout {
                ScrollView(showsIndicators: false) {
                    if shouldShowEmptyState {
                        // Show empty state when demo mode is off and no real holdings
                        VStack {
                            Spacer()
                                .frame(minHeight: 60, maxHeight: 120)
                            
                            PortfolioEmptyStateView(
                                onConnectExchange: {
                                    navigateToPaymentMethods = true
                                },
                                onEnableDemo: {
                                    demoModeManager.enableDemoMode()
                                    portfolioVM.enableDemoMode()
                                },
                                onEnablePaperTrading: {
                                    paperTradingManager.enablePaperTrading()
                                },
                                onImportCSV: {
                                    navigateToCSVImport = true
                                }
                            )
                            
                            Spacer()
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        VStack(spacing: 6) {
                            headerCard
                            PortfolioChartView(
                                portfolioVM: portfolioVM,
                                showMetrics: false,
                                showSelector: true,
                                chartMode: chartModeBinding,
                                overrideAllocationData: paperTradingManager.isPaperTradingEnabled ? paperTradingAllocationData : nil,
                                overrideTotalValue: paperTradingManager.isPaperTradingEnabled ? paperTradingTotalValue : nil,
                                overrideHistory: paperTradingManager.isPaperTradingEnabled ? paperTradingChartHistory : nil
                            )
                            .padding(.horizontal, 16)
                            
                            // Open Orders Widget - shows pending limit orders
                            OpenOrdersWidget()
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            
                            // My Bots Widget - shows bot status summary
                            MyBotsWidget()
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                            
                            // DeFi & Tax Quick Access
                            portfolioQuickActions
                            
                            holdingsSection
                            connectExchangesSection
                        }
                        .frame(width: geometry.size.width) // Lock to screen width
                        .padding(.bottom, 24)
                    }
                }
                // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + KVO tracking
                .withUIKitScrollBridge()
                .refreshable {
                    portfolioVM.manualRefresh()
                }
                .onAppear {
                    // Mark initial layout as complete once we have a valid frame
                    if hasValidFrame && !didCompleteInitialLayout {
                        DispatchQueue.main.async {
                            didCompleteInitialLayout = true
                        }
                    }
                }
            } else {
                // FIX: Show a loading placeholder while waiting for valid geometry
                // This prevents blank screen bug on cold start
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(DS.Colors.gold)
                    Text("Loading Portfolio...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    // Force a layout refresh after a brief delay
                    // This ensures the GeometryReader gets recalculated
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if !didCompleteInitialLayout {
                            didCompleteInitialLayout = true
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Header Card Components

    private var headerCard: some View {
        ZStack {
            headerBackground
            headerContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .contextMenu {
            Button(hideBalances ? "Show Amounts" : "Hide Amounts") {
                hideBalances.toggle()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Portfolio Summary")
        .accessibilityValue("Total value \(hideBalances ? "hidden" : NumberFormatter.currencyFormatter.string(from: NSNumber(value: displayedTotal)) ?? ""). 24 hour change \(portfolioVM.dailyChangePercentString). Total P L \(hideBalances ? "hidden" : portfolioVM.unrealizedPLString).")
    }

    private var headerBackground: some View {
        let isDark = colorScheme == .dark
        let plColor = portfolioVM.unrealizedPL >= 0 ? Color.green : Color.red
        
        let goldColor = Color(red: 0.85, green: 0.65, blue: 0.13)
        return RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: isDark ? [
                        Color.white.opacity(0.08),
                        Color.black.opacity(0.3)
                    ] : [
                        Color(red: 1.0, green: 0.995, blue: 0.98),
                        Color(red: 0.96, green: 0.97, blue: 0.98)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                // Top highlight for glass effect (matches chart card)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.8), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .animation(.easeInOut(duration: 0.3), value: portfolioVM.unrealizedPL)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: isDark
                                ? [goldColor.opacity(0.25), goldColor.opacity(0.08)]
                                : [goldColor.opacity(0.3), goldColor.opacity(0.12)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }

    private var headerContent: some View {
        HStack(alignment: .center, spacing: 8) {
            metricsVStack
                .layoutPriority(1) // Allow metrics to compress if needed
            
            Spacer(minLength: 4)
            
            chartSection
                .frame(width: 110) // Slightly smaller to give metrics more room on iPhone 17 Pro
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
    }

    /// Check if live trading mode is active (developer only)
    private var isLiveTradingMode: Bool {
        SubscriptionManager.shared.isDeveloperMode && 
        SubscriptionManager.shared.developerLiveTradingEnabled
    }
    
    /// Current app trading mode for the Portfolio tab (mirrors HomeHeaderBar logic)
    private var currentAppMode: AppTradingMode {
        if paperTradingManager.isPaperTradingEnabled { return .paper }
        if demoModeManager.isDemoMode { return .demo }
        if isLiveTradingMode { return .liveTrading }
        return .portfolio
    }
    
    private var metricsVStack: some View {
        let isDark = colorScheme == .dark
        
        return VStack(alignment: .leading, spacing: 4) {
            // Total Value - consistent rounded typography
            Group {
                if hideBalances {
                    Text("$••••••••")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                } else if paperTradingManager.isPaperTradingEnabled {
                    Text(MarketFormat.price(paperTradingTotalValue))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .scaleEffect(totalValueScale)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: paperTradingTotalValue)
                } else {
                    shiningTotal
                }
            }
            .foregroundColor(DS.Adaptive.textPrimary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .allowsTightening(true)
            
            // "Total Value" label with COMPACT MODE INDICATORS - unified ModeBadge
            HStack(spacing: 6) {
                Text("Total Value")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.2, green: 0.75, blue: 0.45))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                
                // Shared compact mode badge — colors sourced from AppTradingMode (single source of truth)
                if paperTradingManager.isPaperTradingEnabled {
                    ModeBadge(mode: .paper, variant: .compact) {
                        paperTradingManager.disablePaperTrading()
                    }
                } else if demoModeManager.isDemoMode {
                    ModeBadge(mode: .demo, variant: .compact) {
                        demoModeManager.disableDemoMode()
                        portfolioVM.disableDemoMode()
                    }
                } else if isLiveTradingMode {
                    ModeBadge(mode: .liveTrading, variant: .compact) {
                        SubscriptionManager.shared.developerLiveTradingEnabled = false
                    }
                }
                
                // STALENESS INDICATOR: Show clock icon when prices are stale (>30s old)
                if portfolioVM.arePricesStale && !paperTradingManager.isPaperTradingEnabled && !demoModeManager.isDemoMode {
                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .medium))
                        if let desc = portfolioVM.lastUpdateDescription {
                            Text(desc)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                    }
                    .foregroundColor(.orange.opacity(0.8))
                    .help("Prices may be outdated")
                }
            }
            
            // P&L Section
            if paperTradingManager.isPaperTradingEnabled {
                HStack(spacing: 14) {
                    // P&L Percentage
                    VStack(alignment: .leading, spacing: 2) {
                        Text("P&L")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        (hideBalances ? Text("••••") : Text(String(format: "%@%.2f%%", paperTradingProfitLoss >= 0 ? "+" : "", paperTradingProfitLossPercent)))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(paperTradingProfitLoss >= 0 ? .green : .red)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.25), value: paperTradingProfitLossPercent)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    // Total P&L Value
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total P&L")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        (hideBalances ? Text("$••••••") : Text(String(format: "%@%@", paperTradingProfitLoss >= 0 ? "+" : "", MarketFormat.price(abs(paperTradingProfitLoss)))))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(paperTradingProfitLoss >= 0 ? .green : .red)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.25), value: paperTradingProfitLoss)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Spacer()
                }
                .padding(.top, 6)
            } else {
                // Regular portfolio metrics - matches home page by showing selected timeframe change
                HStack(spacing: 14) {
                    // Selected Timeframe Change (consistent with home page)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(selectedRangeLabelFull) Change")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        if hideBalances {
                            Text("••••")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        } else {
                            let pct = selectedRangeChangePercent
                            let sign = pct >= 0 ? "+" : ""
                            Text("\(sign)\(String(format: "%.2f", pct))%")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(pct >= 0 ? .green : .red)
                                .contentTransition(.numericText())
                                .animation(.easeOut(duration: 0.25), value: pct)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    
                    // Total P&L (cost-basis based - different from time-based change)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total P&L")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(isDark ? .white.opacity(0.5) : .secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        (hideBalances ? Text("$••••") : Text(portfolioVM.unrealizedPLString))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(portfolioVM.unrealizedPL >= 0 ? .green : .red)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.25), value: portfolioVM.unrealizedPL)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Spacer()
                }
                .padding(.top, 6)
            }
        }
        .padding(.leading, 16)
    }

    private var shiningTotal: some View {
        let isDark = colorScheme == .dark
        let text = Text(displayedTotal, format: .currency(code: CurrencyManager.currencyCode))
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundColor(DS.Adaptive.textPrimary)
        return text
            .overlay(
                LinearGradient(
                    colors: [.clear, (isDark ? Color.white : Color.black).opacity(0.35), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                    .rotationEffect(.degrees(18))
                    .offset(x: shineTrigger ? 140 : -140)
                    .mask(text)
            )
            .scaleEffect(totalValueScale)
            .contentTransition(.numericText())
            .animation(.spring(response: 0.3, dampingFraction: 0.78), value: displayedTotal)
            .animation(.easeInOut(duration: 0.85), value: shineTrigger)
    }
    
    // MARK: - Compact Mode Pill (replaced by shared ModeBadge)
    // The compactModePill function has been replaced by ModeBadge(mode:variant:onTap:)
    // from EmptyStateViews.swift for consistent styling across the app.

    // MARK: - Legacy badges removed
    // liveTradingBadge and compactModePill replaced by shared ModeBadge from EmptyStateViews.swift
    
    // MARK: - Chart Subsections

    @ViewBuilder
    private var chartSection: some View {
        // Both views are always in the tree to maintain a stable frame.
        // Opacity + subtle scale crossfade; no .animation() modifier to avoid
        // unintended animations when child data (prices, performers) changes.
        // All mode-change animations come from withAnimation on the toggle/tap.
        ZStack {
            miniPieView
                .opacity(chartMode == .line ? 1 : 0)
                .scaleEffect(chartMode == .line ? 1 : 0.88)
                .allowsHitTesting(chartMode == .line)

            performanceSection
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Fill the ZStack uniformly
                .opacity(chartMode == .pie ? 1 : 0)
                .scaleEffect(chartMode == .pie ? 1 : 0.88)
                .allowsHitTesting(chartMode == .pie)
        }
        .frame(height: 115) // Matches mini pie; performer cards are constrained to same box
        .clipped() // Prevent any overflow during scale animations
    }

    private var performanceSection: some View {
        let isDark = colorScheme == .dark
        
        // Use paper trading or regular performer strings based on mode
        let topString = paperTradingManager.isPaperTradingEnabled 
            ? paperTradingTopPerformerString 
            : portfolioVM.topPerformerString
        let worstString = paperTradingManager.isPaperTradingEnabled 
            ? paperTradingWorstPerformerString 
            : portfolioVM.worstPerformerString
        
        // Parse symbol and change from the formatted strings (e.g., "BTC +4.2%")
        let topParts = topString.split(separator: " ")
        let worstParts = worstString.split(separator: " ")
        let topSymbol = topParts.first.map(String.init) ?? "--"
        let topChange = topParts.dropFirst().joined(separator: " ")
        let worstSymbol = worstParts.first.map(String.init) ?? "--"
        let worstChange = worstParts.dropFirst().joined(separator: " ")
        
        let hasTopPerformer = topSymbol != "--"
        let hasWorstPerformer = worstSymbol != "--"

        return VStack(spacing: 8) {
            // Top Performer Card
            if hasTopPerformer {
                performerCard(
                    label: "Top",
                    symbol: topSymbol,
                    change: topChange,
                    isPositive: !topChange.contains("-"),
                    isDark: isDark
                )
            }
            
            // Worst Performer Card
            if hasWorstPerformer {
                performerCard(
                    label: "Worst",
                    symbol: worstSymbol,
                    change: worstChange,
                    isPositive: !worstChange.contains("-"),
                    isDark: isDark
                )
            }
            
            // Empty state with icon
            if !hasTopPerformer && !hasWorstPerformer {
                performanceEmptyState(isDark: isDark)
            }
        }
    }
    
    /// Premium styled performer card - compact design for the header section
    /// Layout: [Coin Icon] [Symbol/Label] [Arrow+Change%]
    /// Enhanced with performance-colored accents and refined visual hierarchy
    @ViewBuilder
    private func performerCard(
        label: String,
        symbol: String,
        change: String,
        isPositive: Bool,
        isDark: Bool
    ) -> some View {
        let accentColor = isPositive ? Color.green : Color.red
        let accentGlow = accentColor.opacity(isDark ? 0.15 : 0.08)
        
        Button {
            navigateToPerformer(symbol: symbol)
        } label: {
            HStack(spacing: 6) {
                // Coin logo with performance-colored ring
                ZStack {
                    // Colored glow behind logo
                    Circle()
                        .fill(accentColor.opacity(isDark ? 0.25 : 0.15))
                        .frame(width: 26, height: 26)
                    
                    CoinImageView(
                        symbol: symbol,
                        url: getCoinImageURL(symbol),
                        size: 20
                    )
                    .background(
                        Circle()
                            .fill(isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.9))
                    )
                    .overlay(
                        Circle()
                            .stroke(accentColor.opacity(isDark ? 0.6 : 0.45), lineWidth: 1.5)
                    )
                }
                .frame(width: 24, height: 24)
                
                // Symbol and label stacked - fixed size to prevent wrapping
                VStack(alignment: .leading, spacing: 1) {
                    Text(symbol)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(label)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(isDark ? .white.opacity(0.55) : .secondary)
                }
                .fixedSize(horizontal: true, vertical: false) // CRITICAL: Prevent text wrapping
                
                // Change percentage with arrow - always show full text
                HStack(spacing: 2) {
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                    Text(change)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundColor(accentColor)
                .fixedSize(horizontal: true, vertical: false) // CRITICAL: Never truncate change %
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    // Base fill
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isDark
                                    ? [Color.white.opacity(0.09), Color.white.opacity(0.05)]
                                    : [DS.Adaptive.cardBackground, DS.Adaptive.cardBackground.opacity(0.90)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Performance-colored inner glow from left
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [accentGlow, Color.clear],
                                center: .leading,
                                startRadius: 0,
                                endRadius: 100
                            )
                        )
                    
                    // Top highlight for glass effect
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.55),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: isDark
                                ? [accentColor.opacity(0.35), Color.white.opacity(0.10)]
                                : [accentColor.opacity(0.25), DS.Adaptive.stroke.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PerformerCardButtonStyle())
    }
    
    /// Empty state for performance section - compact vertical layout for the 130pt header slot
    @ViewBuilder
    private func performanceEmptyState(isDark: Bool) -> some View {
        let inPaperMode = paperTradingManager.isPaperTradingEnabled
        let title = inPaperMode ? "No Positions Yet" : "Add Holdings"
        let subtitle = inPaperMode ? "Paper cash ready - open a trade" : "Connect exchange or import"
        let iconName = inPaperMode ? "bolt.horizontal.circle.fill" : "chart.line.uptrend.xyaxis"
        let actionLabel = inPaperMode ? "Open Trade" : "Add Now"
        let accent = inPaperMode ? Color.green : DS.Adaptive.gold

        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            if inPaperMode {
                appState.selectedTab = .trade
            } else {
                navigateToPaymentMethods = true
            }
        } label: {
            VStack(spacing: 6) {
                // Icon
                ZStack {
                    Circle()
                        .fill(accent.opacity(isDark ? 0.20 : 0.12))
                        .frame(width: 32, height: 32)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isDark
                                    ? [Color.white.opacity(0.15), Color.white.opacity(0.08)]
                                    : [Color.white.opacity(0.9), Color.white.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isDark ? AnyShapeStyle(accent) : AnyShapeStyle(accent))
                }
                
                // Text - centered for compact vertical layout
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Text(subtitle)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    HStack(spacing: 4) {
                        Text(actionLabel)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(accent.opacity(0.95))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(accent.opacity(0.85))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(accent.opacity(isDark ? 0.18 : 0.12))
                            .overlay(
                                Capsule()
                                    .stroke(accent.opacity(0.35), lineWidth: 0.8)
                            )
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.06) : DS.Adaptive.cardBackground.opacity(0.8))
                    
                    // Subtle directional accent glow
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(isDark ? 0.14 : 0.08),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Top highlight
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.5),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: isDark
                                ? [accent.opacity(0.35), Color.white.opacity(0.08)]
                                : [accent.opacity(0.20), DS.Adaptive.stroke.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PerformerCardButtonStyle())
    }
    
    /// Helper to get coin image URL from either paper trading or regular portfolio
    private func getCoinImageURL(_ symbol: String) -> URL? {
        // First try market data (most complete source)
        if let coin = MarketViewModel.shared.allCoins.first(where: {
            $0.symbol.uppercased() == symbol.uppercased()
        }) {
            return coin.imageUrl
        }
        
        // Fallback to portfolio holdings
        if let holding = portfolioVM.holdings.first(where: {
            $0.coinSymbol.uppercased() == symbol.uppercased()
        }), let urlString = holding.imageUrl {
            return URL(string: urlString)
        }
        
        return nil
    }
    
    /// Navigate to coin detail for a performer symbol
    private func navigateToPerformer(symbol: String) {
        guard symbol != "--" else { return }
        
        // Find the coin in market data
        if let coin = MarketViewModel.shared.allCoins.first(where: { 
            $0.symbol.uppercased() == symbol.uppercased() 
        }) {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            selectedPerformerCoin = coin
        }
    }
    
    private var miniPieView: some View {
        // Compact pie that lives in the header when line mode is active.
        // Shows total value in center with adaptive font sizing for small charts.
        ThemedPortfolioPieChartView(
            portfolioVM: portfolioVM,
            showLegend: .constant(false),
            allowRotation: false,
            allowSweepOscillation: false,
            showSweepIndicator: false,
            allowHoverScrub: false,
            overrideAllocationData: paperTradingManager.isPaperTradingEnabled ? paperTradingAllocationData : nil,
            overrideTotalValue: paperTradingManager.isPaperTradingEnabled ? paperTradingTotalValue : nil,
            centerMode: .normal,  // Show total value in center with adaptive font sizing
            onSelectSymbol: nil,
            onActivateSymbol: nil,
            onUpdateColors: nil
        )
        .frame(width: 115, height: 115)
        .accessibilityLabel(Text("Portfolio allocation mini pie"))
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping the mini pie switches to full pie mode
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                chartMode = .pie
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }
    
    // MARK: - DeFi & Tax Quick Actions
    
    private var portfolioQuickActions: some View {
        let isDark = colorScheme == .dark
        
        return HStack(spacing: 12) {
            // DeFi Dashboard button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showDeFiDashboard = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.purple)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DeFi")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text("Wallets & NFTs")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.purple.opacity(isDark ? 0.12 : 0.06),
                                        Color.purple.opacity(isDark ? 0.04 : 0.02),
                                        Color.clear
                                    ],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 80
                                )
                            )
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(isDark ? 0.05 : 0.20), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [Color.purple.opacity(isDark ? 0.30 : 0.20), Color.purple.opacity(isDark ? 0.10 : 0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isDark ? 1 : 1.2
                        )
                )
            }
            .buttonStyle(.plain)
            
            // Tax Report button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showTaxReport = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tax")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text("Reports")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.green.opacity(isDark ? 0.12 : 0.06),
                                        Color.green.opacity(isDark ? 0.04 : 0.02),
                                        Color.clear
                                    ],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 80
                                )
                            )
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(isDark ? 0.05 : 0.20), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [Color.green.opacity(isDark ? 0.30 : 0.20), Color.green.opacity(isDark ? 0.10 : 0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isDark ? 1 : 1.2
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    private var holdingsSection: some View {
        // Use unified holdings list for both Paper Trading and regular modes
        let holdingsToDisplay = paperTradingManager.isPaperTradingEnabled 
            ? paperTradingAsHoldings 
            : displayedHoldings
        
        let iconColor = DS.Adaptive.textSecondary
        let iconBg = DS.Adaptive.overlay(0.06)
        let iconStroke = DS.Adaptive.stroke
        
        // Check if we have mixed assets (only when stocks feature is enabled)
        // Include commodities (precious metals) in the mixed asset check
        let hasCrypto = portfolioVM.hasCrypto
        let hasSecurities = showStocksInPortfolio && portfolioVM.hasSecurities
        let hasCommodities = portfolioVM.hasCommodities
        // Show asset breakdown if we have any combination of different asset types
        let hasMixedAssets = (hasCrypto && hasSecurities) || (hasCrypto && hasCommodities) || (hasSecurities && hasCommodities)
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Holdings")
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .font(.headline)
                
                // Asset value breakdown (only show if stocks enabled AND mixed assets)
                if showStocksInPortfolio && hasMixedAssets && !paperTradingManager.isPaperTradingEnabled {
                    HStack(spacing: 8) {
                        assetValueBadge(type: .crypto, value: portfolioVM.cryptoValue)
                        assetValueBadge(type: .stock, value: portfolioVM.securitiesValue)
                        // Show commodity badge if user has precious metals
                        if portfolioVM.commodityValue > 0 {
                            assetValueBadge(type: .commodity, value: portfolioVM.commodityValue)
                        }
                    }
                }
                
                Spacer()
                
                // Polished icon button group
                HStack(spacing: 6) {
                    // Favorites filter (only for regular holdings, not Paper Trading)
                    if !paperTradingManager.isPaperTradingEnabled {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showOnlyFavorites.toggle() }
                        } label: {
                            Image(systemName: showOnlyFavorites ? "star.fill" : "star")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(showOnlyFavorites ? .yellow : iconColor)
                                .frame(width: 30, height: 30)
                                .background(
                                    Circle()
                                        .fill(showOnlyFavorites ? Color.yellow.opacity(0.12) : iconBg)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(showOnlyFavorites ? Color.yellow.opacity(0.3) : iconStroke, lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Inline Sort picker
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        showSortPicker = true
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(iconColor)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(iconBg)
                            )
                            .overlay(
                                Circle()
                                    .stroke(iconStroke, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showSortPicker, arrowEdge: .bottom) {
                        HoldingsSortPicker(isPresented: $showSortPicker, selection: $sortMode)
                            .presentationCompactAdaptation(.popover)
                    }
                    
                    // Search toggle - consistent with Market/News pages
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            showSearchBar.toggle()
                            if !showSearchBar {
                                isSearchFocused = false
                                if !searchTerm.isEmpty {
                                    searchTerm = ""
                                }
                            }
                        }
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    } label: {
                        Image(systemName: showSearchBar ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(showSearchBar ? DS.Adaptive.gold : DS.Adaptive.textSecondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            
            if showSearchBar {
                HStack(spacing: 10) {
                    // Search icon
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                    
                    // UIKit-backed text field for reliable keyboard focus
                    SearchTextField(
                        text: $searchTerm,
                        placeholder: "Search holdings...",
                        autoFocus: true,
                        onTextChange: { newText in
                            searchTerm = newText
                        },
                        onSubmit: {
                            // Dismiss keyboard on submit
                            UIApplication.shared.dismissKeyboard()
                            isSearchFocused = false
                        },
                        onEditingChanged: { focused in
                            isSearchFocused = focused
                        }
                    )
                    .frame(height: 36)
                    
                    if !searchTerm.isEmpty {
                        Button {
                            searchTerm = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(DS.Adaptive.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DS.Adaptive.chipBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(isSearchFocused ? DS.Adaptive.gold.opacity(0.5) : DS.Adaptive.stroke, lineWidth: 1)
                        )
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showSearchBar)
            }
            
            // Asset type filter pills (only show when stocks feature is enabled AND not in Paper Trading)
            if showStocksInPortfolio && !paperTradingManager.isPaperTradingEnabled {
                assetTypeFilterPills
            }
            
            // Empty state for stocks filter when no stocks exist
            if selectedAssetType == .stock && holdingsToDisplay.isEmpty && !paperTradingManager.isPaperTradingEnabled {
                stocksEmptyStateView
            } else {
                // Unified holdings list using PortfolioCoinRow for both modes
                LazyVStack(spacing: 0) {
                    ForEach(Array(holdingsToDisplay.enumerated()), id: \.element.id) { index, holding in
                        VStack(spacing: 0) {
                            PortfolioCoinRow(viewModel: portfolioVM, holding: holding) { tappedHolding in
                                // Navigate to appropriate detail view based on asset type
                                if tappedHolding.assetType == .stock || tappedHolding.assetType == .etf || tappedHolding.assetType == .commodity {
                                    selectedStockHolding = tappedHolding
                                } else {
                                    selectedCryptoHolding = tappedHolding
                                }
                            }
                            .padding(.horizontal, 16)
                            .contextMenu {
                                // View Details - navigate to appropriate detail view
                                Button {
                                    if holding.assetType == .stock || holding.assetType == .etf || holding.assetType == .commodity {
                                        selectedStockHolding = holding
                                    } else {
                                        selectedCryptoHolding = holding
                                    }
                                } label: {
                                    Label(
                                        holding.assetType == .crypto ? "Coin Details" : "\(holding.assetType.displayName) Details",
                                        systemImage: "chart.line.uptrend.xyaxis"
                                    )
                                }
                                
                                Divider()
                                
                                Button("Rebalance to target…") { }
                                Button("View on Market") { }
                                
                                Divider()
                                
                                // Context menu only for regular holdings (not Paper Trading)
                                if !paperTradingManager.isPaperTradingEnabled {
                                    Button {
                                        portfolioVM.toggleFavorite(holding)
                                    } label: {
                                        Label(holding.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                              systemImage: holding.isFavorite ? "star.slash" : "star.fill")
                                    }
                                    
                                    Divider()
                                    
                                    Button(role: .destructive) {
                                        if let index = portfolioVM.holdings.firstIndex(where: { $0.id == holding.id }) {
                                            portfolioVM.removeHolding(at: IndexSet(integer: index))
                                        }
                                    } label: {
                                        Label("Remove Holding", systemImage: "trash")
                                    }
                                }
                            }
                            
                            // Subtle separator between rows (not after last item)
                            if index < holdingsToDisplay.count - 1 {
                                Rectangle()
                                    .fill(DS.Adaptive.divider)
                                    .frame(height: 1)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 6)
                            }
                        }
                        // PERFORMANCE FIX: Disable animations during scroll for smooth 60fps
                        .transaction { $0.animation = nil }
                        .animation(.none, value: holding.id)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Stocks Empty State View
    
    private var stocksEmptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 30)
            
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No Stocks Yet")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Add stocks and ETFs to track your\nfull investment portfolio")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            
            // CTA Button
            Button {
                navigateToPaymentMethods = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Add Stocks")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
            
            // Hint
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text("Track only — no trading supported")
                    .font(.caption2)
            }
            .foregroundColor(DS.Adaptive.textTertiary)
            
            Spacer()
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Asset Type Filter Pills
    
    private var assetTypeFilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All filter
                assetFilterPill(type: nil, label: "All", isSelected: selectedAssetType == nil)
                
                // Crypto filter
                assetFilterPill(type: .crypto, label: "Crypto", isSelected: selectedAssetType == .crypto)
                
                // Stocks filter (only show if there are stocks or as option to add)
                assetFilterPill(type: .stock, label: "Stocks", isSelected: selectedAssetType == .stock)
                
                // Commodities filter (precious metals from Coinbase)
                assetFilterPill(type: .commodity, label: "Metals", isSelected: selectedAssetType == .commodity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    @ViewBuilder
    private func assetFilterPill(type: AssetType?, label: String, isSelected: Bool) -> some View {
        let color: Color = type?.color ?? .gray
        
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedAssetType = type
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            HStack(spacing: 4) {
                if let assetType = type {
                    Image(systemName: assetType.icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? (type == nil ? DS.Adaptive.textPrimary : .white) : DS.Adaptive.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? (type == nil ? DS.Adaptive.chipBackgroundActive : color) : DS.Adaptive.chipBackground)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? (type == nil ? DS.Adaptive.strokeStrong : color.opacity(0.5)) : DS.Adaptive.stroke, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
    
    // PERFORMANCE FIX: Cached formatter — avoids allocating NumberFormatter per badge render
    private static let _badgeCurrencyFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf
    }()

    private func assetValueBadge(type: AssetType, value: Double) -> some View {
        let valueStr = Self._badgeCurrencyFormatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
        
        return HStack(spacing: 3) {
            Image(systemName: type.icon)
                .font(.system(size: 8))
            Text(valueStr)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(type.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(type.color.opacity(0.15))
        )
    }
    
    private var connectExchangesSection: some View {
        let isDark = colorScheme == .dark
        let accentGreen = Color(red: 0.2, green: 0.85, blue: 0.65)
        let accentBlue = Color(red: 0.3, green: 0.5, blue: 0.95)
        // LIGHT MODE FIX: Darker accent colors for light backgrounds
        let lightAccentGreen = Color(red: 0.10, green: 0.60, blue: 0.45)
        let lightAccentBlue = Color(red: 0.20, green: 0.38, blue: 0.80)
        
        return HStack(spacing: 12) {
            Button {
                linkExchanges()
            } label: {
                HStack(spacing: 10) {
                    // Gradient icon
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isDark
                                    ? [accentGreen, accentBlue]
                                    : [lightAccentGreen, lightAccentBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // LIGHT MODE FIX: White text was invisible on light background.
                    // Now uses dark teal-blue text in light mode for clear readability.
                    Text("Connect Exchanges & Wallets")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isDark ? .white : Color(red: 0.12, green: 0.42, blue: 0.52))
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .background(
                    ZStack {
                        // Gradient fill - more visible in light mode
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: isDark
                                        ? [accentGreen.opacity(0.2), accentBlue.opacity(0.15)]
                                        : [accentGreen.opacity(0.12), accentBlue.opacity(0.08)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        // Glass effect
                        Capsule(style: .continuous)
                            .fill(isDark ? DS.Adaptive.chipBackground : Color(red: 0.96, green: 0.99, blue: 0.98))
                    }
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isDark
                                    ? [accentGreen.opacity(0.5), accentBlue.opacity(0.3)]
                                    : [lightAccentGreen.opacity(0.45), lightAccentBlue.opacity(0.30)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isDark ? 1.5 : 1.2
                        )
                )
            }
            .buttonStyle(ScaleButtonStyle())
            
            // Info button - LIGHT MODE FIX: Was invisible (white on white)
            Button {
                showTooltip.toggle()
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        isDark
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.white.opacity(0.3)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            : AnyShapeStyle(LinearGradient(
                                colors: [Color.black.opacity(0.30), Color.black.opacity(0.20)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    )
            }
            .popover(isPresented: $showTooltip) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Link Your Accounts")
                        .font(.headline)
                        .foregroundColor(isDark ? .white : DS.Adaptive.textPrimary)
                    Text("Connect exchanges and wallets to track your portfolio and trade seamlessly from within the app.")
                        .font(.subheadline)
                        .foregroundColor(isDark ? .white.opacity(0.8) : DS.Adaptive.textSecondary)
                }
                .padding()
                .background(isDark ? Color.black.opacity(0.95) : DS.Adaptive.cardBackground)
                .cornerRadius(12)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    // Link exchanges function
    private func linkExchanges() {
        // Navigate to the PortfolioPaymentMethodsView using push navigation
        navigateToPaymentMethods = true
    }
}

// MARK: - Paper Trading Balance Row
/// A row component for displaying Paper Trading balance for a single asset
private struct PaperTradingBalanceRow: View {
    let symbol: String
    let amount: Double
    let value: Double
    let percent: Double
    let hideBalances: Bool
    
    // Cache the image URL to prevent recalculation on every render
    @State private var cachedImageURL: URL? = nil
    @State private var hasInitialized: Bool = false
    
    private var formattedAmount: String {
        if amount >= 1 {
            return String(format: "%.4f", amount)
        } else if amount >= 0.0001 {
            return String(format: "%.6f", amount)
        } else {
            return String(format: "%.8f", amount)
        }
    }
    
    /// Get coin name from symbol for display
    private var coinName: String {
        CoinNameMapping.name(for: symbol)
    }
    
    /// Compute coin image URL from market data
    private func computeImageURL() -> URL? {
        let marketCoins = MarketViewModel.shared.allCoins
        if let coin = marketCoins.first(where: { $0.symbol.uppercased() == symbol.uppercased() }) {
            return coin.imageUrl
        }
        return nil
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Asset icon - use CoinImageView with stable cached URL
            CoinImageView(symbol: symbol, url: cachedImageURL, size: 40)
                .transaction { $0.disablesAnimations = true }
            
            // Asset info
            VStack(alignment: .leading, spacing: 2) {
                Text(coinName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                if hideBalances {
                    Text("••••••")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(formattedAmount) \(symbol)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Value and allocation
            VStack(alignment: .trailing, spacing: 2) {
                if hideBalances {
                    Text("$••••••")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .monospacedDigit()
                } else {
                    Text(MarketFormat.price(value))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
                
                Text(String(format: "%.1f%%", percent))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 10)
        .onAppear {
            // Cache the image URL on first appear to prevent flashing
            if !hasInitialized {
                cachedImageURL = computeImageURL()
                hasInitialized = true
            }
        }
    }
    
    /// Get a color for Paper Trading assets (kept for potential future use)
    private func colorForAsset(_ asset: String) -> Color {
        let colorMap: [String: Color] = [
            "BTC": Color(red: 0.96, green: 0.62, blue: 0.07),
            "ETH": Color(red: 0.39, green: 0.47, blue: 0.82),
            "SOL": Color(red: 0.47, green: 0.87, blue: 0.87),
            "XRP": Color(red: 0.13, green: 0.13, blue: 0.13),
            "BNB": Color(red: 0.95, green: 0.77, blue: 0.06),
            "USDT": Color(red: 0.15, green: 0.63, blue: 0.48),
            "USDC": Color(red: 0.24, green: 0.48, blue: 0.96),
            "USD": Color(red: 0.18, green: 0.80, blue: 0.44),
            "DOGE": Color(red: 0.78, green: 0.62, blue: 0.21),
            "ADA": Color(red: 0.00, green: 0.20, blue: 0.55)
        ]
        return colorMap[asset.uppercased()] ?? .gray
    }
}

private extension NumberFormatter {
    static let currencyFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf
    }()
}

// MARK: - Seeded Random Number Generator for Paper Trading
/// A simple seeded random number generator for consistent chart data within a session.
/// Uses a linear congruential generator (LCG) algorithm.
private struct PaperTradingRNG: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed == 0 ? 1 : seed  // Avoid zero seed
    }
    
    mutating func next() -> UInt64 {
        // LCG parameters (same as glibc)
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - Performer Card Button Style
/// Custom button style for performer cards with subtle scale animation
private struct PerformerCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview
struct PortfolioView_Previews: PreviewProvider {
    static var previews: some View {
        PortfolioView()
            .environmentObject(HomeViewModel())
            .preferredColorScheme(.dark)
    }
}

