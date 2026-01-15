import SwiftUI

struct RiskReportView: View {
    let result: RiskScanResult?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                header
                
                if let result = result {
                    ScrollView {
                        VStack(spacing: 24) {
                            summaryRow(result: result)
                            highlightsSection(highlights: result.highlights)
                            metricsSection(result: result)
                        }
                        .padding(.horizontal)
                    }
                } else {
                    placeholderView
                        .padding()
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
            .navigationTitle("Risk Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .foregroundColor(.white)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.fill")
                .foregroundColor(.green)
                .font(.title2)
            Text("Risk Report")
                .font(.title2)
                .fontWeight(.semibold)
        }
        .padding(.top, 12)
    }
    
    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.slash")
                .font(.system(size: 70, weight: .medium))
                .foregroundColor(.secondary)
            Text("No scan results available.")
                .font(.headline)
            Text("Run a risk scan to see detailed analysis and metrics here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func summaryRow(result: RiskScanResult) -> some View {
        HStack {
            Spacer()
            RiskRingBadge(level: result.level,
                          score: result.score,
                          progress: CGFloat(result.score) / 100)
                .frame(width: 96, height: 96)
            Spacer()
        }
    }
    
    private func highlightsSection(highlights: [RiskScanResult.Highlight]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Highlights")
                .font(.headline)
                .padding(.bottom, 4)
            
            if highlights.isEmpty {
                Text("No notable risks detected.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(highlights.indices, id: \.self) { idx in
                    let highlight = highlights[idx]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(highlight.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(highlight.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        SeverityPill(severity: highlight.severity)
                    }
                    .padding(.vertical, 6)
                    Divider()
                        .background(Color.white.opacity(0.1))
                }
            }
        }
    }
    
    private func metricsSection(result: RiskScanResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metrics")
                .font(.headline)
                .padding(.bottom, 4)
            
            HStack(spacing: 16) {
                metricItem(label: "Top Weight", value: formatPercent(result.topWeight))
                metricItem(label: "HHI", value: formatNumber(result.hhi))
                metricItem(label: "Stablecoin", value: formatPercent(result.stablecoinWeight))
            }
            
            HStack(spacing: 16) {
                metricItem(label: "Volatility", value: formatPercent(result.volatility))
                metricItem(label: "Max Drawdown", value: formatPercent(result.maxDrawdown))
                metricItem(label: "Illiquid Count", value: "\(result.illiquidCount)")
            }
        }
    }
    
    private func metricItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .fontWeight(.semibold)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
    
    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
}

fileprivate struct SeverityPill: View {
    let severity: Int
    
    private var color: Color {
        switch severity {
        case 0..<3:
            return .green
        case 3..<7:
            return .yellow
        default:
            return .red
        }
    }
    
    private var label: String {
        switch severity {
        case 0..<3:
            return "Low"
        case 3..<7:
            return "Medium"
        default:
            return "High"
        }
    }
    
    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - Preview & Sample Data

#if DEBUG
import Foundation

// Minimal mock of RiskScanResult and related types to allow preview compilation
struct RiskScanResult {
    struct Highlight {
        let title: String
        let detail: String
        let severity: Int
    }
    
    let level: Int
    let score: Int
    let highlights: [Highlight]
    let topWeight: Double
    let hhi: Double
    let stablecoinWeight: Double
    let volatility: Double
    let maxDrawdown: Double
    let illiquidCount: Int
}

// Minimal mock RiskRingBadge to allow preview compilation
struct RiskRingBadge: View {
    let level: Int
    let score: Int
    let progress: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 8)
                .opacity(0.2)
                .foregroundColor(.green)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .foregroundColor(progress > 0.66 ? .red : (progress > 0.33 ? .yellow : .green))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.title2)
                .bold()
                .foregroundColor(.white)
        }
    }
}

#Preview {
    RiskReportView(result: RiskScanResult(
        level: 2,
        score: 73,
        highlights: [
            RiskScanResult.Highlight(title: "Unstable Liquidity", detail: "High volatility detected in recent assets", severity: 6),
            RiskScanResult.Highlight(title: "Concentration Risk", detail: "Top asset weight exceeds recommended limit", severity: 4),
            RiskScanResult.Highlight(title: "Illiquid Assets", detail: "A few assets have low liquidity", severity: 3)
        ],
        topWeight: 0.42,
        hhi: 1120,
        stablecoinWeight: 0.15,
        volatility: 0.27,
        maxDrawdown: 0.35,
        illiquidCount: 2
    ))
}
#endif
