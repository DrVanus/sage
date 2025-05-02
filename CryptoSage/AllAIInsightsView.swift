//
//  AllAIInsightsView.swift
//  CryptoSage
//
//  Created by DM on 5/31/25.
//


import SwiftUI

struct AllAIInsightsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel = AIInsightViewModel()
    @StateObject private var portfolioVM = PortfolioViewModel(repository: PortfolioRepository())
    
    var body: some View {
        VStack(spacing: 0) {
            // 1) Top navigation bar
            topNavBar
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // 2) Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // 2a) Summary cards with placeholder when loading
                    summaryCardScroll
                    
                    // 2b) Performance & Attribution (custom expand/collapse)
                    VStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.isPerformanceExpanded.toggle()
                            }
                        }) {
                            sectionHeader(title: "Performance & Attribution")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .foregroundColor(.white)

                        if viewModel.isPerformanceExpanded {
                            performanceContent
                                .padding(.top, 8)
                                .padding(.horizontal, 16)
                        }
                    }
                    
                    // 2c) Trade Quality & Timing (custom expand/collapse)
                    VStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.isQualityExpanded.toggle()
                            }
                        }) {
                            sectionHeader(title: "Trade Quality & Timing")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .foregroundColor(.white)

                        if viewModel.isQualityExpanded {
                            qualityContent
                                .padding(.top, 8)
                                .padding(.horizontal, 16)
                        }
                    }
                    
                    // 2d) Diversification & Risk (custom expand/collapse)
                    VStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.isDiversificationExpanded.toggle()
                            }
                        }) {
                            sectionHeader(title: "Diversification & Risk")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .foregroundColor(.white)

                        if viewModel.isDiversificationExpanded {
                            diversificationContent
                                .padding(.top, 8)
                                .padding(.horizontal, 16)
                        }
                    }
                    
                    // 2e) Momentum Analysis (custom expand/collapse)
                    VStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.isMomentumExpanded.toggle()
                            }
                        }) {
                            sectionHeader(title: "Momentum Analysis")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .foregroundColor(.white)

                        if viewModel.isMomentumExpanded {
                            momentumContent
                                .padding(.top, 8)
                                .padding(.horizontal, 16)
                        }
                    }
                    
                    // 2f) Fee Breakdown (custom expand/collapse)
                    VStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.isFeeExpanded.toggle()
                            }
                        }) {
                            sectionHeader(title: "Fee Breakdown")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .foregroundColor(.white)

                        if viewModel.isFeeExpanded {
                            feeContent
                                .padding(.top, 8)
                                .padding(.horizontal, 16)
                        }
                    }
                    
                    Spacer(minLength: 30)
                }
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .all)
        .foregroundColor(.white)
        .onAppear {
            // Trigger ViewModel to fetch summary metrics
            viewModel.fetchSummaryMetrics()
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
    }
}


// MARK: - COMPONENTS
private extension AllAIInsightsView {
    
