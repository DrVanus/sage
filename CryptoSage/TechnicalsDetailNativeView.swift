import SwiftUI

private struct CGResponse: Decodable {
    struct MarketData: Decodable {
        let market_cap: [String: Double]?
        let fully_diluted_valuation: [String: Double]?
        let circulating_supply: Double?
        let total_supply: Double?
        let max_supply: Double?
    }
    let market_data: MarketData?
}

@MainActor
struct TechnicalsDetailNativeView: View {
    let symbol: String
    let tvSymbol: String
    let tvTheme: String
    let currentPrice: Double

    @EnvironmentObject private var marketVM: MarketViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedInterval: ChartInterval = .oneDay
    @StateObject private var vm = TechnicalsViewModel()

    // Fallback values (from a lightweight CoinGecko fetch) to avoid endless shimmers
    @State private var fallbackCap: Double? = nil
    @State private var fallbackFDV: Double? = nil
    @State private var fallbackCirc: Double? = nil
    @State private var fallbackMax: Double? = nil
    @State private var lastFallbackFetchAt: Date = .distantPast
    @State private var isFetchingFallback: Bool = false
    @State private var didInitialLoad: Bool = false

    // Keep intervals simple and supported by our data fetcher
    private let intervals: [ChartInterval] = [.oneHour, .fourHour, .oneDay, .oneWeek, .oneMonth]

    private var freshCoin: MarketCoin? {
        let up = symbol.uppercased()
        return marketVM.allCoins.first { $0.symbol.uppercased() == up }
    }

    private var displayedMarketCap: Double? {
        guard let c = freshCoin else { return nil }
        if let cap = c.effectiveMarketCap(usingPrice: displayedPrice) { return cap }
        if let f = fallbackCap, f.isFinite, f > 0 { return f }
        return nil
    }

    private var displayedVolume24h: Double? {
        guard let c = freshCoin else { return nil }
        return LivePriceManager.shared.bestVolumeUSD(for: c) ?? c.volumeUsd24Hr
    }

    private var displayedMaxSupply: Double? {
        guard let c = freshCoin else { return nil }
        if let ms = c.maxSupply, ms.isFinite, ms > 0 { return ms }
        if let total = c.totalSupply, total.isFinite, total > 0 { return total }
        if let circ = c.circulatingSupply, circ.isFinite, circ > 0 { return circ }
        if let lm = LivePriceManager.shared.bestMaxSupply(for: c), lm.isFinite, lm > 0 { return lm }
        return fallbackMax
    }

    private var displayedCirculatingSupply: Double? {
        guard let c = freshCoin else { return nil }
        // Prefer provider circ supply; else derive from market cap and price
        if let eff = c.effectiveCirculatingSupply(usingPrice: displayedPrice, usingMarketCap: displayedMarketCap) { return eff }
        // Fall back to total or max supply if available
        if let total = c.totalSupply, total.isFinite, total > 0 { return total }
        if let maxS = c.maxSupply, maxS.isFinite, maxS > 0 { return maxS }
        if let f = fallbackCirc, f.isFinite, f > 0 { return f }
        return nil
    }

    private var displayedFDV: Double? {
        guard let c = freshCoin else { return nil }
        if let fdv = c.effectiveFDV(usingPrice: displayedPrice) { return fdv }
        if let f = fallbackFDV, f.isFinite, f > 0 { return f }
        return nil
    }

    private var displayedPrice: Double {
        if let c = freshCoin {
            if let best = c.bestDisplayPrice(live: marketVM.bestPrice(for: c.id)) { return best }
        }
        return currentPrice
    }

    private var rawChange24h: Double? {
        guard let coin = freshCoin else { return nil }
        return LivePriceManager.shared.bestChange24hPercent(for: coin) ?? coin.unified24hPercent ?? coin.changePercent24Hr
    }

    private var displayedChange24hPercent: Double? { return rawChange24h }

    private var priceText: String {
        formatPrice(displayedPrice)
    }

    private func formatPrice(_ value: Double) -> String {
        return MarketFormat.price(value)
    }

    private func formatLargeNumber(_ value: Double) -> String {
        return MarketFormat.largeNumber(value)
    }

    @ViewBuilder
    private func changeChip(_ percent: Double?) -> some View {
        if let val = percent {
            ChangeChipContent(value: val)
        } else {
            EmptyView()
        }
    }

    private func onSelectInterval(_ intv: ChartInterval) {
        withAnimation(.easeInOut(duration: 0.2)) { selectedInterval = intv }
        vm.refresh(symbol: symbol, interval: intv, currentPrice: displayedPrice, sparkline: freshCoin?.sparklineIn7d)
    }
    
    private func onSelectSource(_ pref: TechnicalsViewModel.TechnicalsSourcePreference) {
        #if DEBUG
        print("[TechnicalsDetailNativeView] onSelectSource called with: \(pref), symbol: \(symbol), interval: \(selectedInterval)")
        #endif
        // Use the setter method which triggers @Published update for proper SwiftUI reactivity
        vm.setPreferredSource(pref)
        vm.refresh(symbol: symbol, interval: selectedInterval, currentPrice: displayedPrice, sparkline: freshCoin?.sparklineIn7d, forceBypassCache: true)
    }

