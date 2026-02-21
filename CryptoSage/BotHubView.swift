//
//  BotHubView.swift
//  CryptoSage
//
//  Unified hub for managing both paper trading bots and live trading bots.
//  Provides a segmented control to switch between Paper and Live bot views.
//  Supports Demo Mode with sample bots for demonstration purposes.
//

import SwiftUI

// MARK: - Bot Hub View

struct BotHubView: View {
    // Optional bot ID to highlight (from Social tab copy navigation)
    var highlightBotId: UUID? = nil
    
    // Selected tab
    @State private var selectedTab: BotTab = .paper
    
    // Environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    // Bot managers
    @ObservedObject private var paperBotManager = PaperBotManager.shared
    @ObservedObject private var liveBotManager = LiveBotManager.shared
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    // Available tabs - Strategies always available, Live Bots only in developer mode
    private var availableTabs: [BotTab] {
        if subscriptionManager.isDeveloperMode {
            return BotTab.allCases
        } else {
            return [.paper, .strategies] // Paper Bots and Strategies for regular users
        }
    }
    
    // Strategy-related state
    @State private var showStrategyBuilder = false
    @State private var showStrategyTemplates = false
    @State private var showLearningHub = false
    @ObservedObject private var strategyEngine = StrategyEngine.shared
    
    // Show welcome toast when navigating from Social copy
    @State private var showCopyWelcome: Bool = false
    
    // Help banner state - shows contextual tips about how bots work
    private static let helpBannerDismissedKey = "bot_hub_help_banner_dismissed"
    @State private var showHelpBanner: Bool = !UserDefaults.standard.bool(forKey: helpBannerDismissedKey)
    @State private var isHelpExpanded: Bool = false
    
    // AI Helper state
    @State private var showAIHelper: Bool = false
    
    // Animation state for premium stats
    @State private var statsAppeared: Bool = false
    @State private var pulseAnimation: Bool = false
    
    /// Gold gradient for header buttons (matches Tax/DeFi pages)
    private var chipGoldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    enum BotTab: String, CaseIterable {
        case paper = "Paper Bots"
        case strategies = "Strategies"
        case live = "Live Bots"
        
        var icon: String {
            switch self {
            case .paper: return "doc.text"
            case .strategies: return "cpu"
            case .live: return "bolt.fill"
            }
        }
    }
    
    // MARK: - Current Trading Mode
    
    private enum TradingMode {
        case demo
        case paper
        case live
        
        var title: String {
            switch self {
            case .demo: return "Demo Mode"
            case .paper: return "Paper Trading"
            case .live: return "Live Trading"
            }
        }
        
        var subtitle: String {
            switch self {
            case .demo: return "Viewing sample bots"
            case .paper: return "Practice with virtual funds"
            case .live: return "Connected to 3Commas"
            }
        }
        
        var icon: String {
            switch self {
            case .demo: return AppTradingMode.demo.icon
            case .paper: return AppTradingMode.paper.icon
            case .live: return AppTradingMode.liveTrading.icon
            }
        }
        
        var color: Color {
            switch self {
            case .demo: return AppTradingMode.demo.color     // Gold (single source of truth)
            case .paper: return AppTradingMode.paper.color
            case .live: return AppTradingMode.liveTrading.color
            }
        }
        
        /// Maps to AppTradingMode for use with the shared ModeBadge
        var appMode: AppTradingMode {
            switch self {
            case .demo: return .demo
            case .paper: return .paper
            case .live: return .liveTrading
            }
        }
    }
    
    private var currentMode: TradingMode {
        if demoModeManager.isDemoMode {
            return .demo
        } else if paperTradingManager.isPaperTradingEnabled {
            return .paper
        } else {
            return .live
        }
    }
    
    // MARK: - Bot Counts (mode-aware)
    
    private var paperBotCount: Int {
        if demoModeManager.isDemoMode {
            return paperBotManager.demoBotCount
        }
        return paperBotManager.totalBotCount
    }
    
    private var runningPaperBotCount: Int {
        if demoModeManager.isDemoMode {
            return paperBotManager.runningDemoBotCount
        }
        return paperBotManager.runningBotCount
    }
    
    private var totalPaperBotProfit: Double {
        if demoModeManager.isDemoMode {
            return paperBotManager.totalDemoBotProfit
        }
        return paperBotManager.paperBots.reduce(0) { $0 + $1.totalProfit }
    }
    
