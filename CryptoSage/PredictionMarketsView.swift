//
//  PredictionMarketsView.swift
//  CryptoSage
//
//  View for browsing and displaying prediction markets from Polymarket and Kalshi.
//

import SwiftUI

// MARK: - Prediction Markets View

struct PredictionMarketsView: View {
    @StateObject private var viewModel: PredictionMarketsViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    // Source filter (nil = all sources)
    let sourceFilter: PredictionMarketSource?
    
    // Detail sheet state
    @State private var selectedMarket: PredictionMarketEvent?
    @State private var showDetailSheet = false
    @State private var showPredictionBot = false
    
    init(sourceFilter: PredictionMarketSource? = nil) {
        self.sourceFilter = sourceFilter
        _viewModel = StateObject(wrappedValue: PredictionMarketsViewModel(sourceFilter: sourceFilter))
    }
    
    /// Navigation title based on filter
    private var navigationTitle: String {
        if let source = sourceFilter {
            return source.displayName
        }
        return "Prediction Markets"
    }
    
    /// Accent color based on platform
    private var platformAccentColor: Color {
        switch sourceFilter {
        case .polymarket:
            return .purple
        case .kalshi:
            return Color(red: 0.0, green: 0.7, blue: 0.6) // Teal
        case nil:
            return BrandColors.goldBase
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom nav bar
            customNavBar
            
            // Platform badge when filtered
            if sourceFilter != nil {
                platformBadge
            }
            
            // Sample data banner if showing fallback data
            if viewModel.isShowingSampleData {
                sampleDataBanner
            }
            
            // Category pills (only show when viewing all sources)
            if sourceFilter == nil {
                categoryPills
            }
            
            // Markets list
            if viewModel.isLoading && viewModel.markets.isEmpty {
                loadingView
            } else if viewModel.errorMessage != nil && viewModel.markets.isEmpty {
                errorView
            } else {
                marketsList
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .task {
            await viewModel.loadMarkets()
        }
        .sheet(isPresented: $showDetailSheet) {
            if let market = selectedMarket {
                MarketDetailSheet(
                    market: market,
                    onTrackWithBot: {
                        showDetailSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showPredictionBot = true
                        }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .navigationDestination(isPresented: $showPredictionBot) {
            PredictionBotView()
        }
    }
    
    /// Badge showing which platform is being viewed
    private var platformBadge: some View {
        HStack(spacing: 8) {
            if let source = sourceFilter {
                Image(systemName: source.iconName)
                    .font(.system(size: 12))
                Text("Viewing \(source.displayName) markets")
                    .font(.system(size: 12, weight: .medium))
            }
            Spacer()
            Text("\(viewModel.markets.count) markets")
                .font(.system(size: 11))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .foregroundColor(platformAccentColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(platformAccentColor.opacity(0.1))
    }
    
    private var sampleDataBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
            Text("Showing sample data. Pull to refresh for live markets.")
                .font(.system(size: 11))
            Spacer()
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
    
    private var customNavBar: some View {
        VStack(spacing: 0) {
            HStack {
                CSNavButton(
                    icon: "chevron.left",
                    action: { dismiss() }
                )
                
                Spacer()
                
                // Title with optional platform icon
                HStack(spacing: 6) {
                    if let source = sourceFilter {
                        Image(systemName: source.iconName)
                            .font(.system(size: 14))
                            .foregroundColor(platformAccentColor)
                    }
                    Text(navigationTitle)
                        .font(.headline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                Button(action: {
                    Task { await viewModel.refresh() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17))
                        .foregroundColor(platformAccentColor)
                        .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                        .animation(viewModel.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isLoading)
                }
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Trading mode indicator
            tradingModeIndicator
        }
        .background(DS.Adaptive.background)
    }
    
    private var tradingModeIndicator: some View {
        let isDeveloperMode = SubscriptionManager.shared.isDeveloperMode
        let isPaperTradingEnabled = PaperTradingManager.isEnabled
        
        return Group {
            if isDeveloperMode {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 10))
                    Text("Developer Mode - Live Trading Enabled")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange)
                .frame(maxWidth: .infinity)
            } else if isPaperTradingEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 10))
                    Text("Paper Trading Mode - Practice with Virtual Funds")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.blue)
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 10))
                    Text("View Only - Enable Paper Trading to practice")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DS.Adaptive.chipBackground)
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PredictionMarketCategory.allCases, id: \.rawValue) { category in
                    categoryPill(category)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(DS.Adaptive.background)
    }
    
    private func categoryPill(_ category: PredictionMarketCategory) -> some View {
        let isSelected = viewModel.selectedCategory == category
        
        return Button {
            viewModel.selectedCategory = category
            Task { await viewModel.loadMarkets() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: category.iconName)
                    .font(.system(size: 11))
                Text(category.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? .black : DS.Adaptive.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected 
                          ? AnyShapeStyle(LinearGradient(colors: [BrandColors.goldLight, BrandColors.goldBase], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(DS.Adaptive.chipBackground))
            )
        }
    }
    
    private var marketsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Source filter info
                if !viewModel.markets.isEmpty {
                    HStack {
                        Text("\(viewModel.markets.count) markets")
                            .font(.system(size: 12))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Spacer()
                        
                        // Source badges
                        HStack(spacing: 6) {
                            sourceBadge(.polymarket)
                            sourceBadge(.kalshi)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                
                ForEach(viewModel.markets) { market in
                    PredictionMarketCard(
                        market: market,
                        onTap: {
                            selectedMarket = market
                            showDetailSheet = true
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                    )
                    .padding(.horizontal, 16)
                }
                
                // Bottom padding
                Spacer(minLength: 40)
            }
            // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
            .withUIKitScrollBridge()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
    
    private func sourceBadge(_ source: PredictionMarketSource) -> some View {
        let count = viewModel.markets.filter { $0.source == source }.count
        
        return HStack(spacing: 3) {
            Image(systemName: source.iconName)
                .font(.system(size: 9))
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(DS.Adaptive.textTertiary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(DS.Adaptive.overlay(0.08))
        )
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading markets...")
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
        }
    }
    
    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(viewModel.errorMessage ?? "Failed to load markets")
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                Task { await viewModel.loadMarkets() }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(BrandColors.goldBase)
            .cornerRadius(8)
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Prediction Market Card

struct PredictionMarketCard: View {
    let market: PredictionMarketEvent
    var onTap: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .top, spacing: 10) {
                    // Source badge
                    HStack(spacing: 4) {
                        Image(systemName: market.source.iconName)
                            .font(.system(size: 10))
                        Text(market.source.displayName)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(market.source == .polymarket ? .indigo : .green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((market.source == .polymarket ? Color.indigo : Color.green).opacity(0.12))
                    )
                    
                    // Category
                    Text(market.category)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(DS.Adaptive.overlay(0.08))
                        )
                    
                    // Sample data indicator
                    if market.isSampleData {
                        Text("Sample")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                            )
                    }
                    
                    Spacer()
                    
                    // Volume if available
                    if let volume = market.volume, volume > 0 {
                        Text(formatVolume(volume))
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                
                // Title
                Text(market.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                
                // Outcomes
                HStack(spacing: 8) {
                    ForEach(market.outcomes) { outcome in
                        outcomeView(outcome)
                    }
                }
                
                // Footer - End date and "View Details" hint
                HStack {
                    if let endDate = market.endDate {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(formatEndDate(endDate))
                                .font(.system(size: 11))
                        }
                        .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    
                    Spacer()
                    
                    // View details hint
                    HStack(spacing: 4) {
                        Text("Details")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(BrandColors.goldBase)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func outcomeView(_ outcome: PredictionOutcome) -> some View {
        let isYes = outcome.name.lowercased() == "yes"
        let color: Color = isYes ? .green : .red
        
        return VStack(spacing: 4) {
            Text(outcome.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
            
            Text(outcome.formattedProbability)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            
            Text(outcome.formattedPrice)
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "$%.1fM vol", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "$%.0fK vol", volume / 1_000)
        } else {
            return String(format: "$%.0f vol", volume)
        }
    }
    
    private func formatEndDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - View Model

@MainActor
class PredictionMarketsViewModel: ObservableObject {
    @Published var markets: [PredictionMarketEvent] = []
    @Published var selectedCategory: PredictionMarketCategory = .all
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isShowingSampleData: Bool = false
    
    /// Source filter (nil = all sources)
    let sourceFilter: PredictionMarketSource?
    
    init(sourceFilter: PredictionMarketSource? = nil) {
        self.sourceFilter = sourceFilter
    }
    
    func loadMarkets() async {
        isLoading = true
        errorMessage = nil
        isShowingSampleData = false
        
        do {
            // If we have a source filter, fetch for that source specifically
            if let source = sourceFilter {
                markets = try await PredictionMarketsService.shared.fetchMarkets(forSource: source, limit: 30)
            } else if selectedCategory == .all {
                markets = try await PredictionMarketsService.shared.fetchTrendingMarkets(limit: 30)
            } else {
                markets = try await PredictionMarketsService.shared.fetchMarkets(category: selectedCategory, limit: 30)
            }
            // Check if we got sample data
            isShowingSampleData = markets.first?.isSampleData ?? false
        } catch {
            errorMessage = error.localizedDescription
            // Use platform-specific sample data as fallback
            if let source = sourceFilter {
                markets = source == .polymarket ? PredictionMarketEvent.polymarketSamples : PredictionMarketEvent.kalshiSamples
            } else {
                markets = PredictionMarketEvent.samples
            }
            isShowingSampleData = true
        }
        
        isLoading = false
    }
    
    func refresh() async {
        await PredictionMarketsService.shared.clearCache()
        await loadMarkets()
    }
}

// MARK: - Market Detail Sheet

struct MarketDetailSheet: View {
    let market: PredictionMarketEvent
    let onTrackWithBot: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var showAIAnalysis = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with source and category
                    headerSection
                    
                    // Title
                    Text(market.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // Outcomes section
                    outcomesSection
                    
                    // Stats section
                    statsSection
                    
                    // Description if available
                    if let description = market.description, !description.isEmpty {
                        descriptionSection(description)
                    }
                    
                    // Sample data notice
                    if market.isSampleData {
                        sampleDataNotice
                    }
                    
                    // Action buttons
                    actionButtons
                    
                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(BrandColors.goldBase)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAIAnalysis = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                            Text("Ask AI")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(BrandColors.goldBase)
                    }
                }
            }
            .sheet(isPresented: $showAIAnalysis) {
                MarketAIAnalysisSheet(market: market)
            }
        }
    }
    
    private var headerSection: some View {
        HStack(spacing: 10) {
            // Source badge
            HStack(spacing: 4) {
                Image(systemName: market.source.iconName)
                    .font(.system(size: 12))
                Text(market.source.displayName)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(market.source == .polymarket ? .indigo : .green)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill((market.source == .polymarket ? Color.indigo : Color.green).opacity(0.15))
            )
            
            // Category badge
            Text(market.category)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DS.Adaptive.chipBackground)
                )
            
            Spacer()
        }
    }
    
    private var outcomesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CURRENT ODDS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DS.Adaptive.textTertiary)
                .tracking(0.5)
            
            HStack(spacing: 12) {
                ForEach(market.outcomes) { outcome in
                    detailOutcomeCard(outcome)
                }
            }
        }
    }
    
    private func detailOutcomeCard(_ outcome: PredictionOutcome) -> some View {
        let isYes = outcome.name.lowercased() == "yes"
        let color: Color = isYes ? .green : .red
        let multiplier = outcome.price > 0 && outcome.price < 1 ? 1.0 / outcome.price : 0
        
        return VStack(spacing: 8) {
            Text(outcome.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            
            Text(outcome.formattedProbability)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(color)
            
            VStack(spacing: 2) {
                Text(outcome.formattedPrice)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Text(String(format: "%.1fx return", multiplier))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MARKET INFO")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DS.Adaptive.textTertiary)
                .tracking(0.5)
            
            VStack(spacing: 10) {
                if let volume = market.volume, volume > 0 {
                    statRow(icon: "chart.bar.fill", label: "Volume", value: formatVolume(volume))
                }
                
                if let liquidity = market.liquidity, liquidity > 0 {
                    statRow(icon: "drop.fill", label: "Liquidity", value: formatVolume(liquidity))
                }
                
                if let endDate = market.endDate {
                    statRow(icon: "calendar", label: "Resolves", value: formatEndDateLong(endDate))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
        }
    }
    
    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
    }
    
    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ABOUT THIS MARKET")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DS.Adaptive.textTertiary)
                .tracking(0.5)
            
            Text(description)
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textSecondary)
                .lineSpacing(4)
        }
    }
    
    private var sampleDataNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Sample Data")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                Text("This is demonstration data. Refresh the markets list to load live data.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary action - Ask AI for analysis
            Button {
                showAIAnalysis = true
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Ask AI About This Market")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
            }
            
            // Secondary action - Track with Bot (paper trading)
            Button(action: onTrackWithBot) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis.ascending")
                        .font(.system(size: 13))
                    Text("Track with Prediction Bot")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(DS.Adaptive.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
            }
            
            // Tertiary action - Open in browser (if URL available)
            if let url = market.marketUrl {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                            .font(.system(size: 12))
                        Text("Open on \(market.source.displayName)")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(DS.Adaptive.textTertiary)
                }
            } else if !market.isSampleData {
                // No URL available notice
                Text("External link not available for this market")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "$%.1fM", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "$%.0fK", volume / 1_000)
        } else {
            return String(format: "$%.0f", volume)
        }
    }
    
    private func formatEndDateLong(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Market AI Analysis Sheet

struct MarketAIAnalysisSheet: View {
    let market: PredictionMarketEvent
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: MarketAIAnalysisViewModel
    @FocusState private var isInputFocused: Bool
    
    init(market: PredictionMarketEvent) {
        self.market = market
        _viewModel = StateObject(wrappedValue: MarketAIAnalysisViewModel(market: market))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Market summary header
                marketSummaryHeader
                
                Divider()
                
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if viewModel.isTyping {
                                MarketAnalysisTypingIndicator()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        withAnimation {
                            if let lastMessage = viewModel.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Disclaimer
                aiDisclaimer
                
                // Input area
                inputArea
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(BrandColors.goldBase)
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundColor(BrandColors.goldBase)
                        Text("CryptoSage AI Analysis")
                            .font(.headline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .allowsTightening(true)
                    }
                }
            }
            .onAppear {
                viewModel.startAnalysis()
            }
        }
    }
    
    private var marketSummaryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Platform and category
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: market.source.iconName)
                        .font(.system(size: 10))
                    Text(market.source.displayName)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(market.source == .polymarket ? .indigo : .green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((market.source == .polymarket ? Color.indigo : Color.green).opacity(0.12))
                )
                
                Text(market.category)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(DS.Adaptive.chipBackground))
                
                Spacer()
            }
            
            // Title
            Text(market.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .lineLimit(2)
            
            // Current odds
            HStack(spacing: 16) {
                if let yesOutcome = market.outcomes.first(where: { $0.name.lowercased() == "yes" }) {
                    HStack(spacing: 4) {
                        Text("YES:")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(yesOutcome.formattedProbability)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
                if let noOutcome = market.outcomes.first(where: { $0.name.lowercased() == "no" }) {
                    HStack(spacing: 4) {
                        Text("NO:")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(noOutcome.formattedProbability)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
                if let volume = market.volume, volume > 0 {
                    HStack(spacing: 4) {
                        Text("Vol:")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(formatVolume(volume))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
            }
        }
        .padding(12)
        .background(DS.Adaptive.cardBackground)
    }
    
    private var aiDisclaimer: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            Text("AI analysis is for informational purposes only. Not financial advice.")
                .font(.system(size: 10))
        }
        .foregroundColor(DS.Adaptive.textTertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(DS.Adaptive.chipBackground)
    }
    
    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Ask a follow-up question...", text: $viewModel.userInput)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(DS.Adaptive.chipBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
                .focused($isInputFocused)
            
            Button {
                viewModel.sendFollowUp()
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.gray
                        : BrandColors.goldBase
                    )
            }
            .disabled(viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isTyping)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DS.Adaptive.background)
    }
    
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "$%.1fM", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "$%.0fK", volume / 1_000)
        } else {
            return String(format: "$%.0f", volume)
        }
    }
}

