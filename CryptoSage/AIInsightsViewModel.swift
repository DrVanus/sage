//
//  AIInsightsViewModel.swift
//  CryptoSage
//
//  Supporting model types for AI insight views.
//

import SwiftUI

// MARK: - Supporting Models

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
    let histogramBins: [Int]
    var isUnrealized: Bool = false
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
    let weight: Double
}

struct MomentumData {
    let strategies: [StrategyMomentum]
}

struct StrategyMomentum: Identifiable {
    let id = UUID()
    let name: String
    let score: Double
}

struct FeeData {
    let fees: [FeeItem]
}

struct FeeItem: Identifiable {
    let id = UUID()
    let label: String
    let pct: Double
}
