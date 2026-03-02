//
//  PriceViewModel.swift
//  CSAI1
//
//  Updated by ChatGPT on 2025-06-07 to enable live WebSocket updates and fix historical URL builder
//

import Foundation
import Combine
import SwiftUI
import os
#if canImport(UIKit)
import UIKit
#endif

// MARK: - ChartTimeframe Definition
enum ChartTimeframe {
    case oneMinute, fiveMinutes, fifteenMinutes, thirtyMinutes
    case oneHour, fourHours, oneDay, oneWeek, oneMonth, threeMonths
    case oneYear, threeYears, allTime
    case live
}

struct BinancePriceResponse: Codable {
    let price: String
}

struct CoinGeckoPriceResponse: Codable {
    let usd: Double?
    
    /// Decode any currency key from CoinGecko's simple/price response
    /// The response shape is {"bitcoin": {"usd": 95000}} or {"bitcoin": {"eur": 87000}}
    /// This uses a flexible decoder that accepts any single currency key.
    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        // Try the selected currency first, then fall back to "usd"
        let currencyKey = CurrencyManager.apiValue
        if let key = DynamicKey(stringValue: currencyKey),
           let value = try? container.decode(Double.self, forKey: key) {
            self.usd = value
        } else if let key = DynamicKey(stringValue: "usd"),
                  let value = try? container.decode(Double.self, forKey: key) {
            self.usd = value
        } else {
            // Try any available key
            let allKeys = container.allKeys
            if let firstKey = allKeys.first,
               let value = try? container.decode(Double.self, forKey: firstKey) {
                self.usd = value
            } else {
                self.usd = nil
            }
        }
    }
}

struct PriceChartResponse: Codable {
    let prices: [[Double]]
}

/// Helper class for weak references in collections
private class WeakRef<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

@MainActor
class PriceViewModel: ObservableObject {
    // MARK: - Instance Cache (PERFORMANCE FIX)
    // Share PriceViewModel instances by symbol to avoid duplicate polling
    private static var instanceCache: [String: WeakRef<PriceViewModel>] = [:]
    private static let instanceCacheLock = NSLock()
    
    /// Get or create a shared PriceViewModel instance for a symbol.
    /// This prevents multiple views from creating duplicate polling mechanisms for the same coin.
    static func shared(for symbol: String, timeframe: ChartTimeframe = .live) -> PriceViewModel {
        let key = symbol.uppercased()
        instanceCacheLock.lock()
        defer { instanceCacheLock.unlock() }
        
        // Clean up expired weak references periodically
        if instanceCache.count > 50 {
            instanceCache = instanceCache.filter { $0.value.value != nil }
        }
        
        if let existing = instanceCache[key]?.value {
            // Update timeframe if different
            if existing.timeframe != timeframe {
                existing.timeframe = timeframe
            }
            return existing
        }
        
        let newInstance = PriceViewModel(symbol: symbol, timeframe: timeframe)
        instanceCache[key] = WeakRef(newInstance)
        return newInstance
    }
    
    /// MEMORY FIX v14: Clear all static caches across all PriceViewModel instances.
    /// Called during emergency memory cleanup. Chart data and gecko prices will be
    /// re-fetched from the network when needed.
    static func clearAllStaticCaches() {
        instanceCacheLock.lock()
        // Clear historicalCache on each live instance
        for (_, weakRef) in instanceCache {
            if let vm = weakRef.value {
                vm.historicalCache.removeAll()
                vm.historicalData = []
                vm.liveData = []
                vm.recentPriceBuffer = []
            }
        }
        // Clear expired weak refs + gecko cache
        instanceCache = instanceCache.filter { $0.value.value != nil }
        instanceCacheLock.unlock()
        geckoCache.removeAll()
        #if DEBUG
        print("🗑️ [PriceViewModel] Cleared all static caches (historicalCache, geckoCache, chart data)")
        #endif
    }
    
    // Shared URLSession with custom timeout
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private let logger = Logger(subsystem: "CryptoSage", category: "PriceViewModel")
    private enum TopPriceSource: String { case ws = "WS", manager = "Manager", gecko = "CoinGecko" }
    private var activeSource: TopPriceSource? = nil
    private var sourceStickyUntil: Date = .distantPast
    
    // PERFORMANCE FIX: Rate-limit source switch logging to prevent console spam
    // Only log source changes once per minute to avoid flooding the console
    private static var lastSourceLogTime: [String: Date] = [:]
    private static let sourceLogMinInterval: TimeInterval = 60.0
    
    private func canAccept(source: TopPriceSource) -> Bool {
        let now = Date()
        if now < sourceStickyUntil, let active = activeSource { return active == source }
        return true
    }
    