    // Best-effort mapping from common symbols to CoinGecko IDs
    private func coingeckoID(for symbol: String) -> String {
        switch symbol.uppercased() {
        case "BTC": return "bitcoin"
        case "ETH": return "ethereum"
        case "SOL": return "solana"
        case "XRP": return "ripple"
        case "DOGE": return "dogecoin"
        case "ADA": return "cardano"
        case "BNB": return "binancecoin"
        case "LTC": return "litecoin"
        case "AVAX": return "avalanche-2"
        case "DOT": return "polkadot"
        case "LINK": return "chainlink"
        case "MATIC": return "matic-network" // legacy id still served
        case "USDT": return "tether"
        case "USDC": return "usd-coin"
        default:
            // Fallback guess: try the MarketCoin id if it looks like a slug, else lowercase symbol
            if let id = freshCoin?.id, id.contains("-") || id == id.lowercased() { return id }
            return symbol.lowercased()
        }
    }

    // Lightweight one-shot fetch to backfill missing stats so UI never shimmers indefinitely
    private func fetchFallbackStatsIfNeeded() {
        guard !isFetchingFallback else { return }
        // Only fetch if something important is missing
        let needCap = (displayedMarketCap ?? 0) <= 0
        let needMax = (displayedMaxSupply ?? 0) <= 0
        let needCirc = (displayedCirculatingSupply ?? 0) <= 0
        let needFDV = (displayedFDV ?? 0) <= 0
        guard needCap || needMax || needCirc || needFDV else { return }
        // Avoid spamming
        if Date().timeIntervalSince(lastFallbackFetchAt) < 25 { return }

        // Try a couple of reasonable ID candidates
        var candidates: [String] = []
        candidates.append(coingeckoID(for: symbol))
        if let raw = freshCoin?.id {
            let id = raw.lowercased()
            if !candidates.contains(id) { candidates.append(id) }
        }

        isFetchingFallback = true
        lastFallbackFetchAt = Date()

        Task {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 6
            config.timeoutIntervalForResource = 6
            config.waitsForConnectivity = true
            let session = URLSession(configuration: config)

            let decoder = JSONDecoder()

            var success = false
            for id in candidates where !id.isEmpty {
                guard let url = URL(string: "\(APIConfig.coingeckoBaseURL)/coins/\(id)?localization=false&tickers=false&community_data=false&developer_data=false&sparkline=false") else { continue }
                do {
                    let req = APIConfig.coinGeckoRequest(url: url)
                    let (data, _) = try await session.data(for: req)
                    let decoded = try decoder.decode(CGResponse.self, from: data)
                    if let md = decoded.market_data {
                        // FIX: Removed unnecessary DispatchQueue.main.async inside MainActor.run
                        // MainActor.run already guarantees main thread execution
                        await MainActor.run {
                            if let usdCap = md.market_cap?["usd"], usdCap.isFinite, usdCap > 0 { self.fallbackCap = usdCap }
                            if let usdFDV = md.fully_diluted_valuation?["usd"], usdFDV.isFinite, usdFDV > 0 { self.fallbackFDV = usdFDV }
                            if let circ = md.circulating_supply, circ.isFinite, circ > 0 { self.fallbackCirc = circ }
                            // Prefer max_supply, else total_supply as a practical upper bound
                            if let mx = md.max_supply, mx.isFinite, mx > 0 { self.fallbackMax = mx }
                            else if let tot = md.total_supply, tot.isFinite, tot > 0 { self.fallbackMax = tot }
                        }
                        success = true
                        break
                    }
                } catch {
                    // try next candidate
                }
            }
            await MainActor.run { self.isFetchingFallback = false }
            if !success {
                // No-op; UI will continue to rely on provider/derived values and retry later due to throttle window
            }
        }
    }

    @State private var cardsAppeared = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header row: price + change + TradingView link + inline timeframe chips
                HeaderRow(priceText: priceText, changePercent: displayedChange24hPercent, intervals: intervals, selected: $selectedInterval, onTap: onSelectInterval)
                    .modifier(CardAppearanceModifier(appeared: cardsAppeared, delay: 0))

                // Gauge card with QuickSignalsRow inside
                GaugeCard(
                    summary: vm.summary,
                    timeframe: selectedInterval.rawValue,
                    source: vm.sourceLabel,
                    preferredSource: vm.preferredSource,
                    requestedSource: vm.requestedSource,
                    isSwitchingSource: vm.isSourceSwitchInFlight,
                    onSelectSource: onSelectSource
                )
                .modifier(CardAppearanceModifier(appeared: cardsAppeared, delay: 0.05))
                
                // CryptoSage-exclusive insights card (only shown when we have actual CryptoSage data)
                if vm.summary.source == "cryptosage" && vm.summary.aiSummary != nil {
                    CryptoSageInsightsCard(summary: vm.summary)
                        .modifier(CardAppearanceModifier(appeared: cardsAppeared, delay: 0.07))
                }
                
