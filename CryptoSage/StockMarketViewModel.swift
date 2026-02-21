//
//  StockMarketViewModel.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/20/26.
//  View model for stock market browsing, indices, and market movers.
//  Uses Yahoo Finance as the primary data source (no API key required).
//

import Foundation
import Combine
import SwiftUI

// MARK: - Market Segment

/// Segments for filtering stocks in the market view
enum StockMarketSegment: String, CaseIterable, Identifiable {
    case all = "All"
    case sp500 = "S&P 500"
    case nasdaq100 = "Nasdaq 100"
    case dowJones = "Dow Jones"
    case etfs = "ETFs"
    case commodities = "Commodities"
    case gainers = "Gainers"
    case losers = "Losers"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .sp500: return "chart.bar.fill"
        case .nasdaq100: return "cpu"
        case .dowJones: return "building.2.fill"
        case .etfs: return "chart.pie.fill"
        case .commodities: return "scalemass.fill"
        case .gainers: return "arrow.up.right"
        case .losers: return "arrow.down.right"
        }
    }
    
    var index: StockIndex? {
        switch self {
        case .sp500: return .sp500
        case .nasdaq100: return .nasdaq100
        case .dowJones: return .dowJones
        default: return nil
        }
    }
}

// MARK: - Stock Market View Model

@MainActor
final class StockMarketViewModel: ObservableObject {
    
    // MARK: - Published State
    
    /// Currently selected segment
    @Published var selectedSegment: StockMarketSegment = .all
    
    /// Search query
    @Published var searchText: String = ""
    
    /// Sort option
    @Published var sortOption: StockSortOption = .changePercent
    
    /// Sort direction
    @Published var sortAscending: Bool = false
    
    /// Loading state
    @Published private(set) var isLoading: Bool = false
    
    /// Initial load complete
    @Published private(set) var hasLoaded: Bool = false
    
    /// Error message
    @Published var errorMessage: String?
    
    // MARK: - Initialization
    
    /// Initialize with an optional initial segment
    /// - Parameter initialSegment: The segment to show when the view opens. Defaults to `.all`
    init(initialSegment: StockMarketSegment = .all) {
        self.selectedSegment = initialSegment
    }
    
    // MARK: - Dependencies
    
    private let cache = StockMarketCache.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    /// Filtered and sorted stocks based on current selection
    var displayedStocks: [CachedStock] {
        var stocks: [CachedStock]
        
        // Filter by segment
        switch selectedSegment {
        case .all:
            // FIX: Exclude commodities from "All" segment - they have their own dedicated segment
            // and are already shown in the Commodities section on the home page
            stocks = cache.stocksExcludingCommodities
        case .sp500:
            stocks = cache.stocks(for: .sp500)
        case .nasdaq100:
            stocks = cache.stocks(for: .nasdaq100)
        case .dowJones:
            stocks = cache.stocks(for: .dowJones)
        case .etfs:
            stocks = cache.allStocks().filter { $0.assetType == .etf }
        case .commodities:
            stocks = cache.allStocks().filter { $0.assetType == .commodity }
        case .gainers:
            stocks = cache.topGainers(limit: 50)
        case .losers:
            stocks = cache.topLosers(limit: 50)
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            stocks = stocks.filter {
                $0.symbol.lowercased().contains(query) ||
                $0.name.lowercased().contains(query)
            }
        }
        
        // Apply sorting
        stocks.sort { a, b in
            switch sortOption {
            case .changePercent:
                return sortAscending ? a.changePercent < b.changePercent : a.changePercent > b.changePercent
            case .price:
                return sortAscending ? a.currentPrice < b.currentPrice : a.currentPrice > b.currentPrice
            case .marketCap:
                return sortAscending ? (a.marketCap ?? 0) < (b.marketCap ?? 0) : (a.marketCap ?? 0) > (b.marketCap ?? 0)
            case .name:
                return sortAscending
                    ? a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending
            case .symbol:
                return sortAscending
                    ? a.symbol.localizedCaseInsensitiveCompare(b.symbol) == .orderedAscending
                    : a.symbol.localizedCaseInsensitiveCompare(b.symbol) == .orderedDescending
            }
        }
        
        return stocks
    }
    
