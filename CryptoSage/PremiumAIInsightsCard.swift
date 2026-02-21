import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

private enum LocalGold {
    // Use centralized BrandColors for consistency across all sections
    static var light: Color { BrandColors.goldLight }
    static var base: Color { BrandColors.goldBase }
    static var dark: Color { BrandColors.goldDark }
    
    // Adaptive text color - gold in dark mode, darker amber/brown for readability in light mode
    static func textColor(isDark: Bool) -> Color {
        isDark ? BrandColors.goldLight : Color(red: 0.6, green: 0.45, blue: 0.1) // Darker amber for light mode
    }
    
    // Adaptive accent color for chips/buttons - gold in dark, charcoal in light
    static func accentColor(isDark: Bool) -> Color {
        isDark ? BrandColors.goldLight : BrandColors.silverBase
    }
    
    // Gradients - use light mode versions without dark edge on light backgrounds
    static var gradientH: LinearGradient { BrandColors.goldHorizontalLight }
    static var gradientV: LinearGradient { BrandColors.goldVerticalLight }
    static var gradientHDark: LinearGradient { BrandColors.goldHorizontal }
    static var gradientVDark: LinearGradient { BrandColors.goldVertical }
}

private enum InsightsConfig {
    // Toggle to restore the sparkles icon in the Ask AI prompt bar
    static let askAIShowsIcon = false
    static let useAskAILinkRow = true
}

public struct PremiumAIInsightsCard: View {
    private let portfolioVM: PortfolioViewModel
    private let onOpenChat: (String) -> Void
    
    // Smart prompts - dynamically generated based on context
    @State private var smartPrompts: [String] = []
    private let promptCount: Int = 3

    @State private var promptIndex = 0
    @State private var isHidden = false
    @AppStorage("hideBalances") private var hideBalances: Bool = false
    @State private var lastInteraction: Date = .distantPast
    @State private var autoCycleEnabled: Bool = true
    @State private var cycleTimer = Timer.publish(every: 14, on: .main, in: .common).autoconnect()
    /// FIX v5.0.3: Changed from @State to @Binding so the navigationDestination can be
    /// placed at the parent level (outside any lazy container).
    @Binding var openAllInsights: Bool
    @State private var lastPromptRefresh: Date = .distantPast
    
    // Paper Trading support - observe the manager to get Paper Trading data
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    
    // Refresh interval for smart prompts (regenerate when stale)
    private let promptRefreshInterval: TimeInterval = 60

    init(
        portfolioVM: PortfolioViewModel,
        onOpenChat: @escaping (String) -> Void,
        openAllInsights: Binding<Bool> = .constant(false)
    ) {
        self.portfolioVM = portfolioVM
        self.onOpenChat = onOpenChat
        self._openAllInsights = openAllInsights
    }
    
    /// Active prompts to display - uses smart prompts if available, falls back to defaults
    private var prompts: [String] {
        if smartPrompts.isEmpty {
            return [
                "How can I improve my portfolio diversification?",
                "What trades performed best last week?",
                "Should I rebalance my assets now?"
            ]
        }
        return smartPrompts
    }
    
    /// Refresh smart prompts from SmartPromptService
    private func refreshSmartPrompts() {
        let holdings = portfolioVM.holdings
        let newPrompts = SmartPromptService.shared.buildContextualPrompts(count: promptCount, holdings: holdings)
        
        // Only update if we got valid prompts
        if !newPrompts.isEmpty {
            smartPrompts = newPrompts
            lastPromptRefresh = Date()
            
            // Reset index if it's out of bounds
            if promptIndex >= newPrompts.count {
                promptIndex = 0
            }
        }
    }
    
    // MARK: - Paper Trading Data Helpers
    
    /// Check if Paper Trading mode is active
    private var isPaperTradingActive: Bool {
        paperTradingManager.isPaperTradingEnabled
    }
    