                SubSummariesCard(maSell: vm.summary.maSell, maNeutral: vm.summary.maNeutral, maBuy: vm.summary.maBuy, oscSell: vm.summary.oscSell, oscNeutral: vm.summary.oscNeutral, oscBuy: vm.summary.oscBuy)
                    .modifier(CardAppearanceModifier(appeared: cardsAppeared, delay: 0.1))
                
                KeyStatsCard(marketCap: displayedMarketCap, fdv: displayedFDV, circSupply: displayedCirculatingSupply, maxSupply: displayedMaxSupply, volume24h: displayedVolume24h)
                    .modifier(CardAppearanceModifier(appeared: cardsAppeared, delay: 0.15))

                ConsensusCard(sell: vm.summary.sellCount, neutral: vm.summary.neutralCount, buy: vm.summary.buyCount)
                    .modifier(CardAppearanceModifier(appeared: cardsAppeared, delay: 0.2))
                
                BreakdownCard(summary: vm.summary)
                    .modifier(CardAppearanceModifier(appeared: cardsAppeared, delay: 0.25))

                IndicatorsCard(summary: vm.summary)
                    .modifier(CardAppearanceModifier(appeared: cardsAppeared, delay: 0.3))

                if let err = vm.errorMessage {
                    ErrorMessageButton(message: err) {
                        vm.retry(symbol: symbol, interval: selectedInterval, currentPrice: displayedPrice, sparkline: freshCoin?.sparklineIn7d, forceBypassCache: true)
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 12)
            }
            .padding(16)
        }
        .withUIKitScrollBridge() // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.4)) {
                    cardsAppeared = true
                }
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationTitle("Technicals")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { TechnicalsToolbar(onBack: { dismiss() }, tvSymbol: tvSymbol, tvTheme: tvTheme) }
        .tint(.yellow)
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .toolbarBackground(DS.Adaptive.background.opacity(0.95), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        //.toolbar { ... } <-- REMOVED toolbar with Done button

        .refreshable {
            vm.refresh(symbol: symbol, interval: selectedInterval, currentPrice: displayedPrice, sparkline: freshCoin?.sparklineIn7d)
            fetchFallbackStatsIfNeeded()
        }
        // FIX: Consolidated refresh triggers to prevent duplicate refreshes.
        // Previously both .onAppear AND .task(id:) fired on initial load, causing double API calls.
        // Now .task(id:) is the single source of truth:
        //   - Fires on appear (initial load)
        //   - Fires when freshCoin?.id changes (e.g., MarketViewModel resolves the coin)
        .task(id: freshCoin?.id) {
            if !didInitialLoad {
                didInitialLoad = true
                if marketVM.allCoins.isEmpty || freshCoin == nil || (freshCoin?.marketCap ?? 0) <= 0 {
                    await marketVM.loadAllData()
                }
            }
            vm.refresh(symbol: symbol, interval: selectedInterval, currentPrice: displayedPrice, sparkline: freshCoin?.sparklineIn7d)
            fetchFallbackStatsIfNeeded()
        }
        .onReceive(marketVM.objectWillChange) { _ in
            DispatchQueue.main.async {
                fetchFallbackStatsIfNeeded()
            }
        }
#if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            vm.refresh(symbol: symbol, interval: selectedInterval, currentPrice: displayedPrice, sparkline: freshCoin?.sparklineIn7d)
            fetchFallbackStatsIfNeeded()
        }
#endif
    }
}

extension TechnicalsDetailNativeView {
    private func verdictFor(score: Double) -> TechnicalVerdict {
        switch score {
        case ..<0.15: return .strongSell
        case ..<0.35: return .sell
        case ..<0.65: return .neutral
        case ..<0.85: return .buy
        default:       return .strongBuy
        }
    }

    private func scoreFromCounts(sell: Int, neutral: Int, buy: Int) -> Double {
        let total = max(1, sell + neutral + buy)
        let score = (Double(buy) + 0.5 * Double(neutral)) / Double(total)
        return max(0, min(1, score))
    }

    private func countPill(title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            Text("\(value)")
                .font(.footnote.weight(.bold))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Capsule().fill(DS.Adaptive.cardBackground))
        .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 1))
    }
}

// MARK: - Card Appearance Animation
private struct CardAppearanceModifier: ViewModifier {
    let appeared: Bool
    let delay: Double
    
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.8)
                .delay(delay),
                value: appeared
            )
    }
}

// MARK: - Professional Card Style
private struct TechnicalsCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base gradient background
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                    
                    // Subtle inner highlight at top
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    DS.Adaptive.overlay(0.04),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
    }
}

private struct ConsensusCard: View {
    let sell: Int
    let neutral: Int
    let buy: Int
    
    private var total: Int { sell + neutral + buy }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Consensus")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            // Full-width pill row with equal distribution
            HStack(spacing: 8) {
                ConsensusPill(title: "Sell", value: sell, total: total, color: .red)
                ConsensusPill(title: "Neutral", value: neutral, total: total, color: .yellow)
                ConsensusPill(title: "Buy", value: buy, total: total, color: .green)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TechnicalsCardStyle())
    }
}

private struct ConsensusPill: View {
    let title: String
    let value: Int
    let total: Int
    let color: Color
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                Text("\(value)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)
                    .monospacedDigit()
            }
            
