//
//  AgentSignalFeedView.swift
//  CryptoSage
//
//  Displays real-time AI agent trading signals with composite scores,
//  technical indicators, and market regime info.
//

import SwiftUI

// MARK: - Signal Feed View

struct AgentSignalFeedView: View {
    @ObservedObject private var agentService = AgentConnectionService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if agentService.latestSignals.isEmpty {
                    emptyState
                } else {
                    ForEach(agentService.latestSignals) { signal in
                        AgentSignalCard(signal: signal)
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
        }
        .background(DS.Adaptive.background)
        .navigationTitle("Agent Signals")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            Text("No signals yet")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            Text("Signals appear after the agent runs a market scan")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Signal Card

struct AgentSignalCard: View {
    let signal: AgentSignal
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: symbol + signal + score
            HStack {
                Text(signal.symbol)
                    .font(.title3.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)

                Text(signal.signalDisplayName)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(signal.signalColor)
                    .clipShape(Capsule())

                Spacer()

                // Composite score gauge
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                        .frame(width: 40, height: 40)
                    Circle()
                        .trim(from: 0, to: signal.composite_score / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(signal.composite_score))")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
            }

            // Indicators row
            HStack(spacing: 12) {
                if let fg = signal.fear_greed_index {
                    indicatorPill(
                        label: "F&G",
                        value: "\(Int(fg))",
                        color: fearGreedColor(fg)
                    )
                }

                if let rsi = signal.rsi {
                    indicatorPill(
                        label: "RSI",
                        value: String(format: "%.0f", rsi),
                        color: rsi < 30 ? .green : (rsi > 70 ? .red : .gray)
                    )
                }

                if let trend = signal.primary_trend {
                    indicatorPill(
                        label: "Trend",
                        value: trend.capitalized,
                        color: trend.lowercased() == "bullish" ? .green : (trend.lowercased() == "bearish" ? .red : .gray)
                    )
                }

                if let conf = signal.confidence {
                    indicatorPill(
                        label: "Conf",
                        value: conf.capitalized,
                        color: conf == "high" ? .green : (conf == "low" ? .orange : .gray)
                    )
                }
            }

            // Reasoning
            if let reasoning = signal.reasoning, !reasoning.isEmpty {
                Text(reasoning)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(showDetail ? nil : 2)
                    .onTapGesture { withAnimation { showDetail.toggle() } }
            }

            // Timestamp
            HStack {
                if let ts = signal.timestamp {
                    Text(ts, style: .relative)
                        .font(.caption2)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }

                Spacer()

                if let risk = signal.risk_score {
                    Text("Risk: \(Int(risk))/100")
                        .font(.caption2)
                        .foregroundColor(risk > 60 ? .orange : DS.Adaptive.textTertiary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(signal.signalColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func indicatorPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
            Text(value)
                .font(.caption2.weight(.semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var scoreColor: Color {
        if signal.composite_score >= 65 { return .green }
        if signal.composite_score >= 45 { return .gray }
        return .red
    }

    private func fearGreedColor(_ index: Double) -> Color {
        if index <= 25 { return .red }
        if index <= 45 { return .orange }
        if index <= 55 { return .gray }
        if index <= 75 { return .green }
        return .green
    }
}

// MARK: - Compact Signal Card (for HomeView)

struct AgentSignalCompactCard: View {
    let signal: AgentSignal

    var body: some View {
        HStack(spacing: 10) {
            // Signal indicator
            VStack(spacing: 2) {
                Text("\(Int(signal.composite_score))")
                    .font(.title3.weight(.bold))
                    .foregroundColor(scoreColor)
                Text("Score")
                    .font(.system(size: 8))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(signal.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)

                    Text(signal.signalDisplayName)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(signal.signalColor)
                        .clipShape(Capsule())
                }

                if let reasoning = signal.reasoning, !reasoning.isEmpty {
                    Text(reasoning)
                        .font(.caption2)
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                )
        )
    }

    private var scoreColor: Color {
        if signal.composite_score >= 65 { return .green }
        if signal.composite_score >= 45 { return .gray }
        return .red
    }
}

#Preview {
    NavigationStack {
        AgentSignalFeedView()
    }
}