    /// Get current market prices for Paper Trading calculations
    /// PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing across all views
    private var paperTradingPrices: [String: Double] {
        var prices: [String: Double] = [:]
        for coin in MarketViewModel.shared.allCoins {
            let symbol = coin.symbol.uppercased()
            // Priority: bestPrice() > coin.priceUsd (fallback)
            if let price = MarketViewModel.shared.bestPrice(for: coin.id), price > 0 {
                prices[symbol] = price
            } else if let price = coin.priceUsd, price > 0 {
                prices[symbol] = price
            }
        }
        // FIX: Try bestPrice(forSymbol:) for held assets not in allCoins
        for (asset, _) in paperTradingManager.paperBalances {
            let symbol = asset.uppercased()
            if prices[symbol] == nil || prices[symbol] == 0 {
                if let symbolPrice = MarketViewModel.shared.bestPrice(forSymbol: symbol), symbolPrice > 0 {
                    prices[symbol] = symbolPrice
                }
            }
        }
        // Fallback: Use lastKnownPrices only if fresh (< 30 min)
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
        return prices
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
    
    /// Generate allocation data from Paper Trading balances
    private var paperTradingAllocationData: [(symbol: String, percent: Double)] {
        let totalValue = paperTradingTotalValue
        guard totalValue > 0 else { return [] }
        
        let prices = paperTradingPrices
        var allocations: [(symbol: String, percent: Double)] = []
        
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
            if percent >= 0.5 { // Only show assets with >= 0.5% allocation
                allocations.append((symbol: asset, percent: percent))
            }
        }
        
        return allocations.sorted { $0.percent > $1.percent }
    }

    private var personalizedTip: String? {
        // Use Paper Trading allocation data when in Paper Trading mode
        let allocationData: [(symbol: String, percent: Double)]
        if isPaperTradingActive {
            allocationData = paperTradingAllocationData
        } else {
            allocationData = portfolioVM.allocationData.map { (symbol: $0.symbol, percent: $0.percent) }
        }
        
        guard let top = allocationData.max(by: { $0.percent < $1.percent }) else { return nil }
        let topPct = Int(round(top.percent))
        guard topPct >= 20 else { return nil }
        return "Your largest holding is \(top.symbol) at \(topPct)%. Consider rebalancing if this exceeds your target."
    }

    private var changeAmountAndPercent: (amount: Double, percent: Double, isUp: Bool)? {
        // Use Paper Trading P&L when in Paper Trading mode
        if isPaperTradingActive {
            let pnl = paperTradingProfitLoss
            let pnlPercent = paperTradingProfitLossPercent
            // Only show if there's been any activity or meaningful change
            if paperTradingManager.totalTradeCount > 0 || abs(pnl) > 0.01 {
                return (pnl, pnlPercent, pnl >= 0)
            }
            return nil
        }
        
        // Regular portfolio history-based calculation
        let hist = portfolioVM.history
        guard let firstVal = hist.first?.value, let lastVal = hist.last?.value, firstVal > 0 else { return nil }
        let amount = lastVal - firstVal
        let percent = (lastVal / firstVal - 1.0) * 100.0
        return (amount, percent, amount >= 0)
    }

    private var amountText: String {
        guard !hideBalances else { return "••••••" }
        guard let a = changeAmountAndPercent?.amount else { return "$0.00" }
        return currency(a)
    }

    private var percentText: String {
        guard !hideBalances else { return "•••%" }
        guard let p = changeAmountAndPercent?.percent else { return "0.00%" }
        return pct(p)
    }

    private var currentPrompt: String {
        guard prompts.indices.contains(promptIndex) else { return "" }
        return prompts[promptIndex]
    }