            // Progress bar showing proportion
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(DS.Adaptive.overlay(0.08))
                    
                    // Filled portion
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color.opacity(0.7))
                        .frame(width: geo.size.width * percentage)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.overlay(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 0.8)
        )
    }
}

private struct BreakdownCard: View {
    let summary: TechnicalsSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Breakdown")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Text("Moving Averages")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    Pill(title: "Sell", value: summary.maSell, color: .red)
                    Pill(title: "Neutral", value: summary.maNeutral, color: .yellow)
                    Pill(title: "Buy", value: summary.maBuy, color: .green)
                }
                HStack(spacing: 10) {
                    Text("Oscillators")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    Pill(title: "Sell", value: summary.oscSell, color: .red)
                    Pill(title: "Neutral", value: summary.oscNeutral, color: .yellow)
                    Pill(title: "Buy", value: summary.oscBuy, color: .green)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .modifier(TechnicalsCardStyle())
    }

    private struct Pill: View {
        let title: String
        let value: Int
        let color: Color
        var body: some View {
            HStack(spacing: 6) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text("\(value)")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(color)
                    .monospacedDigit()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Capsule().fill(DS.Adaptive.cardBackground))
            .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 1))
        }
    }
}

private struct IndicatorsCard: View {
    let summary: TechnicalsSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Indicators")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            TechnicalsIndicatorListView(indicators: summary.indicators)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .modifier(TechnicalsCardStyle())
    }
}

private struct ErrorMessageButton: View {
    let message: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                Text(message)
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.red)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Capsule().fill(Color.red.opacity(0.08)))
            .overlay(Capsule().stroke(Color.red.opacity(0.25), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

private struct KeyStatsCard: View {
    let marketCap: Double?
    let fdv: Double?
    let circSupply: Double?
    let maxSupply: Double?
    let volume24h: Double?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                Text("Key Stats")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            VStack(spacing: 0) {
                EnhancedStatRow(
                    title: "Market Cap",
                    value: marketCap,
                    icon: "dollarsign.circle",
                    accentColor: .green
                )
                
                Divider()
                    .background(DS.Adaptive.divider)
                
                EnhancedStatRow(
                    title: "FDV",
                    value: fdv,
                    icon: "chart.pie",
                    accentColor: .blue
                )
                
                Divider()
                    .background(DS.Adaptive.divider)
                
                EnhancedStatRow(
                    title: "Circ. Supply",
                    value: circSupply,
                    icon: "arrow.triangle.2.circlepath",
                    accentColor: .orange
                )
                
                Divider()
                    .background(DS.Adaptive.divider)
                
                EnhancedStatRow(
                    title: "Max Supply",
                    value: maxSupply,
                    icon: "cube.box",
                    accentColor: .purple
                )
                
                Divider()
                    .background(DS.Adaptive.divider)
                
                EnhancedStatRow(
                    title: "Volume (24h)",
                    value: volume24h,
                    icon: "waveform.path.ecg",
                    accentColor: .cyan
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.Adaptive.overlay(0.02))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .modifier(TechnicalsCardStyle())
    }
}

private struct EnhancedStatRow: View {
    let title: String
    let value: Double?
    let icon: String
    let accentColor: Color
    
    @State private var appeared = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(accentColor.opacity(0.8))
                .frame(width: 18)
            
            // Title
            Text(title)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Spacer()
            
            // Value
            if let v = value, v > 0 {
                Text(MarketFormat.largeNumber(v))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .contentTransition(.numericText())
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : 10)
                    .animation(.easeOut(duration: 0.3), value: appeared)
            } else {
                EnhancedShimmerBar()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appeared = true
            }
        }
    }
}

private struct EnhancedShimmerBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmerOffset: CGFloat = -100
    
    var body: some View {
        let baseColor = colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
        let shimmerColor = colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)
        
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(baseColor)
            .frame(width: 64, height: 14)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.clear,
                            shimmerColor,
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 40)
                    .offset(x: shimmerOffset)
                    .onAppear {
                        // Defer to avoid "Modifying state during view update"
                        DispatchQueue.main.async {
                            withAnimation(
                                .linear(duration: 1.2)
                                .repeatForever(autoreverses: false)
                            ) {
                                shimmerOffset = geo.size.width + 40
                            }
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct ChangeChipContent: View {
    let value: Double
    var body: some View {
        // FIX: Defensive clamp to ±300% to prevent absurd displays
        let clampedValue = max(-300, min(300, value))
        let f = PercentDisplay.formatFraction(clampedValue / 100.0)
        let changeColor: Color
        switch f.trend {
        case .positive: changeColor = .green
        case .negative: changeColor = .red
        case .neutral:  changeColor = DS.Adaptive.textSecondary
        }
        return HStack(spacing: 4) {
            Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
            Text(f.text).monospacedDigit()
        }
        .font(.caption2.weight(.bold))
        .foregroundColor(changeColor)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Capsule().fill(DS.Adaptive.cardBackground))
        .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.8))
        .accessibilityLabel("24 hour change")
        .accessibilityValue(f.accessibility)
    }
}

