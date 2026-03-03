//
//  DerivativesBotView.swift
//  CryptoSage
//

import SwiftUI

struct DerivativesBotView: View {
    @StateObject private var viewModel = DerivativesBotViewModel()
    @EnvironmentObject private var appState: AppState
    
    /// Determined automatically via ComplianceManager IP-based geolocation
    private var isUSUser: Bool {
        ComplianceManager.shared.isUSUser
    }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Confirmation state for bot start/stop and position close
    @State private var showingStartBotConfirmation = false
    @State private var showingStopBotConfirmation = false
    @State private var showingClosePositionConfirmation = false
    @State private var pendingClosePositionSymbol: String?
    @State private var pendingBotConfig: DerivativesBotConfig?
    
    @StateObject private var aiChatVM = AiChatViewModel(
        systemPrompt: DerivativesBotView.derivativesSystemPrompt,
        storageKey: "csai_derivatives_bot_chat",
        initialGreeting: "Hello! I'm your derivatives trading assistant. I can help you configure leveraged trading bots for futures and perpetual contracts. Tell me about your trading goals, risk tolerance, and preferred leverage, or tap 'Generate Bot Config' for a recommendation."
    )
    
    // Derivatives-specific AI system prompt
    private static let derivativesSystemPrompt = """
    You are a friendly crypto derivatives trading assistant for CryptoSage. Help users set up leveraged trading bots for futures and perpetual contracts.

    When generating a derivatives bot configuration:
    1. HIDE the technical config by wrapping it in special tags (the app will parse this automatically - the user will NOT see these tags)
    2. Give a brief, friendly summary of the strategy with appropriate risk warnings

    CRITICAL FORMAT - MUST USE XML TAGS WITH VALID JSON:
    Put the config on a SINGLE LINE using <bot_config> tags (user won't see):
    <bot_config>{"botType":"derivatives","name":"My BTC Perpetual Bot","exchange":"Binance Futures","market":"BTC-PERP","leverage":10,"marginMode":"isolated","direction":"Long","takeProfit":"5","stopLoss":"3"}</bot_config>

    NEVER use broken formats like bot_config{...}/bot_config or bot_config(...) - they crash the app.
    ALWAYS use <bot_config>{valid JSON here}</bot_config> with quoted keys.

    Then provide a SHORT friendly summary like:
    "I've configured a derivatives bot to trade BTC perpetuals on Binance Futures with 10x leverage in isolated margin mode. This includes a 5% take profit and 3% stop loss. Remember, leveraged trading carries significant risk - only trade what you can afford to lose! Tap the green button below to apply this config."

    Available exchanges: Binance Futures, Coinbase Perps, KuCoin Futures, Bybit
    Available markets: BTC-PERP, ETH-PERP, SOL-PERP, ADA-PERP
    Leverage: 1-125 (recommend 1-20 for beginners)
    Margin modes: isolated (safer), cross
    Directions: Long, Short

    IMPORTANT - Risk Warnings:
    - Always include a brief risk warning about leveraged trading
    - For leverage above 20x, emphasize extreme risk
    - Recommend isolated margin mode for risk management

    DO NOT:
    - Show raw JSON or technical field names to the user
    - Use any format other than <bot_config>{...}</bot_config>
    - Explain each parameter individually with its value
    - Use developer/technical jargon
    - Put the config tags on multiple lines

    Keep responses warm, brief, and focused on helping the user while being mindful of risks.
    """
    
    // MARK: - Subscription Check
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    private var hasAccess: Bool {
        subscriptionManager.hasAccess(to: .derivativesFeatures)
    }

