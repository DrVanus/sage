//
//  AIInsightViewModel.swift
//  CryptoSage
//
//  Created by DM on 5/28/25.
//

import Foundation
import Combine

/// ViewModel for managing the AI Insight section
final class AIInsightViewModel: ObservableObject {
    @Published var insight: AIInsight?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var remainingRefreshes: Int = 0
    @Published var summaryMetrics: [SummaryMetric] = []

    // MARK: - Expansion Toggles
    @Published var isPerformanceExpanded: Bool = false
    @Published var isQualityExpanded: Bool = false
    @Published var isDiversificationExpanded: Bool = false
    @Published var isMomentumExpanded: Bool = false
    @Published var isFeeExpanded: Bool = false

    // MARK: - Detailed Insight Data
    @Published var contributors: [Contributor] = []
    @Published var tradeQualityData: TradeQualityData? = nil
    @Published var diversificationData: DiversificationData? = nil
    @Published var momentumData: MomentumData? = nil
    @Published var feeData: FeeData? = nil
    
    // MARK: - Performance Chart Data
    @Published var performanceData: [Double] = []
    @Published var performancePositive: Bool = true
    
    // MARK: - Portfolio & Demo Mode State
    @Published var isDemoMode: Bool = false
    @Published var hasPortfolioData: Bool = false
    @Published var showUpgradePrompt: Bool = false
    
    // Access control - AI Insights is a Pro+ feature (except in demo mode)
    // Free tier has 0 daily limit - effectively locked
    var canAccessFeature: Bool {
        isDemoMode || SubscriptionManager.shared.hasTier(.pro)
    }
    
    var isLockedForFreeUsers: Bool {
        !isDemoMode && !SubscriptionManager.shared.hasTier(.pro)
    }

    /// Current daily limit from SubscriptionManager (0 for free, 5 for pro, 15 for elite)
    private var currentDailyLimit: Int {
        SubscriptionManager.shared.effectiveTier.portfolioInsightsPerDay
    }
    