private struct TimeframeChipsRow: View {
    let intervals: [ChartInterval]
    @Binding var selected: ChartInterval
    let onTap: (ChartInterval) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(intervals, id: \.self) { intv in
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onTap(intv)
                    } label: {
                        Text(intv.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundColor(selected == intv ? (isDark ? .black : .white) : DS.Adaptive.textPrimary)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(
                                Capsule().fill(selected == intv ? (isDark ? Color.white : Color.black) : DS.Adaptive.cardBackground)
                            )
                            .overlay(
                                Capsule().stroke(DS.Adaptive.stroke, lineWidth: 1)
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.trailing, 16)
        }
        .scrollClipDisabled()
    }
}

private struct SubSummaryMiniGauge: View {
    let label: String
    let summary: TechnicalsSummary
    var lineWidth: CGFloat = 8

    init(label: String, sell: Int, neutral: Int, buy: Int, lineWidth: CGFloat = 8) {
        self.label = label
        self.lineWidth = lineWidth
        let total = sell + neutral + buy
        // FIX: When all counts are zero (loading/no data), show neutral instead of Strong Sell
        if total == 0 {
            self.summary = TechnicalsSummary(score01: 0.5, verdict: .neutral)
        } else {
            let score = (Double(buy) + 0.5 * Double(neutral)) / Double(max(1, total))
            let verdict: TechnicalVerdict
            switch score {
            case ..<0.15: verdict = .strongSell
            case ..<0.35: verdict = .sell
            case ..<0.65: verdict = .neutral
            case ..<0.85: verdict = .buy
            default:       verdict = .strongBuy
            }
            self.summary = TechnicalsSummary(
                score01: score,
                verdict: verdict,
                sellCount: sell,
                neutralCount: neutral,
                buyCount: buy
            )
        }
    }

    var body: some View {
        let headlineText: String
        let headlineColor: Color
        switch summary.verdict {
        case .strongSell:
            headlineText = "Strong Sell"; headlineColor = .red
        case .sell:
            headlineText = "Sell"; headlineColor = .red
        case .neutral:
            headlineText = "Neutral"; headlineColor = .yellow
        case .buy:
            headlineText = "Buy"; headlineColor = .green
        case .strongBuy:
            headlineText = "Strong Buy"; headlineColor = .green
        }

        let badgeText: String
        let badgeColor: Color
        switch summary.verdict {
        case .strongSell, .sell:
            badgeText = "Sell"; badgeColor = .red
        case .neutral:
            badgeText = "Neutral"; badgeColor = .yellow
        case .buy, .strongBuy:
            badgeText = "Buy"; badgeColor = .green
        }

        return VStack(spacing: 2) {
            ZStack {
                TechnicalsGaugeView(summary: summary, timeframeLabel: "", lineWidth: lineWidth, preferredHeight: 105, showArcLabels: false, showEndCaps: false, showVerdictLine: false)
                
                // Add compact tick marks and labels overlay for mini gauges
                CompactArcLabelsOverlay(lineWidth: lineWidth)
            }
            .frame(maxWidth: .infinity, minHeight: 105, alignment: .top)
            .padding(.horizontal, 4)
            Text(headlineText)
                .font(.subheadline.weight(.bold))
                .fontWidth(.condensed)
                .foregroundColor(headlineColor)
                .padding(.top, 2)
            HStack(spacing: 5) {
                Text(label)
                    .font(.caption2)
                    .fontWidth(.condensed)
                    .foregroundColor(DS.Adaptive.textSecondary)
                Text(badgeText)
                    .font(.caption2.weight(.bold))
                    .fontWidth(.condensed)
                    .foregroundColor(badgeColor)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 7)
                    .background(DS.Adaptive.cardBackground)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.6))
            }
        }
    }
}

// Compact arc labels overlay for mini gauges - shows tick marks and minimal labels
// Only shows "Sell" and "Buy" to avoid overlap when gauges are side by side
private struct CompactArcLabelsOverlay: View {
    let lineWidth: CGFloat
    
    // Convert a 0-100 value to a point on the arc
    private func arcPoint(center: CGPoint, radius: CGFloat, value: Double) -> CGPoint {
        let degrees = 180.0 - (value / 100.0) * 180.0
        let radians = CGFloat(degrees) * .pi / 180.0
        return CGPoint(
            x: center.x + CoreGraphics.cos(radians) * radius,
            y: center.y - CoreGraphics.sin(radians) * radius
        )
    }
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            // Calculate gauge geometry (matching ImprovedHalfCircleGauge)
            let arcRadius = (min(w, h * 2) / 2 - lineWidth / 2) * 0.87
            let centerLift = lineWidth * 1.28 + 10
            let center = CGPoint(x: w / 2, y: h - centerLift)
            
            // Tick mark radii
            let tickOuterRadius = arcRadius + lineWidth * 0.5
            let tickInnerRadius = arcRadius - lineWidth * 0.3
            
            // Label radius - position labels outside the arc
            let labelRadius = arcRadius + lineWidth * 1.0 + 8
            
            // Main tick marks at zone boundaries (matching main gauge: 0, 20, 40, 60, 80, 100)
            let majorTickPositions: [Double] = [0, 20, 40, 60, 80, 100]
            