    /// Rate-limited logging for price source changes to prevent console spam
    private func logSourceChange(to source: TopPriceSource) {
        let key = "\(symbol)_\(source.rawValue)"
        let now = Date()
        if let lastLog = Self.lastSourceLogTime[key],
           now.timeIntervalSince(lastLog) < Self.sourceLogMinInterval {
            return // Skip logging - too soon since last log for this source
        }
        Self.lastSourceLogTime[key] = now
        logger.debug("TopPriceSource=\(source.rawValue)")
    }
    
    @Published var price: Double = 0
    @Published var symbol: String
    @Published var historicalData: [ChartDataPoint] = []
    @Published var liveData: [ChartDataPoint] = []
    @Published var timeframe: ChartTimeframe
    
    @Published var priceSourceLabel: String = ""
    @Published var isStale: Bool = false
    
    /// Indicates the current price transport mode for UI display
    /// Note: Both ws and polling show as "Live" to users - they don't need to know the transport mechanism
    enum PriceTransportMode: String {
        case ws
        case polling
        case offline
        
        /// User-friendly display string - hides technical transport details
        var displayString: String {
            switch self {
            case .ws, .polling: return "Live"
            case .offline: return "Offline"
            }
        }
    }
    @Published var transportMode: PriceTransportMode = .polling
    
    private let service = CryptoAPIService.shared
    // WebSocket-based price publisher service
    private let wsService: PriceService = BinanceWebSocketPriceService.shared
    private var liveCancellable: AnyCancellable?
    // CoinGecko polling subscription for live prices
    private var livePriceCancellable: AnyCancellable?
    private var unifiedPriceCancellable: AnyCancellable?
    
    private var pollingTask: Task<Void, Never>?
    private var lastPriceTickAt: Date = .distantPast
    private let maxBackoff: Double = 60.0
    
    private var aggressivePollTask: Task<Void, Never>?
    private var liveGuardTask: Task<Void, Never>?
    
    private var lastWSTickAt: Date = .distantPast
    private var lastManagerTickAt: Date = .distantPast
    private var lastGeckoTickAt: Date = .distantPast

    private var wsFailureCount = 0
    private var wsCooldownUntil: Date = .distantPast
    // PERFORMANCE FIX v21: After 8 WS failures, stop attempting reconnection entirely.
    // Logs show circuit-breaker cycling 1→2→3→4→5→max indefinitely, each attempt spawning
    // new WebSocket connections that immediately fail (Coinbase geo-blocked or throttled).
    // After 8 failures, rely on REST polling only until next explicit user navigation.
    private let maxWSFailures = 8
    private var lastStaleRefreshAt: Date = .distantPast

    private var isInBackground = false
    private var lifecycleCancellables = Set<AnyCancellable>()
    private var historicalCache: [String: (Date, [ChartDataPoint])] = [:]
    private let lastPriceKeyPrefix = "lastPrice_"
    private let lastPriceAtKeyPrefix = "lastPriceAt_"
    
    // MARK: - Outlier Detection Buffer
    /// Circular buffer of recent prices for outlier detection
    private var recentPriceBuffer: [Double] = []
    private let priceBufferSize = 5
    
    /// Check if a new price is an outlier compared to recent prices.
    /// Returns true if price should be accepted, false if it's an outlier.
    private func isAcceptablePrice(_ newPrice: Double) -> Bool {
        guard !recentPriceBuffer.isEmpty else { return true }
        
        // Calculate median of recent prices
        let sorted = recentPriceBuffer.sorted()
        let median: Double
        if sorted.count % 2 == 0 {
            median = (sorted[sorted.count/2 - 1] + sorted[sorted.count/2]) / 2.0
        } else {
            median = sorted[sorted.count/2]
        }
        
        // Reject prices that deviate more than 10% from the median
        // PRICE CONSISTENCY FIX: Relaxed from 5% to 10% to allow faster price convergence
        // during volatile markets where prices can move quickly
        let deviation = abs(newPrice - median) / max(median, 1e-9)
        let maxDeviation: Double = 0.10 // 10% threshold (relaxed from 5% to handle volatile markets)
        
        return deviation <= maxDeviation
    }
    
    /// Add a price to the recent buffer (for outlier detection)
    private func recordPriceInBuffer(_ price: Double) {
        recentPriceBuffer.append(price)
        if recentPriceBuffer.count > priceBufferSize {
            recentPriceBuffer.removeFirst()
        }
    }