    var body: some View {
        Group {
            if hasAccess {
                unlockedContent
            } else {
                lockedContent
            }
        }
        // DEPRECATED FIX: Use ignoresSafeArea instead of edgesIgnoringSafeArea
        .background(DS.Adaptive.background)
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
    
    // MARK: - Unlocked Content (Full Access)
    private var unlockedContent: some View {
        VStack(spacing: 0) {
            customNavBar
            Divider().background(DS.Adaptive.divider)
            Group {
                switch viewModel.selectedTab {
                case .chat:
                    // Reuse the same AI chat experience as TradingBotView
                    AiChatTabView(viewModel: aiChatVM)
                case .strategy:
                    DerivativesStrategyView(viewModel: viewModel)
                case .risk:
                    riskAccountsContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom primary action for non-chat tabs to avoid clashing with chat input bar
            if viewModel.selectedTab != .chat {
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    if viewModel.isRunning {
                        showingStopBotConfirmation = true
                    } else {
                        guard let ex = viewModel.selectedExchange, let mk = viewModel.selectedMarket else { return }
                        pendingBotConfig = DerivativesBotConfig(exchange: ex, market: mk, leverage: viewModel.leverage, isIsolated: viewModel.isIsolated)
                        showingStartBotConfirmation = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(viewModel.isRunning ? "Stop Bot" : "Start Bot")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        viewModel.isRunning
                        ? AnyShapeStyle(Color.red)
                        : AnyShapeStyle(AdaptiveGradients.goldButton(isDark: colorScheme == .dark))
                    )
                    // LIGHT MODE FIX: Adaptive text color on gold button
                    .foregroundColor(viewModel.isRunning ? .white : (colorScheme == .dark ? .black : .white.opacity(0.95)))
                    .cornerRadius(14)
                }
                .disabled(!viewModel.isReadyToStart && !viewModel.isRunning)
                .opacity((!viewModel.isReadyToStart && !viewModel.isRunning) ? 0.5 : 1)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            viewModel.loadChatHistory()
            setupAIConfigCallback()
            // Start position refresh for real trading mode
            if viewModel.isRealTradingMode {
                viewModel.startPositionRefresh()
            }
            // Apply pending config from AI Chat if available
            applyPendingAIConfig()
        }
        .onDisappear {
            viewModel.stopPositionRefresh()
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedTab)
        // MARK: - Paper Bot Created Alert
        .alert("Derivatives Bot Started", isPresented: $viewModel.showBotCreatedAlert) {
            Button("View My Bots") {
                dismiss()
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("\"\(viewModel.createdBotName)\" has been created and started in Paper Trading mode. Your derivatives bot is now running with simulated leveraged trades.")
        }
        // MARK: - Start Bot Confirmation
        .alert("Start Derivatives Bot?", isPresented: $showingStartBotConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingBotConfig = nil
            }
            Button("Start Bot") {
                if let config = pendingBotConfig {
                    viewModel.startBot(with: config)
                }
                pendingBotConfig = nil
            }
        } message: {
            if let config = pendingBotConfig {
                Text("Start a \(config.leverage)x leveraged \(config.isIsolated ? "isolated" : "cross")-margin bot on \(config.exchange.name) for \(config.market.title)?\n\n\(viewModel.isRealTradingMode ? "⚠️ This will trade with REAL funds. Leveraged trading carries high risk." : "This will use paper trading (simulated funds).")")
            }
        }
        // MARK: - Stop Bot Confirmation
        .alert("Stop Derivatives Bot?", isPresented: $showingStopBotConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Stop Bot", role: .destructive) {
                viewModel.toggleDerivativesBot()
            }
        } message: {
            Text("Are you sure you want to stop the running derivatives bot? Any open positions will remain until manually closed.")
        }
        // MARK: - Close Position Confirmation
        .alert("Close Position?", isPresented: $showingClosePositionConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingClosePositionSymbol = nil
            }
            Button("Close Position", role: .destructive) {
                if let sym = pendingClosePositionSymbol {
                    Task {
                        await viewModel.closePosition(symbol: sym)
                    }
                }
                pendingClosePositionSymbol = nil
            }
        } message: {
            Text("Are you sure you want to close your \(pendingClosePositionSymbol ?? "") position? This action cannot be undone.")
        }
        .alert(
            "Derivatives Trading Notice",
            isPresented: Binding(
                get: { viewModel.tradeErrorMessage != nil },
                set: { showing in
                    if !showing { viewModel.tradeErrorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.tradeErrorMessage ?? "")
        }
    }
    
    /// Set up the callback to apply AI-generated derivatives bot configurations
    private func setupAIConfigCallback() {
        aiChatVM.onApplyConfig = { [self] config in
            applyDerivativesConfig(config)
        }
    }
    
    /// Apply pending config from AI Chat (when navigating from Execute Trade button)
    private func applyPendingAIConfig() {
        guard let config = appState.pendingDerivativesConfig else { return }
        
        // Clear the pending config
        appState.pendingDerivativesConfig = nil
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        
        // Switch to the risk/accounts tab
        withAnimation(.easeInOut(duration: 0.3)) {
            viewModel.selectedTab = .risk
        }
        
        // Apply leverage if specified
        if let leverage = config.leverage, leverage > 0 {
            viewModel.leverage = min(leverage, viewModel.maxLeverage)
        }
        
        // Try to match the symbol to a market
        let normalizedSymbol = config.symbol.uppercased()
        if let market = viewModel.marketsForSelectedExchange.first(where: {
            $0.symbol.uppercased().contains(normalizedSymbol) ||
            $0.title.uppercased().contains(normalizedSymbol)
        }) {
            viewModel.selectedMarket = market
        }
        
        // Apply position side based on trade direction
        viewModel.positionSide = (config.direction == .buy) ? .long : .short
        
        // Set bot name based on the trade
        let directionStr = config.direction == .buy ? "Long" : "Short"
        let leverageStr = config.leverage.map { "\($0)x" } ?? ""
        viewModel.botName = "\(config.symbol) \(directionStr) \(leverageStr)".trimmingCharacters(in: .whitespaces)
    }
    
    /// Apply the AI-generated configuration to the derivatives bot form
    private func applyDerivativesConfig(_ config: AIBotConfig) {
        // Provide haptic feedback
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        
        // Switch to the risk/accounts tab where settings are configured
        withAnimation(.easeInOut(duration: 0.3)) {
            viewModel.selectedTab = .risk
        }
        
        // Apply exchange if specified
        if let exchangeName = config.exchange {
            // Map AI exchange name to available exchanges
            let normalizedName = exchangeName.lowercased()
            if let exchange = viewModel.availableDerivativesExchanges.first(where: {
                $0.name.lowercased().contains(normalizedName.replacingOccurrences(of: " futures", with: "").replacingOccurrences(of: " perps", with: ""))
            }) {
                viewModel.selectedExchange = exchange
            }
        }
        
        // Apply market if specified
        if let marketName = config.market {
            // Map AI market name to available markets
            let normalizedMarket = marketName.uppercased().replacingOccurrences(of: "-PERP", with: "")
            if let market = viewModel.marketsForSelectedExchange.first(where: {
                $0.title.uppercased().contains(normalizedMarket)
            }) {
                viewModel.selectedMarket = market
            }
        }
        
        // Apply leverage if specified
        if let leverage = config.leverage {
            viewModel.leverage = min(max(leverage, 1), viewModel.maxLeverage)
        }
        
        // Apply margin mode if specified
        if let marginMode = config.marginMode {
            viewModel.isIsolated = marginMode.lowercased() == "isolated"
        }
    }
    
    // MARK: - Locked Content (Subscription Required)
    private var lockedContent: some View {
        StandardLockedContentView.derivatives(onDismiss: { dismiss() })
    }
    
    private var customNavBar: some View {
        VStack(spacing: 0) {
            HStack {
                CSNavButton(
                    icon: "chevron.left",
                    action: { dismiss() }
                )
                Spacer()
                Text("Derivatives Bot")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                // Invisible placeholder for symmetric spacing
                Image(systemName: "chevron.left")
                    .opacity(0)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Picker("", selection: $viewModel.selectedTab) {
                ForEach(DerivativesBotViewModel.BotTab.allCases) { tab in
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
    
    private var riskAccountsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Exchange & Market Card
                riskCard {
                    VStack(alignment: .leading, spacing: 14) {
                        riskCardHeader("EXCHANGE & MARKET")

                        // Filtered exchanges for US users
                        // US users can use Coinbase INTX (regulated perpetual-style futures)
                        // but NOT Binance Futures, KuCoin Futures, or Bybit
                        let filteredExchanges: [Exchange] = isUSUser
                            ? viewModel.availableDerivativesExchanges.filter { $0.id == "coinbase" }
                            : viewModel.availableDerivativesExchanges.filter { $0.id != "coinbase" }  // Non-US can't use Coinbase INTX

                        // Exchange picker
                        riskPicker(
                            title: "Exchange",
                            value: viewModel.selectedExchange?.name ?? "Select Exchange",
                            options: filteredExchanges.map { $0.name }
                        ) { selected in
                            if let ex = filteredExchanges.first(where: { $0.name == selected }) {
                                viewModel.selectedExchange = ex
                            }
                        }

                        // Region-based info banner
                        regionInfoBanner

                        // Market picker
                        riskPicker(
                            title: "Market",
                            value: viewModel.selectedMarket?.title ?? "Select Market",
                            options: viewModel.marketsForSelectedExchange.map { $0.title }
                        ) { selected in
                            if let mk = viewModel.marketsForSelectedExchange.first(where: { $0.title == selected }) {
                                viewModel.selectedMarket = mk
                            }
                        }
                    }
                }

                // Risk Management Card
                riskCard {
                    VStack(alignment: .leading, spacing: 16) {
                        riskCardHeader("RISK MANAGEMENT")

                        // Leverage control
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Leverage")
                                    .font(.system(size: 14))
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                Spacer()
                                Text("\(viewModel.leverage)x")
                                    .font(.system(size: 18, weight: .bold))
                                    // LIGHT MODE FIX: Deeper amber leverage text
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: colorScheme == .dark
                                                ? [BrandColors.goldLight, BrandColors.goldBase]
                                                : [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.45, blue: 0.08)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                            
                            HStack(spacing: 12) {
                                // Minus button
                                Button {
                                    #if os(iOS)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    viewModel.leverage = max(1, viewModel.leverage - 1)
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(DS.Adaptive.textPrimary)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            Circle()
                                                .fill(DS.Adaptive.overlay(0.12))
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                        )
                                }
                                
                                // Leverage slider track
                                GeometryReader { geo in
                                    let progress = CGFloat(viewModel.leverage - 1) / CGFloat(viewModel.maxLeverage - 1)
                                    ZStack(alignment: .leading) {
                                        // Background track
                                        Capsule()
                                            .fill(DS.Adaptive.overlay(0.12))
                                            .frame(height: 8)
                                        
                                        // Filled track - LIGHT MODE FIX: Deeper amber
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: colorScheme == .dark
                                                        ? [BrandColors.goldLight, BrandColors.goldBase]
                                                        : [Color(red: 0.82, green: 0.65, blue: 0.15), Color(red: 0.68, green: 0.50, blue: 0.08)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: max(8, geo.size.width * progress), height: 8)
                                    }
                                }
                                .frame(height: 8)
                                
                                // Plus button
                                Button {
                                    #if os(iOS)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    viewModel.leverage = min(viewModel.maxLeverage, viewModel.leverage + 1)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .bold))
                                        // LIGHT MODE FIX: Adaptive icon color
                                        .foregroundColor(colorScheme == .dark ? .black : .white.opacity(0.95))
                                        .frame(width: 44, height: 44)
                                        .background(
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: colorScheme == .dark
                                                            ? [BrandColors.goldLight, BrandColors.goldBase]
                                                            : [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.48, blue: 0.06)],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                        )
                                }
                            }
                            
                            // Preset leverage buttons
                            HStack(spacing: 8) {
                                ForEach([1, 5, 10, 25, 50], id: \.self) { lev in
                                    Button {
                                        #if os(iOS)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        viewModel.leverage = lev
                                    } label: {
                                        Text("\(lev)x")
                                            .font(.system(size: 12, weight: .semibold))
                                            // LIGHT MODE FIX: Adaptive selected text
                                            .foregroundColor(
                                                viewModel.leverage == lev
                                                    ? (colorScheme == .dark ? .black : .white.opacity(0.95))
                                                    : DS.Adaptive.textSecondary
                                            )
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(viewModel.leverage == lev
                                                          ? (colorScheme == .dark
                                                             ? LinearGradient(colors: [BrandColors.goldLight, BrandColors.goldBase], startPoint: .top, endPoint: .bottom)
                                                             : LinearGradient(colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.48, blue: 0.06)], startPoint: .top, endPoint: .bottom))
                                                          : LinearGradient(colors: [DS.Adaptive.chipBackground, DS.Adaptive.chipBackground], startPoint: .top, endPoint: .bottom))
                                            )
                                    }
                                }
                            }
                        }
                        
                        Divider()
                            .background(DS.Adaptive.divider)

                        // Isolated Margin Toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Isolated Margin")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                Text("Limit risk to position margin only")
                                    .font(.system(size: 12))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.isIsolated)
                                .toggleStyle(SwitchToggleStyle(tint: BrandColors.goldBase))
                                .labelsHidden()
                        }
                    }
                }

