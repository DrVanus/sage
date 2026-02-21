//
//  StockWatchlistManager.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/20/26.
//  Manager for persisting and managing stock watchlist (favorites).
//

import Foundation
import Combine

// MARK: - Stock Watchlist Manager

/// Manages the user's stock watchlist (favorited stocks they want to track)
@MainActor
final class StockWatchlistManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = StockWatchlistManager()
    
    // MARK: - UserDefaults Keys
    
    private let watchlistKey = "stockWatchlist"
    private let orderKey = "stockWatchlistOrder"
    
    // MARK: - Published State
    
    /// Set of watched stock symbols
    @Published private(set) var watchedSymbols: Set<String> = []
    
    /// Ordered array of watched symbols (for display order)
    @Published private(set) var watchlistOrder: [String] = []
    
    /// Cached stock data for watchlist items
    @Published private(set) var watchlistStocks: [CachedStock] = []
    
    /// Loading state
    @Published private(set) var isLoading: Bool = false
    
    /// Last update time
    @Published private(set) var lastUpdate: Date?
    
    // MARK: - Computed Properties
    
    /// Alias for compatibility
    var favorites: Set<String> { watchedSymbols }
    
    /// Number of stocks in watchlist
    var count: Int { watchedSymbols.count }
    
    /// Check if watchlist is empty
    var isEmpty: Bool { watchedSymbols.isEmpty }
    
    // MARK: - Private
    
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    private init() {
        loadFromDefaults()
        LiveStockPriceManager.shared.setTickers(watchlistOrder, source: "watchlist")
        
        // Auto-save when watchlist changes
        $watchedSymbols
            .dropFirst()
            .sink { [weak self] symbols in
                self?.saveToDefaults(symbols)
                self?.refreshWatchlistData()
            }
            .store(in: &cancellables)
        
        // Subscribe to cache updates
        StockMarketCache.shared.$stocks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateWatchlistStocks()
            }
            .store(in: &cancellables)
        
        // Initial data refresh
        refreshWatchlistData()
    }
    
    // MARK: - Persistence
    
    private func loadFromDefaults() {
        let savedSymbols = ((UserDefaults.standard.array(forKey: watchlistKey) as? [String]) ?? [])
            .map { $0.uppercased() }
        watchedSymbols = Set(savedSymbols)
        
        if let savedOrder = UserDefaults.standard.array(forKey: orderKey) as? [String] {
            watchlistOrder = savedOrder.map { $0.uppercased() }
        } else {
            watchlistOrder = savedSymbols
        }
        
        normalizeOrder()
        updateWatchlistStocks()
    }
    
    private func saveToDefaults(_ symbols: Set<String>) {
        let array = Array(symbols)
        UserDefaults.standard.set(array, forKey: watchlistKey)
        normalizeOrder()
        UserDefaults.standard.set(watchlistOrder, forKey: orderKey)
    }
    
    private func normalizeOrder() {
        // Ensure watchlistOrder contains exactly the symbols in watchedSymbols
        var ordered: [String] = []
        var seen = Set<String>()
        
        // Keep existing order for symbols that are still in watchlist
        for symbol in watchlistOrder where watchedSymbols.contains(symbol) {
            if !seen.contains(symbol) {
                ordered.append(symbol)
                seen.insert(symbol)
            }
        }
        
        // Append any new symbols at the end
        for symbol in watchedSymbols where !seen.contains(symbol) {
            ordered.append(symbol)
        }
        
        watchlistOrder = ordered
    }
    
    // MARK: - Public API
    
    /// Check if a stock is in the watchlist
    func isWatched(_ symbol: String) -> Bool {
        watchedSymbols.contains(symbol.uppercased())
    }
    
    /// Check if a stock is favorite (alias for isWatched)
    func isFavorite(symbol: String) -> Bool {
        isWatched(symbol)
    }
    
    /// Add a stock to the watchlist
    func add(_ symbol: String) {
        let uppercased = symbol.uppercased()
        guard !watchedSymbols.contains(uppercased) else { return }
        
        watchedSymbols.insert(uppercased)
        if !watchlistOrder.contains(uppercased) {
            watchlistOrder.append(uppercased)
        }
        
        // Start tracking for live prices
        Task { @MainActor in
            LiveStockPriceManager.shared.addTickers([uppercased], source: "watchlist")
        }
        
        #if DEBUG
        print("📌 StockWatchlist: Added \(uppercased)")
        #endif
    }
    
    /// Remove a stock from the watchlist
    func remove(_ symbol: String) {
        let uppercased = symbol.uppercased()
        guard watchedSymbols.contains(uppercased) else { return }
        
        watchedSymbols.remove(uppercased)
        watchlistOrder.removeAll { $0 == uppercased }
        
        // Stop tracking if not needed elsewhere
        Task { @MainActor in
            LiveStockPriceManager.shared.removeTickers([uppercased], source: "watchlist")
        }
        
        #if DEBUG
        print("📌 StockWatchlist: Removed \(uppercased)")
        #endif
    }
    
    /// Toggle watchlist status for a stock
    func toggle(_ symbol: String) {
        if isWatched(symbol) {
            remove(symbol)
        } else {
            add(symbol)
        }
    }
    
    /// Reorder the watchlist
    func reorder(from source: IndexSet, to destination: Int) {
        watchlistOrder.move(fromOffsets: source, toOffset: destination)
        saveToDefaults(watchedSymbols)
    }
    
    /// Set a new order for the watchlist
    func setOrder(_ newOrder: [String]) {
        let validOrder = newOrder.filter { watchedSymbols.contains($0) }
        watchlistOrder = validOrder
        normalizeOrder()
        saveToDefaults(watchedSymbols)
    }
    
    /// Clear the entire watchlist
    func clearAll() {
        watchedSymbols.removeAll()
        watchlistOrder.removeAll()
        watchlistStocks.removeAll()
        LiveStockPriceManager.shared.setTickers([], source: "watchlist")
        saveToDefaults(watchedSymbols)
        
        #if DEBUG
        print("📌 StockWatchlist: Cleared all")
        #endif
    }
    
    // MARK: - Data Refresh
    
    /// Refresh stock data for watchlist items
    func refreshWatchlistData() {
        guard !watchedSymbols.isEmpty else {
            watchlistStocks = []
            return
        }
        
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self = self else { return }
            
            await MainActor.run { self.isLoading = true }
            
            // Fetch latest quotes
            let symbols = Array(self.watchedSymbols)
            await StockMarketCache.shared.refreshQuotes(for: symbols)
            
            await MainActor.run {
                self.updateWatchlistStocks()
                self.isLoading = false
                self.lastUpdate = Date()
            }
        }
    }
    
    /// Force refresh
    func forceRefresh() async {
        guard !watchedSymbols.isEmpty else { return }
        
        isLoading = true
        
        let symbols = Array(watchedSymbols)
        let cache = StockMarketCache.shared
        
        // Try Finnhub first, fallback to Yahoo
        let finnhubQuotes = await FinnhubService.shared.fetchQuotes(symbols: symbols)
        
        let missingSymbols = symbols.filter { finnhubQuotes[$0] == nil }
        var yahooQuotes: [String: StockQuote] = [:]
        if !missingSymbols.isEmpty {
            yahooQuotes = await StockPriceService.shared.fetchQuotes(tickers: missingSymbols)
        }
        
        // Update cache using the updateStock method
        for (symbol, quote) in finnhubQuotes {
            let existingName = cache.stock(for: symbol)?.name ?? symbol
            cache.updateStock(CachedStock(
                symbol: symbol,
                name: existingName,
                currentPrice: quote.currentPrice,
                change: quote.change,
                changePercent: quote.changePercent,
                dayHigh: quote.dayHigh,
                dayLow: quote.dayLow,
                previousClose: quote.previousClose,
                marketCap: nil,
                volume: nil,
                assetType: .stock,
                exchange: nil,
                sector: nil,
                lastUpdated: Date()
            ))
        }
        
        for (symbol, quote) in yahooQuotes {
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
        
        updateWatchlistStocks()
        isLoading = false
        lastUpdate = Date()
    }
    
    /// Update the watchlistStocks array from cache
    private func updateWatchlistStocks() {
        watchlistStocks = watchlistOrder.compactMap { symbol in
            StockMarketCache.shared.stock(for: symbol)
        }
    }
    
    // MARK: - Debounced Publisher
    
    /// Publisher that emits watchlist changes after a short debounce
    var debouncedWatchlist: AnyPublisher<Set<String>, Never> {
        $watchedSymbols
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

// MARK: - Convenience Extensions

extension StockWatchlistManager {
    /// Get stock data for a specific symbol from the watchlist
    func stock(for symbol: String) -> CachedStock? {
        watchlistStocks.first { $0.symbol == symbol.uppercased() }
    }
    
    /// Get total value of watchlist (if tracking quantities)
    var totalValue: Double {
        watchlistStocks.reduce(0) { $0 + $1.currentPrice }
    }
    
    /// Average change percent across watchlist
    var averageChangePercent: Double {
        guard !watchlistStocks.isEmpty else { return 0 }
        return watchlistStocks.reduce(0) { $0 + $1.changePercent } / Double(watchlistStocks.count)
    }
    
    /// Number of gainers in watchlist
    var gainerCount: Int {
        watchlistStocks.filter { $0.changePercent > 0 }.count
    }
    
    /// Number of losers in watchlist
    var loserCount: Int {
        watchlistStocks.filter { $0.changePercent < 0 }.count
    }
}
