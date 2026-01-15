// TechnicalsViewModel.swift
// Fetches closes and computes native technicals summary

import Foundation
import Combine
import SwiftUI

@MainActor
final class TechnicalsViewModel: ObservableObject {
    @Published var summary: TechnicalsSummary = TechnicalsSummary(score01: 0.5, verdict: .neutral)
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private var currentTask: Task<Void, Never>? = nil

    func refresh(symbol: String, interval: ChartInterval, currentPrice: Double) {
        currentTask?.cancel()
        errorMessage = nil
        isLoading = true
        let sym = symbol.uppercased()
        currentTask = Task { [weak self] in
            guard let self = self else { return }
            let id = self.coingeckoID(for: sym)
            guard let closes = await self.fetchCloses(coinID: id, interval: interval) else {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Unable to load technicals data"
                }
                return
            }
            let price = max(currentPrice, closes.last ?? 0)
            let score = TechnicalsEngine.aggregateScore(price: price, closes: closes)
            let verdict = self.verdictFor(score: score)
            await MainActor.run {
                self.summary = TechnicalsSummary(score01: score, verdict: verdict)
                self.isLoading = false
            }
        }
    }

    // MARK: - Verdict mapping
    private func verdictFor(score: Double) -> TechnicalVerdict {
        switch score {
        case ..<0.15: return .strongSell
        case ..<0.35: return .sell
        case ..<0.65: return .neutral
        case ..<0.85: return .buy
        default:       return .strongBuy
        }
    }

    // MARK: - Data
    private func fetchCloses(coinID: String, interval: ChartInterval) async -> [Double]? {
        let days = daysForInterval(interval)
        var comps = URLComponents(string: "https://api.coingecko.com/api/v3/coins/\(coinID)/market_chart")
        comps?.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "days", value: String(days))
        ]
        if days <= 90 { comps?.queryItems?.append(URLQueryItem(name: "interval", value: "hourly")) }
        guard let url = comps?.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Resp: Decodable { let prices: [[Double]] }
            let decoded = try JSONDecoder().decode(Resp.self, from: data)
            let closes: [Double] = decoded.prices.compactMap { arr in arr.count >= 2 ? arr[1] : nil }
            if closes.count < 20 { return nil }
            return closes
        } catch {
            return nil
        }
    }

    private func daysForInterval(_ i: ChartInterval) -> Int {
        switch i {
        case .live, .oneMin, .fiveMin, .fifteenMin, .thirtyMin: return 1
        case .oneHour:   return 2
        case .fourHour:  return 7
        case .oneDay:    return 30
        case .oneWeek:   return 365
        case .oneMonth:  return 365
        case .threeMonth: return 365
        case .oneYear:   return 365
        case .threeYear: return 365
        case .all:       return 365
        }
    }

    // Copied mapping similar to PriceViewModel for common tickers
    private func coingeckoID(for symbol: String) -> String {
        switch symbol.uppercased() {
        case "BTC": return "bitcoin"
        case "ETH": return "ethereum"
        case "DOGE": return "dogecoin"
        case "ADA": return "cardano"
        case "SOL": return "solana"
        case "XRP": return "ripple"
        case "DOT": return "polkadot"
        case "MATIC": return "matic-network"
        default: return symbol.lowercased()
        }
    }
}