                // Account Info Card (Real Trading Mode)
                if viewModel.isRealTradingMode {
                    riskCard {
                        VStack(alignment: .leading, spacing: 10) {
                            riskCardHeader("FUTURES ACCOUNT")
                            
                            HStack(spacing: 16) {
                                infoItem(icon: "dollarsign.circle", label: "Balance", value: String(format: "%.2f USDT", viewModel.futuresBalance))
                                infoItem(icon: "chart.bar", label: "Available", value: String(format: "%.2f USDT", viewModel.availableMargin))
                            }
                            
                            if let fundingRate = viewModel.fundingRate {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Funding Rate")
                                            .font(.system(size: 11))
                                            .foregroundColor(DS.Adaptive.textTertiary)
                                        Text(fundingRate.formattedRate)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(fundingRate.isPositive ? .red : .green)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Mark Price")
                                            .font(.system(size: 11))
                                            .foregroundColor(DS.Adaptive.textTertiary)
                                        Text(String(format: "$%.2f", fundingRate.markPrice))
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(DS.Adaptive.textPrimary)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Open Positions Card
                    riskCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                riskCardHeader("OPEN POSITIONS")
                                Spacer()
                                if viewModel.isLoadingPositions {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                            }
                            
                            if viewModel.openPositions.isEmpty {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "chart.line.uptrend.xyaxis")
                                            .font(.system(size: 24))
                                            .foregroundColor(DS.Adaptive.textTertiary)
                                        Text("No open positions")
                                            .font(.system(size: 13))
                                            .foregroundColor(DS.Adaptive.textSecondary)
                                    }
                                    .padding(.vertical, 16)
                                    Spacer()
                                }
                            } else {
                                ForEach(viewModel.openPositions) { position in
                                    positionRow(position)
                                }
                            }
                        }
                    }
                }
                
                // Quick Info Card
                riskCard {
                    VStack(alignment: .leading, spacing: 10) {
                        riskCardHeader("QUICK INFO")
                        
                        HStack(spacing: 16) {
                            infoItem(icon: "arrow.up.arrow.down", label: "Max Leverage", value: "\(viewModel.maxLeverage)x")
                            infoItem(icon: "shield.checkered", label: "Margin Mode", value: viewModel.isIsolated ? "Isolated" : "Cross")
                        }
                        
                        if let market = viewModel.selectedMarket {
                            HStack(spacing: 16) {
                                infoItem(icon: "bitcoinsign.circle", label: "Market", value: market.title)
                            }
                        }
                        
                        // Trading Mode Indicator
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.isRealTradingMode ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(viewModel.isRealTradingMode ? "Live Trading" : "Paper Trading")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(viewModel.isRealTradingMode ? .green : .orange)
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.vertical, 16)
        }
        .scrollViewBackSwipeFix()
    }
    
    // MARK: - Risk Section Helpers
    @ViewBuilder
    private func riskCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
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
    
    private func riskCardHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            // LIGHT MODE FIX: Deeper amber in light mode
            .foregroundColor(colorScheme == .dark ? BrandColors.goldBase : Color(red: 0.68, green: 0.50, blue: 0.08))
            .tracking(0.5)
    }
    
    private func riskPicker(title: String, value: String, options: [String], onSelect: @escaping (String) -> Void) -> some View {
        DerivativesRiskPicker(title: title, value: value, options: options, onSelect: onSelect)
    }
}