    public var body: some View {
        // Precompute simple values to reduce type-checking load
        let tip = personalizedTip
        let prompt = currentPrompt
        
        // Determine the period label based on mode
        let periodLabel = isPaperTradingActive ? "P&L" : "Portfolio change"
        
        // When privacy mode is enabled, use a generic prompt instead of showing actual values
        let explainPrompt = hideBalances
            ? "Explain my portfolio change this period. Break down contributions by asset, highlight biggest drivers and risks, and recommend one actionable step."
            : "Explain my portfolio change \(amountText) (\(percentText)) this period. Break down contributions by asset, highlight biggest drivers and risks, and recommend one actionable step."
        
        // Use appropriate allocation data based on mode
        let allocationData: [(symbol: String, percent: Double)] = isPaperTradingActive
            ? paperTradingAllocationData
            : portfolioVM.allocationData.map { (symbol: $0.symbol, percent: $0.percent) }
        
        var onRebalanceAction: (() -> Void)? = nil
        if let top = allocationData.max(by: { $0.percent < $1.percent }) {
            let topPct = Int(round(top.percent))
            if topPct >= 35 {
                let rbPrompt = "I'm concentrated \(topPct)% in \(top.symbol). Should I rebalance now? Suggest a target allocation and specific trades to reach it with minimal tax impact."
                onRebalanceAction = { onOpenChat(rbPrompt) }
            }
        }
        
        // Volatility action - only for regular portfolio mode (Paper Trading doesn't have history data)
        var onVolatilityAction: (() -> Void)? = nil
        if !isPaperTradingActive {
            if let volLabel = volatilityLabel(from: portfolioVM.history.map { $0.value }), volLabel == "High" {
                let volPrompt = "Volatility appears high in my portfolio this period. Explain the drivers, risks, and suggest hedging or position-sizing steps I can take."
                onVolatilityAction = { onOpenChat(volPrompt) }
            }
        }
        
        let chips: [InsightChipData] = {
            var result: [InsightChipData] = []
            if let delta = changeAmountAndPercent {
                let dir = delta.isUp ? "Up" : "Down"
                let pctText = hideBalances ? "•••%" : String(format: "%.2f%%", abs(delta.percent))
                result.append(InsightChipData(text: "\(dir) \(pctText)", style: delta.isUp ? .positive : .negative))
            }
            // Use the mode-appropriate allocation data
            if let top = allocationData.max(by: { $0.percent < $1.percent }) {
                let topPct = Int(round(top.percent))
                if topPct >= 20 {
                    result.append(InsightChipData(text: "Concentration \(top.symbol) \(topPct)%", style: .gold))
                }
            }
            // For Paper Trading, show trade count instead of volatility (since we don't have history data)
            if isPaperTradingActive {
                let tradeCount = paperTradingManager.totalTradeCount
                if tradeCount > 0 {
                    result.append(InsightChipData(text: "\(tradeCount) Trade\(tradeCount == 1 ? "" : "s")", style: .neutral))
                }
            } else {
                if let vol = volatilityLabel(from: portfolioVM.history.map { $0.value }) {
                    result.append(InsightChipData(text: "Volatility \(vol)", style: .neutral))
                }
            }
            return Array(result.prefix(3))
        }()
        let isHiddenLocal = isHidden
        return CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                InsightsCardContent(
                    amountText: amountText,
                    percentText: percentText,
                    isUp: changeAmountAndPercent?.isUp ?? true,
                    periodLabel: periodLabel,
                    tip: tip,
                    currentPrompt: prompt,
                    isHidden: isHiddenLocal,
                    onPrev: {
                        lastInteraction = Date()
                        withAnimation { promptIndex = (promptIndex - 1 + max(1, prompts.count)) % max(1, prompts.count) }
                    },
                    onNext: {
                        lastInteraction = Date()
                        withAnimation { promptIndex = (promptIndex + 1) % max(1, prompts.count) }
                    },
                    onTapAskAI: { onOpenChat(prompt) },
                    onExplain: { onOpenChat(explainPrompt) },
                    onRebalance: onRebalanceAction,
                    onVolatility: onVolatilityAction,
                    chips: chips
                )
                
                allInsightsButton
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        // FIX v5.0.3: navigationDestination for AllAIInsightsView removed — should be
        // placed at the parent level (outside any lazy container) to fix SwiftUI warning.
        .onReceive(cycleTimer) { _ in
            // PERFORMANCE FIX: Skip timer actions during scroll to avoid animations and processing
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            
            // Defer ALL state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Double-check scroll state after async dispatch
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                
                if autoCycleEnabled && prompts.count > 1 && Date().timeIntervalSince(lastInteraction) > 18 {
                    withAnimation { promptIndex = (promptIndex + 1) % max(1, prompts.count) }
                }
                
                // Refresh smart prompts periodically if stale
                if Date().timeIntervalSince(lastPromptRefresh) > promptRefreshInterval {
                    refreshSmartPrompts()
                }
            }
        }
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Generate context-aware prompts on first appear
                refreshSmartPrompts()
            }
        }
        .onChange(of: portfolioVM.holdings.count) { _, _ in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Refresh prompts when holdings change significantly
                refreshSmartPrompts()
            }
        }
    }
    
    // MARK: - All Insights Button
    
    private var allInsightsButton: some View {
        SectionCTAButton(title: "Portfolio Insights", icon: "chart.pie.fill", compact: true) {
            openAllInsights = true
        }
        .padding(.top, 2)
    }
}

