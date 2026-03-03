import SwiftUI

// Disambiguate OrderType - use the public one from TradingTypes.swift
typealias TradingOrderType = OrderType

// MARK: - AI Bot Configuration Model
/// Structured model for AI-generated bot configurations that can be parsed and applied to forms
struct AIBotConfig: Codable, Equatable {
    enum BotType: String, Codable, CaseIterable, Equatable {
        case dca = "dca"
        case grid = "grid"
        case signal = "signal"
        case derivatives = "derivatives"
        case predictionMarket = "predictionMarket"
        
        var displayName: String {
            switch self {
            case .dca: return "DCA Bot"
            case .grid: return "Grid Bot"
            case .signal: return "Signal Bot"
            case .derivatives: return "Derivatives Bot"
            case .predictionMarket: return "Prediction Bot"
            }
        }
    }
    
    let botType: BotType
    let name: String?
    let exchange: String?
    let direction: String?        // Long/Short for trading, YES/NO for prediction
    let tradingPair: String?
    
    // DCA-specific
    let baseOrderSize: String?
    let takeProfit: String?
    let stopLoss: String?
    let maxOrders: String?
    let priceDeviation: String?
    
    // Grid-specific
    let lowerPrice: String?
    let upperPrice: String?
    let gridLevels: String?
    
    // Signal-specific
    let maxInvestment: String?
    
    // Derivatives-specific
    let leverage: Int?
    let marginMode: String?       // "isolated" or "cross"
    let market: String?           // e.g., "BTC-PERP", "ETH-PERP"
    
    // Prediction Market-specific
    let platform: String?         // "Polymarket" or "Kalshi"
    let marketId: String?         // Prediction market ID
    let marketTitle: String?      // Title of the prediction market
    let outcome: String?          // "YES" or "NO"
    let targetPrice: String?      // Target price to enter (0.0 to 1.0)
    let betAmount: String?        // Amount to bet in USD
    let category: String?         // Market category (crypto, politics, etc.)
    
    // Make all fields optional in decoder for flexibility
    enum CodingKeys: String, CodingKey {
        case botType, name, exchange, direction, tradingPair
        case baseOrderSize, takeProfit, stopLoss, maxOrders, priceDeviation
        case lowerPrice, upperPrice, gridLevels
        case maxInvestment
        case leverage, marginMode, market
        case platform, marketId, marketTitle, outcome, targetPrice, betAmount, category
    }
}

// MARK: - TradingBotView
struct TradingBotView: View {
    let side: TradeSide
    let orderType: TradingOrderType
    let quantity: Double
    let slippage: Double
    
    // Optional initial mode - allows direct navigation to specific bot type
    private let initialMode: BotCreationMode?
    
    // MARK: - Environment
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    
    // MARK: - Subscription Check
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    init(
        side: TradeSide = .buy,
        orderType: TradingOrderType = .market,
        quantity: Double = 0,
        slippage: Double = 0.5,
        initialMode: BotCreationMode? = nil
    ) {
        self.side = side
        self.orderType = orderType
        self.quantity = quantity
        self.slippage = slippage
        self.initialMode = initialMode
    }
    
    // MARK: - Bot Creation Modes
    enum BotCreationMode: String, CaseIterable {
        case dcaBot = "DCA Bot"
        case gridBot = "Grid Bot"
        case signalBot = "Signal Bot"
    }
    
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss

    // MARK: - State Variables
    @State private var selectedMode: BotCreationMode = .dcaBot
    
    // MARK: - AI Helper Sheet State
    @State private var showAIHelper: Bool = false
    
    // LIGHT MODE FIX: Adaptive gold gradient - deeper amber in light mode
    private var chipGoldGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.45, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    // MARK: - DCA Bot State
    @State private var botName: String = ""
    @State private var selectedExchange: String = "Binance"
    @State private var selectedDirection: String = "Long"
    @State private var selectedBotType: String = "Single-pair"
    @State private var selectedProfitCurrency: String = "Quote"
    @State private var selectedTradingPairDCA: String = "BTC_USDT"
    
    @State private var baseOrderSize: String = ""
    @State private var selectedStartOrderType: String = "Market"
    @State private var selectedTradeCondition: String = "RSI"
    
    @State private var averagingOrderSize: String = ""
    @State private var priceDeviation: String = ""
    @State private var maxAveragingOrders: String = ""
    @State private var averagingOrderStepMultiplier: String = ""
    
    @State private var takeProfit: String = ""
    @State private var selectedTakeProfitType: String = "Single Target"
    @State private var trailingEnabled: Bool = false
    @State private var revertProfit: Bool = false
    @State private var stopLossEnabled: Bool = false
    @State private var stopLossValue: String = ""
    @State private var maxHoldPeriod: String = ""
    
    @State private var isAdvancedViewExpanded: Bool = false
    @State private var balanceInfo: String = "0.00 USDT"
    @State private var maxAmountForBotUsage: String = ""
    @State private var maxAveragingPriceDeviation: String = ""
    
    // MARK: - Grid Bot State
    @State private var gridBotName: String = ""
    @State private var gridSelectedExchange: String = "Binance"
    @State private var gridSelectedTradingPair: String = "BTC_USDT"
    @State private var gridLowerPrice: String = ""
    @State private var gridUpperPrice: String = ""
    @State private var gridLevels: String = ""
    @State private var gridOrderVolume: String = ""
    @State private var gridTakeProfit: String = ""
    @State private var gridStopLossEnabled: Bool = false
    @State private var gridStopLossValue: String = ""
    
    // MARK: - Signal Bot State
    @State private var signalBotName: String = ""
    @State private var signalSelectedExchange: String = "Binance"
    @State private var signalSelectedPairs: String = "BTC_USDT"
    @State private var signalMaxUsage: String = ""
    @State private var signalPriceDeviation: String = ""
    @State private var signalEntriesLimit: String = ""
    @State private var signalTakeProfit: String = ""
    @State private var signalStopLossEnabled: Bool = false
    @State private var signalStopLossValue: String = ""
    @State private var isRunning: Bool = false
    
    // MARK: - Risk Acknowledgment State
    @State private var showingBotRiskAcknowledgment: Bool = false
    @State private var pendingBotCreationAction: (() -> Void)? = nil
    @State private var statusMessage: String = "Idle"
    
    // MARK: - Bot Creation Feedback State
    @State private var showBotCreatedAlert: Bool = false
    @State private var createdBotName: String = ""
    @State private var showNeedExchangeAlert: Bool = false
    
    // MARK: - Option Arrays for Pickers
    @State private var exchangeOptions = ["Binance", "Binance US", "Coinbase", "Kraken", "KuCoin", "Bybit", "OKX", "Gate.io", "MEXC", "HTX", "Bitstamp", "Crypto.com", "Bitget", "Bitfinex", "Paper"]
    private let directionOptions = ["Long", "Short", "Neutral"]
    private let botTypeOptions = ["Single-pair", "Multi-pair"]
    private let profitCurrencyOptions = ["Quote", "Base"]
    @State private var tradingPairsOptions = ["BTC_USDT", "ETH_USDT", "SOL_USDT", "ADA_USDT", "XRP_USDT", "DOGE_USDT", "AVAX_USDT", "LINK_USDT", "DOT_USDT", "MATIC_USDT", "BNB_USDT", "OP_USDT", "ARB_USDT", "NEAR_USDT", "SUI_USDT", "APT_USDT"]
    
    private let startOrderTypes = ["Market", "Limit", "Stop", "Stop-Limit"]
    private let tradeConditions = ["RSI", "QFL", "MACD", "Custom Condition"]
    private let takeProfitTypes = ["Single Target", "Multiple Targets", "Trailing TP"]
    
    private var hasAccess: Bool {
        subscriptionManager.hasAccess(to: .tradingBots)
    }
    
