//
//  MarketStatsViewModel.swift
//  CryptoSage
//
//  Created by DM on 5/20/25.
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// Represents a single stat for display.
public struct Stat: Identifiable, Codable {
    public let id: UUID
    public let title: String
    public let value: String
    public let iconName: String

    public init(title: String, value: String, iconName: String) {
        self.id = UUID()
        self.title = title
        self.value = value
        self.iconName = iconName
    }
    public init(id: UUID, title: String, value: String, iconName: String) {
        self.id = id
        self.title = title
        self.value = value
        self.iconName = iconName
    }
}

@MainActor
public class MarketStatsViewModel: ObservableObject {
    // Throttle network fetches to avoid rate-limit bursts
    private let minFetchInterval: TimeInterval = 120 // seconds

    // Memoization flags to avoid repeatedly probing missing caches and spamming logs
    private static var didCheckLegacyGlobalCache = false
    private static var legacyGlobalCacheExists = false
    private static var didCheckCoinsCache = false
    private static var cachedCoinsFromDisk: [MarketCoin]? = nil

    @Published public private(set) var stats: [Stat] = []

    private var isFetching = false
    private var cancellables = Set<AnyCancellable>()
    private var statsTimer: AnyCancellable? = nil
    private let derivedRefreshInterval: TimeInterval = 240 // seconds

    private var lastFetchAt: Date? = nil
    private var lastGlobalSuccessAt: Date? = nil
    private var lastFallbackMarketsAttemptAt: Date? = nil
    private let fallbackMarketsCooldown: TimeInterval = 180 // 3 minutes

    private var degradedStreak: Int = 0
    private var cooldownUntil: Date? = nil

    private let cacheFileName = "market_stats_cache.json"
    
    // MARK: - Publish Debouncing
    // Prevents rapid stat updates that cause UI flickering
    private var lastPublishAt: Date = .distantPast
    private var pendingPublishWork: DispatchWorkItem? = nil
    private var pendingStats: [Stat]? = nil
    private let minPublishInterval: TimeInterval = 0.5 // 500ms debounce window
    
    // MARK: - Value Hysteresis (24h Change)
    // Only update 24h change if delta exceeds threshold to prevent flicker
    private var lastDisplayed24hChange: Double? = nil
    private let change24hHysteresisThreshold: Double = 0.05 // 0.05% minimum change to update

    public init() {
        // PERFORMANCE FIX v18: Defer ALL cache loading to after first frame renders.
        // Previously this did up to 4 synchronous file reads + writes during
        // HomeViewModel.init() → CryptoSageAIApp.init(), blocking the splash screen.
        // Stats are shown on the home screen but are small and populate quickly.
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // Yield to let splash render first
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            
            if let cached: [Stat] = CacheManager.shared.load([Stat].self, from: self.cacheFileName), !cached.isEmpty {
                self.stats = cached
            }
            // MIGRATION: repair old cache filenames and wrapper-shaped caches
            if self.stats.isEmpty {
                if let old: [Stat] = CacheManager.shared.load([Stat].self, from: "global_stats_cache.json"), !old.isEmpty {
                    self.stats = old
                    CacheManager.shared.save(old, to: self.cacheFileName)
                } else if ({
                    if !Self.didCheckLegacyGlobalCache {
                        if let _: GlobalMarketData = CacheManager.shared.load(GlobalMarketData.self, from: "global_cache.json") {
                            Self.legacyGlobalCacheExists = true
                        }
                        Self.didCheckLegacyGlobalCache = true
                    }
                    return Self.legacyGlobalCacheExists
                })(), let g: GlobalMarketData = CacheManager.shared.load(GlobalMarketData.self, from: "global_cache.json") {
                    let seeded: [Stat] = [
                        Stat(title: "Market Cap",      value: self.formatCurrency(g.totalMarketCap["usd"] ?? 0), iconName: "globe"),
                        Stat(title: "24h Volume",     value: self.formatCurrency(g.totalVolume["usd"] ?? 0),     iconName: "clock"),
                        Stat(title: "BTC Dom",        value: String(format: "%.2f%%", g.marketCapPercentage["btc"] ?? 0), iconName: "bitcoinsign.circle.fill"),
                        Stat(title: "ETH Dom",        value: String(format: "%.2f%%", g.marketCapPercentage["eth"] ?? 0), iconName: "diamond.fill"),
                        Stat(title: "24h Volatility", value: "—", iconName: "waveform.path.ecg"),
                        Stat(title: "24h Change",     value: String(format: "%.2f%%", g.marketCapChangePercentage24HUsd), iconName: "arrow.up.arrow.down.circle")
                    ]
                    self.stats = seeded
                    CacheManager.shared.save(seeded, to: self.cacheFileName)
                }
            }
            if self.stats.isEmpty || self.stats.prefix(4).allSatisfy({ $0.value == "$0.00" || $0.value == "0.00%" || $0.value == "0.00" }) {
                if let approx = self.derivedStatsFromLocalCoins() {
                    self.stats = approx
                    CacheManager.shared.save(approx, to: self.cacheFileName)
                }
            }
            
            self.setupSubscriptions()
        }