// MARK: - Local Helper Functions

// PERFORMANCE FIX: Cached currency formatter
private let _insightsCurrencyFmt: NumberFormatter = {
    let nf = NumberFormatter(); nf.numberStyle = .currency
    nf.currencyCode = Locale.current.currency?.identifier ?? "USD"
    nf.minimumFractionDigits = 2; nf.maximumFractionDigits = 2; return nf
}()
private func currency(_ v: Double) -> String {
    let sign = v >= 0 ? "+" : "-"
    let absValue = abs(v)
    if let formatted = _insightsCurrencyFmt.string(from: NSNumber(value: absValue)) {
        return "\(sign)\(formatted)"
    }
    return "\(sign)$\(String(format: "%.2f", absValue))"
}

private func pct(_ p: Double) -> String {
    let value = abs(p)
    return String(format: "%.2f%%", value)
}

private func volatilityLabel(from rawValues: [Double]) -> String? {
    let values = rawValues.filter { $0.isFinite && $0 > 0 }
    guard values.count >= 3 else { return nil }
    var returns: [Double] = []
    for i in 1..<values.count {
        let prev = values[i-1]
        let curr = values[i]
        guard prev > 0 else { continue }
        returns.append(curr / prev - 1.0)
    }
    guard returns.count >= 2 else { return nil }
    let mean = returns.reduce(0, +) / Double(returns.count)
    // Use sample variance (n-1) for unbiased estimation
    let variance = returns.reduce(0) { $0 + pow($1 - mean, 2) } / Double(returns.count - 1)
    let std = sqrt(variance)
    switch std {
    case ..<0.008: return "Low"
    case ..<0.02: return "Medium"
    default: return "High"
    }
}

// MARK: - Supporting Views and Modifiers

private struct GlassCard: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 12
    var body: some View {
        let base = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isDark = colorScheme == .dark
        ZStack {
            // Adaptive gradient - dark in dark mode, warm cream in light mode
            base
                .fill(
                    LinearGradient(
                        colors: isDark ? [
                            Color(red: 0.09, green: 0.09, blue: 0.11),
                            Color(red: 0.03, green: 0.03, blue: 0.05)
                        ] : [
                            Color(red: 1.0, green: 0.992, blue: 0.976),   // Warm cream top #FFFDF9
                            Color(red: 0.99, green: 0.98, blue: 0.965)    // Slightly warmer bottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(base.stroke(DS.Adaptive.stroke, lineWidth: 1))
                .overlay(base.stroke(DS.Adaptive.divider, lineWidth: 0.5))
        }
        .background(
            Group {
                if #available(iOS 26.0, *) {
                    // Subtle glass effect on top of the neutral gradient
                    Color.clear
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                } else {
                    // Adaptive material
                    base.fill(.regularMaterial)
                        .opacity(isDark ? 0.35 : 0.5)
                }
            }
        )
    }
}

private struct InsightChipData: Hashable {
    enum Style { case gold, positive, negative, neutral }
    let text: String
    let style: Style
}

private struct InsightChip: View {
    let data: InsightChipData
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        Text(data.text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(stroke, lineWidth: 1))
    }
    private var foreground: Color {
        switch data.style {
        case .gold: return LocalGold.textColor(isDark: isDark)
        case .positive: return .green
        case .negative: return .red
        case .neutral: return .secondary
        }
    }
    private var fill: Color {
        switch data.style {
        case .gold: return LocalGold.textColor(isDark: isDark).opacity(isDark ? 0.12 : 0.1)
        case .positive: return Color.green.opacity(0.15)
        case .negative: return Color.red.opacity(0.15)
        case .neutral: return DS.Adaptive.surfaceOverlay
        }
    }
    private var stroke: Color {
        switch data.style {
        case .gold: return LocalGold.textColor(isDark: isDark).opacity(isDark ? 0.28 : 0.25)
        case .positive, .negative: return DS.Adaptive.divider
        case .neutral: return DS.Adaptive.divider
        }
    }
}