    // Safely mutate published price to avoid "Modifying state during view update"
    private func applyPriceUpdate(_ newPrice: Double, animated: Bool) {
        // Validate
        guard newPrice.isFinite, newPrice > 0 else { return }

        let priceKey = self.lastPriceKeyPrefix + self.symbol.uppercased()
        let atKey = self.lastPriceAtKeyPrefix + self.symbol.uppercased()
        let symUpper = self.symbol.uppercased()

        // Always defer to next runloop tick to avoid touching state during view updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Apply update (deferred) and persist. Keep animations minimal from the VM.
            let apply = {
                self.price = newPrice
                UserDefaults.standard.set(newPrice, forKey: priceKey)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: atKey)
                
                // PRICE CONSISTENCY FIX: Sync to LivePriceManager so all views see the same price
                // This ensures TradeView, CoinDetailView, and HomeView all display the same price
                // when they query MarketViewModel.bestPrice()
                let source: LivePriceManager.PriceSource = {
                    switch self.activeSource {
                    case .ws: return .binance      // WebSocket is from Binance
                    case .manager: return .binance // Manager gets data from Binance
                    case .gecko: return .coinGecko
                    case .none: return .binance    // Default to Binance
                    }
                }()
                LivePriceManager.shared.update(symbol: symUpper, price: newPrice, source: source)
            }

