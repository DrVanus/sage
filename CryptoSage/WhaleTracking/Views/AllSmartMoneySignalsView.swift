//
//  AllSmartMoneySignalsView.swift
//  CryptoSage
//
//  Full view for all smart money signals with filtering and sorting.
//

import SwiftUI

struct AllSmartMoneySignalsView: View {
    let signals: [SmartMoneySignal]
    let index: SmartMoneyIndex?
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: SmartMoneyCategory? = nil
    @State private var selectedSentiment: TransactionSentiment? = nil
    @State private var sortOrder: SortOrder = .newest
    
    // Use @State instead of computed property for stable scrolling
    @State private var displayedSignals: [SmartMoneySignal] = []
    
    enum SortOrder: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case largestAmount = "Largest"
        case highestConfidence = "Confidence"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Adaptive.background.ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 16, pinnedViews: []) {
                        // Smart Money Index Summary
                        if let index = index {
                            indexSummaryCard(index)
                                .id("header")
                        }
                        
                        // Filter Bar - pinned section
                        filterBar
                            .id("filters")
                        
                        // Signals List
                        if displayedSignals.isEmpty {
                            emptyState
                                .id("empty")
                        } else {
                            signalsList
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Smart Money Signals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    CSNavButton(icon: "xmark", action: { dismiss() }, accessibilityText: "Close", compact: true)
                }
            }
            .onAppear {
                updateDisplayedSignals()
            }
            .onChange(of: selectedCategory) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    updateDisplayedSignals()
                }
            }
            .onChange(of: selectedSentiment) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    updateDisplayedSignals()
                }
            }
            .onChange(of: sortOrder) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    updateDisplayedSignals()
                }
            }
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
        }
    }
    
    // MARK: - Update Displayed Signals
    
    private func updateDisplayedSignals() {
        var result = signals
        
        // Filter by category
        if let category = selectedCategory {
            result = result.filter { $0.wallet.category == category }
        }
        
        // Filter by sentiment
        if let sentiment = selectedSentiment {
            result = result.filter { $0.signalType.sentiment == sentiment }
        }
        
        // Sort
        switch sortOrder {
        case .newest:
            result.sort { $0.timestamp > $1.timestamp }
        case .oldest:
            result.sort { $0.timestamp < $1.timestamp }
        case .largestAmount:
            result.sort { $0.transaction.amountUSD > $1.transaction.amountUSD }
        case .highestConfidence:
            result.sort { $0.confidence > $1.confidence }
        }
        
        displayedSignals = result
    }
    
    // MARK: - Index Summary Card
    
    private func indexSummaryCard(_ index: SmartMoneyIndex) -> some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "dollarsign.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Money Index")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Last updated \(index.lastUpdated, style: .relative) ago")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                
                Spacer()
                
                // Score badge
                VStack(spacing: 2) {
                    Text("\(index.score)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(index.trend.color)
                    
                    Text(index.trend.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(index.trend.color)
                }
            }
            
            // Gauge
            SmartMoneyGauge(index: index)
            
            // Stats row
            HStack(spacing: 0) {
                statItem(count: index.bullishSignals, label: "Bullish", color: .green)
                
                Divider()
                    .frame(height: 30)
                
                statItem(count: index.neutralSignals, label: "Neutral", color: .gray)
                
                Divider()
                    .frame(height: 30)
                
                statItem(count: index.bearishSignals, label: "Bearish", color: .red)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.05), Color.blue.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private func statItem(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Filter Bar
    
    private var filterBar: some View {
        VStack(spacing: 8) {
            // Scrollable filter buttons to prevent gesture conflicts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Category filter
                    Menu {
                        Button("All Categories") {
                            selectedCategory = nil
                        }
                        
                        Divider()
                        
                        ForEach(SmartMoneyCategory.allCases, id: \.rawValue) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                Label(category.rawValue, systemImage: category.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if let category = selectedCategory {
                                Image(systemName: category.icon)
                                    .foregroundStyle(category.color)
                            }
                            Text(selectedCategory?.rawValue ?? "All Categories")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(selectedCategory != nil ? DS.Adaptive.textPrimary : DS.Adaptive.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedCategory != nil ? selectedCategory!.color.opacity(0.15) : DS.Adaptive.chipBackground)
                        )
                        .overlay(
                            Capsule()
                                .stroke(selectedCategory != nil ? selectedCategory!.color.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Capsule())
                    }
                    
                    // Sentiment filter
                    Menu {
                        Button("All Sentiments") {
                            selectedSentiment = nil
                        }
                        
                        Divider()
                        
                        ForEach([TransactionSentiment.bullish, .bearish, .neutral], id: \.rawValue) { sentiment in
                            Button {
                                selectedSentiment = sentiment
                            } label: {
                                Label(sentiment.rawValue, systemImage: sentiment.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if let sentiment = selectedSentiment {
                                Image(systemName: sentiment.icon)
                                    .foregroundStyle(sentiment.color)
                            }
                            Text(selectedSentiment?.rawValue ?? "All Sentiments")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(selectedSentiment != nil ? DS.Adaptive.textPrimary : DS.Adaptive.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedSentiment != nil ? selectedSentiment!.color.opacity(0.15) : DS.Adaptive.chipBackground)
                        )
                        .overlay(
                            Capsule()
                                .stroke(selectedSentiment != nil ? selectedSentiment!.color.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Capsule())
                    }
                    
                    Spacer(minLength: 8)
                    
                    // Sort order
                    Menu {
                        ForEach(SortOrder.allCases, id: \.rawValue) { order in
                            Button {
                                sortOrder = order
                            } label: {
                                HStack {
                                    Text(order.rawValue)
                                    if sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortOrder.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(DS.Adaptive.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(DS.Adaptive.chipBackground)
                        )
                        .contentShape(Capsule())
                    }
                }
                .padding(.horizontal, 1) // Prevent clipping
            }
            
            // Results count
            HStack {
                Text("\(displayedSignals.count) signals")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Spacer()
                
                if selectedCategory != nil || selectedSentiment != nil {
                    Button {
                        selectedCategory = nil
                        selectedSentiment = nil
                    } label: {
                        Text("Clear filters")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Signals List
    
    private var signalsList: some View {
        ForEach(displayedSignals) { signal in
            ExpandedSmartMoneySignalRow(signal: signal)
                .id(signal.id) // Explicit stable ID
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dollarsign.arrow.circlepath")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple.opacity(0.5), .blue.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 6) {
                Text("No signals match filters")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Try adjusting your filter criteria")
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Button {
                selectedCategory = nil
                selectedSentiment = nil
            } label: {
                Text("Clear Filters")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Expanded Signal Row

struct ExpandedSmartMoneySignalRow: View {
    let signal: SmartMoneySignal
    @State private var showTransactionDetail: Bool = false
    
    var body: some View {
        Button {
            showTransactionDetail = true
        } label: {
            VStack(spacing: 12) {
                // Header row
                HStack(spacing: 12) {
                    // Enhanced category icon with gradient ring
                    ZStack {
                        // Outer glow ring
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [signal.wallet.category.color.opacity(0.5), signal.wallet.category.color.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 48, height: 48)
                        
                        // Inner circle
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [signal.wallet.category.color.opacity(0.2), signal.wallet.category.color.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: signal.wallet.category.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [signal.wallet.category.color, signal.wallet.category.color.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    
                    // Wallet info
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(signal.wallet.label)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                                .lineLimit(1)
                            
                            // Enhanced ROI badge
                            if let roi = signal.wallet.historicalROI {
                                HStack(spacing: 2) {
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("+\(Int(roi))%")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.green.opacity(0.15))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.green.opacity(0.3), lineWidth: 0.5)
                                )
                            }
                        }
                        
                        HStack(spacing: 6) {
                            // Category
                            Text(signal.wallet.category.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(signal.wallet.category.color)
                            
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            
                            // Blockchain
                            HStack(spacing: 3) {
                                CoinImageView(symbol: signal.wallet.blockchain.symbol, url: nil, size: 14)
                                Text(signal.wallet.blockchain.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(signal.wallet.blockchain.color)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Amount
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatLargeAmount(signal.transaction.amountUSD))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text(formatRelativeTime(signal.timestamp))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                
                // Signal type and confidence
                HStack(spacing: 12) {
                    // Signal type badge
                    HStack(spacing: 5) {
                        Image(systemName: signal.signalType.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(signal.signalType.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(signal.signalType.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(signal.signalType.color.opacity(0.15))
                    )
                    .overlay(
                        Capsule()
                            .stroke(signal.signalType.color.opacity(0.25), lineWidth: 0.5)
                    )
                    
                    Spacer()
                    
                    // Enhanced Confidence meter
                    HStack(spacing: 6) {
                        Text("Confidence")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        // Animated bar visualization
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(DS.Adaptive.chipBackground)
                                
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [confidenceColor.opacity(0.8), confidenceColor],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * (signal.confidence / 100))
                            }
                        }
                        .frame(width: 60, height: 6)
                        
                        Text("\(Int(signal.confidence))%")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(confidenceColor)
                    }
                }
                
                // Transaction details preview
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(signal.transaction.shortFromAddress)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(signal.signalType.color)
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("To")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(signal.transaction.shortToAddress)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.top, 4)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [signal.signalType.color.opacity(0.3), DS.Adaptive.stroke],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(WhaleCardButtonStyle())
        .sheet(isPresented: $showTransactionDetail) {
            WhaleTransactionDetailView(transaction: signal.transaction)
                .presentationDetents([.medium, .large])
        }
    }
    
    private var confidenceColor: Color {
        if signal.confidence >= 70 {
            return .green
        } else if signal.confidence >= 40 {
            return .orange
        }
        return .red
    }
    
    private func formatLargeAmount(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "$%.2fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.1fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            let mins = (seconds % 3600) / 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h ago"
        } else {
            return "\(seconds / 86400)d ago"
        }
    }
}

#Preview {
    AllSmartMoneySignalsView(
        signals: [],
        index: SmartMoneyIndex(
            score: 72,
            trend: .bullish,
            bullishSignals: 4,
            bearishSignals: 2,
            neutralSignals: 0,
            lastUpdated: Date()
        )
    )
    .preferredColorScheme(.dark)
}