    var body: some View {
        Group {
            if hasAccess {
                // Full access - show bot creation interface
                unlockedContent
            } else {
                // Locked - show upgrade prompt
                lockedContent
            }
        }
        // DEPRECATED FIX: Use ignoresSafeArea instead of edgesIgnoringSafeArea
        .background(Color(UIColor.systemBackground))
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        // MARK: - Bot Creation Success Alert
        .alert("Bot Created Successfully", isPresented: $showBotCreatedAlert) {
            Button("View My Bots") {
                // Navigate to bot list (handled by dismiss and navigation)
                dismiss()
            }
            Button("Create Another", role: .cancel) {
                // Reset form fields for the current bot type
                resetCurrentBotForm()
            }
        } message: {
            Text("\"\(createdBotName)\" has been created and started in Paper Trading mode. Your bot is now running with simulated trades.")
        }
        // MARK: - Paper Trading Required Alert
        .alert("Paper Trading Required", isPresented: $showNeedExchangeAlert) {
            Button("Enable Paper Trading") {
                // Enable paper trading mode
                PaperTradingManager.shared.enablePaperTrading()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Trading bots run in Paper Trading mode with simulated funds. Enable Paper Trading to create and test your bot strategies risk-free.")
        }
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
    
    /// Reset the form fields for the current bot type after creation
    private func resetCurrentBotForm() {
        switch selectedMode {
        case .dcaBot:
            botName = ""
            baseOrderSize = ""
            takeProfit = ""
            stopLossValue = ""
            stopLossEnabled = false
            maxAveragingOrders = ""
            priceDeviation = ""
        case .gridBot:
            gridBotName = ""
            gridLowerPrice = ""
            gridUpperPrice = ""
            gridLevels = ""
            gridOrderVolume = ""
            gridTakeProfit = ""
            gridStopLossEnabled = false
            gridStopLossValue = ""
        case .signalBot:
            signalBotName = ""
            signalMaxUsage = ""
            signalPriceDeviation = ""
            signalEntriesLimit = ""
            signalTakeProfit = ""
            signalStopLossEnabled = false
            signalStopLossValue = ""
        }
    }
    
    private var unlockedContent: some View {
        VStack(spacing: 0) {
            customNavBar
            Divider()
            Group {
                switch selectedMode {
                case .dcaBot:
                    dcaBotView
                case .gridBot:
                    gridBotView
                case .signalBot:
                    signalBotView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Set initial mode if specified (for direct navigation to specific bot type)
            if let mode = initialMode {
                selectedMode = mode
            }
            // Apply pending bot config from AI Chat if available
            applyPendingBotConfig()
        }
        .onChange(of: showAIHelper) { _, isShowing in
            // When AI Helper sheet closes, check for pending config to apply
            if !isShowing {
                applyPendingBotConfig()
            }
        }
        .sheet(isPresented: $showAIHelper) {
            ContextualAIHelperView(context: .bots)
        }
        .sheet(isPresented: $showingBotRiskAcknowledgment) {
            BotTradingRiskAcknowledgmentView(
                onAcknowledge: {
                    // Execute the pending bot creation
                    pendingBotCreationAction?()
                    pendingBotCreationAction = nil
                },
                onDecline: {
                    pendingBotCreationAction = nil
                }
            )
        }
    }
    
    /// Apply pending bot config from AppState (when navigating from AI helper)
    private func applyPendingBotConfig() {
        guard let config = appState.pendingBotConfig else { return }
        
        // Clear the pending config
        appState.pendingBotConfig = nil
        
        // Apply the config
        applyBotConfig(config)
    }
    
    /// Apply the AI-generated configuration to the appropriate bot form
    private func applyBotConfig(_ config: AIBotConfig) {
        // Provide haptic feedback
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        
        // Switch to the appropriate bot tab based on config type
        withAnimation(.easeInOut(duration: 0.3)) {
            switch config.botType {
            case .dca:
                selectedMode = .dcaBot
                applyDCAConfig(config)
            case .grid:
                selectedMode = .gridBot
                applyGridConfig(config)
            case .signal:
                selectedMode = .signalBot
                applySignalConfig(config)
            case .derivatives:
                // Derivatives configs are handled in DerivativesBotView, not here
                // If somehow received here, default to DCA with available fields
                selectedMode = .dcaBot
                applyDCAConfig(config)
            case .predictionMarket:
                // Prediction market configs are handled in PredictionBotView, not here
                // If somehow received here, default to signal bot with available fields
                selectedMode = .signalBot
                applySignalConfig(config)
            }
        }
    }
    
    /// Fuzzy-match an exchange name from config to our picker options.
    /// Returns the best match or adds the value to the list if reasonable.
    private func resolveExchange(_ raw: String) -> String? {
        // Exact match
        if exchangeOptions.contains(raw) { return raw }
        
        // Case-insensitive match
        if let match = exchangeOptions.first(where: { $0.caseInsensitiveCompare(raw) == .orderedSame }) {
            return match
        }
        
        // Common aliases
        let aliases: [String: String] = [
            "paper": "Paper",
            "paper trading": "Paper",
            "simulated": "Paper",
            "binance futures": "Binance",
            "coinbase pro": "Coinbase",
            "coinbase advanced": "Coinbase",
            "kucoin": "KuCoin",
            "gate": "Gate.io",
            "crypto.com": "Crypto.com",
        ]
        if let mapped = aliases[raw.lowercased()] {
            return mapped
        }
        
        // Partial match (e.g., "Binance" matches "Binance US")
        if let match = exchangeOptions.first(where: { $0.lowercased().contains(raw.lowercased()) || raw.lowercased().contains($0.lowercased()) }) {
            return match
        }
        
        // If nothing matched, add as a custom option so it shows in the picker
        exchangeOptions.append(raw)
        return raw
    }
    
    /// Fuzzy-match a trading pair from config to our picker options.
    /// Normalizes separators and adds the pair if not present.
    private func resolveTradingPair(_ raw: String) -> String {
        // Normalize: replace / and - with _
        let normalized = raw.uppercased()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        
        // Exact match after normalization
        if tradingPairsOptions.contains(normalized) { return normalized }
        
        // Case-insensitive match
        if let match = tradingPairsOptions.first(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return match
        }
        
        // If the pair has no quote currency, append _USDT
        let withQuote = normalized.contains("_") ? normalized : "\(normalized)_USDT"
        if tradingPairsOptions.contains(withQuote) { return withQuote }
        
        // Not in list - add it dynamically so the picker works
        if !tradingPairsOptions.contains(withQuote) {
            tradingPairsOptions.append(withQuote)
        }
        return withQuote
    }
    
    /// Fuzzy-match a direction string
    private func resolveDirection(_ raw: String) -> String? {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch lower {
        case "long", "buy": return "Long"
        case "short", "sell": return "Short"
        case "neutral", "both": return "Neutral"
        default: return directionOptions.first(where: { $0.caseInsensitiveCompare(raw) == .orderedSame })
        }
    }
    
    /// Apply config values to DCA bot form fields
    private func applyDCAConfig(_ config: AIBotConfig) {
        if let name = config.name, !name.isEmpty {
            botName = name
        }
        if let exchange = config.exchange {
            if let resolved = resolveExchange(exchange) {
                selectedExchange = resolved
            }
        }
        if let direction = config.direction {
            if let resolved = resolveDirection(direction) {
                selectedDirection = resolved
            }
        }
        if let pair = config.tradingPair {
            selectedTradingPairDCA = resolveTradingPair(pair)
        }
        if let baseOrder = config.baseOrderSize {
            baseOrderSize = baseOrder
        }
        if let tp = config.takeProfit {
            takeProfit = tp
        }
        if let sl = config.stopLoss {
            stopLossEnabled = true
            stopLossValue = sl
        }
        if let maxOrd = config.maxOrders {
            maxAveragingOrders = maxOrd
        }
        if let deviation = config.priceDeviation {
            priceDeviation = deviation
        }
    }
    
    /// Apply config values to Grid bot form fields
    private func applyGridConfig(_ config: AIBotConfig) {
        if let name = config.name, !name.isEmpty {
            gridBotName = name
        }
        if let exchange = config.exchange {
            if let resolved = resolveExchange(exchange) {
                gridSelectedExchange = resolved
            }
        }
        if let pair = config.tradingPair {
            gridSelectedTradingPair = resolveTradingPair(pair)
        }
        if let lower = config.lowerPrice {
            gridLowerPrice = lower
        }
        if let upper = config.upperPrice {
            gridUpperPrice = upper
        }
        if let levels = config.gridLevels {
            gridLevels = levels
        }
        if let tp = config.takeProfit {
            gridTakeProfit = tp
        }
        if let sl = config.stopLoss {
            gridStopLossEnabled = true
            gridStopLossValue = sl
        }
    }
    
    /// Apply config values to Signal bot form fields
    private func applySignalConfig(_ config: AIBotConfig) {
        if let name = config.name, !name.isEmpty {
            signalBotName = name
        }
        if let exchange = config.exchange {
            if let resolved = resolveExchange(exchange) {
                signalSelectedExchange = resolved
            }
        }
        if let pair = config.tradingPair {
            signalSelectedPairs = resolveTradingPair(pair)
        }
        if let maxInv = config.maxInvestment {
            signalMaxUsage = maxInv
        }
        if let tp = config.takeProfit {
            signalTakeProfit = tp
        }
        if let sl = config.stopLoss {
            signalStopLossEnabled = true
            signalStopLossValue = sl
        }
        if let deviation = config.priceDeviation {
            signalPriceDeviation = deviation
        }
    }
    
    private var lockedContent: some View {
        StandardLockedContentView.tradingBots(onDismiss: { dismiss() })
    }
    
    // Legacy helper kept for reference - now using StandardLockedContentView
    private func botFeatureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.purple)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
    }
}

// MARK: - Custom Navigation Bar (Without Manage Button)
extension TradingBotView {
    private var customNavBar: some View {
        VStack(spacing: 0) {
            // Top row: Custom back button, centered title, Ask AI button
            HStack {
                CSNavButton(
                    icon: "chevron.left",
                    action: { dismiss() }
                )
                Spacer()
                Text("Trading Bot")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                // Ask AI button - opens AI helper sheet
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    showAIHelper = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text("AI")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(chipGoldGradient)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(DS.Adaptive.overlay(0.06))
                    )
                    .overlay(
                        Capsule()
                            .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
                    )
                }
                .accessibilityLabel("Ask AI for help")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            // Segmented control for mode selection
            Picker("", selection: $selectedMode) {
                ForEach(TradingBotView.BotCreationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DS.Adaptive.background)
            .overlay(
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1),
                alignment: .bottom
            )
        }
        .background(DS.Adaptive.background)
    }
    
    // A helper function to dismiss the view.
    private func dismissView() {
        // If this view was presented modally, dismiss it.
        // Otherwise, if it was pushed on a NavigationView, you might use
        // the environment's presentationMode (or use a dedicated NavigationStack/PresentationLink).
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

// MARK: - AI Chat View & Models
struct AiChatTabView: View {
    @ObservedObject var viewModel: AiChatViewModel
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var didInitialScroll: Bool = false
    @State private var lastMessageCount: Int = 0
    @State private var showClearConfirmation: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat controls header
            chatControlsHeader
            
            // Main chat scroll view
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                            ModernChatBubble(message: message)
                                .id(message.id)
                                .zIndex(Double(index))
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }
                        
                        // Apply Config button - appears when bot config is generated
                        if let config = viewModel.generatedConfig {
                            ApplyConfigButton(config: config) {
                                viewModel.applyCurrentConfig()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(Double(viewModel.messages.count + 1))
                        }
                        
                        // Execute Trade button - appears when trade config is generated
                        if let tradeConfig = viewModel.generatedTradeConfig {
                            ExecuteTradeButton(config: tradeConfig) {
                                // Navigate to trade page with config
                                appState.navigateToTrade(with: tradeConfig)
                                viewModel.generatedTradeConfig = nil
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(Double(viewModel.messages.count + 2))
                        }
                        
                        // Typing indicator with smooth transition
                        if viewModel.isTyping {
                            TypingIndicator()
                                .padding(.leading, 16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .zIndex(Double(viewModel.messages.count + 3))
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.9)),
                                    removal: .opacity.combined(with: .scale(scale: 0.95))
                                ))
                        }
                        
                        // Bottom anchor
                        Color.clear.frame(height: 8)
                            .id("chat_bottom")
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .animation(.easeOut(duration: 0.2), value: viewModel.isTyping)
                    .animation(.easeOut(duration: 0.15), value: viewModel.messages.count)
                }
                // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
                .withUIKitScrollBridge()
                .defaultScrollAnchor(.bottom) // iOS 17+ - Start scroll position at bottom for chat UX
                .background(DS.Adaptive.background)
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    // Dismiss keyboard when tapping on the scroll area
                    UIApplication.shared.dismissKeyboard()
                }
                .onAppear {
                    scrollProxy = proxy
                    viewModel.fetchInitialMessageIfNeeded()
                    lastMessageCount = viewModel.messages.count
                    
                    // Only perform initial scroll if not already done
                    guard !didInitialScroll else { return }
                    
                    // Two-stage scroll for reliable initial positioning
                    // Stage 1: Immediate scroll
                    if let lastMessage = viewModel.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                    
                    // Stage 2: Short delay for content layout
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let lastMessage = viewModel.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                    
                    // Stage 3: Fallback for complex layouts
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let lastMessage = viewModel.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                        didInitialScroll = true
                    }
                }
                .onChange(of: viewModel.messages.count) { _, newCount in
                    // Only animate scroll for NEW messages (not on initial load)
                    guard didInitialScroll else { return }
                    guard newCount > lastMessageCount else {
                        lastMessageCount = newCount
                        return
                    }
                    lastMessageCount = newCount
                    
                    // Smooth scroll for new messages
                    withAnimation(.easeOut(duration: 0.25)) {
                        if let lastMessage = viewModel.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.generatedConfig != nil) { _, hasConfig in
                    // Only scroll when config appears (not disappears)
                    guard hasConfig, didInitialScroll else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("chat_bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.generatedTradeConfig != nil) { _, hasTradeConfig in
                    // Only scroll when trade config appears (not disappears)
                    guard hasTradeConfig, didInitialScroll else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("chat_bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.messages.isEmpty) { _, isEmpty in
                    // Reset scroll tracking when chat is cleared
                    if isEmpty {
                        didInitialScroll = false
                        lastMessageCount = 0
                    }
                }
                .onChange(of: viewModel.messages.last?.text.count ?? 0) { _, newCount in
                    // Auto-scroll during streaming - only when AI is typing
                    guard viewModel.isTyping, didInitialScroll else { return }
                    // Throttle: only scroll every ~50 characters to reduce jank
                    guard newCount % 50 < 5 else { return }
                    // Disable animations for smoother streaming scroll
                    var trans = SwiftUI.Transaction()
                    trans.disablesAnimations = true
                    withTransaction(trans) {
                        proxy.scrollTo("chat_bottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isTyping) { _, isTyping in
                    // Final scroll when streaming completes
                    if !isTyping && didInitialScroll {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("chat_bottom", anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Clear Chat History", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Clear All Messages", role: .destructive) {
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.clearHistory()
                    viewModel.fetchInitialMessageIfNeeded()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all messages in this chat. This action cannot be undone.")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                // Generate Bot Config button
                Button(action: {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    UIApplication.shared.dismissKeyboard()
                    viewModel.generateBotConfig()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Generate Bot Config")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(BrandColors.ctaTextColor(isDark: colorScheme == .dark))
                    .background(
                        AdaptiveGradients.goldButton(isDark: colorScheme == .dark)
                    )
                    .cornerRadius(14)
                }
                .disabled(viewModel.isTyping)
                .opacity(viewModel.isTyping ? 0.6 : 1)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Input bar
                ModernChatInputBar(text: $viewModel.userInput) { text in
                    viewModel.sendMessage(text)
                }
            }
            .background(DS.Adaptive.background)
            // Prevent bouncy keyboard animation - use smooth linear animation
            .animation(.linear(duration: 0.25), value: viewModel.userInput.isEmpty)
        }
        // Critical: Disable implicit animations on the safeAreaInset container to prevent overshoot
        .transaction { transaction in
            transaction.animation = .easeOut(duration: 0.25)
        }
    }
    
    // MARK: - Chat Controls Header
    private var chatControlsHeader: some View {
        HStack(spacing: 16) {
            // New Chat button
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.clearHistory()
                    viewModel.fetchInitialMessageIfNeeded()
                    didInitialScroll = false
                    lastMessageCount = 0
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("New Chat")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(chipGoldGradient)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(DS.Adaptive.overlay(0.06))
                )
                .overlay(
                    Capsule()
                        .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
                )
            }
            
            Spacer()
            
            // Message count indicator
            if viewModel.messages.count > 1 {
                Text("\(viewModel.messages.count) messages")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            // Clear Chat button (trash icon)
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showClearConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(chipGoldGradient)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(DS.Adaptive.overlay(0.06))
                    )
                    .overlay(
                        Circle()
                            .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
                    )
            }
            .opacity(viewModel.messages.count > 1 ? 1 : 0.3)
            .disabled(viewModel.messages.count <= 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            DS.Adaptive.background
                .overlay(
                    Rectangle()
                        .fill(DS.Adaptive.divider)
                        .frame(height: 1),
                    alignment: .bottom
                )
        )
    }
}

// MARK: - Apply Config Button
struct ApplyConfigButton: View {
    let config: AIBotConfig
    let onApply: () -> Void
    
    /// Compact trading pair display
    private var compactPair: String {
        if let pair = config.tradingPair {
            return pair.replacingOccurrences(of: "_", with: "/")
        }
        if let marketTitle = config.marketTitle {
            return String(marketTitle.prefix(20)) + (marketTitle.count > 20 ? "..." : "")
        }
        return ""
    }
    
    var body: some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            onApply()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apply to \(config.botType.displayName)")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if !compactPair.isEmpty {
                        Text(compactPair)
                            .font(.system(size: 11))
                            .opacity(0.8)
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)
                
                Spacer(minLength: 8)
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .foregroundColor(.black)
            .background(
                LinearGradient(
                    colors: [Color.green.opacity(0.9), Color.green],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

class AiChatViewModel: ObservableObject {
    @Published var messages: [AiChatMessage] = []
    @Published var userInput: String = ""
    @Published var isTyping: Bool = false
    @Published var generatedConfig: AIBotConfig?
    @Published var generatedTradeConfig: AITradeConfig?
    @Published var generatedStrategyConfig: AIStrategyConfig?
    @Published var errorMessage: String?
    
    // Callback for when user wants to apply a config
    var onApplyConfig: ((AIBotConfig) -> Void)?
    // Callback for when user wants to execute a trade
    var onApplyTradeConfig: ((AITradeConfig) -> Void)?
    
    // Custom system prompt (can be set for different bot types)
    private var customSystemPrompt: String?
    
    // Storage key for chat history persistence (unique per bot type)
    private let storageKey: String
    
    // Customizable initial greeting message
    private let initialGreeting: String
    
    // Default greeting for trading bots
    private static let defaultTradingBotGreeting = "I'm CryptoSage AI, your trading bot assistant. I'll help you configure DCA, Grid, or Signal bots using professional trading methodology.\n\nQuick tip: Before enabling any bot, check BTC's daily chart - if the 10 SMA is above the 20 SMA, market conditions favor long strategies.\n\nTell me your goals, or tap 'Generate Bot Config' for a recommendation."
    
    /// Initialize with optional custom system prompt, storage key, and initial greeting
    init(systemPrompt: String? = nil, 
         storageKey: String = "csai_trading_bot_chat",
         initialGreeting: String? = nil) {
        self.customSystemPrompt = systemPrompt
        self.storageKey = storageKey
        self.initialGreeting = initialGreeting ?? AiChatViewModel.defaultTradingBotGreeting
        loadMessages()
    }
    
    /// Update the system prompt dynamically (for mode switching in Smart Trading Hub)
    func updateSystemPrompt(_ newPrompt: String) {
        customSystemPrompt = newPrompt
    }
    
    /// Add a system message to indicate context change (optional, not from user)
    func addSystemMessage(_ text: String) {
        let systemMsg = AiChatMessage(
            text: text,
            isUser: false,
            timestamp: Date()
        )
        messages.append(systemMsg)
        saveMessages()
    }
    
    // Default bot-specific system prompt
    private var botSystemPrompt: String {
        customSystemPrompt ?? defaultSpotBotSystemPrompt
    }
    
    private let defaultSpotBotSystemPrompt = """
    You are CryptoSage AI, a professional crypto trading bot assistant. Help users set up DCA, Grid, or Signal bots using proven trading methodology.

    YOUR PERSONALITY:
    - Warm and helpful, like a knowledgeable trading mentor
    - Direct and practical - get to actionable advice quickly
    - Safety-conscious - always mention risk management
    
    PROFESSIONAL TRADING FRAMEWORK:
    
    1. POSITION SIZING (CRITICAL - teach users this)
       - Risk 1% of account per trade maximum
       - Formula: Risk/(Entry - Stop) = Position Size
       - Example: $10K account, 1% risk = $100 max loss per trade
       - Apply this to bot base order sizes
    
    2. MARKET CONDITIONS CHECK
       - Always mention checking BTC 10 SMA vs 20 SMA
       - 10 above 20 = bullish, good for long bots
       - 10 below 20 = cautious, reduce bot allocations
       - Grid bots best when market is ranging
    
    3. EXIT STRATEGY FOR BOTS
       - Take profit at 5x risk level (e.g., risk $100, TP at $500)
       - Use 10 SMA close as trailing stop reference
       - For Signal bots: partial profit at 5x, trail the rest
    
    When generating a bot configuration:
    1. HIDE the technical config in XML-style tags (user won't see them)
    2. Give a brief, friendly summary - NO technical JSON visible to user

    CRITICAL FORMAT - MUST USE XML TAGS WITH VALID JSON:
    Put the config on a SINGLE LINE using <bot_config> tags (user won't see):
    <bot_config>{"botType":"dca","name":"My BTC DCA Bot","exchange":"Binance","direction":"Long","tradingPair":"BTC_USDT","baseOrderSize":"50","takeProfit":"5","stopLoss":"10","maxOrders":"10","priceDeviation":"2"}</bot_config>

    NEVER use these broken formats (they crash the app):
    - bot_config{botType:dca,...}/bot_config
    - bot_config(key:value,...)/bot_config
    - Any format without < > angle brackets and "quoted" JSON keys

    Then provide a SHORT friendly summary like:
    "I've configured a DCA bot to accumulate BTC on Binance! It will take profit at 5% (about 5x our risk) and has a 10% stop loss for protection. Remember to check that BTC's 10 SMA is above the 20 SMA before starting!"

    Available bot types: dca, grid, signal
    Available exchanges: Binance, Coinbase, KuCoin, Bitfinex, Paper
    Available pairs: BTC_USDT, ETH_USDT, SOL_USDT, ADA_USDT
    Directions: Long, Short, Neutral

    For DCA: include baseOrderSize, takeProfit, stopLoss, maxOrders, priceDeviation
    For Grid: include lowerPrice, upperPrice, gridLevels, takeProfit, stopLoss
    For Signal: include maxInvestment, takeProfit, stopLoss

    DO NOT:
    - Show raw JSON to the user
    - Use any format other than <bot_config>{...}</bot_config>
    - Skip mentioning market conditions
    - Forget to teach position sizing concepts

    Keep responses warm, brief, and EDUCATIONAL - teach the WHY behind bot configuration!
    """
    
    private var currentTask: Task<Void, Never>?
    
    func fetchInitialMessageIfNeeded() {
        if messages.isEmpty {
            let initial = AiChatMessage(
                text: initialGreeting,
                isUser: false,
                timestamp: Date()
            )
            messages.append(initial)
            // Don't save the initial greeting - it will be regenerated if history is empty
        }
    }
    
    /// Timeout duration for AI requests (30 seconds)
    private let aiRequestTimeoutSeconds: UInt64 = 30
    
    /// Custom error type for AI request timeout
    private struct AIRequestTimeoutError: Error {
        let message = "Request timed out. Please try again."
    }
    
    func sendMessage(_ text: String) {
        // Rate limit check (abuse protection)
        if SubscriptionManager.shared.isRateLimited {
            errorMessage = "Slow down — try again in \(SubscriptionManager.shared.rateLimitSecondsRemaining)s"
            return
        }
        
        let userMsg = AiChatMessage(text: text, isUser: true, timestamp: Date())
        messages.append(userMsg)
        userInput = ""
        
        // Save immediately after user message is added (ensures history persists even if app closes)
        saveMessages()
        
        // Cancel any existing task
        currentTask?.cancel()
        currentTask = nil
        
        // Show typing indicator with animation
        withAnimation(.easeOut(duration: 0.2)) {
            isTyping = true
        }
        errorMessage = nil
        
        // Create a placeholder for the streaming response
        let placeholderId = UUID()
        let placeholder = AiChatMessage(
            id: placeholderId,
            text: "",
            isUser: false,
            timestamp: Date()
        )
        messages.append(placeholder)
        
        currentTask = Task { @MainActor in
            do {
                // Check for cancellation early
                try Task.checkCancellation()
                
                // Stream the response with timeout
                try await withThrowingTaskGroup(of: Void.self) { group in
                    // Task 1: The actual AI streaming request
                    group.addTask { @MainActor in
                        _ = try await AIService.shared.sendMessageStreaming(
                            text,
                            systemPrompt: self.botSystemPrompt,
                            usePremiumModel: false,
                            includeTools: false
                        ) { [weak self] streamedText in
                            guard let self = self else { return }
                            
                            // Hide typing indicator once text starts flowing
                            if self.isTyping && !streamedText.isEmpty {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    self.isTyping = false
                                }
                            }
                            
                            // Update the placeholder message with streamed content
                            if let index = self.messages.firstIndex(where: { $0.id == placeholderId }) {
                                self.messages[index] = AiChatMessage(
                                    id: placeholderId,
                                    text: streamedText,
                                    isUser: false,
                                    timestamp: Date()
                                )
                            }
                        }
                    }
                    
                    // Task 2: Timeout watchdog (30 seconds)
                    group.addTask {
                        try await Task.sleep(nanoseconds: self.aiRequestTimeoutSeconds * 1_000_000_000)
                        throw AIRequestTimeoutError()
                    }
                    
                    // Wait for the first task to complete
                    do {
                        try await group.next()
                        group.cancelAll()
                    } catch {
                        group.cancelAll()
                        throw error
                    }
                }
                
                withAnimation(.easeOut(duration: 0.15)) {
                    self.isTyping = false
                }
                self.currentTask = nil
                
                // Count bot chat message against daily AI limit
                SubscriptionManager.shared.recordAIPromptUsage(modelUsed: "gpt-4o-mini")
                
                // After streaming completes, check for JSON config in the final message
                if let lastMessage = self.messages.last, !lastMessage.isUser {
                    self.parseConfigFromResponse(lastMessage.text)
                }
                
                // Save messages after successful completion
                self.saveMessages()
                
            } catch is CancellationError {
                // Task was cancelled - silently clean up
                if let index = self.messages.firstIndex(where: { $0.id == placeholderId }),
                   self.messages[index].text.isEmpty {
                    self.messages.remove(at: index)
                }
                withAnimation(.easeOut(duration: 0.15)) {
                    self.isTyping = false
                }
                self.currentTask = nil
                
            } catch let error as AIRequestTimeoutError {
                // Timeout error
                withAnimation(.easeOut(duration: 0.15)) {
                    self.isTyping = false
                }
                self.currentTask = nil
                if let index = self.messages.firstIndex(where: { $0.id == placeholderId }) {
                    self.messages[index] = AiChatMessage(
                        id: placeholderId,
                        text: error.message,
                        isUser: false,
                        timestamp: Date()
                    )
                }
                self.errorMessage = error.message
                self.saveMessages()
                
            } catch {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.isTyping = false
                }
                self.currentTask = nil
                // Update placeholder with error message
                if let index = self.messages.firstIndex(where: { $0.id == placeholderId }) {
                    self.messages[index] = AiChatMessage(
                        id: placeholderId,
                        text: "Sorry, I encountered an error: \(error.localizedDescription). Please check your API key in Settings.",
                        isUser: false,
                        timestamp: Date()
                    )
                }
                self.errorMessage = error.localizedDescription
                
                // Save messages even after error (to preserve user message)
                self.saveMessages()
            }
        }
    }
    
    func generateBotConfig() {
        // Send a specific prompt to generate a bot configuration
        let configPrompt = "Based on current market conditions, generate a recommended bot configuration for me. I'm interested in a moderate-risk strategy for Bitcoin trading."
        sendMessage(configPrompt)
    }
    
    /// Parse AI response for embedded JSON configurations (bot or trade)
    private func parseConfigFromResponse(_ text: String) {
        // Try to parse trade config first (for spot/derivatives trades)
        if let tradeConfig = parseTradeConfigFromText(text) {
            self.generatedTradeConfig = tradeConfig
            return
        }
        
        // Try bot_config XML tag formats (preferred, case-insensitive)
        let botTagPatterns = [
            ("<bot_config>", "</bot_config>"),
            ("<botconfig>", "</botconfig>"),
            ("<bot-config>", "</bot-config>")
        ]
        for (startTag, endTag) in botTagPatterns {
            if let startRange = text.range(of: startTag, options: .caseInsensitive),
               let endRange = text.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<text.endIndex) {
                let jsonString = String(text[startRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let jsonData = jsonString.data(using: .utf8),
                   let config = try? JSONDecoder().decode(AIBotConfig.self, from: jsonData) {
                    self.generatedConfig = config
                    return
                }
            }
        }
        
        // Try plain-text bot_config formats: bot_config{key:value,...}/bot_config etc.
        let plainTextPatterns = [
            "bot_config\\{([^}]+)\\}/bot_config",
            "bot_config\\{([^}]+)\\}",
            "bot_config\\(([^)]+)\\)/bot_config",
            "bot_config\\(([^)]+)\\)"
        ]
        for pattern in plainTextPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let contentRange = Range(match.range(at: 1), in: text) {
                let rawContent = String(text[contentRange])
                if let config = parseUnquotedKeyValueBotConfig(rawContent) {
                    self.generatedConfig = config
                    return
                }
            }
        }
        
        // Try strategy_config tags (for strategies mode)
        if let strategyConfig = parseStrategyConfigFromText(text) {
            self.generatedStrategyConfig = strategyConfig
            return
        }
        
        // Fall back to markdown code block format (```json ... ```)
        if let jsonStart = text.range(of: "```json"),
           let jsonEnd = text.range(of: "```", range: jsonStart.upperBound..<text.endIndex) {
            let jsonString = String(text[jsonStart.upperBound..<jsonEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let jsonData = jsonString.data(using: .utf8),
               let config = try? JSONDecoder().decode(AIBotConfig.self, from: jsonData) {
                self.generatedConfig = config
                return
            }
        }
        
        // Last resort: try to find raw JSON object for bot config
        if let config = extractRawJSON(from: text) {
            self.generatedConfig = config
        }
    }
    
    /// Parse unquoted key:value pairs from plain-text bot_config format
    private func parseUnquotedKeyValueBotConfig(_ raw: String) -> AIBotConfig? {
        var dict: [String: String] = [:]
        let parts = raw.components(separatedBy: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIdx])
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(trimmed[trimmed.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && !value.isEmpty { dict[key] = value }
        }
        guard !dict.isEmpty else { return nil }
        
        let botTypeStr = (dict["bottype"] ?? dict["bot_type"] ?? dict["type"] ?? "dca").lowercased()
        let botType: AIBotConfig.BotType
        switch botTypeStr {
        case "grid": botType = .grid
        case "signal": botType = .signal
        case "derivatives", "futures", "perp": botType = .derivatives
        case "predictionmarket", "prediction", "prediction_market": botType = .predictionMarket
        default: botType = .dca
        }
        
        var leverage: Int? = nil
        if let levStr = dict["leverage"] {
            leverage = Int(levStr.replacingOccurrences(of: "x", with: "", options: .caseInsensitive))
        }
        
        return AIBotConfig(
            botType: botType, name: dict["name"], exchange: dict["exchange"],
            direction: dict["direction"],
            tradingPair: dict["tradingpair"] ?? dict["trading_pair"] ?? dict["pair"],
            baseOrderSize: dict["baseordersize"] ?? dict["base_order_size"],
            takeProfit: dict["takeprofit"] ?? dict["take_profit"] ?? dict["tp"],
            stopLoss: dict["stoploss"] ?? dict["stop_loss"] ?? dict["sl"],
            maxOrders: dict["maxorders"] ?? dict["max_orders"],
            priceDeviation: dict["pricedeviation"] ?? dict["price_deviation"],
            lowerPrice: dict["lowerprice"] ?? dict["lower_price"],
            upperPrice: dict["upperprice"] ?? dict["upper_price"],
            gridLevels: dict["gridlevels"] ?? dict["grid_levels"] ?? dict["levels"],
            maxInvestment: dict["maxinvestment"] ?? dict["max_investment"],
            leverage: leverage,
            marginMode: dict["marginmode"] ?? dict["margin_mode"],
            market: dict["market"], platform: dict["platform"],
            marketId: dict["marketid"] ?? dict["market_id"],
            marketTitle: dict["markettitle"] ?? dict["market_title"],
            outcome: dict["outcome"],
            targetPrice: dict["targetprice"] ?? dict["target_price"],
            betAmount: dict["betamount"] ?? dict["bet_amount"],
            category: dict["category"]
        )
    }
    
    /// Parse strategy config from <strategy_config> tags
    private func parseStrategyConfigFromText(_ text: String) -> AIStrategyConfig? {
        let tagPatterns = [
            ("<strategy_config>", "</strategy_config>"),
            ("<strategyconfig>", "</strategyconfig>"),
            ("<strategy-config>", "</strategy-config>")
        ]
        for (startTag, endTag) in tagPatterns {
            if let startRange = text.range(of: startTag, options: .caseInsensitive),
               let endRange = text.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<text.endIndex) {
                let jsonString = String(text[startRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let jsonData = jsonString.data(using: .utf8),
                   let config = try? JSONDecoder().decode(AIStrategyConfig.self, from: jsonData) {
                    return config
                }
            }
        }
        return nil
    }
    
    /// Parse trade config from <trade_config> tags
    private func parseTradeConfigFromText(_ text: String) -> AITradeConfig? {
        let tagPatterns = [
            ("<trade_config>", "</trade_config>"),
            ("<tradeconfig>", "</tradeconfig>"),
            ("<trade-config>", "</trade-config>")
        ]
        
        for (startTag, endTag) in tagPatterns {
            if let startRange = text.range(of: startTag, options: .caseInsensitive),
               let endRange = text.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<text.endIndex) {
                let jsonString = String(text[startRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let jsonData = jsonString.data(using: .utf8),
                   let config = try? JSONDecoder().decode(AITradeConfig.self, from: jsonData) {
                    return config
                }
            }
        }
        
        return nil
    }
    
    /// Try to extract raw JSON object from text (without code fence)
    private func extractRawJSON(from text: String) -> AIBotConfig? {
        // Find JSON-like structure
        // SAFETY: Check that start comes before end to prevent String index out of bounds crash
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else { return nil }
        
        let jsonString = String(text[start...end])
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        
        return try? JSONDecoder().decode(AIBotConfig.self, from: jsonData)
    }
    
    func applyCurrentConfig() {
        guard let config = generatedConfig else { return }
        onApplyConfig?(config)
        generatedConfig = nil // Clear after applying
    }
    
    func applyCurrentTradeConfig() {
        guard let config = generatedTradeConfig else { return }
        onApplyTradeConfig?(config)
        generatedTradeConfig = nil // Clear after applying
    }
    
    func clearConfig() {
        generatedConfig = nil
        generatedTradeConfig = nil
        generatedStrategyConfig = nil
    }
    
    // MARK: - Chat History Persistence
    
    /// Save messages to UserDefaults for persistence across sessions
    private func saveMessages() {
        // Only save non-empty messages (skip initial greeting if it's the only message)
        let messagesToSave = messages.filter { !$0.text.isEmpty }
        guard !messagesToSave.isEmpty else { return }
        
        // Limit to last 100 messages to prevent storage bloat
        let limitedMessages = Array(messagesToSave.suffix(100))
        
        do {
            let data = try JSONEncoder().encode(limitedMessages)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            #if DEBUG
            print("[AiChatViewModel] Failed to save messages: \(error)")
            #endif
        }
    }
    
    /// Load messages from UserDefaults
    private func loadMessages() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        
        do {
            let loadedMessages = try JSONDecoder().decode([AiChatMessage].self, from: data)
            if !loadedMessages.isEmpty {
                messages = loadedMessages
            }
        } catch {
            #if DEBUG
            print("[AiChatViewModel] Failed to load messages: \(error)")
            #endif
        }
    }
    
    /// Clear chat history
    func clearHistory() {
        // Cancel any ongoing AI request
        currentTask?.cancel()
        currentTask = nil
        
        // Clear all state with animation
        withAnimation(.easeOut(duration: 0.2)) {
            isTyping = false
        }
        messages.removeAll()
        userInput = ""
        generatedConfig = nil
        generatedTradeConfig = nil
        errorMessage = nil
        
        // Remove from persistent storage
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

struct AiChatMessage: Identifiable, Codable {
    let id: UUID
    let text: String
    let isUser: Bool
    let timestamp: Date
    
    init(id: UUID = UUID(), text: String, isUser: Bool, timestamp: Date) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

// MARK: - Modern Chat Bubble (Aligned with Main AI Chat Design)
struct ModernChatBubble: View {
    let message: AiChatMessage
    @Environment(\.colorScheme) private var colorScheme
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
    
    /// Clean message text by removing hidden config blocks, JSON, and technical explanations
    private static func cleanMessageForDisplay(_ text: String) -> String {
        var cleaned = text
        
        // Remove all config XML tag formats (case insensitive)
        let allTagPatterns = [
            ("<bot_config>", "</bot_config>"),
            ("<botconfig>", "</botconfig>"),
            ("<bot-config>", "</bot-config>"),
            ("<trade_config>", "</trade_config>"),
            ("<tradeconfig>", "</tradeconfig>"),
            ("<trade-config>", "</trade-config>"),
            ("<strategy_config>", "</strategy_config>"),
            ("<strategyconfig>", "</strategyconfig>"),
            ("<strategy-config>", "</strategy-config>")
        ]
        for (startTag, endTag) in allTagPatterns {
            while let startRange = cleaned.range(of: startTag, options: .caseInsensitive),
                  let endRange = cleaned.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<cleaned.endIndex) {
                cleaned.removeSubrange(startRange.lowerBound...endRange.upperBound)
            }
        }
        
        // Remove plain-text config formats (non-XML)
        let plainConfigPatterns = [
            "bot_config\\{[^}]*\\}/bot_config",
            "bot_config\\{[^}]*\\}",
            "bot_config\\([^)]*\\)/bot_config",
            "bot_config\\([^)]*\\)",
            "trade_config\\{[^}]*\\}/trade_config",
            "trade_config\\{[^}]*\\}",
            "strategy_config\\{[^}]*\\}/strategy_config",
            "strategy_config\\{[^}]*\\}"
        ]
        for pattern in plainConfigPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        
        // Remove ```json...``` code blocks (legacy format)
        while let startRange = cleaned.range(of: "```json"),
              let endRange = cleaned.range(of: "```", range: startRange.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(startRange.lowerBound...endRange.upperBound)
        }
        
        // Remove any remaining ``` code blocks that might contain config
        while let startRange = cleaned.range(of: "```"),
              let endRange = cleaned.range(of: "```", range: startRange.upperBound..<cleaned.endIndex) {
            let blockContent = String(cleaned[startRange.upperBound..<endRange.lowerBound])
            if blockContent.contains("botType") || blockContent.contains("\"name\"") {
                cleaned.removeSubrange(startRange.lowerBound...endRange.upperBound)
            } else {
                break
            }
        }
        
        // Remove raw JSON objects containing config fields
        if let jsonStart = cleaned.range(of: "{", options: .literal),
           let jsonEnd = cleaned.range(of: "}", options: .backwards),
           jsonStart.lowerBound < jsonEnd.upperBound {
            let potentialJSON = String(cleaned[jsonStart.lowerBound..<jsonEnd.upperBound])
            if potentialJSON.contains("\"botType\"") || potentialJSON.contains("\"tradingPair\"") ||
               potentialJSON.contains("\"symbol\"") || potentialJSON.contains("\"direction\"") ||
               potentialJSON.contains("botType") || potentialJSON.contains("tradingPair") {
                cleaned.removeSubrange(jsonStart.lowerBound..<jsonEnd.upperBound)
            }
        }
        
        // Remove intro lines that reference JSON configuration
        cleaned = cleaned.replacingOccurrences(
            of: "Here's the JSON configuration[^\\n]*:\\s*",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "Here is the JSON[^\\n]*:\\s*",
            with: "",
            options: .regularExpression
        )
        
        // Remove technical "Explanation:" sections
        if let explanationRange = cleaned.range(of: "\nExplanation:", options: .caseInsensitive) {
            if let nextSectionRange = cleaned.range(of: "\n\n", range: explanationRange.upperBound..<cleaned.endIndex) {
                let afterExplanation = String(cleaned[nextSectionRange.upperBound...])
                cleaned = String(cleaned[..<explanationRange.lowerBound]) + afterExplanation
            } else {
                cleaned = String(cleaned[..<explanationRange.lowerBound])
            }
        }
        
        // Remove lines with technical field names (parameter explanations)
        let technicalPatterns = [
            "- Base Order Size:[^\\n]*\\n?",
            "- Take Profit:[^\\n]*\\n?",
            "- Stop Loss:[^\\n]*\\n?",
            "- Max Orders:[^\\n]*\\n?",
            "- Price Deviation:[^\\n]*\\n?",
            "- Investment Amount:[^\\n]*\\n?",
            "- Leverage:[^\\n]*\\n?",
            "- Margin Mode:[^\\n]*\\n?"
        ]
        for pattern in technicalPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        
        // Remove bracketed action indicators
        cleaned = cleaned.replacingOccurrences(
            of: "\\[(?:Execute|Place|Create|Submit|Confirm|Set|Cancel)\\s+\\w+(?:\\s+\\w+)?\\]",
            with: "",
            options: .regularExpression
        )
        
        // === MARKDOWN STRIPPING ===
        cleaned = cleaned.replacingOccurrences(of: "\\n#{1,6}\\s*", with: "\n", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
        for _ in 0..<3 {
            cleaned = cleaned.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: "__(.+?)__", with: "$1", options: .regularExpression)
        }
        for _ in 0..<2 {
            cleaned = cleaned.replacingOccurrences(of: "(?<![*\\s])\\*([^*\\n]+?)\\*(?![*])", with: "$1", options: .regularExpression)
        }
        cleaned = cleaned.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(?<=\\s|^)\\*\\*(?=\\S)", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(?<=\\S)\\*\\*(?=\\s|$|[.,!?;:])", with: "", options: .regularExpression)
        
        // Clean up extra whitespace and newlines from removed blocks
        cleaned = cleaned.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isUser {
                Spacer(minLength: 40)
                userBubble
            } else {
                aiBubble
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // AI message - card with avatar (consistent with other AI chats)
    // Uses cleaned text to hide config blocks from user
    private var aiBubble: some View {
        let displayText = Self.cleanMessageForDisplay(message.text)
        return HStack(alignment: .top, spacing: 10) {
            // AI Avatar - LIGHT MODE FIX: Adaptive gold tones
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [BrandColors.goldLight.opacity(0.25), BrandColors.goldBase.opacity(0.1)]
                                : [Color(red: 0.78, green: 0.60, blue: 0.10).opacity(0.15), Color(red: 0.65, green: 0.48, blue: 0.06).opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? BrandColors.goldBase : Color(red: 0.68, green: 0.50, blue: 0.08))
            }
            
            VStack(alignment: .leading, spacing: 6) {
                if !displayText.isEmpty {
                    Text(displayText)
                        .font(.system(size: 15))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(formattedTimestamp(message.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }
    
    // User message - premium gold styling (matches main AI Chat) - LIGHT MODE FIX
    private var userBubble: some View {
        return VStack(alignment: .trailing, spacing: 6) {
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 15))
                    // LIGHT MODE FIX: Adaptive text on gold bubble
                    .foregroundColor(colorScheme == .dark ? Color.black.opacity(0.9) : Color(red: 0.30, green: 0.22, blue: 0.02))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(formattedTimestamp(message.timestamp))
                .font(.system(size: 10))
                .foregroundColor(colorScheme == .dark ? Color.black.opacity(0.6) : Color(red: 0.45, green: 0.35, blue: 0.10).opacity(0.7))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            ZStack {
                // Base gold gradient - LIGHT MODE FIX: Warm amber
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? BrandColors.goldVertical
                            : LinearGradient(
                                colors: [Color(red: 0.96, green: 0.88, blue: 0.65), Color(red: 0.92, green: 0.82, blue: 0.52)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
                // Top gloss highlight for premium feel
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(colorScheme == .dark ? 0.28 : 0.40), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    colorScheme == .dark
                        ? BrandColors.goldLight.opacity(0.6)
                        : Color(red: 0.80, green: 0.65, blue: 0.25).opacity(0.35),
                    lineWidth: colorScheme == .dark ? 0.8 : 0.5
                )
        )
    }
    
    private func formattedTimestamp(_ date: Date) -> String {
        ModernChatBubble.timeFormatter.string(from: date)
    }
}

// MARK: - Bubble Shape
struct BubbleShape: Shape {
    let corners: UIRectCorner
    let radius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Typing Indicator (Unified gold theme with AI avatar)
struct TypingIndicator: View {
    @State private var dotPhase: Int = 0
    @State private var animationTimer: Timer? = nil
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // AI Avatar - LIGHT MODE FIX: Adaptive gold tones
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [BrandColors.goldLight.opacity(0.25), BrandColors.goldBase.opacity(0.1)]
                                : [Color(red: 0.78, green: 0.60, blue: 0.10).opacity(0.15), Color(red: 0.65, green: 0.48, blue: 0.06).opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? BrandColors.goldBase : Color(red: 0.68, green: 0.50, blue: 0.08))
            }
            
            // Animated dots - LIGHT MODE FIX: Deeper amber
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(
                            isDark
                                ? BrandColors.goldLight.opacity(dotPhase == index ? 1.0 : 0.35)
                                : Color(red: 0.78, green: 0.60, blue: 0.10).opacity(dotPhase == index ? 1.0 : 0.30)
                        )
                        .frame(width: 8, height: 8)
                        .scaleEffect(dotPhase == index ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.35), value: dotPhase)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isDark ? BrandColors.goldLight.opacity(0.25) : Color(red: 0.78, green: 0.60, blue: 0.10).opacity(0.15),
                                lineWidth: isDark ? 1 : 0.5
                            )
                    )
            )
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
    }
    
    private func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            DispatchQueue.main.async {
                dotPhase = (dotPhase + 1) % 3
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - Modern Chat Input Bar (Aligned with main AI Chat styling)
struct ModernChatInputBar: View {
    @Binding var text: String
    var placeholder: String = "Ask about bots..."
    var onSend: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isEditing: Bool = false
    
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Text field - using UIKit-backed ChatTextField for reliable keyboard
            ChatTextField(text: $text, placeholder: placeholder)
                .onSubmit {
                    submitMessage()
                }
                .onEditingChanged { editing in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isEditing = editing
                    }
                }
                .frame(height: 42)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(DS.Adaptive.chipBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(
                            isEditing ? BrandColors.goldLight.opacity(0.6) : DS.Adaptive.stroke,
                            lineWidth: isEditing ? 1.5 : 1
                        )
                )
                .animation(.easeOut(duration: 0.15), value: isEditing)
            
            // Circular send button matching main AI chat - LIGHT MODE FIX
            Button {
                submitMessage()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            colorScheme == .dark
                                ? BrandColors.goldVertical
                                : LinearGradient(
                                    colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.48, blue: 0.06)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                        )
                        .frame(width: 36, height: 36)
                    
                    // Glass highlight
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(colorScheme == .dark ? 0.3 : 0.35), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        // LIGHT MODE FIX: White icon on darker gold
                        .foregroundColor(colorScheme == .dark ? .black.opacity(0.9) : .white.opacity(0.95))
                }
            }
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.45)
            .scaleEffect(canSend ? 1.0 : 0.95)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            DS.Adaptive.background
                .overlay(
                    Rectangle()
                        .fill(DS.Adaptive.divider)
                        .frame(height: 0.5),
                    alignment: .top
                )
        )
    }
    
    private func submitMessage() {
        guard canSend else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        onSend(text)
        text = ""
        // Dismiss keyboard after sending
        UIApplication.shared.dismissKeyboard()
    }
}

// MARK: - DCA Bot View
extension TradingBotView {
    private var dcaBotView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Main Settings Card
                formCard {
                    VStack(alignment: .leading, spacing: 12) {
                        cardHeader("MAIN")
                        styledTextField(title: "Bot Name", text: $botName)
                        styledPicker(title: "Exchange", selection: $selectedExchange, options: exchangeOptions)
                        HStack(spacing: 12) {
                            styledPicker(title: "Direction", selection: $selectedDirection, options: directionOptions)
                            styledPicker(title: "Bot Type", selection: $selectedBotType, options: botTypeOptions)
                        }
                        HStack(spacing: 12) {
                            styledPicker(title: "Trading Pair", selection: $selectedTradingPairDCA, options: tradingPairsOptions)
                            styledPicker(title: "Profit Currency", selection: $selectedProfitCurrency, options: profitCurrencyOptions)
                        }
                    }
                }
                
                // Entry Order Card
                formCard {
                    VStack(alignment: .leading, spacing: 12) {
                        cardHeader("ENTRY ORDER")
                        styledTextField(title: "Base Order Size", text: $baseOrderSize, keyboard: .decimalPad)
                        styledPicker(title: "Start Order Type", selection: $selectedStartOrderType, options: startOrderTypes)
                        styledPicker(title: "Trade Condition", selection: $selectedTradeCondition, options: tradeConditions)
                    }
                }
                
                // Averaging Order Card
                formCard {
                    VStack(alignment: .leading, spacing: 12) {
                        cardHeader("AVERAGING ORDER")
                        styledTextField(title: "Order Size", text: $averagingOrderSize, keyboard: .decimalPad)
                        styledTextField(title: "Price Deviation (%)", text: $priceDeviation, keyboard: .decimalPad)
                        styledTextField(title: "Max Orders", text: $maxAveragingOrders, keyboard: .numberPad)
                        styledTextField(title: "Step Multiplier", text: $averagingOrderStepMultiplier, keyboard: .decimalPad)
                    }
                }
                
                // Exit Order Card
                formCard {
                    VStack(alignment: .leading, spacing: 12) {
                        cardHeader("EXIT ORDER")
                        styledTextField(title: "Take Profit (%)", text: $takeProfit, keyboard: .decimalPad)
                        styledPicker(title: "TP Type", selection: $selectedTakeProfitType, options: takeProfitTypes)
                        styledToggle(title: "Trailing", isOn: $trailingEnabled)
                        styledToggle(title: "Reinvest Profit", isOn: $revertProfit)
                        styledToggle(title: "Stop Loss", isOn: $stopLossEnabled)
                        if stopLossEnabled {
                            styledTextField(title: "Stop Loss (%)", text: $stopLossValue, keyboard: .decimalPad)
                            styledTextField(title: "Max Hold (days)", text: $maxHoldPeriod, keyboard: .numberPad)
                        }
                    }
                }
                
                // Advanced Card
                formCard {
                    VStack(alignment: .leading, spacing: 12) {
                        DisclosureGroup(isExpanded: $isAdvancedViewExpanded) {
                            VStack(alignment: .leading, spacing: 12) {
                                styledTextField(title: "Balance", text: $balanceInfo, disabled: true)
                                styledTextField(title: "Max Bot Usage", text: $maxAmountForBotUsage, keyboard: .decimalPad)
                                styledTextField(title: "Max Price Deviation", text: $maxAveragingPriceDeviation, keyboard: .decimalPad)
                            }
                            .padding(.top, 8)
                        } label: {
                            HStack {
                                Text("ADVANCED")
                                    .font(.system(size: 12, weight: .semibold))
                                    // LIGHT MODE FIX: Deeper amber
                                    .foregroundColor(colorScheme == .dark ? BrandColors.goldBase : Color(red: 0.68, green: 0.50, blue: 0.08))
                                    .tracking(0.5)
                                Spacer()
                            }
                        }
                        .accentColor(colorScheme == .dark ? BrandColors.goldBase : Color(red: 0.68, green: 0.50, blue: 0.08))
                    }
                }
                
                // Summary Card
                formCard {
                    VStack(alignment: .leading, spacing: 8) {
                        cardHeader("SUMMARY")
                        Text(dcaSummary)
                            .font(.system(size: 13))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
                
                // Create Button
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    
                    // Paper trading doesn't need acknowledgment
                    if PaperTradingManager.isEnabled {
                        createDcaBot()
                        return
                    }
                    
                    // Check if user has acknowledged bot trading risks
                    if !TradingRiskAcknowledgmentManager.shared.hasAcknowledgedBotTrading {
                        pendingBotCreationAction = { createDcaBot() }
                        showingBotRiskAcknowledgment = true
                        return
                    }
                    
                    createDcaBot()
                } label: {
                    Text("Create DCA Bot")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundColor(BrandColors.ctaTextColor(isDark: colorScheme == .dark))
                        .background(
                            AdaptiveGradients.goldButton(isDark: colorScheme == .dark)
                        )
                        .cornerRadius(14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer(minLength: 100)
            }
            .padding(.vertical, 16)
        }
        .background(DS.Adaptive.background)
    }
    
    private var dcaSummary: String {
        let name = botName.isEmpty ? "—" : botName
        let pair = selectedTradingPairDCA
        let tp = takeProfit.isEmpty ? "—" : "\(takeProfit)%"
        let sl = stopLossEnabled ? (stopLossValue.isEmpty ? "—" : "\(stopLossValue)%") : "Off"
        return "Bot: \(name) | Pair: \(pair) | Direction: \(selectedDirection) | TP: \(tp) | SL: \(sl)"
    }
    
    private func createDcaBot() {
        // SAFETY: Force paper trading when live trading is disabled at app config level
        if !AppConfig.liveTradingEnabled && !PaperTradingManager.isEnabled {
            PaperTradingManager.shared.enablePaperTrading()
        }
        
        // Check if paper trading mode is enabled (or forced by AppConfig)
        if PaperTradingManager.isEnabled || !AppConfig.liveTradingEnabled {
            // Create paper bot
            let bot = PaperBotManager.shared.createDCABot(
                name: botName.isEmpty ? "DCA Bot" : botName,
                exchange: selectedExchange,
                tradingPair: selectedTradingPairDCA,
                direction: selectedDirection,
                baseOrderSize: baseOrderSize.isEmpty ? "50" : baseOrderSize,
                takeProfit: takeProfit.isEmpty ? "5" : takeProfit,
                stopLoss: stopLossEnabled ? stopLossValue : nil,
                maxOrders: maxAveragingOrders.isEmpty ? "10" : maxAveragingOrders,
                priceDeviation: priceDeviation.isEmpty ? "2" : priceDeviation,
                additionalConfig: [
                    "botType": selectedBotType,
                    "profitCurrency": selectedProfitCurrency,
                    "startOrderType": selectedStartOrderType,
                    "tradeCondition": selectedTradeCondition,
                    "averagingOrderSize": averagingOrderSize,
                    "stepMultiplier": averagingOrderStepMultiplier,
                    "takeProfitType": selectedTakeProfitType,
                    "trailingEnabled": String(trailingEnabled),
                    "revertProfit": String(revertProfit),
                    "maxHoldPeriod": maxHoldPeriod
                ]
            )
            
            createdBotName = bot.name
            showBotCreatedAlert = true
            
            // Auto-start the bot
            PaperBotManager.shared.startBot(id: bot.id)
            
            #if DEBUG
            print("[Paper Trading] DCA Bot created: \(bot.name), ID: \(bot.id)")
            #endif
        } else {
            // Live mode - check if exchange is connected
            // For now, show alert that exchange connection is needed
            showNeedExchangeAlert = true
            #if DEBUG
            print("[Live Mode] DCA Bot creation requires exchange connection: \(botName), Exchange: \(selectedExchange)")
            #endif
        }
    }
}

// MARK: - Grid Bot View
extension TradingBotView {
    private var gridBotView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Main Settings Card
                formCard {
                    VStack(alignment: .leading, spacing: 12) {
                        cardHeader("MAIN")
                        styledTextField(title: "Bot Name", text: $gridBotName)
                        styledPicker(title: "Exchange", selection: $gridSelectedExchange, options: exchangeOptions)
                        styledPicker(title: "Trading Pair", selection: $gridSelectedTradingPair, options: tradingPairsOptions)
                    }
                }
                
                // Grid Settings Card
                formCard {
                    VStack(alignment: .leading, spacing: 12) {
                        cardHeader("GRID SETTINGS")
                        styledTextField(title: "Lower Price", text: $gridLowerPrice, placeholder: "e.g. 30000", keyboard: .decimalPad)
                        styledTextField(title: "Upper Price", text: $gridUpperPrice, placeholder: "e.g. 40000", keyboard: .decimalPad)
                        styledTextField(title: "Grid Levels", text: $gridLevels, placeholder: "Number of levels", keyboard: .numberPad)
                        styledTextField(title: "Order Volume", text: $gridOrderVolume, placeholder: "Volume per order", keyboard: .decimalPad)
                    }
                }
                
                // Exit Settings Card
                formCard {
                    VStack(alignment: .leading, spacing: 12) {
                        cardHeader("EXIT SETTINGS")
                        styledTextField(title: "Take Profit (%)", text: $gridTakeProfit, keyboard: .decimalPad)
                        styledToggle(title: "Enable Stop Loss", isOn: $gridStopLossEnabled)
                        if gridStopLossEnabled {
                            styledTextField(title: "Stop Loss (%)", text: $gridStopLossValue, keyboard: .decimalPad)
                        }
                    }
                }
                
                // Summary Card
                formCard {
                    VStack(alignment: .leading, spacing: 8) {
                        cardHeader("SUMMARY")
                        Text(gridSummary)
                            .font(.system(size: 13))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
                
                // Create Button
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    
                    // Paper trading doesn't need acknowledgment
                    if PaperTradingManager.isEnabled {
                        createGridBot()
                        return
                    }
                    
                    // Check if user has acknowledged bot trading risks
                    if !TradingRiskAcknowledgmentManager.shared.hasAcknowledgedBotTrading {
                        pendingBotCreationAction = { createGridBot() }
                        showingBotRiskAcknowledgment = true
                        return
                    }
                    
                    createGridBot()
                } label: {
                    Text("Create Grid Bot")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundColor(BrandColors.ctaTextColor(isDark: colorScheme == .dark))
                        .background(
                            AdaptiveGradients.goldButton(isDark: colorScheme == .dark)
                        )
                        .cornerRadius(14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer(minLength: 100)
            }
            .padding(.vertical, 16)
        }
        .background(DS.Adaptive.background)
    }
    
    private var gridSummary: String {
        let name = gridBotName.isEmpty ? "—" : gridBotName
        let lower = gridLowerPrice.isEmpty ? "—" : gridLowerPrice
        let upper = gridUpperPrice.isEmpty ? "—" : gridUpperPrice
        let levels = gridLevels.isEmpty ? "—" : gridLevels
        return "Bot: \(name) | Range: \(lower) - \(upper) | Levels: \(levels)"
    }
    
    private func createGridBot() {
        // SAFETY: Force paper trading when live trading is disabled at app config level
        if !AppConfig.liveTradingEnabled && !PaperTradingManager.isEnabled {
            PaperTradingManager.shared.enablePaperTrading()
        }
        
        // Check if paper trading mode is enabled (or forced by AppConfig)
        if PaperTradingManager.isEnabled || !AppConfig.liveTradingEnabled {
            // Create paper bot
            let bot = PaperBotManager.shared.createGridBot(
                name: gridBotName.isEmpty ? "Grid Bot" : gridBotName,
                exchange: gridSelectedExchange,
                tradingPair: gridSelectedTradingPair,
                lowerPrice: gridLowerPrice.isEmpty ? "30000" : gridLowerPrice,
                upperPrice: gridUpperPrice.isEmpty ? "40000" : gridUpperPrice,
                gridLevels: gridLevels.isEmpty ? "10" : gridLevels,
                orderVolume: gridOrderVolume.isEmpty ? "10" : gridOrderVolume,
                takeProfit: gridTakeProfit.isEmpty ? "5" : gridTakeProfit,
                stopLoss: gridStopLossEnabled ? gridStopLossValue : nil
            )
            
            createdBotName = bot.name
            showBotCreatedAlert = true
            
            // Auto-start the bot
            PaperBotManager.shared.startBot(id: bot.id)
            
            #if DEBUG
            print("[Paper Trading] Grid Bot created: \(bot.name), ID: \(bot.id)")
            #endif
        } else {
            // Live mode - check if exchange is connected
            showNeedExchangeAlert = true
            #if DEBUG
            print("[Live Mode] Grid Bot creation requires exchange connection: \(gridBotName), Exchange: \(gridSelectedExchange)")
            #endif
        }
    }
}

// MARK: - Signal Bot View
extension TradingBotView {
    private var signalBotView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Main Settings Card
                formCard {
                    VStack(alignment: .leading, spacing: 12) {
                        cardHeader("MAIN")
                        styledTextField(title: "Bot Name", text: $signalBotName)
                        styledPicker(title: "Exchange", selection: $signalSelectedExchange, options: exchangeOptions)
                        styledPicker(title: "Trading Pairs", selection: $signalSelectedPairs, options: tradingPairsOptions)
                    }
                }
                
                // Settings Card
                formCard {
                    VStack(alignment: .leading, spacing: 12) {
                        cardHeader("SETTINGS")
                        styledTextField(title: "Max Investment", text: $signalMaxUsage, placeholder: "e.g. 500 USDT", keyboard: .decimalPad)
                        styledTextField(title: "Price Deviation (%)", text: $signalPriceDeviation, keyboard: .decimalPad)
                        styledTextField(title: "Max Entry Orders", text: $signalEntriesLimit, placeholder: "Number of orders", keyboard: .numberPad)
                    }
                }
                
                // Exit Settings Card
                formCard {
                    VStack(alignment: .leading, spacing: 12) {
                        cardHeader("EXIT SETTINGS")
                        styledTextField(title: "Take Profit (%)", text: $signalTakeProfit, keyboard: .decimalPad)
                        styledToggle(title: "Enable Stop Loss", isOn: $signalStopLossEnabled)
                        if signalStopLossEnabled {
                            styledTextField(title: "Stop Loss (%)", text: $signalStopLossValue, keyboard: .decimalPad)
                        }
                    }
                }
                
                // Summary Card
                formCard {
                    VStack(alignment: .leading, spacing: 8) {
                        cardHeader("SUMMARY")
                        Text(signalSummary)
                            .font(.system(size: 13))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
                
                // Create Button
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    
                    // Paper trading doesn't need acknowledgment
                    if PaperTradingManager.isEnabled {
                        createSignalBot()
                        return
                    }
                    
                    // Check if user has acknowledged bot trading risks
                    if !TradingRiskAcknowledgmentManager.shared.hasAcknowledgedBotTrading {
                        pendingBotCreationAction = { createSignalBot() }
                        showingBotRiskAcknowledgment = true
                        return
                    }
                    
                    createSignalBot()
                } label: {
                    Text("Create Signal Bot")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundColor(BrandColors.ctaTextColor(isDark: colorScheme == .dark))
                        .background(
                            AdaptiveGradients.goldButton(isDark: colorScheme == .dark)
                        )
                        .cornerRadius(14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer(minLength: 100)
            }
            .padding(.vertical, 16)
        }
        .background(DS.Adaptive.background)
    }
    
    private var signalSummary: String {
        let name = signalBotName.isEmpty ? "—" : signalBotName
        let maxUsage = signalMaxUsage.isEmpty ? "—" : signalMaxUsage
        let tp = signalTakeProfit.isEmpty ? "—" : "\(signalTakeProfit)%"
        return "Bot: \(name) | Max Usage: \(maxUsage) | TP: \(tp)"
    }
    
    private func createSignalBot() {
        // SAFETY: Force paper trading when live trading is disabled at app config level
        if !AppConfig.liveTradingEnabled && !PaperTradingManager.isEnabled {
            PaperTradingManager.shared.enablePaperTrading()
        }
        
        // Check if paper trading mode is enabled (or forced by AppConfig)
        if PaperTradingManager.isEnabled || !AppConfig.liveTradingEnabled {
            // Create paper bot
            let bot = PaperBotManager.shared.createSignalBot(
                name: signalBotName.isEmpty ? "Signal Bot" : signalBotName,
                exchange: signalSelectedExchange,
                tradingPair: signalSelectedPairs,
                maxInvestment: signalMaxUsage.isEmpty ? "500" : signalMaxUsage,
                priceDeviation: signalPriceDeviation.isEmpty ? "2" : signalPriceDeviation,
                entriesLimit: signalEntriesLimit.isEmpty ? "5" : signalEntriesLimit,
                takeProfit: signalTakeProfit.isEmpty ? "5" : signalTakeProfit,
                stopLoss: signalStopLossEnabled ? signalStopLossValue : nil
            )
            
            createdBotName = bot.name
            showBotCreatedAlert = true
            
            // Auto-start the bot
            PaperBotManager.shared.startBot(id: bot.id)
            
            #if DEBUG
            print("[Paper Trading] Signal Bot created: \(bot.name), ID: \(bot.id)")
            #endif
        } else {
            // Live mode - check if exchange is connected
            showNeedExchangeAlert = true
            #if DEBUG
            print("[Live Mode] Signal Bot creation requires exchange connection: \(signalBotName), Exchange: \(signalSelectedExchange)")
            #endif
        }
    }
}

// MARK: - Shared Helpers
extension TradingBotView {
    // Card container with consistent styling
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
    
    // Card header with gold accent - LIGHT MODE FIX: Deeper amber
    private func cardHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(colorScheme == .dark ? BrandColors.goldBase : Color(red: 0.68, green: 0.50, blue: 0.08))
            .tracking(0.5)
    }
    
    // Styled text field
    private func styledTextField(title: String, text: Binding<String>, placeholder: String? = nil, disabled: Bool = false, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textSecondary)
            TextField(placeholder ?? title, text: text)
                .keyboardType(keyboard)
                .disabled(disabled)
                .font(.system(size: 15))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(disabled ? DS.Adaptive.overlay(0.2) : DS.Adaptive.chipBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
                .foregroundColor(disabled ? DS.Adaptive.textTertiary : DS.Adaptive.textPrimary)
        }
    }
    
    // Styled picker - wrapper function for BotStyledPicker
    private func styledPicker(title: String, selection: Binding<String>, options: [String]) -> some View {
        BotStyledPicker(title: title, selection: selection, options: options)
    }
}

// MARK: - Bot Styled Picker (Form field dropdown with popover)
private struct BotStyledPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    @State private var showPicker: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textSecondary)
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showPicker = true
            } label: {
                HStack {
                    Text(selection)
                        .font(.system(size: 15))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        // LIGHT MODE FIX: Deeper amber
                        .foregroundColor(colorScheme == .dark ? BrandColors.goldBase : Color(red: 0.68, green: 0.50, blue: 0.08))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.Adaptive.chipBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                FormFieldOptionsPicker(isPresented: $showPicker, selection: $selection, options: options, title: title)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}

// MARK: - Form Field Options Picker (Styled popover for form dropdowns)
private struct FormFieldOptionsPicker: View {
    @Binding var isPresented: Bool
    @Binding var selection: String
    let options: [String]
    let title: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 4) {
            // Header
            HStack {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DS.Adaptive.textSecondary)
                Spacer(minLength: 6)
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(height: 1)
                .padding(.horizontal, 6)
            
            // Options list
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(options, id: \.self) { option in
                        optionRow(for: option)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 200)
        }
        .padding(4)
        .background(DS.Adaptive.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            LinearGradient(colors: [DS.Adaptive.overlay(0.10), .clear], startPoint: .top, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 0.75)
                .allowsHitTesting(false)
        )
        .frame(minWidth: 160, maxWidth: 240)
    }
    
    @ViewBuilder
    private func optionRow(for option: String) -> some View {
        let selected = (option == selection)
        
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                selection = option
            }
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Colors.gold)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 16)
                Text(option)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? DS.Adaptive.textPrimary : DS.Adaptive.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? DS.Adaptive.overlay(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension TradingBotView {
    
    // Styled toggle
    private func styledToggle(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textPrimary)
        }
        .toggleStyle(SwitchToggleStyle(tint: BrandColors.goldBase))
    }
}

// MARK: - Chat Message Model
extension TradingBotView {
    struct ChatMessage: Identifiable {
        let id = UUID()
        let text: String
        let isUser: Bool
    }
}

// MARK: - Preview
struct TradingBotView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TradingBotView(side: .buy,
                           orderType: .market,
                           quantity: 0.0,
                           slippage: 0.0)
        }
        .preferredColorScheme(.dark)
    }
}

