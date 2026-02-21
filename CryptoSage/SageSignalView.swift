//
//  SageSignalView.swift
//  CryptoSage
//
//  User-facing UI components for CryptoSage AI signals.
//  Displays algorithm recommendations, consensus, and regime analysis.
//

import SwiftUI

// MARK: - Sage Signal Card (Main HomeView Component)

/// Main card displaying CryptoSage AI signal for a symbol
/// Designed to be added to HomeView
struct SageSignalCard: View {
    let symbol: String
    let consensus: SageConsensus?
    let isLoading: Bool
    
    @State private var showingDetail = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "brain")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BrandColors.goldBase)
                
                Text("CryptoSage AI")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let consensus = consensus {
                    RegimePill(regime: consensus.regime)
                }
            }
            
            if let consensus = consensus {
                // Signal display
                HStack(spacing: 16) {
                    // Signal type with icon
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: consensus.masterSignal.icon)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(consensus.masterSignal.color)
                            
                            Text(consensus.masterSignal.displayName)
                                .font(.title2.weight(.bold))
                                .foregroundColor(consensus.masterSignal.color)
                        }
                        
                        Text("\(Int(consensus.confidence))% confidence")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Algorithm agreement
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(consensus.bullishCount)/5")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(consensus.bullishCount > consensus.bearishCount ? .green : .red)
                        
                        Text("algorithms agree")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
                
                // Explanation
                Text(consensus.explanation)
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(3)
                
                // Actions
                HStack(spacing: 12) {
                    Button {
                        showingDetail = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.bar.doc.horizontal")
                            Text("Details")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(BrandColors.goldBase)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(BrandColors.goldBase.opacity(0.15))
                        .cornerRadius(8)
                    }
                    
                    if PaperTradingManager.isEnabled {
                        Button {
                            paperTradeFromSignal(consensus)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Paper Trade")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(consensus.masterSignal.color)
                            .cornerRadius(8)
                        }
                    }
                    
                    Spacer()
                }
            } else if !isLoading {
                // No signal state
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text("Analyzing market conditions...")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
        }
        .padding(16)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [BrandColors.goldBase.opacity(0.3), BrandColors.goldBase.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .sheet(isPresented: $showingDetail) {
            if let consensus = consensus {
                SageSignalDetailView(consensus: consensus)
            }
        }
    }
    
    private func paperTradeFromSignal(_ consensus: SageConsensus) {
        // Create paper trade based on signal
        // This would integrate with PaperTradingManager
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

// MARK: - Regime Pill

struct RegimePill: View {
    let regime: SageMarketRegime
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: regime.icon)
                .font(.system(size: 10))
            Text(regime.displayName)
                .font(.caption2.weight(.medium))
        }
        .foregroundColor(regime.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(regime.color.opacity(0.15))
        .cornerRadius(12)
    }
}

// MARK: - Signal Detail View

struct SageSignalDetailView: View {
    let consensus: SageConsensus
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header card
                    signalHeaderCard
                    
                    // Algorithm breakdown
                    algorithmBreakdownCard
                    
                    // Risk management
                    riskManagementCard
                    
                    // Individual signals
                    if !consensus.signals.isEmpty {
                        individualSignalsSection
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(16)
            }
            .background(DS.Adaptive.background)
            .navigationTitle("CryptoSage AI Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(BrandColors.goldBase)
                }
            }
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
        }
    }
    
    private var signalHeaderCard: some View {
        VStack(spacing: 16) {
            // Symbol and signal
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(consensus.symbol)
                        .font(.title.weight(.bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    RegimePill(regime: consensus.regime)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: consensus.masterSignal.icon)
                            .font(.system(size: 28, weight: .bold))
                        Text(consensus.masterSignal.displayName)
                            .font(.title2.weight(.bold))
                    }
                    .foregroundColor(consensus.masterSignal.color)
                    
                    Text("\(Int(consensus.confidence))% confidence")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
            
            Divider()
            
            // Explanation
            Text(consensus.explanation)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(16)
    }
    
    private var algorithmBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Algorithm Scores")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            // Score bars
            AlgorithmScoreBar(name: "Sage Trend", score: consensus.trendScore, icon: "chart.line.uptrend.xyaxis")
            AlgorithmScoreBar(name: "Sage Momentum", score: consensus.momentumScore, icon: "bolt.fill")
            AlgorithmScoreBar(name: "Sage Reversion", score: consensus.reversionScore, icon: "arrow.left.arrow.right")
            AlgorithmScoreBar(name: "Sage Confluence", score: consensus.confluenceScore, icon: "clock.badge.checkmark")
            AlgorithmScoreBar(name: "Sage Volatility", score: consensus.volatilityScore, icon: "waveform.path.ecg")
            
            Divider()
            
            // Sentiment
            HStack {
                Image(systemName: "face.smiling")
                    .foregroundColor(.orange)
                Text("Sentiment Score")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                Spacer()
                Text(formatScore(consensus.sentimentScore))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(scoreColor(consensus.sentimentScore))
            }
            
            // Agreement level
            HStack {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                Text("Algorithm Agreement")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                Spacer()
                Text("\(Int(consensus.agreementLevel * 100))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
        }
        .padding(16)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(16)
    }
    
    private var riskManagementCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Risk Management")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            // Position size
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggested Position")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text("\(Int(consensus.suggestedPositionSize))%")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 2) {
                    Text("Stop Loss")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text("-\(String(format: "%.1f", consensus.suggestedStopLoss))%")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Take Profit")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text("+\(String(format: "%.1f", consensus.suggestedTakeProfit))%")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.green)
                }
            }
            
            // Risk/Reward visual
            GeometryReader { geo in
                let total = consensus.suggestedStopLoss + consensus.suggestedTakeProfit
                let riskWidth = geo.size.width * CGFloat(consensus.suggestedStopLoss / total)
                let rewardWidth = geo.size.width * CGFloat(consensus.suggestedTakeProfit / total)
                
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.red.opacity(0.6))
                        .frame(width: riskWidth)
                    Rectangle()
                        .fill(Color.green.opacity(0.6))
                        .frame(width: rewardWidth)
                }
                .frame(height: 8)
                .cornerRadius(4)
            }
            .frame(height: 8)
            
            Text("Risk/Reward: 1:\(String(format: "%.1f", consensus.suggestedTakeProfit / max(consensus.suggestedStopLoss, 0.01)))")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
        }
        .padding(16)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(16)
    }
    
    private var individualSignalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Individual Signals")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            ForEach(consensus.signals) { signal in
                IndividualSignalRow(signal: signal)
            }
        }
        .padding(16)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(16)
    }
    
    private func formatScore(_ score: Double) -> String {
        let prefix = score > 0 ? "+" : ""
        return "\(prefix)\(Int(score))"
    }
    
    private func scoreColor(_ score: Double) -> Color {
        if score > 20 { return .green }
        if score < -20 { return .red }
        return DS.Adaptive.textSecondary
    }
}

