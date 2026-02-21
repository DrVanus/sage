//
//  MarketStatsView.swift
//  CryptoSage
//
//  Created by DM on 5/19/25.
//

import SwiftUI

// Local gold palette for Market Stats (uses centralized BrandColors)
private enum GoldTheme {
    static let light = BrandColors.goldLight
    static let base  = BrandColors.goldBase
    static let dark  = BrandColors.goldDark
    
    // Dark mode gradients (with dark edge for depth)
    static var gradientTLBR: LinearGradient { BrandColors.goldDiagonalGradient }
    static var gradientLR: LinearGradient { BrandColors.goldHorizontal }
    
    // Light mode gradients (flat, no dark edge)
    static var gradientTLBRLight: LinearGradient { BrandColors.goldDiagonalGradientLight }
    static var gradientLRLight: LinearGradient { BrandColors.goldHorizontalLight }
}

// MARK: - Premium Glassmorphism Background for Stats
private struct PremiumStatsBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        ZStack {
            // PERFORMANCE FIX v19: Replaced .ultraThinMaterial with solid gradient
            // Material effects perform real-time Gaussian blur every frame during scroll
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DS.Adaptive.chipBackground)
            
            // Dark mode overlay for better contrast
            if isDark {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.25))
            }
            
            // Depth gradient (top highlight to bottom shadow)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isDark ? 0.1 : 0.5), location: 0.0),
                            .init(color: Color.clear, location: 0.25),
                            .init(color: Color.clear, location: 0.75),
                            .init(color: Color.black.opacity(isDark ? 0.08 : 0.02), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Subtle gold tint at top edge for premium feel
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            GoldTheme.base.opacity(isDark ? 0.08 : 0.05),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
        .overlay(
            // Premium border with gold accent at top
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: GoldTheme.base.opacity(isDark ? 0.5 : 0.3), location: 0.0),
                            .init(color: GoldTheme.base.opacity(isDark ? 0.15 : 0.1), location: 0.2),
                            .init(color: DS.Adaptive.stroke.opacity(0.4), location: 0.5),
                            .init(color: DS.Adaptive.stroke.opacity(0.2), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: isDark ? 1.0 : 0.7
                )
        )
    }
}

// MARK: - Premium Gradient Divider
private struct PremiumDivider: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        // LIGHT MODE FIX: Increased center opacity from 0.25 to 0.40 so the divider
        // between stat rows is actually visible on the warm cream card background.
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        DS.Adaptive.divider.opacity(colorScheme == .dark ? 0.1 : 0.15),
                        DS.Adaptive.divider.opacity(colorScheme == .dark ? 0.4 : 0.40),
                        DS.Adaptive.divider.opacity(colorScheme == .dark ? 0.1 : 0.15)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: colorScheme == .dark ? 0.6 : 0.8)
            .padding(.horizontal, 8)
    }
}

// MARK: - MarketStatsView

struct MarketStatsView: View {
    @StateObject var statsVM = MarketStatsViewModel()
    // PERFORMANCE FIX v19: Removed @ObservedObject for MarketViewModel.
    // Using onReceive on specific publishers instead of observing all 25+ @Published properties.
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    private var isCompactLayout: Bool {
        (horizontalSizeClass == .compact) || sizeCategory.isAccessibilityCategory
    }
    @State private var refreshTick: Int = 0
    
    // Debouncing state to prevent rapid refresh flicker
    @State private var lastRefreshAt: Date = .distantPast
    @State private var pendingRefreshWork: DispatchWorkItem? = nil
    private let minRefreshInterval: TimeInterval = 2.0 // Minimum 2 seconds between refreshes

    // PERFORMANCE FIX v25: Cached currency formatter to avoid allocating a new NumberFormatter
    // on every view body evaluation. NumberFormatter init is expensive (~0.1ms per call) and
    // this function is called multiple times per frame during scroll.
    private static let cachedCurrencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = CurrencyManager.currencyCode
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()
    
    // Compact currency formatter used for local fallback
    private func abbrevCurrency(_ v: Double) -> String {
        let absV = abs(v)
        let sym = CurrencyManager.symbol
        if absV >= 1_000_000_000_000 { return String(format: "%@%.2fT", sym, v/1_000_000_000_000) }
        if absV >= 1_000_000_000 { return String(format: "%@%.2fB", sym, v/1_000_000_000) }
        if absV >= 1_000_000 { return String(format: "%@%.2fM", sym, v/1_000_000) }
        return Self.cachedCurrencyFormatter.string(from: v as NSNumber) ?? String(format: "$%.2f", v)
    }

