//
//  MarketScannerView.swift
//  CryptoSage
//
//  AI Market Scanner - scans top coins for technical signals.
//  Uses existing TechnicalsEngine to identify buy/sell opportunities.
//

import SwiftUI

// MARK: - Signal Model
struct CoinSignal: Identifiable {
    let id: String
    let coin: MarketCoin
    let signal: SignalType
    let rsi: Double?
    let macdHistogram: Double?
    let score: Double // 0-1, higher = stronger buy
    
    enum SignalType: Comparable {
        case strongBuy, buy, neutral, sell, strongSell
        
        var label: String {
            switch self {
            case .strongBuy: return "Strong Buy"
            case .buy: return "Buy"
            case .neutral: return "Neutral"
            case .sell: return "Sell"
            case .strongSell: return "Strong Sell"
            }
        }
        
        var shortLabel: String {
            switch self {
            case .strongBuy: return "Strong Buy"
            case .buy: return "Buy"
            case .neutral: return "Hold"
            case .sell: return "Sell"
            case .strongSell: return "Strong Sell"
            }
        }
        
        var color: Color {
            switch self {
            case .strongBuy: return .mint
            case .buy: return .green
            case .neutral: return .yellow
            case .sell: return .orange
            case .strongSell: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .strongBuy: return "arrow.up.circle.fill"
            case .buy: return "arrow.up.circle"
            case .neutral: return "minus.circle"
            case .sell: return "arrow.down.circle"
            case .strongSell: return "arrow.down.circle.fill"
            }
        }
        
        // For sorting: strongBuy (0) to strongSell (4)
        var sortOrder: Int {
            switch self {
            case .strongBuy: return 0
            case .buy: return 1
            case .neutral: return 2
            case .sell: return 3
            case .strongSell: return 4
            }
        }
    }
}

// MARK: - Tab Selection
enum ScannerTab: Int, CaseIterable {
    case all = 0
    case bullish = 1
    case bearish = 2
    
    var title: String {
        switch self {
        case .all: return "All"
        case .bullish: return "Bullish"
        case .bearish: return "Bearish"
        }
    }
}

// MARK: - ViewModel
@MainActor
final class MarketScannerViewModel: ObservableObject {
    @Published var allSignals: [CoinSignal] = []
    @Published var isScanning: Bool = false
    @Published var lastScanAt: Date? = nil
    @Published var errorMessage: String? = nil
    @Published var scanProgress: Double = 0
    
    private let maxCoinsToScan = 50
    
    var bullishSignals: [CoinSignal] {
        allSignals.filter { $0.signal == .strongBuy || $0.signal == .buy }
            .sorted { $0.score > $1.score }
    }
    
    var bearishSignals: [CoinSignal] {
        allSignals.filter { $0.signal == .strongSell || $0.signal == .sell }
            .sorted { $0.score < $1.score }
    }
    
    // Stats for header
    var bullishCount: Int { bullishSignals.count }
    var bearishCount: Int { bearishSignals.count }
    var neutralCount: Int { allSignals.filter { $0.signal == .neutral }.count }
    
    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        scanProgress = 0
        
        // Get top coins from MarketViewModel
        let coins = Array(MarketViewModel.shared.allCoins
            .filter { $0.priceUsd != nil && $0.priceUsd! > 0 }
            .prefix(maxCoinsToScan))
        
        guard !coins.isEmpty else {
            errorMessage = "No market data available. Pull to refresh."
            isScanning = false
            return
        }
        
        var signals: [CoinSignal] = []
        let total = Double(coins.count)
        
        for (index, coin) in coins.enumerated() {
            // Update progress
            scanProgress = Double(index + 1) / total
            
            // Use sparkline data as price history for technicals
            let closes = coin.sparklineIn7d.filter { $0 > 0 && $0.isFinite }
            
            // PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing across all views
            let price = MarketViewModel.shared.bestPrice(for: coin.id) ?? coin.priceUsd ?? closes.last ?? 0
            guard price > 0 else { continue }
            
            // Calculate indicators (with fallbacks for insufficient data)
            let rsi = closes.count >= 15 ? TechnicalsEngine.rsi(closes) : nil
            let macdHist = closes.count >= 26 ? TechnicalsEngine.macdHistogram(closes) : nil
            let score: Double
            
            if closes.count >= 26 {
                score = TechnicalsEngine.aggregateScore(price: price, closes: closes)
            } else if closes.count >= 10 {
                // Simple score based on recent price action
                let recent = Array(closes.suffix(10))
                let avg = recent.reduce(0, +) / Double(recent.count)
                score = price > avg ? 0.6 : (price < avg ? 0.4 : 0.5)
            } else {
                score = 0.5 // Neutral for coins with no sparkline
            }
            
            // Determine signal type using relaxed criteria
            let signalType = determineSignal(rsi: rsi, macdHist: macdHist, score: score)
            
            signals.append(CoinSignal(
                id: coin.id,
                coin: coin,
                signal: signalType,
                rsi: rsi,
                macdHistogram: macdHist,
                score: score
            ))
            
            // Small delay to show progress animation
            if index % 5 == 0 {
                try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
            }
        }
        
        // Sort all signals by score (best buys first)
        allSignals = signals.sorted { $0.score > $1.score }
        lastScanAt = Date()
        isScanning = false
    }
    
    private func determineSignal(rsi: Double?, macdHist: Double?, score: Double) -> CoinSignal.SignalType {
        // Score-based primary signal (more lenient)
        if score >= 0.7 {
            // Check for strong buy confirmation
            if let r = rsi, r < 35 {
                return .strongBuy
            }
            return .buy
        } else if score >= 0.55 {
            if let r = rsi, r < 40, let m = macdHist, m > 0 {
                return .buy
            }
            return .neutral
        } else if score <= 0.3 {
            if let r = rsi, r > 65 {
                return .strongSell
            }
            return .sell
        } else if score <= 0.45 {
            if let r = rsi, r > 60, let m = macdHist, m < 0 {
                return .sell
            }
            return .neutral
        }
        
        return .neutral
    }
}