    private var displayedPaperBots: [PaperBot] {
        if demoModeManager.isDemoMode {
            return paperBotManager.demoBots
        }
        return paperBotManager.paperBots
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header (matching Tax/DeFi pattern)
            customHeader
            
            // Mode indicator banner
            modeBanner
            
            // Custom segmented control
            segmentedControl
            
            // Help banner - explains how bots work
            if showHelpBanner {
                helpBanner
            }
            
            // Connection status banner (for live bots, not in demo mode)
            if selectedTab == .live && !liveBotManager.isConfigured && !demoModeManager.isDemoMode {
                connectionBanner
            }
            
            // Content based on selected tab (Live Bots only available in developer mode)
            TabView(selection: $selectedTab) {
                // Paper Bots Tab (always available)
                paperBotsContent
                    .tag(BotTab.paper)
                
                // Strategies Tab (always available)
                strategiesContent
                    .tag(BotTab.strategies)
                
                // Live Bots Tab (developer mode only)
                if subscriptionManager.isDeveloperMode {
                    liveBotsContent
                        .tag(BotTab.live)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .sheet(isPresented: $showStrategyBuilder) {
                StrategyBuilderView()
            }
            .sheet(isPresented: $showStrategyTemplates) {
                StrategyTemplatesView()
            }
            .sheet(isPresented: $showLearningHub) {
                StrategyLearningHub()
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .onAppear {
            // Seed demo data when in demo mode
            if demoModeManager.isDemoMode {
                paperBotManager.seedDemoBots()
                paperTradingManager.seedDemoTrades()
                liveBotManager.seedDemoLiveBots()
            }
            
            // Set initial tab based on trading mode
            // Live Bots tab only available in developer mode
            if paperTradingManager.isPaperTradingEnabled || demoModeManager.isDemoMode {
                selectedTab = .paper
            } else if liveBotManager.isConfigured && subscriptionManager.isDeveloperMode {
                selectedTab = .live
            } else {
                selectedTab = .paper
            }
            
            // Show welcome toast if navigating from Social copy
            if highlightBotId != nil {
                selectedTab = .paper  // Copied bots go to paper tab
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        showCopyWelcome = true
                    }
                    // Auto-dismiss after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showCopyWelcome = false
                        }
                    }
                }
            }
            
            // Trigger entrance animations for stats
            withAnimation(.easeOut(duration: 0.5)) {
                statsAppeared = true
            }
            // Start pulse animation for active bots
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
        .overlay(alignment: .top) {
            // Copy welcome toast
            if showCopyWelcome {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bot Ready!")
                            .font(.subheadline.weight(.semibold))
                        Text("Tap Start to begin trading")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showCopyWelcome = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
                }
                .padding(.horizontal)
                .padding(.top, 100)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .onDemoModeChange { isDemoMode in
            if isDemoMode {
                paperBotManager.seedDemoBots()
                paperTradingManager.seedDemoTrades()
                liveBotManager.seedDemoLiveBots()
                selectedTab = .paper
            } else {
                paperBotManager.clearDemoBots()
                paperTradingManager.clearDemoTrades()
                liveBotManager.clearDemoLiveBots()
            }
        }
        // Floating AI Helper button
        .overlay(alignment: .bottomTrailing) {
            floatingAIButton
        }
        // AI Helper sheet - context-aware based on selected tab
        .sheet(isPresented: $showAIHelper) {
            ContextualAIHelperView(context: selectedTab == .strategies ? .strategies : .bots)
        }
    }
    
    // MARK: - Floating AI Button
    
    private var floatingAIButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showAIHelper = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("Ask AI")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                Capsule()
                    .stroke(DS.Adaptive.stroke, lineWidth: 1.5)
            )
        }
        .padding(.trailing, 20)
        .padding(.bottom, 100) // Above tab bar
        .buttonStyle(.plain)
    }
    
    // MARK: - Custom Header
    
    private var customHeader: some View {
        HStack(spacing: 0) {
            // Back button
            CSNavButton(
                icon: "chevron.left",
                action: { dismiss() }
            )
            
            Spacer()
            
            // Title
            Text("My Bots")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            // Add Bot button (only show if not in demo mode)
            if !demoModeManager.isDemoMode {
                NavigationLink {
                    TradingBotView(
                        side: TradeSide.buy,
                        orderType: OrderType.market,
                        quantity: 0,
                        slippage: 0.5
                    )
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(chipGoldGradient)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Create Bot")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(DS.Adaptive.background.opacity(0.95))
    }
    
    // MARK: - Mode Banner
    
    private var modeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: currentMode.icon)
                .font(.system(size: 14))
                .foregroundColor(currentMode.color)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(currentMode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(currentMode.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            // Mode badge — shared ModeBadge for consistent styling
            ModeBadge(mode: currentMode.appMode, variant: .compact)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(currentMode.color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(currentMode.color.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Segmented Control
    
    private var segmentedControl: some View {
        HStack(spacing: 0) {
            // Only show tabs available for current user (Live Bots requires developer mode)
            ForEach(availableTabs, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12))
                        
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                        
                        // Count badge (mode-aware for paper bots, strategies, and live bots)
                        let count: Int = {
                            switch tab {
                            case .paper: return paperBotCount
                            case .strategies: return strategyEngine.activeStrategies.count
                            case .live: return liveBotManager.totalBotCount
                            }
                        }()
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(selectedTab == tab ? .black : DS.Adaptive.textPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(selectedTab == tab ? Color.black.opacity(0.2) : DS.Adaptive.overlay(0.2))
                                )
                        }
                    }
                    .foregroundColor(selectedTab == tab ? .black : DS.Adaptive.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        ZStack {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        AdaptiveGradients.goldButton(isDark: colorScheme == .dark)
                                    )
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.overlay(0.08))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Help Banner
    
    private var helpBanner: some View {
        VStack(spacing: 0) {
            // Header - always visible
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isHelpExpanded.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                    
                    Text("How Bots Work")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Spacer()
                    
                    // Dismiss button
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showHelpBanner = false
                            UserDefaults.standard.set(true, forKey: Self.helpBannerDismissedKey)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .padding(6)
                            .background(Circle().fill(DS.Adaptive.overlay(0.1)))
                    }
                    
                    Image(systemName: isHelpExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            
            // Expanded content
            if isHelpExpanded {
                Divider()
                    .background(DS.Adaptive.divider)
                
                VStack(alignment: .leading, spacing: 12) {
                    // Contextual tips based on selected tab
                    if selectedTab == .paper {
                        helpItem(
                            icon: "doc.text.fill",
                            iconColor: .blue,
                            title: "Paper Bots",
                            description: "Practice trading with virtual funds. No real money is used - perfect for testing strategies!"
                        )
                        
                        helpItem(
                            icon: "play.circle.fill",
                            iconColor: .green,
                            title: "Start a Bot",
                            description: "Tap the play button on any bot to start it. The bot will automatically execute trades based on its strategy."
                        )
                        
                        helpItem(
                            icon: "square.and.arrow.down",
                            iconColor: .purple,
                            title: "Copy Trading",
                            description: "Browse the Bot Marketplace in the Social tab to copy successful strategies from other traders."
                        )
                    } else {
                        helpItem(
                            icon: "bolt.fill",
                            iconColor: .green,
                            title: "Live Bots",
                            description: "Real trading bots connected via 3Commas. These use actual funds from your exchange account."
                        )
                        
                        helpItem(
                            icon: "link.badge.plus",
                            iconColor: .orange,
                            title: "Connect 3Commas",
                            description: "Link your 3Commas account to view and control your live trading bots from this app."
                        )
                        
                        helpItem(
                            icon: "exclamationmark.triangle.fill",
                            iconColor: .yellow,
                            title: "Real Money",
                            description: "Live bots trade with real funds. Always start with paper trading to test your strategies first."
                        )
                    }
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    private func helpItem(icon: String, iconColor: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(iconColor.opacity(0.15))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // MARK: - Connection Banner
    
    private var connectionBanner: some View {
        NavigationLink(destination: Link3CommasView()) {
            HStack(spacing: 12) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect 3Commas")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text("Link your account to manage live bots")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Paper Bots Content
    
    private var paperBotsContent: some View {
        Group {
            if displayedPaperBots.isEmpty {
                emptyPaperBotsView
            } else {
                paperBotsList
            }
        }
    }
    
    private var emptyPaperBotsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)
                
                // Premium Empty State Card
                PremiumGlassCard(showGoldAccent: true, cornerRadius: 20) {
                    VStack(spacing: 20) {
                        // Animated CPU icon with glow ring
                        ZStack {
                            // Outer glow
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [BrandColors.goldBase.opacity(statsAppeared ? 0.25 : 0.1), Color.clear],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 70
                                    )
                                )
                                .frame(width: 140, height: 140)
                                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: statsAppeared)
                            
                            // Gold ring stroke
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [BrandColors.goldLight.opacity(0.7), BrandColors.goldBase.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 100, height: 100)
                            
                            // Inner background
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [BrandColors.goldBase.opacity(0.15), BrandColors.goldBase.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 96, height: 96)
                            
                            Image(systemName: "cpu")
                                .font(.system(size: 44, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .padding(.top, 8)
                        
                        // Title and description
                        VStack(spacing: 8) {
                            Text("No Paper Bots Yet")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            if demoModeManager.isDemoMode {
                                Text("Demo bots will appear here.\nExit Demo Mode to create your own bots.")
                                    .font(.system(size: 14))
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                    .multilineTextAlignment(.center)
                            } else {
                                Text("Create your first paper trading bot to\npractice automated strategies risk-free.")
                                    .font(.system(size: 14))
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        
                        // CTA Buttons - only show if not in demo mode
                        if !demoModeManager.isDemoMode {
                            VStack(spacing: 12) {
                                // Primary CTA - Create Bot
                                NavigationLink(destination: TradingBotView(
                                    side: TradeSide.buy,
                                    orderType: OrderType.market,
                                    quantity: 0,
                                    slippage: 0.5
                                )) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 16))
                                        Text("Create Paper Bot")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        Capsule()
                                            .fill(
                                                AdaptiveGradients.goldButton(isDark: colorScheme == .dark)
                                            )
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [BrandColors.goldLight.opacity(0.6), BrandColors.goldBase.opacity(0.3)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                
                                // Secondary CTA - Ask AI
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    showAIHelper = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("Not sure? Ask AI for help")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, 20)
                
                // Quick bot creation cards (when not in demo mode)
                if !demoModeManager.isDemoMode {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Start")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .padding(.horizontal, 4)
                        
                        // Horizontal scroll of bot type cards
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(QuickBotType.allCases) { type in
                                    QuickBotCard(type: type, onTap: {})
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer(minLength: 100)
            }
        }
    }
    
    private var paperBotsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Stats summary (mode-aware)
                botStatsSummary(
                    total: paperBotCount,
                    running: runningPaperBotCount,
                    totalProfit: totalPaperBotProfit,
                    isDemo: demoModeManager.isDemoMode
                )
                
                // Quick bot creation cards (only show when not in demo mode)
                if !demoModeManager.isDemoMode {
                    quickBotCreationSection
                }
                
                // Trading bots section header
                if !displayedPaperBots.isEmpty {
                    sectionHeader(title: "Trading Bots", count: displayedPaperBots.count)
                }
                
                // Bot rows (mode-aware)
                ForEach(displayedPaperBots) { bot in
                    if demoModeManager.isDemoMode {
                        // Demo bots are view-only
                        DemoBotRowView(bot: bot)
                    } else {
                        PaperBotRowView(
                            bot: bot,
                            onToggle: {
                                paperBotManager.toggleBot(id: bot.id)
                            },
                            onDelete: {
                                paperBotManager.deleteBot(id: bot.id)
                            }
                        )
                    }
                }
                
                // Prediction Bots Section
                if !demoModeManager.isDemoMode {
                    predictionBotsSectionPaper
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 100)
        }
        .refreshable {
            await refreshPaperBots()
        }
    }
    
    // MARK: - Prediction Bots Section (Paper)
    
    @ObservedObject private var predictionTradingService = PredictionTradingService.shared
    
    private var paperPredictionBots: [PaperBot] {
        paperBotManager.paperBots.filter { $0.type == .predictionMarket }
    }
    
    private var predictionBotsSectionPaper: some View {
        VStack(spacing: 12) {
            // Section header with link to Prediction Bot creation
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis.ascending")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cyan)
                    Text("Prediction Bots")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text("(\(paperPredictionBots.count))")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                NavigationLink(destination: PredictionBotView()) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("New")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.cyan.opacity(0.15))
                    )
                }
            }
            .padding(.top, 8)
            
            if paperPredictionBots.isEmpty {
                // Empty state for prediction bots
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 28))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text("No prediction bots yet")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Text("Trade on Polymarket & Kalshi with AI assistance")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    NavigationLink(destination: PredictionBotView()) {
                        Text("Create Prediction Bot")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.cyan)
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DS.Adaptive.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                .foregroundColor(Color.cyan.opacity(0.3))
                        )
                )
            } else {
                // Paper prediction bot rows
                ForEach(paperPredictionBots) { bot in
                    PaperBotRowView(
                        bot: bot,
                        onToggle: {
                            paperBotManager.toggleBot(id: bot.id)
                        },
                        onDelete: {
                            paperBotManager.deleteBot(id: bot.id)
                        }
                    )
                }
            }
        }
    }
    
    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            Text("(\(count))")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
            Spacer()
        }
        .padding(.top, 8)
    }
    
    // MARK: - Strategies Content
    
    private var strategiesContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Quick actions header
                strategyQuickActions
                
                // Active strategies section
                activeStrategiesSection
                
                // Learning resources
                learningResourcesSection
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(DS.Adaptive.background)
    }
    
    private var strategyQuickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            HStack(spacing: 12) {
                // Create Strategy button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showStrategyBuilder = true
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(BrandColors.goldBase.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [BrandColors.goldBase, BrandColors.goldLight],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        Text("Create")
                            .font(.caption.weight(.medium))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DS.Adaptive.cardBackground)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
                
                // Templates button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showStrategyTemplates = true
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.purple)
                        }
                        Text("Templates")
                            .font(.caption.weight(.medium))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DS.Adaptive.cardBackground)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
                
                // Learn button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showLearningHub = true
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "graduationcap.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.blue)
                        }
                        Text("Learn")
                            .font(.caption.weight(.medium))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(DS.Adaptive.cardBackground)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var activeStrategiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Strategies")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                if !strategyEngine.activeStrategies.isEmpty {
                    Text("\(strategyEngine.activeStrategies.count)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BrandColors.goldBase)
                        .cornerRadius(8)
                }
            }
            
            if strategyEngine.activeStrategies.isEmpty {
                // Empty state - Enhanced with better icon and AI option
                VStack(spacing: 16) {
                    // Icon with subtle gradient glow
                    ZStack {
                        Circle()
                            .fill(Color.indigo.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "function")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.indigo, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(spacing: 6) {
                        Text("No Strategies Yet")
                            .font(.title3.weight(.bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Create your first algorithmic trading strategy or start from a template")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    
                    // Two-row CTA layout
                    VStack(spacing: 10) {
                        // Primary row: Create and Templates
                        HStack(spacing: 10) {
                            Button {
                                showStrategyBuilder = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Create Strategy")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundColor(DS.Adaptive.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(DS.Adaptive.overlay(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                )
                                .cornerRadius(10)
                            }
                            
                            Button {
                                showStrategyTemplates = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.on.doc.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Browse Templates")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundColor(DS.Adaptive.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(DS.Adaptive.overlay(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                )
                                .cornerRadius(10)
                            }
                        }
                        
                        // Secondary row: Ask AI to create strategy
                        Button {
                            showAIHelper = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                Text("Describe to AI & Generate")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(BrandColors.goldBase.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(BrandColors.goldBase.opacity(0.25), lineWidth: 1)
                            )
                            .cornerRadius(10)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.indigo.opacity(0.2), Color.purple.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            } else {
                // Strategy list
                LazyVStack(spacing: 8) {
                    ForEach(strategyEngine.activeStrategies) { strategy in
                        StrategyRowView(strategy: strategy)
                    }
                }
            }
        }
    }
    
    private var learningResourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Learn & Improve")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            VStack(spacing: 8) {
                // Learning hub link
                Button {
                    showLearningHub = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Strategy Academy")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            Text("Learn indicators, strategies & risk management")
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .padding(12)
                    .background(DS.Adaptive.cardBackground)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                // AI Advisor link - coming soon or link to AI tab
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundColor(BrandColors.goldBase)
                        .frame(width: 36, height: 36)
                        .background(BrandColors.goldBase.opacity(0.15))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Strategy Advisor")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text("Get AI-powered strategy suggestions")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Ask AI")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BrandColors.goldBase.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(6)
                }
                .padding(12)
                .background(DS.Adaptive.cardBackground)
                .cornerRadius(12)
                .onTapGesture {
                    showAIHelper = true
                }
            }
        }
    }
    
    // MARK: - Live Bots Content
    
    private var liveBotsContent: some View {
        Group {
            if demoModeManager.isDemoMode {
                // In demo mode, show demo live bots
                if liveBotManager.demoBots.isEmpty {
                    emptyDemoLiveBotsView
                } else {
                    demoLiveBotsList
                }
            } else if !liveBotManager.isConfigured {
                notConfiguredView
            } else if liveBotManager.bots.isEmpty {
                emptyLiveBotsView
            } else {
                liveBotsList
            }
        }
    }
    
    private var emptyDemoLiveBotsView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(BrandColors.goldBase.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "cpu")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 10) {
                Text("Demo Live Bots")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Sample live trading bots will appear here for demonstration purposes.")
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
    }
    
    private var demoLiveBotsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(liveBotManager.demoBots) { bot in
                    DemoLiveBotRowView(bot: bot)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
    
    private var notConfiguredView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Illustration
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "link.circle")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 10) {
                Text("Connect 3Commas")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Link your 3Commas account to view and manage your live trading bots.")
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            // CTA Button
            NavigationLink(destination: Link3CommasView()) {
                HStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 16))
                    Text("Connect Account")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            
            Spacer()
        }
    }
    
    private var emptyLiveBotsView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 10) {
                Text("No Live Bots")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("You don't have any live bots on 3Commas. Create one in the 3Commas app to see it here.")
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button {
                Task { await liveBotManager.refreshBots() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(BrandColors.goldBase)
            }
            
            Spacer()
        }
    }
    
    private var liveBotsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Stats summary
                botStatsSummary(
                    total: liveBotManager.totalBotCount + predictionTradingService.liveBots.count,
                    running: liveBotManager.enabledBotCount + predictionTradingService.liveBots.filter { $0.isEnabled }.count,
                    totalProfit: liveBotManager.totalProfitUsd,
                    isDemo: false
                )
                
                // 3Commas bots section header (if there are any)
                if !liveBotManager.bots.isEmpty {
                    sectionHeader(title: "3Commas Bots", count: liveBotManager.bots.count)
                }
                
                // Bot rows (using LiveBotRowView from LiveBotsListView)
                ForEach(liveBotManager.bots) { bot in
                    LiveBotRowView(
                        bot: bot,
                        isToggling: liveBotManager.togglingBotIds.contains(bot.id),
                        onToggle: {
                            Task {
                                if bot.isEnabled {
                                    await liveBotManager.disableBot(id: bot.id)
                                } else {
                                    await liveBotManager.enableBot(id: bot.id)
                                }
                            }
                        }
                    )
                }
                
                // Live Prediction Bots Section
                predictionBotsSectionLive
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 100)
        }
        .refreshable {
            await liveBotManager.refreshBots()
        }
    }
    
    // MARK: - Prediction Bots Section (Live)
    
    private var predictionBotsSectionLive: some View {
        VStack(spacing: 12) {
            // Section header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis.ascending")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cyan)
                    Text("Live Prediction Bots")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text("(\(predictionTradingService.liveBots.count))")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                NavigationLink(destination: PredictionBotView()) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("New")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.cyan.opacity(0.15))
                    )
                }
            }
            .padding(.top, 8)
            
            // Wallet status
            if !predictionTradingService.isWalletConnected {
                walletConnectionPrompt
            } else if predictionTradingService.liveBots.isEmpty {
                // Empty state for live prediction bots
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 28))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text("No live prediction bots")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Text("Trade with real USDC on Polymarket & Kalshi")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    NavigationLink(destination: PredictionBotView()) {
                        Text("Create Live Bot")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.green)
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DS.Adaptive.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                .foregroundColor(Color.green.opacity(0.3))
                        )
                )
            } else {
                // Live prediction bot rows
                ForEach(predictionTradingService.liveBots) { bot in
                    LivePredictionBotCard(bot: bot) {
                        // Navigate to detail
                    }
                }
            }
        }
    }
    
    private var walletConnectionPrompt: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "wallet.pass")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallet Not Connected")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text("Connect wallet with USDC on Polygon for live trading")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
            }
            
            NavigationLink(destination: WalletConnectView()) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                    Text("Connect Wallet")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(BrandColors.goldBase)
                .cornerRadius(10)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Premium Stats Header
    
    private func botStatsSummary(total: Int, running: Int, totalProfit: Double?, isDemo: Bool = false) -> some View {
        VStack(spacing: 0) {
            // Demo indicator banner if applicable
            if isDemo {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [BrandColors.goldLight, BrandColors.goldBase],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("Sample Bot Statistics")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BrandColors.goldBase)
                }
                .padding(.bottom, 10)
            }
            
            // Premium stat cards grid
            HStack(spacing: 10) {
                // Total Bots
                BotPremiumStatCard(
                    icon: "cpu",
                    label: "Total Bots",
                    value: "\(total)",
                    gradient: [Color.blue.opacity(0.8), Color.blue],
                    isActive: total > 0,
                    pulseAnimation: pulseAnimation
                )
                .opacity(statsAppeared ? 1 : 0)
                .offset(y: statsAppeared ? 0 : 20)
                
                // Running Bots
                BotPremiumStatCard(
                    icon: "play.circle.fill",
                    label: "Running",
                    value: "\(running)",
                    gradient: [Color.green.opacity(0.8), Color.green],
                    isActive: running > 0,
                    pulseAnimation: pulseAnimation
                )
                .opacity(statsAppeared ? 1 : 0)
                .offset(y: statsAppeared ? 0 : 20)
                .animation(.easeOut(duration: 0.5).delay(0.1), value: statsAppeared)
                
                // Stopped Bots
                BotPremiumStatCard(
                    icon: "stop.circle.fill",
                    label: "Stopped",
                    value: "\(total - running)",
                    gradient: [Color.red.opacity(0.8), Color.red],
                    isActive: (total - running) > 0,
                    pulseAnimation: false
                )
                .opacity(statsAppeared ? 1 : 0)
                .offset(y: statsAppeared ? 0 : 20)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: statsAppeared)
                
                // Total P/L (if available)
                if let profit = totalProfit {
                    BotPremiumStatCard(
                        icon: "dollarsign.circle.fill",
                        label: "Total P/L",
                        value: formatProfitLoss(profit),
                        gradient: profit >= 0 
                            ? [BrandColors.goldLight, BrandColors.goldBase]
                            : [Color.red.opacity(0.8), Color.red],
                        isActive: abs(profit) > 0,
                        pulseAnimation: pulseAnimation
                    )
                    .opacity(statsAppeared ? 1 : 0)
                    .offset(y: statsAppeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.5).delay(0.3), value: statsAppeared)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark 
                            ? [Color(white: 0.08), Color(white: 0.05)]
                            : [DS.Adaptive.cardBackground, DS.Adaptive.cardBackground.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [BrandColors.goldBase.opacity(0.3), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Quick Bot Creation Section
    
    private var quickBotCreationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack {
                Text("Quick Create")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                // AI suggestion button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showAIHelper = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Ask AI")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
            
            // Horizontal scroll of bot type cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // DCA Bot
                    QuickBotCard(
                        type: .dca,
                        onTap: { /* Navigation handled by NavigationLink */ }
                    )
                    
                    // Grid Bot
                    QuickBotCard(
                        type: .grid,
                        onTap: { /* Navigation handled by NavigationLink */ }
                    )
                    
                    // Signal Bot
                    QuickBotCard(
                        type: .signal,
                        onTap: { /* Navigation handled by NavigationLink */ }
                    )
                    
                    // Prediction Bot
                    QuickBotCard(
                        type: .prediction,
                        onTap: { /* Navigation handled by NavigationLink */ }
                    )
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func refreshPaperBots() async {
        // Paper bots are local, just trigger a UI refresh
        paperBotManager.objectWillChange.send()
    }
    
    private func formatProfitLoss(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        let absValue = abs(value)
        if absValue >= 1000 {
            return "\(prefix)$\(String(format: "%.1fK", value / 1000))"
        }
        return "\(prefix)$\(String(format: "%.2f", value))"
    }
}

// MARK: - Demo Bot Row View

/// A view-only row for displaying demo bots (no toggle/delete actions)
struct DemoBotRowView: View {
    let bot: PaperBot
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDetails: Bool = false
    
    private var isRunning: Bool {
        bot.status == .running
    }
    
    var body: some View {
        VStack(spacing: 0) {
            mainRowContent
            expandedDetailsContent
        }
        .background(rowBackground)
        .overlay(rowOverlay)
    }
    
    // MARK: - Main Row
    
    private var mainRowContent: some View {
        HStack(spacing: 12) {
            botIconView
            botInfoView
            Spacer()
            profitLossView
            actionButtonsView
        }
        .padding(14)
    }
    
    private var botIconView: some View {
        ZStack {
            Circle()
                .fill(bot.type.color.opacity(0.15))
                .frame(width: 44, height: 44)
            
            Image(systemName: bot.type.icon)
                .font(.system(size: 18))
                .foregroundColor(bot.type.color)
        }
    }
    
    private var botInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(bot.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                // Status badge - fixed size to prevent wrapping
                HStack(spacing: 4) {
                    Circle()
                        .fill(bot.status.color)
                        .frame(width: 6, height: 6)
                    Text(bot.status.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(bot.status.color)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(bot.status.color.opacity(0.15)))
                .fixedSize()
            }
            
            HStack(spacing: 5) {
                Text(bot.type.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .lineLimit(1)
                
                Text("•")
                    .foregroundColor(DS.Adaptive.textTertiary.opacity(0.5))
                
                Text(bot.tradingPair.replacingOccurrences(of: "_", with: "/"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(1)
                
                Text("•")
                    .foregroundColor(DS.Adaptive.textTertiary.opacity(0.5))
                
                Text(bot.exchange)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .lineLimit(1)
                
                // Demo indicator - compact sparkle icon
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BrandColors.goldBase)
            }
        }
        .layoutPriority(1)
    }
    
    // MARK: - P/L Summary (visible without expanding)
    
    private var profitLossView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(formatProfit(bot.totalProfit))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(bot.totalProfit >= 0 ? .green : .red)
                .lineLimit(1)
            
            Text("\(bot.totalTrades) trades")
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textTertiary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    
    // MARK: - Action Buttons (View-only for demo)
    
    private var actionButtonsView: some View {
        // Expand button only (no toggle for demo)
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showDetails.toggle()
            }
        } label: {
            Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(DS.Adaptive.overlay(0.08)))
        }
    }
    
    // MARK: - Expanded Details
    
    @ViewBuilder
    private var expandedDetailsContent: some View {
        if showDetails {
            Divider()
                .background(DS.Adaptive.divider)
            
            VStack(spacing: 12) {
                configDetailsRow
                statsRow
                demoNotice
            }
            .padding(14)
            .padding(.top, 2)
        }
    }
    
    private var configDetailsRow: some View {
        HStack(spacing: 20) {
            if let direction = bot.direction {
                detailItem(label: "Direction", value: direction)
            }
            if let tp = bot.takeProfit {
                detailItem(label: "Take Profit", value: "\(tp)%")
            }
            if let sl = bot.stopLoss {
                detailItem(label: "Stop Loss", value: "\(sl)%")
            }
            if let leverage = bot.leverage {
                detailItem(label: "Leverage", value: "\(leverage)x")
            }
        }
    }
    
    private var statsRow: some View {
        HStack(spacing: 20) {
            detailItem(label: "Total Trades", value: "\(bot.totalTrades)")
            detailItem(label: "Profit", value: formatProfit(bot.totalProfit), color: bot.totalProfit >= 0 ? .green : .red)
            detailItem(label: "Created", value: formatDate(bot.createdAt))
        }
    }
    
    private var demoNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
            Text("This is a sample bot for demonstration purposes")
                .font(.system(size: 12))
        }
        .foregroundColor(BrandColors.goldBase.opacity(0.8))
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(BrandColors.goldBase.opacity(0.1))
        )
    }
    
    // MARK: - Background & Overlay
    
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(DS.Adaptive.cardBackground)
    }
    
    private var rowOverlay: some View {
        let strokeColor = isRunning ? bot.status.color.opacity(0.3) : DS.Adaptive.stroke
        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(strokeColor, lineWidth: 1)
    }
    
    // MARK: - Helpers
    
    private func detailItem(label: String, value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color ?? DS.Adaptive.textPrimary)
        }
    }
    
    private func formatProfit(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        let absValue = abs(value)
        if absValue >= 1000 {
            return "\(prefix)$\(String(format: "%.1fK", value / 1000))"
        }
        return "\(prefix)$\(String(format: "%.2f", value))"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Demo Live Bot Row View

struct DemoLiveBotRowView: View {
    let bot: ThreeCommasBot
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDetails: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            mainRowContent
            
            if showDetails {
                expandedDetailsContent
            }
        }
        .background(rowBackground)
        .overlay(rowOverlay)
    }
    
    // MARK: - Main Row
    
    private var mainRowContent: some View {
        HStack(spacing: 12) {
            botIconView
            botInfoView
            Spacer()
            profitLossView
            chevronButton
        }
        .padding(14)
    }
    
    private var botIconView: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 44, height: 44)
            
            Image(systemName: "cpu")
                .font(.system(size: 18))
                .foregroundColor(.blue)
        }
    }
    
    private var botInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(bot.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                // Status badge - fixed size to prevent wrapping
                HStack(spacing: 4) {
                    Circle()
                        .fill(bot.isEnabled ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(bot.isEnabled ? "Running" : "Stopped")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(bot.isEnabled ? .green : .red)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill((bot.isEnabled ? Color.green : Color.red).opacity(0.15)))
                .fixedSize()
            }
            
            HStack(spacing: 5) {
                Text(bot.strategy.rawValue.capitalized)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .lineLimit(1)
                
                Text("•")
                    .foregroundColor(DS.Adaptive.textTertiary.opacity(0.5))
                
                Text(bot.primaryPair.replacingOccurrences(of: "_", with: "/"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(1)
                
                Text("•")
                    .foregroundColor(DS.Adaptive.textTertiary.opacity(0.5))
                
                Text(bot.accountName ?? "Demo Account")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .lineLimit(1)
                
                // Demo indicator - compact sparkle icon
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BrandColors.goldBase)
            }
        }
        .layoutPriority(1)
    }
    
    // MARK: - P/L Summary (visible without expanding)
    
    private var profitLossView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(formatProfit(bot.totalProfitUsd))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(bot.totalProfitUsd >= 0 ? .green : .red)
                .lineLimit(1)
            
            let deals = (bot.closedDealsCount ?? 0)
            Text("\(deals) trades")
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textTertiary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var chevronButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                showDetails.toggle()
            }
        } label: {
            Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(DS.Adaptive.overlay(0.06)))
        }
    }
    
    // MARK: - Expanded Details
    
    private var expandedDetailsContent: some View {
        VStack(spacing: 12) {
            Divider()
                .background(DS.Adaptive.divider)
            
            // Stats row
            HStack(spacing: 20) {
                detailItem(label: "Active Deals", value: "\(bot.activeDealsCount ?? 0)")
                detailItem(label: "Closed Deals", value: "\(bot.closedDealsCount ?? 0)")
                detailItem(
                    label: "Total Profit",
                    value: formatProfit(bot.totalProfitUsd),
                    color: bot.totalProfitUsd >= 0 ? .green : .red
                )
            }
            
            // Config row
            HStack(spacing: 20) {
                if let baseOrder = bot.baseOrderVolume {
                    detailItem(label: "Base Order", value: "$\(String(format: "%.0f", baseOrder))")
                }
                if let tp = bot.takeProfit {
                    detailItem(label: "Take Profit", value: "\(tp)%")
                }
                if let maxDeals = bot.maxActiveDeals {
                    detailItem(label: "Max Deals", value: "\(maxDeals)")
                }
            }
            
            // Demo notice
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                Text("This is a sample 3Commas bot for demonstration")
                    .font(.system(size: 12))
            }
            .foregroundColor(BrandColors.goldBase.opacity(0.8))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(BrandColors.goldBase.opacity(0.1))
            )
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
    
    // MARK: - Background & Overlay
    
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(DS.Adaptive.cardBackground)
    }
    
    private var rowOverlay: some View {
        let strokeColor = bot.isEnabled ? Color.green.opacity(0.3) : DS.Adaptive.stroke
        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(strokeColor, lineWidth: 1)
    }
    
    // MARK: - Helpers
    
    private func detailItem(label: String, value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color ?? DS.Adaptive.textPrimary)
        }
    }
    
    private func formatProfit(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        let absValue = abs(value)
        if absValue >= 1000 {
            return "\(prefix)$\(String(format: "%.1fK", value / 1000))"
        }
        return "\(prefix)$\(String(format: "%.2f", value))"
    }
}