    // Best available coins for fallback calculations
    private func bestCoins() -> [MarketCoin] {
        let vm = MarketViewModel.shared
        // 1) Prefer live in-memory sets from the shared MarketViewModel
        if !vm.allCoins.isEmpty { return vm.allCoins }
        if !vm.lastGoodAllCoins.isEmpty { return vm.lastGoodAllCoins }
        if !vm.coins.isEmpty { return vm.coins }
        if !vm.watchlistCoins.isEmpty { return vm.watchlistCoins }

        // 2) Fall back to on-disk cache so we can compute Market Cap before MarketViewModel finishes loading
        if let cached: [MarketCoin] = CacheManager.shared.load([MarketCoin].self, from: "coins_cache.json"), !cached.isEmpty {
            return cached
        }
        // 3) Legacy cache may contain CoinGeckoCoin array — map it into MarketCoin
        if let raw: [CoinGeckoCoin] = CacheManager.shared.load([CoinGeckoCoin].self, from: "coins_cache.json"), !raw.isEmpty {
            return raw.map { MarketCoin(gecko: $0) }
        }
        return []
    }

    private func bestCap(for c: MarketCoin) -> Double {
        if let cap = c.marketCap, cap.isFinite, cap > 0 { return cap }
        if let p = c.priceUsd, p.isFinite, p > 0 {
            if let circ = c.circulatingSupply, circ.isFinite, circ > 0 { let v = p * circ; if v.isFinite, v > 0 { return v } }
            if let total = c.totalSupply, total.isFinite, total > 0 { let v = p * total; if v.isFinite, v > 0 { return v } }
            if let maxSup = c.maxSupply, maxSup.isFinite, maxSup > 0 { let v = p * maxSup; if v.isFinite, v > 0 { return v } }
        }
        return 0
    }

    private func parsePercent(_ s: String?) -> Double {
        guard var str = s?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !str.isEmpty else { return 0 }
        if str.hasSuffix("%") { str.removeLast() }
        str = str.replacingOccurrences(of: ",", with: "")
        return Double(str) ?? 0
    }

    private func parseCurrency(_ s: String) -> Double {
        var str = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if str.hasPrefix("$") { str.removeFirst() }
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
        return (Double(str) ?? 0) * multiplier
    }

