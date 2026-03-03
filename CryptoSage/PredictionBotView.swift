//
//  PredictionBotView.swift
//  CryptoSage
//
//  AI-powered prediction market bot creation view.
//  Allows users to create both paper and live trading bots for Polymarket/Kalshi markets
//  with AI-assisted strategy generation.
//

import SwiftUI

// MARK: - Trading Mode

enum PredictionTradingMode: String, CaseIterable, Identifiable {
    case paper = "Paper"
    case live = "Live"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .paper: return "Paper Trading"
        case .live: return "Live Trading"
        }
    }
    
    var description: String {
        switch self {
        case .paper: return "Practice with simulated funds"
        case .live: return "Trade with real USDC"
        }
    }
    
    var icon: String {
        switch self {
        case .paper: return "doc.text.fill"
        case .live: return "bolt.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .paper: return AppTradingMode.paper.color  // Warm amber for paper trading
        case .live: return .green
        }
    }
}

// MARK: - Prediction Bot View Model

@MainActor
class PredictionBotViewModel: ObservableObject {
    
    enum BotTab: String, CaseIterable, Identifiable {
        case chat = "AI Chat"
        case markets = "Markets"
        case config = "Config"
        
        var id: String { rawValue }
        var title: String { rawValue }
    }
    
    // MARK: - Published Properties
    @Published var selectedTab: BotTab = .chat
    @Published var selectedPlatform: PredictionPlatform = .polymarket
    @Published var selectedMarket: PredictionMarket? = nil
    @Published var selectedOutcome: String = "YES"
    @Published var betAmount: String = ""
    @Published var targetPrice: String = ""
    @Published var isRunning: Bool = false
    @Published var showBotCreatedAlert: Bool = false
    @Published var createdBotName: String = ""
    
    // Trading mode (paper vs live)
    @Published var tradingMode: PredictionTradingMode = .paper
    @Published var showLiveConfirmation: Bool = false
    
    // MARK: - Market Data
    @Published var availableMarkets: [PredictionMarket] = []
    @Published var isLoadingMarkets: Bool = false
    @Published var isShowingSampleData: Bool = false
    
    // MARK: - Live Trading State
    @Published var isWalletConnected: Bool = false
    @Published var walletAddress: String?
    @Published var usdcBalance: Double = 0
    
    // MARK: - Computed Properties
    
    var isReadyToStart: Bool {
        guard selectedMarket != nil,
              !betAmount.isEmpty,
              let amount = Double(betAmount),
              amount > 0 else { return false }
        
        // For live trading, check wallet connection and balance
        if tradingMode == .live {
            return isWalletConnected && usdcBalance >= amount
        }
        
        return true
    }
    
    var currentYesPrice: Double {
        selectedMarket?.yesPrice ?? 0.5
    }
    
    var currentNoPrice: Double {
        selectedMarket?.noPrice ?? 0.5
    }
    
    var potentialReturn: String {
        guard selectedMarket != nil else { return "—" }
        let price = selectedOutcome == "YES" ? currentYesPrice : currentNoPrice
        guard price > 0 && price < 1 else { return "—" }
        let multiplier = 1.0 / price
        return String(format: "%.1fx", multiplier)
    }
    
    var estimatedProfit: String {
        guard let amount = Double(betAmount), amount > 0 else { return "—" }
        let price = selectedOutcome == "YES" ? currentYesPrice : currentNoPrice
        guard price > 0 && price < 1 else { return "—" }
        let profit = (amount / price) - amount
        return String(format: "+$%.2f", profit)
    }
    
    // MARK: - Initialization
    
    init() {
        updateWalletState()
    }
    
    // MARK: - Methods
    
    func updateWalletState() {
        let tradingService = PredictionTradingService.shared
        isWalletConnected = tradingService.isWalletConnected
        walletAddress = tradingService.walletAddress
        usdcBalance = tradingService.usdcBalance
    }
    
