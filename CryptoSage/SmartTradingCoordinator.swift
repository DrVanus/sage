//
//  SmartTradingCoordinator.swift
//  CryptoSage
//
//  Smart Trading Coordinator — The ViewModel that bridges the AI Trading
//  Intelligence system to the SwiftUI UI layer.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Smart Trading Coordinator

/// Main ViewModel for the AI Trading Intelligence dashboard.
/// Orchestrates the SmartTradingEngine, DCA, and Performance systems
/// and provides reactive state to SwiftUI views.
@MainActor
public final class SmartTradingCoordinator: ObservableObject {

    // MARK: - Singleton
    public static let shared = SmartTradingCoordinator()

    // MARK: - Engine References
    private let engine = SmartTradingEngine.shared
    private let dcaEngine = SmartDCAEngine.shared
    private let performanceEngine = PerformanceAttributionEngine.shared
    private let positionSizer = DynamicPositionSizer.shared

    // MARK: - Published UI State
    @Published public var topDecisions: [SmartTradingDecision] = []
    @Published public var watchlistDecisions: [SmartTradingDecision] = []
    @Published public var portfolioDecisions: [SmartTradingDecision] = []
    @Published public var isAnalyzing: Bool = false
    @Published public var lastRefreshTime: Date?
    @Published public var selectedTab: IntelligenceTab = .overview
    @Published public var errorMessage: String?

    // Market context
    @Published public var currentFearGreed: Int = 50
    @Published public var fearGreedClassification: String = "Neutral"
    @Published public var marketRegimeSummary: String = "Unknown"

    // Performance summary
    @Published public var aiAccuracy: Double = 0
    @Published public var totalPredictions: Int = 0
    @Published public var bestSignalSource: String = "—"

    // DCA summary
    @Published public var activeDCAPlans: Int = 0
    @Published public var nextDCAExecution: Date?

    private var cancellables = Set<AnyCancellable>()
    private var autoRefreshTimer: Timer?

    // MARK: - Tabs

    public enum IntelligenceTab: String, CaseIterable {
        case overview = "Overview"
        case signals = "Signals"
        case dca = "Smart DCA"
        case performance = "Performance"
        case settings = "Settings"

        public var icon: String {
            switch self {
            case .overview:    return "brain.head.profile"
            case .signals:     return "waveform.path.ecg"
            case .dca:         return "arrow.triangle.2.circlepath"
            case .performance: return "chart.bar.xaxis"
            case .settings:    return "gearshape"
            }
        }
    }

    // MARK: - Init

    private init() {
        setupBindings()
        refreshMarketContext()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Forward engine analyzing state
        engine.$isAnalyzing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAnalyzing)

        // Forward DCA plan count
        dcaEngine.$activePlans
            .receive(on: DispatchQueue.main)
            .map(\.count)
            .assign(to: &$activeDCAPlans)

        // Forward performance accuracy
        performanceEngine.$overallAccuracy
            .receive(on: DispatchQueue.main)
            .assign(to: &$aiAccuracy)

        performanceEngine.$trackedPredictions
            .receive(on: DispatchQueue.main)
            .map(\.count)
            .assign(to: &$totalPredictions)