    // If the Market Cap stat is placeholder or implausibly low, compute a local fallback
    private func marketCapFallbackIfNeeded(current: String?) -> String? {
        let cur = (current ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isPlaceholder = cur.isEmpty || cur == "—" || cur == "$0.00" || cur == "$0"
        
        // Parse current value for cross-validation
        let currentValue = parseCurrency(cur)
        
        // 0) If MarketViewModel already has a validated global cap, prefer it
        if let vmCap = MarketViewModel.shared.globalMarketCap, vmCap.isFinite, vmCap > 0 {
            if isPlaceholder || currentValue <= 0 || currentValue < vmCap * 0.6 {
                return abbrevCurrency(vmCap)
            }
        }
        
        // Cross-validate: derive expected market cap from BTC cap and dominance
        let coins = bestCoins()
        let btc = coins.first { $0.symbol.lowercased() == "btc" }
        
        // Check multiple sources for BTC dominance (stats may not be populated yet)
        let btcDom: Double = {
            let fromStats = parsePercent(statsVM.stats.first(where: { $0.title == "BTC Dom" })?.value)
            if fromStats > 10 && fromStats < 90 { return fromStats }
            if let fromVM = MarketViewModel.shared.btcDominance, fromVM.isFinite, fromVM > 10, fromVM < 90 { return fromVM }
            return fromStats
        }()
        
        if let b = btc, btcDom > 10, btcDom < 90 {
            let btcCap = bestCap(for: b)
            if btcCap > 0 {
                let derivedTotal = btcCap / (btcDom / 100.0)
                // If current value is implausibly low (less than 60% of derived), use derived
                if derivedTotal > 0 && (isPlaceholder || currentValue < derivedTotal * 0.6 || currentValue <= 0) {
                    return abbrevCurrency(derivedTotal)
                }
            }
        }
        
        guard isPlaceholder else { return nil }
        
        // Sum best-available caps from coins
        if !coins.isEmpty {
            let sum = coins.map { bestCap(for: $0) }.reduce(0, +)
            if sum.isFinite, sum > 0 { return abbrevCurrency(sum) }
            // Derive from BTC or ETH dominance if available
            let eth = coins.first { $0.symbol.lowercased() == "eth" }
            let ethDom: Double = {
                let fromStats = parsePercent(statsVM.stats.first(where: { $0.title == "ETH Dom" })?.value)
                if fromStats > 0 { return fromStats }
                if let fromVM = MarketViewModel.shared.ethDominance, fromVM.isFinite, fromVM > 0 { return fromVM }
                return fromStats
            }()
            if let b = btc { let bcap = bestCap(for: b); if bcap > 0, btcDom > 0 { let total = bcap / (btcDom/100); if total.isFinite, total > 0 { return abbrevCurrency(total) } } }
            if let e = eth { let ecap = bestCap(for: e); if ecap > 0, ethDom > 0 { let total = ecap / (ethDom/100); if total.isFinite, total > 0 { return abbrevCurrency(total) } } }
        }
        return nil
    }

    // DEBUG: Control verbose logging for market stats sources
    #if DEBUG
    private static var verboseStatsLogging = false
    private static var lastStatsLogAt: Date?
    #endif
    
    private func value(for title: String) -> String {
        let base = statsVM.stats.first(where: { $0.title == title })?.value
        
        #if DEBUG
        // Log data sources periodically (every 30 seconds) when verbose logging is enabled
        func logSource(_ source: String, _ value: String) {
            guard Self.verboseStatsLogging else { return }
            let now = Date()
            if let last = Self.lastStatsLogAt, now.timeIntervalSince(last) < 30 { return }
            Self.lastStatsLogAt = now
            print("[MarketStatsView] \(title): \(value) (source: \(source))")
        }
        #endif
        
        // Market Cap fallback via MarketViewModel
        if title == "Market Cap", let fallback = marketCapFallbackIfNeeded(current: base) {
            #if DEBUG
            logSource("computed fallback", fallback)
            #endif
            return fallback
        }
        // 24h Change: PRIORITY - always prefer live globalChange24hPercent for consistency
        if title == "24h Change" {
            // Always prefer live value from MarketViewModel when available to prevent flicker
            if let v = MarketViewModel.shared.globalChange24hPercent, v.isFinite {
                let result = String(format: "%.2f%%", v)
                #if DEBUG
                logSource("live MarketViewModel.globalChange24hPercent", result)
                #endif
                return result
            }
            // Fallback to cached statsVM value if globalChange24hPercent isn't ready yet
            let cur = (base ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let isPlaceholder = cur.isEmpty || cur == "—" || cur == "0.00%" || cur == "0%"
            if !isPlaceholder {
                #if DEBUG
                logSource("cached statsVM", cur)
                #endif
                return cur
            }
        }
        // BTC Dominance: PRIORITY - always prefer live btcDominance for consistency
        if title == "BTC Dom" {
            if let v = MarketViewModel.shared.btcDominance, v.isFinite, v > 0 {
                let result = String(format: "%.2f%%", v)
                #if DEBUG
                logSource("live MarketViewModel.btcDominance", result)
                #endif
                return result
            }
            let cur = (base ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let isPlaceholder = cur.isEmpty || cur == "—" || cur == "0.00%" || cur == "0%"
            if !isPlaceholder {
                #if DEBUG
                logSource("cached statsVM", cur)
                #endif
                return cur
            }
        }
        // ETH Dominance: PRIORITY - always prefer live ethDominance for consistency
        if title == "ETH Dom" {
            if let v = MarketViewModel.shared.ethDominance, v.isFinite, v > 0 {
                let result = String(format: "%.2f%%", v)
                #if DEBUG
                logSource("live MarketViewModel.ethDominance", result)
                #endif
                return result
            }
            let cur = (base ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let isPlaceholder = cur.isEmpty || cur == "—" || cur == "0.00%" || cur == "0%"
            if !isPlaceholder {
                #if DEBUG
                logSource("cached statsVM", cur)
                #endif
                return cur
            }
        }
        if let v = base {
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            #if DEBUG
            logSource("statsVM base", trimmed.isEmpty ? "—" : v)
            #endif
            return trimmed.isEmpty ? "—" : v
        }
        #if DEBUG
        logSource("none", "—")
        #endif
        return "—"
    }

    @State private var hasAppeared = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                GoldHeaderGlyph(systemName: "globe")
                
                Text("Market Stats")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                Spacer()
            }
            
            // Stats content with gold icons per stat
            if !statsVM.stats.isEmpty {
                VStack(spacing: 4) {
                    // Top row: Market Cap, BTC Dom, ETH Dom
                    HStack(spacing: 4) {
                        GoldStatItemView(title: "Market Cap", value: value(for: "Market Cap"), iconName: StatIcon.name(for: "Market Cap"))
                        GoldStatItemView(title: "BTC Dom", value: value(for: "BTC Dom"), iconName: StatIcon.name(for: "BTC Dom"))
                        GoldStatItemView(title: "ETH Dom", value: value(for: "ETH Dom"), iconName: StatIcon.name(for: "ETH Dom"))
                    }
                    
                    // Gold-tinted divider
                    PremiumDivider()
                    
                    // Bottom row: Volume, Volatility, 24h Change
                    HStack(spacing: 4) {
                        GoldStatItemView(title: "24h Volume", value: value(for: "24h Volume"), iconName: StatIcon.name(for: "24h Volume"))
                        GoldStatItemView(title: "24h Volatility", value: value(for: "24h Volatility"), iconName: StatIcon.name(for: "24h Volatility"))
                        GoldStatItemView(title: "24h Change", value: value(for: "24h Change"), iconName: StatIcon.name(for: "24h Change"))
                    }
                }
            } else {
                // Loading state
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(GoldTheme.base)
                    Spacer()
                }
                .frame(minHeight: 60)
            }
        }
        .id(refreshTick)
        .onAppear {
            // Nudge an update shortly after appear to let MarketViewModel populate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { scheduleRefreshDebounced() }
            withAnimation(.easeOut(duration: 0.35)) {
                hasAppeared = true
            }
        }
        // PERFORMANCE FIX v19: Use onReceive on specific publishers instead of onChange
        // onChange(of: marketVM.allCoins.count) required @ObservedObject which observed ALL 25+ publishers
        // SCROLL FIX: Added scroll guard - these can trigger during scroll and .id(refreshTick) forces
        // full view recreation which adds jank. Stats are not time-critical during scroll.
        .onReceive(MarketViewModel.shared.$allCoins.map(\.count).removeDuplicates().debounce(for: .seconds(2), scheduler: DispatchQueue.main)) { _ in
            guard !isInGlobalStartupPhase(), !ScrollStateManager.shared.isScrolling else { return }
            scheduleRefreshDebounced()
        }
        .onReceive(MarketViewModel.shared.$globalMarketCap.removeDuplicates().debounce(for: .seconds(2), scheduler: DispatchQueue.main)) { _ in
            guard !isInGlobalStartupPhase(), !ScrollStateManager.shared.isScrolling else { return }
            scheduleRefreshDebounced()
        }
        .onChange(of: statsVM.stats.count) { _, _ in
            // PERFORMANCE FIX v12: Skip during global startup phase
            // SCROLL FIX: Skip during scroll to prevent .id(refreshTick) jank
            guard !isInGlobalStartupPhase(), !ScrollStateManager.shared.isScrolling else { return }
            scheduleRefreshDebounced()
        }
        .padding(16)
        .background(
            PremiumGlassCard(showGoldAccent: true, cornerRadius: 16) {
                Color.clear
            }
        )
        // Subtle appear animation
        .scaleEffect(hasAppeared ? 1.0 : 0.98)
        .opacity(hasAppeared ? 1.0 : 0.0)
    }
    