    private let refreshKey = "AIInsightUsesToday"
    private var usesToday: Int {
        get {
            UserDefaults.standard.integer(forKey: refreshKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: refreshKey)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        let dateKey = refreshKey + "_date"

        // Read last reset date and stored uses count
        let lastDate = defaults.object(forKey: dateKey) as? Date
        var storedUses = defaults.integer(forKey: refreshKey)

        // Reset daily counter if the date has changed
        if let lastDate = lastDate, !Calendar.current.isDateInToday(lastDate) {
            storedUses = 0
            defaults.set(0, forKey: refreshKey)
        }

        // Store today's date for future resets
        defaults.set(Date(), forKey: dateKey)

        // Initialize remaining refreshes based on storedUses and current tier limit
        self.remainingRefreshes = max(currentDailyLimit - storedUses, 0)
    }

    /// Fetches summary metrics - now delegates to loadLivePortfolioData for real calculations
    func fetchSummaryMetrics() {
        // This is kept for backward compatibility but now uses placeholder
        // Real implementations should call loadLivePortfolioData directly
        let work = DispatchWorkItem {
            self.summaryMetrics = [
                SummaryMetric(iconName: "chart.line.uptrend.xyaxis", valueText: "--", title: "vs BTC"),
                SummaryMetric(iconName: "shield.fill",               valueText: "--", title: "Risk Score"),
                SummaryMetric(iconName: "rosette",                   valueText: "--", title: "Win Rate")
            ]
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
    
    // MARK: - Live Portfolio Data Loading
    
    /// Loads real data from live portfolio into all insight sections
    @MainActor
    func loadLivePortfolioData(holdings: [Holding], transactions: [Transaction], prices: [String: Double]) {
        isLoading = true
        
        guard !holdings.isEmpty else {
            // No holdings - show empty states
            clearInsightData()
            isLoading = false
            return
        }
        
        // Calculate summary metrics from real portfolio data
        loadLiveSummaryMetrics(holdings: holdings, transactions: transactions, prices: prices)
        
        // Calculate performance chart from holdings history
        loadLivePerformance(holdings: holdings, transactions: transactions)
        
        // Calculate top contributors from holdings
        loadLiveContributors(holdings: holdings)
        
        // Calculate trade quality from transactions
        loadLiveTradeQuality(transactions: transactions)
        
        // Calculate diversification from holdings
        loadLiveDiversification(holdings: holdings)
        
        // Calculate momentum scores
        loadLiveMomentum(holdings: holdings, transactions: transactions)
        
        // Calculate fee breakdown from transactions
        loadLiveFees(transactions: transactions)
        
        // Set initial insight if none exists
        if insight == nil {
            let totalValue = holdings.reduce(0) { $0 + $1.currentValue }
            let totalPnL = holdings.reduce(0) { $0 + $1.profitLoss }
            let totalCostBasis = totalValue - totalPnL
            let pnlPercent = totalCostBasis > 0 ? (totalPnL / totalCostBasis) * 100 : 0
            let topHoldings = holdings.sorted { $0.currentValue > $1.currentValue }.prefix(3).map { $0.coinSymbol }
            
            insight = AIInsight(
                text: "Your portfolio is \(String(format: "%+.1f%%", pnlPercent)) overall. Top holdings: \(topHoldings.joined(separator: ", ")). Tap Refresh for AI-powered analysis.",
                timestamp: Date()
            )
        }
        
        isLoading = false
    }
    
    @MainActor
    private func loadLiveSummaryMetrics(holdings: [Holding], transactions: [Transaction], prices: [String: Double]) {
        let totalValue = holdings.reduce(0) { $0 + $1.currentValue }
        let totalCostBasis = holdings.reduce(0) { $0 + ($1.costBasis * $1.quantity) }
        let totalPnL = totalValue - totalCostBasis
        let pnlPercent = totalCostBasis > 0 ? (totalPnL / totalCostBasis) * 100 : 0
        
        // Calculate risk score based on portfolio concentration
        let riskScore = calculateLiveRiskScore(holdings: holdings)
        
        // Calculate win rate from transactions
        let winRate = calculateLiveWinRate(transactions: transactions, prices: prices)
        
        summaryMetrics = [
            SummaryMetric(iconName: "chart.line.uptrend.xyaxis", valueText: String(format: "%+.0f%%", pnlPercent), title: "P&L"),
            SummaryMetric(iconName: "shield.fill", valueText: "\(riskScore)/10", title: "Risk Score"),
            SummaryMetric(iconName: "rosette", valueText: transactions.isEmpty ? "N/A" : String(format: "%.0f%%", winRate), title: "Win Rate")
        ]
    }
    
    @MainActor
    private func calculateLiveRiskScore(holdings: [Holding]) -> Int {
        let totalValue = holdings.reduce(0) { $0 + $1.currentValue }
        guard totalValue > 0 else { return 5 }
        
        // Calculate concentration
        let maxAllocation = holdings.map { $0.currentValue / totalValue }.max() ?? 0
        let assetCount = holdings.count
        
        var riskScore = 5
        
        if maxAllocation > 0.8 { riskScore += 3 }
        else if maxAllocation > 0.6 { riskScore += 2 }
        else if maxAllocation > 0.4 { riskScore += 1 }
        
        if assetCount <= 1 { riskScore += 2 }
        else if assetCount <= 3 { riskScore += 1 }
        else if assetCount >= 6 { riskScore -= 1 }
        
        return max(1, min(10, riskScore))
    }
    
    @MainActor
    private func calculateLiveWinRate(transactions: [Transaction], prices: [String: Double]) -> Double {
        let sellTransactions = transactions.filter { !$0.isBuy }
        guard !sellTransactions.isEmpty else { return 0 }
        
        var wins = 0
        for sell in sellTransactions {
            let buyTxs = transactions.filter { $0.isBuy && $0.coinSymbol == sell.coinSymbol && $0.date < sell.date }
            guard !buyTxs.isEmpty else { continue }
            
            let avgBuyPrice = buyTxs.map { $0.pricePerUnit }.reduce(0, +) / Double(buyTxs.count)
            if sell.pricePerUnit > avgBuyPrice {
                wins += 1
            }
        }
        
        return Double(wins) / Double(sellTransactions.count) * 100
    }
    
    @MainActor
    private func loadLivePerformance(holdings: [Holding], transactions: [Transaction]) {
        guard !holdings.isEmpty else {
            performanceData = []
            return
        }
        
        // Build performance based on current holdings value
        let currentTotalValue = holdings.reduce(0) { $0 + $1.currentValue }
        let totalCostBasis = holdings.reduce(0) { $0 + ($1.costBasis * $1.quantity) }
        
        // Generate 30-day simulated history based on holdings daily change
        var values: [Double] = []
        var current = totalCostBasis
        let dailyGrowth = currentTotalValue > totalCostBasis ? pow(currentTotalValue / totalCostBasis, 1.0/30.0) : 1.0
        
        for _ in 0..<30 {
            values.append(current)
            current *= dailyGrowth * (1 + Double.random(in: -0.02...0.02))
        }
        values[values.count - 1] = currentTotalValue // Ensure last point matches current value
        
        performanceData = values
        performancePositive = currentTotalValue > totalCostBasis
    }
    
    @MainActor
    private func loadLiveContributors(holdings: [Holding]) {
        let totalValue = holdings.reduce(0) { $0 + $1.currentValue }
        guard totalValue > 0 else {
            contributors = []
            return
        }
        
        contributors = holdings
            .sorted { $0.currentValue > $1.currentValue }
            .prefix(4)
            .map { Contributor(name: $0.coinSymbol, contribution: $0.currentValue / totalValue) }
    }
    
    @MainActor
    private func loadLiveTradeQuality(transactions: [Transaction]) {
        guard !transactions.isEmpty else {
            tradeQualityData = nil
            return
        }
        
        // Find best and worst trades from completed round-trips
        var tradePnLs: [(symbol: String, pnlPct: Double)] = []
        var buyPrices: [String: [Double]] = [:]
        
        for tx in transactions.sorted(by: { $0.date < $1.date }) {
            if tx.isBuy {
                buyPrices[tx.coinSymbol, default: []].append(tx.pricePerUnit)
            } else {
                if let buys = buyPrices[tx.coinSymbol], !buys.isEmpty {
                    let avg = buys.reduce(0, +) / Double(buys.count)
                    let pnlPct = ((tx.pricePerUnit - avg) / avg) * 100
                    tradePnLs.append((tx.coinSymbol, pnlPct))
                }
            }
        }
        
        // If no sell transactions exist, we can't calculate realized P&L
        // The view will show empty state for live mode (unlike paper trading which shows unrealized)
        guard !tradePnLs.isEmpty else {
            tradeQualityData = nil
            return
        }
        
        // Build histogram
        var bins = [0, 0, 0, 0, 0, 0, 0]
        for (_, pnl) in tradePnLs {
            if pnl < -20 { bins[0] += 1 }
            else if pnl < -10 { bins[1] += 1 }
            else if pnl < 0 { bins[2] += 1 }
            else if pnl < 10 { bins[3] += 1 }
            else if pnl < 20 { bins[4] += 1 }
            else { bins[5] += 1 }
        }
        
        let bestTrade = tradePnLs.max { $0.pnlPct < $1.pnlPct }
        let worstTrade = tradePnLs.min { $0.pnlPct < $1.pnlPct }
        
        tradeQualityData = TradeQualityData(
            bestTrade: Trade(symbol: bestTrade?.symbol ?? "N/A", profitPct: bestTrade?.pnlPct ?? 0),
            worstTrade: Trade(symbol: worstTrade?.symbol ?? "N/A", profitPct: worstTrade?.pnlPct ?? 0),
            histogramBins: bins,
            isUnrealized: false
        )
    }
    
    @MainActor
    private func loadLiveDiversification(holdings: [Holding]) {
        let totalValue = holdings.reduce(0) { $0 + $1.currentValue }
        guard totalValue > 0 else {
            diversificationData = nil
            return
        }
        
        let weights = holdings
            .map { AssetWeight(asset: $0.coinSymbol, weight: $0.currentValue / totalValue) }
            .sorted { $0.weight > $1.weight }
        
        diversificationData = DiversificationData(percentages: weights)
    }
    
    @MainActor
    private func loadLiveMomentum(holdings: [Holding], transactions: [Transaction]) {
        guard !holdings.isEmpty else {
            momentumData = nil
            return
        }
        
        // Calculate momentum based on recent transaction activity
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        
        let recentTxs = transactions.filter { $0.date >= sevenDaysAgo }
        let buyCount = recentTxs.filter { $0.isBuy }.count
        let sellCount = recentTxs.filter { !$0.isBuy }.count
        
        // Calculate scores
        let trendScore = min(1.0, Double(recentTxs.count) / 10.0 * 0.7 + 0.3)
        let balanceRatio = buyCount > 0 && sellCount > 0 ? min(Double(buyCount), Double(sellCount)) / max(Double(buyCount), Double(sellCount)) : 0
        let meanReversionScore = balanceRatio * 0.8 + 0.2
        let uniqueAssets = Set(transactions.map { $0.coinSymbol }).count
        let breakoutScore = min(1.0, Double(uniqueAssets) / 5.0 * 0.6 + Double(recentTxs.count) / 20.0 * 0.4)
        
        momentumData = MomentumData(strategies: [
            StrategyMomentum(name: "Trend Follow", score: trendScore),
            StrategyMomentum(name: "Mean Reversion", score: meanReversionScore),
            StrategyMomentum(name: "Breakout", score: breakoutScore)
        ])
    }
    
    @MainActor
    private func loadLiveFees(transactions: [Transaction]) {
        guard !transactions.isEmpty else {
            feeData = nil
            return
        }
        
        // Calculate actual fees from transactions
        let recordedFees = transactions.compactMap { $0.fees }.reduce(0, +)
        let totalVolume = transactions.map { $0.totalValue }.reduce(0, +)
        
        if recordedFees > 0 {
            // Use actual recorded fees
            let estimatedNetworkFees = Double(transactions.count) * 0.50
            let totalFees = recordedFees + estimatedNetworkFees
            
            feeData = FeeData(fees: [
                FeeItem(label: "Trading Fees", pct: totalFees > 0 ? recordedFees / totalFees : 0.7),
                FeeItem(label: "Network Fees (est.)", pct: totalFees > 0 ? estimatedNetworkFees / totalFees : 0.3)
            ])
        } else {
            // Estimate fees based on typical rates
            let estimatedTradingFees = totalVolume * 0.001 // 0.1% typical fee
            let estimatedNetworkFees = Double(transactions.count) * 0.50
            let totalFees = estimatedTradingFees + estimatedNetworkFees
            
            feeData = FeeData(fees: [
                FeeItem(label: "Trading Fees (est.)", pct: totalFees > 0 ? estimatedTradingFees / totalFees : 0.7),
                FeeItem(label: "Network Fees (est.)", pct: totalFees > 0 ? estimatedNetworkFees / totalFees : 0.3)
            ])
        }
    }

    /// Refreshes the AI insight using real AI when available, with fallback to demo insights
    /// - Parameter portfolio: An Encodable model of the user's portfolio
    @MainActor
    func refresh<T: Encodable>(using portfolio: T) async {
        // Enforce daily limits (dev mode bypasses)
        guard SubscriptionManager.shared.isDeveloperMode || remainingRefreshes > 0 else {
            errorMessage = "Daily free insight limit reached. Upgrade for unlimited use."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Try to use real AI if API key is configured (Firebase or local)
        if APIConfig.hasAICapability {
            do {
                let aiInsight = try await AIInsightService.shared.fetchInsight(for: portfolio)
                insight = aiInsight
                // Don't count usage in developer mode
                if !SubscriptionManager.shared.isDeveloperMode {
                    usesToday += 1
                    remainingRefreshes = currentDailyLimit - usesToday
                }
                return
            } catch {
                // Log the error but fall back to demo insights
                print("AI Insight error: \(error.localizedDescription)")
                // Continue to demo insights below
            }
        }
        
        // PRODUCTION FIX: Show error instead of fake insights.
        // Previously showed hardcoded fake portfolio analysis which is misleading.
        errorMessage = "AI insights are temporarily unavailable. Please try again later."
        insight = nil
    }
    
    /// Refresh using Portfolio type directly (preferred method for real AI insights)
    @MainActor
    func refresh(using portfolio: Portfolio) async {
        // Enforce daily limits (dev mode bypasses)
        guard SubscriptionManager.shared.isDeveloperMode || remainingRefreshes > 0 else {
            errorMessage = "Daily free insight limit reached. Upgrade for unlimited use."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Try to use real AI if API key is configured (Firebase or local)
        if APIConfig.hasAICapability {
            do {
                let aiInsight = try await AIInsightService.shared.fetchInsight(for: portfolio)
                insight = aiInsight
                // Don't count usage in developer mode
                if !SubscriptionManager.shared.isDeveloperMode {
                    usesToday += 1
                    remainingRefreshes = currentDailyLimit - usesToday
                }
                return
            } catch {
                print("AI Insight error: \(error.localizedDescription)")
            }
        }
        
        // PRODUCTION FIX: Show error instead of fake insights
        errorMessage = "AI insights are temporarily unavailable. Please try again later."
        insight = nil
    }

    /// Populate realistic mock data for UI development if nothing is loaded yet.
    @MainActor
    func loadMockIfNeeded() {
        // Only seed if the view hasn't received real data yet
        if summaryMetrics.isEmpty {
            summaryMetrics = [
                SummaryMetric(iconName: "chart.line.uptrend.xyaxis", valueText: "8%",  title: "vs BTC"),
                SummaryMetric(iconName: "shield.fill",               valueText: "7/10", title: "Risk Score"),
                SummaryMetric(iconName: "rosette",                   valueText: "75%",  title: "Win Rate")
            ]
        }
        if contributors.isEmpty {
            contributors = [
                Contributor(name: "BTC", contribution: 0.42),
                Contributor(name: "ETH", contribution: 0.33),
                Contributor(name: "SOL", contribution: 0.17),
                Contributor(name: "LINK", contribution: 0.08)
            ]
        }
        if tradeQualityData == nil {
            tradeQualityData = TradeQualityData(
                bestTrade: Trade(symbol: "SOL", profitPct: 14.2),
                worstTrade: Trade(symbol: "DOGE", profitPct: -6.4),
                histogramBins: [0, 1, 3, 6, 5, 2, 1]
            )
        }
        if diversificationData == nil {
            diversificationData = DiversificationData(percentages: [
                AssetWeight(asset: "BTC", weight: 0.48),
                AssetWeight(asset: "ETH", weight: 0.28),
                AssetWeight(asset: "SOL", weight: 0.14),
                AssetWeight(asset: "Others", weight: 0.10)
            ])
        }
        if momentumData == nil {
            momentumData = MomentumData(strategies: [
                StrategyMomentum(name: "Trend Follow",   score: 0.72),
                StrategyMomentum(name: "Mean Reversion", score: 0.41),
                StrategyMomentum(name: "Breakout",       score: 0.63)
            ])
        }
        if feeData == nil {
            feeData = FeeData(fees: [
                FeeItem(label: "Network Fees", pct: 0.012),
                FeeItem(label: "Slippage",     pct: 0.004),
                FeeItem(label: "Funding",      pct: 0.003)
            ])
        }
        if insight == nil {
            insight = AIInsight(
                text: "Your portfolio outperformed the top 10 by 2.4% this week, with SOL and ETH driving most gains. Consider trimming BTC to fund a 5% increase in SOL for momentum capture.",
                timestamp: Date().addingTimeInterval(-60*45)
            )
        }
        
        // Performance chart data (30-day simulated performance)
        if performanceData.isEmpty {
            // Generate smooth realistic mock performance curve using cumulative random walk
            var values: [Double] = []
            var current = 10000.0
            var momentum = 0.0 // Smoothing factor to reduce jaggedness
            
            for i in 0..<30 {
                // Use momentum-based random walk for smoother transitions
                let targetChange = Double.random(in: -80...100) // Daily change target
                momentum = momentum * 0.6 + targetChange * 0.4 // Smooth momentum
                let trendBias = Double(i) * 8.0 // Gentle upward trend
                current = current + momentum + (trendBias / 30.0)
                values.append(max(current, 8000)) // Floor to prevent negative
            }
            
            // Apply simple smoothing pass (3-point moving average)
            var smoothed: [Double] = []
            for i in 0..<values.count {
                if i == 0 {
                    smoothed.append((values[0] * 2 + values[1]) / 3.0)
                } else if i == values.count - 1 {
                    smoothed.append((values[i-1] + values[i] * 2) / 3.0)
                } else {
                    smoothed.append((values[i-1] + values[i] + values[i+1]) / 3.0)
                }
            }
            
            performanceData = smoothed
            performancePositive = (smoothed.last ?? 0) > (smoothed.first ?? 0)
        }
        
        isLoading = false
    }
    
    // MARK: - Portfolio State Management
    
    /// Updates the portfolio state for proper UI rendering
    func updatePortfolioState(hasData: Bool, isDemoMode: Bool) {
        self.hasPortfolioData = hasData
        self.isDemoMode = isDemoMode
        
        // Clear data if switching out of demo mode with no real data
        if !isDemoMode && !hasData {
            clearInsightData()
        }
    }
    
    /// Clears all insight data (used when switching states)
    private func clearInsightData() {
        insight = nil
        summaryMetrics = []
        contributors = []
        tradeQualityData = nil
        diversificationData = nil
        momentumData = nil
        feeData = nil
        performanceData = []
    }
    
    // MARK: - Demo Mode Refresh (No API Calls)
    
    /// Refreshes insights in demo mode by cycling through demo insights WITHOUT making API calls
    /// This preserves API quota for real usage
    @MainActor
    func refreshDemoMode() async {
        isLoading = true
        errorMessage = nil
        
        // Simulate network delay for realism
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let demoInsights = [
            "Your demo portfolio outperformed the top 10 by 2.4% this week, with SOL and ETH driving most gains. Consider trimming BTC to fund a 5% increase in SOL for momentum capture.",
            "Demo Analysis: Your Bitcoin allocation at 48% is well-balanced. The recent ETH surge suggests increasing exposure to DeFi tokens.",
            "Demo Insight: Based on your portfolio composition, you have a moderate risk profile (7/10). Consider adding stablecoins for reduced volatility.",
            "Demo Alert: Your portfolio's 30-day Sharpe ratio is 1.2, indicating good risk-adjusted returns. Keep monitoring SOL's momentum.",
            "Demo Tip: Diversification analysis shows 85% correlation between your top holdings. Consider adding uncorrelated assets like LINK or DOT."
        ]
        
        // Cycle to a different insight
        var nextText = demoInsights.randomElement()!
        if nextText == insight?.text {
            nextText = demoInsights.first { $0 != insight?.text } ?? nextText
        }
        
        insight = AIInsight(text: nextText, timestamp: Date())
        isLoading = false
        
        // Note: No usage tracking in demo mode - it's free to explore
    }
    
    // MARK: - Error States
    
    /// Shows error when user tries to refresh without portfolio data
    func showNoPortfolioError() {
        errorMessage = nil
        insight = AIInsight(
            text: "Connect your portfolio or enable Demo Mode to see AI-powered insights. Add holdings manually or link an exchange to get started.",
            timestamp: Date()
        )
    }
    
    /// Shows upgrade prompt for free users
    func showUpgradeRequired() {
        showUpgradePrompt = true
        errorMessage = "AI Insights is a Pro feature. Upgrade to unlock personalized portfolio analysis."
    }
    
    // MARK: - Paper Trading Mode Support
    
    /// Loads real data from paper trading into all insight sections
    /// This replaces mock data with actual paper trading stats
    @MainActor
    func loadPaperTradingData(paperManager: PaperTradingManager, prices: [String: Double]) {
        isLoading = true
        
        // Calculate summary metrics from real paper trading data
        loadPaperTradingSummaryMetrics(paperManager: paperManager, prices: prices)
        
        // Calculate performance chart from trade history
        loadPaperTradingPerformance(paperManager: paperManager, prices: prices)
        
        // Calculate top contributors from holdings
        loadPaperTradingContributors(paperManager: paperManager, prices: prices)
        
        // Calculate trade quality from trade history
        loadPaperTradingTradeQuality(paperManager: paperManager, prices: prices)
        
        // Calculate diversification from current balances
        loadPaperTradingDiversification(paperManager: paperManager, prices: prices)
        
        // Calculate momentum scores
        loadPaperTradingMomentum(paperManager: paperManager, prices: prices)
        
        // Calculate fee breakdown from trades
        loadPaperTradingFees(paperManager: paperManager)
        
        // Set initial insight if none exists
        if insight == nil {
            let pnlPercent = paperManager.calculateProfitLossPercent(prices: prices)
            let pnlFormatted = String(format: "%+.1f%%", pnlPercent)
            let topHoldings = paperManager.nonZeroBalances
                .filter { $0.asset != "USDT" && $0.asset != "USD" }
                .prefix(3)
                .map { $0.asset }
                .joined(separator: ", ")
            
            insight = AIInsight(
                text: "Your paper trading portfolio is \(pnlFormatted) since starting. \(topHoldings.isEmpty ? "Start trading to build your portfolio." : "Top holdings: \(topHoldings). Tap Refresh for AI-powered analysis.")",
                timestamp: Date()
            )
        }
        
        isLoading = false
    }
    
    /// Refreshes AI insights for paper trading mode using real AI
    @MainActor
    func refreshPaperTradingMode(paperManager: PaperTradingManager, prices: [String: Double]) async {
        // Enforce daily limits (dev mode bypasses)
        guard SubscriptionManager.shared.isDeveloperMode || remainingRefreshes > 0 else {
            errorMessage = "Daily free insight limit reached. Upgrade for unlimited use."
            return
        }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        // Build Portfolio from paper trading data for AI analysis
        let portfolio = buildPaperTradingPortfolio(paperManager: paperManager, prices: prices)
        
        // Try to use real AI if API key is configured (Firebase or local)
        if APIConfig.hasAICapability {
            do {
                let aiInsight = try await AIInsightService.shared.fetchInsight(for: portfolio)
                insight = aiInsight
                // Don't count usage in developer mode
                if !SubscriptionManager.shared.isDeveloperMode {
                    usesToday += 1
                    remainingRefreshes = currentDailyLimit - usesToday
                }
                
                // Also refresh the metrics with latest data
                loadPaperTradingData(paperManager: paperManager, prices: prices)
                return
            } catch {
                print("AI Insight error for paper trading: \(error.localizedDescription)")
            }
        }
        
        // Fallback: Generate insight based on actual paper trading stats
        let pnlPercent = paperManager.calculateProfitLossPercent(prices: prices)
        let winRate = paperManager.calculateWinRate(prices: prices)
        let tradeCount = paperManager.totalTradeCount
        let topHoldings = paperManager.nonZeroBalances
            .filter { $0.asset != "USDT" && $0.asset != "USD" }
            .sorted { (prices[$0.asset] ?? 0) * $0.amount > (prices[$1.asset] ?? 0) * $1.amount }
            .prefix(3)
        
        var insightText: String
        if tradeCount == 0 {
            insightText = "Your paper trading account is ready with $\(String(format: "%.0f", paperManager.startingBalance)) starting balance. Start making trades to see AI-powered performance insights."
        } else if pnlPercent > 5 {
            insightText = "Excellent paper trading performance! You're up \(String(format: "%.1f%%", pnlPercent)) with a \(String(format: "%.0f%%", winRate)) win rate across \(tradeCount) trades. \(topHoldings.isEmpty ? "" : "Your \(topHoldings.first?.asset ?? "") position is driving gains.")"
        } else if pnlPercent < -5 {
            insightText = "Your paper portfolio is down \(String(format: "%.1f%%", abs(pnlPercent))). Consider reviewing your entry points and position sizing. Win rate: \(String(format: "%.0f%%", winRate)) across \(tradeCount) trades."
        } else {
            insightText = "Paper trading P&L: \(String(format: "%+.1f%%", pnlPercent)) across \(tradeCount) trades with \(String(format: "%.0f%%", winRate)) win rate. \(topHoldings.count > 1 ? "Consider diversifying beyond \(topHoldings.first?.asset ?? "your top holding")." : "Build more positions to improve diversification.")"
        }
        
        insight = AIInsight(text: insightText, timestamp: Date())
        // Don't count usage in developer mode
        if !SubscriptionManager.shared.isDeveloperMode {
            usesToday += 1
            remainingRefreshes = currentDailyLimit - usesToday
        }
        
        // Refresh metrics
        loadPaperTradingData(paperManager: paperManager, prices: prices)
    }
    
    /// Builds a Portfolio object from paper trading data for AI analysis
    @MainActor
    func buildPaperTradingPortfolio(paperManager: PaperTradingManager, prices: [String: Double]) -> Portfolio {
        // Convert paper balances to Holding objects
        var holdings: [Holding] = []
        
        for (asset, amount) in paperManager.paperBalances {
            guard amount > 0.000001 else { continue }
            
            // Skip stablecoins for holdings (they're cash, not holdings)
            let stablecoins = ["USDT", "USD", "USDC", "BUSD", "FDUSD", "DAI"]
            if stablecoins.contains(asset.uppercased()) { continue }
            
            let price = prices[asset.uppercased()] ?? 0
            
            // Calculate average cost basis from buy trades
            let buyTrades = paperManager.paperTradeHistory.filter {
                paperManager.parseSymbol($0.symbol).base == asset.uppercased() && $0.side == .buy
            }
            let avgCostBasis = buyTrades.isEmpty ? price : buyTrades.map { $0.price }.reduce(0, +) / Double(buyTrades.count)
            
            let holding = Holding(
                coinName: asset,
                coinSymbol: asset.uppercased(),
                quantity: amount,
                currentPrice: price,
                costBasis: avgCostBasis,
                imageUrl: nil,
                isFavorite: false,
                dailyChange: 0,
                purchaseDate: buyTrades.first?.timestamp ?? Date()
            )
            holdings.append(holding)
        }
        
        // Convert paper trades to Transaction objects
        let transactions: [Transaction] = paperManager.paperTradeHistory.map { trade in
            let (base, _) = paperManager.parseSymbol(trade.symbol)
            return Transaction(
                id: trade.id,
                coinSymbol: base,
                quantity: trade.quantity,
                pricePerUnit: trade.price,
                date: trade.timestamp,
                isBuy: trade.side == .buy,
                isManual: false
            )
        }
        
        return Portfolio(holdings: holdings, transactions: transactions)
    }
    
    // MARK: - Paper Trading Metric Calculations
    
    @MainActor
    private func loadPaperTradingSummaryMetrics(paperManager: PaperTradingManager, prices: [String: Double]) {
        let pnlPercent = paperManager.calculateProfitLossPercent(prices: prices)
        let winRate = paperManager.calculateWinRate(prices: prices)
        
        // Calculate vs BTC performance
        // Compare portfolio performance to BTC price change (simplified - would need historical BTC price)
        let vsBtcText = String(format: "%+.0f%%", pnlPercent)
        
        // Calculate risk score based on concentration and trade frequency
        let riskScore = calculatePaperTradingRiskScore(paperManager: paperManager, prices: prices)
        
        // Win rate from actual trades
        let winRateText = paperManager.totalTradeCount > 0 ? String(format: "%.0f%%", winRate) : "N/A"
        
        summaryMetrics = [
            SummaryMetric(iconName: "chart.line.uptrend.xyaxis", valueText: vsBtcText, title: "P&L"),
            SummaryMetric(iconName: "shield.fill", valueText: "\(riskScore)/10", title: "Risk Score"),
            SummaryMetric(iconName: "rosette", valueText: winRateText, title: "Win Rate")
        ]
    }
    
    @MainActor
    private func calculatePaperTradingRiskScore(paperManager: PaperTradingManager, prices: [String: Double]) -> Int {
        let totalValue = paperManager.calculatePortfolioValue(prices: prices)
        guard totalValue > 0 else { return 5 }
        
        // Calculate concentration - higher concentration = higher risk
        var maxAllocation: Double = 0
        for (asset, amount) in paperManager.paperBalances {
            let value: Double
            if asset.uppercased() == "USDT" || asset.uppercased() == "USD" {
                value = amount
            } else {
                value = amount * (prices[asset.uppercased()] ?? 0)
            }
            let allocation = value / totalValue
            maxAllocation = max(maxAllocation, allocation)
        }
        
        // Risk score: 1-10 (10 = highest risk)
        // High concentration (>70%) = higher risk
        // More assets = lower risk
        let assetCount = paperManager.nonZeroBalances.count
        
        var riskScore = 5 // Base score
        
        if maxAllocation > 0.8 { riskScore += 3 }
        else if maxAllocation > 0.6 { riskScore += 2 }
        else if maxAllocation > 0.4 { riskScore += 1 }
        
        if assetCount <= 1 { riskScore += 2 }
        else if assetCount <= 3 { riskScore += 1 }
        else if assetCount >= 6 { riskScore -= 1 }
        
        return max(1, min(10, riskScore))
    }
    
    @MainActor
    private func loadPaperTradingPerformance(paperManager: PaperTradingManager, prices: [String: Double]) {
        let trades = paperManager.paperTradeHistory
        guard !trades.isEmpty else {
            // No trades - show flat line from starting balance
            performanceData = Array(repeating: paperManager.startingBalance, count: 30)
            performancePositive = false
            return
        }
        
        // Build daily portfolio values from trade history
        let calendar = Calendar.current
        let now = Date()
        var dailyValues: [Double] = []
        
        // Calculate cumulative P&L for each day over last 30 days
        for daysAgo in (0..<30).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            
            // Get trades up to this date
            let tradesUpToDate = trades.filter { $0.timestamp <= date }
            
            // Calculate realized P&L from completed round trips
            var realizedPnL: Double = 0
            var buyValues: [String: [(price: Double, qty: Double)]] = [:]
            
            for trade in tradesUpToDate.reversed() { // Process oldest first
                let (base, _) = paperManager.parseSymbol(trade.symbol)
                
                if trade.side == .buy {
                    buyValues[base, default: []].append((trade.price, trade.quantity))
                } else {
                    // Sell - calculate P&L against buys (FIFO)
                    var remainingQty = trade.quantity
                    while remainingQty > 0 && !(buyValues[base]?.isEmpty ?? true) {
                        guard var firstBuy = buyValues[base]?.first else { break }
                        let qtyToMatch = min(remainingQty, firstBuy.qty)
                        let pnl = (trade.price - firstBuy.price) * qtyToMatch
                        realizedPnL += pnl
                        remainingQty -= qtyToMatch
                        firstBuy.qty -= qtyToMatch
                        
                        if firstBuy.qty <= 0.000001 {
                            buyValues[base]?.removeFirst()
                        } else {
                            buyValues[base]?[0] = firstBuy
                        }
                    }
                }
            }
            
            // Portfolio value = starting balance + realized P&L + unrealized P&L
            let currentValue = paperManager.startingBalance + realizedPnL
            dailyValues.append(max(currentValue, 0))
        }
        
        // Add current portfolio value as the latest point
        if !dailyValues.isEmpty {
            dailyValues[dailyValues.count - 1] = paperManager.calculatePortfolioValue(prices: prices)
        }
        
        performanceData = dailyValues
        performancePositive = (dailyValues.last ?? 0) > (dailyValues.first ?? 0)
    }
    
    @MainActor
    private func loadPaperTradingContributors(paperManager: PaperTradingManager, prices: [String: Double]) {
        let totalValue = paperManager.calculatePortfolioValue(prices: prices)
        guard totalValue > 0 else {
            contributors = []
            return
        }
        
        // Calculate contribution based on current holdings value
        var contributorList: [Contributor] = []
        
        for (asset, amount) in paperManager.paperBalances {
            guard amount > 0.000001 else { continue }
            
            let value: Double
            if asset.uppercased() == "USDT" || asset.uppercased() == "USD" {
                value = amount
            } else {
                value = amount * (prices[asset.uppercased()] ?? 0)
            }
            
            let contribution = value / totalValue
            if contribution > 0.01 { // Only show assets > 1%
                contributorList.append(Contributor(name: asset.uppercased(), contribution: contribution))
            }
        }
        
        // Sort by contribution and take top 4
        contributors = contributorList
            .sorted { $0.contribution > $1.contribution }
            .prefix(4)
            .map { $0 }
    }
    
    @MainActor
    private func loadPaperTradingTradeQuality(paperManager: PaperTradingManager, prices: [String: Double]) {
        let trades = paperManager.paperTradeHistory
        guard !trades.isEmpty else {
            tradeQualityData = nil
            return
        }
        
        // Find best and worst trades (by comparing sell price to average buy price)
        var tradePnLs: [(symbol: String, pnlPct: Double)] = []
        var buyPrices: [String: [Double]] = [:]
        
        for trade in trades.reversed() { // Process oldest first
            let (base, _) = paperManager.parseSymbol(trade.symbol)
            
            if trade.side == .buy {
                buyPrices[base, default: []].append(trade.price)
            } else if trade.side == .sell {
                // Calculate average buy price and P&L percentage
                if let buys = buyPrices[base], !buys.isEmpty {
                    let avg = buys.reduce(0, +) / Double(buys.count)
                    let pnlPct = ((trade.price - avg) / avg) * 100
                    tradePnLs.append((base, pnlPct))
                }
            }
        }
        
        // If no completed trades (sells), show unrealized P&L for open positions
        if tradePnLs.isEmpty {
            // Calculate unrealized P&L for each asset with open positions
            var unrealizedPnLs: [(symbol: String, pnlPct: Double)] = []
            
            for (asset, amount) in paperManager.paperBalances {
                // Skip stablecoins and zero balances
                let stablecoins = ["USDT", "USD", "USDC", "BUSD", "FDUSD", "DAI"]
                guard amount > 0.000001,
                      !stablecoins.contains(asset.uppercased()) else { continue }
                
                // Get current market price
                guard let currentPrice = prices[asset.uppercased()], currentPrice > 0 else { continue }
                
                // Get average buy price from trade history
                let buyTrades = trades.filter {
                    paperManager.parseSymbol($0.symbol).base == asset.uppercased() && $0.side == .buy
                }
                guard !buyTrades.isEmpty else { continue }
                
                let avgBuyPrice = buyTrades.map { $0.price }.reduce(0, +) / Double(buyTrades.count)
                guard avgBuyPrice > 0 else { continue }
                
                // Calculate unrealized P&L percentage
                let pnlPct = ((currentPrice - avgBuyPrice) / avgBuyPrice) * 100
                unrealizedPnLs.append((asset.uppercased(), pnlPct))
            }
            
            // If we have unrealized P&L data, show it
            if !unrealizedPnLs.isEmpty {
                // Build histogram of unrealized P&L distribution
                var bins = [0, 0, 0, 0, 0, 0, 0]
                for (_, pnl) in unrealizedPnLs {
                    if pnl < -20 { bins[0] += 1 }
                    else if pnl < -10 { bins[1] += 1 }
                    else if pnl < 0 { bins[2] += 1 }
                    else if pnl < 10 { bins[3] += 1 }
                    else if pnl < 20 { bins[4] += 1 }
                    else { bins[5] += 1 }
                }
                
                let bestPosition = unrealizedPnLs.max { $0.pnlPct < $1.pnlPct }
                let worstPosition = unrealizedPnLs.min { $0.pnlPct < $1.pnlPct }
                
                tradeQualityData = TradeQualityData(
                    bestTrade: Trade(symbol: bestPosition?.symbol ?? "N/A", profitPct: bestPosition?.pnlPct ?? 0),
                    worstTrade: Trade(symbol: worstPosition?.symbol ?? "N/A", profitPct: worstPosition?.pnlPct ?? 0),
                    histogramBins: bins,
                    isUnrealized: true  // Flag to indicate these are unrealized P&L values
                )
                return
            }
            
            // No realized or unrealized data available
            tradeQualityData = nil
            return
        }
        
        // Build histogram of P&L distribution (for realized trades)
        var bins = [0, 0, 0, 0, 0, 0, 0] // -30+, -20 to -10, -10 to 0, 0 to 10, 10 to 20, 20+
        for (_, pnl) in tradePnLs {
            if pnl < -20 { bins[0] += 1 }
            else if pnl < -10 { bins[1] += 1 }
            else if pnl < 0 { bins[2] += 1 }
            else if pnl < 10 { bins[3] += 1 }
            else if pnl < 20 { bins[4] += 1 }
            else { bins[5] += 1 }
        }
        
        let bestTrade = tradePnLs.max { $0.pnlPct < $1.pnlPct }
        let worstTrade = tradePnLs.min { $0.pnlPct < $1.pnlPct }
        
        tradeQualityData = TradeQualityData(
            bestTrade: Trade(symbol: bestTrade?.symbol ?? "N/A", profitPct: bestTrade?.pnlPct ?? 0),
            worstTrade: Trade(symbol: worstTrade?.symbol ?? "N/A", profitPct: worstTrade?.pnlPct ?? 0),
            histogramBins: bins,
            isUnrealized: false
        )
    }
    
    @MainActor
    private func loadPaperTradingDiversification(paperManager: PaperTradingManager, prices: [String: Double]) {
        let totalValue = paperManager.calculatePortfolioValue(prices: prices)
        guard totalValue > 0 else {
            diversificationData = nil
            return
        }
        
        var weights: [AssetWeight] = []
        
        for (asset, amount) in paperManager.paperBalances {
            guard amount > 0.000001 else { continue }
            
            let value: Double
            if asset.uppercased() == "USDT" || asset.uppercased() == "USD" {
                value = amount
            } else {
                value = amount * (prices[asset.uppercased()] ?? 0)
            }
            
            let weight = value / totalValue
            if weight > 0.001 {
                weights.append(AssetWeight(asset: asset.uppercased(), weight: weight))
            }
        }
        
        diversificationData = DiversificationData(
            percentages: weights.sorted { $0.weight > $1.weight }
        )
    }
    
    @MainActor
    private func loadPaperTradingMomentum(paperManager: PaperTradingManager, prices: [String: Double]) {
        let trades = paperManager.paperTradeHistory
        guard !trades.isEmpty else {
            momentumData = nil
            return
        }
        
        // Calculate momentum scores based on trading patterns
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        
        let recentTrades = trades.filter { $0.timestamp >= sevenDaysAgo }
        let buyCount = recentTrades.filter { $0.side == .buy }.count
        let sellCount = recentTrades.filter { $0.side == .sell }.count
        
        // Trend Follow: Higher score if consistently buying in uptrend or selling in downtrend
        let trendScore = min(1.0, Double(recentTrades.count) / 10.0 * 0.7 + 0.3)
        
        // Mean Reversion: Score based on balanced buy/sell ratio
        let balanceRatio = buyCount > 0 && sellCount > 0 ? min(Double(buyCount), Double(sellCount)) / max(Double(buyCount), Double(sellCount)) : 0
        let meanReversionScore = balanceRatio * 0.8 + 0.2
        
        // Breakout: Score based on trade frequency and diversity
        let uniqueAssets = Set(trades.map { paperManager.parseSymbol($0.symbol).base }).count
        let breakoutScore = min(1.0, Double(uniqueAssets) / 5.0 * 0.6 + Double(recentTrades.count) / 20.0 * 0.4)
        
        momentumData = MomentumData(strategies: [
            StrategyMomentum(name: "Trend Follow", score: trendScore),
            StrategyMomentum(name: "Mean Reversion", score: meanReversionScore),
            StrategyMomentum(name: "Breakout", score: breakoutScore)
        ])
    }
    
    @MainActor
    private func loadPaperTradingFees(paperManager: PaperTradingManager) {
        let totalVolume = paperManager.totalVolumeTraded
        guard totalVolume > 0 else {
            feeData = nil
            return
        }
        
        // Paper trading doesn't have real fees, but we can show estimated fees
        // based on typical exchange rates
        let tradingFeeRate = 0.001 // 0.1% typical maker fee
        let estimatedTradingFees = totalVolume * tradingFeeRate
        
        // Estimate network fees (simplified - would vary by asset)
        let networkFeePerTrade = 0.50 // $0.50 average per trade
        let estimatedNetworkFees = Double(paperManager.totalTradeCount) * networkFeePerTrade
        
        let totalFees = estimatedTradingFees + estimatedNetworkFees
        
        feeData = FeeData(fees: [
            FeeItem(label: "Trading Fees (est.)", pct: totalFees > 0 ? estimatedTradingFees / totalFees : 0.5),
            FeeItem(label: "Network Fees (est.)", pct: totalFees > 0 ? estimatedNetworkFees / totalFees : 0.5)
        ])
    }
}
