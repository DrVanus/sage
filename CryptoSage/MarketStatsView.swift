//
//  MarketStatsView.swift
//  CryptoSage
//
//  Created by DM on 5/19/25.
//

import SwiftUI

// MARK: - MarketStatsView

struct MarketStatsView: View {
    @ObservedObject var statsVM = MarketStatsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if statsVM.stats.count >= 6 {
                HStack(spacing: 16) {
                    StatItemView(iconName: "globe", title: "Market Cap", value: statsVM.stats[0].value)
                    StatItemView(iconName: "bitcoinsign.circle.fill", title: "BTC Dom", value: statsVM.stats[2].value)
                    StatItemView(customImage: Image("eth-logo"), title: "ETH Dom", value: statsVM.stats[3].value)
                }
                HStack(spacing: 16) {
                    StatItemView(iconName: "clock", title: "24h Volume", value: statsVM.stats[1].value)
                    StatItemView(iconName: "waveform.path.ecg", title: "24h Volatility", value: statsVM.stats[4].value)
                    StatItemView(iconName: "arrow.up.arrow.down.circle", title: "24h Change", value: statsVM.stats[5].value)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground).opacity(0.05))
        )
        .onAppear {
            Task {
                await statsVM.fetchStats()
            }
        }
    }
}

// MARK: - StatItemView

struct StatItemView: View {
    let iconName: String?
    let customImage: Image?
    let title: String
    let value: String

    init(iconName: String, title: String, value: String) {
        self.iconName = iconName
        self.customImage = nil
        self.title = title
        self.value = value
    }

    init(customImage: Image, title: String, value: String) {
        self.iconName = nil
        self.customImage = customImage
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .center, spacing: 1) {
            if let customImage = customImage {
                customImage
                    .resizable()
                    .scaledToFit()
                    .frame(height: 20)
            } else if let iconName = iconName {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(.yellow)
            }
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline).bold()
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
    }
}