    /// Top 5 gainers for quick view
    var topGainers: [CachedStock] {
        cache.topGainers(limit: 5)
    }
    
    /// Top 5 losers for quick view
    var topLosers: [CachedStock] {
        cache.topLosers(limit: 5)
    }
    
    /// Market status
    var isMarketOpen: Bool {
        cache.isMarketOpen
    }
    
    /// Last update time
    var lastUpdate: Date? {
        cache.lastQuoteUpdate
    }
    
    /// Check if Finnhub is configured (optional for enhanced index data)
    var isFinnhubConfigured: Bool {
        APIConfig.hasValidFinnhubKey
    }
    
    /// Total stock count
    var totalStockCount: Int {
        cache.stocks.count
    }
    
    /// Index stock counts
    var indexCounts: [StockIndex: Int] {
        var counts: [StockIndex: Int] = [:]
        for index in StockIndex.allCases {
            counts[index] = cache.indexConstituents[index]?.count ?? 0
        }
        return counts
    }
    
    // MARK: - Initialization
    
    init() {
        // Observe cache changes
        cache.$stocks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        cache.$isLoadingQuotes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                self?.isLoading = loading
            }
            .store(in: &cancellables)
        
        // Debounce search
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Load initial data - prioritizes showing cached data immediately
    func loadData() async {
        guard !hasLoaded else { return }
        
        // OPTIMIZATION: Check if we have valid cached data to show immediately
        if cache.hasValidCache {
            #if DEBUG
            print("✅ [StockMarketVM] Displaying \(cache.stocks.count) cached stocks immediately")
            #endif
            hasLoaded = true
            
            // Background refresh if data is stale (don't block UI)
            if cache.needsRefresh {
                Task.detached(priority: .utility) { @MainActor in
                    await self.backgroundRefresh()
                }
            }
            return
        }
        
        // No cache available - show loading and fetch data
        isLoading = true
        errorMessage = nil
        
        // Always load with Yahoo Finance first (no API key required)
        await loadWithYahooFinance()
        
        // If Finnhub is configured, try to fetch real index constituents in background
        if isFinnhubConfigured {
            Task {
                await fetchFinnhubIndicesInBackground()
            }
        }
        
        hasLoaded = true
        isLoading = false
    }
    
    /// Background refresh without blocking UI
    private func backgroundRefresh() async {
        guard !isLoading else { return }
        
        #if DEBUG
        print("🔄 [StockMarketVM] Starting background refresh...")
        #endif
        
        await loadWithYahooFinance()
        
        if isFinnhubConfigured {
            await fetchFinnhubIndicesInBackground()
        }
        
        #if DEBUG
        print("✅ [StockMarketVM] Background refresh complete")
        #endif
    }
    
    /// Refresh data
    func refresh() async {
        isLoading = true
        errorMessage = nil
        
        // Always use Yahoo Finance as primary source
        await loadWithYahooFinance()
        
        // If Finnhub is configured, also refresh index data
        if isFinnhubConfigured {
            Task {
                await fetchFinnhubIndicesInBackground()
            }
        }
        
        isLoading = false
    }
    