// MARK: - Market AI Analysis ViewModel

@MainActor
class MarketAIAnalysisViewModel: ObservableObject {
    @Published var messages: [AiChatMessage] = []
    @Published var userInput: String = ""
    @Published var isTyping: Bool = false
    
    private let market: PredictionMarketEvent
    private var currentTask: Task<Void, Never>?
    
    init(market: PredictionMarketEvent) {
        self.market = market
    }
    
    private var marketContext: String {
        let yesPrice = market.outcomes.first(where: { $0.name.lowercased() == "yes" })?.probability ?? 0.5
        let noPrice = market.outcomes.first(where: { $0.name.lowercased() == "no" })?.probability ?? 0.5
        
        var context = """
        PREDICTION MARKET ANALYSIS REQUEST:
        
        Platform: \(market.source.displayName)
        Category: \(market.category)
        Question: \(market.title)
        
        Current Prices:
        - YES: \(String(format: "%.0f%%", yesPrice * 100)) (pay \(String(format: "%.0f¢", yesPrice * 100)) to win $1)
        - NO: \(String(format: "%.0f%%", noPrice * 100)) (pay \(String(format: "%.0f¢", noPrice * 100)) to win $1)
        
        """
        
        if let volume = market.volume, volume > 0 {
            context += "Total Volume: $\(Int(volume).formatted())\n"
        }
        
        if let endDate = market.endDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            context += "Resolves: \(formatter.string(from: endDate))\n"
        }
        