            ZStack {
                // Draw zone boundary tick marks
                ForEach(majorTickPositions, id: \.self) { pos in
                    let outerPt = arcPoint(center: center, radius: tickOuterRadius, value: pos)
                    let innerPt = arcPoint(center: center, radius: tickInnerRadius, value: pos)
                    
                    Path { path in
                        path.move(to: outerPt)
                        path.addLine(to: innerPt)
                    }
                    .stroke(DS.Adaptive.textTertiary.opacity(0.5), lineWidth: 1.0)
                }
                
                // Minimal labels for compact gauges - only Sell and Buy
                // Positioned at 20 and 80 (zone boundaries) to stay within gauge bounds
                // This prevents overlap when two gauges are side by side
                
                // "Sell" label at position 20 (left side, within gauge bounds)
                let sellPt = arcPoint(center: center, radius: labelRadius, value: 18)
                Text("Sell")
                    .font(.system(size: 8, weight: .semibold))
                    .fontWidth(.condensed)
                    .foregroundColor(.red.opacity(0.75))
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: sellPt.x, y: sellPt.y)
                
                // "Buy" label at position 80 (right side, within gauge bounds)
                let buyPt = arcPoint(center: center, radius: labelRadius, value: 82)
                Text("Buy")
                    .font(.system(size: 8, weight: .semibold))
                    .fontWidth(.condensed)
                    .foregroundColor(.green.opacity(0.75))
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: buyPt.x, y: buyPt.y)
            }
            .allowsHitTesting(false)
        }
    }
}

private struct GaugeCard: View {
    let summary: TechnicalsSummary
    let timeframe: String
    let source: String
    let preferredSource: TechnicalsViewModel.TechnicalsSourcePreference
    let requestedSource: TechnicalsViewModel.TechnicalsSourcePreference
    let isSwitchingSource: Bool
    let onSelectSource: (TechnicalsViewModel.TechnicalsSourcePreference) -> Void

    private func displaySourceLabel(_ source: String) -> String {
        let lower = source.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Hide explicit 'no data' or empty
        if lower.contains("no data") || lower.isEmpty { return "" }
        
        var base: String = source
        let isStale = lower.contains("stale")
        
        // Map source names - check CryptoSage/Firebase first (most specific)
        if lower.contains("cryptosage") || lower.contains("firebase") {
            base = "CryptoSage"
        } else if lower.contains("coinbase") {
            base = "Coinbase"
        } else if lower.contains("binance") {
            base = "Binance"
        } else if lower.contains("coingecko") {
            base = "CoinGecko"
        } else if lower.contains("loading") {
            // Actually still loading - keep it
            base = "Loading..."
        } else if lower.contains("cache") || lower.contains("memory") || lower.contains("mem") || lower.contains("sparkline") || lower.contains("auto") || lower.contains("on-device") || lower.contains("on device") || lower.contains("derived") || lower.contains("local") || lower.contains("offline") || lower.contains("cash") {
            // Local/cached data
            base = "CryptoSage"
        }
        
        // Strip explicit ' • fallback' noise
        if let range = base.range(of: "• fallback", options: [.caseInsensitive]) {
            base.removeSubrange(range)
            base = base.trimmingCharacters(in: .whitespaces)
        }
        
        // Preserve stale suffix if present on original
        if isStale && !base.lowercased().contains("stale") && base != "Loading..." {
            base += " • stale"
        }
        return base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickSignalsRow(summary: summary)
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            TechnicalsGaugeView(summary: summary, timeframeLabel: timeframe, showArcLabels: true)
                .padding(.top, 4)
                .frame(maxWidth: .infinity)
            let display = displaySourceLabel(source)
            if !display.isEmpty {
                HStack {
                    Spacer()
                    TechnicalsSourceMenu(
                        sourceLabel: source,
                        preferred: preferredSource,
                        requestedSource: requestedSource,
                        isSwitchingSource: isSwitchingSource,
                        onSelect: onSelectSource
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .modifier(TechnicalsCardStyle())
        .transaction { txn in txn.animation = nil }
    }
}

private struct TechnicalsToolbar: ToolbarContent {
    let onBack: () -> Void
    let tvSymbol: String
    let tvTheme: String
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            CSNavButton(
                icon: "chevron.left",
                action: onBack,
                compact: true
            )
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                TechnicalsDetailView(symbol: tvSymbol, theme: tvTheme)
            } label: {
                TradingViewCTACompact()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See in TradingView")
        }
    }
}

private struct InfoButton: View {
    let title: String
    let message: String
    @State private var show = false
    var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            show = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundColor(DS.Adaptive.textSecondary)
        }
        .popover(isPresented: $show) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(message).font(.footnote).foregroundColor(.secondary)
            }
            .padding()
        }
    }
}

private struct TradingViewCTACompact: View {
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        Text("See in TradingView")
            .font(.footnote.weight(.semibold))
            .foregroundColor(.black)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                LinearGradient(
                    colors: isDark 
                        ? [Color.white.opacity(0.96), Color.white.opacity(0.88)]
                        : [Color.white, Color(red: 0.97, green: 0.97, blue: 0.98)],
                    startPoint: .topLeading, 
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    isDark ? Color.white.opacity(0.25) : Color.black.opacity(0.12), 
                    lineWidth: isDark ? 0.8 : 0.5
                )
            )
            .contentShape(Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.95)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(0)
    }
}