// MARK: - Algorithm Score Bar

struct AlgorithmScoreBar: View {
    let name: String
    let score: Double
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(scoreColor)
                .frame(width: 20)
            
            Text(name)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .frame(width: 100, alignment: .leading)
            
            // Score bar
            GeometryReader { geo in
                ZStack(alignment: score >= 0 ? .leading : .trailing) {
                    // Background
                    Rectangle()
                        .fill(DS.Adaptive.stroke)
                        .frame(height: 6)
                    
                    // Score fill
                    let normalizedScore = abs(score) / 100
                    let barWidth = geo.size.width / 2 * CGFloat(normalizedScore)
                    
                    Rectangle()
                        .fill(scoreColor)
                        .frame(width: barWidth, height: 6)
                        .offset(x: score >= 0 ? geo.size.width / 2 : (geo.size.width / 2 - barWidth))
                }
                .cornerRadius(3)
            }
            .frame(height: 6)
            
            Text(formatScore)
                .font(.caption.weight(.semibold))
                .foregroundColor(scoreColor)
                .frame(width: 35, alignment: .trailing)
        }
    }
    
    private var scoreColor: Color {
        if score > 30 { return .green }
        if score < -30 { return .red }
        return .gray
    }
    
    private var formatScore: String {
        let prefix = score > 0 ? "+" : ""
        return "\(prefix)\(Int(score))"
    }
}

// MARK: - Individual Signal Row

struct IndividualSignalRow: View {
    let signal: SageSignal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: signal.category.icon)
                    .foregroundColor(signal.category.color)
                
                Text(signal.algorithmName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: signal.type.icon)
                    Text(signal.type.displayName)
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(signal.type.color)
            }
            
            // Factors
            if !signal.factors.isEmpty {
                Text(signal.factors.joined(separator: " • "))
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(DS.Adaptive.overlay(0.05))
        .cornerRadius(10)
    }
}

// MARK: - Compact Signal Badge (for lists)

struct SageSignalBadge: View {
    let signal: SageSignalType
    let confidence: Double?
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: signal.icon)
                .font(.system(size: 10, weight: .bold))
            
            if let confidence = confidence {
                Text("\(Int(confidence))%")
                    .font(.caption2.weight(.bold))
            }
        }
        .foregroundColor(signal.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(signal.color.opacity(0.15))
        .cornerRadius(6)
    }
}

// MARK: - Preview

#if DEBUG
struct SageSignalCard_Previews: PreviewProvider {
    static var previews: some View {
        let mockConsensus = SageConsensus(
            symbol: "BTC",
            regime: .trending,
            trendScore: 65,
            momentumScore: 45,
            reversionScore: -10,
            confluenceScore: 55,
            volatilityScore: 30,
            sentimentScore: 25,
            masterSignal: .buy,
            confidence: 72,
            explanation: "CryptoSage AI detects a buying opportunity for BTC. Market regime: Trending. 3 of 5 algorithms are bullish. Sage Trend shows strong bullish signal.",
            signals: [],
            suggestedPositionSize: 75,
            suggestedStopLoss: 3.5,
            suggestedTakeProfit: 7.0
        )
        
        VStack(spacing: 20) {
            SageSignalCard(symbol: "BTC", consensus: mockConsensus, isLoading: false)
            SageSignalCard(symbol: "ETH", consensus: nil, isLoading: true)
        }
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
#endif
