//
//  LiveStockPriceManager.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/19/26.
//  Manager for real-time stock price polling and updates.
//  Updates portfolio holdings with live stock prices.
//

import Foundation
import Combine
import os

// MARK: - Live Stock Price Manager

/// Manages live stock price updates for portfolio holdings.
/// Polls Yahoo Finance at configurable intervals and respects market hours.
@MainActor
final class LiveStockPriceManager: ObservableObject {
    static let shared = LiveStockPriceManager()
    
    private let logger = Logger(subsystem: "CryptoSage", category: "LiveStockPriceManager")
    
    // MARK: - Published State
    
    /// Latest stock quotes keyed by ticker
    @Published private(set) var quotes: [String: StockQuote] = [:]
    
    /// Whether polling is currently active
    @Published private(set) var isPolling: Bool = false
    
    /// Last successful update time
    @Published private(set) var lastUpdateAt: Date?
    
    /// Whether the US stock market is currently open
    @Published private(set) var isMarketOpen: Bool = false
    
    // MARK: - Combine Publishers
    
    private let quotesSubject = PassthroughSubject<[String: StockQuote], Never>()
    
    /// Publisher for stock quote updates
    var quotesPublisher: AnyPublisher<[String: StockQuote], Never> {
        quotesSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Configuration
    
    /// Polling interval during market hours (seconds)
    private let marketHoursInterval: TimeInterval = 60  // 1 minute
    
    /// Polling interval outside market hours (seconds)
    private let afterHoursInterval: TimeInterval = 300  // 5 minutes
    
    /// Maximum concurrent API requests
    private let maxConcurrentRequests: Int = 4
    
    // MARK: - State
    
    private var pollingTask: Task<Void, Never>?
    private var trackedTickers: Set<String> = []
    /// Track tickers by source so one feature cannot accidentally remove another's subscriptions.
    private var sourceTickers: [String: Set<String>] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // Rate limiting
    private var lastFetchAt: Date?
    private var consecutiveFailures: Int = 0
    private let maxConsecutiveFailures: Int = 5
    private var backoffMultiplier: Double = 1.0
    
    // MARK: - Initialization
    
    private init() {
        // Update market status on init
        updateMarketStatus()
        
        // Schedule periodic market status updates
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateMarketStatus()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Start polling for stock prices
    /// - Parameter tickers: Array of stock ticker symbols to track
    func startPolling(for tickers: [String]) {
        setTickers(tickers, source: "generic")
    }
    
    /// Stop polling
    func stopPolling() {
        stopPollingTask()
    }
    
    /// Replace tracked tickers for a source.
    func setTickers(_ tickers: [String], source: String = "generic") {
        let normalized = Set(tickers.map { $0.uppercased() })
        if normalized.isEmpty {
            sourceTickers.removeValue(forKey: source)
        } else {
            sourceTickers[source] = normalized
        }
        rebuildTrackedTickers()
        applyPollingState()
    }
    
    /// Re-evaluate polling against current settings + market status.
    func reapplyPollingPreferences() {
        applyPollingState()
    }
    
    /// Add tickers to track
    func addTickers(_ tickers: [String], source: String = "generic") {
        let newTickers = Set(tickers.map { $0.uppercased() })
        guard !newTickers.isEmpty else { return }
        var existing = sourceTickers[source] ?? []
        existing.formUnion(newTickers)
        sourceTickers[source] = existing
        rebuildTrackedTickers()
        applyPollingState()
    }
    
    /// Remove tickers from a specific tracking source.
    func removeTickers(_ tickers: [String], source: String = "generic") {
        let tickersToRemove = Set(tickers.map { $0.uppercased() })
        guard !tickersToRemove.isEmpty else { return }
        
        if var existing = sourceTickers[source] {
            existing.subtract(tickersToRemove)
            if existing.isEmpty {
                sourceTickers.removeValue(forKey: source)
            } else {
                sourceTickers[source] = existing
            }
        }
        
        rebuildTrackedTickers()
        
        // Only purge quote cache for symbols no longer tracked by ANY source.
        for ticker in tickersToRemove where !trackedTickers.contains(ticker) {
            quotes.removeValue(forKey: ticker)
        }
        
        applyPollingState()
    }
    
    private func rebuildTrackedTickers() {
        trackedTickers = sourceTickers.values.reduce(into: Set<String>()) { result, tickers in
            result.formUnion(tickers)
        }
    }
    
    private func applyPollingState() {
        guard !trackedTickers.isEmpty else {
            stopPollingTask()
            logger.info("No tracked stock tickers remain; polling paused")
            return
        }
        
        guard shouldPoll() else {
            stopPollingTask()
            logger.info("Polling paused by user settings or market-hours policy")
            return
        }
        
        startPollingTaskIfNeeded()
    }
    
    private func startPollingTaskIfNeeded() {
        guard pollingTask == nil else { return }
        isPolling = true
        logger.info("Starting stock price polling for \(self.trackedTickers.count) tickers")
        
        pollingTask = Task { [weak self] in
            await self?.pollingLoop()
        }
    }
    
    private func stopPollingTask() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
        logger.info("Stopped stock price polling")
    }
    
    /// Force an immediate refresh
    func refresh() async {
        await fetchQuotes()
    }
    
    /// Get the latest quote for a ticker
    func quote(for ticker: String) -> StockQuote? {
        quotes[ticker.uppercased()]
    }
    
    /// Get current price for a ticker
    func price(for ticker: String) -> Double? {
        quotes[ticker.uppercased()]?.regularMarketPrice
    }
    
    /// Get daily change percent for a ticker
    func dailyChangePercent(for ticker: String) -> Double? {
        quotes[ticker.uppercased()]?.regularMarketChangePercent
    }
    
    // MARK: - Polling Loop
    
    private func pollingLoop() async {
        while !Task.isCancelled {
            // Fetch quotes
            await fetchQuotes()
            
            // Calculate next poll interval based on market hours and backoff
            let baseInterval = isMarketOpen ? marketHoursInterval : afterHoursInterval
            let interval = baseInterval * backoffMultiplier
            
            logger.debug("Next poll in \(interval)s (market \(self.isMarketOpen ? "open" : "closed"), backoff: \(self.backoffMultiplier)x)")
            
            // Wait for next poll
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                // Task was cancelled
                break
            }
        }
    }
    