        if let description = market.description, !description.isEmpty {
            context += "\nMarket Description: \(description)\n"
        }
        
        return context
    }
    
    private var systemPrompt: String {
        """
        You are a prediction market analyst helping users understand and evaluate prediction markets from Polymarket and Kalshi.
        
        YOUR APPROACH:
        - Be analytical and balanced - consider both YES and NO outcomes
        - Focus on probability assessment, not price speculation
        - Consider what would need to happen for each outcome to win
        - Be honest about uncertainty - these are probabilistic markets
        
        ANALYSIS FRAMEWORK:
        
        1. PROBABILITY ASSESSMENT
           - Does the current price seem fair based on available information?
           - What factors support the current pricing?
           - Are there reasons to think it's mispriced?
        
        2. KEY FACTORS
           - What events, data, or announcements could move this market?
           - What's the timeline? Key dates to watch?
           - What's the current trajectory/momentum?
        
        3. EDGE OPPORTUNITIES
           - Do you see any obvious mispricings?
           - What information might the market be missing or overweighting?
           - What would change your view significantly?
        
        4. RISK CONSIDERATIONS
           - What could go wrong with each position?
           - Is there asymmetric risk (one side safer than the other)?
           - Resolution risk - any ambiguity in how the market settles?
        
        IMPORTANT GUIDELINES:
        - Keep analysis concise but insightful (2-3 paragraphs max for initial analysis)
        - Use plain language, no markdown formatting (no *, #, _, etc.)
        - For NON-CRYPTO topics (politics, sports, economics), focus on relevant domain knowledge
        - Include a brief "Bottom Line" summary
        - Acknowledge uncertainty - prediction markets aggregate collective wisdom
        - Do NOT guarantee any outcome or give financial advice
        
        DISCLAIMER: Always remind users that prediction market prices reflect crowd probability estimates, not certainties. Past performance does not guarantee future results.
        """
    }
    
    func startAnalysis() {
        guard messages.isEmpty else { return }
        
        let analysisRequest = """
        \(marketContext)
        
        Please provide your analysis of this prediction market. Consider:
        1. Whether the current price seems fair or potentially mispriced
        2. Key factors that could influence the outcome
        3. Risks and considerations for both YES and NO positions
        """
        
        // Add a system message indicating analysis is starting
        let systemMsg = AiChatMessage(
            text: "Analyzing this market for you...",
            isUser: false,
            timestamp: Date()
        )
        messages.append(systemMsg)
        
        isTyping = true
        
        let placeholderId = UUID()
        
        currentTask = Task {
            do {
                _ = try await AIService.shared.sendMessageStreaming(
                    analysisRequest,
                    systemPrompt: systemPrompt,
                    usePremiumModel: false,
                    includeTools: false
                ) { [weak self] streamedText in
                    guard let self = self else { return }
                    
                    if self.isTyping && !streamedText.isEmpty {
                        // Remove the "Analyzing..." message and add real response
                        if self.messages.count == 1 {
                            self.messages.removeAll()
                        }
                        self.isTyping = false
                    }
                    
                    // Update or create the response message
                    if let index = self.messages.firstIndex(where: { $0.id == placeholderId }) {
                        self.messages[index] = AiChatMessage(
                            id: placeholderId,
                            text: streamedText,
                            isUser: false,
                            timestamp: Date()
                        )
                    } else if !streamedText.isEmpty {
                        let msg = AiChatMessage(
                            id: placeholderId,
                            text: streamedText,
                            isUser: false,
                            timestamp: Date()
                        )
                        self.messages.append(msg)
                    }
                }
            } catch {
                isTyping = false
                let errorMsg = AiChatMessage(
                    text: "Sorry, I couldn't analyze this market right now. Please try again later.",
                    isUser: false,
                    timestamp: Date()
                )
                if messages.first?.text == "Analyzing this market for you..." {
                    messages.removeAll()
                }
                messages.append(errorMsg)
            }
        }
    }
    
    func sendFollowUp() {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }
        
        let userMsg = AiChatMessage(text: trimmedInput, isUser: true, timestamp: Date())
        messages.append(userMsg)
        userInput = ""
        
        isTyping = true
        
        let placeholderId = UUID()
        let placeholder = AiChatMessage(id: placeholderId, text: "", isUser: false, timestamp: Date())
        messages.append(placeholder)
        
        // Include market context with follow-up
        let contextualQuery = """
        [Context: The user is asking about this prediction market]
        \(marketContext)
        
        User's follow-up question: \(trimmedInput)
        """
        
        currentTask = Task {
            do {
                _ = try await AIService.shared.sendMessageStreaming(
                    contextualQuery,
                    systemPrompt: systemPrompt,
                    usePremiumModel: false,
                    includeTools: false
                ) { [weak self] streamedText in
                    guard let self = self else { return }
                    
                    if self.isTyping && !streamedText.isEmpty {
                        self.isTyping = false
                    }
                    
                    if let index = self.messages.firstIndex(where: { $0.id == placeholderId }) {
                        self.messages[index] = AiChatMessage(
                            id: placeholderId,
                            text: streamedText,
                            isUser: false,
                            timestamp: Date()
                        )
                    }
                }
            } catch {
                isTyping = false
                if let index = messages.firstIndex(where: { $0.id == placeholderId }) {
                    messages[index] = AiChatMessage(
                        id: placeholderId,
                        text: "Sorry, I couldn't process your question. Please try again.",
                        isUser: false,
                        timestamp: Date()
                    )
                }
            }
        }
    }
}