        performanceEngine.$sourceAccuracies
            .receive(on: DispatchQueue.main)
            .map { accuracies -> String in
                accuracies.first?.source.displayName ?? "—"
            }
            .assign(to: &$bestSignalSource)
    }

    // MARK: - Refresh Market Context

    public func refreshMarketContext() {
        let fgVM = ExtendedFearGreedViewModel.shared

        if let firebaseScore = fgVM.firebaseSentimentScore {
            currentFearGreed = firebaseScore
            fearGreedClassification = fgVM.firebaseSentimentVerdict ?? "Unknown"
        } else if let first = fgVM.data.first, let val = Int(first.value) {
            currentFearGreed = val
            fearGreedClassification = first.value_classification
        }

        // Market regime from SageAlgorithmEngine
        if let regime = SageAlgorithmEngine.shared.currentRegimes.values.first {
            marketRegimeSummary = regime.displayName
        }
    }

    // MARK: - Full Portfolio Analysis

    /// Analyze the user's entire portfolio and watchlist with the SmartTradingEngine.
    public func analyzePortfolio() async {
        isAnalyzing = true
        errorMessage = nil

        defer {
            isAnalyzing = false
            lastRefreshTime = Date()
        }

        refreshMarketContext()

        let marketVM = MarketViewModel.shared
        let portfolioVM = PortfolioViewModel.shared

        // Build portfolio snapshot
        let snapshot = buildPortfolioSnapshot(from: portfolioVM)

        // Analyze portfolio holdings
        var assets: [(symbol: String, coinName: String, price: Double, history: [Double], volumes: [Double], sparkline: [Double], change24h: Double, change7d: Double?)] = []

        // Get holdings from portfolio
        let holdings = portfolioVM.holdings
        for holding in holdings {
            if let coin = marketVM.allCoins.first(where: { $0.symbol.lowercased() == holding.coinSymbol.lowercased() }) {
                let sparkline = coin.sparklineIn7d
                let change24h = coin.priceChangePercentage24hInCurrency ?? 0
                let change7d = coin.priceChangePercentage7dInCurrency

                assets.append((
                    symbol: coin.symbol,
                    coinName: coin.name,
                    price: coin.priceUsd ?? holding.currentPrice,
                    history: sparkline,
                    volumes: [],
                    sparkline: sparkline,
                    change24h: change24h,
                    change7d: change7d
                ))
            }
        }

        // Analyze
        if !assets.isEmpty {
            let decisions = await engine.analyzeMultipleAssets(
                assets: assets,
                portfolioSnapshot: snapshot
            )
            portfolioDecisions = decisions

            // Track decisions for performance monitoring
            for decision in decisions {
                performanceEngine.trackDecision(decision)
            }
        }

        // Resolve any expired predictions
        var currentPrices: [String: Double] = [:]
        for coin in marketVM.allCoins {
            if let price = coin.priceUsd {
                currentPrices[coin.symbol.lowercased()] = price
            }
        }
        performanceEngine.resolveExpiredPredictions(currentPrices: currentPrices)
    }

    /// Analyze the user's watchlist favorites.
    public func analyzeWatchlist() async {
        let marketVM = MarketViewModel.shared
        let portfolioVM = PortfolioViewModel.shared
        let snapshot = buildPortfolioSnapshot(from: portfolioVM)

        let favorites = FavoritesManager.shared.favoriteIDs
        var assets: [(symbol: String, coinName: String, price: Double, history: [Double], volumes: [Double], sparkline: [Double], change24h: Double, change7d: Double?)] = []

        for coinId in favorites {
            if let coin = marketVM.allCoins.first(where: { $0.id == coinId }) {
                assets.append((
                    symbol: coin.symbol,
                    coinName: coin.name,
                    price: coin.priceUsd ?? 0,
                    history: coin.sparklineIn7d,
                    volumes: [],
                    sparkline: coin.sparklineIn7d,
                    change24h: coin.priceChangePercentage24hInCurrency ?? 0,
                    change7d: coin.priceChangePercentage7dInCurrency
                ))
            }
        }

        if !assets.isEmpty {
            let decisions = await engine.analyzeMultipleAssets(
                assets: assets,
                portfolioSnapshot: snapshot
            )
            watchlistDecisions = decisions
        }
    }

    /// Analyze the top market coins.
    public func analyzeTopCoins(limit: Int = 10) async {
        let marketVM = MarketViewModel.shared
        let portfolioVM = PortfolioViewModel.shared
        let snapshot = buildPortfolioSnapshot(from: portfolioVM)

        let topCoins = Array(marketVM.allCoins.prefix(limit))
        var assets: [(symbol: String, coinName: String, price: Double, history: [Double], volumes: [Double], sparkline: [Double], change24h: Double, change7d: Double?)] = []

        for coin in topCoins {
            assets.append((
                symbol: coin.symbol,
                coinName: coin.name,
                price: coin.priceUsd ?? 0,
                history: coin.sparklineIn7d,
                volumes: [],
                sparkline: coin.sparklineIn7d,
                change24h: coin.priceChangePercentage24hInCurrency ?? 0,
                change7d: coin.priceChangePercentage7dInCurrency
            ))
        }

        if !assets.isEmpty {
            let decisions = await engine.analyzeMultipleAssets(
                assets: assets,
                portfolioSnapshot: snapshot
            )
            topDecisions = decisions
        }
    }

    /// Full refresh: portfolio + watchlist + top coins.
    public func fullRefresh() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.analyzePortfolio() }
            group.addTask { await self.analyzeWatchlist() }
            group.addTask { await self.analyzeTopCoins() }
        }
    }

    // MARK: - Single Asset Analysis

    public func analyzeAsset(
        symbol: String,
        coinName: String,
        price: Double,
        sparkline: [Double],
        change24h: Double,
        change7d: Double?
    ) async -> SmartTradingDecision {
        let snapshot = buildPortfolioSnapshot(from: PortfolioViewModel.shared)

        let decision = await engine.analyzeAsset(
            symbol: symbol,
            coinName: coinName,
            currentPrice: price,
            priceHistory: sparkline,
            volumes: [],
            sparkline7d: sparkline,
            change24h: change24h,
            change7d: change7d,
            portfolioSnapshot: snapshot
        )

        performanceEngine.trackDecision(decision)
        return decision
    }

    // MARK: - Smart DCA

    public func createDCAPlan(
        name: String,
        assets: [(symbol: String, name: String, pct: Double)],
        baseAmount: Double,
        frequency: DCAFrequency
    ) -> SmartDCAPlan {
        let allocations = assets.map { asset in
            DCAAssetAllocation(
                id: UUID(),
                symbol: asset.symbol,
                coinName: asset.name,
                allocationPct: asset.pct
            )
        }

        return dcaEngine.createPlan(
            name: name,
            assets: allocations,
            baseAmount: baseAmount,
            frequency: frequency
        )
    }

    public func previewDCA(plan: SmartDCAPlan) -> DCAExecutionResult {
        dcaEngine.previewExecution(plan: plan)
    }

    public func executeDCA(plan: SmartDCAPlan) async -> DCAExecutionResult {
        await dcaEngine.executePlan(plan)
    }

    // MARK: - Portfolio Rebalancing

    public func getRebalancingRecommendations() -> [PortfolioAllocationRecommendation] {
        let allDecisions = portfolioDecisions + watchlistDecisions
        guard !allDecisions.isEmpty else { return [] }

        let snapshot = buildPortfolioSnapshot(from: PortfolioViewModel.shared)
        return positionSizer.calculatePortfolioAllocation(
            decisions: allDecisions,
            portfolioSnapshot: snapshot,
            config: engine.config
        )
    }

    // MARK: - Engine Configuration

    public func updateConfig(_ config: SmartEngineConfig) {
        engine.config = config
        engine.saveConfig()
    }

    public var currentConfig: SmartEngineConfig {
        engine.config
    }

    public func applyPreset(_ preset: ConfigPreset) {
        switch preset {
        case .conservative: engine.config = .conservative
        case .balanced:     engine.config = .default
        case .aggressive:   engine.config = .aggressive
        }
        engine.saveConfig()
    }

    public enum ConfigPreset: String, CaseIterable {
        case conservative = "Conservative"
        case balanced = "Balanced"
        case aggressive = "Aggressive"

        public var description: String {
            switch self {
            case .conservative: return "Lower risk, smaller positions, higher conviction required"
            case .balanced:     return "Standard risk/reward balance"
            case .aggressive:   return "Higher risk tolerance, larger positions, lower conviction threshold"
            }
        }
    }

    // MARK: - Auto Refresh

    public func startAutoRefresh(interval: TimeInterval = 300) { // 5 minutes
        stopAutoRefresh()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fullRefresh()
            }
        }
    }

    public func stopAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    // MARK: - Helper: Build Portfolio Snapshot

    private func buildPortfolioSnapshot(from portfolioVM: PortfolioViewModel) -> PortfolioRiskSnapshot {
        let holdings = portfolioVM.holdings
        let totalValue = holdings.map(\.currentValue).reduce(0, +)

        let holdingSnapshots = holdings.map { h -> PortfolioRiskSnapshot.PortfolioHoldingSnapshot in
            PortfolioRiskSnapshot.PortfolioHoldingSnapshot(
                symbol: h.coinSymbol,
                allocationPct: totalValue > 0 ? (h.currentValue / totalValue * 100) : 0,
                unrealizedPnLPct: h.costBasis > 0 ? ((h.currentValue - h.costBasis) / h.costBasis * 100) : 0,
                costBasis: h.costBasis,
                currentValue: h.currentValue
            )
        }

        // Concentration risk: Herfindahl index
        let weights = holdingSnapshots.map { $0.allocationPct / 100.0 }
        let herfindahl = weights.map { pow($0, 2) }.reduce(0, +)

        return PortfolioRiskSnapshot(
            totalValueUSD: totalValue,
            cashAvailableUSD: totalValue * 0.1, // assume 10% available unless we have exchange data
            holdings: holdingSnapshots,
            concentrationRisk: min(herfindahl * 2, 1.0), // normalize
            overallDrawdown: 0, // would need historical peak tracking
            dailyPnLPct: 0,
            weeklyPnLPct: 0
        )
    }
}