    private func fetchQuotes() async {
        guard shouldPoll(), !trackedTickers.isEmpty else { return }
        
        // Rate limiting check
        if let lastFetch = lastFetchAt {
            let elapsed = Date().timeIntervalSince(lastFetch)
            let minInterval = isMarketOpen ? 30 : 60  // Minimum seconds between fetches
            if elapsed < Double(minInterval) {
                logger.debug("Rate limit: skipping fetch, \(Int(elapsed))s since last fetch")
                return
            }
        }
        
        lastFetchAt = Date()
        
        let tickers = Array(trackedTickers)
        logger.info("Fetching quotes for \(tickers.count) tickers")
        
        // Fetch in batches
        let fetchedQuotes = await StockPriceService.shared.fetchQuotes(
            tickers: tickers,
            maxConcurrency: maxConcurrentRequests
        )
        
        if fetchedQuotes.isEmpty {
            // Handle failure
            consecutiveFailures += 1
            if consecutiveFailures >= maxConsecutiveFailures {
                backoffMultiplier = min(backoffMultiplier * 1.5, 10.0)
                logger.warning("Stock fetch failed \(self.consecutiveFailures) times, backoff: \(self.backoffMultiplier)x")
            }
            return
        }
        
        // Success - reset backoff
        consecutiveFailures = 0
        backoffMultiplier = 1.0
        
        // ROBUSTNESS: Only update valid quotes and preserve existing valid data
        var updatedCount = 0
        for (ticker, quote) in fetchedQuotes {
            // Validate quote data before updating
            guard quote.regularMarketPrice > 0,
                  quote.regularMarketPrice.isFinite else {
                logger.debug("Skipping invalid quote for \(ticker): price=\(quote.regularMarketPrice)")
                continue
            }
            
            // Only update if we have meaningful data
            quotes[ticker] = quote
            updatedCount += 1
        }
        
        lastUpdateAt = Date()
        
        // Only emit if we actually updated something
        if updatedCount > 0 {
            quotesSubject.send(quotes)
            logger.info("Updated \(updatedCount) stock quotes")
        }
    }
    
    // MARK: - Market Hours
    
    private func updateMarketStatus() {
        isMarketOpen = checkMarketOpen()
        applyPollingState()
    }
    
    private func checkMarketOpen() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        
        // Get Eastern Time zone
        guard let eastern = TimeZone(identifier: "America/New_York") else {
            return false
        }
        
        // Get current date/time in Eastern
        let components = calendar.dateComponents(in: eastern, from: now)
        
        // Check day of week (1 = Sunday, 7 = Saturday)
        let weekday = components.weekday ?? 1
        if weekday == 1 || weekday == 7 {
            return false  // Weekend
        }
        
        // Check time (market hours: 9:30 AM - 4:00 PM ET)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        
        // Before 9:30 AM
        if hour < 9 || (hour == 9 && minute < 30) {
            return false
        }
        
        // After 4:00 PM
        if hour >= 16 {
            return false
        }
        
        // Check for common US market holidays
        if isMarketHoliday(date: now, calendar: calendar, timezone: eastern) {
            return false
        }
        
