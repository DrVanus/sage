//
//  MarketStatsViewModel.swift
//  CryptoSage
//
//  Created by DM on 5/20/25.
//

import Foundation

/// Represents a single stat for display.
public struct Stat: Identifiable {
    public let id = UUID()
    public let title: String
    public let value: String
    public let iconName: String
}

@MainActor
public class MarketStatsViewModel: ObservableObject {
    @Published public private(set) var stats: [Stat] = []

    public init() {
        Task { await fetchStats() }
    }

    /// Fetches global market stats from CoinGecko’s global endpoint.
    public func fetchStats() async {
        print("▶️ fetchStats() called")
        do {
            // 1) Build URL and fetch data
            guard let url = URL(string: "https://api.coingecko.com/api/v3/global") else {
                print("❌ Invalid global URL")
                return
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("❌ HTTP error fetching global data: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            // 2) Decode wrapper and extract data
            let wrapper = try JSONDecoder().decode(GlobalMarketDataWrapper.self, from: data)
            let d = wrapper.data
            // 3) Map into Stat models
            let fetched: [Stat] = [
                Stat(title: "Market Cap",      value: formatCurrency(d.totalMarketCap["usd"] ?? 0),             iconName: "globe"),
                Stat(title: "24h Volume",     value: formatCurrency(d.totalVolume["usd"] ?? 0),                  iconName: "clock"),
                Stat(title: "BTC Dom",        value: String(format: "%.2f%%", d.marketCapPercentage["btc"] ?? 0), iconName: "bitcoinsign.circle.fill"),
                Stat(title: "ETH Dom",        value: String(format: "%.2f%%", d.marketCapPercentage["eth"] ?? 0), iconName: "chart.bar.fill"),
                Stat(title: "Active Cryptos", value: formatNumber(d.activeCryptocurrencies),                       iconName: "cube.box.fill"),
                Stat(title: "Markets",        value: formatNumber(d.markets),                                         iconName: "chart.bar.xaxis"),
                Stat(title: "24h Change",     value: String(format: "%.2f%%", d.marketCapChangePercentage24HUsd),    iconName: "arrow.up.arrow.down.circle")
            ]
            // 4) Publish on main actor
            await MainActor.run {
                self.stats = fetched
                print("✅ Stats loaded with \(fetched.count) items")
            }
        } catch {
            print("❌ Failed fetching stats:", error)
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ v: Double) -> String {
        switch v {
        case 1_000_000_000_000...: return String(format: "$%.2fT", v/1_000_000_000_000)
        case 1_000_000_000...: return String(format: "$%.2fB", v/1_000_000_000)
        case 1_000_000...: return String(format: "$%.2fM", v/1_000_000)
        default:
            let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
            return f.string(from: v as NSNumber) ?? "$\(v)"
        }
    }

    private func formatNumber(_ v: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: v as NSNumber) ?? "\(v)"
    }
}

/// JSON wrapper for CoinGecko global endpoint
private struct GlobalMarketDataWrapper: Decodable {
    let data: GlobalMarketData
}