    /// Primary data loading using Yahoo Finance (no API key required)
    /// PERFORMANCE OPTIMIZATION: Progressive batch loading - shows first batch immediately
    private func loadWithYahooFinance() async {
        // Expanded batches for better market coverage - 50 stocks per batch (Yahoo Finance limit)
        // Prioritize most popular stocks first for faster perceived loading
        let symbolBatches = [
            // Batch 1: Mega-cap tech + top ETFs (50 symbols) - PRIORITY BATCH
            ["AAPL", "MSFT", "GOOGL", "AMZN", "META", "TSLA", "NVDA", "SPY", "QQQ", "VOO",
             "JPM", "V", "JNJ", "WMT", "PG", "UNH", "HD", "MA", "DIS", "PYPL",
             "NFLX", "AMD", "INTC", "CRM", "ADBE", "CSCO", "ORCL", "IBM", "QCOM", "TXN",
             "BAC", "WFC", "GS", "MS", "C", "AXP", "BLK", "SCHW", "USB", "PNC",
             "KO", "PEP", "MCD", "SBUX", "NKE", "COST", "TGT", "LOW", "CVX", "XOM"],
            // Batch 2: More large caps + finance + industrials (50 symbols)
            ["COP", "SLB", "BA", "CAT", "HON", "GE", "RTX", "LMT", "UPS", "FDX",
             "PFE", "MRK", "ABBV", "LLY", "BMY", "AMGN", "GILD", "REGN", "VRTX", "ISRG",
             "DHR", "TMO", "ABT", "MDT", "SYK", "BDX", "ZTS", "CI", "CVS", "HUM",
             "AVGO", "ACN", "NEE", "PM", "T", "VZ", "CMCSA", "TMUS", "MO", "CB",
             "MMC", "BKNG", "ADP", "SPGI", "DE", "BRK-B", "INTU", "MDLZ", "ADI", "TJX"],
            // Batch 3: ETFs + growth stocks + semiconductors (50 symbols)
            ["DIA", "IWM", "VTI", "ARKK", "XLF", "XLE", "XLK", "GLD", "VNQ", "HYG",
             "SNOW", "PLTR", "NET", "DDOG", "CRWD", "ZS", "ABNB", "UBER", "SQ", "SHOP",
             "VGT", "XLV", "XLI", "XLY", "XLP", "XLB", "XLU", "XLRE", "SLV", "TLT",
             "LQD", "EEM", "VWO", "VEA", "IEMG", "EFA", "VIG", "AMAT", "MU", "LRCX",
             "KLAC", "MRVL", "ON", "SWKS", "MPWR", "MCHP", "SNPS", "CDNS", "NXPI", "NOW"],
            // Batch 4: More stocks across sectors (50 symbols)
            ["OKTA", "TEAM", "TWLO", "TFC", "COF", "AIG", "ELV", "MCK", "CNC", "BSX",
             "LYFT", "DASH", "SPOT", "ROKU", "ZM", "ETSY", "OXY", "EOG", "PXD", "DVN",
             "MPC", "PSX", "VLO", "HES", "HAL", "DOW", "MMM", "TRV", "WBA", "PANW",
             "MELI", "MNST", "FTNT", "KDP", "CTAS", "MAR", "ORLY", "ADSK", "PCAR", "KHC",
             "AEP", "EXC", "PAYX", "ROST", "DXCM", "CPRT", "IDXX", "ODFL", "WDAY", "LULU"],
            // Batch 5: Additional S&P 500 stocks (50 symbols)
            ["FAST", "VRSK", "CSGP", "EA", "BKR", "GEHC", "CTSH", "AZO", "CHTR", "BIIB",
             "ILMN", "ALGN", "ENPH", "FSLR", "MRNA", "ZBH", "MTD", "IQV", "TECH", "TTWO",
             "ANSS", "SPLK", "PAYC", "PODD", "POOL", "SBAC", "EQIX", "DLR", "PSA", "AVB",
             "EQR", "UDR", "MAA", "CPT", "ESS", "ARE", "HST", "REG", "KIM", "FRT",
             "SPG", "O", "WY", "AMT", "CCI", "ZION", "CFG", "WAT", "PKI", "LH"],
            // Batch 6: More S&P 500 stocks (50 symbols)
            ["KEY", "RF", "HBAN", "FITB", "MTB", "NTRS", "STT", "BK", "TROW", "IVZ",
             "BEN", "LNC", "PFG", "PRU", "MET", "AFL", "ALL", "AJG", "AON", "CINF",
             "PGR", "HIG", "L", "WRB", "RE", "RNR", "GL", "UNM", "CNO", "VOYA",
             "FAF", "FNF", "ORI", "AIZ", "BRO", "WTW", "FIS", "FISV", "FLT", "JKHY",
             "BR", "NDAQ", "ICE", "CME", "MSCI", "SPGI", "MCO", "INFO", "TRI", "CBRE"],
            // Batch 7: Commodities + Precious Metals + Energy Futures (21 symbols)
            ["GC=F", "SI=F", "PL=F", "PA=F", "CL=F", "BZ=F", "NG=F", "HO=F", "RB=F",
             "HG=F", "ALI=F", "ZC=F", "ZS=F", "ZW=F", "KC=F", "CC=F", "CT=F", "SB=F",
             "LE=F", "HE=F", "GLD"]
        ]
        
        var allQuotes: [String: StockQuote] = [:]
        let maxRetries = 3
        var firstBatchLoaded = false
        
        for (index, batch) in symbolBatches.enumerated() {
            var quotes: [String: StockQuote] = [:]
            
            // Retry logic with exponential backoff
            for attempt in 1...maxRetries {
                quotes = await StockPriceService.shared.fetchQuotes(tickers: batch)
                
                if !quotes.isEmpty {
                    break // Success, exit retry loop
                }
                
                // If failed and not last attempt, wait with exponential backoff
                if attempt < maxRetries {
                    let backoffMs = UInt64(150_000_000 * attempt) // 150ms, 300ms, 450ms
                    #if DEBUG
                    print("⚠️ [StockMarketVM] Batch \(index + 1) attempt \(attempt) failed, retrying in \(attempt * 150)ms...")
                    #endif
                    try? await Task.sleep(nanoseconds: backoffMs)
                }
            }
            
            allQuotes.merge(quotes) { _, new in new }
            
            #if DEBUG
            print("📊 [StockMarketVM] Batch \(index + 1)/\(symbolBatches.count): loaded \(quotes.count) quotes")
            #endif
            
            // Update cache incrementally for faster UI updates
            if !quotes.isEmpty {
                for (symbol, quote) in quotes {
                    cache.updateStock(CachedStock(
                        symbol: symbol,
                        name: quote.displayName,
                        currentPrice: quote.regularMarketPrice,
                        change: quote.regularMarketChange ?? 0,
                        changePercent: quote.regularMarketChangePercent ?? {
                            // Calculate from previousClose if API doesn't provide change percent
                            if let prevClose = quote.regularMarketPreviousClose, prevClose > 0 {
                                return ((quote.regularMarketPrice - prevClose) / prevClose) * 100
                            }
                            return 0
                        }(),
                        dayHigh: quote.regularMarketDayHigh ?? 0,
                        dayLow: quote.regularMarketDayLow ?? 0,
                        previousClose: quote.regularMarketPreviousClose ?? 0,
                        marketCap: quote.marketCap,
                        volume: quote.regularMarketVolume,
                        assetType: quote.assetType,
                        exchange: quote.exchange,
                        sector: nil,
                        lastUpdated: Date()
                    ))
                }
                
                // PERFORMANCE FIX: After first batch succeeds, mark as loaded so UI shows data immediately
                // Remaining batches continue loading in background while user can already interact
                if !firstBatchLoaded && index == 0 {
                    firstBatchLoaded = true
                    hasLoaded = true
                    isLoading = false
                    
                    // Set up initial index groupings with first batch data
                    setupDefaultIndexConstituents(loadedSymbols: Set(quotes.keys))
                    
                    #if DEBUG
                    print("✅ [StockMarketVM] First batch loaded - UI can now display \(quotes.count) stocks")
                    #endif
                }
            }
            
            // Delay between batches to avoid rate limiting
            // OPTIMIZATION: Shorter delay (100ms) for subsequent batches since UI is already showing data
            if index < symbolBatches.count - 1 {
                let delayNs: UInt64 = firstBatchLoaded ? 100_000_000 : 200_000_000 // 100ms vs 200ms
                try? await Task.sleep(nanoseconds: delayNs)
            }
        }
        
        // If we got any data, finalize index groupings with all loaded symbols
        if !allQuotes.isEmpty {
            #if DEBUG
            print("✅ [StockMarketVM] Loaded total \(allQuotes.count) stock quotes from Yahoo Finance")
            #endif
            
            // Update index groupings with complete symbol set
            setupDefaultIndexConstituents(loadedSymbols: Set(allQuotes.keys))
            errorMessage = nil
            return
        }
        
        // If Yahoo Finance fails completely, use sample data so the UI works
        #if DEBUG
        print("⚠️ [StockMarketVM] Yahoo Finance unavailable, loading sample data...")
        #endif
        
        loadSampleData()
        errorMessage = nil // Clear error since we have sample data
    }
    
