//
//  FearGreedWidget.swift
//  CryptoSageWidget
//
//  Fear & Greed Index widget showing current market sentiment.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct FearGreedProvider: TimelineProvider {
    typealias Entry = FearGreedEntry
    
    func placeholder(in context: Context) -> FearGreedEntry {
        FearGreedEntry(date: Date(), fearGreed: WidgetDataProvider.shared.getFearGreedData())
    }
    
    func getSnapshot(in context: Context, completion: @escaping (FearGreedEntry) -> Void) {
        let entry = FearGreedEntry(date: Date(), fearGreed: WidgetDataProvider.shared.getFearGreedData())
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<FearGreedEntry>) -> Void) {
        let fearGreed = WidgetDataProvider.shared.getFearGreedData()
        let currentDate = Date()
        
        let entry = FearGreedEntry(date: currentDate, fearGreed: fearGreed)
        
        // Refresh every hour (Fear & Greed doesn't change that often)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct FearGreedEntry: TimelineEntry {
    let date: Date
    let fearGreed: WidgetFearGreedData
}

// MARK: - Widget View

struct FearGreedWidgetEntryView: View {
    var entry: FearGreedProvider.Entry
    @Environment(\.widgetFamily) var family
    
    private var sentimentColor: Color {
        switch entry.fearGreed.value {
        case 0..<25: return .red
        case 25..<45: return .orange
        case 45..<55: return .yellow
        case 55..<75: return .green
        default: return .green.opacity(0.8)
        }
    }
    
    var body: some View {
        switch family {
        case .systemSmall:
            smallView
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
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("Market Sentiment")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            Spacer()
            
            // Gauge
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.red, .orange, .yellow, .green]),
                            center: .center,
                            startAngle: .degrees(135),
                            endAngle: .degrees(405)
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(90))
                
                VStack(spacing: 2) {
                    Text("\(entry.fearGreed.value)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(sentimentColor)
                    
                    Text(entry.fearGreed.sentiment)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(UIColor.systemBackground)
        }
    }
    
    // MARK: - Lock Screen Widgets
    
    private var circularView: some View {
        ZStack {
            Circle()
                .stroke(sentimentColor.opacity(0.3), lineWidth: 4)
            
            Circle()
                .trim(from: 0, to: CGFloat(entry.fearGreed.value) / 100)
                .stroke(sentimentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            Text("\(entry.fearGreed.value)")
                .font(.system(size: 18, weight: .bold))
        }
        .containerBackground(for: .widget) { Color.clear }
    }
    
    private var rectangularView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fear & Greed")
                    .font(.system(size: 12, weight: .semibold))
                
                Text(entry.fearGreed.sentiment)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(entry.fearGreed.value)")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(sentimentColor)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Widget Configuration

struct FearGreedWidget: Widget {
    let kind: String = "FearGreedWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FearGreedProvider()) { entry in
            FearGreedWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Fear & Greed")
        .description("Monitor market sentiment with the Fear & Greed Index.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    FearGreedWidget()
} timeline: {
    FearGreedEntry(date: Date(), fearGreed: WidgetFearGreedData(value: 72, classification: "Greed", timestamp: Date()))
    FearGreedEntry(date: Date(), fearGreed: WidgetFearGreedData(value: 25, classification: "Fear", timestamp: Date()))
}