private struct InlineMetaRow: View {
    let items: [InsightChipData]
    let onTapVolatility: (() -> Void)?
    let onTapRebalance: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    if idx > 0 {
                        Text("•")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    let isVol = item.text.lowercased().hasPrefix("volatility")
                    let isHighVol = item.text.contains("High")
                    let isConcentration = item.text.lowercased().hasPrefix("concentration")
                    
                    if isVol, isHighVol, let onTapVolatility = onTapVolatility {
                        Button(action: onTapVolatility) {
                            Text(item.text)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(LocalGold.textColor(isDark: isDark))
                                .underline(false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Explain high volatility")
                    } else if isConcentration, let onTapRebalance = onTapRebalance {
                        Button(action: onTapRebalance) {
                            Text(item.text)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(LocalGold.textColor(isDark: isDark))
                                .underline(false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Get rebalance suggestion")
                    } else {
                        Text(item.text)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color(for: item.style))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func color(for style: InsightChipData.Style) -> Color {
        switch style {
        case .gold: return LocalGold.textColor(isDark: isDark)
        case .neutral: return .secondary
        case .positive, .negative: return .secondary
        }
    }
}

private struct InsightsCardContent: View {
    let amountText: String
    let percentText: String
    let isUp: Bool
    let periodLabel: String
    let tip: String?
    let currentPrompt: String
    let isHidden: Bool
    let onPrev: () -> Void
    let onNext: () -> Void
    let onTapAskAI: () -> Void
    let onExplain: () -> Void
    let onRebalance: (() -> Void)?
    let onVolatility: (() -> Void)?
    let chips: [InsightChipData]
    
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            GlassCard()
            VStack(alignment: .leading, spacing: 8) {
                StructuredHeadlineCard(amountText: amountText, percentText: percentText, isUp: isUp, periodLabel: periodLabel, tip: tip, onExplain: onExplain, onRebalance: onRebalance, onVolatility: onVolatility, chips: chips)
                if InsightsConfig.useAskAILinkRow {
                    AskAILinkRow(
                        currentPrompt: currentPrompt,
                        isHidden: isHidden,
                        onPrev: onPrev,
                        onNext: onNext,
                        onTapAskAI: onTapAskAI
                    )
                } else {
                    AskAIPromptBar(
                        currentPrompt: currentPrompt,
                        isHidden: isHidden,
                        onPrev: onPrev,
                        onNext: onNext,
                        onTapAskAI: onTapAskAI
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        // Subtle border for card definition
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke.opacity(isDark ? 0.5 : 0.4), lineWidth: 1)
        )
    }
}

private struct StructuredHeadlineCard: View {
    let amountText: String
    let percentText: String
    let isUp: Bool
    let periodLabel: String
    let tip: String?
    let onExplain: () -> Void
    let onRebalance: (() -> Void)?
    let onVolatility: (() -> Void)?
    let chips: [InsightChipData]

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Period label
            Text(periodLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // Amount + percent (tappable to explain)
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                onExplain()
            }) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Group {
                        if #available(iOS 17.0, *) {
                            Text(amountText)
                                .font(.system(.title2, design: .rounded).weight(.semibold))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.easeOut(duration: 0.5), value: amountText)
                        } else {
                            Text(amountText)
                                .font(.system(.title2, design: .rounded).weight(.semibold))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                                .monospacedDigit()
                        }
                    }
                    Text("(\(percentText))")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isUp ? .green : .red)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Explain this change")

            HStack(spacing: 8) {
                InlineMetaRow(items: chips.filter { $0.style != .positive && $0.style != .negative }, onTapVolatility: onVolatility, onTapRebalance: onRebalance)
                    .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .lineLimit(1)

            // Recommendation / tip (multiline)
            if let tipText = tip {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(LocalGold.textColor(isDark: isDark)).frame(width: 6, height: 6)
                    Text(tipText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(
            ZStack {
                // Base fill with improved contrast - warm cream in light mode
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isDark ? [
                                Color(red: 0.08, green: 0.08, blue: 0.10),
                                Color(red: 0.05, green: 0.05, blue: 0.07)
                            ] : [
                                Color(red: 0.995, green: 0.985, blue: 0.965),  // Warm cream top
                                Color(red: 0.985, green: 0.975, blue: 0.955)   // Slightly warmer bottom
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                // Subtle gold top accent gradient
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LocalGold.light.opacity(0.08), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            // Enhanced border with gold top accent
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [LocalGold.light.opacity(0.3), DS.Adaptive.divider, DS.Adaptive.divider],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        // Subtle gold left accent bar
        .overlay(alignment: .leading) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            LocalGold.light.opacity(isDark ? 0.8 : 0.7),
                            LocalGold.base.opacity(isDark ? 0.6 : 0.5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 10)
        }
    }
}

private struct AskAIPromptBar: View {
    let currentPrompt: String
    let isHidden: Bool
    let onPrev: () -> Void
    let onNext: () -> Void
    let onTapAskAI: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        HStack(spacing: 6) {
            if InsightsConfig.askAIShowsIcon {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LocalGold.textColor(isDark: isDark))
            }
            Text("Ask AI")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
            Text(isHidden ? "•••••" : currentPrompt)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
                .layoutPriority(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onPrev) { Image(systemName: "chevron.left").font(.caption2.weight(.bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Button(action: onNext) { Image(systemName: "chevron.right").font(.caption2.weight(.bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            Group {
                if #available(iOS 26.0, *) {
                    Capsule().fill(Color.clear).glassEffect(.regular)
                } else {
                    // PERFORMANCE FIX v19: Replaced .ultraThinMaterial with solid color
                    Capsule().fill(DS.Adaptive.chipBackground)
                }
            }
        )
        .overlay(Capsule().stroke(DS.Adaptive.divider, lineWidth: 0.8))
        .contentShape(Capsule())
        .onTapGesture { if !isHidden { onTapAskAI() } }
    }
}

private struct AskAILinkRow: View {
    let currentPrompt: String
    let isHidden: Bool
    let onPrev: () -> Void
    let onNext: () -> Void
    let onTapAskAI: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        let goldTextColor = LocalGold.textColor(isDark: isDark)
        
        HStack(spacing: 0) {
            // Chat icon + AI label - compact
            HStack(spacing: 3) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(goldTextColor.opacity(0.7))
                Text("AI")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(goldTextColor.opacity(0.85))
            }
            .padding(.leading, 10)
            
            // Navigation chevron left - compact
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(goldTextColor.opacity(0.6))
                    .frame(width: 22, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous prompt")
            
            // Prompt text (tappable) - gets more space now
            Button(action: { if !isHidden { onTapAskAI() } }) {
                Text(isHidden ? "•••••" : currentPrompt)
                    .font(.footnote)
                    .foregroundStyle(DS.Adaptive.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            
            // Navigation chevron right - compact, flush to edge
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(goldTextColor.opacity(0.6))
                    .frame(width: 26, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next prompt")
            .padding(.trailing, 2)
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isDark
                        ? Color.white.opacity(0.05)
                        : Color.black.opacity(0.04)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [goldTextColor.opacity(0.25), DS.Adaptive.divider.opacity(0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.4) { onNext() }
    }
}

private struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public struct InsightsHeaderRow: View {
    @Environment(\.colorScheme) private var colorScheme
    
    public var body: some View {
        let isDark = colorScheme == .dark
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LocalGold.textColor(isDark: isDark))
                    .accessibilityHidden(true)
                Text("AI Insights")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(LocalGold.textColor(isDark: isDark))
            }
            .padding(.horizontal, 0)
            Spacer(minLength: 8)
            
            NavigationLink {
                AllAIInsightsView()
            } label: {
                Text("All Insights")
            }
            .buttonStyle(CSTextLinkButtonStyle())
        }
    }
}

/*
private struct HeadlineTipCard: View {
    let headline: String
    let tip: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .lineSpacing(2)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let tipText = tip {
                Text("Tip: \(tipText)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
*/

#if DEBUG
/*
struct PremiumAIInsightsCard_Previews: PreviewProvider {
    static var previews: some View {
        // Minimal fake PortfolioViewModel to make the preview compile
        struct FakePortfolioVM: PortfolioViewModel {
            var history: [HistoryEntry] = [HistoryEntry(value: 0.05)]
            var allocationData: [AllocationEntry] = [AllocationEntry(percentage: 0.15)]
            init() {}
        }
        PremiumAIInsightsCard(
            portfolioVM: FakePortfolioVM(),
            onOpenChat: { _ in },
            prompts: ["How can I optimize my portfolio?", "What are top stocks today?", "Any risk alerts?"]
        )
        .frame(width: 350, height: 200)
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
*/
#endif