    /// Load sample data when API is unavailable (for demo/offline purposes)
    private func loadSampleData() {
        let sampleStocks: [(String, String, Double, Double, AssetType)] = [
            ("AAPL", "Apple Inc.", 248.50, 1.25, .stock),
            ("MSFT", "Microsoft Corporation", 425.80, 0.85, .stock),
            ("GOOGL", "Alphabet Inc.", 175.30, -0.45, .stock),
            ("AMZN", "Amazon.com Inc.", 198.75, 2.10, .stock),
            ("META", "Meta Platforms Inc.", 585.20, 1.75, .stock),
            ("TSLA", "Tesla Inc.", 248.90, -1.30, .stock),
            ("NVDA", "NVIDIA Corporation", 875.40, 3.25, .stock),
            ("JPM", "JPMorgan Chase & Co.", 198.50, 0.65, .stock),
            ("V", "Visa Inc.", 285.30, 0.40, .stock),
            ("JNJ", "Johnson & Johnson", 155.80, -0.25, .stock),
            ("WMT", "Walmart Inc.", 168.40, 0.55, .stock),
            ("PG", "Procter & Gamble Co.", 165.20, 0.35, .stock),
            ("UNH", "UnitedHealth Group Inc.", 525.60, 1.15, .stock),
            ("HD", "Home Depot Inc.", 385.40, 0.90, .stock),
            ("SPY", "SPDR S&P 500 ETF Trust", 525.80, 0.75, .etf),
            ("QQQ", "Invesco QQQ Trust", 485.30, 1.10, .etf),
            ("VOO", "Vanguard S&P 500 ETF", 482.50, 0.70, .etf),
            ("DIA", "SPDR Dow Jones Industrial ETF", 420.80, 0.45, .etf),
            ("IWM", "iShares Russell 2000 ETF", 225.40, -0.35, .etf),
        ]
        
        for (symbol, name, price, changePercent, assetType) in sampleStocks {
            let change = price * changePercent / 100
            cache.updateStock(CachedStock(
                symbol: symbol,
                name: name,
                currentPrice: price,
                change: change,
                changePercent: changePercent,
                dayHigh: price * 1.01,
                dayLow: price * 0.99,
                previousClose: price - change,
                marketCap: nil,
                volume: nil,
                assetType: assetType,
                exchange: assetType == .etf ? "NYSE Arca" : "NASDAQ",
                sector: nil,
                lastUpdated: Date()
            ))
        }
        
        // Set up index constituents
        let stockSymbols = sampleStocks.filter { $0.4 == .stock }.map { $0.0 }
        cache.setIndexConstituents(.sp500, symbols: stockSymbols)
        cache.setIndexConstituents(.nasdaq100, symbols: stockSymbols.filter { ["AAPL", "MSFT", "GOOGL", "AMZN", "META", "TSLA", "NVDA"].contains($0) })
        cache.setIndexConstituents(.dowJones, symbols: ["AAPL", "MSFT", "JPM", "V", "JNJ", "WMT", "PG", "UNH", "HD"])
        
        #if DEBUG
        print("✅ [StockMarketVM] Loaded \(sampleStocks.count) sample stocks")
        #endif
    }
    
