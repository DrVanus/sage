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
    @Published var remainingRefreshes: Int
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

    private let maxFreeRefreshes = 3
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

        // Initialize remaining refreshes based on storedUses
        self.remainingRefreshes = max(maxFreeRefreshes - storedUses, 0)
    }

    /// Fetches the placeholder summary metrics, replacing them once data is ready
    func fetchSummaryMetrics() {
        // Replace with real async fetch logic as needed
        let work = DispatchWorkItem {
            self.summaryMetrics = [
                SummaryMetric(iconName: "chart.line.uptrend.xyaxis", valueText: "8%", title: "vs BTC"),
                SummaryMetric(iconName: "shield.fill",               valueText: "7/10", title: "Risk Score"),
                SummaryMetric(iconName: "rosette",                   valueText: "75%", title: "Win Rate")
            ]
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Refreshes the AI insight, enforcing free-tier limits
    /// - Parameter portfolio: An Encodable model of the user's portfolio
    @MainActor
    func refresh<T: Encodable>(using portfolio: T) async {
        // Uncomment to enforce free-tier limits
        // guard remainingRefreshes > 0 else {
        //     errorMessage = "Free insight limit reached. Upgrade for unlimited use."
        //     return
        // }

        isLoading = true
        defer { isLoading = false }

        // Demo stub insight messages with richer, portfolio-aware phrasing
        let fakeInsights = [
            "Your Bitcoin allocation is 45% of your portfolio. Consider reallocating 5–10% into Ethereum (up 6% this week) or Solana (12% MoM) for better diversification.",
            "This week, your overall portfolio returned 7%, outpacing the crypto market’s 4% gain. You’ve capitalized on the latest bullish momentum.",
            "Ethereum gas fees spiked 15% recently, which could eat into your ETH trading profits. Try scheduling transactions during off-peak hours.",
            "Volatility Alert: Your holdings swung ±3% in the last 24 hours as market sentiment shifted. Setting dynamic stop-loss orders might protect gains.",
            "Solana, one of your smaller positions, outperformed with a 12% month-to-date rise. You may want to rebalance to lock in those profits.",
            "Your top three holdings contributed 60% of your gains this month. Reviewing mid-cap altcoins like Cardano or Polkadot could uncover new opportunities."
        ]

        // Choose a new insight, ensuring it differs from the current one
        var nextText = fakeInsights.randomElement()!
        if nextText == insight?.text {
            nextText = fakeInsights.first { $0 != insight?.text } ?? nextText
        }

        // Assign the stub insight and update timestamp
        insight = AIInsight(text: nextText, timestamp: Date())

        // Update usage count
        usesToday += 1
        remainingRefreshes = maxFreeRefreshes - usesToday
    }
}
