//
//  BacktestResultsView.swift
//  CryptoSage
//
//  Displays backtest results with equity curve chart,
//  performance metrics, and trade history.
//

import SwiftUI
import Charts

// MARK: - Backtest Results View

struct BacktestResultsView: View {
    let result: BacktestResult
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Performance grade header
                    performanceGradeHeader
                    
                    // Key metrics cards
                    keyMetricsGrid
                    
                    // Equity curve chart
                    equityCurveSection
                    
                    // Tab selector for detailed views
                    Picker("View", selection: $selectedTab) {
                        Text("Metrics").tag(0)
                        Text("Trades").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    if selectedTab == 0 {
                        detailedMetricsSection
                    } else {
                        tradeHistorySection
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.top, 8)
            }
            .background(DS.Adaptive.background)
            .navigationTitle("Backtest Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(BrandColors.goldBase)
                }
            }
        }
    }
    
    // MARK: - Performance Grade Header
    
    private var performanceGradeHeader: some View {
        VStack(spacing: 12) {
            // Grade circle
            ZStack {
                Circle()
                    .stroke(gradeColor.opacity(0.3), lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: gradeProgress)
                    .stroke(gradeColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                
                Text(result.performanceGrade)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(gradeColor)
            }
            
            Text(gradeDescription)
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            // Return summary
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text(result.netProfitLoss >= 0 ? "+$\(result.netProfitLoss, specifier: "%.2f")" : "-$\(abs(result.netProfitLoss), specifier: "%.2f")")
                        .font(.title3.weight(.bold))
                        .foregroundColor(result.netProfitLoss >= 0 ? .green : .red)
                    Text("Net P/L")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Divider()
                    .frame(height: 30)
                
                VStack(spacing: 2) {
                    Text("\(result.totalReturnPercent >= 0 ? "+" : "")\(result.totalReturnPercent, specifier: "%.1f")%")
                        .font(.title3.weight(.bold))
                        .foregroundColor(result.totalReturnPercent >= 0 ? .green : .red)
                    Text("Return")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Divider()
                    .frame(height: 30)
                
                VStack(spacing: 2) {
                    Text("\(result.totalTrades)")
                        .font(.title3.weight(.bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text("Trades")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    private var gradeColor: Color {
        switch result.performanceGrade {
        case "A": return .green
        case "B": return .blue
        case "C": return .orange
        case "D": return .orange
        default: return .red
        }
    }
    
    private var gradeProgress: CGFloat {
        switch result.performanceGrade {
        case "A": return 0.95
        case "B": return 0.80
        case "C": return 0.65
        case "D": return 0.50
        default: return 0.30
        }
    }
    
    private var gradeDescription: String {
        switch result.performanceGrade {
        case "A": return "Excellent Strategy"
        case "B": return "Good Strategy"
        case "C": return "Average Strategy"
        case "D": return "Below Average"
        default: return "Needs Improvement"
        }
    }
    
    // MARK: - Key Metrics Grid
    
    private var keyMetricsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            metricCard(
                title: "Win Rate",
                value: String(format: "%.1f%%", result.winRate),
                icon: "target",
                color: result.winRate >= 50 ? .green : .orange
            )
            
            metricCard(
                title: "Profit Factor",
                value: result.profitFactor.isInfinite ? "∞" : String(format: "%.2f", result.profitFactor),
                icon: "chart.bar.fill",
                color: result.profitFactor >= 1.5 ? .green : (result.profitFactor >= 1 ? .orange : .red)
            )
            
            metricCard(
                title: "Sharpe Ratio",
                value: String(format: "%.2f", result.sharpeRatio),
                icon: "waveform.path",
                color: result.sharpeRatio >= 1 ? .green : (result.sharpeRatio >= 0.5 ? .orange : .red)
            )
            
            metricCard(
                title: "Max Drawdown",
                value: String(format: "%.1f%%", result.maxDrawdownPercent),
                icon: "arrow.down.right",
                color: result.maxDrawdownPercent <= 10 ? .green : (result.maxDrawdownPercent <= 20 ? .orange : .red)
            )
        }
        .padding(.horizontal)
    }
    
    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundColor(DS.Adaptive.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Equity Curve Section
    
    private var equityCurveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Equity Curve")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal)
            
            if result.equityCurve.count > 1 {
                Chart {
                    ForEach(Array(result.equityCurve.enumerated()), id: \.offset) { index, point in
                        LineMark(
                            x: .value("Time", index),
                            y: .value("Equity", point.equity)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [BrandColors.goldBase, BrandColors.goldLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .interpolationMethod(.monotone)
                        
                        AreaMark(
                            x: .value("Time", index),
                            y: .value("Equity", point.equity)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    BrandColors.goldBase.opacity(0.3),
                                    BrandColors.goldBase.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)
                    }
                    
                    // Initial balance reference line
                    RuleMark(y: .value("Initial", result.initialBalance))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        if let equity = value.as(Double.self) {
                            AxisValueLabel {
                                Text("$\(Int(equity))")
                                    .font(.caption2)
                                    .foregroundColor(DS.Adaptive.textSecondary)
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 200)
                .padding()
                .background(DS.Adaptive.cardBackground)
                .cornerRadius(14)
                .padding(.horizontal)
            } else {
                Text("No equity data available")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
    
    // MARK: - Detailed Metrics Section
    
    private var detailedMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Returns section
            metricsGroup(title: "Returns", items: [
                ("Initial Balance", String(format: "$%.2f", result.initialBalance)),
                ("Final Balance", String(format: "$%.2f", result.finalBalance)),
                ("Total Return", String(format: "%@%.2f%%", result.totalReturnPercent >= 0 ? "+" : "", result.totalReturnPercent)),
                ("Annualized Return", String(format: "%@%.2f%%", result.annualizedReturn >= 0 ? "+" : "", result.annualizedReturn))
            ])
            
            // Trade statistics
            metricsGroup(title: "Trade Statistics", items: [
                ("Total Trades", "\(result.totalTrades)"),
                ("Winning Trades", "\(result.winningTrades)"),
                ("Losing Trades", "\(result.losingTrades)"),
                ("Win Rate", String(format: "%.1f%%", result.winRate)),
                ("Avg Holding Period", String(format: "%.1f days", result.averageHoldingDays))
            ])
            
            // Risk metrics
            metricsGroup(title: "Risk Metrics", items: [
                ("Max Drawdown", String(format: "%.2f%%", result.maxDrawdownPercent)),
                ("Max Consecutive Losses", "\(result.maxConsecutiveLosses)"),
                ("Sharpe Ratio", String(format: "%.2f", result.sharpeRatio)),
                ("Sortino Ratio", String(format: "%.2f", result.sortinoRatio))
            ])
            
            // Win/Loss analysis
            metricsGroup(title: "Win/Loss Analysis", items: [
                ("Average Win", String(format: "+$%.2f", result.averageWin)),
                ("Average Loss", String(format: "-$%.2f", abs(result.averageLoss))),
                ("Largest Win", String(format: "+$%.2f", result.largestWin)),
                ("Largest Loss", String(format: "-$%.2f", abs(result.largestLoss))),
                ("Profit Factor", result.profitFactor.isInfinite ? "∞" : String(format: "%.2f", result.profitFactor))
            ])
        }
        .padding(.horizontal)
    }
    
    private func metricsGroup(title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack {
                        Text(item.0)
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Spacer()
                        Text(item.1)
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    
                    if index < items.count - 1 {
                        Divider()
                    }
                }
            }
            .background(DS.Adaptive.cardBackground)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Trade History Section
    
    private var tradeHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trade History")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal)
            
            if result.trades.isEmpty {
                Text("No trades executed")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(result.trades) { trade in
                        TradeHistoryRow(trade: trade)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Trade History Row

struct TradeHistoryRow: View {
    let trade: BacktestTrade
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Win/Loss indicator
            Circle()
                .fill(trade.isWinner ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(trade.exitReason)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Spacer()
                    
                    Text(trade.profitLoss >= 0 ? "+$\(trade.profitLoss, specifier: "%.2f")" : "-$\(abs(trade.profitLoss), specifier: "%.2f")")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundColor(trade.isWinner ? .green : .red)
                }
                
                HStack {
                    Text("\(dateFormatter.string(from: trade.entryDate)) → \(dateFormatter.string(from: trade.exitDate))")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Spacer()
                    
                    Text("\(trade.returnPercent >= 0 ? "+" : "")\(trade.returnPercent, specifier: "%.1f")%")
                        .font(.caption.weight(.medium))
                        .foregroundColor(trade.isWinner ? .green : .red)
                }
                
                HStack {
                    Text("Entry: $\(trade.entryPrice, specifier: "%.2f")")
                    Text("→")
                    Text("Exit: $\(trade.exitPrice, specifier: "%.2f")")
                }
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
        .padding(12)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(10)
    }
}

// MARK: - Backtest Running View

struct BacktestRunningView: View {
    @ObservedObject var engine = BacktestEngine.shared
    let strategyName: String
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Progress indicator
            ZStack {
                Circle()
                    .stroke(DS.Adaptive.overlay(0.1), lineWidth: 8)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: engine.progress)
                    .stroke(BrandColors.goldBase, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: engine.progress)
                
                Text("\(Int(engine.progress * 100))%")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            Text("Running Backtest")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text(strategyName)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Text("Analyzing historical data...")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(DS.Adaptive.background)
    }
}

// MARK: - Preview

#if DEBUG
struct BacktestResultsView_Previews: PreviewProvider {
    static var previews: some View {
        // Create sample result
        var result = BacktestResult(
            strategyId: UUID(),
            strategyName: "RSI Oversold Strategy",
            tradingPair: "BTC_USDT",
            startDate: Date().addingTimeInterval(-86400 * 30),
            endDate: Date(),
            initialBalance: 10000
        )
        result.finalBalance = 12500
        result.totalTrades = 15
        result.winningTrades = 10
        result.losingTrades = 5
        result.winRate = 66.7
        result.totalReturnPercent = 25
        result.maxDrawdownPercent = 8.5
        result.sharpeRatio = 1.85
        result.profitFactor = 2.3
        
        return BacktestResultsView(result: result)
            .preferredColorScheme(.dark)
    }
}
#endif
