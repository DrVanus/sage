//
//  TaxLossHarvestingView.swift
//  CryptoSage
//
//  Tax-loss harvesting opportunities and analysis UI.
//

import SwiftUI

// MARK: - Tax Loss Harvesting View

struct TaxLossHarvestingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var lotManager = TaxLotManager.shared
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    
    @State private var opportunities: [TaxLossHarvestingOpportunity] = []
    @State private var totalPotentialSavings: Double = 0
    @State private var totalHarvestableAmount: Double = 0
    @State private var isLoading = true
    @State private var selectedOpportunity: TaxLossHarvestingOpportunity?
    @State private var filingStatus: FilingStatus = .single
    
    private var themedAccent: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue
    }
    
    private var chipGoldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                FuturisticBackground()
                    .ignoresSafeArea()
                
                if isLoading {
                    ProgressView("Analyzing portfolio...")
                        .foregroundColor(DS.Adaptive.textSecondary)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Summary Card
                            summaryCard
                            
                            // Filing Status Selector
                            filingStatusPicker
                            
                            // Opportunities List
                            if opportunities.isEmpty {
                                emptyState
                            } else {
                                opportunitiesList
                            }
                            
                            // Disclaimer
                            disclaimerSection
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Tax-Loss Harvesting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
            }
            .sheet(item: $selectedOpportunity) { opportunity in
                OpportunityDetailSheet(opportunity: opportunity, filingStatus: filingStatus)
            }
            .task {
                await analyzePortfolio()
            }
        }
    }
    
    // MARK: - Summary Card
    
    private var summaryCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.green.opacity(0.3), .green.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "leaf.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Potential Tax Savings")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Text(formatCurrency(totalPotentialSavings))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
                
                Spacer()
            }
            
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(height: 1)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Harvestable Losses")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text(formatCurrency(totalHarvestableAmount))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Opportunities")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text("\(opportunities.count)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - Filing Status Picker
    
    private var filingStatusPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filing Status (for tax rate calculation)")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            // Horizontal scrolling pill selector - prevents truncation
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilingStatus.allCases, id: \.self) { status in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            filingStatus = status
                            recalculateSavings()
                        } label: {
                            Text(status.shortDisplayName)
                                .font(.system(size: 13, weight: filingStatus == status ? .semibold : .medium))
                                .foregroundColor(filingStatus == status 
                                    ? (colorScheme == .dark ? .black : .white)
                                    : DS.Adaptive.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Group {
                                        if filingStatus == status {
                                            LinearGradient(
                                                colors: colorScheme == .dark
                                                    ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                                    : [.blue, .blue.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        } else {
                                            Color.clear
                                        }
                                    }
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(filingStatus == status 
                                            ? Color.clear 
                                            : DS.Adaptive.stroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - Opportunities List
    
    private var opportunitiesList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Harvesting Opportunities")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            ForEach(opportunities) { opportunity in
                opportunityRow(opportunity)
            }
        }
    }
    
    private func opportunityRow(_ opportunity: TaxLossHarvestingOpportunity) -> some View {
        Button {
            selectedOpportunity = opportunity
        } label: {
            VStack(spacing: 12) {
                HStack {
                    // Symbol with icon
                    HStack(spacing: 8) {
                        Text(opportunity.symbol)
                            .font(.headline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text(opportunity.holdingPeriod)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(opportunity.isShortTerm ? .orange : .blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((opportunity.isShortTerm ? Color.orange : Color.blue).opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatCurrency(opportunity.unrealizedLoss))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        
                        Text("loss")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Price")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Text(formatCurrency(opportunity.currentPrice))
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .center, spacing: 2) {
                        Text("Avg Cost Basis")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Text(formatCurrency(opportunity.averageCostBasis))
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Est. Savings")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Text(formatCurrency(opportunity.estimatedSavings))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                }
                
                // Progress bar showing loss %
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(DS.Adaptive.cardBackgroundElevated)
                            .frame(height: 4)
                        
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: geo.size.width * min(1, opportunity.lossPercent / 100), height: 4)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 4)
                
                HStack {
                    Text("\(String(format: "%.1f", opportunity.lossPercent))% down from cost basis")
                        .font(.caption2)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            .padding(14)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.2), .green.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
            }
            
            Text("No Harvesting Opportunities")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Great news! None of your holdings have unrealized losses significant enough to harvest. Check back when market conditions change.")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
    }
    
    // MARK: - Disclaimer
    
    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("Important Notice")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Tax-loss harvesting involves selling assets at a loss to offset gains. Be aware of the wash-sale rule: if you buy back the same or \"substantially identical\" asset within 30 days, your loss may be disallowed. This is not tax advice - consult a tax professional.")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                
                LinearGradient(
                    colors: [.yellow.opacity(colorScheme == .dark ? 0.1 : 0.05), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Card Background
    
    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
            
            LinearGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.5), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Analysis
    
    private func analyzePortfolio() async {
        isLoading = true
        
        // Get current prices from portfolio
        var currentPrices: [String: Double] = [:]
        for holding in portfolioVM.holdings {
            currentPrices[holding.coinSymbol.uppercased()] = holding.currentPrice
        }
        
        // Also check CoinGecko prices if available
        for symbol in lotManager.symbols {
            if currentPrices[symbol] == nil {
                // Try to get price from LivePriceManager or use 0
                if let price = await fetchPrice(for: symbol) {
                    currentPrices[symbol] = price
                }
            }
        }
        
        // Analyze each symbol
        var newOpportunities: [TaxLossHarvestingOpportunity] = []
        
        for symbol in lotManager.symbols {
            guard let price = currentPrices[symbol], price > 0 else { continue }
            
            let lots = lotManager.availableLots(for: symbol)
            guard !lots.isEmpty else { continue }
            
            let analysis = TaxLossHarvestingAnalysis(symbol: symbol, currentPrice: price, lots: lots)
            
            if analysis.isHarvestingRecommended {
                let taxRate = getTaxRate(for: filingStatus, isShortTerm: !analysis.shortTermLossLots.isEmpty)
                let savings = analysis.estimatedTaxSavings(shortTermRate: taxRate.shortTerm, longTermRate: taxRate.longTerm)
                
                let totalBasis = analysis.lotsWithUnrealizedLosses.reduce(0) { $0 + $1.remainingCostBasis }
                let totalQty = analysis.lotsWithUnrealizedLosses.reduce(0) { $0 + $1.remainingQuantity }
                let avgBasis = totalQty > 0 ? totalBasis / totalQty : 0
                
                let opportunity = TaxLossHarvestingOpportunity(
                    symbol: symbol,
                    currentPrice: price,
                    averageCostBasis: avgBasis,
                    unrealizedLoss: analysis.totalUnrealizedLoss,
                    estimatedSavings: savings,
                    lotsCount: analysis.lotsWithUnrealizedLosses.count,
                    isShortTerm: !analysis.shortTermLossLots.isEmpty,
                    lots: analysis.lotsWithUnrealizedLosses
                )
                newOpportunities.append(opportunity)
            }
        }
        
        // Sort by potential savings
        newOpportunities.sort { $0.estimatedSavings > $1.estimatedSavings }
        
        await MainActor.run {
            opportunities = newOpportunities
            totalHarvestableAmount = newOpportunities.reduce(0) { $0 + $1.unrealizedLoss }
            totalPotentialSavings = newOpportunities.reduce(0) { $0 + $1.estimatedSavings }
            isLoading = false
        }
    }
    
    private func recalculateSavings() {
        for i in opportunities.indices {
            let taxRate = getTaxRate(for: filingStatus, isShortTerm: opportunities[i].isShortTerm)
            let lots = opportunities[i].lots
            let price = opportunities[i].currentPrice
            
            let stLoss = lots.filter { !$0.isLongTerm }.reduce(0) { total, lot in
                total + (lot.costBasisPerUnit - price) * lot.remainingQuantity
            }
            let ltLoss = lots.filter { $0.isLongTerm }.reduce(0) { total, lot in
                total + (lot.costBasisPerUnit - price) * lot.remainingQuantity
            }
            
            opportunities[i].estimatedSavings = (stLoss * taxRate.shortTerm) + (ltLoss * taxRate.longTerm)
        }
        
        totalPotentialSavings = opportunities.reduce(0) { $0 + $1.estimatedSavings }
    }
    
    private func getTaxRate(for status: FilingStatus, isShortTerm: Bool) -> (shortTerm: Double, longTerm: Double) {
        // Simplified tax rates based on filing status
        switch status {
        case .single:
            return (0.32, 0.15) // 32% marginal, 15% LTCG
        case .marriedFilingJointly:
            return (0.24, 0.15)
        case .marriedFilingSeparately:
            return (0.32, 0.15)
        case .headOfHousehold:
            return (0.32, 0.15)
        }
    }
    
    private func fetchPrice(for symbol: String) async -> Double? {
        // This would ideally call LivePriceManager or CoinGecko
        // For now, return nil and let the UI handle it
        return nil
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        return formatter.string(from: NSNumber(value: abs(amount))) ?? "$0.00"
    }
}

// MARK: - Tax Loss Harvesting Opportunity

struct TaxLossHarvestingOpportunity: Identifiable {
    let id = UUID()
    let symbol: String
    let currentPrice: Double
    let averageCostBasis: Double
    let unrealizedLoss: Double
    var estimatedSavings: Double
    let lotsCount: Int
    let isShortTerm: Bool
    let lots: [TaxLot]
    
    var lossPercent: Double {
        guard averageCostBasis > 0 else { return 0 }
        return ((averageCostBasis - currentPrice) / averageCostBasis) * 100
    }
    
    var holdingPeriod: String {
        isShortTerm ? "Short-Term" : "Long-Term"
    }
}

// MARK: - Opportunity Detail Sheet

struct OpportunityDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let opportunity: TaxLossHarvestingOpportunity
    let filingStatus: FilingStatus
    
    private var themedAccent: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                FuturisticBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 12) {
                            Text(opportunity.symbol)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            HStack(spacing: 20) {
                                VStack {
                                    Text("Current Price")
                                        .font(.caption)
                                        .foregroundColor(DS.Adaptive.textSecondary)
                                    Text(formatCurrency(opportunity.currentPrice))
                                        .font(.headline)
                                        .foregroundColor(DS.Adaptive.textPrimary)
                                }
                                
                                VStack {
                                    Text("Cost Basis")
                                        .font(.caption)
                                        .foregroundColor(DS.Adaptive.textSecondary)
                                    Text(formatCurrency(opportunity.averageCostBasis))
                                        .font(.headline)
                                        .foregroundColor(DS.Adaptive.textPrimary)
                                }
                                
                                VStack {
                                    Text("Unrealized Loss")
                                        .font(.caption)
                                        .foregroundColor(DS.Adaptive.textSecondary)
                                    Text(formatCurrency(opportunity.unrealizedLoss))
                                        .font(.headline)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(cardBackground)
                        
                        // Tax Savings Breakdown
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Tax Savings Breakdown")
                                .font(.headline)
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Harvestable Loss")
                                    Spacer()
                                    Text(formatCurrency(opportunity.unrealizedLoss))
                                        .foregroundColor(.red)
                                }
                                
                                HStack {
                                    Text("Filing Status")
                                    Spacer()
                                    Text(filingStatus.displayName)
                                        .foregroundColor(DS.Adaptive.textSecondary)
                                }
                                
                                HStack {
                                    Text("Holding Period")
                                    Spacer()
                                    Text(opportunity.holdingPeriod)
                                        .foregroundColor(opportunity.isShortTerm ? .orange : .blue)
                                }
                                
                                Rectangle()
                                    .fill(DS.Adaptive.divider)
                                    .frame(height: 1)
                                
                                HStack {
                                    Text("Estimated Tax Savings")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(formatCurrency(opportunity.estimatedSavings))
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(14)
                            .background(DS.Adaptive.cardBackgroundElevated)
                            .cornerRadius(12)
                        }
                        .padding(16)
                        .background(cardBackground)
                        
                        // Affected Lots
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Tax Lots with Losses (\(opportunity.lotsCount))")
                                .font(.headline)
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            ForEach(opportunity.lots, id: \.id) { lot in
                                lotRow(lot)
                            }
                        }
                        .padding(16)
                        .background(cardBackground)
                        
                        // Action Guidance
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                Text("How to Harvest")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            
                            Text("1. Sell your \(opportunity.symbol) holdings to realize the loss\n2. Wait 31+ days before repurchasing to avoid wash sale rules\n3. Consider buying a similar (but not identical) asset during the waiting period\n4. Report the loss on your tax return")
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.yellow.opacity(colorScheme == .dark ? 0.1 : 0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding()
                }
            }
            .navigationTitle("Harvesting Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
            }
        }
    }
    
    private func lotRow(_ lot: TaxLot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%.6f %@", lot.remainingQuantity, lot.symbol))
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text("Acquired: \(formatDate(lot.acquiredDate))")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency((lot.costBasisPerUnit - opportunity.currentPrice) * lot.remainingQuantity))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
                Text("@ \(formatCurrency(lot.costBasisPerUnit))")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
        .padding(12)
        .background(DS.Adaptive.cardBackgroundElevated)
        .cornerRadius(10)
    }
    
    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
            
            LinearGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.5), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        return formatter.string(from: NSNumber(value: abs(amount))) ?? "$0.00"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    TaxLossHarvestingView()
        .environmentObject(PortfolioViewModel.sample)
}