        // First-frame deferral: avoid competing with view mounting and potential web view startup.
        // This keeps the UI responsive while still loading stats shortly after launch.
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // ~1s
            await fetchStats()
        }

        if AppSettings.isSimulatorLimitedDataMode {
            #if DEBUG
            print("🧪 [MarketStatsVM] Simulator limited profile: eager fetch enabled, periodic refresh disabled")
            #endif
        } else {
            // Periodic global stats refresh to keep Market Cap/Volume/Dominance up to date
            // PERFORMANCE FIX v19: Changed .common to .default so timer pauses during scroll
            statsTimer = Timer.publish(every: 300, on: .main, in: .default)
                .autoconnect()
                .sink { [weak self] _ in
                    // PERFORMANCE FIX: Skip fetch during scroll
                    guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                    
                    Task {
                        let jitter = Double.random(in: 0...12)
                        try? await Task.sleep(nanoseconds: UInt64(jitter * 1_000_000_000))
                        await self?.fetchStats()
                    }
                }

            // Also refresh when app returns to foreground or significant time changes
            #if canImport(UIKit)
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                .sink { [weak self] _ in
                    Task { await self?.fetchStats() }
                }
                .store(in: &cancellables)
            #endif
            NotificationCenter.default.publisher(for: .NSSystemClockDidChange)
                .merge(with: NotificationCenter.default.publisher(for: .NSCalendarDayChanged))
                .sink { [weak self] _ in
                    Task { await self?.fetchStats() }
                }
                .store(in: &cancellables)
        }
        
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            DispatchQueue.main.async { [weak self] in
                self?.refreshFromLocalIfZeros()
            }
        }
        
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            DispatchQueue.main.async { [weak self] in
                self?.updateMarketCapFromLocalIfPlaceholder()
                self?.updateChange24hFromLocalIfPlaceholder()
            }
        }
    }
    
    /// Sets up Combine subscriptions to MarketViewModel.
    /// Called from init() via Task to defer singleton access and avoid circular initialization.
    /// PERFORMANCE FIX: Consolidated duplicate subscriptions to reduce overhead
    @MainActor private func setupSubscriptions() {
        let vm = MarketViewModel.shared
        
        // PERFORMANCE FIX: Consolidated three similar subscriptions into one with 500ms debounce
        // Previously had 3 subscriptions at 400ms, 450ms, and 600ms listening to the same publishers
        Publishers.Merge3(
            vm.$allCoins.map { _ in () },
            vm.$coins.map { _ in () },
            vm.$watchlistCoins.map { _ in () }
        )
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            guard let self = self else { return }
            // Choose the richest available coin set
            let coins: [MarketCoin] = {
                if !vm.allCoins.isEmpty { return vm.allCoins }
                if !vm.coins.isEmpty { return vm.coins }
                if !vm.watchlistCoins.isEmpty { return vm.watchlistCoins }
                return []
            }()
            // Compute volatility off-main to avoid blocking UI
            Task.detached(priority: .utility) {
                let liveMap = await MainActor.run { self.liveChange24hSnapshot(for: coins) }
                let vol = self.estimatedVolatility24h(using: nil, coinsOverride: coins, liveChange24h: liveMap)
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async { [weak self] in
                    // Consolidated from multiple subscriptions
                    self?.updateVolatilityInStats(vol)
                    self?.updateDerivedCoreStatsIfStale()
                    self?.updateMarketCapFromLocalIfPlaceholder()
                    self?.updateChange24hFromLocalIfPlaceholder()
                    self?.refreshFromLocalIfZeros()
                }
            }
        }
        .store(in: &cancellables)

        // Direct Firestore subscription: recalculate derived stats immediately when
        // FirestoreMarketSync delivers fresh CoinGecko coin data (the primary real-time source).
        // This closes the gap where MarketViewModel may not yet have processed the Firestore push.
        FirestoreMarketSync.shared.coingeckoCoinsPublisher
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] coins in
                guard let self = self, !coins.isEmpty else { return }
                Task.detached(priority: .utility) {
                    let liveMap = await MainActor.run { self.liveChange24hSnapshot(for: coins) }
                    let vol = self.estimatedVolatility24h(using: nil, coinsOverride: coins, liveChange24h: liveMap)
                    DispatchQueue.main.async { [weak self] in
                        self?.updateVolatilityInStats(vol)
                        self?.updateDerivedCoreStatsIfStale()
                        self?.updateMarketCapFromLocalIfPlaceholder()
                        self?.updateChange24hFromLocalIfPlaceholder()
                        self?.refreshFromLocalIfZeros()
                    }
                }
            }
            .store(in: &cancellables)

        // PERFORMANCE FIX: Consolidated four separate stat subscriptions into one using CombineLatest
        // This reduces subscription overhead and batches stat updates together
        Publishers.CombineLatest4(
            MarketViewModel.shared.$globalMarketCap.removeDuplicates(),
            MarketViewModel.shared.$globalChange24hPercent.removeDuplicates(),
            MarketViewModel.shared.$btcDominance.removeDuplicates(),
            MarketViewModel.shared.$ethDominance.removeDuplicates()
        )
        .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        .receive(on: RunLoop.main)
        .sink { [weak self] (cap, change, btcDom, ethDom) in
            guard let self = self else { return }
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                var newStats = self.stats
                var didChange = false
                
                // Update Market Cap
                if let cap = cap, cap.isFinite && cap > 0 {
                    let formatted = self.mergeCurrencyValue(title: "Market Cap", newNumeric: cap)
                    if let idx = newStats.firstIndex(where: { $0.title == "Market Cap" }) {
                        let old = newStats[idx]
                        if old.value != formatted {
                            newStats[idx] = Stat(id: old.id, title: old.title, value: formatted, iconName: old.iconName)
                            didChange = true
                        }
                    } else {
                        newStats.insert(Stat(title: "Market Cap", value: formatted, iconName: "globe"), at: 0)
                        didChange = true
                    }
                }
                
                // Update 24h Change
                if let change = change, change.isFinite {
                    var norm = self.normalizePercentValue(change)
                    if !norm.isFinite || abs(norm) < 0.01 {
                        if let local = self.capWeightedChange24hFromCoins() { norm = local }
                    }
                    let formatted = String(format: "%.2f%%", max(-35.0, min(35.0, norm)))
                    if let idx = newStats.firstIndex(where: { $0.title == "24h Change" }) {
                        let old = newStats[idx]
                        if old.value != formatted {
                            newStats[idx] = Stat(id: old.id, title: old.title, value: formatted, iconName: old.iconName)
                            didChange = true
                        }
                    } else {
                        newStats.append(Stat(title: "24h Change", value: formatted, iconName: "arrow.up.arrow.down.circle"))
                        didChange = true
                    }
                }
                
                // Update BTC Dominance
                if let btcDom = btcDom, btcDom.isFinite && btcDom > 0 {
                    let formatted = String(format: "%.2f%%", btcDom)
                    if let idx = newStats.firstIndex(where: { $0.title == "BTC Dom" }) {
                        let old = newStats[idx]
                        if old.value != formatted {
                            newStats[idx] = Stat(id: old.id, title: old.title, value: formatted, iconName: old.iconName)
                            didChange = true
                        }
                    } else {
                        newStats.append(Stat(title: "BTC Dom", value: formatted, iconName: "bitcoinsign.circle.fill"))
                        didChange = true
                    }
                }
                
                // Update ETH Dominance
                if let ethDom = ethDom, ethDom.isFinite && ethDom > 0 {
                    let formatted = String(format: "%.2f%%", ethDom)
                    if let idx = newStats.firstIndex(where: { $0.title == "ETH Dom" }) {
                        let old = newStats[idx]
                        if old.value != formatted {
                            newStats[idx] = Stat(id: old.id, title: old.title, value: formatted, iconName: old.iconName)
                            didChange = true
                        }
                    } else {
                        newStats.append(Stat(title: "ETH Dom", value: formatted, iconName: "diamond.fill"))
                        didChange = true
                    }
                }
                
                // Only publish if something actually changed
                if didChange {
                    self.publishStats(newStats)
                }
            }
        }
        .store(in: &cancellables)
    }

    deinit {
        statsTimer?.cancel()
        statsTimer = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    
    /// If the Market Cap stat is currently a placeholder (— or $0.00), try to replace it using best local data
    private func updateMarketCapFromLocalIfPlaceholder() {
        // Check current value
        let current = value(from: "Market Cap")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let isPlaceholder = current.isEmpty || current == "—" || current == "$0.00" || current == "$0"
        guard isPlaceholder else { return }
        
        // Choose the best numeric candidate
        let vmCap = MarketViewModel.shared.globalMarketCap
        let coins = bestCoinsForStats()
        let sumCap = coins.map { bestCap(for: $0) }.reduce(0, +)
        let candidate: Double = {
            if let c = vmCap, c.isFinite, c > 0 { return c }
            if sumCap.isFinite, sumCap > 0 { return sumCap }
            // 3) Derive from BTC or ETH dominance if we have those stats and a reliable cap for the coin
            let btcDom = parsePercent(value(from: "BTC Dom"))
            let ethDom = parsePercent(value(from: "ETH Dom"))
            if btcDom > 0, let btc = coins.first(where: { $0.symbol.lowercased() == "btc" }) {
                let btcCap = bestCap(for: btc)
                if btcCap.isFinite, btcCap > 0 { return btcCap / (btcDom / 100.0) }
            }
            if ethDom > 0, let eth = coins.first(where: { $0.symbol.lowercased() == "eth" }) {
                let ethCap = bestCap(for: eth)
                if ethCap.isFinite, ethCap > 0 { return ethCap / (ethDom / 100.0) }
            }
            // 4) Try legacy cached global payload from disk as a last resort
            if let global: GlobalMarketData = CacheManager.shared.load(GlobalMarketData.self, from: "global_cache.json") {
                let cachedCap = global.totalMarketCap["usd"] ?? 0
                if cachedCap.isFinite, cachedCap > 0 { return cachedCap }
            }
            return 0
        }()
        guard candidate > 0 else { return }
        
        // Merge/format and write back
        let formatted = mergeCurrencyValue(title: "Market Cap", newNumeric: candidate)
        var newStats = stats
        if let idx = newStats.firstIndex(where: { $0.title == "Market Cap" }) {
            let old = newStats[idx]
            let updated = Stat(id: old.id, title: old.title, value: formatted, iconName: old.iconName)
            if old.value != updated.value {
                newStats[idx] = updated
                self.publishStats(newStats)
            }
        } else {
            let s = Stat(title: "Market Cap", value: formatted, iconName: "globe")
            newStats.insert(s, at: 0)
            self.publishStats(newStats)
        }
    }

    /// If the 24h Change stat is placeholder/zero, replace it using a cap-weighted local computation.
    private func updateChange24hFromLocalIfPlaceholder() {
        let current = value(from: "24h Change")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let isPlaceholder = current.isEmpty || current == "—" || current == "0.00%" || current == "0%" || current == "0.00" || current == "0"
        guard isPlaceholder else { return }
        guard let local = capWeightedChange24hFromCoins() else { return }
        let val = max(-35.0, min(35.0, local))
        let formatted = String(format: "%.2f%%", val)
        var newStats = stats
        if let idx = newStats.firstIndex(where: { $0.title == "24h Change" }) {
            let old = newStats[idx]
            let updated = Stat(id: old.id, title: old.title, value: formatted, iconName: old.iconName)
            if old.value != updated.value {
                newStats[idx] = updated
                self.publishStats(newStats)
            }
        } else {
            let s = Stat(title: "24h Change", value: formatted, iconName: "arrow.up.arrow.down.circle")
            newStats.append(s)
            self.publishStats(newStats)
        }
    }

    /// Best available market cap for a coin: prefer provider-reported marketCap, else approximate as price * supply (circulating > total > max).
    private func bestCap(for c: MarketCoin) -> Double {
        // 1) Prefer reported market cap when present and sane
        if let cap = c.marketCap, cap.isFinite, cap > 0 { return cap }
        // 2) Attempt to approximate using price * circulating supply
        if let price = c.priceUsd, price.isFinite, price > 0 {
            if let circ = c.circulatingSupply, circ.isFinite, circ > 0 {
                let cap = price * circ
                if cap.isFinite, cap > 0 { return cap }
            }
            // 3) Fallback to price * total supply
            if let total = c.totalSupply, total.isFinite, total > 0 {
                let cap = price * total
                if cap.isFinite, cap > 0 { return cap }
            }
            // 4) Last resort: price * max supply
            if let maxSup = c.maxSupply, maxSup.isFinite, maxSup > 0 {
                let cap = price * maxSup
                if cap.isFinite, cap > 0 { return cap }
            }
        }
        return 0
    }
    
    /// Best cap for dominance math: prefer reported marketCap; else price * circulatingSupply. Do not use total/max.
    private func bestDominanceCap(for c: MarketCoin) -> Double {
        if let cap = c.marketCap, cap.isFinite, cap > 0 { return cap }
        if let price = c.priceUsd, price.isFinite, price > 0,
           let circ = c.circulatingSupply, circ.isFinite, circ > 0 {
            let cap = price * circ
            return (cap.isFinite && cap > 0) ? cap : 0
        }
        return 0
    }

    /// Choose the richest available coin set for computing stats
    private func bestCoinsForStats() -> [MarketCoin] {
        let vm = MarketViewModel.shared
        if !vm.allCoins.isEmpty { return vm.allCoins }
        if !vm.lastGoodAllCoins.isEmpty { return vm.lastGoodAllCoins }
        if !vm.coins.isEmpty { return vm.coins }

        // Check memoized disk cache once to avoid noisy repeated failures
        if let cached = Self.cachedCoinsFromDisk, !cached.isEmpty {
            return cached
        }
        if !Self.didCheckCoinsCache {
            if let cached: [MarketCoin] = CacheManager.shared.load([MarketCoin].self, from: "coins_cache.json"), !cached.isEmpty {
                Self.cachedCoinsFromDisk = cached
            } else if let raw: [CoinGeckoCoin] = CacheManager.shared.load([CoinGeckoCoin].self, from: "coins_cache.json") {
                Self.cachedCoinsFromDisk = raw.map { MarketCoin(gecko: $0) }
            } else {
                Self.cachedCoinsFromDisk = []
            }
            Self.didCheckCoinsCache = true
        }
        return Self.cachedCoinsFromDisk ?? []
    }

    private func formatPercent(_ v: Double?) -> String {
        guard let v = v, v.isFinite else { return "—" }
        return String(format: "%.1f%%", v as CVarArg)
    }
    
    /// Normalize a percent-like value to percent units.
    /// - Rules: values in 0..1 are treated as fractional and ×100; values ≥1000 are divided by 100; others unchanged.
    private func normalizePercentValue(_ v: Double) -> Double {
        guard v.isFinite else { return v }
        let absV = abs(v)
        if absV <= 1.5 { return v * 100.0 }
        if absV >= 1000.0 { return v / 100.0 }
        return v
    }

    /// Compute a cap/volume-weighted 24h change from local coins as a resilient fallback.
    private func capWeightedChange24hFromCoins(coinsOverride: [MarketCoin]? = nil) -> Double? {
        let coins = coinsOverride ?? bestCoinsForStats()
        guard !coins.isEmpty else { return nil }
        let liveMap = self.liveChange24hSnapshot(for: coins)

        let bestTotalCap = coins.map { bestCap(for: $0) }.reduce(0, +)
        let totalVol = coins.compactMap { $0.totalVolume }.reduce(0, +)
        let epsilon = 0.0005

        func perCoinChange(_ c: MarketCoin) -> Double? {
            if let live = liveMap[c.symbol.lowercased()], live.isFinite, abs(live) > epsilon { return live }
            if let p = c.priceChangePercentage24hInCurrency, p.isFinite, abs(p) > epsilon { return p }
            if let ch = c.changePercent24Hr, ch.isFinite, abs(ch) > epsilon { return ch }
            return derivePercentFromSparkline(c.sparklineIn7d, anchorPrice: c.priceUsd, hours: 24)
        }

        let pairs: [(weight: Double, change: Double)] = coins.compactMap { c in
            guard let ch = perCoinChange(c), ch.isFinite else { return nil }
            let wCap = bestCap(for: c)
            let wVol = c.totalVolume ?? 0
            let w = (bestTotalCap > 0 ? wCap : (totalVol > 0 ? wVol : 1))
            return (weight: w, change: ch)
        }
        guard !pairs.isEmpty else { return nil }

        let avg: Double
        if (bestTotalCap > 0 || totalVol > 0) {
            let sumW = pairs.reduce(0.0) { $0 + $1.weight }
            if sumW <= 0 { return nil }
            let num = pairs.reduce(0.0) { $0 + ($1.weight * $1.change) }
            avg = num / sumW
        } else {
            avg = pairs.reduce(0.0) { $0 + $1.change } / Double(pairs.count)
        }
        let clamped = max(-35.0, min(35.0, avg))
        return clamped.isFinite ? clamped : nil
    }

    /// Prefer keeping an existing non-zero currency value when a new value is implausibly smaller or non-positive.
    private func mergeCurrencyValue(title: String, newNumeric: Double) -> String {
        // Helper: choose placeholder by title
        func placeholder(for title: String) -> String {
            if title.lowercased().contains("market cap") { return "—" }
            return "$0.00"
        }

        // If we have a previous value, and it's non-zero, prefer it when the new is bad or implausibly small
        if let oldStr = value(from: title) {
            let old = parseCurrency(oldStr)
            if old > 0 {
                // If new is non-positive, keep old
                if !(newNumeric.isFinite) || newNumeric <= 0 {
                    return oldStr
                }
                // If new is implausibly smaller (>20x smaller), keep old to avoid flicker/regressions
                if newNumeric < (old / 20.0) {
                    return oldStr
                }
                // Otherwise accept new
                return formatCurrency(newNumeric)
            } else {
                // Old was zero/placeholder; if new is non-positive, return a placeholder
                if !(newNumeric.isFinite) || newNumeric <= 0 {
                    return placeholder(for: title)
                }
                return formatCurrency(newNumeric)
            }
        }

        // No previous value: if new is non-positive, return a placeholder; else format normally
        if !(newNumeric.isFinite) || newNumeric <= 0 {
            return placeholder(for: title)
        }
        return formatCurrency(newNumeric)
    }

    private func updateVolatilityInStats(_ vol: Double?) {
        let value = formatPercent(vol)
        if let existing = stats.first(where: { $0.title == "24h Volatility" })?.value, existing == value {
            return
        }
        // Defer state modifications to avoid "Modifying state during view update"
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let idx = self.stats.firstIndex(where: { $0.title == "24h Volatility" }) {
                let old = self.stats[idx]
                // If incoming value is placeholder, keep the old non-placeholder value
                let trimmedOld = old.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if value == "—" && !trimmedOld.isEmpty && trimmedOld != "—" {
                    // keep old
                } else {
                    self.stats[idx] = Stat(id: old.id, title: old.title, value: value, iconName: old.iconName)
                }
            } else {
                self.stats.append(Stat(title: "24h Volatility", value: value, iconName: "waveform.path.ecg"))
            }
            CacheManager.shared.save(self.stats, to: self.cacheFileName)
        }
    }

    private func formatCurrency(_ v: Double) -> String {
        return MarketFormat.largeCurrency(v)
    }

    // PERFORMANCE FIX: Cached decimal formatter — avoids allocation per call
    private static let _decimalFormatter: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .decimal; return nf
    }()
    private func formatNumber(_ v: Int) -> String {
        Self._decimalFormatter.string(from: v as NSNumber) ?? "\(v)"
    }

    /// Snapshot live 24h percent changes for provided coins (MainActor)
    private func liveChange24hSnapshot(for coins: [MarketCoin]) -> [String: Double] {
        var map: [String: Double] = [:]
        for c in coins {
            if let v = LivePriceManager.shared.bestChange24hPercent(for: c), v.isFinite {
                map[c.symbol.lowercased()] = v
            }
        }
        return map
    }

    /// Derive a percentage change over the given lookback (in hours) from a 7d sparkline, anchoring to current price when available
    nonisolated private func derivePercentFromSparkline(_ prices: [Double], anchorPrice: Double?, hours: Int) -> Double? {
        let data = prices.filter { $0.isFinite && $0 > 0 }
        if data.isEmpty { return nil }
        let n = data.count
        guard n >= 3 else { return nil }
        
        // SMART STEP CALCULATION: Detect actual data coverage based on point count
        // Common sparkline formats:
        // - 168 points (140-200): Hourly data over 7 days
        // - 42 points (35-55): 4-hour intervals over 7 days
        // - 7 points (5-14): Daily data over 7 days
        let (estimatedTotalHours, stepHours): (Double, Double) = {
            if n >= 140 && n <= 200 {
                return (Double(n - 1), 1.0)  // Hourly data
            } else if n >= 35 && n < 140 {
                return (Double(n - 1) * 4.0, 4.0)  // 4-hour interval
            } else if n >= 5 && n < 35 {
                return (Double(n - 1) * 24.0, 24.0)  // Daily data
            } else {
                let totalH = 24.0 * 7.0
                let step = totalH / Double(max(1, n - 1))
                return (totalH, step)  // Fallback
            }
        }()
        
        // Validate minimum coverage for requested timeframe
        let minimumCoverageRequired = Double(hours) * 0.8
        if estimatedTotalHours < minimumCoverageRequired { return nil }
        
        let lookbackSteps = max(1, Int(round(Double(hours) / stepHours)))
        // Avoid using almost the entire series for short lookbacks
        let minWindow = min(n - 1, max(3, lookbackSteps))
        let nominalIndex = max(0, (n - 1) - minWindow)

        func findUsableIndex(around idx: Int, maxSteps: Int = 12) -> Int? {
            var step = 0
            while step <= maxSteps {
                let back = idx - step
                if back >= 0, data[back] > 0, data[back].isFinite { return back }
                step += 1
            }
            step = 1
            while step <= maxSteps {
                let fwd = idx + step
                if fwd < n, data[fwd] > 0, data[fwd].isFinite { return fwd }
                step += 1
            }
            return data.firstIndex(where: { $0 > 0 && $0.isFinite })
        }

        let lastVal: Double = {
            if let p = anchorPrice, p.isFinite, p > 0 { return p }
            for idx in stride(from: n - 1, through: 0, by: -1) {
                if data[idx].isFinite && data[idx] > 0 { return data[idx] }
            }
            return 0
        }()
        guard lastVal > 0 else { return nil }
        guard let prevIdx = findUsableIndex(around: nominalIndex) else { return nil }
        let prev = data[prevIdx]
        guard prev > 0 else { return nil }
        let change = ((lastVal - prev) / prev) * 100.0
        // Remove micro-noise: return nil (not 0) to avoid displaying misleading "0.00%"
        if abs(change) < 0.0005 { return nil }
        return change
    }

    /// Estimate 24h volatility as the standard deviation of 24h % changes across available coins.
    /// Returns nil when insufficient data is available (no global fallback).
    private nonisolated func estimatedVolatility24h(using global: GlobalMarketData?, coinsOverride: [MarketCoin]? = nil, liveChange24h: [String: Double]? = nil) -> Double? {
        // Prefer explicit coins; do not touch MainActor state here
        guard let srcCoins = coinsOverride, !srcCoins.isEmpty else {
            return nil
        }

        // Skip stables
        let stables: Set<String> = ["usdt","usdc","busd","dai"]
        let usable = srcCoins.filter { !stables.contains($0.symbol.lowercased()) }
        _ = 0.0005

        func change24h(for coin: MarketCoin) -> Double? {
            // 0) Prefer live 24h change snapshot if provided
            if let map = liveChange24h, let live = map[coin.symbol.lowercased()], live.isFinite { return live }
            // 1) Provider 24h change when present
            if let p = coin.priceChangePercentage24hInCurrency, p.isFinite { return p }
            if let ch = coin.changePercent24Hr, ch.isFinite { return ch }
            // 2) Derive from 7d sparkline using the best anchor price
            let anchor = coin.priceUsd
            if let d = derivePercentFromSparkline(coin.sparklineIn7d, anchorPrice: anchor, hours: 24), d.isFinite {
                return d
            }
            return nil
        }

        let changes = usable.compactMap { change24h(for: $0) }.filter { $0.isFinite }
        if changes.count >= 2 {
            // Remove extreme outliers (top/bottom 2%) to prevent inflated volatility
            let sorted = changes.sorted()
            let drop = max(1, Int(Double(sorted.count) * 0.02))
            let trimmed = Array(sorted.dropFirst(min(drop, sorted.count/4)).dropLast(min(drop, sorted.count/4)))
            let sample = trimmed.count >= 2 ? trimmed : sorted
            let mean = sample.reduce(0, +) / Double(sample.count)
            // Use sample variance (n-1) for unbiased estimation
            let variance = sample.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(1, sample.count - 1))
            var stddev = sqrt(variance)
            // Clamp to a realistic daily percent band to avoid absurd values from bad inputs
            if !stddev.isFinite { return nil }
            stddev = max(0, min(stddev, 25.0))
            return stddev
        }

        return nil
    }

    /// Build a best-effort set of stats from locally available market coins
    private func derivedStatsFromLocalCoins() -> [Stat]? {
        let coins = bestCoinsForStats()
        guard !coins.isEmpty else { return nil }
        let liveMap = self.liveChange24hSnapshot(for: coins)

        let bestTotalCap = coins.map { bestCap(for: $0) }.reduce(0, +)

        // Sums from available data
        let totalCap = coins.compactMap { $0.marketCap }.reduce(0, +)
        let totalVol = coins.compactMap { $0.totalVolume }.reduce(0, +)

        // Proxy: price * maxSupply when per-coin caps are missing
        let proxyCap: Double = coins.reduce(0) { partial, c in
            let price = c.priceUsd ?? 0
            let maxSup = c.maxSupply ?? 0
            if price.isFinite, price > 0, maxSup.isFinite, maxSup > 0 {
                let cap = price * maxSup
                return cap.isFinite && cap > 0 ? (partial + cap) : partial
            }
            return partial
        }

        // Prefer per-coin market caps; if unavailable, fall back to cached global cap
        let capCandidate: Double = {
            // 1) Prefer MarketViewModel's computed global cap if available
            if let vmCap = MarketViewModel.shared.globalMarketCap, vmCap.isFinite, vmCap > 0 { return vmCap }
            // 2) Prefer sum of best-available caps (marketCap or price*maxSupply)
            if bestTotalCap.isFinite, bestTotalCap > 0 { return bestTotalCap }
            // 3) Prefer sum of reported per-coin market caps when present
            if totalCap.isFinite, totalCap > 0 { return totalCap }
            // 4) Prefer proxy cap calculation
            if proxyCap.isFinite, proxyCap > 0 { return proxyCap }
            // 5) Fall back to cached global payload if present
            if ({
                if !Self.didCheckLegacyGlobalCache {
                    if let _: GlobalMarketData = CacheManager.shared.load(GlobalMarketData.self, from: "global_cache.json") {
                        Self.legacyGlobalCacheExists = true
                    }
                    Self.didCheckLegacyGlobalCache = true
                }
                return Self.legacyGlobalCacheExists
            })(), let global: GlobalMarketData = CacheManager.shared.load(GlobalMarketData.self, from: "global_cache.json") {
                let cachedCap = global.totalMarketCap["usd"] ?? 0
                if cachedCap.isFinite, cachedCap > 0 { return cachedCap }
            }
            // 6) Derive from current dominance and a known top coin cap (BTC/ETH) if available
            if let btc = coins.first(where: { $0.symbol.lowercased() == "btc" }) {
                let btcCap = bestCap(for: btc)
                let dom = parsePercent(value(from: "BTC Dom"))
                if btcCap > 0, dom > 0 { return btcCap / (dom / 100) }
            }
            if let eth = coins.first(where: { $0.symbol.lowercased() == "eth" }) {
                let ethCap = bestCap(for: eth)
                let dom = parsePercent(value(from: "ETH Dom"))
                if ethCap > 0, dom > 0 { return ethCap / (dom / 100) }
            }
            return 0
        }()

        // Fallback helpers to preserve previous non-zero values when new data is incomplete
        func previousNonZeroValue(for title: String) -> String? {
            guard let prev = value(from: title) else { return nil }
            let trimmed = prev.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed == "$0.00" || trimmed == "$0" || trimmed == "0.00%" || trimmed == "0%" || trimmed == "0.00" || trimmed == "0" || trimmed == "—" {
                return nil
            }
            return prev
        }

        // Dominance: prefer market cap share only (removed volume share fallback)
        func dominance(for symbol: String) -> Double {
            let lower = symbol.lowercased()
            let denom = coins.map { bestDominanceCap(for: $0) }.reduce(0, +)
            guard denom > 0 else { return 0 }
            let cap = coins.first(where: { $0.symbol.lowercased() == lower }).map { bestDominanceCap(for: $0) } ?? 0
            return (cap / denom) * 100
        }

        // 24h change: cap-weighted if caps available; else volume-weighted if volumes available; else simple average
        let change24h: Double = {
            let epsilon = 0.0005
            func perCoinChange(_ c: MarketCoin) -> Double? {
                // 0) Prefer live 24h change from snapshot
                if let live = liveMap[c.symbol.lowercased()], live.isFinite, abs(live) > epsilon { return live }
                // 1) Provider values
                if let p = c.priceChangePercentage24hInCurrency, p.isFinite, abs(p) > epsilon { return p }
                if let ch = c.changePercent24Hr, ch.isFinite, abs(ch) > epsilon { return ch }
                // 2) Derived from sparkline using best anchor price
                return derivePercentFromSparkline(c.sparklineIn7d, anchorPrice: c.priceUsd, hours: 24)
            }
            let pairs: [(weight: Double, change: Double)] = coins.compactMap { c in
                guard let ch = perCoinChange(c), ch.isFinite else { return nil }
                let weightCap = bestCap(for: c)
                let weightVol = c.totalVolume ?? 0
                return (weight: (bestTotalCap > 0 ? weightCap : (totalVol > 0 ? weightVol : 1)), change: ch)
            }
            guard !pairs.isEmpty else { return 0 }
            if totalCap > 0 || totalVol > 0 {
                let sumW = pairs.reduce(0.0) { $0 + $1.weight }
                if sumW > 0 {
                    let num = pairs.reduce(0.0) { $0 + ($1.weight * $1.change) }
                    return num / sumW
                }
            }
            let mean = pairs.reduce(0.0) { $0 + $1.change } / Double(pairs.count)
            return mean
        }()
        let normalizedChange24h = max(-35.0, min(35.0, change24h))


        let btcDom = dominance(for: "btc")
        let ethDom = dominance(for: "eth")

        // Build values, preserving previous non-zero strings when we cannot compute fresh ones
        let marketCapStr: String = {
            if capCandidate > 0 { return mergeCurrencyValue(title: "Market Cap", newNumeric: capCandidate) }
            if let prev = previousNonZeroValue(for: "Market Cap") { return prev }
            return "—"
        }()
        let volumeStr: String = {
            if totalVol > 0 { return mergeCurrencyValue(title: "24h Volume", newNumeric: totalVol) }
            if let prev = previousNonZeroValue(for: "24h Volume") { return prev }
            return "$0.00"
        }()
        let btcDomStr: String = {
            if btcDom > 0 { return String(format: "%.2f%%", btcDom) }
            if let prev = previousNonZeroValue(for: "BTC Dom") { return prev }
            return "0.00%"
        }()
        let ethDomStr: String = {
            if ethDom > 0 { return String(format: "%.2f%%", ethDom) }
            if let prev = previousNonZeroValue(for: "ETH Dom") { return prev }
            return "0.00%"
        }()

        let vol24h = estimatedVolatility24h(using: nil, coinsOverride: coins, liveChange24h: liveMap)
        let volatilityStr = vol24h != nil ? String(format: "%.1f%%", vol24h!) : (previousNonZeroValue(for: "24h Volatility") ?? "—")

        // Preserve previous non-zero 24h Change if our computed value is effectively zero
        let changeStr: String = {
            if normalizedChange24h != 0 { return String(format: "%.2f%%", normalizedChange24h) }
            if let prev = previousNonZeroValue(for: "24h Change") { return prev }
            return "0.00%"
        }()

        let approx: [Stat] = [
            Stat(title: "Market Cap",      value: marketCapStr,                         iconName: "globe"),
            Stat(title: "24h Volume",     value: volumeStr,                             iconName: "clock"),
            Stat(title: "BTC Dom",        value: btcDomStr,                             iconName: "bitcoinsign.circle.fill"),
            Stat(title: "ETH Dom",        value: ethDomStr,                             iconName: "diamond.fill"),
            Stat(title: "24h Volatility", value: volatilityStr,                         iconName: "waveform.path.ecg"),
            Stat(title: "24h Change",     value: changeStr,                             iconName: "arrow.up.arrow.down.circle")
        ]
        return approx
    }

    /// Parses a currency string with symbols and suffixes to a Double
    private func parseCurrency(_ s: String) -> Double {
        var str = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if str.hasPrefix("$") {
            str.removeFirst()
        }
        let suffixMultipliers: [String: Double] = [
            "k": 1_000,
            "m": 1_000_000,
            "b": 1_000_000_000,
            "t": 1_000_000_000_000
        ]
        var multiplier: Double = 1
        for (suffix, mult) in suffixMultipliers {
            if str.hasSuffix(suffix) {
                multiplier = mult
                str = String(str.dropLast())
                break
            }
        }
        str = str.replacingOccurrences(of: ",", with: "")
        let number = Double(str) ?? 0
        return number * multiplier
    }

    /// Parses a percentage string like "20.34%" (case/space tolerant) into a Double.
    private func parsePercent(_ s: String?) -> Double {
        guard var str = s?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !str.isEmpty else { return 0 }
        if str.hasSuffix("%") { str.removeLast() }
        str = str.replacingOccurrences(of: ",", with: "")
        return Double(str) ?? 0
    }

    /// Returns the value string of a stat by title
    private func value(from statTitle: String) -> String? {
        return stats.first(where: { $0.title == statTitle })?.value
    }

    /// Replace stats array only when values actually change; preserve stable IDs by title.
    /// Uses debouncing and value hysteresis to prevent rapid flickering.
    private func publishStats(_ incoming: [Stat]) {
        let currentByTitle = Dictionary(uniqueKeysWithValues: self.stats.map { ($0.title, $0) })
        
        // Apply 24h change hysteresis - only update if delta exceeds threshold
        let hysteresisApplied: [Stat] = incoming.map { s in
            if s.title == "24h Change" {
                let newValue = parsePercent(s.value)
                if let lastValue = lastDisplayed24hChange {
                    let delta = abs(newValue - lastValue)
                    // If change is below threshold, keep the old value
                    if delta < change24hHysteresisThreshold, let old = currentByTitle["24h Change"] {
                        return old
                    }
                }
                // Update the tracked value
                lastDisplayed24hChange = newValue
            }
            return s
        }
        
        let merged: [Stat] = hysteresisApplied.map { s in
            if let old = currentByTitle[s.title] {
                if old.value == s.value && old.iconName == s.iconName {
                    return old
                } else {
                    return Stat(id: old.id, title: s.title, value: s.value, iconName: s.iconName)
                }
            } else {
                return s
            }
        }
        let unchanged = merged.count == self.stats.count &&
            zip(merged, self.stats).allSatisfy { $0.id == $1.id && $0.title == $1.title && $0.value == $1.value && $0.iconName == $1.iconName }
        if unchanged { return }
        
        // Debounce rapid publishes to prevent UI flickering
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastPublishAt)
        
        // Cancel any pending publish
        pendingPublishWork?.cancel()
        pendingStats = merged
        
        if timeSinceLast >= minPublishInterval {
            // Enough time has passed, publish immediately
            executePublish(merged)
        } else {
            // Schedule a delayed publish
            let delay = minPublishInterval - timeSinceLast
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if let pending = self.pendingStats {
                    self.executePublish(pending)
                    self.pendingStats = nil
                }
            }
            pendingPublishWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }
    
    /// Executes the actual publish of stats (called after debouncing)
    private func executePublish(_ merged: [Stat]) {
        lastPublishAt = Date()
        // Defer state modification to avoid "Modifying state during view update"
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.stats = merged
            CacheManager.shared.save(merged, to: self.cacheFileName)
        }
    }

    /// Fetches global market stats from CoinGecko’s global endpoint.
    public func fetchStats() async {
        // Throttle frequent calls (foreground/time-change/timer bursts)
        if let last = lastFetchAt, Date().timeIntervalSince(last) < minFetchInterval {
            return
        }
        // Avoid overlapping fetches
        if isFetching { return }
        
        // Respect temporary cooldown after degraded payloads or network errors
        if let until = cooldownUntil, Date() < until {
            DebugLog.log("Stats", "fetchStats() skipping due to cooldown until \(until)")
            return
        }
        
        DebugLog.log("Stats", "fetchStats() proceeding (passed throttle & not overlapping)")
        lastFetchAt = Date()
        isFetching = true
        defer { isFetching = false }
        do {
            // Exponential backoff with jitter for transient failures / rate limits
            var attempt = 0
            var lastError: Error?
            var d: GlobalMarketData!
            while attempt < 3 {
                do {
                    d = try await CryptoAPIService.shared.fetchGlobalData()
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    attempt += 1
                    // backoff: 1s, 2s, 4s with up to 20% jitter
                    let base = min(60.0, pow(2.0, Double(attempt - 1)))
                    let jitter = Double.random(in: 0...(base * 0.2))
                    let delay = base + jitter
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
            if let lastError = lastError {
                throw lastError
            }

            // Compute a simple 24h volatility proxy from available market coins (std dev of 24h % changes)
            let coinsForVol = self.bestCoinsForStats()
            let liveMap = self.liveChange24hSnapshot(for: coinsForVol)
            let volatility = self.estimatedVolatility24h(using: d, coinsOverride: coinsForVol, liveChange24h: liveMap)
            DebugLog.log("Stats", "fetchStats computed volatility: \(volatility.map { String($0) } ?? "nil")")
            self.updateVolatilityInStats(volatility)

            // Detect bad/zero payloads and merge with locally derived stats
            let derived = self.derivedStatsFromLocalCoins()

            var marketCapUSD = d.totalMarketCap["usd"] ?? 0
            var volumeUSD = d.totalVolume["usd"] ?? 0
            var btcDom = d.marketCapPercentage["btc"] ?? 0
            var ethDom = d.marketCapPercentage["eth"] ?? 0
            
            // Cross-validate market cap using BTC dominance
            // If we have a reliable BTC cap and dominance, derive total market cap for sanity check
            let coins = bestCoinsForStats()
            if let btcCoin = coins.first(where: { $0.symbol.lowercased() == "btc" }) {
                let btcCap = bestCap(for: btcCoin)
                if btcCap > 0 && btcDom > 10 && btcDom < 90 {
                    let derivedTotalCap = btcCap / (btcDom / 100.0)
                    // If API market cap is implausibly low (less than 60% of derived), use derived
                    if derivedTotalCap > 0 && (marketCapUSD < derivedTotalCap * 0.6 || marketCapUSD <= 0) {
                        DebugLog.log("Stats", "API market cap ($\(Int(marketCapUSD/1e9))B) seems low; using BTC-derived ($\(Int(derivedTotalCap/1e9))B)")
                        marketCapUSD = derivedTotalCap
                    }
                }
            }
            
            var normalizedChange24h: Double = {
                let raw = d.marketCapChangePercentage24HUsd
                guard raw.isFinite else { return 0 }
                let absV = abs(raw)
                let percent = (absV <= 1.0) ? (raw * 100.0) : raw
                let scaled = (abs(percent) > 1000.0) ? (percent / 100.0) : percent
                return max(-35.0, min(35.0, scaled))
            }()
            if !normalizedChange24h.isFinite || abs(normalizedChange24h) < 0.01 {
                if let local = self.capWeightedChange24hFromCoins() {
                    normalizedChange24h = max(-35.0, min(35.0, local))
                }
            }

            let degradedPayload = ( (d.totalMarketCap["usd"] ?? 0) == 0 || (d.totalVolume["usd"] ?? 0) == 0 || (d.marketCapPercentage["btc"] ?? 0) == 0 || (d.marketCapPercentage["eth"] ?? 0) == 0 )
            if degradedPayload {
                DebugLog.log("Stats", "Global payload degraded; will merge with local repairs before publishing.")
            } else {
                DebugLog.log("Stats", "Global payload healthy; normalized 24h change=\(String(format: "%.2f%%", normalizedChange24h))")
            }

            // Track degraded streak and apply cooldown if it persists
            let isDegraded = ((d.totalMarketCap["usd"] ?? 0) == 0 || (d.totalVolume["usd"] ?? 0) == 0 || (d.marketCapPercentage["btc"] ?? 0) == 0 || (d.marketCapPercentage["eth"] ?? 0) == 0)
            if isDegraded {
                degradedStreak += 1
            } else {
                degradedStreak = 0
            }
            if degradedStreak >= 2 {
                cooldownUntil = Date().addingTimeInterval(180) // 3 minutes
                degradedStreak = 0
                DebugLog.log("Stats", "Degraded payload streak; entering cooldown for 180s")
            }

            // if (marketCapUSD == 0 || volumeUSD == 0 || btcDom == 0 || ethDom == 0), let _ = derived {  <-- REPLACED LINE
            if (marketCapUSD == 0 || volumeUSD == 0 || btcDom == 0 || ethDom == 0) {
                let coins = bestCoinsForStats()
                let totalCapLocalDom = coins.map { bestDominanceCap(for: $0) }.reduce(0, +)
                var totalCapLocal = coins.map { bestCap(for: $0) }.reduce(0, +)
                if !(totalCapLocal.isFinite) || totalCapLocal <= 0 {
                    if let vmCap = MarketViewModel.shared.globalMarketCap, vmCap.isFinite, vmCap > 0 {
                        totalCapLocal = vmCap
                    }
                }
                let totalVolLocal = coins.compactMap { $0.totalVolume }.reduce(0, +)
                func dominance(_ sym: String) -> Double {
                    guard totalCapLocalDom > 0 else { return 0 }
                    let cap = coins.first(where: { $0.symbol.lowercased() == sym }) .map { bestDominanceCap(for: $0) } ?? 0
                    return (cap / totalCapLocalDom) * 100
                }
                if marketCapUSD == 0, totalCapLocal > 0 {
                    marketCapUSD = totalCapLocal
                }
                if volumeUSD == 0, totalVolLocal > 0 {
                    volumeUSD = totalVolLocal
                }
                if btcDom == 0 {
                    btcDom = dominance("btc")
                }
                if ethDom == 0 {
                    ethDom = dominance("eth")
                }
            }

            // Final fallback: fetch a fresh markets page to compute stats if zeros persist
            if marketCapUSD == 0 || volumeUSD == 0 || btcDom == 0 || ethDom == 0 {
                // Respect a cooldown for the heavier markets fallback to avoid rate limiting
                if let last = lastFallbackMarketsAttemptAt, Date().timeIntervalSince(last) < fallbackMarketsCooldown {
                    // Skip fallback; we'll rely on local/derived values
                } else {
                    lastFallbackMarketsAttemptAt = Date()
                    do {
                        let coinsForStats = try await CryptoAPIService.shared.fetchCoinMarkets()
                        if !coinsForStats.isEmpty {
                            let totalCap = coinsForStats.map { bestCap(for: $0) }.reduce(0, +)
                            let totalCapDom = coinsForStats.map { bestDominanceCap(for: $0) }.reduce(0, +)
                            let totalVol = coinsForStats.compactMap { $0.totalVolume }.reduce(0, +)
                            func dom(_ sym: String) -> Double {
                                guard totalCapDom > 0 else { return 0 }
                                let cap = coinsForStats.first(where: { $0.symbol.lowercased() == sym }) .map { bestDominanceCap(for: $0) } ?? 0
                                return (cap / totalCapDom) * 100
                            }
                            if marketCapUSD == 0, totalCap > 0 { marketCapUSD = totalCap }
                            if volumeUSD == 0, totalVol > 0 { volumeUSD = totalVol }
                            if btcDom == 0 { btcDom = dom("btc") }
                            if ethDom == 0 { ethDom = dom("eth") }
                        }
                    } catch {
                        // ignore; we'll use whatever we have
                    }
                }
            }

            // If zeros still persist, prefer fully derived local stats to avoid publishing $0.00
            if (marketCapUSD == 0 || volumeUSD == 0 || btcDom == 0 || ethDom == 0), let derivedNonZero = derived {
                _ = await MainActor.run { [derivedNonZero] in
                    Task { @MainActor [weak self] in
                        self?.publishStats(derivedNonZero)
                    }
                }
                self.lastFetchAt = Date()
                return
            }

            let fetched: [Stat] = [
                Stat(title: "Market Cap",      value: mergeCurrencyValue(title: "Market Cap", newNumeric: marketCapUSD),                     iconName: "globe"),
                Stat(title: "24h Volume",     value: mergeCurrencyValue(title: "24h Volume", newNumeric: volumeUSD),                         iconName: "clock"),
                Stat(title: "BTC Dom",        value: String(format: "%.2f%%", btcDom),                iconName: "bitcoinsign.circle.fill"),
                Stat(title: "ETH Dom",        value: String(format: "%.2f%%", ethDom),                iconName: "diamond.fill"),
                Stat(title: "24h Volatility", value: volatility != nil ? String(format: "%.1f%%", volatility!) : "—", iconName: "waveform.path.ecg"),
                Stat(title: "24h Change",     value: String(format: "%.2f%%", normalizedChange24h),   iconName: "arrow.up.arrow.down.circle")
            ]
            _ = await MainActor.run { [fetched] in
                Task { @MainActor [weak self] in
                    self?.publishStats(fetched)
                }
            }
            self.lastGlobalSuccessAt = Date()
            self.lastFetchAt = Date()
        } catch {
            // Apply a short cooldown for common transient network errors
            if let urlErr = error as? URLError {
                let code = urlErr.code
                let cooldown: TimeInterval
                switch code {
                case .timedOut, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet:
                    cooldown = 90
                default:
                    cooldown = 0
                }
                if cooldown > 0 {
                    cooldownUntil = Date().addingTimeInterval(cooldown)
                    DebugLog.log("Stats", "fetchStats() network error \(code.rawValue); cooldown \(Int(cooldown))s")
                }
            }
            
            // Fallback: derive approximate stats from currently loaded market coins
            let localCoins = MarketViewModel.shared.allCoins
            if let approx = self.derivedStatsFromLocalCoins() {
                // Defer state modification to avoid "Modifying state during view update"
                Task { @MainActor [weak self] in
                    self?.stats = approx
                }
            }
            let fallbackSrc = localCoins.isEmpty ? MarketViewModel.shared.watchlistCoins : localCoins
            let fallbackLive = self.liveChange24hSnapshot(for: fallbackSrc)
            let fallbackVol = self.estimatedVolatility24h(using: nil, coinsOverride: fallbackSrc, liveChange24h: fallbackLive)
            self.updateVolatilityInStats(fallbackVol)
            if case URLError.notConnectedToInternet = (error as? URLError)?.code {
                DebugLog.log("Stats", "fetchStats offline; used local approximation. Volatility=\(fallbackVol.map { String(format: "%.2f", $0) } ?? "nil")")
            } else {
                DebugLog.log("Stats", "fetchStats failed; used local approximation. Error=\(error.localizedDescription) Volatility=\(fallbackVol.map { String(format: "%.2f", $0) } ?? "nil")")
            }

            if (self.stats.isEmpty || self.stats.prefix(4).allSatisfy { $0.value == "$0.00" || $0.value == "0.00%" || $0.value == "0.00" }) {
                if let cached: [Stat] = CacheManager.shared.load([Stat].self, from: cacheFileName), !cached.isEmpty {
                    // Defer state modification to avoid "Modifying state during view update"
                    Task { @MainActor [weak self] in
                        self?.stats = cached
                    }
                }
            }
            self.lastFetchAt = Date()
            return
        }
    }

    /// Check if first four stats show zeros and refresh from local if so.
    public func refreshFromLocalIfZeros() {
        // If stats haven't been built yet but we have coins, build them now from local data
        if self.stats.count < 6, let approx = self.derivedStatsFromLocalCoins() {
            // Defer state modification to avoid "Modifying state during view update"
            let capturedApprox = approx
            let capturedCacheFileName = cacheFileName
            Task { @MainActor [weak self] in
                self?.stats = capturedApprox
                CacheManager.shared.save(capturedApprox, to: capturedCacheFileName)
            }
            return
        }

        // Titles to check
        let titlesToCheck = ["Market Cap", "24h Volume", "BTC Dom", "ETH Dom"]
        var needRefresh = false
        for title in titlesToCheck {
            if let statValue = value(from: title) {
                let trimmed = statValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if trimmed == "$0.00" || trimmed == "$0" || trimmed == "0.00%" || trimmed == "0%" || trimmed == "0.00" || trimmed == "0" || trimmed == "—" {
                    needRefresh = true
                    break
                }
            }
        }
        guard needRefresh else { return }

        var newStats = stats

        func replaceStatValue(title: String, newValue: String) {
            if let index = newStats.firstIndex(where: { $0.title == title }) {
                var stat = newStats[index]
                stat = Stat(id: stat.id, title: stat.title, value: newValue, iconName: stat.iconName)
                newStats[index] = stat
            }
        }

        let coins = bestCoinsForStats()
        let totalCapLocalDom = coins.map { bestDominanceCap(for: $0) }.reduce(0, +)
        var totalCapLocal = coins.map { bestCap(for: $0) }.reduce(0, +)
        if !(totalCapLocal.isFinite) || totalCapLocal <= 0 {
            if let vmCap = MarketViewModel.shared.globalMarketCap, vmCap.isFinite, vmCap > 0 {
                totalCapLocal = vmCap
            }
        }
        if !(totalCapLocal.isFinite) || totalCapLocal <= 0 {
            // Try to estimate from dominance and a known BTC/ETH cap
            if let btc = coins.first(where: { $0.symbol.lowercased() == "btc" }) {
                let btcCap = bestCap(for: btc)
                let dom = parsePercent(value(from: "BTC Dom"))
                if btcCap > 0, dom > 0 {
                    totalCapLocal = btcCap / (dom / 100)
                }
            }
            if (totalCapLocal <= 0 || !totalCapLocal.isFinite), let eth = coins.first(where: { $0.symbol.lowercased() == "eth" }) {
                let ethCap = bestCap(for: eth)
                let dom = parsePercent(value(from: "ETH Dom"))
                if ethCap > 0, dom > 0 {
                    totalCapLocal = ethCap / (dom / 100)
                }
            }
        }
        let totalVolLocal = coins.compactMap { $0.totalVolume }.reduce(0, +)
        func dominance(_ sym: String) -> Double {
            guard totalCapLocalDom > 0 else { return 0 }
            let cap = coins.first(where: { $0.symbol.lowercased() == sym }) .map { bestDominanceCap(for: $0) } ?? 0
            return (cap / totalCapLocalDom) * 100
        }

        for title in titlesToCheck {
            if let statValue = value(from: title) {
                let trimmed = statValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if trimmed == "$0.00" || trimmed == "$0" || trimmed == "0.00%" || trimmed == "0%" || trimmed == "0.00" || trimmed == "0" || trimmed == "—" {
                    switch title {
                    case "Market Cap":
                        if totalCapLocal > 0 {
                            replaceStatValue(title: title, newValue: mergeCurrencyValue(title: title, newNumeric: totalCapLocal))
                        }
                    case "24h Volume":
                        if totalVolLocal > 0 {
                            replaceStatValue(title: title, newValue: mergeCurrencyValue(title: title, newNumeric: totalVolLocal))
                        }
                    case "BTC Dom":
                        let btcDominance = dominance("btc")
                        if btcDominance > 0 {
                            replaceStatValue(title: title, newValue: String(format: "%.2f%%", btcDominance))
                        }
                    case "ETH Dom":
                        let ethDominance = dominance("eth")
                        if ethDominance > 0 {
                            replaceStatValue(title: title, newValue: String(format: "%.2f%%", ethDominance))
                        }
                    default:
                        break
                    }
                }
            }
        }

        DispatchQueue.main.async {
            self.publishStats(newStats)
        }
    }

    /// If the last successful global stats fetch is stale, update core stats (cap/volume/dominance) from local coins.
    private func updateDerivedCoreStatsIfStale() {
        // Only update if the last successful global fetch is older than our refresh window
        let now = Date()
        if let last = lastGlobalSuccessAt, now.timeIntervalSince(last) < derivedRefreshInterval {
            return
        }
        guard let derived = derivedStatsFromLocalCoins() else { return }

        let coins = bestCoinsForStats()
        _ = coins.map { bestDominanceCap(for: $0) }.reduce(0, +)
        var totalCapLocal = coins.map { bestCap(for: $0) }.reduce(0, +)
        if !(totalCapLocal.isFinite) || totalCapLocal <= 0 {
            if let vmCap = MarketViewModel.shared.globalMarketCap, vmCap.isFinite, vmCap > 0 {
                totalCapLocal = vmCap
            }
        }
        if !(totalCapLocal.isFinite) || totalCapLocal <= 0 {
            // Try to estimate from dominance and a known BTC/ETH cap
            if let btc = coins.first(where: { $0.symbol.lowercased() == "btc" }) {
                let btcCap = bestCap(for: btc)
                let dom = parsePercent(value(from: "BTC Dom"))
                if btcCap > 0, dom > 0 {
                    totalCapLocal = btcCap / (dom / 100)
                }
            }
            if (totalCapLocal <= 0 || !totalCapLocal.isFinite), let eth = coins.first(where: { $0.symbol.lowercased() == "eth" }) {
                let ethCap = bestCap(for: eth)
                let dom = parsePercent(value(from: "ETH Dom"))
                if ethCap > 0, dom > 0 {
                    totalCapLocal = ethCap / (dom / 100)
                }
            }
        }
        let totalVolLocal = coins.compactMap { $0.totalVolume }.reduce(0, +)

        // Merge: replace only Market Cap, 24h Volume, BTC Dom, ETH Dom; keep existing Volatility and 24h Change if present
        var newStats = self.stats
        func replaceValue(title: String, with newValue: String) {
            if let idx = newStats.firstIndex(where: { $0.title == title }) {
                let old = newStats[idx]
                newStats[idx] = Stat(id: old.id, title: old.title, value: newValue, iconName: old.iconName)
            } else {
                if let src = derived.first(where: { $0.title == title }) {
                    newStats.append(src)
                }
            }
        }
        replaceValue(title: "Market Cap", with: mergeCurrencyValue(title: "Market Cap", newNumeric: totalCapLocal))
        replaceValue(title: "24h Volume", with: mergeCurrencyValue(title: "24h Volume", newNumeric: totalVolLocal))
        if let btc = derived.first(where: { $0.title == "BTC Dom" })?.value {
            replaceValue(title: "BTC Dom", with: btc)
        }
        if let eth = derived.first(where: { $0.title == "ETH Dom" })?.value {
            replaceValue(title: "ETH Dom", with: eth)
        }
        // Preserve or append Volatility and 24h Change as they were (do not overwrite here)
        DispatchQueue.main.async {
            self.publishStats(newStats)
        }
    }
}