// MARK: - Derivatives Risk Picker (Form field dropdown with popover)
private struct DerivativesRiskPicker: View {
    let title: String
    let value: String
    let options: [String]
    let onSelect: (String) -> Void
    @State private var showPicker: Bool = false
    
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
                    Text(value)
                        .font(.system(size: 15))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BrandColors.goldBase)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DS.Adaptive.chipBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                DerivativesOptionsPicker(isPresented: $showPicker, currentValue: value, options: options, title: title, onSelect: onSelect)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}

// MARK: - Derivatives Options Picker (Styled popover)
private struct DerivativesOptionsPicker: View {
    @Binding var isPresented: Bool
    let currentValue: String
    let options: [String]
    let title: String
    let onSelect: (String) -> Void
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
        let selected = (option == currentValue)
        
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onSelect(option)
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

extension DerivativesBotView {
    
    /// Region-based info banner showing available exchanges
    private var regionInfoBanner: some View {
        let regionCode = ComplianceManager.shared.countryCode ?? Locale.current.region?.identifier ?? "Unknown"
        let hasDetected = ComplianceManager.shared.hasDetectedCountry
        
        return VStack(spacing: 6) {
            if isUSUser {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    Text("Coinbase INTX available - CFTC-regulated perpetual-style futures")
                        .font(.system(size: 12))
                        .foregroundColor(.green.opacity(0.9))
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text("Region: \(regionCode)\(hasDetected ? "" : " (device locale)")")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    Text("Binance, KuCoin, or Bybit perpetuals available")
                        .font(.system(size: 12))
                        .foregroundColor(.blue.opacity(0.9))
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text("Region: \(regionCode) (Coinbase INTX is US-only)")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
        }
    }
    
    private func infoItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(BrandColors.goldBase)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
        }
    }
    
