//
//  PriceTickerWidget.swift
//  CryptoSageWidget
//
//  Price ticker widget showing a single coin's price and 24h change.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct PriceTickerProvider: TimelineProvider {
    typealias Entry = PriceTickerEntry
    
    func placeholder(in context: Context) -> PriceTickerEntry {
        PriceTickerEntry(date: Date(), coin: WidgetDataProvider.shared.getWatchlistData().first ?? sampleCoin)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (PriceTickerEntry) -> Void) {
        let coins = WidgetDataProvider.shared.getWatchlistData()
        let entry = PriceTickerEntry(date: Date(), coin: coins.first ?? sampleCoin)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<PriceTickerEntry>) -> Void) {
        let coins = WidgetDataProvider.shared.getWatchlistData()
        let currentDate = Date()
        
        // Create entries for each coin in rotation
        var entries: [PriceTickerEntry] = []
        for (index, coin) in coins.prefix(5).enumerated() {
            let entryDate = Calendar.current.date(byAdding: .minute, value: index * 15, to: currentDate)!
            entries.append(PriceTickerEntry(date: entryDate, coin: coin))
        }
        
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private var sampleCoin: WidgetCoinData {
        WidgetCoinData(id: "bitcoin", symbol: "BTC", name: "Bitcoin", price: 94500, change24h: 2.5, imageURL: nil)
    }
}

// MARK: - Timeline Entry

struct PriceTickerEntry: TimelineEntry {
    let date: Date
    let coin: WidgetCoinData
}

// MARK: - Widget View

struct PriceTickerWidgetEntryView: View {
    var entry: PriceTickerProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            smallView
        }
    }
    
    // MARK: - Small Widget
    
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(entry.coin.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Change badge
                Text(entry.coin.formattedChange)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(entry.coin.isPositive ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(entry.coin.isPositive ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    )
            }
            
            Spacer()
            
            // Price
            Text(entry.coin.formattedPrice)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.7)
            
            Text(entry.coin.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding()
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    entry.coin.isPositive ? Color.green.opacity(0.15) : Color.red.opacity(0.15),
                    Color.clear
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }
    
    // MARK: - Medium Widget
    
    private var mediumView: some View {
        HStack(spacing: 16) {
            // Left side - coin info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.coin.symbol)
                        .font(.system(size: 20, weight: .bold))
                    
                    Text(entry.coin.formattedChange)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(entry.coin.isPositive ? .green : .red)
                }
                
                Text(entry.coin.formattedPrice)
                    .font(.system(size: 28, weight: .bold))
                
                Text(entry.coin.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Right side - simple sparkline placeholder
            VStack {
                Image(systemName: entry.coin.isPositive ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(entry.coin.isPositive ? .green : .red)
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(UIColor.systemBackground)
        }
    }
    
    // MARK: - Lock Screen Widgets
    
    private var circularView: some View {
        VStack(spacing: 2) {
            Text(entry.coin.symbol)
                .font(.system(size: 12, weight: .bold))
            
            Text(entry.coin.formattedChange)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(entry.coin.isPositive ? .green : .red)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
    
    private var rectangularView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.coin.symbol)
                    .font(.system(size: 14, weight: .bold))
                Text(entry.coin.formattedPrice)
                    .font(.system(size: 12, weight: .medium))
            }
            
            Spacer()
            
            Text(entry.coin.formattedChange)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(entry.coin.isPositive ? .green : .red)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Widget Configuration

struct PriceTickerWidget: Widget {
    let kind: String = "PriceTickerWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PriceTickerProvider()) { entry in
            PriceTickerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Price Ticker")
        .description("View live price and 24h change for your favorite coins.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    PriceTickerWidget()
} timeline: {
    PriceTickerEntry(date: Date(), coin: WidgetCoinData(id: "bitcoin", symbol: "BTC", name: "Bitcoin", price: 94500, change24h: 2.5, imageURL: nil))
    PriceTickerEntry(date: Date(), coin: WidgetCoinData(id: "ethereum", symbol: "ETH", name: "Ethereum", price: 3350, change24h: -1.2, imageURL: nil))
}