        return true
    }
    
    private func isMarketHoliday(date: Date, calendar: Calendar, timezone: TimeZone) -> Bool {
        var cal = calendar
        cal.timeZone = timezone
        
        let components = cal.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return false
        }
        
        // Major US market holidays (simplified)
        let holidays: [(Int, Int)] = [
            (1, 1),   // New Year's Day
            (7, 4),   // Independence Day
            (12, 25), // Christmas Day
        ]
        
        for (holidayMonth, holidayDay) in holidays {
            if month == holidayMonth && day == holidayDay {
                return true
            }
        }
        
        // MLK Day (3rd Monday in January)
        if month == 1 {
            if let mlkDay = nthWeekday(nth: 3, weekday: 2, month: 1, year: year, calendar: cal) {
                if cal.isDate(date, inSameDayAs: mlkDay) {
                    return true
                }
            }
        }
        
        // Presidents' Day (3rd Monday in February)
        if month == 2 {
            if let presDay = nthWeekday(nth: 3, weekday: 2, month: 2, year: year, calendar: cal) {
                if cal.isDate(date, inSameDayAs: presDay) {
                    return true
                }
            }
        }
        
        // Memorial Day (last Monday in May)
        if month == 5 {
            if let memDay = lastWeekday(weekday: 2, month: 5, year: year, calendar: cal) {
                if cal.isDate(date, inSameDayAs: memDay) {
                    return true
                }
            }
        }
        
        // Labor Day (1st Monday in September)
        if month == 9 {
            if let laborDay = nthWeekday(nth: 1, weekday: 2, month: 9, year: year, calendar: cal) {
                if cal.isDate(date, inSameDayAs: laborDay) {
                    return true
                }
            }
        }
        
        // Thanksgiving (4th Thursday in November)
        if month == 11 {
            if let tgiving = nthWeekday(nth: 4, weekday: 5, month: 11, year: year, calendar: cal) {
                if cal.isDate(date, inSameDayAs: tgiving) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func nthWeekday(nth: Int, weekday: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.weekday = weekday
        components.weekdayOrdinal = nth
        return calendar.date(from: components)
    }
    
    private func lastWeekday(weekday: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
        // Find the last weekday of the month
        var components = DateComponents()
        components.year = year
        components.month = month + 1  // Next month
        components.day = 0  // Last day of previous month
        
        guard let lastDay = calendar.date(from: components) else { return nil }
        
        // Find the last occurrence of the weekday
        var currentDay = lastDay
        while calendar.component(.weekday, from: currentDay) != weekday {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDay) else {
                return nil
            }
            currentDay = previousDay
        }
        
        return currentDay
    }
}

// MARK: - Portfolio Integration Extension

extension LiveStockPriceManager {
    /// Update portfolio holdings with latest stock prices
    /// - Parameter holdings: Array of holdings to update
    /// - Returns: Updated holdings array
    func updateHoldings(_ holdings: [Holding]) -> [Holding] {
        holdings.map { holding in
            // Only update stock/ETF/commodity holdings
            guard holding.assetType == .stock || holding.assetType == .etf || holding.assetType == .commodity else {
                return holding
            }
            
            let ticker = (holding.ticker ?? holding.coinSymbol).uppercased()
            guard let quote = quotes[ticker] else {
                return holding
            }
            
            // Create updated holding
            var updated = holding
            updated.currentPrice = quote.regularMarketPrice
            // Calculate change: prefer API value, fallback to previousClose calculation
            updated.dailyChange = quote.regularMarketChangePercent ?? {
                if let prevClose = quote.regularMarketPreviousClose, prevClose > 0 {
                    return ((quote.regularMarketPrice - prevClose) / prevClose) * 100
                }
                return 0
            }()
            return updated
        }
    }
    
    /// Extract stock/ETF/commodity tickers from portfolio holdings
    /// - Parameter holdings: Portfolio holdings
    /// - Returns: Array of ticker symbols
    func extractStockTickers(from holdings: [Holding]) -> [String] {
        holdings.compactMap { holding in
            guard holding.assetType == .stock || holding.assetType == .etf || holding.assetType == .commodity else {
                return nil
            }
            return (holding.ticker ?? holding.coinSymbol).uppercased()
        }
    }
    
    /// Start tracking stocks from portfolio
    /// - Parameter holdings: Portfolio holdings
    func trackFromPortfolio(_ holdings: [Holding]) {
        let tickers = extractStockTickers(from: holdings)
        setTickers(tickers, source: "portfolio")
    }
}

// MARK: - Settings Integration

extension LiveStockPriceManager {
    /// Whether live stock updates are enabled (stored in UserDefaults)
    var liveUpdatesEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "liveStockUpdatesEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "liveStockUpdatesEnabled") }
    }
    
    /// User preference for polling during market hours only (stored in UserDefaults)
    var marketHoursOnly: Bool {
        get { UserDefaults.standard.bool(forKey: "stockPollingMarketHoursOnly") }
        set { UserDefaults.standard.set(newValue, forKey: "stockPollingMarketHoursOnly") }
    }
    
    /// Check if polling should be active based on settings
    func shouldPoll() -> Bool {
        guard liveUpdatesEnabled else { return false }
        if marketHoursOnly && !isMarketOpen { return false }
        return true
    }
}