            if animated && !self.isInBackground {
                withAnimation(.linear(duration: 0.18)) { apply() }
            } else {
                apply()
            }
        }
    }

    // PERFORMANCE FIX v21: Also return true if maxWSFailures exceeded, to stop reconnection entirely
    private func inWSCooldown() -> Bool { wsFailureCount >= maxWSFailures || Date() < wsCooldownUntil }

    private func noteWSFailure() {
        let previousCount = wsFailureCount
        wsFailureCount += 1
        let backoff = min(60.0, pow(2.0, Double(min(wsFailureCount, 5)))) // 2,4,8,16,32,60
        wsCooldownUntil = Date().addingTimeInterval(backoff)
        // LOG SPAM FIX: Only log for first 5 failures (while backoff is still increasing), then stop
        if wsFailureCount <= 5 {
            self.logger.warning("WS circuit-breaker engaged for \(backoff, privacy: .public)s after \(self.wsFailureCount, privacy: .public) failures")
        } else if previousCount == 5 {
            // Log once when reaching max backoff
            self.logger.warning("WS circuit-breaker at max backoff (60s) - suppressing further logs until success")
        }
    }

    private func noteWSSuccess() {
        wsFailureCount = 0
        wsCooldownUntil = .distantPast
    }
    
    #if canImport(UIKit)
    private func setupLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isInBackground = true
                    if self.timeframe == .live {
                        self.stopLiveUpdates()
                        self.startLiveUpdates(coinID: self.coingeckoID(for: self.symbol))
                    }
                }
            }
            .store(in: &lifecycleCancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isInBackground = false
                    if self.timeframe == .live {
                        self.stopLiveUpdates()
                        self.startLiveUpdates(coinID: self.coingeckoID(for: self.symbol))
                    }
                }
            }
            .store(in: &lifecycleCancellables)
    }
    #else
    private func setupLifecycleObservers() { /* no-op on non-UIKit platforms */ }
    #endif

    private func loadLastPriceSeed() {
        let key = lastPriceKeyPrefix + symbol.uppercased()
        let atKey = lastPriceAtKeyPrefix + symbol.uppercased()
        let stored = UserDefaults.standard.double(forKey: key)
        let ts = UserDefaults.standard.double(forKey: atKey)
        if stored > 0, ts > 0 {
            let age = Date().timeIntervalSince1970 - ts
            if age < 48 * 3600 {
                self.price = stored
            }
        }
    }

    private func historicalCacheKey(coinID: String, timeframe: ChartTimeframe) -> String {
        let tf: String
        switch timeframe {
        case .oneMinute: tf = "1m"
        case .fiveMinutes: tf = "5m"
        case .fifteenMinutes: tf = "15m"
        case .thirtyMinutes: tf = "30m"
        case .oneHour: tf = "1h"
        case .fourHours: tf = "4h"
        case .oneDay: tf = "1d"
        case .oneWeek: tf = "1w"
        case .oneMonth: tf = "1mo"
        case .threeMonths: tf = "3mo"
        case .oneYear: tf = "1y"
        case .threeYears: tf = "3y"
        case .allTime: tf = "all"
        case .live: tf = "live"
        }
        return coinID + "|" + tf
    }

    private func historicalTTL(for timeframe: ChartTimeframe) -> TimeInterval {
        switch timeframe {
        case .oneMinute, .fiveMinutes, .fifteenMinutes, .thirtyMinutes:
            return 5 * 60
        case .oneHour, .fourHours:
            return 10 * 60
        case .oneDay:
            return 30 * 60
        case .oneWeek, .oneMonth, .threeMonths:
            return 60 * 60
        case .oneYear, .threeYears, .allTime:
            return 6 * 60 * 60
        case .live:
            return 0
        }
    }
    
    init(symbol: String, timeframe: ChartTimeframe = .live) {
        self.symbol = symbol
        self.timeframe = timeframe
        self.setupLifecycleObservers()
        self.loadLastPriceSeed()
        startPolling()
    }
    
    func updateSymbol(_ newSymbol: String) {
        let normalized = newSymbol.uppercased()
        // If symbol is the same but live is stale, force a refresh
        if normalized == symbol.uppercased() {
            let stale = Date().timeIntervalSince(lastPriceTickAt) > 5 || price <= 0
            let sinceLastRefresh = Date().timeIntervalSince(lastStaleRefreshAt)
            if timeframe == .live && stale && sinceLastRefresh > 10 {
                lastStaleRefreshAt = Date()
                #if DEBUG
                print("PriceViewModel: same symbol \(normalized) but live is stale; refreshing live updates")
                #endif
                stopPolling()
                startPolling()
            } else {
                #if DEBUG
                print("PriceViewModel: updateSymbol called with same symbol \(normalized), skipping")
                #endif
            }
            return
        }
        symbol = normalized
        stopPolling()
        startPolling()
    }
    
    func updateTimeframe(_ newTimeframe: ChartTimeframe) {
        guard newTimeframe != timeframe else { return }
        timeframe = newTimeframe
        stopPolling()
        startPolling()
    }
    
    // MARK: - REST Polling with Backoff
    func startPolling() {
        aggressivePollTask?.cancel()
        aggressivePollTask = nil
        liveGuardTask?.cancel()
        liveGuardTask = nil
        
        liveCancellable?.cancel()
        pollingTask?.cancel()
        if timeframe == .live {
            let id = coingeckoID(for: symbol)
            startLiveUpdates(coinID: id)
            return
        }
        pollingTask = Task { [weak self] in
            guard let self = self else { return }
            // Immediate initial fetch
            if let initial = await self.fetchPriceChain(for: self.symbol) {
                _ = await MainActor.run {
                    Task { @MainActor [weak self] in
                        self?.applyPriceUpdate(initial, animated: false)
                    }
                }
            }
            // Start backoff loop
            var delay: Double = 5
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if let newPrice = await self.fetchPriceChain(for: self.symbol) {
                    _ = await MainActor.run {
                        Task { @MainActor [weak self] in
                            self?.applyPriceUpdate(newPrice, animated: false)
                        }
                    }
                    delay = 5
                } else {
                    delay = min(self.maxBackoff, delay * 2)
                }
            }
        }
    }
    
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        stopLiveUpdates()
        
        aggressivePollTask?.cancel()
        aggressivePollTask = nil
        liveGuardTask?.cancel()
        liveGuardTask = nil
    }
    
    // Price fetching with special handling for precious metals
    // Precious metals: Use Coinbase directly (Binance/CoinGecko don't have them)
    // Crypto: CryptoAPIService → Binance → CoinGecko fallback chain
    private func fetchPriceChain(for symbol: String) async -> Double? {
        let upperSymbol = symbol.uppercased()
        
        // For precious metals, use Coinbase directly (they won't be on Binance/CoinGecko)
        if PreciousMetalsHelper.isPreciousMetal(upperSymbol) {
            if let price = await CoinbaseService.shared.fetchSpotPrice(coin: upperSymbol) {
                #if DEBUG
                print("💰 [PriceVM] Fetched precious metal price for \(upperSymbol): $\(price)")
                #endif
                return price
            }
            return nil
        }
        
        // Standard crypto fallback chain
        if let p = try? await service.fetchSpotPrice(coin: symbol) {
            return p
        }
        if let p = await fetchBinancePrice(for: symbol) {
            return p
        }
        return await fetchCoingeckoPrice(for: symbol)
    }
    
    private func binanceTickerURL(for pair: String, endpoints: ExchangeEndpoints) -> URL? {
        var comps = URLComponents(url: endpoints.restBase.appendingPathComponent("ticker/price"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "symbol", value: pair)]
        return comps?.url
    }
    
    private func fetchBinancePrice(for symbol: String) async -> Double? {
        if !NetworkReachability.shared.isReachable { return nil }
        let isUS = ComplianceManager.shared.isUSUser
        let quote = isUS ? "USD" : "USDT"
        let pair = symbol.uppercased() + quote

        func buildURL(from endpoints: ExchangeEndpoints) -> URL? {
            var comps = URLComponents(url: endpoints.restBase.appendingPathComponent("ticker/price"), resolvingAgainstBaseURL: false)
            comps?.queryItems = [URLQueryItem(name: "symbol", value: pair)]
            return comps?.url
        }

        let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()

        guard let initial = buildURL(from: endpoints) else { return nil }

        let session = self.session

        do {
            let (data, _) = try await ExchangeHTTP.getWithPolicyFallback(
                initial: initial,
                session: session,
                buildFromEndpoints: { eps in buildURL(from: eps)! }
            )
            if let decoded = try? JSONDecoder().decode(BinancePriceResponse.self, from: data),
               let val = Double(decoded.price), val > 0 {
                return val
            }
        } catch {
            return nil
        }
        return nil
    }
    
    /// Map common ticker symbols to CoinGecko IDs
    private func coingeckoID(for symbol: String) -> String {
        switch symbol.uppercased() {
        case "BTC": return "bitcoin"
        case "ETH": return "ethereum"
        case "DOGE": return "dogecoin"
        case "ADA": return "cardano"
        case "SOL": return "solana"
        case "XRP": return "ripple"
        case "DOT": return "polkadot"
        case "MATIC": return "matic-network"
        // add any other symbols you use as needed
        default:
            return symbol.lowercased()
        }
    }
    
    // PERFORMANCE FIX: Static cache for CoinGecko price lookups
    private static var geckoCache: [String: (price: Double, fetchedAt: Date)] = [:]
    private static let geckoCacheTTL: TimeInterval = 120.0 // RATE LIMIT FIX: Increased from 30s - Firestore provides fresher data
    private static let maxGeckoCacheSize = 50
    
    private func fetchCoingeckoPrice(for symbol: String) async -> Double? {
        if !NetworkReachability.shared.isReachable { return nil }
        let id = coingeckoID(for: symbol)
        
        // PERFORMANCE FIX: Check cache first
        let now = Date()
        if let cached = Self.geckoCache[id],
           now.timeIntervalSince(cached.fetchedAt) < Self.geckoCacheTTL {
            return cached.price
        }
        
        // PERFORMANCE FIX: Check rate limiter
        guard APIRequestCoordinator.shared.canMakeRequest(for: .coinGecko) else {
            // Return cached value if available
            if let cached = Self.geckoCache[id] {
                return cached.price
            }
            return nil
        }
        
        APIRequestCoordinator.shared.recordRequest(for: .coinGecko)
        
        var comps = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")
        comps?.queryItems = [
            URLQueryItem(name: "ids", value: id),
            URLQueryItem(name: "vs_currencies", value: CurrencyManager.apiValue)
        ]
        guard let url = comps?.url else {
            APIRequestCoordinator.shared.recordFailure(for: .coinGecko)
            return nil
        }
        do {
            let req = APIConfig.coinGeckoRequest(url: url)
            let (data, _) = try await session.data(for: req)
            let dict = try JSONDecoder().decode([String: CoinGeckoPriceResponse].self, from: data)
            if let price = dict[id]?.usd {
                // PERFORMANCE FIX: Update cache
                Self.geckoCache[id] = (price, Date())
                // MEMORY FIX v14: Evict stale entries when cache grows beyond limit
                if Self.geckoCache.count > Self.maxGeckoCacheSize {
                    let cutoff = Date().addingTimeInterval(-Self.geckoCacheTTL * 2)
                    Self.geckoCache = Self.geckoCache.filter { $0.value.fetchedAt > cutoff }
                }
                APIRequestCoordinator.shared.recordSuccess(for: .coinGecko)
                return price
            }
            APIRequestCoordinator.shared.recordFailure(for: .coinGecko)
            return nil
        } catch {
            APIRequestCoordinator.shared.recordFailure(for: .coinGecko)
            return nil
        }
    }
    
    // MARK: - Live WebSocket Updates
    func startLiveUpdates(coinID: String) {
        // Cancel any existing polling or previous live subscriptions
        pollingTask?.cancel()
        livePriceCancellable?.cancel()
        unifiedPriceCancellable?.cancel()
        unifiedPriceCancellable = nil

        aggressivePollTask?.cancel()
        aggressivePollTask = nil
        liveGuardTask?.cancel()
        liveGuardTask = nil

        // Use the BinanceWebSocketPriceService to stream live ticks for this symbol
        // Unified live price stream: prefer app-wide LivePriceManager feed, merge with WS and CoinGecko fallbacks.
        let symbolUpper = self.symbol.uppercased()
        // PRICE CONSISTENCY FIX: Reduced stickiness from 30s to 10s for faster convergence
        // This allows prices to update more quickly when switching between sources,
        // reducing visible discrepancies across different views
        let sourceStickiness: TimeInterval = 10 // seconds (reduced from 30 to allow faster convergence)

        let pref = AppSettings.priceSourcePreference

        let managerStream: AnyPublisher<Double, Never> = {
            if pref == .ws || pref == .gecko { return Empty<Double, Never>().eraseToAnyPublisher() }
            // PERFORMANCE FIX v22: Use realtimePublisher (200ms throttle) instead of raw publisher.
            // CoinDetail needs fast updates but not every single emission — 200ms is sufficient
            // for showing live prices while reducing processing overhead.
            return LivePriceManager.shared.realtimePublisher
                .compactMap { coins -> Double? in
                    coins.first(where: { $0.symbol.uppercased() == symbolUpper })?.priceUsd
                }
                .filter { $0.isFinite && $0 > 0 }
                .filter { [weak self] _ in
                    guard let self = self else { return true }
                    // PRICE CONSISTENCY FIX: Reduced from 10s to 5s for faster fallback to manager
                    // This ensures views show consistent prices more quickly when WS is silent
                    return Date().timeIntervalSince(self.lastWSTickAt) > 5
                }
                .filter { [weak self] _ in (self?.canAccept(source: .manager) ?? true) }
                .handleEvents(receiveOutput: { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.lastManagerTickAt = Date()
                        self?.priceSourceLabel = "Manager"
                        self?.transportMode = .polling // Manager is app-level overlay, not direct WS
                        if self?.activeSource != .manager {
                            self?.activeSource = .manager
                            self?.sourceStickyUntil = Date().addingTimeInterval(sourceStickiness)
                            self?.logSourceChange(to: .manager)
                        }
                    }
                })
                .eraseToAnyPublisher()
        }()

        let wsStream: AnyPublisher<Double, Never> = {
            if pref == .manager || pref == .gecko { return Empty<Double, Never>().eraseToAnyPublisher() }
            if self.inWSCooldown() || self.isInBackground {
                return Empty<Double, Never>().eraseToAnyPublisher()
            }
            return wsService
                .pricePublisher(for: [symbolUpper], interval: 1.0)
                .map { dict -> Double in
                    if let v = dict[symbolUpper] { return v }
                    let pair = symbolUpper.hasSuffix("USDT") ? symbolUpper : (symbolUpper + "USDT")
                    if let v = dict[pair] { return v }
                    let quotes = ["USDT","USD","BUSD","USDC"]
                    for q in quotes where pair.hasSuffix(q) {
                        let base = String(pair.dropLast(q.count))
                        if let v = dict[base] { return v }
                    }
                    return 0
                }
                .filter { $0.isFinite && $0 > 0 }
                .filter { [weak self] _ in (self?.canAccept(source: .ws) ?? true) }
                .handleEvents(receiveOutput: { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.noteWSSuccess()
                        self?.lastWSTickAt = Date()
                        self?.priceSourceLabel = "WS"
                        self?.transportMode = .ws // Direct WebSocket connection
                        if self?.activeSource != .ws {
                            self?.activeSource = .ws
                            self?.sourceStickyUntil = Date().addingTimeInterval(sourceStickiness)
                            self?.logSourceChange(to: .ws)
                        }
                    }
                })
                .eraseToAnyPublisher()
        }()

        // PERFORMANCE FIX: CoinGecko fallback stream with drastically reduced frequency
        // Changed: check interval from 2s to 45s, silence threshold from 12s to 90s, poll interval from 6s to 90s
        let geckoStream: AnyPublisher<Double, Never> = {
            if pref == .ws || pref == .manager { return Empty<Double, Never>().eraseToAnyPublisher() }
            let geckoEnabledInitially: Bool = {
                let now = Date()
                // Only enable CoinGecko fallback after 90s of silence from primary sources (increased from 60s)
                return now.timeIntervalSince(self.lastWSTickAt) > 90 &&
                       now.timeIntervalSince(self.lastManagerTickAt) > 90
            }()
            return Timer.publish(every: 45.0, on: .main, in: .common)  // Increased from 30s to 45s
                .autoconnect()
                .map { [weak self] _ -> Bool in
                    guard let self = self else { return false }
                    let now = Date()
                    // PERFORMANCE FIX: Also check rate limiter before enabling gecko stream
                    guard APIRequestCoordinator.shared.canMakeRequest(for: .coinGecko) else {
                        return false
                    }
                    return now.timeIntervalSince(self.lastWSTickAt) > 90 &&  // Increased from 60s to 90s
                           now.timeIntervalSince(self.lastManagerTickAt) > 90
                }
                .prepend(geckoEnabledInitially)
                .removeDuplicates()
                .map { [weak self] enabled -> AnyPublisher<Double, Never> in
                    guard let self = self else { return Empty<Double, Never>().eraseToAnyPublisher() }
                    if enabled {
                        guard NetworkReachability.shared.isReachable else { return Empty<Double, Never>().eraseToAnyPublisher() }
                        // PERFORMANCE FIX: Increased intervals significantly to 90s
                        let interval: TimeInterval = self.isInBackground ? 180.0 : 90.0
                        return CryptoAPIService.shared
                            .liveSpotPricePublisher(for: symbolUpper, interval: interval)
                            .filter { $0.isFinite && $0 > 0 }
                            .eraseToAnyPublisher()
                    } else {
                        return Empty<Double, Never>().eraseToAnyPublisher()
                    }
                }
                .switchToLatest()
                .handleEvents(receiveOutput: { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.lastGeckoTickAt = Date()
                        self?.priceSourceLabel = "CoinGecko"
                        self?.transportMode = .polling // CoinGecko is REST polling fallback
                        if self?.activeSource != .gecko {
                            self?.activeSource = .gecko
                            self?.sourceStickyUntil = Date().addingTimeInterval(sourceStickiness)
                            self?.logSourceChange(to: .gecko)
                        }
                    }
                })
                .eraseToAnyPublisher()
        }()

        let unifiedThrottle: TimeInterval = self.isInBackground ? 3.0 : 0.75 // Faster updates in foreground for price consistency
        // Relaxed clamping: for BTC at $83K, max jump is now ~$415 (0.5%) to keep up with order book
        let clampPct: Double = self.isInBackground ? 0.008 : 0.005

        // Merge all streams and stabilize
        unifiedPriceCancellable = Publishers.Merge3(wsStream, managerStream, geckoStream)
            // Remove micro-noise: ignore changes below max(10 cents, 0.05%)
            // More aggressive filtering to prevent jitter from source switching
            .removeDuplicates(by: { a, b in
                let tol = max(0.10, 0.0005 * max(a, b))
                return abs(a - b) < tol
            })
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main) // Increased from 150ms
            // Outlier detection: reject prices that deviate too much from recent median
            .filter { [weak self] newPrice in
                guard let self = self else { return true }
                // Always accept if buffer is too small (cold start)
                if self.recentPriceBuffer.count < 3 { return true }
                return self.isAcceptablePrice(newPrice)
            }
            // Sample at ~0.67 Hz for smoother updates
            .throttle(for: .seconds(unifiedThrottle), scheduler: RunLoop.main, latest: true)
            // Smoothing & clamp to avoid unrealistic one-tick jumps while keeping up with real prices
            .scan(nil as Double?) { prev, new in
                guard let prev = prev, prev.isFinite, prev > 0 else { return new as Double? }
                let pct = abs((new - prev) / max(prev, 1e-9))
                // Higher alpha = faster convergence to real price (was 0.20 base, now 0.40)
                let baseAlpha = 0.40
                let alpha = min(0.70, max(0.25, baseAlpha + (pct - 0.001) * 8.0))
                var smoothed = prev + alpha * (new - prev)
                // Much tighter max jump constraint
                let maxJump = max(0.50, prev * clampPct)
                if smoothed > prev + maxJump { smoothed = prev + maxJump }
                if smoothed < prev - maxJump { smoothed = prev - maxJump }
                return smoothed
            }
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] newPrice in
                guard let self = self else { return }
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // Record price in buffer for future outlier detection
                    self.recordPriceInBuffer(newPrice)
                    self.lastPriceTickAt = Date()
                    self.isStale = false
                    self.applyPriceUpdate(newPrice, animated: false)
                }
            }

        // PERFORMANCE FIX: Reduced aggressive seeding from 8 attempts at 1s to 3 attempts at 5s
        // This significantly reduces API spam during startup while still providing quick initial data
        aggressivePollTask = Task { [weak self] in
            guard let self = self else { return }
            var attempts = 0
            while !Task.isCancelled && attempts < 3 {  // Reduced from 8 to 3
                attempts += 1
                if self.isInBackground { break }
                if Date().timeIntervalSince(self.lastPriceTickAt) < 5 { break }  // Increased from 2s to 5s
                if !NetworkReachability.shared.isReachable {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)  // Increased from 1s to 5s
                    continue
                }
                if let p = await self.fetchPriceChain(for: self.symbol), p > 0 {
                    _ = await MainActor.run {
                        Task { @MainActor [weak self] in
                            self?.applyPriceUpdate(p, animated: false)
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)  // Increased from 1s to 5s
            }
        }

        // PERFORMANCE FIX: Live guard with reduced frequency
        // Changed: check interval from 3s to 15s, stale threshold from 6s to 45s, restart threshold from 20s to 90s
        // This drastically reduces fallback API calls while still recovering from failures
        liveGuardTask = Task { [weak self] in
            guard let self = self else { return }
            var noTickStreak: TimeInterval = 0
            while !Task.isCancelled && self.unifiedPriceCancellable != nil {
                try? await Task.sleep(nanoseconds: 15_000_000_000)  // Increased from 3s to 15s
                let elapsed = Date().timeIntervalSince(self.lastPriceTickAt)
                _ = await MainActor.run {
                    Task { @MainActor [weak self] in
                        self?.isStale = elapsed > 30  // Increased from 5s to 30s
                    }
                }
                if elapsed > 45 {  // Increased from 6s to 45s
                    if let fallback = await self.fetchPriceChain(for: self.symbol), fallback > 0 {
                        _ = await MainActor.run {
                            Task { @MainActor [weak self] in
                                guard let self = self else { return }
                                self.applyPriceUpdate(fallback, animated: false)
                                self.lastPriceTickAt = Date()
                            }
                        }
                    }
                }
                noTickStreak = elapsed
                if noTickStreak > 90 {  // Increased from 20s to 90s
                    _ = await MainActor.run { [coinID] in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            // PERFORMANCE FIX v21: Stop reconnection cycle after maxWSFailures.
                            // Without this cap, the app endlessly cycles: connect → fail → backoff → connect → fail
                            guard self.wsFailureCount < self.maxWSFailures else {
                                self.logger.warning("WS max failures (\(self.maxWSFailures)) reached — relying on REST polling only")
                                return
                            }
                            self.noteWSFailure()
                            // Restart pipeline; WS will be skipped during cooldown
                            self.stopLiveUpdates()
                            self.startLiveUpdates(coinID: coinID)
                        }
                    }
                    break
                }
            }
        }

        // Seed initial price immediately using the same fallback chain
        Task { [weak self] in
            guard let self = self else { return }
            if let seeded = await self.fetchPriceChain(for: self.symbol) {
                _ = await MainActor.run {
                    Task { @MainActor [weak self] in
                        if seeded > 0 { self?.applyPriceUpdate(seeded, animated: false) }
                    }
                }
            }
        }
    }
    
    func stopLiveUpdates() {
        livePriceCancellable?.cancel()
        livePriceCancellable = nil
        unifiedPriceCancellable?.cancel()
        unifiedPriceCancellable = nil
        lastPriceTickAt = .distantPast
        lastWSTickAt = .distantPast
        lastManagerTickAt = .distantPast
        lastGeckoTickAt = .distantPast
        activeSource = nil
        sourceStickyUntil = .distantPast
        // Clear price buffer when stopping (symbol may change)
        recentPriceBuffer.removeAll()
        
        aggressivePollTask?.cancel()
        aggressivePollTask = nil
        liveGuardTask?.cancel()
        liveGuardTask = nil
    }
    
    // MARK: - Historical Chart
    func fetchHistoricalData(for coinID: String, timeframe: ChartTimeframe) async {
        let cacheKey = historicalCacheKey(coinID: coinID, timeframe: timeframe)
        if let (ts, cached) = historicalCache[cacheKey] {
            if Date().timeIntervalSince(ts) < historicalTTL(for: timeframe) {
                self.historicalData = cached
                return
            }
        }
        // Normalize incoming id/symbol to a proper CoinGecko ID for robust history fetches
        let mappedID: String = {
            let trimmed = coinID.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("-") && trimmed.lowercased() == trimmed { return trimmed }
            // Reuse the local coingeckoID(symbol:) mapper from this VM
            return self.coingeckoID(for: trimmed)
        }()
        guard let url = CryptoAPIService.buildPriceHistoryURL(for: mappedID, timeframe: timeframe) else { return }
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(PriceChartResponse.self, from: data)
            let points = decoded.prices.map { arr in
                ChartDataPoint(date: Date(timeIntervalSince1970: arr[0] / 1000), close: arr[1], volume: 0)
            }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.historicalData = points
                self.historicalCache[cacheKey] = (Date(), points)
                // MEMORY FIX v14: Cap historicalCache to 10 entries to prevent unbounded growth.
                // Each entry stores 200-400 ChartDataPoints (~12 KB each). With many symbol/timeframe
                // combinations this can accumulate. Evict oldest entries beyond the limit.
                if self.historicalCache.count > 10 {
                    let sorted = self.historicalCache.sorted { $0.value.0 < $1.value.0 }
                    for (key, _) in sorted.prefix(self.historicalCache.count - 10) {
                        self.historicalCache.removeValue(forKey: key)
                    }
                }
            }
        } catch {
            #if DEBUG
            print("[PriceVM] Historical price fetch failed: \(error.localizedDescription)")
            #endif
        }
    }
}

