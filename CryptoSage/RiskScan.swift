import SwiftUI

public enum RiskLevel: String, Codable, CaseIterable {
    case low = "Low", medium = "Medium", high = "High"
}

public struct RiskHighlight: Identifiable, Codable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let severity: RiskLevel
    
    public init(title: String, detail: String, severity: RiskLevel, id: UUID = UUID()) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
    }
}

public struct RiskMetrics: Codable {
    public var topWeight: Double
    public var hhi: Double
    public var stablecoinWeight: Double
    public var volatility: Double
    public var maxDrawdown: Double
    public var illiquidCount: Int
    
    public static let zero = RiskMetrics(topWeight: 0, hhi: 0, stablecoinWeight: 0, volatility: 0, maxDrawdown: 0, illiquidCount: 0)
}

public struct RiskScanResult: Codable {
    public let score: Int
    public let level: RiskLevel
    public let highlights: [RiskHighlight]
    public let metrics: RiskMetrics
    
    // AI-generated analysis (populated after algorithmic scan)
    public var aiRecommendations: [String]?
    public var aiAnalysis: String?
    
    public init(score: Int, level: RiskLevel, highlights: [RiskHighlight], metrics: RiskMetrics, aiRecommendations: [String]? = nil, aiAnalysis: String? = nil) {
        self.score = score
        self.level = level
        self.highlights = highlights
        self.metrics = metrics
        self.aiRecommendations = aiRecommendations
        self.aiAnalysis = aiAnalysis
    }
}