    /// Debounced refresh to prevent rapid flickering of stats values
    private func scheduleRefreshDebounced() {
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastRefreshAt)
        
        // Cancel any pending refresh
        pendingRefreshWork?.cancel()
        
        if timeSinceLast >= minRefreshInterval {
            // Enough time has passed, refresh immediately
            DispatchQueue.main.async {
                lastRefreshAt = Date()
                refreshTick &+= 1
            }
        } else {
            // Schedule a delayed refresh
            let delay = minRefreshInterval - timeSinceLast
            let work = DispatchWorkItem { [self] in
                DispatchQueue.main.async {
                    lastRefreshAt = Date()
                    refreshTick &+= 1
                }
            }
            pendingRefreshWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }
}

// MARK: - GoldStatItemView (Gold icon + title/value for premium look)

struct GoldStatItemView: View {
    let title: String
    let value: String
    let iconName: String
    
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    
    private var isCompactLayout: Bool {
        (horizontalSizeClass == .compact) || sizeCategory.isAccessibilityCategory
    }
    private var isDark: Bool { colorScheme == .dark }

    private var valueColor: Color {
        if title.lowercased().contains("change") {
            let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("-") { return .red }
            if s == "—" { return DS.Adaptive.textPrimary }
            return .green
        }
        return DS.Adaptive.textPrimary
    }
    
