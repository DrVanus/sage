//
//  BotMarketplaceView.swift
//  CryptoSage
//
//  Bot marketplace for discovering and copying shared bot configurations.
//

import SwiftUI

struct BotMarketplaceView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    @StateObject private var socialService = SocialService.shared
    @StateObject private var copyTradingManager = CopyTradingManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    @State private var searchText = ""
    @State private var selectedType: SharedBotType?
    @State private var selectedRisk: RiskLevel?
    @State private var sortOption: BotSortOption = .popular
    @State private var isLoading = false
    @State private var selectedBot: SharedBotConfig?
    @State private var showUpgradeSheet = false
    @State private var showSearchBar = false
    @FocusState private var isSearchFocused: Bool
    
    /// Check if user has bot marketplace access (Premium tier)
    private var hasMarketplaceAccess: Bool {
        subscriptionManager.hasAccess(to: .botMarketplace)
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Upgrade banner for non-Premium users
                    if !hasMarketplaceAccess {
                        marketplaceUpgradeBanner
                    }
                    
                    // Search bar (toggleable)
                    if showSearchBar {
                        searchBar
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                    }
                    
                    // Featured Bots Section (only show when not searching)
                    if searchText.isEmpty && selectedType == nil && selectedRisk == nil && !showSearchBar {
                        featuredBotsSection
                    }
                    
                    // Filters
                    filterBar
                    
                    // Sort with search toggle
                    sortBarWithSearchToggle
                    
                    // Bot Grid - visible to all but copy action is gated
                    botGrid
                }
                .padding()
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showSearchBar)
            }
            .task {
                await loadBots()
            }
            .refreshable {
                await loadBots()
            }
            .sheet(item: $selectedBot) { bot in
                SharedBotDetailView(bot: bot) { botId in
                    // Navigate to BotHub after dismissing sheet
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        appState.navigateToBotHub(botId: botId)
                    }
                }
            }
            .unifiedPaywallSheet(feature: .botMarketplace, isPresented: $showUpgradeSheet)
        }
    }
    
    // MARK: - Upgrade Banner
    
    private var marketplaceUpgradeBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "storefront.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.purple)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Bot Marketplace")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Browse bots for free • Copy with Premium")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showUpgradeSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                    Text("Upgrade")
                        .font(.caption.weight(.bold))
                }
            }
            .buttonStyle(
                PremiumCompactCTAStyle(
                    height: 30,
                    horizontalPadding: 12,
                    cornerRadius: 15,
                    font: .caption.weight(.bold)
                )
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Featured Bots Section
    
    private var featuredBots: [SharedBotConfig] {
        // Get top performing bots from discovered marketplace bots
        // (not sharedBots which is the user's OWN bots)
        let allBots = socialService.discoveredBots
            .filter { $0.performanceStats.pnlPercent > 0 }
            .sorted { (bot1: SharedBotConfig, bot2: SharedBotConfig) in
                // Popular bots (more copies) first, then by ROI
                if bot1.copiesCount != bot2.copiesCount {
                    return bot1.copiesCount > bot2.copiesCount
                }
                return bot1.performanceStats.pnlPercent > bot2.performanceStats.pnlPercent
            }
        
        return Array(allBots.prefix(5))
    }
    
    private var featuredBotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(.yellow)
                    
                    Text("Featured Bots")
                        .font(.headline.weight(.bold))
                }
                
                Spacer()
                
                Text("Editor's Pick")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.93))
                    )
            }
            
            if featuredBots.isEmpty {
                // Fallback if no featured bots
                Text("Discover top-performing bots below")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(featuredBots) { bot in
                            FeaturedBotCard(bot: bot)
                                .onTapGesture {
                                    selectedBot = bot
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                        }
                    }
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.08), Color(white: 0.12)]
                            : [Color.white, Color(white: 0.98)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [.yellow.opacity(0.3), .orange.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search bots...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    Task { await searchBots() }
                }
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Task { await loadBots() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            
            // Close search button
            Button {
                withAnimation {
                    showSearchBar = false
                    searchText = ""
                    isSearchFocused = false
                }
                Task { await loadBots() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Circle().fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.9)))
            }
        }
        .padding()
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
        .onAppear {
            // Auto-focus when search bar appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isSearchFocused = true
            }
        }
    }
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Bot Type Filter
                Menu {
                    Button("All Types") { selectedType = nil }
                    Divider()
                    ForEach(SharedBotType.allCases, id: \.self) { type in
                        Button {
                            selectedType = type
                        } label: {
                            Label(type.displayName, systemImage: type.icon)
                        }
                    }
                } label: {
                    filterChip(
                        icon: selectedType?.icon ?? "line.3.horizontal.decrease.circle",
                        text: selectedType?.displayName ?? "Bot Type",
                        isActive: selectedType != nil
                    )
                }
                
                // Risk Level Filter
                Menu {
                    Button("All Risks") { selectedRisk = nil }
                    Divider()
                    ForEach(RiskLevel.allCases, id: \.self) { risk in
                        Button(risk.rawValue) {
                            selectedRisk = risk
                        }
                    }
                } label: {
                    filterChip(
                        icon: "exclamationmark.triangle",
                        text: selectedRisk?.rawValue ?? "Risk Level",
                        isActive: selectedRisk != nil
                    )
                }
            }
        }
        .onChange(of: selectedType) { _, _ in Task { await loadBots() } }
        .onChange(of: selectedRisk) { _, _ in Task { await loadBots() } }
    }
    
    private func filterChip(icon: String, text: String, isActive: Bool) -> some View {
        let isDark = colorScheme == .dark
        
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.caption.weight(.semibold))
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .foregroundStyle(isActive 
            ? TintedChipStyle.selectedText(isDark: isDark) 
            : DS.Adaptive.textSecondary)
        .tintedCapsuleChip(isSelected: isActive, isDark: isDark)
    }
    
    private var sortBar: some View {
        let isDark = colorScheme == .dark
        
        return HStack {
            // Bot count with subtle styling
            HStack(spacing: 5) {
                Text("\(socialService.discoveredBots.count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                Text("bots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Menu {
                ForEach(BotSortOption.allCases, id: \.self) { option in
                    Button {
                        sortOption = option
                        Task { await loadBots() }
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Sort:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(sortOption.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TintedChipStyle.selectedText(isDark: isDark))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TintedChipStyle.selectedText(isDark: isDark).opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .tintedCapsuleChip(isSelected: true, isDark: isDark)
            }
        }
    }
    
    private var sortBarWithSearchToggle: some View {
        let isDark = colorScheme == .dark
        
        return HStack {
            // Bot count with subtle styling
            HStack(spacing: 5) {
                Text("\(socialService.discoveredBots.count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                Text("bots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Search toggle button (only show when search is closed)
            if !showSearchBar {
                Button {
                    withAnimation {
                        showSearchBar = true
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                        .padding(8)
                        .background {
                            Circle()
                                .fill(DS.Adaptive.chipBackground)
                        }
                        .overlay {
                            Circle()
                                .stroke(DS.Adaptive.stroke, lineWidth: 1)
                        }
                }
            }
            
            Menu {
                ForEach(BotSortOption.allCases, id: \.self) { option in
                    Button {
                        sortOption = option
                        Task { await loadBots() }
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Sort:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(sortOption.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TintedChipStyle.selectedText(isDark: isDark))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TintedChipStyle.selectedText(isDark: isDark).opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .tintedCapsuleChip(isSelected: true, isDark: isDark)
            }
        }
    }
    
    private var botGrid: some View {
        LazyVStack(spacing: 12) {
            ForEach(socialService.discoveredBots) { bot in
                BotCard(
                    bot: bot, 
                    isCopied: copyTradingManager.isCopied(sharedBotId: bot.id),
                    onQuickCopy: {
                        // Navigate to bot after quick copy
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            appState.navigateToBotHub()
                        }
                    }
                )
                    .onTapGesture {
                        selectedBot = bot
                    }
            }
        }
    }
    
    private func loadBots() async {
        isLoading = true
        _ = try? await socialService.discoverBots(
            sortBy: sortOption,
            botType: selectedType,
            riskLevel: selectedRisk
        )
        isLoading = false
    }
    
    private func searchBots() async {
        guard !searchText.isEmpty else {
            await loadBots()
            return
        }
        
        isLoading = true
        _ = try? await socialService.searchBots(query: searchText)
        isLoading = false
    }
}

// MARK: - Bot Card

struct BotCard: View {
    let bot: SharedBotConfig
    let isCopied: Bool
    var onQuickCopy: (() -> Void)? = nil  // Callback for quick copy action
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var isQuickCopying = false
    @State private var showUpgradeSheet = false
    @StateObject private var copyTradingManager = CopyTradingManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    
    // List of supported exchanges for compatibility check
    private static let supportedExchanges = ["Binance", "Coinbase", "KuCoin", "Bybit", "Kraken", "OKX"]
    
    // Check if this is a top-performing bot (ROI > 50%)
    private var isTopPerformer: Bool {
        bot.performanceStats.pnlPercent >= 50.0
    }
    
    // Check if this is a verified bot (running > 30 days with good performance)
    private var isVerified: Bool {
        bot.performanceStats.runningDays >= 30 && 
        bot.performanceStats.winRate >= 0.6 &&
        bot.performanceStats.totalTrades >= 50
    }
    
    // Check if hot (many copies recently - simulated)
    private var isHot: Bool {
        bot.copiesCount >= 300
    }
    
    // Check if new (running < 14 days)
    private var isNew: Bool {
        bot.performanceStats.runningDays <= 14
    }
    
    // Check if trending (good ROI + high copies)
    private var isTrending: Bool {
        bot.performanceStats.pnlPercent >= 30 && bot.copiesCount >= 100
    }
    
    private var accentColor: Color {
        isTopPerformer ? Color(red: 0.95, green: 0.82, blue: 0.42) : bot.botType.color
    }
    
    // Check if exchange is compatible/supported
    private var isExchangeSupported: Bool {
        Self.supportedExchanges.contains { bot.exchange.lowercased().contains($0.lowercased()) }
    }
    
    // Generate simulated performance data for sparkline - more realistic trading chart
    private var performanceData: [Double] {
        let baseValue = 100.0
        let trend = bot.performanceStats.pnlPercent / 100.0
        var data: [Double] = []
        var current = baseValue
        
        // Use more points for smoother curves
        let pointCount = 30
        
        for i in 0..<pointCount {
            // Add realistic volatility based on win rate (lower win rate = more volatile)
            let volatilityFactor = 1.5 + (1.0 - bot.performanceStats.winRate) * 2.0
            let noise = Double.random(in: -volatilityFactor...volatilityFactor)
            let trendComponent = trend * Double(i) / Double(pointCount) * 20
            
            // Add occasional dips/spikes for realism
            let spike = (i % 7 == 0) ? Double.random(in: -1.5...2.0) : 0
            
            current = baseValue + trendComponent + noise + spike
            data.append(max(baseValue * 0.85, current)) // Floor at 85% to prevent unrealistic drops
        }
        return data
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Bot Type Icon with glow for top performers
                ZStack {
                    if isTopPerformer {
                        Circle()
                            .fill(accentColor.opacity(0.3))
                            .frame(width: 48, height: 48)
                    }
                    
                    Circle()
                        .fill(bot.botType.color.gradient)
                        .frame(width: 42, height: 42)
                        .overlay {
                            Image(systemName: bot.botType.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(bot.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        
                        // Verified badge
                        if isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        
                        if isCopied {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        
                        if isTopPerformer {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(accentColor)
                        }
                    }
                    
                    Text("by @\(bot.creatorUsername)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Status badges stack
                VStack(alignment: .trailing, spacing: 4) {
                    // Risk Badge
                    Text(bot.riskLevel.rawValue)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(bot.riskLevel.badgeColor.opacity(0.2))
                                .overlay(
                                    Capsule()
                                        .stroke(bot.riskLevel.badgeColor.opacity(0.4), lineWidth: 1)
                                )
                        )
                        .foregroundStyle(bot.riskLevel.badgeColor)
                    
                    // Status badge (Hot/Trending/New)
                    if isHot {
                        statusBadge(text: "🔥 Hot", colors: [.orange, .red])
                    } else if isTrending {
                        statusBadge(text: "📈 Trending", colors: [.purple, .blue])
                    } else if isNew {
                        statusBadge(text: "✨ New", colors: [.cyan, .blue])
                    }
                }
            }
            
            // ROI Sparkline Chart - Professional trading terminal style
            HStack(spacing: 16) {
                // Enhanced Sparkline with better visibility
                SparklineView(
                    data: performanceData,
                    isPositive: bot.performanceStats.pnlPercent >= 0,
                    height: 44,
                    lineWidth: SparklineConsistency.miniCardLineWidth,
                    fillOpacity: SparklineConsistency.miniCardFillOpacity,
                    gradientStroke: true,
                    showEndDot: true,
                    endDotPulse: false,
                    preferredWidth: nil,
                    backgroundStyle: .dark,
                    cornerRadius: 8,
                    glowOpacity: SparklineConsistency.miniCardGlowOpacity,
                    glowLineWidth: SparklineConsistency.miniCardGlowLineWidth,
                    smoothSamplesPerSegment: SparklineConsistency.miniCardSmoothSamplesPerSegment,
                    maxPlottedPoints: SparklineConsistency.miniCardMaxPlottedPoints,
                    horizontalInset: SparklineConsistency.miniCardHorizontalInset,
                    compact: false
                )
                .opacity(appeared ? 1 : 0)
                
                // ROI Display with enhanced styling
                VStack(alignment: .trailing, spacing: 3) {
                    Text(formatPercent(bot.performanceStats.pnlPercent))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(bot.performanceStats.pnlPercent >= 0 ? .green : .red)
                    
                    Text("ROI")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 75, alignment: .trailing)
            }
            
            // Stats with improved visual separation
            HStack(spacing: 0) {
                statItem(
                    value: "\(String(format: "%.0f", bot.performanceStats.winRate * 100))%",
                    label: "Win Rate",
                    isPositive: bot.performanceStats.winRate >= 0.5,
                    isHighlight: false
                )
                
                statDivider
                
                statItem(
                    value: "\(bot.performanceStats.totalTrades)",
                    label: "Trades",
                    isPositive: true,
                    isHighlight: false
                )
                
                statDivider
                
                statItem(
                    value: "\(bot.performanceStats.runningDays)d",
                    label: "Running",
                    isPositive: true,
                    isHighlight: false
                )
                
                statDivider
                
                statItem(
                    value: formatDrawdown(bot.performanceStats.maxDrawdown),
                    label: "Max DD",
                    isPositive: bot.performanceStats.maxDrawdown <= 0.15,
                    isHighlight: false
                )
            }
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color(white: 0.06) : Color(white: 0.97))
            )
            
            // Footer
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.caption)
                    Text("\(bot.copiesCount)")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
                
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(Color.pink.opacity(0.7))
                    Text("\(bot.likesCount)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Exchange with compatibility badge
                HStack(spacing: 6) {
                    Text(bot.tradingPair)
                        .font(.caption.weight(.semibold))
                    Text("•")
                        .foregroundStyle(.secondary.opacity(0.5))
                    
                    HStack(spacing: 3) {
                        if isExchangeSupported {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.green)
                        }
                        Text(bot.exchange)
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
            
            // Quick Copy Button (only show if not already copied)
            if !isCopied && onQuickCopy != nil {
                let hasAccess = subscriptionManager.hasAccess(to: .copyTrading)
                
                Button {
                    if hasAccess {
                        performQuickCopy()
                    } else {
                        // Show paywall for non-Premium users
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        PaywallManager.shared.trackFeatureAttempt(.copyTrading)
                        showUpgradeSheet = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isQuickCopying {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else if !hasAccess {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10))
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        
                        Text(isQuickCopying ? "Copying..." : (hasAccess ? "Quick Copy" : "Premium to Copy"))
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                hasAccess
                                ? LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: bot.botType.color.opacity(0.95), location: 0.0),
                                        .init(color: bot.botType.color, location: 0.5),
                                        .init(color: bot.botType.color.opacity(0.75), location: 1.0)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.purple.opacity(0.7), Color.purple.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        // Inner shine highlight
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(colorScheme == .dark ? 0.25 : 0.35), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                    .overlay {
                        // Subtle border
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(colorScheme == .dark ? 0.4 : 0.6), Color.white.opacity(colorScheme == .dark ? 0.1 : 0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .foregroundStyle(.white)
                }
                .disabled(isQuickCopying)
                .buttonStyle(QuickCopyButtonStyle())
                .unifiedPaywallSheet(feature: .copyTrading, isPresented: $showUpgradeSheet)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isTopPerformer 
                        ? LinearGradient(
                            colors: [accentColor.opacity(0.6), accentColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          )
                        : LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.1), Color.clear]
                                : [Color.black.opacity(0.06), Color.black.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          ),
                    lineWidth: isTopPerformer ? 1.5 : 1
                )
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                appeared = true
            }
        }
    }
    
    private func statusBadge(text: String, colors: [Color]) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
    }
    
    private var statDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 1, height: 32)
    }
    
    private func statItem(value: String, label: String, isPositive: Bool, isHighlight: Bool) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isHighlight ? (isPositive ? .green : .red) : .primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formatPercent(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.1f", value))%"
    }
    
    private func performQuickCopy() {
        guard !isCopied, !isQuickCopying else { return }
        
        isQuickCopying = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        Task {
            do {
                _ = try await copyTradingManager.copyBot(bot, customName: "Copy: \(bot.name)")
                await MainActor.run {
                    isQuickCopying = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onQuickCopy?()
                }
            } catch {
                await MainActor.run {
                    isQuickCopying = false
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
    
    private func formatDrawdown(_ value: Double) -> String {
        return "\(String(format: "%.1f", value * 100))%"
    }
}

// MARK: - Risk Level Extension

extension RiskLevel {
    var badgeColor: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
}

// MARK: - Featured Bot Card

struct FeaturedBotCard: View {
    let bot: SharedBotConfig
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 10) {
                // Bot icon with enhanced glow
                ZStack {
                    // Outer glow — subtler in light mode
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    BrandColors.goldBase.opacity(isDark ? 0.4 : 0.15),
                                    BrandColors.goldBase.opacity(isDark ? 0.1 : 0.05),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 28
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isDark
                                    ? [BrandColors.goldLight, BrandColors.goldBase]
                                    : [Color(red: 0.85, green: 0.72, blue: 0.28), Color(red: 0.78, green: 0.62, blue: 0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(isDark ? 0.3 : 0.5), lineWidth: 1)
                        }
                    
                    Image(systemName: bot.botType.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isDark ? Color(red: 0.2, green: 0.15, blue: 0.0) : .white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(bot.name)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                        
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    
                    Text("by @\(bot.creatorUsername)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Mini sparkline - Premium featured style
            SparklineView(
                data: generateSparklineData(),
                isPositive: bot.performanceStats.pnlPercent >= 0,
                height: 48,
                lineWidth: SparklineConsistency.miniCardLineWidth,
                fillOpacity: SparklineConsistency.miniCardFillOpacity,
                gradientStroke: true,
                showEndDot: true,
                endDotPulse: false,
                showBaseline: false,
                backgroundStyle: .dark,
                cornerRadius: 8,
                glowOpacity: SparklineConsistency.miniCardGlowOpacity,
                glowLineWidth: SparklineConsistency.miniCardGlowLineWidth,
                smoothSamplesPerSegment: SparklineConsistency.miniCardSmoothSamplesPerSegment,
                maxPlottedPoints: SparklineConsistency.miniCardMaxPlottedPoints,
                horizontalInset: SparklineConsistency.miniCardHorizontalInset,
                compact: false
            )
            
            // Stats row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatPercent(bot.performanceStats.pnlPercent))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(bot.performanceStats.pnlPercent >= 0 ? .green : .red)
                    Text("ROI")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(String(format: "%.0f", bot.performanceStats.winRate * 100))%")
                        .font(.subheadline.weight(.semibold))
                    Text("Win Rate")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Featured badge with premium styling
            HStack(spacing: 5) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Featured")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(
                LinearGradient(
                    colors: [BrandColors.goldLight, BrandColors.goldBase],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(BrandColors.goldBase.opacity(0.15))
            }
            .overlay {
                Capsule()
                    .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
            }
        }
        .padding()
        .frame(width: 200)
        .background {
            // Glass morphism background
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(isDark 
                        ? Color(white: 0.1).opacity(0.9) 
                        : Color.white.opacity(0.95))
                
                // Glass effect overlay
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.08 : 0.3),
                                Color.clear,
                                Color.white.opacity(isDark ? 0.02 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .overlay {
            // Premium gold border with glow effect
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: BrandColors.goldLight.opacity(0.7), location: 0.0),
                            .init(color: BrandColors.goldBase.opacity(0.5), location: 0.3),
                            .init(color: BrandColors.goldBase.opacity(0.3), location: 0.7),
                            .init(color: BrandColors.goldLight.opacity(0.5), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
    }
    
    private func generateSparklineData() -> [Double] {
        let baseValue = 100.0
        let trend = bot.performanceStats.pnlPercent / 100.0
        var data: [Double] = []
        var current = baseValue
        
        // More points for smoother featured card sparklines
        let pointCount = 24
        
        for i in 0..<pointCount {
            let volatilityFactor = 1.2 + (1.0 - bot.performanceStats.winRate) * 1.5
            let noise = Double.random(in: -volatilityFactor...volatilityFactor)
            let trendComponent = trend * Double(i) / Double(pointCount) * 15
            
            // Add occasional dips for realism
            let spike = (i % 6 == 0) ? Double.random(in: -1.0...1.5) : 0
            
            current = baseValue + trendComponent + noise + spike
            data.append(max(baseValue * 0.9, current))
        }
        return data
    }
    
    private func formatPercent(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.1f", value))%"
    }
}

// MARK: - Quick Copy Button Style

struct QuickCopyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    BotMarketplaceView()
}