public enum RiskScanner {
    @MainActor
    static func scan(portfolioVM: PortfolioViewModel, marketVM: MarketViewModel) -> RiskScanResult {
        // Check if paper trading mode is enabled - if so, build holdings from paper balances
        let holdings: [Holding]
        let total: Double
        
        if PaperTradingManager.isEnabled {
            // Build holdings from paper trading balances
            let paperBalances = PaperTradingManager.shared.paperBalances
            let coinMap: [String: MarketCoin] = marketVM.allCoins.reduce(into: [:]) { dict, c in
                dict[c.symbol.uppercased()] = c
            }
            
            // Convert paper balances to Holding objects
            var paperHoldings: [Holding] = []
            for (symbol, quantity) in paperBalances where quantity > 0 {
                let upperSymbol = symbol.uppercased()
                // Skip quote currencies (USDT, USD, etc.) unless they have substantial value
                let isQuoteCurrency = ["USDT", "USDC", "USD", "BUSD", "DAI"].contains(upperSymbol)
                
                // Get market data for this asset
                if let coin = coinMap[upperSymbol] {
                    let price = coin.priceUsd ?? 0
                    let dailyChange = coin.dailyChange ?? 0
                    
                    // Only include if it has meaningful value (>$1)
                    if price * quantity > 1 {
                        let holding = Holding(
                            coinName: coin.name,
                            coinSymbol: upperSymbol,
                            quantity: quantity,
                            currentPrice: price,
                            costBasis: price, // Use current price as cost basis for paper trading
                            imageUrl: coin.imageUrl?.absoluteString,
                            isFavorite: false,
                            dailyChange: dailyChange,
                            purchaseDate: Date()
                        )
                        paperHoldings.append(holding)
                    }
                } else if isQuoteCurrency {
                    // Stablecoins: treat as $1 per unit
                    if quantity > 1 {
                        let holding = Holding(
                            coinName: symbol,
                            coinSymbol: upperSymbol,
                            quantity: quantity,
                            currentPrice: 1.0,
                            costBasis: 1.0,
                            imageUrl: nil,
                            isFavorite: false,
                            dailyChange: 0,
                            purchaseDate: Date()
                        )
                        paperHoldings.append(holding)
                    }
                }
            }
            
            holdings = paperHoldings
            total = holdings.reduce(0) { $0 + $1.currentValue }
        } else {
            // Use regular portfolio holdings
            holdings = portfolioVM.holdings
            total = max(0.0, portfolioVM.totalValue)
        }

        // Empty portfolio: return a friendly low-risk result
        guard total > 0, !holdings.isEmpty else {
            let emptyDetail = PaperTradingManager.isEnabled
                ? "Your paper trading portfolio is empty. Execute some trades to analyze risk."
                : "Add assets to your portfolio to analyze risk."
            return RiskScanResult(
                score: 0,
                level: .low,
                highlights: [RiskHighlight(title: "No holdings", detail: emptyDetail, severity: .low)],
                metrics: .zero
            )
        }

        // Compute weights per holding
        let weights: [Double] = holdings.map { h in
            let w = h.currentValue / max(total, 1e-9)
            return w.isFinite && w > 0 ? w : 0
        }
        let topWeight: Double = max(0, weights.max() ?? 0)
        let hhi: Double = weights.reduce(0) { $0 + $1 * $1 }

        // Stablecoin exposure
        let stableSet: Set<String> = ["USDT","USDC","BUSD","DAI","FDUSD","TUSD","USDP","GUSD","FRAX","LUSD"]
        let stablecoinWeight: Double = zip(holdings, weights).reduce(0) { acc, pair in
            let (h, w) = pair
            return acc + (stableSet.contains(h.coinSymbol.uppercased()) ? w : 0)
        }

        // Volatility proxy: weighted average absolute daily change (fraction)
        func dailyChangePercent(for h: Holding) -> Double {
            // Prefer dailyChangePercent if available; else dailyChange
            // Both expected in percent units (e.g., 5.0 == +5%)
            let mirror = Mirror(reflecting: h)
            var value: Double? = nil
            for child in mirror.children {
                if child.label == "dailyChangePercent", let v = child.value as? Double { value = v; break }
            }
            if let v = value { return v }
            // Fallback to dailyChange if present
            for child in Mirror(reflecting: h).children {
                if child.label == "dailyChange", let v = child.value as? Double { return v }
            }
            return 0
        }
        let volAbsWeightedPct: Double = zip(holdings, weights).reduce(0) { acc, pair in
            let (h, w) = pair
            let pct = dailyChangePercent(for: h)
            let frac = (pct.isFinite ? abs(pct) / 100.0 : 0)
            return acc + w * frac
        }
        let volatility = min(max(volAbsWeightedPct, 0), 1.0)

        // Max drawdown proxy from portfolio history (fraction)
        let history = portfolioVM.history
        var maxDD: Double = 0
        if history.count >= 2 {
            var peak: Double = max(1e-9, history.first?.value ?? 1)
            for p in history {
                let v = max(1e-9, p.value)
                if v > peak { peak = v }
                let dd = (peak - v) / peak
                if dd.isFinite, dd > maxDD { maxDD = dd }
            }
        }
        let maxDrawdown = min(max(maxDD, 0), 1.0)

        // Illiquidity: count of holdings where coin 24h volume is very small
        let coinMap: [String: MarketCoin] = marketVM.allCoins.reduce(into: [:]) { dict, c in
            dict[c.symbol.uppercased()] = c
        }
        let illiquidThresholdUSD: Double = 10_000_000 // $10M/day
        let illiquidCount: Int = holdings.reduce(0) { acc, h in
            let sym = h.coinSymbol.uppercased()
            if let c = coinMap[sym] {
                let vol = c.totalVolume ?? 0
                return acc + ((vol.isFinite && vol > 0 && vol < illiquidThresholdUSD) ? 1 : 0)
            }
            return acc + 1 // unknown coin: conservatively count as illiquid
        }

        // Assemble metrics
        let metrics = RiskMetrics(
            topWeight: topWeight,
            hhi: hhi,
            stablecoinWeight: stablecoinWeight,
            volatility: volatility,
            maxDrawdown: maxDrawdown,
            illiquidCount: illiquidCount
        )

        // Build highlights
        var highlights: [RiskHighlight] = []
        if topWeight >= 0.60 {
            highlights.append(RiskHighlight(title: "Concentration Risk", detail: String(format: "Top holding is %.0f%% of portfolio", topWeight * 100), severity: .high))
        } else if topWeight >= 0.40 {
            highlights.append(RiskHighlight(title: "Elevated Concentration", detail: String(format: "Top holding is %.0f%% of portfolio", topWeight * 100), severity: .medium))
        }

        if hhi >= 0.20 {
            highlights.append(RiskHighlight(title: "Low Diversification", detail: String(format: "HHI = %.2f (higher is more concentrated)", hhi), severity: .medium))
        }

        if volatility >= 0.03 { // ~3% weighted absolute daily move
            highlights.append(RiskHighlight(title: "High Daily Volatility", detail: String(format: "Weighted |24h| ≈ %.1f%%", volatility * 100), severity: .medium))
        }

        if maxDrawdown >= 0.30 {
            highlights.append(RiskHighlight(title: "Large Drawdown", detail: String(format: "Recent max drawdown ≈ %.0f%%", maxDrawdown * 100), severity: .high))
        }

        if illiquidCount > 0 {
            highlights.append(RiskHighlight(title: "Illiquid Assets", detail: "\(illiquidCount) holding(s) have low 24h volume", severity: illiquidCount >= 3 ? .high : .medium))
        }

        if stablecoinWeight >= 0.30 {
            highlights.append(RiskHighlight(title: "Defensive Allocation", detail: String(format: "Stablecoins ≈ %.0f%% of portfolio", stablecoinWeight * 100), severity: .low))
        }

        // Compute score (0..100) and level
        let illiqFactor = min(1.0, Double(illiquidCount) / max(1.0, Double(holdings.count)))
        var scoreRaw = 0.0
        scoreRaw += 40.0 * min(1.0, topWeight)        // concentration
        scoreRaw += 30.0 * min(1.0, hhi)              // diversification
        scoreRaw += 20.0 * min(1.0, volatility * 2)   // scale volatility to 0..0.5 => 0..1
        scoreRaw += 20.0 * min(1.0, maxDrawdown)      // drawdown
        scoreRaw += 15.0 * illiqFactor                // illiquidity share
        scoreRaw -= 20.0 * min(1.0, stablecoinWeight) // defensive buffer reduces risk
        let score = Int(max(0, min(100, round(scoreRaw))))

        let level: RiskLevel
        switch score {
        case ..<35: level = .low
        case 35..<70: level = .medium
        default: level = .high
        }

        return RiskScanResult(score: score, level: level, highlights: highlights, metrics: metrics)
    }
}

