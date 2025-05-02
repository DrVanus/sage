//
//  AIInsightsViewModel.swift
//  CryptoSage
//
//  Created by DM on 5/31/25.
//


// AIInsightsViewModel.swift

import SwiftUI
import Combine

final class AIInsightsViewModel: ObservableObject {
    // MARK: - Published properties for each section
    @Published var summaryMetrics: [SummaryMetric] = []
    @Published var performanceData: [PerformancePoint] = []
    @Published var contributors: [Contributor] = []
    @Published var tradeQualityData: TradeQualityData?
    @Published var diversificationData: DiversificationData?
    @Published var momentumData: MomentumData?
    @Published var feeData: FeeData?
    
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    
    // Section‐expanded state could also live here (optional)
    @Published var isPerformanceExpanded = false
    @Published var isQualityExpanded = false
    @Published var isDiversificationExpanded = false
    @Published var isMomentumExpanded = false
    @Published var isFeeExpanded = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        fetchAllInsights()
    }
    
    func fetchAllInsights() {
        isLoading = true
        errorMessage = nil
        
        // Example: Asynchronously compute or fetch from your AI backend
        // Replace this with your real networking or AI‐compute logic.
        Just(())
            .delay(for: .seconds(1.0), scheduler: DispatchQueue.main)  // simulate delay
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Populate mock data for demonstration
                self.summaryMetrics = [
                    SummaryMetric(iconName: "chart.line.uptrend.xyaxis", valueText: "8%",  title: "vs BTC"),
                    SummaryMetric(iconName: "shield.fill",               valueText: "7/10", title: "Risk Score"),
                    SummaryMetric(iconName: "rosette",                   valueText: "75%",  title: "Win Rate")
                ]
                // Example performance points
                self.performanceData = (0..<30).map { i in
                    PerformancePoint(date: Calendar.current.date(byAdding: .day, value: -i, to: Date())!,
                                     value: Double.random(in: 90_000...110_000))
                }.reversed()
                self.contributors = [ // replace with real contributor data
                    Contributor(name: "BTC", contribution: 0.4),
                    Contributor(name: "ETH", contribution: 0.3),
                    Contributor(name: "SOL", contribution: 0.15),
                    Contributor(name: "ADA", contribution: 0.15)
                ]
                self.tradeQualityData = TradeQualityData(bestTrade: Trade(symbol: "SOL", profitPct: 12.3),
                                                         worstTrade: Trade(symbol: "DOGE", profitPct: -8.5),
                                                         histogramBins: [0,0,1,3,5,2,1])
                self.diversificationData = DiversificationData(percentages: [
                    AssetWeight(asset: "BTC", weight: 0.5),
                    AssetWeight(asset: "ETH", weight: 0.3),
                    AssetWeight(asset: "SOL", weight: 0.2)
                ])
                self.momentumData = MomentumData(strategies: [
                    StrategyMomentum(name: "Trend Follow", score: 0.7),
                    StrategyMomentum(name: "Mean Reversion", score: 0.4),
                    StrategyMomentum(name: "Breakout", score: 0.6)
                ])
                self.feeData = FeeData(fees: [
                    FeeItem(label: "Network Fees", pct: 0.015),
                    FeeItem(label: "Slippage", pct: 0.005)
                ])
                
                self.isLoading = false
            }
            .store(in: &cancellables)
    }
}

// MARK: - Supporting Models (replace these with your real types)
struct PerformancePoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct Contributor: Identifiable {
    let id = UUID()
    let name: String
    let contribution: Double   // e.g., 0.4 means 40%
}

struct TradeQualityData {
    let bestTrade: Trade
    let worstTrade: Trade
    let histogramBins: [Int]   // Example distribution
}

struct Trade {
    let symbol: String
    let profitPct: Double
}

struct DiversificationData {
    let percentages: [AssetWeight]
}
struct AssetWeight: Identifiable {
    let id = UUID()
    let asset: String
    let weight: Double   // 0.5 means 50% of portfolio
}

struct MomentumData {
    let strategies: [StrategyMomentum]
}
struct StrategyMomentum: Identifiable {
    let id = UUID()
    let name: String
    let score: Double   // e.g., 0.7 means 70% momentum
}

struct FeeData {
    let fees: [FeeItem]
}
struct FeeItem: Identifiable {
    let id = UUID()
    let label: String   // e.g. “Network Fees”
    let pct: Double     // e.g. 0.015 means 1.5% of total fees
}