private struct DonePillButton: View {
    let action: () -> Void
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let title = "Done"
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.vertical, 8)
                .padding(.horizontal, sizeCategory.isAccessibilityCategory ? 12 : 10)
                .background(
                    Capsule().fill(DS.Adaptive.cardBackground)
                )
                .overlay(
                    Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.8)
                )
                .contentShape(Capsule())
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .buttonStyle(.plain)
    }
}

private struct LiveStatusDot: View {
    let lastUpdated: Date?
    var onTap: (() -> Void)? = nil

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    statusContent
                }
                .buttonStyle(.plain)
            } else {
                statusContent
            }
        }
    }

    private var statusContent: some View {
        let isLive = (lastUpdated != nil && Date().timeIntervalSince(lastUpdated!) < 60)
        return HStack(spacing: 6) {
            Circle()
                .fill(isLive ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(isLive ? "Live" : "Stale")
                .font(.caption2.weight(.semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DS.Adaptive.cardBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Data status")
        .accessibilityValue(isLive ? "Live" : "Stale")
    }
}

private struct QuickSignalsRow: View {
    let summary: TechnicalsSummary
    
    // Check if we have real data loaded (not just defaults)
    private var hasRealData: Bool {
        let totalCounts = summary.sellCount + summary.neutralCount + summary.buyCount
        return totalCounts > 0
    }
    
    private func textColor(for verdict: TechnicalVerdict) -> (String, Color) {
        switch verdict {
        case .strongSell: return ("Strong Sell", .red)
        case .sell: return ("Sell", .red)
        case .neutral: return ("Neutral", .yellow)
        case .buy: return ("Buy", .green)
        case .strongBuy: return ("Strong Buy", .green)
        }
    }
    var body: some View {
        let (overallText, overallColor) = textColor(for: summary.verdict)

        // Precompute MA verdict
        let maDenom = Double(max(1, summary.maSell + summary.maNeutral + summary.maBuy))
        let maScore = (Double(summary.maBuy) + 0.5 * Double(summary.maNeutral)) / maDenom
        let maVerdict: TechnicalVerdict = {
            switch maScore {
            case ..<0.15: return .strongSell
            case ..<0.35: return .sell
            case ..<0.65: return .neutral
            case ..<0.85: return .buy
            default:       return .strongBuy
            }
        }()
        let (maText, maColor) = textColor(for: maVerdict)

        // Precompute Oscillators verdict
        let oscDenom = Double(max(1, summary.oscSell + summary.oscNeutral + summary.oscBuy))
        let oscScore = (Double(summary.oscBuy) + 0.5 * Double(summary.oscNeutral)) / oscDenom
        let oscVerdict: TechnicalVerdict = {
            switch oscScore {
            case ..<0.15: return .strongSell
            case ..<0.35: return .sell
            case ..<0.65: return .neutral
            case ..<0.85: return .buy
            default:       return .strongBuy
            }
        }()
        let (oscText, oscColor) = textColor(for: oscVerdict)

        // Always show the computed values - use opacity to smoothly reveal
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TechVerdictPill(title: "Overall", value: overallText, color: overallColor)
                TechVerdictPill(title: "MAs", value: maText, color: maColor)
                TechVerdictPill(title: "Osc", value: oscText, color: oscColor)
            }
            .padding(.horizontal, 2)
        }
        // Use opacity fade-in instead of changing content/id
        .opacity(hasRealData ? 1 : 0.3)
        .animation(.easeOut(duration: 0.2), value: hasRealData)
        .scrollClipDisabled()
        // Suppress any animations on the content itself during initial load
        .transaction { txn in
            if !hasRealData { txn.animation = nil }
        }
    }
}

private struct TechVerdictPill: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .fontWidth(.condensed)
                .foregroundColor(DS.Adaptive.textSecondary)
            Text(value)
                .font(.caption2.weight(.bold))
                .fontWidth(.condensed)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(DS.Adaptive.cardBackground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 0.6))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.Adaptive.overlay(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(DS.Adaptive.stroke.opacity(0.8), lineWidth: 1))
    }
}

private struct HeaderRow: View {
    let priceText: String
    let changePercent: Double?
    let intervals: [ChartInterval]
    @Binding var selected: ChartInterval
    let onTap: (ChartInterval) -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(priceText)
                    .monospacedDigit()
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Adaptive.cardBackground))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DS.Adaptive.stroke, lineWidth: 0.8))
                    .contentTransition(.numericText())
                if let cp = changePercent {
                    ChangeChipContent(value: cp)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            // Inline timeframe chips to the right of price
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(intervals, id: \.self) { intv in
                        TimeframeChipButton(
                            interval: intv,
                            isSelected: selected == intv,
                            onTap: { onTap(intv) }
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
                .padding(.trailing, 16)
            }
            .frame(height: 28)
            .scrollClipDisabled()
        }
    }
}