public struct GaugeRing: View {
    public var progress: CGFloat
    public var color: Color
    public var lineWidth: CGFloat = 3
    @State private var animatedProgress: CGFloat = 0
    
    public init(progress: CGFloat, color: Color, lineWidth: CGFloat = 3) {
        self.progress = progress
        self.color = color
        self.lineWidth = lineWidth
    }
    
    public var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, animatedProgress)))
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [color.opacity(0.6), color]), center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            withAnimation(GaugeMotionProfile.fill) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newProgress in
            withAnimation(GaugeMotionProfile.fill) {
                animatedProgress = newProgress
            }
        }
    }
}

public struct RiskRingBadge: View {
    public let level: RiskLevel
    public let score: Int
    public let progress: CGFloat
    
    public init(level: RiskLevel, score: Int, progress: CGFloat) {
        self.level = level
        self.score = score
        self.progress = progress
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            ZStack {
                GaugeRing(progress: progress, color: color, lineWidth: 3)
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text("\(level.rawValue) \(score)")
                .font(.caption.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.15)))
        .foregroundStyle(color)
    }
    
    private var color: Color {
        switch level {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
}

public struct SparkleBurstView: View {
    public var color: Color
    @State private var animate = false
    
    public init(color: Color) {
        self.color = color
    }
    
    public var body: some View {
        ZStack {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color.opacity(0.95))
                .scaleEffect(animate ? 1.6 : 0.7)
                .opacity(animate ? 0 : 1)
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color.opacity(0.8))
                .offset(x: -10, y: 6)
                .scaleEffect(animate ? 1.4 : 0.6)
                .opacity(animate ? 0 : 1)
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color.opacity(0.8))
                .offset(x: 10, y: 6)
                .scaleEffect(animate ? 1.4 : 0.6)
                .opacity(animate ? 0 : 1)
        }
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 1.0)) {
                    animate = true
                }
            }
        }
    }
}