// MARK: - Bot Premium Stat Card

/// A premium-styled stat card for the bot stats header with gradient background and animations
private struct BotPremiumStatCard: View {
    let icon: String
    let label: String
    let value: String
    let gradient: [Color]
    let isActive: Bool
    let pulseAnimation: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 6) {
            // Icon with subtle glow when active
            ZStack {
                if isActive && pulseAnimation {
                    Circle()
                        .fill(gradient[0].opacity(pulseAnimation ? 0.3 : 0.15))
                        .frame(width: 32, height: 32)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
                }
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            // Value with emphasized styling
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(isDark ? .white : DS.Adaptive.textPrimary)
            
            // Label
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isDark ? .gray : DS.Adaptive.textTertiary)
                .textCase(.uppercase)
                .tracking(0.3)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isDark
                        ? LinearGradient(
                            colors: [Color.white.opacity(isActive ? 0.08 : 0.04), Color.white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        : LinearGradient(
                            colors: [DS.Adaptive.cardBackground, DS.Adaptive.cardBackground.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isActive 
                        ? gradient[0].opacity(isDark ? 0.3 : 0.4) 
                        : (isDark ? Color.white.opacity(0.06) : DS.Adaptive.stroke),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Quick Bot Type
// NOTE: QuickBotType is defined in SmartTradingHub.swift as a shared enum

// MARK: - Quick Bot Card

/// A quick action card for creating bots
private struct QuickBotCard: View {
    let type: QuickBotType
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed: Bool = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        NavigationLink {
            if type == .prediction {
                PredictionBotView()
            } else {
                TradingBotView(
                    side: TradeSide.buy,
                    orderType: OrderType.market,
                    quantity: 0,
                    slippage: 0.5,
                    initialMode: type.botCreationMode
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Icon with colored background
                ZStack {
                    Circle()
                        .fill(type.color.opacity(isDark ? 0.2 : 0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: type.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(type.color)
                }
                
                // Title
                Text(type.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                // Subtitle
                Text(type.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 110)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [type.color.opacity(isDark ? 0.3 : 0.25), type.color.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) { isPressed = false }
                }
        )
    }
}

// MARK: - Strategy Row View

struct StrategyRowView: View {
    let strategy: TradingStrategy
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDetail = false
    
    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: 12) {
                // Status indicator
                Circle()
                    .fill(strategy.isEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                // Strategy info
                VStack(alignment: .leading, spacing: 4) {
                    Text(strategy.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    HStack(spacing: 8) {
                        Text(strategy.tradingPair)
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        Text("•")
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text(strategy.timeframe.shortName)
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        Text("•")
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text("\(strategy.entryConditions.count) conditions")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
                
                Spacer()
                
                // Backtest grade if available
                if let backtest = strategy.backtestResults {
                    Text(backtest.performanceGrade)
                        .font(.caption.weight(.bold))
                        .foregroundColor(gradeColor(backtest.performanceGrade))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(gradeColor(backtest.performanceGrade).opacity(0.15))
                        .cornerRadius(6)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(14)
            .background(DS.Adaptive.cardBackground)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            StrategyBuilderView(existingStrategy: strategy)
        }
    }
    
    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .green
        case "B": return .blue
        case "C": return .orange
        case "D": return .orange
        default: return .red
        }
    }
}

// MARK: - Preview

#if DEBUG
struct BotHubView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BotHubView()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