    /// Fetch Finnhub index constituents in background (optional enhancement)
    private func fetchFinnhubIndicesInBackground() async {
        do {
            for index in StockIndex.allCases {
                let constituents = try await FinnhubService.shared.fetchIndexConstituents(index: index)
                cache.setIndexConstituents(index, symbols: constituents)
            }
        } catch {
            // Silently fail - we already have default data from Yahoo Finance
            #if DEBUG
            print("⚠️ [StockMarketVM] Finnhub index fetch failed (using defaults): \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Set up default index constituents from curated lists
    private func setupDefaultIndexConstituents(loadedSymbols: Set<String>) {
        // S&P 500 top components (that we loaded)
        let sp500Symbols = Self.sp500TopStocks.filter { loadedSymbols.contains($0) }
        if !sp500Symbols.isEmpty {
            cache.setIndexConstituents(.sp500, symbols: sp500Symbols)
        }
        
        // Nasdaq 100 top components
        let nasdaq100Symbols = Self.nasdaq100TopStocks.filter { loadedSymbols.contains($0) }
        if !nasdaq100Symbols.isEmpty {
            cache.setIndexConstituents(.nasdaq100, symbols: nasdaq100Symbols)
        }
        
        // Dow Jones components
        let dowSymbols = Self.dowJonesStocks.filter { loadedSymbols.contains($0) }
        if !dowSymbols.isEmpty {
            cache.setIndexConstituents(.dowJones, symbols: dowSymbols)
        }
    }
    
    /// Get stock by symbol
    func stock(for symbol: String) -> CachedStock? {
        cache.stock(for: symbol)
    }
    
    /// Toggle sort direction
    func toggleSortDirection() {
        sortAscending.toggle()
    }
    
    /// Set sort option
    func setSortOption(_ option: StockSortOption) {
        if sortOption == option {
            sortAscending.toggle()
        } else {
            sortOption = option
            sortAscending = false
        }
    }
    
    // MARK: - Curated Stock Lists (No API Key Required)
    
    /// Comprehensive list of popular stocks, ETFs, and commodities to fetch
    static let popularStocksList: [String] = {
        var all = Set<String>()
        all.formUnion(sp500TopStocks)
        all.formUnion(nasdaq100TopStocks)
        all.formUnion(dowJonesStocks)
        all.formUnion(popularETFs)
        all.formUnion(additionalPopularStocks)
        all.formUnion(commodityFutures)
        return Array(all)
    }()
    
    /// S&P 500 stocks - comprehensive list (using simple symbols only)
    static let sp500TopStocks: [String] = [
        // Mega-cap tech
        "AAPL", "MSFT", "AMZN", "NVDA", "GOOGL", "GOOG", "META", "TSLA",
        // Healthcare
        "UNH", "JNJ", "LLY", "ABBV", "MRK", "PFE", "TMO", "ABT", "DHR", "BMY",
        "AMGN", "GILD", "REGN", "VRTX", "ISRG", "SYK", "MDT", "BDX", "ZTS", "CI",
        "CVS", "HUM", "ELV", "MCK", "CNC", "BSX", "HCA", "DXCM", "IQV", "MTD",
        "IDXX", "ALGN", "HOLX", "WAT", "A", "TECH", "COO", "PODD", "BIO",
        // Financial
        "V", "JPM", "MA", "BAC", "WFC", "GS", "MS", "AXP", "BLK", "SCHW",
        "C", "USB", "PNC", "TFC", "COF", "AIG", "MMC", "CB", "AON", "PGR",
        "MET", "AFL", "PRU", "ALL", "TRV", "AJG", "BK", "STT", "NTRS", "TROW",
        "FITB", "CFG", "RF", "KEY", "HBAN", "MTB", "ZION", "CMA", "EWBC",
        // Consumer Discretionary
        "HD", "MCD", "NKE", "SBUX", "TJX", "BKNG", "LOW", "TGT", "ROST", "MAR",
        "HLT", "DRI", "CMG", "YUM", "ORLY", "AZO", "BBY", "KMX", "GPC", "POOL",
        "DHI", "LEN", "PHM", "NVR", "TOL", "DG", "DLTR", "TSCO", "ULTA",
        // Consumer Staples
        "PG", "KO", "PEP", "COST", "WMT", "PM", "MO", "MDLZ", "CL", "KMB",
        "GIS", "K", "HSY", "SJM", "CPB", "CAG", "MKC", "HRL", "KHC", "STZ",
        "EL", "CLX", "CHD", "KR", "SYY", "WBA", "TAP",
        // Energy
        "XOM", "CVX", "COP", "SLB", "EOG", "PXD", "MPC", "PSX", "VLO", "OXY",
        "DVN", "HES", "HAL", "BKR", "FANG", "OKE", "WMB", "KMI", "TRGP",
        // Industrials
        "CAT", "HON", "UNP", "RTX", "LMT", "BA", "DE", "GE", "UPS", "FDX",
        "MMM", "EMR", "ITW", "ETN", "ROK", "PH", "FAST", "NSC", "CSX", "PCAR",
        "WAB", "CMI", "ODFL", "DAL", "LUV", "AAL", "UAL", "GD", "NOC", "TDG",
        "IR", "DOV", "CARR", "TT", "XYL", "SWK", "GWW", "IEX", "ROP", "VRSK",
        // Technology
        "ADBE", "CRM", "CSCO", "ORCL", "IBM", "QCOM", "TXN", "AMD", "INTC", "AVGO",
        "ADI", "INTU", "NOW", "SNPS", "CDNS", "ANSS", "PANW", "FTNT", "ANET", "KEYS",
        "KLAC", "LRCX", "MCHP", "NXPI", "SWKS", "MPWR", "AMAT", "MU", "ON", "MRVL",
        "CTSH", "ACN", "IT", "EPAM", "LDOS", "DXC", "HPQ", "HPE", "JNPR",
        // Communication Services
        "NFLX", "DIS", "CMCSA", "VZ", "T", "TMUS", "CHTR", "EA", "TTWO", "MTCH",
        "WBD", "PARA", "FOX", "FOXA", "NWS", "NWSA", "IPG", "OMC",
        // Utilities
        "NEE", "DUK", "SO", "D", "AEP", "EXC", "SRE", "XEL", "WEC", "ES",
        "ED", "EIX", "DTE", "PEG", "FE", "PPL", "ETR", "CMS", "AES", "NI",
        "ATO", "LNT", "EVRG", "NRG", "PNW", "AWK", "WTR",
        // Real Estate
        "PLD", "AMT", "CCI", "EQIX", "DLR", "O", "SPG", "PSA", "WELL", "AVB",
        "EQR", "VTR", "ARE", "UDR", "MAA", "ESS", "REG", "KIM", "FRT", "HST",
        "SUI", "CPT", "IRM", "EXR", "PEAK", "BXP", "VNO", "SLG", "CBRE", "JLL",
        // Materials
        "LIN", "APD", "SHW", "ECL", "DD", "NEM", "FCX", "NUE", "VMC", "MLM",
        "DOW", "CTVA", "FMC", "ALB", "CF", "MOS", "IFF", "PPG", "RPM", "EMN",
        "PKG", "SEE", "IP", "AVY", "BLL", "AMCR", "CE", "WRK"
    ]
    
    /// Nasdaq 100 stocks - complete list
    static let nasdaq100TopStocks: [String] = [
        // Mega-cap tech (top weighted)
        "AAPL", "MSFT", "AMZN", "NVDA", "GOOGL", "GOOG", "META", "TSLA", "AVGO", "COST",
        // Large-cap tech and communications
        "PEP", "CSCO", "ADBE", "NFLX", "AMD", "CMCSA", "INTC", "INTU", "QCOM", "TXN",
        "TMUS", "AMGN", "HON", "SBUX", "ISRG", "AMAT", "BKNG", "GILD", "ADI", "MDLZ",
        // Healthcare and biotech
        "VRTX", "ADP", "REGN", "PYPL", "LRCX", "KLAC", "MU", "SNPS", "CDNS", "PANW",
        // Consumer and retail
        "MELI", "MNST", "FTNT", "KDP", "CTAS", "MAR", "ORLY", "NXPI", "MCHP", "ADSK",
        "PCAR", "KHC", "AEP", "EXC", "PAYX", "ROST", "DXCM", "CPRT", "IDXX", "ODFL",
        // Growth tech and cloud
        "CRWD", "WDAY", "LULU", "FAST", "VRSK", "CSGP", "EA", "BKR", "GEHC", "CTSH",
        // Additional Nasdaq 100 components
        "ABNB", "AZN", "BIIB", "CHTR", "CEG", "DLTR", "DDOG", "ENPH", "FANG", "ILMN",
        "JD", "MRVL", "MRNA", "ON", "PDD", "SIRI", "TEAM", "TTD", "WBD", "XEL",
        "ZM", "ZS", "ALGN", "ANSS", "ASML", "CDW", "EBAY", "FISV", "GFS", "HSIC",
        "OKTA", "SWKS", "VRSN", "WYNN", "ZBRA", "ARM", "SMCI", "COIN", "DASH", "MDB"
    ]
    
    /// Dow Jones 30 components
    static let dowJonesStocks: [String] = [
        "AAPL", "AMGN", "AXP", "BA", "CAT", "CRM", "CSCO", "CVX", "DIS", "DOW",
        "GS", "HD", "HON", "IBM", "INTC", "JNJ", "JPM", "KO", "MCD", "MMM",
        "MRK", "MSFT", "NKE", "PG", "TRV", "UNH", "V", "VZ", "WBA", "WMT"
    ]
    
    /// Popular ETFs
    static let popularETFs: [String] = [
        "SPY", "QQQ", "VOO", "VTI", "IWM", "DIA", "VGT", "XLF", "XLE", "VNQ",
        "ARKK", "XLK", "XLV", "XLI", "XLY", "XLP", "XLB", "XLU", "XLRE", "GLD",
        "SLV", "TLT", "HYG", "LQD", "EEM", "VWO", "VEA", "IEMG", "EFA", "VIG"
    ]
    
    /// Additional popular stocks
    static let additionalPopularStocks: [String] = [
        // More tech
        "CRM", "NOW", "SNOW", "PLTR", "NET", "DDOG", "ZS", "OKTA", "TEAM", "TWLO",
        // Semiconductors
        "AMAT", "MU", "LRCX", "KLAC", "MRVL", "ON", "SWKS", "MPWR", "MCHP",
        // Finance
        "BAC", "WFC", "C", "MS", "SCHW", "USB", "PNC", "TFC", "COF", "AIG",
        // Healthcare
        "DHR", "BMY", "ELV", "HUM", "MCK", "CNC", "SYK", "BSX", "MDT", "BDX",
        // Consumer
        "ABNB", "UBER", "LYFT", "DASH", "SPOT", "ROKU", "ZM", "SQ", "SHOP", "ETSY",
        // Energy
        "OXY", "SLB", "EOG", "PXD", "DVN", "MPC", "PSX", "VLO", "HES", "HAL"
    ]
    
    /// Commodity futures symbols (Yahoo Finance format)
    static let commodityFutures: [String] = [
        // Precious Metals
        "GC=F",   // Gold Futures
        "SI=F",   // Silver Futures
        "PL=F",   // Platinum Futures
        "PA=F",   // Palladium Futures
        // Energy
        "CL=F",   // Crude Oil WTI Futures
        "BZ=F",   // Brent Crude Oil Futures
        "NG=F",   // Natural Gas Futures
        "HO=F",   // Heating Oil Futures
        "RB=F",   // RBOB Gasoline Futures
        // Industrial Metals
        "HG=F",   // Copper Futures
        "ALI=F",  // Aluminum Futures
        // Agriculture
        "ZC=F",   // Corn Futures
        "ZS=F",   // Soybean Futures
        "ZW=F",   // Wheat Futures
        "KC=F",   // Coffee Futures
        "CC=F",   // Cocoa Futures
        "CT=F",   // Cotton Futures
        "SB=F",   // Sugar Futures
        // Livestock
        "LE=F",   // Live Cattle Futures
        "HE=F"    // Lean Hogs Futures
    ]
}

// MARK: - Preview Support

extension StockMarketViewModel {
    static var preview: StockMarketViewModel {
        let vm = StockMarketViewModel()
        // Add some mock data for previews
        return vm
    }
}