    /// Display a single futures position row with PnL and close button
    private func positionRow(_ position: FuturesPosition) -> some View {
        VStack(spacing: 8) {
            HStack {
                // Position direction badge
                HStack(spacing: 4) {
                    Image(systemName: position.isLong ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(position.isLong ? "LONG" : "SHORT")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(position.isLong ? .green : .red)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill((position.isLong ? Color.green : Color.red).opacity(0.15))
                )
                
                // Symbol
                Text(position.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                // Leverage badge
                Text("\(position.leverage)x")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(BrandColors.goldBase)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(BrandColors.goldBase.opacity(0.15))
                    )
                
                Spacer()
                
                // Close button – requires confirmation to prevent accidental taps
                Button {
                    pendingClosePositionSymbol = position.symbol
                    showingClosePositionConfirmation = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.red.opacity(0.7))
                }
            }
            
            HStack {
                // Entry price
                VStack(alignment: .leading, spacing: 1) {
                    Text("Entry")
                        .font(.system(size: 9))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(String(format: "$%.2f", position.entryPrice))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                // Mark price
                VStack(alignment: .center, spacing: 1) {
                    Text("Mark")
                        .font(.system(size: 9))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(String(format: "$%.2f", position.markPrice))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                // Liquidation price
                VStack(alignment: .center, spacing: 1) {
                    Text("Liq.")
                        .font(.system(size: 9))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(String(format: "$%.2f", position.liquidationPrice))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                // PnL
                VStack(alignment: .trailing, spacing: 1) {
                    Text("PnL")
                        .font(.system(size: 9))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    HStack(spacing: 2) {
                        Text(String(format: "%+.2f", position.unrealizedPnL))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                        Text(String(format: "(%+.1f%%)", position.pnlPercent))
                            .font(.system(size: 10))
                    }
                    .foregroundColor(position.unrealizedPnL >= 0 ? .green : .red)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.overlay(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(position.unrealizedPnL >= 0 ? Color.green.opacity(0.2) : Color.red.opacity(0.2), lineWidth: 1)
        )
    }
}