// MARK: - Animated Timeframe Chip
private struct TimeframeChipButton: View {
    let interval: ChartInterval
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isPressed = false
    
    var body: some View {
        let isDark = colorScheme == .dark
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onTap()
        } label: {
            Text(interval.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundColor(isSelected ? (isDark ? .black : .white) : DS.Adaptive.textPrimary)
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    Capsule().fill(isSelected ? (isDark ? Color.white : Color.black) : DS.Adaptive.cardBackground)
                )
                .overlay(
                    Capsule().stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
                .contentShape(Capsule())
                .scaleEffect(isPressed ? 0.92 : 1.0)
                .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
}
// MARK: - CryptoSage-Exclusive Insights Card
/// Shows advanced analysis features only available with CryptoSage source
/// Includes AI summary, divergence detection, trend strength, and confidence
private struct CryptoSageInsightsCard: View {
    let summary: TechnicalsSummary
    
    /// Check if we have any meaningful CryptoSage-exclusive data to display
    private var hasContent: Bool {
        summary.aiSummary != nil ||
        summary.confidence != nil ||
        summary.trendStrength != nil ||
        summary.volatilityRegime != nil ||
        (summary.divergence != nil && summary.divergence != "none") ||
        summary.supertrendDirection != nil ||
        summary.parabolicSarTrend != nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with badge
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                Text("CryptoSage Analysis")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                // Confidence badge
                if let conf = summary.confidence {
                    Text("\(conf)%")
                        .font(.caption.weight(.bold))
                        .foregroundColor(conf >= 70 ? .green : (conf >= 50 ? .yellow : .red))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill((conf >= 70 ? Color.green : (conf >= 50 ? Color.yellow : Color.red)).opacity(0.15))
                        )
                }
            }
            
            if hasContent {
                // AI Summary (if available)
                if let aiSummary = summary.aiSummary, !aiSummary.isEmpty {
                    Text(aiSummary)
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Advanced indicators grid
                let showTrendRow = summary.trendStrength != nil || summary.volatilityRegime != nil || (summary.divergence != nil && summary.divergence != "none")
                
                if showTrendRow {
                    HStack(spacing: 12) {
                        // Trend Strength
                        if let trend = summary.trendStrength {
                            InsightPill(
                                icon: "arrow.up.right",
                                label: "Trend",
                                value: trend,
                                color: trendColor(trend)
                            )
                        }
                        
                        // Volatility
                        if let vol = summary.volatilityRegime {
                            InsightPill(
                                icon: "waveform.path.ecg",
                                label: "Volatility",
                                value: vol,
                                color: volatilityColor(vol)
                            )
                        }
                        
                        // Divergence (if detected)
                        if let div = summary.divergence, div != "none" {
                            InsightPill(
                                icon: div == "bullish" ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                                label: "Divergence",
                                value: div.capitalized,
                                color: div == "bullish" ? .green : .red
                            )
                        }
                    }
                }
                
                // Supertrend and SAR indicators
                if summary.supertrendDirection != nil || summary.parabolicSarTrend != nil {
                    HStack(spacing: 12) {
                        if let st = summary.supertrendDirection {
                            InsightPill(
                                icon: st == "bullish" ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                                label: "Supertrend",
                                value: st.capitalized,
                                color: st == "bullish" ? .green : .red
                            )
                        }
                        
                        if let sar = summary.parabolicSarTrend {
                            InsightPill(
                                icon: "point.3.connected.trianglepath.dotted",
                                label: "Parabolic SAR",
                                value: sar.capitalized,
                                color: sar == "bullish" ? .green : .red
                            )
                        }
                    }
                }
            } else {
                // No CryptoSage data available - show loading or unavailable message
                Text("Advanced analysis loading...")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .italic()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .modifier(TechnicalsCardStyle())
    }
    
    private func trendColor(_ trend: String) -> Color {
        switch trend.lowercased() {
        case "very strong", "strong": return .green
        case "moderate": return .yellow
        case "weak", "ranging": return .gray
        default: return DS.Adaptive.textSecondary
        }
    }
    
    private func volatilityColor(_ vol: String) -> Color {
        switch vol.lowercased() {
        case "extreme": return .red
        case "high": return .orange
        case "normal": return .yellow
        case "low": return .green
        default: return DS.Adaptive.textSecondary
        }
    }
}

/// Compact pill for showing individual insight values
private struct InsightPill: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
}

private struct SubSummariesCard: View {
    let maSell: Int
    let maNeutral: Int
    let maBuy: Int
    let oscSell: Int
    let oscNeutral: Int
    let oscBuy: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sub-summaries")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            HStack(spacing: 8) {
                SubSummaryMiniGauge(label: "MAs", sell: maSell, neutral: maNeutral, buy: maBuy)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)

                #if os(iOS)
                if UIScreen.main.bounds.width < 380 {
                    Rectangle()
                        .fill(DS.Adaptive.divider)
                        .frame(width: 1)
                        .frame(height: 70)
                }
                #endif

                SubSummaryMiniGauge(label: "Oscillators", sell: oscSell, neutral: oscNeutral, buy: oscBuy)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .modifier(TechnicalsCardStyle())
    }
}