    // Top navigation bar with back button, title, and timestamp
    var topNavBar: some View {
        HStack {
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            .padding(.leading, 16)
            
            Spacer()
            
            Text("All AI Insights")
                .font(.headline)
            
            Spacer()
            
            Text(DateFormatter.shortTime.string(from: Date()))
                .font(.subheadline)
                .foregroundColor(Color(.systemGray2))
                .padding(.trailing, 16)
        }
        .padding(.top, UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0)
        .padding(.bottom, 8)
        .background(Color.black)
        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 2)
    }
    
    // Horizontal scroll of summary metric cards (with placeholders)
    var summaryCardScroll: some View {
        Group {
            if viewModel.summaryMetrics.isEmpty {
                // Show placeholder cards while there’s no real data
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        // Display three placeholder cards
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.darkGray).opacity(0.8))
                                .frame(width: 120, height: 110)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 110)
                .padding(.bottom, 16)
            } else {
                // Real summary metrics
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(viewModel.summaryMetrics, id: \.id) { metric in
                            summaryCard(metric: metric)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 110)
                .padding(.bottom, 16)
            }
        }
    }
    
    // Single summary card (icon + value + label)
    func summaryCard(metric: SummaryMetric) -> some View {
        VStack(spacing: 8) {
            Image(systemName: metric.iconName)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Color.yellow)
            
            Text(metric.valueText)
                .font(.title2)
                .bold()
                .foregroundColor(.white)
            
            Text(metric.title)
                .font(.caption)
                .foregroundColor(Color(.systemGray2))
        }
        .padding()
        .frame(width: 120, height: 100)
        .background(Color(.darkGray).opacity(0.8))
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        .cornerRadius(10)
    }
    
    // Standard header for each DisclosureGroup
    func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .bold()
                .foregroundColor(.white)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(isSectionExpanded(title) ? 90 : 270))
                .animation(.easeInOut(duration: 0.2), value: isSectionExpanded(title))
                .font(.caption)
                .foregroundColor(.white)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(.darkGray).opacity(0.6))
        .cornerRadius(10)
    }
    
    // Helper to toggle the chevron direction
    func isSectionExpanded(_ title: String) -> Bool {
        switch title {
        case "Performance & Attribution": return viewModel.isPerformanceExpanded
        case "Trade Quality & Timing":   return viewModel.isQualityExpanded
        case "Diversification & Risk":    return viewModel.isDiversificationExpanded
        case "Momentum Analysis":         return viewModel.isMomentumExpanded
        case "Fee Breakdown":             return viewModel.isFeeExpanded
        default:                          return false
        }
    }
    
    // Performance & Attribution content
    var performanceContent: some View {
        VStack(spacing: 14) {
            PortfolioChartView(
                portfolioVM: portfolioVM,
                showMetrics: true,
                showSelector: false,
                chartMode: .constant(.line)
            )
            .frame(height: 180)
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("Top Contributors")
                    .font(.caption)
                    .foregroundColor(Color(.systemGray2))
                    .padding(.horizontal, 12)

                ForEach(viewModel.contributors) { contributor in
                    HStack {
                        Text(contributor.name)
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%.0f%%", contributor.contribution * 100))
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.darkGray).opacity(0.6))
                    .cornerRadius(8)
                }
            }
            .frame(height: 120)
            .background(Color.black)
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.vertical, 0)
        }
    }
    
    // Trade Quality & Timing content
    var qualityContent: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best Trade")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text("\(viewModel.tradeQualityData?.bestTrade.symbol ?? "---"): \(String(format: "%.1f%%", viewModel.tradeQualityData?.bestTrade.profitPct ?? 0))")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Spacer()
                    Text("Worst Trade")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text("\(viewModel.tradeQualityData?.worstTrade.symbol ?? "---"): \(String(format: "%.1f%%", viewModel.tradeQualityData?.worstTrade.profitPct ?? 0))")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .padding()
                .frame(width: UIScreen.main.bounds.width/2 - 40, height: 120)
                .background(Color(.darkGray).opacity(0.6))
                .cornerRadius(10)
                .padding(.vertical, 12)

                VStack(alignment: .center) {
                    Text("P/L Distribution")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))

                    HStack {
                        Spacer()
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(viewModel.tradeQualityData?.histogramBins.indices ?? 0..<0, id: \.self) { idx in
                                let count = viewModel.tradeQualityData?.histogramBins[idx] ?? 0
                                Rectangle()
                                    .fill(Color.yellow)
                                    .frame(width: 8, height: CGFloat(count) * 10)
                            }
                        }
                        .frame(height: 80)
                        Spacer()
                    }
                }
                .frame(width: UIScreen.main.bounds.width/2 - 40, height: 120)
                .background(Color(.darkGray).opacity(0.6))
                .cornerRadius(10)
                .padding(.vertical, 12)
            }
        }
    }
    
    // Diversification & Risk content
    var diversificationContent: some View {
        VStack(spacing: 14) {
            ThemedPortfolioPieChartView(portfolioVM: portfolioVM)
                .frame(height: 180)
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if let topAsset = viewModel.diversificationData?.percentages.max(by: { $0.weight < $1.weight }),
               topAsset.weight > 0.6 {
                Text("⚠️ Concentration Warning: \(Int(topAsset.weight * 100))% in \(topAsset.asset)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                    .padding(.horizontal, 16)
            } else {
                Text("Diversification levels are healthy.")
                    .font(.caption)
                    .foregroundColor(Color(.systemGray2))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
    }
    
    // Momentum Analysis content (refined)
    var momentumContent: some View {
        VStack(spacing: 12) {
            // Centered title
            Text("Momentum Scores")
                .font(.subheadline)
                .bold()
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
            
            GeometryReader { geo in
                ZStack {
                    // Horizontal grid lines at 50% and 100% (and bottom)
                    ForEach([0.0, 0.5, 1.0], id: \.self) { fraction in
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 1)
                            .offset(y: geo.size.height * (1 - CGFloat(fraction)))
                    }
                    
                    // Bars and labels, centered horizontally
                    HStack(alignment: .bottom, spacing: 24) {
                        let maxScore = (viewModel.momentumData?.strategies.map { $0.score }.max() ?? 1)
                        ForEach(viewModel.momentumData?.strategies ?? []) { strategy in
                            VStack(spacing: 4) {
                                // Numeric value above each bar
                                Text(String(format: "%.0f", strategy.score * 100))
                                    .font(.caption2)
                                    .bold()
                                    .foregroundColor(.white)
                                
                                // Bar rectangle with subtle shadow
                                Rectangle()
                                    .fill(LinearGradient(
                                        gradient: Gradient(colors: [Color.green.opacity(0.8), Color.green]),
                                        startPoint: .bottom,
                                        endPoint: .top
                                    ))
                                    .frame(
                                        width: 44,
                                        height: maxScore > 0
                                            ? (CGFloat(strategy.score) / CGFloat(maxScore)) * (geo.size.height * 0.6)
                                            : 0
                                    )
                                    .cornerRadius(4)
                                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                                
                                // Strategy name label (single line)
                                Text(strategy.name)
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                                    .frame(width: 60)
                            }
                            .frame(minWidth: 60)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .frame(height: 200)
        }
        .background(Color(.darkGray).opacity(0.6))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // Fee Breakdown content
    var feeContent: some View {
        VStack(spacing: 14) {
            ForEach(viewModel.feeData?.fees ?? []) { feeItem in
                HStack {
                    Text(feeItem.label)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(String(format: "%.2f%%", feeItem.pct * 100))
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.darkGray).opacity(0.6))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}





// MARK: - DATEFORMATTER EXTENSION
fileprivate extension DateFormatter {
    static let shortTime: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df
    }()
}


// MARK: - PREVIEW
struct AllAIInsightsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AllAIInsightsView()
                .preferredColorScheme(.dark)
            
            AllAIInsightsView()
                .preferredColorScheme(.light)
        }
    }
}