    func loadMarkets() async {
        isLoadingMarkets = true
        isShowingSampleData = false
        
        await PredictionMarketService.shared.fetchTrendingMarkets()
        
        // Filter by selected platform
        availableMarkets = PredictionMarketService.shared.trendingMarkets.filter {
            $0.platform == selectedPlatform
        }
        
        // Check if we're showing sample data (sample IDs start with "sample-")
        isShowingSampleData = availableMarkets.first?.id.hasPrefix("sample-") ?? false
        
        isLoadingMarkets = false
    }
    
    func createBot() {
        guard let market = selectedMarket else { return }
        guard let amount = Double(betAmount), amount > 0 else { return }
        
        let botName = "Pred: \(market.title.prefix(30))"
        let price = selectedOutcome == "YES" ? currentYesPrice : currentNoPrice
        
        switch tradingMode {
        case .paper:
            createPaperBot(market: market, botName: botName, amount: amount, price: price)
        case .live:
            createLiveBot(market: market, botName: botName, amount: amount, price: price)
        }
    }
    
    private func createPaperBot(market: PredictionMarket, botName: String, amount: Double, price: Double) {
        let bot = PaperBotManager.shared.createPredictionBot(
            name: botName,
            platform: selectedPlatform.displayName,
            marketId: market.id,
            marketTitle: market.title,
            outcome: selectedOutcome,
            targetPrice: String(format: "%.2f", price),
            betAmount: betAmount,
            category: market.category.rawValue
        )
        
        createdBotName = bot.name
        showBotCreatedAlert = true
        
        // Auto-start the bot
        PaperBotManager.shared.startBot(id: bot.id)
        isRunning = true
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    
    private func createLiveBot(market: PredictionMarket, botName: String, amount: Double, price: Double) {
        // Create live prediction bot
        let bot = PredictionTradingService.shared.createLiveBot(
            name: botName,
            platform: selectedPlatform.displayName,
            marketId: market.id,
            marketTitle: market.title,
            outcome: selectedOutcome,
            targetPrice: price,
            betAmount: amount
        )
        
        createdBotName = bot.name
        showBotCreatedAlert = true
        
        // Enable the live bot (starts monitoring and trading)
        Task {
            await PredictionTradingService.shared.enableBot(id: bot.id)
        }
        isRunning = true
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    
    func toggleBot() {
        isRunning.toggle()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    
    /// Request confirmation before creating live bot
    func requestLiveConfirmation() {
        showLiveConfirmation = true
    }
}

// MARK: - Prediction Bot View

struct PredictionBotView: View {
    @StateObject private var viewModel = PredictionBotViewModel()
    @StateObject private var aiChatVM = AiChatViewModel(
        systemPrompt: PredictionBotView.baseSystemPrompt,
        storageKey: "csai_prediction_bot_chat",
        initialGreeting: "Hello! I'm your prediction market assistant. I can help you find opportunities on Polymarket and Kalshi. Tell me what kind of events you're interested in (crypto, politics, economics), and I'll help you identify markets with potential edges.\n\nI have access to live market data, so feel free to ask about current prices and trending markets!"
    )
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var marketService = PredictionMarketService.shared
    
    // Sheet presentation state
    @State private var showWalletSheet = false
    
    // Base system prompt for prediction market bots
    private static let baseSystemPrompt = """
    You are a friendly prediction market assistant for CryptoSage. Help users identify opportunities on Polymarket and Kalshi.

    YOUR CAPABILITIES:
    - You have access to LIVE market data from Polymarket and Kalshi (provided below)
    - You can analyze markets across all categories: Crypto, Politics, Economics, Sports, Entertainment, Science
    - You can help users understand probability pricing and find potential edges
    - You can create bot configurations to track markets

    When generating a prediction market bot configuration:
    1. HIDE the technical config by wrapping it in special tags (the app will parse this automatically)
    2. Give a brief, friendly summary of why you think this market has potential

    CRITICAL FORMAT - MUST USE XML TAGS WITH VALID JSON:
    Put the config on a SINGLE LINE using <bot_config> tags (user won't see):
    <bot_config>{"botType":"predictionMarket","name":"BTC 100K Bet","platform":"Polymarket","marketTitle":"Will Bitcoin reach $100K in 2026?","outcome":"YES","betAmount":"50","targetPrice":"0.68"}</bot_config>

    NEVER use broken formats like bot_config{...}/bot_config or bot_config(...) - they crash the app.
    ALWAYS use <bot_config>{valid JSON here}</bot_config> with quoted keys.

    Then provide a SHORT friendly summary like:
    "I found a crypto market that might interest you - 'Will Bitcoin reach $100K in 2026?' is currently priced at 68% YES. Given current market momentum and institutional adoption, some analysts believe this is underpriced. Tap the green button to create a paper bot tracking this market!"

    Available platforms: Polymarket, Kalshi
    Categories: Crypto, Politics, Economics, Sports, Entertainment, Science
    Outcomes: YES, NO

    ANALYSIS FRAMEWORK:
    1. PROBABILITY ASSESSMENT - Is the price fair? What would each outcome require?
    2. KEY FACTORS - What events could move the market? Timeline and key dates?
    3. EDGE FINDING - Any obvious mispricings? What might the market be missing?
    4. RISK CONSIDERATIONS - What could go wrong? Asymmetric risk?

    IMPORTANT - Risk Warnings:
    - Always mention that prediction markets are speculative
    - Prices represent crowd probability estimates, not certainties
    - Encourage starting with paper trading to test strategies

    DO NOT:
    - Show raw JSON or technical field names to the user
    - Guarantee any outcome will happen
    - Recommend specific bet amounts (let user decide)
    - Ignore non-crypto topics - you can analyze politics, sports, economics too!

    Keep responses warm, brief, and educational.
    """
    
    /// Build system prompt with live market data
    private func buildSystemPromptWithMarketData() -> String {
        let marketData = marketService.getMarketSummaryForAI()
        
        if marketData == "No prediction market data available." {
            return Self.baseSystemPrompt
        }
        
        return """
        \(Self.baseSystemPrompt)
        
        ===== LIVE MARKET DATA =====
        
        \(marketData)
        
        Use this live data to help users find opportunities. Reference specific markets when relevant.
        """
    }
    
    /// Gold gradient for header buttons
    private var chipGoldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var hasAccess: Bool {
        subscriptionManager.hasAccess(to: .tradingBots)
    }
    
    var body: some View {
        Group {
            if hasAccess {
                unlockedContent
            } else {
                lockedContent
            }
        }
        .background(DS.Adaptive.background)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .onAppear {
            setupAIConfigCallback()
            Task {
                await viewModel.loadMarkets()
                viewModel.updateWalletState()
                // Update AI system prompt with live market data
                aiChatVM.updateSystemPrompt(buildSystemPromptWithMarketData())
            }
            // Apply pending bot config from AI Chat if available
            applyPendingBotConfig()
        }
        .alert("Prediction Bot Created", isPresented: $viewModel.showBotCreatedAlert) {
            Button("View My Bots") {
                dismiss()
            }
            Button("OK", role: .cancel) {}
        } message: {
            if viewModel.tradingMode == .live {
                Text("\"\(viewModel.createdBotName)\" has been created and is now LIVE. Trading with real USDC on \(viewModel.selectedPlatform.displayName)!")
            } else {
                Text("\"\(viewModel.createdBotName)\" has been created and started in Paper Trading mode. Track this prediction market with simulated funds!")
            }
        }
        .alert("Confirm Live Trading", isPresented: $viewModel.showLiveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Start Live Bot", role: .destructive) {
                viewModel.createBot()
            }
        } message: {
            Text("You are about to create a LIVE prediction bot. This will use real USDC ($\(viewModel.betAmount)) from your connected wallet. This action cannot be undone. Are you sure?")
        }
        .sheet(isPresented: $showWalletSheet) {
            // Refresh wallet state after sheet dismisses
            viewModel.updateWalletState()
        } content: {
            WalletConnectView()
        }
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
    
    // MARK: - Unlocked Content
    
    private var unlockedContent: some View {
        VStack(spacing: 0) {
            customNavBar
            Divider().background(DS.Adaptive.divider)
            
            Group {
                switch viewModel.selectedTab {
                case .chat:
                    AiChatTabView(viewModel: aiChatVM)
                case .markets:
                    marketsSelectionView
                case .config:
                    configurationView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom action for non-chat tabs
            if viewModel.selectedTab != .chat {
                createBotButton
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedTab)
    }
    
    /// Set up the callback to apply AI-generated prediction bot configurations
    private func setupAIConfigCallback() {
        aiChatVM.onApplyConfig = { [self] config in
            applyPredictionConfig(config)
        }
    }
    
    /// Apply pending bot config from AppState (when navigating from AI helper)
    private func applyPendingBotConfig() {
        guard let config = appState.pendingBotConfig,
              config.botType == .predictionMarket else { return }
        
        // Clear the pending config
        appState.pendingBotConfig = nil
        
        // Apply the config
        applyPredictionConfig(config)
    }
    
    /// Apply the AI-generated configuration to the prediction bot form
    private func applyPredictionConfig(_ config: AIBotConfig) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        
        withAnimation(.easeInOut(duration: 0.3)) {
            viewModel.selectedTab = .config
        }
        
        // Apply platform
        if let platformName = config.platform {
            if platformName.lowercased().contains("polymarket") {
                viewModel.selectedPlatform = .polymarket
            } else if platformName.lowercased().contains("kalshi") {
                viewModel.selectedPlatform = .kalshi
            }
        }
        
        // Apply outcome
        if let outcome = config.outcome {
            viewModel.selectedOutcome = outcome.uppercased() == "YES" ? "YES" : "NO"
        }
        
        // Apply bet amount
        if let amount = config.betAmount {
            viewModel.betAmount = amount
        }
        
        // Apply target price
        if let price = config.targetPrice {
            viewModel.targetPrice = price
        }
        
        // Try to find matching market by title
        if let marketTitle = config.marketTitle {
            let matchingMarket = marketService.trendingMarkets.first {
                $0.title.lowercased().contains(marketTitle.lowercased().prefix(20))
            }
            if let market = matchingMarket {
                viewModel.selectedMarket = market
            }
        }
    }
    
    // MARK: - Custom Nav Bar
    
    private var customNavBar: some View {
        VStack(spacing: 0) {
            HStack {
                CSNavButton(
                    icon: "chevron.left",
                    action: { dismiss() }
                )
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis.ascending")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(chipGoldGradient)
                    Text("Prediction Bot")
                        .font(.headline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Trading mode badge
                tradingModeBadge
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            Picker("", selection: $viewModel.selectedTab) {
                ForEach(PredictionBotViewModel.BotTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DS.Adaptive.background)
            .overlay(
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1), alignment: .bottom
            )
        }
        .background(DS.Adaptive.background)
    }
    
    private var tradingModeBadge: some View {
        let isDeveloperMode = SubscriptionManager.shared.isDeveloperMode
        
        return Group {
            if isDeveloperMode {
                ModeBadge(mode: .liveTrading, variant: .compact)
            } else if viewModel.tradingMode == .paper {
                ModeBadge(mode: .paper, variant: .compact)
            } else {
                EmptyView()
            }
        }
    }
    
    // MARK: - Markets Selection View
    
    private var marketsSelectionView: some View {
        VStack(spacing: 0) {
            // Platform selector with refresh button
            HStack(spacing: 12) {
                ForEach(PredictionPlatform.allCases, id: \.self) { platform in
                    Button {
                        viewModel.selectedPlatform = platform
                        Task {
                            await viewModel.loadMarkets()
                            aiChatVM.updateSystemPrompt(buildSystemPromptWithMarketData())
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: platform.icon)
                                .font(.system(size: 12))
                            Text(platform.displayName)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(viewModel.selectedPlatform == platform ? .black : DS.Adaptive.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(viewModel.selectedPlatform == platform ?
                                      AnyShapeStyle(AdaptiveGradients.goldButton(isDark: colorScheme == .dark)) :
                                      AnyShapeStyle(DS.Adaptive.chipBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Refresh button
                Button {
                    Task {
                        await viewModel.loadMarkets()
                        aiChatVM.updateSystemPrompt(buildSystemPromptWithMarketData())
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(chipGoldGradient)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(DS.Adaptive.chipBackground)
                        )
                }
                .disabled(viewModel.isLoadingMarkets)
                .opacity(viewModel.isLoadingMarkets ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Data source indicator
            if viewModel.isShowingSampleData {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                    Text("Showing sample markets. Pull down to refresh for live data.")
                        .font(.system(size: 11))
                    Spacer()
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }
            
            Divider()
            
            // Markets list
            if viewModel.isLoadingMarkets && viewModel.availableMarkets.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("Loading \(viewModel.selectedPlatform.displayName) markets...")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                }
            } else if viewModel.availableMarkets.isEmpty {
                marketsEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        // Markets count
                        HStack {
                            Text("\(viewModel.availableMarkets.count) markets")
                                .font(.system(size: 12))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Spacer()
                            if viewModel.selectedMarket != nil {
                                Text("1 selected")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.horizontal, 4)
                        
                        ForEach(viewModel.availableMarkets, id: \.id) { market in
                            MarketSelectionRow(
                                market: market,
                                isSelected: viewModel.selectedMarket?.id == market.id
                            ) {
                                viewModel.selectedMarket = market
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 100)
                }
                .scrollViewBackSwipeFix()
                .refreshable {
                    await viewModel.loadMarkets()
                    aiChatVM.updateSystemPrompt(buildSystemPromptWithMarketData())
                }
            }
        }
    }
    
    private var marketsEmptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(DS.Adaptive.chipBackground)
                    .frame(width: 80, height: 80)
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 32))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            VStack(spacing: 8) {
                Text("No Markets Available")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Text("We couldn't load markets from \(viewModel.selectedPlatform.displayName). This could be a temporary issue.")
                    .font(.system(size: 13))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            VStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.loadMarkets()
                        aiChatVM.updateSystemPrompt(buildSystemPromptWithMarketData())
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                        Text("Refresh Markets")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(BrandColors.goldBase)
                    )
                }
                
                // Option to try different platform
                let otherPlatform: PredictionPlatform = viewModel.selectedPlatform == .polymarket ? .kalshi : .polymarket
                Button {
                    viewModel.selectedPlatform = otherPlatform
                    Task {
                        await viewModel.loadMarkets()
                        aiChatVM.updateSystemPrompt(buildSystemPromptWithMarketData())
                    }
                } label: {
                    Text("Try \(otherPlatform.displayName)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Configuration View
    
    private var configurationView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Trading Mode Selector
                tradingModeCard
                
                // Wallet Status (for live trading)
                if viewModel.tradingMode == .live {
                    walletStatusCard
                }
                
                // Selected Market Card
                if let market = viewModel.selectedMarket {
                    selectedMarketCard(market)
                } else {
                    noMarketSelectedCard
                }
                
                // Outcome Selection
                outcomeSelectionCard
                
                // Bet Configuration
                betConfigCard
                
                // Summary
                if viewModel.selectedMarket != nil {
                    summaryCard
                }
                
                // Disclaimer
                disclaimerCard
                
                Spacer(minLength: 120)
            }
            .padding(.vertical, 16)
        }
        .scrollViewBackSwipeFix()
    }
    
    // MARK: - Trading Mode Card
    
    private var tradingModeCard: some View {
        let isDeveloperMode = SubscriptionManager.shared.isDeveloperMode
        
        return formCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("TRADING MODE")
                
                HStack(spacing: 12) {
                    ForEach(PredictionTradingMode.allCases, id: \.self) { mode in
                        let isLiveDisabled = mode == .live && !isDeveloperMode
                        
                        Button {
                            guard !isLiveDisabled else { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.tradingMode = mode
                            }
                            if mode == .live {
                                viewModel.updateWalletState()
                            }
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 20))
                                Text(mode.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(isLiveDisabled ? "Dev Mode Only" : mode.description)
                                    .font(.system(size: 10))
                                    .opacity(0.8)
                            }
                            .foregroundColor(viewModel.tradingMode == mode ? .white : (isLiveDisabled ? DS.Adaptive.textTertiary : DS.Adaptive.textSecondary))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(viewModel.tradingMode == mode ? mode.color : DS.Adaptive.chipBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(viewModel.tradingMode == mode ? Color.clear : DS.Adaptive.stroke, lineWidth: 1)
                            )
                            .opacity(isLiveDisabled ? 0.5 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLiveDisabled)
                    }
                }
                
                // Mode-specific messages
                if viewModel.tradingMode == .live {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("Live trading uses real USDC. Make sure you understand the risks.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 4)
                } else if viewModel.tradingMode == .paper {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("Paper trading uses virtual funds. Perfect for testing strategies risk-free!")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 4)
                }
                
                // Live trading availability notice
                if !isDeveloperMode {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                        Text("Live trading is only available in Developer Mode")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .padding(.top, 4)
                }
            }
        }
    }
    
    // MARK: - Wallet Status Card (only shown for Live trading)
    
    @ViewBuilder
    private var walletStatusCard: some View {
        // Only show wallet card in Live trading mode
        if viewModel.tradingMode == .live {
            formCard {
                VStack(alignment: .leading, spacing: 12) {
                    cardHeader("WALLET STATUS")
                    
                    if viewModel.isWalletConnected {
                        // Connected wallet info
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.green)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connected")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.green)
                                if let address = viewModel.walletAddress {
                                    Text("\(address.prefix(6))...\(address.suffix(4))")
                                        .font(.caption)
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("USDC Balance")
                                    .font(.caption)
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                Text(String(format: "$%.2f", viewModel.usdcBalance))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                            }
                        }
                        
                        // Balance warning if insufficient
                        if let amount = Double(viewModel.betAmount), amount > viewModel.usdcBalance {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 12))
                                Text("Insufficient balance. You need $\(viewModel.betAmount) but have $\(String(format: "%.2f", viewModel.usdcBalance))")
                                    .font(.caption)
                            }
                            .foregroundColor(.red)
                            .padding(.top, 4)
                        }
                    } else {
                        // Not connected - show connect prompt
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "wallet.pass")
                                        .font(.system(size: 18))
                                        .foregroundColor(.orange)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Wallet Not Connected")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.orange)
                                    Text("Required for live trading on Polymarket")
                                        .font(.caption)
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                }
                                
                                Spacer()
                            }
                            
                            Button {
                                showWalletSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "link")
                                        .font(.system(size: 12))
                                    Text("Connect Wallet")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(BrandColors.goldBase)
                                .cornerRadius(10)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func selectedMarketCard(_ market: PredictionMarket) -> some View {
        formCard {
            VStack(alignment: .leading, spacing: 12) {
                // Step indicator showing progress
                HStack(spacing: 0) {
                    stepIndicator(number: 1, title: "Select", isActive: false, isCompleted: true)
                    stepConnector(isActive: true)
                    stepIndicator(number: 2, title: "Position", isActive: true, isCompleted: false)
                    stepConnector(isActive: false)
                    stepIndicator(number: 3, title: "Amount", isActive: false, isCompleted: !viewModel.betAmount.isEmpty)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                
                Divider()
                
                cardHeader("SELECTED MARKET")
                
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(market.platform == .polymarket ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: market.platform.icon)
                            .font(.system(size: 16))
                            .foregroundColor(market.platform == .polymarket ? .purple : .blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(market.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .lineLimit(2)
                        
                        HStack(spacing: 8) {
                            Text(market.platform.displayName)
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textTertiary)
                            if let time = market.timeRemaining {
                                Text("•")
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                Text(time)
                                    .font(.caption)
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Current prices with better layout
                HStack(spacing: 16) {
                    // YES price
                    VStack(alignment: .center, spacing: 4) {
                        Text("YES")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green.opacity(0.8))
                        Text(String(format: "%.0f%%", viewModel.currentYesPrice * 100))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                        Text(String(format: "%.1fx", viewModel.currentYesPrice > 0 ? 1.0 / viewModel.currentYesPrice : 0))
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green.opacity(0.08))
                    )
                    
                    // NO price
                    VStack(alignment: .center, spacing: 4) {
                        Text("NO")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                        Text(String(format: "%.0f%%", viewModel.currentNoPrice * 100))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.red)
                        Text(String(format: "%.1fx", viewModel.currentNoPrice > 0 ? 1.0 / viewModel.currentNoPrice : 0))
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.08))
                    )
                    
                    // Volume
                    VStack(alignment: .center, spacing: 4) {
                        Text("Volume")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(market.formattedVolume)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DS.Adaptive.chipBackground)
                    )
                }
                
                Button {
                    viewModel.selectedTab = .markets
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                        Text("Change Market")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(BrandColors.goldBase)
                }
            }
        }
    }
    
    private var noMarketSelectedCard: some View {
        formCard {
            VStack(spacing: 20) {
                // Step indicator
                HStack(spacing: 0) {
                    stepIndicator(number: 1, title: "Select", isActive: true, isCompleted: false)
                    stepConnector(isActive: false)
                    stepIndicator(number: 2, title: "Position", isActive: false, isCompleted: false)
                    stepConnector(isActive: false)
                    stepIndicator(number: 3, title: "Amount", isActive: false, isCompleted: false)
                }
                .padding(.horizontal, 8)
                
                Divider()
                
                // Empty state content
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(BrandColors.goldBase.opacity(0.1))
                            .frame(width: 60, height: 60)
                        Image(systemName: "chart.bar.xaxis.ascending.badge.clock")
                            .font(.system(size: 26))
                            .foregroundColor(BrandColors.goldBase)
                    }
                    
                    VStack(spacing: 6) {
                        Text("Select a Market")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Choose a prediction market to create your bot. Browse available markets or ask AI for recommendations.")
                            .font(.system(size: 13))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                }
                
                // Action buttons
                VStack(spacing: 10) {
                    Button {
                        viewModel.selectedTab = .markets
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12))
                            Text("Browse Markets")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(BrandColors.goldBase)
                        )
                    }
                    
                    Button {
                        viewModel.selectedTab = .chat
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                            Text("Ask AI for Suggestions")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func stepIndicator(number: Int, title: String, isActive: Bool, isCompleted: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green : (isActive ? BrandColors.goldBase : DS.Adaptive.chipBackground))
                    .frame(width: 28, height: 28)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isActive ? .black : DS.Adaptive.textTertiary)
                }
            }
            
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isActive || isCompleted ? DS.Adaptive.textPrimary : DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func stepConnector(isActive: Bool) -> some View {
        Rectangle()
            .fill(isActive ? BrandColors.goldBase : DS.Adaptive.stroke)
            .frame(height: 2)
            .frame(maxWidth: 40)
            .offset(y: -8)
    }
    
    private var outcomeSelectionCard: some View {
        formCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("YOUR POSITION")
                
                HStack(spacing: 12) {
                    OutcomeButton(
                        outcome: "YES",
                        isSelected: viewModel.selectedOutcome == "YES",
                        price: viewModel.currentYesPrice
                    ) {
                        viewModel.selectedOutcome = "YES"
                    }
                    
                    OutcomeButton(
                        outcome: "NO",
                        isSelected: viewModel.selectedOutcome == "NO",
                        price: viewModel.currentNoPrice
                    ) {
                        viewModel.selectedOutcome = "NO"
                    }
                }
            }
        }
    }
    
    private var betConfigCard: some View {
        formCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("BET CONFIGURATION")
                
                // Bet amount
                VStack(alignment: .leading, spacing: 6) {
                    Text("Amount (USD)")
                        .font(.system(size: 14))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    HStack {
                        Text("$")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        TextField("0.00", text: $viewModel.betAmount)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 16))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(DS.Adaptive.chipBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                    )
                }
                
                // Quick amount buttons
                HStack(spacing: 8) {
                    ForEach(["10", "25", "50", "100"], id: \.self) { amount in
                        Button {
                            viewModel.betAmount = amount
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        } label: {
                            Text("$\(amount)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(viewModel.betAmount == amount ? .black : DS.Adaptive.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(viewModel.betAmount == amount ?
                                              AnyShapeStyle(BrandColors.goldBase) :
                                              AnyShapeStyle(DS.Adaptive.chipBackground))
                                )
                        }
                    }
                }
            }
        }
    }
    
    private var summaryCard: some View {
        formCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("SUMMARY")
                
                HStack {
                    Text("Your Bet")
                        .font(.system(size: 14))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    Text("\(viewModel.selectedOutcome) @ \(String(format: "%.0f%%", (viewModel.selectedOutcome == "YES" ? viewModel.currentYesPrice : viewModel.currentNoPrice) * 100))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(viewModel.selectedOutcome == "YES" ? .green : .red)
                }
                
                HStack {
                    Text("Potential Return")
                        .font(.system(size: 14))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    Text(viewModel.potentialReturn)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                HStack {
                    Text("If \(viewModel.selectedOutcome) Wins")
                        .font(.system(size: 14))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    Text(viewModel.estimatedProfit)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                }
            }
        }
    }
    
    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                Text("Important")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
            }
            
            Text("Prediction markets are speculative. Prices represent crowd probability estimates, not certainties. This paper trading bot simulates bets for learning purposes. No real money is used.")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.1))
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Create Bot Button
    
    private var createBotButton: some View {
        Button {
            if viewModel.tradingMode == .live {
                // Require confirmation for live trading
                viewModel.requestLiveConfirmation()
            } else {
                viewModel.createBot()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.tradingMode == .live ? "bolt.fill" : "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(viewModel.tradingMode == .live ? "Create Live Bot" : "Create Paper Bot")
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                viewModel.tradingMode == .live ?
                    AnyShapeStyle(LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing)) :
                    AnyShapeStyle(AdaptiveGradients.goldButton(isDark: colorScheme == .dark))
            )
            .foregroundColor(viewModel.tradingMode == .live ? .white : .black)
            .cornerRadius(14)
        }
        .disabled(!viewModel.isReadyToStart)
        .opacity(viewModel.isReadyToStart ? 1 : 0.5)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - Locked Content
    
    private var lockedContent: some View {
        StandardLockedContentView.predictionBots(onDismiss: { dismiss() })
    }
    
    // MARK: - Helpers
    
    @ViewBuilder
    private func formCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
            .padding(.horizontal, 16)
    }
    
    private func cardHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(BrandColors.goldBase)
            .tracking(0.5)
    }
}