// MARK: - Message Bubble for AI Analysis

private struct MessageBubble: View {
    let message: AiChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 60)
            }
            
            Text(message.text)
                .font(.system(size: 14))
                .foregroundColor(message.isUser ? .white : DS.Adaptive.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(message.isUser ? BrandColors.goldBase : DS.Adaptive.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(message.isUser ? Color.clear : DS.Adaptive.stroke, lineWidth: 1)
                )
            
            if !message.isUser {
                Spacer(minLength: 40)
            }
        }
    }
}

// MARK: - Typing Indicator for AI Analysis

private struct MarketAnalysisTypingIndicator: View {
    @State private var dotCount = 0
    // PERFORMANCE FIX: Use @State so timer is tied to view identity lifecycle,
    // not re-created on every SwiftUI struct re-init (which leaked timers)
    @State private var timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(DS.Adaptive.textTertiary)
                        .frame(width: 6, height: 6)
                        .opacity(dotCount % 3 == index ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
            
            Spacer()
        }
        .onReceive(timer) { _ in
            dotCount += 1
        }
    }
}

// MARK: - Compact Market Row (for embedding in other views)

struct CompactPredictionMarketRow: View {
    let market: PredictionMarketEvent
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill((market.source == .polymarket ? Color.indigo : Color.green).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: market.source.iconName)
                    .font(.system(size: 14))
                    .foregroundColor(market.source == .polymarket ? .indigo : .green)
            }
            
            // Title and category
            VStack(alignment: .leading, spacing: 2) {
                Text(market.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(2)
                
                Text(market.category)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            // Primary outcome probability
            if let yesOutcome = market.outcomes.first(where: { $0.name.lowercased() == "yes" }) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(yesOutcome.formattedProbability)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.green)
                    Text("Yes")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PredictionMarketsView()
    }
}