// MARK: - Main View
struct MarketScannerView: View {
    @StateObject private var vm = MarketScannerViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ScannerTab = .all
    @State private var selectedScannerCoin: MarketCoin? = nil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Stats Header
                if !vm.isScanning && !vm.allSignals.isEmpty {
                    statsHeader
                }
                
                // Tab Picker
                Picker("Signal Type", selection: $selectedTab) {
                    ForEach(ScannerTab.allCases, id: \.rawValue) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // Content
                if vm.isScanning {
                    scanningView
                } else if let error = vm.errorMessage {
                    errorView(message: error)
                } else {
                    signalList
                }
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("AI Market Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await vm.scan() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isScanning)
                }
            }
            .navigationDestination(item: $selectedScannerCoin) { coin in
                CoinDetailView(coin: coin)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .task {
            if vm.allSignals.isEmpty {
                await vm.scan()
            }
        }
    }
    
    // MARK: - Stats Header
    private var statsHeader: some View {
        HStack(spacing: 16) {
            StatPill(count: vm.bullishCount, label: "Bullish", color: .green)
            StatPill(count: vm.neutralCount, label: "Neutral", color: .yellow)
            StatPill(count: vm.bearishCount, label: "Bearish", color: .red)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Scanning View
    private var scanningView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(DS.Adaptive.stroke, lineWidth: 4)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: vm.scanProgress)
                    .stroke(Color.csGoldSolid, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: vm.scanProgress)
                
                VStack(spacing: 2) {
                    Text("\(Int(vm.scanProgress * 100))%")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    Text("Scanning")
                        .font(.caption)
                        .foregroundStyle(DS.Adaptive.textSecondary)
                }
            }
            
            Text("Analyzing \(vm.allSignals.count > 0 ? "\(vm.allSignals.count)" : "top") coins...")
                .font(.subheadline)
                .foregroundStyle(DS.Adaptive.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error View
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await vm.scan() }
            }
            .buttonStyle(CSGoldButtonStyle())
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Signal List
    private var signalList: some View {
        let signals: [CoinSignal] = {
            switch selectedTab {
            case .all: return vm.allSignals
            case .bullish: return vm.bullishSignals
            case .bearish: return vm.bearishSignals
            }
        }()
        
        return Group {
            if signals.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(signals) { signal in
                            Button {
                                selectedScannerCoin = signal.coin
                            } label: {
                                SignalRow(signal: signal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    
                    if let lastScan = vm.lastScanAt {
                        Text("Last scan: \(lastScan, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(DS.Adaptive.textTertiary)
                            .padding(.bottom, 16)
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.flattrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(DS.Adaptive.textTertiary)
            Text("No \(selectedTab.title.lowercased()) signals found")
                .font(.subheadline)
                .foregroundStyle(DS.Adaptive.textSecondary)
            if let lastScan = vm.lastScanAt {
                Text("Last scan: \(lastScan, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(DS.Adaptive.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Stat Pill
private struct StatPill: View {
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(DS.Adaptive.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(DS.Adaptive.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DS.Adaptive.cardBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(DS.Adaptive.stroke, lineWidth: 1))
    }
}

// MARK: - Signal Row
private struct SignalRow: View {
    let signal: CoinSignal
    
    var body: some View {
        HStack(spacing: 12) {
            // Coin icon
            CoinImageView(symbol: signal.coin.symbol, url: signal.coin.imageUrl, size: 40)
                .clipShape(Circle())
            
            // Coin info
            VStack(alignment: .leading, spacing: 2) {
                Text(signal.coin.symbol.uppercased())
                    .font(.headline)
                    .foregroundStyle(DS.Adaptive.textPrimary)
                Text(signal.coin.name)
                    .font(.caption)
                    .foregroundStyle(DS.Adaptive.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Score gauge
            ScoreGauge(score: signal.score)
            
            // Signal badge
            SignalBadge(signal: signal.signal)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(signal.signal.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Score Gauge
private struct ScoreGauge: View {
    let score: Double
    @State private var animatedScore: Double = 0
    
    private var gaugeColor: Color {
        if animatedScore >= 0.6 { return .green }
        if animatedScore <= 0.4 { return .red }
        return .yellow
    }
    
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(DS.Adaptive.stroke, lineWidth: 3)
                    .frame(width: 32, height: 32)
                
                Circle()
                    .trim(from: 0, to: GaugeMotionProfile.clampUnit(animatedScore))
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(GaugeMotionProfile.clampUnit(animatedScore) * 100))")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(gaugeColor)
            }
            Text("Score")
                .font(.system(size: 8))
                .foregroundStyle(DS.Adaptive.textTertiary)
        }
        .onAppear {
            withAnimation(GaugeMotionProfile.fill) {
                animatedScore = score
            }
        }
        .onChange(of: score) { _, newScore in
            withAnimation(GaugeMotionProfile.fill) {
                animatedScore = newScore
            }
        }
    }
}

// MARK: - Signal Badge
private struct SignalBadge: View {
    let signal: CoinSignal.SignalType
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: signal.icon)
                .font(.caption)
        }
        .foregroundStyle(signal.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(signal.color.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Preview
#if DEBUG
struct MarketScannerView_Previews: PreviewProvider {
    static var previews: some View {
        MarketScannerView()
            .preferredColorScheme(.dark)
    }
}
#endif
