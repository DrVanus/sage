//
//  PortfolioWidget.swift
//  CryptoSageWidget
//
//  Portfolio summary widget showing total value and top holdings.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct PortfolioProvider: TimelineProvider {
    typealias Entry = PortfolioEntry
    
    func placeholder(in context: Context) -> PortfolioEntry {
        PortfolioEntry(date: Date(), portfolio: WidgetDataProvider.shared.getPortfolioData())
    }
    
    func getSnapshot(in context: Context, completion: @escaping (PortfolioEntry) -> Void) {
        let entry = PortfolioEntry(date: Date(), portfolio: WidgetDataProvider.shared.getPortfolioData())
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<PortfolioEntry>) -> Void) {
        let portfolio = WidgetDataProvider.shared.getPortfolioData()
        let currentDate = Date()
        
        let entry = PortfolioEntry(date: currentDate, portfolio: portfolio)
        
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct PortfolioEntry: TimelineEntry {
    let date: Date
    let portfolio: WidgetPortfolioData
}

// MARK: - Widget View

struct PortfolioWidgetEntryView: View {
    var entry: PortfolioProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            smallView
        }
    }
    
    // MARK: - Small Widget
    
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("Portfolio")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            Spacer()
            
            // Total value
            Text(entry.portfolio.formattedTotal)
                .font(.system(size: 26, weight: .bold))
                .minimumScaleFactor(0.7)
            
            // Change
            HStack(spacing: 4) {
                Image(systemName: entry.portfolio.isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                
                Text(entry.portfolio.formattedChange)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(entry.portfolio.isPositive ? .green : .red)
        }
        .padding()
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    entry.portfolio.isPositive ? Color.green.opacity(0.1) : Color.red.opacity(0.1),
                    Color(UIColor.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // MARK: - Medium Widget
    
    private var mediumView: some View {
        HStack(spacing: 16) {
            // Left side - total value
            VStack(alignment: .leading, spacing: 6) {
                Text("Portfolio")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text(entry.portfolio.formattedTotal)
                    .font(.system(size: 28, weight: .bold))
                
                HStack(spacing: 4) {
                    Image(systemName: entry.portfolio.isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                    
                    Text(entry.portfolio.formattedChange)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(entry.portfolio.isPositive ? .green : .red)
            }
            
            Spacer()
            
            // Right side - top holdings
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(entry.portfolio.topHoldings.prefix(3)) { holding in
                    HStack(spacing: 8) {
                        Text(holding.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        
                        Text("\(Int(holding.percentage))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(UIColor.systemBackground)
        }
    }
    
    // MARK: - Large Widget
    
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Text(entry.portfolio.formattedTotal)
                        .font(.system(size: 32, weight: .bold))
                }
                
                Spacer()
                
                // Change badge
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: entry.portfolio.isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                        
                        Text(entry.portfolio.formattedChange)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(entry.portfolio.isPositive ? .green : .red)
                    
                    Text("24h")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Holdings list
            Text("Top Holdings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            ForEach(entry.portfolio.topHoldings) { holding in
                HStack {
                    // Symbol with background
                    Text(holding.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 50, alignment: .leading)
                    
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * CGFloat(holding.percentage) / 100)
                        }
                    }
                    .frame(height: 8)
                    
                    // Percentage
                    Text("\(Int(holding.percentage))%")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.vertical, 4)
            }
            
            Spacer()
            
            // Last update
            Text("Updated \(entry.portfolio.lastUpdate, style: .relative) ago")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(UIColor.systemBackground)
        }
    }
}

// MARK: - Widget Configuration

struct PortfolioWidget: Widget {
    let kind: String = "PortfolioWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PortfolioProvider()) { entry in
            PortfolioWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Portfolio")
        .description("Track your portfolio value and top holdings at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    PortfolioWidget()
} timeline: {
    PortfolioEntry(date: Date(), portfolio: WidgetPortfolioData(
        totalValue: 12500,
        change24h: 350,
        changePercent: 2.8,
        topHoldings: [
            WidgetHolding(id: "btc", symbol: "BTC", value: 8500, percentage: 68),
            WidgetHolding(id: "eth", symbol: "ETH", value: 2500, percentage: 20),
            WidgetHolding(id: "sol", symbol: "SOL", value: 1500, percentage: 12)
        ],
        lastUpdate: Date()
    ))
}