    // Gold gradient for the stat icon
    private var iconGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [BrandColors.goldLight, BrandColors.goldBase]
                : [BrandColors.goldBase, BrandColors.goldDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            // Gold icon with subtle background
            // LIGHT MODE FIX: Increased icon circle opacity from 0.10/0.02 to 0.20/0.06
            // so icons are actually visible against the light card background.
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BrandColors.goldBase.opacity(isDark ? 0.18 : 0.20),
                                BrandColors.goldBase.opacity(isDark ? 0.04 : 0.06)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 14
                        )
                    )
                    .frame(width: 22, height: 22)
                
                Image(systemName: iconName)
                    .font(.system(size: isCompactLayout ? 10 : 11, weight: .semibold))
                    .foregroundStyle(iconGradient)
            }
            
            // Title
            Text(title)
                .font(.system(size: isCompactLayout ? 8 : 9, weight: .medium, design: .rounded))
                .foregroundColor(DS.Adaptive.textSecondary)
                .lineLimit(1)
            
            // Value
            Text(value)
                .font(.system(size: isCompactLayout ? 13 : 15, weight: .bold, design: .rounded))
                .foregroundColor(valueColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
    }
}

// MARK: - Stat icon mapping
private enum StatIcon {
    static func name(for stat: String) -> String {
        switch stat {
        case "Market Cap":      return "dollarsign.circle.fill"
        case "BTC Dom":         return "bitcoinsign.circle.fill"
        case "ETH Dom":         return "diamond.fill"
        case "24h Volume":      return "chart.bar.fill"
        case "24h Volatility":  return "bolt.fill"
        case "24h Change":      return "percent"
        default:                return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - MarketStatsBar (Compact horizontal bar for Market page header)

/// A compact horizontal stats bar designed for the Market page header.
/// Shows key market metrics in a single scrollable row.
struct MarketStatsBar: View {
    @StateObject private var statsVM = MarketStatsViewModel()
    // PERFORMANCE FIX v19: Removed unused @ObservedObject for MarketViewModel
    // It was declared but never used in MarketStatsBar, causing unnecessary re-renders.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    // SCROLL FIX: Track scroll state to suppress animations during scroll.
    // MarketStatsBar is ABOVE the main ScrollView, so the UIKit bridge's layer.speed=0
    // animation freeze does NOT apply to it. Without this, data updates during scroll
    // trigger .animation() modifiers below, causing microstutter.
    @State private var suppressAnimations = false
    
    private var isCompactLayout: Bool {
        (horizontalSizeClass == .compact) || sizeCategory.isAccessibilityCategory
    }
    private var isDark: Bool { colorScheme == .dark }
    
    // PERFORMANCE FIX v25: Cached currency formatter (same pattern as MarketStatsView)
    private static let cachedCurrencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = CurrencyManager.currencyCode
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()
    
    // Compact currency formatter
    private func abbrevCurrency(_ v: Double) -> String {
        let absV = abs(v)
        let sym = CurrencyManager.symbol
        if absV >= 1_000_000_000_000 { return String(format: "%@%.2fT", sym, v/1_000_000_000_000) }
        if absV >= 1_000_000_000 { return String(format: "%@%.1fB", sym, v/1_000_000_000) }
        if absV >= 1_000_000 { return String(format: "%@%.1fM", sym, v/1_000_000) }
        return Self.cachedCurrencyFormatter.string(from: v as NSNumber) ?? String(format: "%@%.2f", sym, v)
    }
    
    private func parsePercent(_ s: String?) -> Double {
        guard var str = s?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !str.isEmpty else { return 0 }
        if str.hasSuffix("%") { str.removeLast() }
        str = str.replacingOccurrences(of: ",", with: "")
        return Double(str) ?? 0
    }
    
    private func parseCurrency(_ s: String) -> Double {
        var str = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if str.hasPrefix("$") { str.removeFirst() }
        let suffixMultipliers: [String: Double] = ["k": 1_000, "m": 1_000_000, "b": 1_000_000_000, "t": 1_000_000_000_000]
        var multiplier: Double = 1
        for (suffix, mult) in suffixMultipliers {
            if str.hasSuffix(suffix) { multiplier = mult; str = String(str.dropLast()); break }
        }
        str = str.replacingOccurrences(of: ",", with: "")
        return (Double(str) ?? 0) * multiplier
    }
    
    private func bestCoins() -> [MarketCoin] {
        let vm = MarketViewModel.shared
        if !vm.allCoins.isEmpty { return vm.allCoins }
        if !vm.lastGoodAllCoins.isEmpty { return vm.lastGoodAllCoins }
        if !vm.coins.isEmpty { return vm.coins }
        if let cached: [MarketCoin] = CacheManager.shared.load([MarketCoin].self, from: "coins_cache.json"), !cached.isEmpty { return cached }
        return []
    }
    
    private func bestCap(for c: MarketCoin) -> Double {
        if let cap = c.marketCap, cap.isFinite, cap > 0 { return cap }
        if let p = c.priceUsd, p.isFinite, p > 0 {
            if let circ = c.circulatingSupply, circ.isFinite, circ > 0 { return p * circ }
            if let total = c.totalSupply, total.isFinite, total > 0 { return p * total }
        }
        return 0
    }
    
    private func marketCapFallback(current: String?) -> String? {
        let cur = (current ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isPlaceholder = cur.isEmpty || cur == "—" || cur == "$0.00" || cur == "$0"
        let currentValue = parseCurrency(cur)
        
        let coins = bestCoins()
        let btc = coins.first { $0.symbol.lowercased() == "btc" }
        let btcDom = parsePercent(statsVM.stats.first(where: { $0.title == "BTC Dom" })?.value)
        
        if let b = btc, btcDom > 10, btcDom < 90 {
            let btcCap = bestCap(for: b)
            if btcCap > 0 {
                let derivedTotal = btcCap / (btcDom / 100.0)
                if derivedTotal > 0 && (isPlaceholder || currentValue < derivedTotal * 0.6 || currentValue <= 0) {
                    return abbrevCurrency(derivedTotal)
                }
            }
        }
        
        guard isPlaceholder else { return nil }
        if let cap = MarketViewModel.shared.globalMarketCap, cap.isFinite, cap > 0 { return abbrevCurrency(cap) }
        if !coins.isEmpty {
            let sum = coins.map { bestCap(for: $0) }.reduce(0, +)
            if sum.isFinite, sum > 0 { return abbrevCurrency(sum) }
        }
        return nil
    }
    
    private func value(for title: String) -> String {
        let base = statsVM.stats.first(where: { $0.title == title })?.value
        if title == "Market Cap", let fallback = marketCapFallback(current: base) { return fallback }
        if title == "24h Change" {
            // PRIORITY: Always prefer live globalChange24hPercent from MarketViewModel when available
            // This ensures consistency and prevents stale cached values from flashing on load
            if let v = MarketViewModel.shared.globalChange24hPercent, v.isFinite {
                return String(format: "%.2f%%", v)
            }
            // Fallback to statsVM value if globalChange24hPercent isn't ready yet
            let cur = (base ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let isPlaceholder = cur.isEmpty || cur == "—" || cur == "0.00%" || cur == "0%"
            if !isPlaceholder {
                return cur
            }
        }
        if title == "BTC Dom" {
            // PRIORITY: Always prefer live btcDominance from MarketViewModel when available
            if let v = MarketViewModel.shared.btcDominance, v.isFinite, v > 0 {
                return String(format: "%.2f%%", v)
            }
            let cur = (base ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let isPlaceholder = cur.isEmpty || cur == "—" || cur == "0.00%" || cur == "0%"
            if !isPlaceholder {
                return cur
            }
        }
        if let v = base {
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "—" : v
        }
        return "—"
    }
    
    /// Extracts numeric value from a percentage string (e.g., "-1.30%" -> -1.30)
    private func extractNumericValue(_ s: String) -> Double? {
        var str = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if str == "—" || str.isEmpty { return nil }
        if str.hasSuffix("%") { str.removeLast() }
        str = str.replacingOccurrences(of: ",", with: "")
        return Double(str)
    }
    
    /// Returns the absolute value string for display (removes minus sign since arrow shows direction)
    private func absoluteValueString(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "—" || trimmed.isEmpty { return trimmed }
        
        // Extract the numeric value and format as absolute
        if let numericValue = extractNumericValue(trimmed) {
            let absValue = abs(numericValue)
            return String(format: "%.2f%%", absValue)
        }
        
        // Fallback: just remove leading minus if present
        if trimmed.hasPrefix("-") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
    
    private func changeColor(for value: String) -> Color {
        if let numericValue = extractNumericValue(value) {
            if numericValue < 0 { return .red }
            if numericValue > 0 { return .green }
        }
        return DS.Adaptive.textSecondary
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Stats row - no horizontal scroll needed, 4 items fit on all devices
            HStack(spacing: 0) {
                // Market Cap - primary metric
                StatChip(label: "MCap", value: value(for: "Market Cap"), valueColor: DS.Adaptive.textPrimary, isPrimary: true)
                
                Spacer(minLength: 4)
                statDivider
                Spacer(minLength: 4)
                
                // BTC Dominance
                StatChip(label: "BTC", value: value(for: "BTC Dom"), valueColor: DS.Adaptive.textPrimary)
                
                Spacer(minLength: 4)
                statDivider
                Spacer(minLength: 4)
                
                // 24h Volume
                StatChip(label: "Vol", value: value(for: "24h Volume"), valueColor: DS.Adaptive.textPrimary)
                
                Spacer(minLength: 4)
                statDivider
                Spacer(minLength: 4)
                
                // 24h Change with directional indicator
                let changeValue = value(for: "24h Change")
                let numericChange = extractNumericValue(changeValue)
                let isPositive = (numericChange ?? 0) >= 0
                let displayValue = absoluteValueString(changeValue)
                StatChip(
                    label: "24h",
                    value: displayValue,
                    valueColor: changeColor(for: changeValue),
                    showDirectionIndicator: numericChange != nil && changeValue != "—",
                    isPositive: isPositive
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Bottom divider
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(height: 0.5)
        }
        .background(DS.Adaptive.background)
        // SCROLL FIX: Suppress stat-bar animations while user is scrolling the coin list.
        // These animations are outside the UIKit scroll bridge's layer.speed=0 freeze zone,
        // so data updates during scroll would cause visible microstutter without this guard.
        .transaction { txn in
            if suppressAnimations { txn.disablesAnimations = true }
        }
        .animation(suppressAnimations ? nil : .easeInOut(duration: 0.2), value: value(for: "Market Cap"))
        .animation(suppressAnimations ? nil : .easeInOut(duration: 0.2), value: value(for: "BTC Dom"))
        .animation(suppressAnimations ? nil : .easeInOut(duration: 0.2), value: value(for: "24h Volume"))
        .animation(suppressAnimations ? nil : .easeInOut(duration: 0.2), value: value(for: "24h Change"))
        .onReceive(ScrollStateManager.shared.$isScrolling.removeDuplicates()) { scrolling in
            suppressAnimations = scrolling
        }
    }
    
    private var statDivider: some View {
        Rectangle()
            .fill(DS.Adaptive.divider.opacity(0.5))
            .frame(width: 1, height: 20)
    }
    
    // MARK: - StatChip (inline stat display for the bar)
    
    private struct StatChip: View {
        let label: String
        let value: String
        let valueColor: Color
        var isPrimary: Bool = false
        var showDirectionIndicator: Bool = false
        var isPositive: Bool = true
        
        @Environment(\.sizeCategory) private var sizeCategory
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        private var isCompact: Bool {
            (horizontalSizeClass == .compact) || sizeCategory.isAccessibilityCategory
        }
        
        var body: some View {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: isCompact ? 10 : 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                // Show direction arrow for 24h change
                if showDirectionIndicator && value != "—" {
                    Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                        .font(.system(size: isCompact ? 8 : 9, weight: .bold))
                        .foregroundColor(valueColor)
                }
                
                Text(value)
                    .font(.system(size: isPrimary ? (isCompact ? 12 : 13) : (isCompact ? 11 : 12), weight: .bold, design: .rounded))
                    .foregroundColor(valueColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}