// MARK: - Market Selection Row

struct MarketSelectionRow: View {
    let market: PredictionMarket
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? BrandColors.goldBase : DS.Adaptive.stroke, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    
                    if isSelected {
                        Circle()
                            .fill(BrandColors.goldBase)
                            .frame(width: 12, height: 12)
                    }
                }
                
                // Market info
                VStack(alignment: .leading, spacing: 4) {
                    Text(market.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        Text("YES: \(market.yesPrice.map { String(format: "%.0f%%", $0 * 100) } ?? "—")")
                            .font(.caption)
                            .foregroundColor(.green)
                        
                        Text(market.formattedVolume)
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        if let time = market.timeRemaining {
                            Text(time)
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? BrandColors.goldBase.opacity(0.1) : DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? BrandColors.goldBase : DS.Adaptive.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Outcome Button

struct OutcomeButton: View {
    let outcome: String
    let isSelected: Bool
    let price: Double
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isYes: Bool { outcome == "YES" }
    private var baseColor: Color { isYes ? .green : .red }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(outcome)
                    .font(.system(size: 16, weight: .bold))
                
                Text(String(format: "%.0f%%", price * 100))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                
                Text(String(format: "%.1fx", price > 0 ? 1.0 / price : 0))
                    .font(.caption)
                    .opacity(0.8)
            }
            .foregroundColor(isSelected ? .white : baseColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? baseColor : baseColor.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(baseColor, lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct PredictionBotView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PredictionBotView()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
