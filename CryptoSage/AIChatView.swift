//
//  AIChatView.swift
//  CryptoSage
//
//  Main AI Chat tab with conversations, quick replies, and input bar.
//

import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Brand Gold Palette (single source of truth for AI tab)
private enum BrandGold {
    // Unified to centralized BrandColors (Classic Gold)
    static let light = BrandColors.goldLight
    static let dark  = BrandColors.goldBase
    static var horizontalGradient: LinearGradient { BrandColors.goldDiagonalGradient }
    static var verticalGradient: LinearGradient { BrandColors.goldVertical }
    
    // Light-mode friendly gradients (no dark edge - cleaner on white backgrounds)
    static var verticalGradientLight: LinearGradient { BrandColors.goldVerticalLight }
    static var horizontalGradientLight: LinearGradient { BrandColors.goldHorizontalLight }
}

// MARK: - AI Trade Configuration Model
struct AITradeConfig: Codable, Equatable {
    enum TradeDirection: String, Codable, Equatable {
        case buy, sell
    }
    enum OrderType: String, Codable, Equatable {
        case market, limit
    }
    
    let symbol: String              // e.g., "BTC", "ETH"
    let quoteCurrency: String?      // e.g., "USDT", "USD" - defaults based on region if nil
    let direction: TradeDirection   // buy or sell
    let orderType: OrderType        // market or limit
    let amount: String?             // Quantity or USD amount
    let isUSDAmount: Bool           // true if amount is in USD (e.g., "$100"), false if quantity
    let price: String?              // Target price for limit orders
    let stopLoss: String?           // Optional stop loss percentage
    let takeProfit: String?         // Optional take profit percentage
    let leverage: Int?              // For derivatives trading (1-125)
    
    var displayDirection: String {
        direction == .buy ? "Buy" : "Sell"
    }
    
    var displayOrderType: String {
        orderType == .market ? "Market" : "Limit"
    }
    
    /// Display the trading pair (e.g., "BTC/USDT")
    /// Always shows the quote currency, defaulting based on user region
    var displayPair: String {
        let quote = quoteCurrency ?? (ComplianceManager.shared.isUSUser ? "USD" : "USDT")
        return "\(symbol)/\(quote)"
    }
    
    // Custom decoder to handle backwards compatibility (isUSDAmount defaults to false)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(String.self, forKey: .symbol)
        quoteCurrency = try container.decodeIfPresent(String.self, forKey: .quoteCurrency)
        direction = try container.decode(TradeDirection.self, forKey: .direction)
        orderType = try container.decode(OrderType.self, forKey: .orderType)
        amount = try container.decodeIfPresent(String.self, forKey: .amount)
        isUSDAmount = try container.decodeIfPresent(Bool.self, forKey: .isUSDAmount) ?? false
        price = try container.decodeIfPresent(String.self, forKey: .price)
        stopLoss = try container.decodeIfPresent(String.self, forKey: .stopLoss)
        takeProfit = try container.decodeIfPresent(String.self, forKey: .takeProfit)
        leverage = try container.decodeIfPresent(Int.self, forKey: .leverage)
    }
    
    // Standard initializer
    init(symbol: String, quoteCurrency: String? = nil, direction: TradeDirection, orderType: OrderType, 
         amount: String? = nil, isUSDAmount: Bool = false, price: String? = nil, 
         stopLoss: String? = nil, takeProfit: String? = nil, leverage: Int? = nil) {
        self.symbol = symbol
        self.quoteCurrency = quoteCurrency
        self.direction = direction
        self.orderType = orderType
        self.amount = amount
        self.isUSDAmount = isUSDAmount
        self.price = price
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.leverage = leverage
    }
}

private struct AIChatModeCapabilities {
    let liveTradingEnabled: Bool
    let paperModeEnabled: Bool
    let paperAccessAvailable: Bool
    let demoModeEnabled: Bool

    var canExecuteLiveTrade: Bool { liveTradingEnabled }
    var canExecutePaperTrade: Bool { !liveTradingEnabled && paperModeEnabled && paperAccessAvailable }
    var canCreateAlerts: Bool { true }

    var currentModeLabel: String {
        if canExecuteLiveTrade { return "live" }
        if canExecutePaperTrade { return "paper" }
        if demoModeEnabled { return "demo" }
        return "advisory"
    }

    @MainActor
    static func current() -> AIChatModeCapabilities {
        AIChatModeCapabilities(
            liveTradingEnabled: AppConfig.liveTradingEnabled,
            paperModeEnabled: PaperTradingManager.isEnabled,
            paperAccessAvailable: PaperTradingManager.shared.hasAccess,
            demoModeEnabled: DemoModeManager.isEnabled
        )
    }
}

// MARK: - Execute Trade Button
struct ExecuteTradeButton: View {
    let config: AITradeConfig
    let onExecute: () -> Void
    var onDismiss: (() -> Void)? = nil
    
    @State private var isPressed = false
    @State private var glowAnimation = false
    @State private var showingRiskAcknowledgment = false
    @State private var showingDerivativesAcknowledgment = false
    @State private var showingPreTradeConfirmation = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Risk manager instance
    private var riskManager: TradingRiskAcknowledgmentManager { .shared }
    
    /// Check if live trading mode is enabled (developer mode)
    private var isLiveTradingMode: Bool {
        capabilities.canExecuteLiveTrade
    }
    
    /// Mode/access capabilities shared with prompt routing.
    private var capabilities: AIChatModeCapabilities {
        AIChatModeCapabilities.current()
    }

    private var isPaperModeEnabled: Bool {
        capabilities.paperModeEnabled
    }

    private var hasPaperAccess: Bool {
        capabilities.paperAccessAvailable
    }

    private var canExecutePaperTrade: Bool {
        capabilities.canExecutePaperTrade
    }

    private var isPaperMode: Bool {
        canExecutePaperTrade
    }
    
    /// Whether this is a derivatives/futures trade
    private var isDerivativesTrade: Bool {
        config.leverage != nil && config.leverage! > 1
    }
    
    /// Button title based on trading mode and type
    private var buttonTitle: String {
        if isLiveTradingMode {
            // Developer mode - live trading
            return isDerivativesTrade ? "Live Futures" : "Live Trade"
        }
        if canExecutePaperTrade {
            return isDerivativesTrade ? "Paper Futures" : "Paper Trade"
        }
        return "Set Up Trade"
    }
    
    /// Mode subtitle
    private var modeSubtitle: String {
        if isLiveTradingMode {
            // Developer mode - real trade
            return isDerivativesTrade ? "Real Futures Order" : "Real Trade Order"
        }
        if canExecutePaperTrade {
            return isDerivativesTrade ? "Simulated Futures" : "Simulated Trade"
        }
        if capabilities.demoModeEnabled {
            return "Review and switch from Demo Mode"
        }
        return "Review in Trading Tab"
    }
    
    private var isSetupState: Bool {
        !canExecutePaperTrade && !isLiveTradingMode
    }
    
    private var modeAccent: Color {
        if canExecutePaperTrade { return AppTradingMode.paper.color }
        if isLiveTradingMode { return Color.green }
        return DS.Adaptive.textTertiary
    }
    
    private var modeAccentLight: Color {
        if canExecutePaperTrade { return AppTradingMode.paper.secondaryColor }
        if isLiveTradingMode { return Color(red: 0.56, green: 0.92, blue: 0.66) }
        return DS.Adaptive.textSecondary
    }
    
    /// Display amount with proper formatting
    // PERFORMANCE FIX: Cached formatters to avoid per-render allocations
    private static let _amountFormatter: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .decimal; nf.maximumFractionDigits = 2; return nf
    }()

    private var amountDisplay: String? {
        guard let amount = config.amount else { return nil }
        if config.isUSDAmount {
            if let doubleAmount = Double(amount) {
                return "$\(Self._amountFormatter.string(from: NSNumber(value: doubleAmount)) ?? amount)"
            }
            return "$\(amount)"
        } else {
            return "\(amount) \(config.symbol)"
        }
    }
    
    /// Direction indicator color (green for buy, red for sell)
    private var directionColor: Color {
        config.direction == .buy ? Color(red: 0.2, green: 0.75, blue: 0.4) : Color(red: 0.95, green: 0.4, blue: 0.35)
    }
    
    /// Compact price display for limit orders
    private var compactPriceDisplay: String? {
        guard config.orderType == .limit, let price = config.price else { return nil }
        if let doublePrice = Double(price) {
            if doublePrice >= 10000 {
                return String(format: "$%.0f", doublePrice)
            } else if doublePrice >= 1000 {
                return String(format: "$%.1f", doublePrice)
            } else if doublePrice >= 1 {
                return String(format: "$%.2f", doublePrice)
            }
        }
        return "$\(price)"
    }
    
    /// Whether the trade requires risk acknowledgment check
    private var requiresRiskCheck: Bool {
        isLiveTradingMode
    }
    
    /// Handle the execute action with risk checks
    private func handleExecuteAction() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        
        // Paper trading mode with access - route directly to the executable spot form.
        if canExecutePaperTrade {
            executeWithAnimation()
            return
        }
        
        // Live trading mode - always require risk acknowledgment
        if isLiveTradingMode {
            // Check basic trading risk acknowledgment
            if !riskManager.hasValidAcknowledgment {
                showingRiskAcknowledgment = true
                return
            }
            
            // Check derivatives-specific acknowledgment if applicable
            if isDerivativesTrade && !riskManager.hasAcknowledgedDerivatives {
                showingDerivativesAcknowledgment = true
                return
            }
            
            // Show pre-trade confirmation for live trades
            showingPreTradeConfirmation = true
            return
        }
        
        // Paper mode toggled but no access: route to trading tab where upgrade flow is explicit.
        if isPaperModeEnabled && !hasPaperAccess {
            executeWithAnimation()
            return
        }
        
        // Paper trading available but not currently enabled
        // Skip risk acknowledgment for simulated trades
        executeWithAnimation()
    }
    
    /// Execute with button press animation
    private func executeWithAnimation() {
        withAnimation(.easeInOut(duration: 0.1)) {
            isPressed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = false
            }
            onExecute()
        }
    }
    
    var body: some View {
        Button(action: handleExecuteAction) {
            HStack(spacing: 12) {
                // Coin logo with direction indicator
                ZStack {
                    // Coin image
                    CoinImageView(symbol: config.symbol, url: nil, size: 38)
                        .clipShape(Circle())
                    
                    // Direction badge overlay
                    Circle()
                        .fill(directionColor)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Image(systemName: config.direction == .buy ? "arrow.up" : "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .offset(x: 12, y: 12)
                }
                .frame(width: 40, height: 40)
                
                // Trade details - Compact layout
                VStack(alignment: .leading, spacing: 3) {
                    // Main action text - single line
                    Text("\(config.displayDirection) \(config.displayPair)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                    
                    // Trade details row - compact with proper spacing
                    HStack(spacing: 4) {
                        // Order type pill
                        Text(config.displayOrderType)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Adaptive.chipBackground)
                            .cornerRadius(4)
                        
                        // Leverage pill for derivatives trades
                        if let leverage = config.leverage, leverage > 1 {
                            Text("\(leverage)x")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.85))
                                .cornerRadius(4)
                        }
                        
                        // Amount and price combined
                        if let amount = amountDisplay {
                            Text(amount)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                                .lineLimit(1)
                        }
                        
                        if let priceDisplay = compactPriceDisplay {
                            Text("@ \(priceDisplay)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.Adaptive.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .lineLimit(1)
                }
                .layoutPriority(1)
                
                Spacer(minLength: 8)
                
                // Action button area - Fixed width to prevent overflow
                VStack(alignment: .trailing, spacing: 3) {
                    // Main action button with semantic mode accent
                    HStack(spacing: 4) {
                        Image(systemName: isPaperMode ? "doc.text.fill" : "bolt.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(buttonTitle)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundColor(isSetupState ? DS.Adaptive.textPrimary : Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                isSetupState
                                    ? LinearGradient(
                                        colors: [DS.Adaptive.chipBackground, DS.Adaptive.chipBackground],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    : LinearGradient(
                                        colors: [modeAccentLight, modeAccent],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                            )
                            .overlay(
                                // Top gloss highlight
                                LinearGradient(
                                    colors: [Color.white.opacity(isDark ? 0.16 : 0.25), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isSetupState ? DS.Adaptive.stroke : modeAccent.opacity(isDark ? 0.55 : 0.4),
                                        lineWidth: 0.8
                                    )
                            )
                    )
                    .fixedSize()
                    
                    // Mode indicator
                    HStack(spacing: 3) {
                        Circle()
                            .fill(modeAccent)
                            .frame(width: 5, height: 5)
                        Text(modeSubtitle)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(DS.Adaptive.textTertiary)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    // Base card fill with warm cream in light mode
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isDark ? [
                                    Color(red: 0.09, green: 0.09, blue: 0.11),
                                    Color(red: 0.05, green: 0.05, blue: 0.07)
                                ] : [
                                    Color(red: 1.0, green: 0.992, blue: 0.976),   // Warm cream top
                                    Color(red: 0.99, green: 0.98, blue: 0.965)    // Slightly warmer bottom
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Mode top-edge highlight gradient
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [modeAccentLight.opacity(isSetupState ? 0.06 : (isDark ? 0.10 : 0.08)), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                // Mode-tinted gradient border
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                modeAccent.opacity(isSetupState ? 0.2 : (isDark ? 0.35 : 0.3)),
                                DS.Adaptive.divider,
                                DS.Adaptive.divider
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            // Mode accent bar on left edge
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                modeAccentLight.opacity(isSetupState ? 0.35 : (isDark ? 0.8 : 0.7)),
                                modeAccent.opacity(isSetupState ? 0.25 : (isDark ? 0.6 : 0.5))
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                    .padding(.vertical, 12)
            }
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        // Dismiss X button overlay (top-right corner)
        .overlay(alignment: .topTrailing) {
            if onDismiss != nil {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(DS.Adaptive.chipBackground)
                                .overlay(
                                    Circle()
                                        .stroke(DS.Adaptive.divider, lineWidth: 0.5)
                                )
                        )
                }
                .offset(x: -8, y: 8)
            }
        }
        // Swipe down to dismiss
        .offset(y: dragOffset)
        .gesture(
            onDismiss == nil ? nil :
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    // Only allow downward drag
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height * 0.6
                    }
                }
                .onEnded { value in
                    if value.translation.height > 60 {
                        // Dismiss with animation
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 300
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            onDismiss?()
                        }
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        // Risk acknowledgment sheet
        .sheet(isPresented: $showingRiskAcknowledgment) {
            TradingRiskAcknowledgmentView(
                onAcknowledge: {
                    // After acknowledging, check if derivatives acknowledgment is also needed
                    if isDerivativesTrade && !riskManager.hasAcknowledgedDerivatives {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingDerivativesAcknowledgment = true
                        }
                    } else {
                        showingPreTradeConfirmation = true
                    }
                },
                onDecline: {
                    // User declined - do nothing
                }
            )
        }
        // Derivatives risk acknowledgment sheet
        .sheet(isPresented: $showingDerivativesAcknowledgment) {
            DerivativesRiskAcknowledgmentView(
                onAcknowledge: {
                    showingPreTradeConfirmation = true
                },
                onDecline: {
                    // User declined - do nothing
                }
            )
        }
        // Pre-trade confirmation alert (live trades)
        .alert("⚠️ Confirm Real Trade", isPresented: $showingPreTradeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Execute Trade", role: .destructive) {
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                #endif
                executeWithAnimation()
            }
        } message: {
            Text("""
            \(TradingRiskTexts.preTradeWarning)
            
            \(config.displayDirection) \(config.displayPair)
            Order Type: \(config.orderType == .limit ? "Limit" : "Market")
            \(config.amount != nil ? "Amount: \(config.amount!)" : "")
            \(config.price != nil ? "Price: \(config.price!)" : "")
            
            \(TradingRiskTexts.aiTradeDisclaimer)
            """)
        }
    }
}

// MARK: - Create Bot Button
struct CreateBotButton: View {
    let config: AIBotConfig
    let onExecute: () -> Void
    var onDismiss: (() -> Void)? = nil
    
    @State private var isPressed = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Check if live trading mode is enabled (developer mode)
    private var isLiveTradingMode: Bool {
        AppConfig.liveTradingEnabled
    }
    
    /// Check if paper trading mode is enabled
    private var isPaperMode: Bool {
        PaperTradingManager.isEnabled
    }
    
    /// Bot type icon from PaperBotType
    private var botTypeIcon: String {
        switch config.botType {
        case .dca: return "repeat.circle.fill"
        case .grid: return "square.grid.3x3.fill"
        case .signal: return "bolt.circle.fill"
        case .derivatives: return "chart.line.uptrend.xyaxis.circle.fill"
        case .predictionMarket: return "chart.bar.xaxis.ascending"
        }
    }
    
    /// Bot type color
    private var botTypeColor: Color {
        switch config.botType {
        case .dca: return .blue
        case .grid: return .purple
        case .signal: return .orange
        case .derivatives: return .red
        case .predictionMarket: return .cyan
        }
    }
    
    /// Button title
    private var buttonTitle: String {
        isLiveTradingMode ? "Create Live Bot" : "Create Paper Bot"
    }
    
    /// Mode subtitle
    private var modeSubtitle: String {
        isLiveTradingMode ? "Real Trading Bot" : "Simulated Bot"
    }
    
    private var modeAccent: Color {
        isPaperMode ? AppTradingMode.paper.color : Color.green
    }
    
    private var modeAccentLight: Color {
        isPaperMode ? AppTradingMode.paper.secondaryColor : Color(red: 0.56, green: 0.92, blue: 0.66)
    }
    
    /// Display the bot name or generate one
    private var displayName: String {
        if let name = config.name, !name.isEmpty {
            return name
        }
        return "\(config.botType.displayName)"
    }
    
    /// Display the trading pair
    private var displayPair: String {
        if let pair = config.tradingPair {
            return pair.replacingOccurrences(of: "_", with: "/")
        }
        // For prediction bots, show the market title instead
        if let marketTitle = config.marketTitle {
            return String(marketTitle.prefix(25)) + (marketTitle.count > 25 ? "..." : "")
        }
        return "—"
    }
    
    /// Key parameter to display based on bot type
    private var keyParameter: String? {
        switch config.botType {
        case .dca:
            if let size = config.baseOrderSize {
                return "$\(size)/order"
            }
        case .grid:
            if let lower = config.lowerPrice, let upper = config.upperPrice {
                return "$\(lower) - $\(upper)"
            }
        case .signal:
            if let max = config.maxInvestment {
                return "Max $\(max)"
            }
        case .derivatives:
            if let leverage = config.leverage {
                return "\(leverage)x Leverage"
            }
        case .predictionMarket:
            if let outcome = config.outcome, let amount = config.betAmount {
                return "\(outcome) @ $\(amount)"
            }
        }
        return nil
    }
    
    /// Secondary parameter (take profit, etc.)
    private var secondaryParameter: String? {
        if let tp = config.takeProfit {
            return "TP: \(tp)%"
        }
        if let target = config.targetPrice {
            return "Target: \(target)"
        }
        return nil
    }
    
    /// Compact trading pair display
    private var compactPair: String {
        if let pair = config.tradingPair {
            return pair.replacingOccurrences(of: "_", with: "/")
        }
        if let marketTitle = config.marketTitle {
            return String(marketTitle.prefix(18)) + (marketTitle.count > 18 ? "..." : "")
        }
        return "—"
    }
    
    var body: some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
                onExecute()
            }
        }) {
            HStack(spacing: 12) {
                // Bot type icon
                ZStack {
                    Circle()
                        .fill(botTypeColor.opacity(isDark ? 0.2 : 0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: botTypeIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(botTypeColor)
                }
                
                // Bot details - Compact layout
                VStack(alignment: .leading, spacing: 3) {
                    // Bot name with type badge
                    HStack(spacing: 5) {
                        Text(displayName)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                        
                        Text(config.botType.displayName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(botTypeColor.opacity(0.85))
                            .cornerRadius(4)
                    }
                    .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // Bot parameters row - compact
                    HStack(spacing: 4) {
                        // Trading pair / Market
                        Text(compactPair)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Adaptive.chipBackground)
                            .cornerRadius(4)
                            .lineLimit(1)
                        
                        // Key parameter only (most important)
                        if let param = keyParameter {
                            Text(param)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                                .lineLimit(1)
                        }
                        
                        // Take profit (if space allows)
                        if let secondary = secondaryParameter {
                            Text(secondary)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.green)
                                .lineLimit(1)
                        }
                    }
                    .lineLimit(1)
                }
                .layoutPriority(1)
                
                Spacer(minLength: 8)
                
                // Action button area - Fixed width
                VStack(alignment: .trailing, spacing: 3) {
                    // Main action button with semantic mode accent
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10, weight: .semibold))
                        Text(buttonTitle)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [modeAccentLight, modeAccent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                // Top gloss highlight
                                LinearGradient(
                                    colors: [Color.white.opacity(isDark ? 0.16 : 0.25), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        modeAccent.opacity(isDark ? 0.55 : 0.4),
                                        lineWidth: 0.8
                                    )
                            )
                    )
                    .fixedSize()
                    
                    // Mode indicator
                    HStack(spacing: 3) {
                        Circle()
                            .fill(modeAccent)
                            .frame(width: 5, height: 5)
                        Text(modeSubtitle)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(DS.Adaptive.textTertiary)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    // Base card fill
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isDark ? [
                                    Color(red: 0.09, green: 0.09, blue: 0.11),
                                    Color(red: 0.05, green: 0.05, blue: 0.07)
                                ] : [
                                    Color(red: 1.0, green: 0.992, blue: 0.976),
                                    Color(red: 0.99, green: 0.98, blue: 0.965)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Bot type color accent at top
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [botTypeColor.opacity(isDark ? 0.08 : 0.06), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                // Gradient border with bot type tint
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                botTypeColor.opacity(isDark ? 0.35 : 0.3),
                                DS.Adaptive.divider,
                                DS.Adaptive.divider
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            // Bot type accent bar on left edge
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                botTypeColor.opacity(isDark ? 0.8 : 0.7),
                                botTypeColor.opacity(isDark ? 0.5 : 0.4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                    .padding(.vertical, 12)
            }
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        // Dismiss X button overlay (top-right corner)
        .overlay(alignment: .topTrailing) {
            if onDismiss != nil {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(DS.Adaptive.chipBackground)
                                .overlay(
                                    Circle()
                                        .stroke(DS.Adaptive.divider, lineWidth: 0.5)
                                )
                        )
                }
                .offset(x: -8, y: 8)
            }
        }
        // Swipe down to dismiss
        .offset(y: dragOffset)
        .gesture(
            onDismiss == nil ? nil :
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height * 0.6
                    }
                }
                .onEnded { value in
                    if value.translation.height > 60 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 300
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            onDismiss?()
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

// MARK: - AI Alert Suggestion Model
struct AIAlertSuggestion: Codable, Equatable {
    let symbol: String
    let targetPrice: Double
    let direction: String // "above" or "below"
    let reason: String
    let enableAI: Bool
    let currentPrice: Double?
    
    // Support both camelCase (targetPrice) and snake_case (target_price) from AI
    enum CodingKeys: String, CodingKey {
        case symbol
        case targetPrice = "targetPrice"
        case direction
        case reason
        case enableAI = "enableAI"
        case currentPrice = "currentPrice"
    }
    
    // Custom decoder to handle both camelCase and snake_case JSON from AI
    init(from decoder: Decoder) throws {
        // Try standard camelCase keys first
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let tp = try? container.decode(Double.self, forKey: .targetPrice) {
            symbol = try container.decode(String.self, forKey: .symbol)
            targetPrice = tp
            direction = try container.decode(String.self, forKey: .direction)
            reason = (try? container.decode(String.self, forKey: .reason)) ?? "Price alert"
            enableAI = (try? container.decode(Bool.self, forKey: .enableAI)) ?? true
            currentPrice = try? container.decode(Double.self, forKey: .currentPrice)
            return
        }
        
        // Fallback: try snake_case keys (target_price, enable_ai, current_price)
        enum SnakeKeys: String, CodingKey {
            case symbol
            case targetPrice = "target_price"
            case direction
            case reason
            case enableAI = "enable_ai"
            case currentPrice = "current_price"
        }
        let container = try decoder.container(keyedBy: SnakeKeys.self)
        symbol = try container.decode(String.self, forKey: .symbol)
        targetPrice = try container.decode(Double.self, forKey: .targetPrice)
        direction = try container.decode(String.self, forKey: .direction)
        reason = (try? container.decode(String.self, forKey: .reason)) ?? "Price alert"
        enableAI = (try? container.decode(Bool.self, forKey: .enableAI)) ?? true
        currentPrice = try? container.decode(Double.self, forKey: .currentPrice)
    }
    
    // Standard init for programmatic creation
    init(symbol: String, targetPrice: Double, direction: String, reason: String, enableAI: Bool = true, currentPrice: Double? = nil) {
        self.symbol = symbol
        self.targetPrice = targetPrice
        self.direction = direction
        self.reason = reason
        self.enableAI = enableAI
        self.currentPrice = currentPrice
    }
    
    var isAbove: Bool { direction.lowercased() == "above" }
    
    var formattedSymbol: String {
        let upper = symbol.uppercased()
        return upper.hasSuffix("USDT") ? upper : "\(upper)USDT"
    }
    
    var formattedTargetPrice: String {
        if targetPrice >= 1000 {
            return String(format: "$%.2f", targetPrice)
        } else if targetPrice >= 1 {
            return String(format: "$%.2f", targetPrice)
        } else if targetPrice >= 0.01 {
            return String(format: "$%.4f", targetPrice)
        } else {
            return String(format: "$%.6f", targetPrice)
        }
    }
    
    var distancePercent: String? {
        guard let current = currentPrice, current > 0 else { return nil }
        let distance = abs(current - targetPrice) / current * 100
        return String(format: "%.1f%%", distance)
    }
}

// MARK: - Create Alert Card
struct CreateAlertCard: View {
    let suggestion: AIAlertSuggestion
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    
    @State private var glowAnimation = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Direction indicator color (green for above, red for below)
    private var directionColor: Color {
        suggestion.isAbove ? Color(red: 0.2, green: 0.75, blue: 0.4) : Color(red: 0.95, green: 0.4, blue: 0.35)
    }
    
    // Alert semantic accent for suggestion card chrome
    private var alertAccent: Color {
        isDark ? BrandColors.alertAccentLight : BrandColors.alertAccent
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 10) {
                // Alert icon with semantic alert tint
                ZStack {
                    Circle()
                        .fill(BrandColors.alertAccent.opacity(isDark ? 0.18 : 0.14))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [BrandColors.alertAccentLight, BrandColors.alertAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Alert Suggestion")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(DS.Adaptive.textPrimary)
                            .lineLimit(1)
                        
                        if suggestion.enableAI {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8))
                                Text("AI")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(BrandColors.ctaTextColor(isDark: isDark))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(BrandColors.ctaHorizontal(isDark: isDark))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isDark ? BrandColors.alertAccent.opacity(0.5) : Color.clear,
                                        lineWidth: 0.5
                                    )
                            )
                            .fixedSize()
                        }
                    }
                    
                    Text(suggestion.reason)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                        .lineLimit(2)
                }
                .layoutPriority(1)
                
                Spacer()
                
                // Dismiss button
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(DS.Adaptive.chipBackground)
                                .overlay(
                                    Circle()
                                        .stroke(DS.Adaptive.divider, lineWidth: 0.5)
                                )
                        )
                }
            }
            
            // Price details
            HStack(spacing: 12) {
                // Symbol and direction
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.symbol.uppercased())
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Image(systemName: suggestion.isAbove ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(directionColor)
                        
                        Text(suggestion.isAbove ? "Above" : "Below")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 8)
                
                // Target price
                VStack(alignment: .trailing, spacing: 4) {
                    Text(suggestion.formattedTargetPrice)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(directionColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    if let distance = suggestion.distancePercent {
                        Text("\(distance) away")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 4)
            
            // Action buttons
            HStack(spacing: 10) {
                // Decline button with gold-tinted stroke
                Button {
                    onDismiss()
                } label: {
                    Text("Not Now")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    PremiumSecondaryCTAStyle(
                        height: 40,
                        horizontalPadding: 12,
                        cornerRadius: 10,
                        font: .system(size: 13, weight: .semibold)
                    )
                )
                
                // Confirm button with alert accent CTA
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    onConfirm()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 12))
                        Text("Create Alert")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    PremiumAccentCTAStyle(
                        accent: BrandColors.alertAccent,
                        height: 40,
                        horizontalPadding: 12,
                        cornerRadius: 10,
                        font: .system(size: 13, weight: .bold)
                    )
                )
            }
        }
        .padding(.leading, 18) // Extra padding for left accent bar
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .background(
            ZStack {
                // Base card fill with warm cream in light mode
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isDark ? [
                                Color(red: 0.09, green: 0.09, blue: 0.11),
                                Color(red: 0.05, green: 0.05, blue: 0.07)
                            ] : [
                                Color(red: 1.0, green: 0.992, blue: 0.976),   // Warm cream top
                                Color(red: 0.99, green: 0.98, blue: 0.965)    // Slightly warmer bottom
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Alert top-edge highlight gradient
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [alertAccent.opacity(isDark ? 0.10 : 0.08), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            // Alert-tinted gradient border
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            alertAccent.opacity(isDark ? 0.35 : 0.3),
                            DS.Adaptive.divider,
                            DS.Adaptive.divider
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        // Alert accent bar on left edge
        .overlay(alignment: .leading) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            alertAccent.opacity(isDark ? 0.8 : 0.7),
                            BrandColors.alertAccent.opacity(isDark ? 0.6 : 0.5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 12)
        }
        // Swipe down to dismiss
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height * 0.6
                    }
                }
                .onEnded { value in
                    if value.translation.height > 60 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 300
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            onDismiss()
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

struct AITabView: View {
    // All stored conversations
    @State private var conversations: [Conversation] = []
    // Which conversation is currently active
    @State private var activeConversationID: UUID? = nil
    
    // Controls whether the history sheet is shown
    @State private var showHistory = false
    
    // Use shared ChatViewModel
    @EnvironmentObject var chatVM: ChatViewModel
    // Portfolio data for AI context
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    // Whether the AI is "thinking" (processing a request)
    @State private var isThinking: Bool = false
    
    // Track which tool is currently executing (for UI indicator)
    // Values: "web_search", "read_url", or nil
    @State private var activeToolName: String? = nil
    
    // Track the active AI request task for cancellation support
    @State private var activeAITask: Task<Void, Never>? = nil
    
    // Subscription management for prompt limits
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var authManager = AuthenticationManager.shared
    @State private var showPromptLimitView: Bool = false
    
    @AppStorage("csai_show_prompt_bar") private var showPromptBar: Bool = true
    @AppStorage("csai_use_personalized_prompts") private var usePersonalizedPrompts: Bool = false
    @State private var isFetchingPersonalized: Bool = false
    @State private var toastMessage: String? = nil
    @State private var showScrollHint: Bool = true
    @State private var hasShownLongConvoHint: Bool = false
    @State private var isInputFocused: Bool = false
    @State private var restorePromptBarAfterKeyboard: Bool = false
    @State private var hasHandledInitialKeyboardFocus: Bool = false
    
    // Track if initial scroll to bottom has been performed (prevents redundant scrolling on re-renders)
    @State private var hasPerformedInitialScroll: Bool = false
    
    // LOADING FIX: Track when conversations are loading to prevent UI flash
    @State private var isLoadingConversations: Bool = true
    // PERFORMANCE FIX: Track initial load to skip redundant work on tab switches
    @State private var didInitialLoad: Bool = false

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var pendingImages: [Data] = []
    @State private var topSafeInset: CGFloat = 0
    @State private var bottomSafeInset: CGFloat = 0
    @State private var inputOverlayMeasuredHeight: CGFloat = 0
    private let headerBarHeight: CGFloat = 52
    private let tabBarHeight: CGFloat = 64
    private let headerDrop: CGFloat = 16 // how far below the very top the header sits
    private var headerHeight: CGFloat { topSafeInset + headerBarHeight }
    
    // Track if this tab is active (visible)
    @State private var isActiveTab: Bool = true
    @EnvironmentObject private var appState: AppState
    
    // Color scheme for adaptive light/dark mode
    @Environment(\.colorScheme) private var colorScheme
    
    // APP LIFECYCLE: Track scene phase to handle app returning from background
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - AI Trade Configuration State
    @State private var detectedTradeConfig: AITradeConfig? = nil
    
    // MARK: - AI Alert Suggestion State
    @State private var detectedAlertSuggestion: AIAlertSuggestion? = nil
    
    // MARK: - AI Bot Configuration State
    @State private var detectedBotConfig: AIBotConfig? = nil
    
    // MARK: - AI Strategy Configuration State
    @State private var detectedStrategyConfig: AIStrategyConfig? = nil
    @State private var showStrategyBuilder: Bool = false
    
    // Reuse a single ephemeral session for all OpenAI calls (reduces connection churn)
    private static let openAISession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    
    // Currently displayed quick replies (populated by SmartPromptService)
    @State private var quickReplies: [String] = []
    
    private let knownTickers: Set<String> = ["BTC","ETH","SOL","LTC","DOGE","RLC","ADA","XRP","BNB","AVAX","DOT","LINK","MATIC","ARB","OP","ATOM","NEAR","FTM","SUI","APT"]
    
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private let promptCount: Int = 3

    private let bottomAnchorID = "chat_bottom_anchor"
    
    // Heights for bottom components
    private let inputBarHeight: CGFloat = 56
    private let promptBarHeightExpanded: CGFloat = 42
    private let promptHandleHeight: CGFloat = 14
    private let minimalBottomReserve: CGFloat = 4

    private var hasFloatingSuggestionCard: Bool {
        detectedTradeConfig != nil ||
        detectedAlertSuggestion != nil ||
        detectedBotConfig != nil ||
        detectedStrategyConfig != nil
    }

    /// Keep only a tiny trailing reserve and let safeAreaInset handle overlay spacing.
    private var chatBottomReserveHeight: CGFloat {
        let baselineOverlayHeight = inputBarHeight + (showPromptBar ? promptBarHeightExpanded : promptHandleHeight)
        let extraOverlay = max(0, inputOverlayMeasuredHeight - baselineOverlayHeight)
        let dynamicReserve = min(10, extraOverlay * 0.08)
        return minimalBottomReserve + dynamicReserve
    }
    
    // Computed: returns messages for the active conversation.
    private var currentMessages: [ChatMessage] {
        guard let activeID = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == activeID }) else {
            return []
        }
        return conversations[index].messages
    }
    
    var body: some View {
        ZStack {
            FuturisticBackground()
                .ignoresSafeArea()
            chatBodyView
        }
        .accentColor(.white)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: TopSafeKey.self, value: proxy.safeAreaInsets.top)
                    .preference(key: BottomSafeKey.self, value: proxy.safeAreaInsets.bottom)
            }
        )
        .onPreferenceChange(TopSafeKey.self) { value in
            // PERFORMANCE FIX: Removed DispatchQueue.main.async - the preference key
            // already has throttling, and async queuing was causing multiple updates.
            // Only update if there's a meaningful difference.
            guard abs(value - self.topSafeInset) > 1 else { return }
            self.topSafeInset = value
        }
        .onPreferenceChange(BottomSafeKey.self) { value in
            // PERFORMANCE FIX: Same fix as TopSafeKey
            guard abs(value - self.bottomSafeInset) > 1 else { return }
            self.bottomSafeInset = value
        }
        .onPreferenceChange(InputOverlayHeightKey.self) { value in
            guard value.isFinite else { return }
            guard abs(value - self.inputOverlayMeasuredHeight) > 1 else { return }
            self.inputOverlayMeasuredHeight = value
        }
        .safeAreaInset(edge: .top) {
            ZStack(alignment: .bottomLeading) {
                // Adaptive header bar background - dark in dark mode, light in light mode
                DS.Adaptive.background
                    .ignoresSafeArea(edges: .top)

                HStack(alignment: .center) {
                    // Left control — premium glass treatment
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        showHistory.toggle()
                    } label: {
                        Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 14, weight: .semibold))
                            .contentShape(Capsule())
                            .accessibilityLabel("Open Conversations")
                    }
                    .buttonStyle(
                        PremiumCompactCTAStyle(
                            height: 34,
                            horizontalPadding: 12,
                            cornerRadius: 17,
                            font: .system(size: 14, weight: .semibold)
                        )
                    )

                    Spacer(minLength: 8)

                    // Center title – gets its own column so it won't overlap controls
                    Text(activeConversationTitle())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary.opacity(0.95))
                        .lineLimit(2)
                        .allowsTightening(true)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer(minLength: 8)

                    // Invisible ghost button to balance width on the right
                    Button(action: {}) {
                        Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DS.Adaptive.textPrimary.opacity(0.92))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(DS.Adaptive.chipBackground)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(DS.Adaptive.stroke, lineWidth: 1)
                            )
                            .contentShape(Capsule())
                    }
                    .opacity(0)
                    .disabled(true)
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .frame(height: headerBarHeight + headerDrop)

                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 0.5)
                    .frame(maxWidth: .infinity)
                    .alignmentGuide(.bottom) { d in d[.bottom] }
            }
            .frame(maxWidth: .infinity)
            .frame(height: headerBarHeight + headerDrop)
        }
        .sheet(isPresented: $showHistory) {
            ConversationHistoryView(
                conversations: conversations,
                onSelectConversation: { convo in
                    // Cancel any ongoing AI request and reset loading state
                    activeAITask?.cancel()
                    activeAITask = nil
                    isThinking = false
                    
                    activeConversationID = convo.id
                    detectedTradeConfig = nil // Clear stale trade config when switching conversations
                    detectedBotConfig = nil // Clear stale bot config when switching conversations
                    detectedStrategyConfig = nil // Clear stale strategy config when switching conversations
                    detectedAlertSuggestion = nil // Clear stale alert suggestion
                    showHistory = false
                    saveConversations()
                },
                onNewChat: {
                    // Cancel any ongoing AI request and reset loading state
                    activeAITask?.cancel()
                    activeAITask = nil
                    isThinking = false
                    AIService.shared.clearHistory() // Clear AI conversation context
                    
                    let newConvo = Conversation(title: "New Chat")
                    conversations.append(newConvo)
                    activeConversationID = newConvo.id
                    detectedTradeConfig = nil // Clear stale trade config for new chat
                    detectedBotConfig = nil // Clear stale bot config for new chat
                    detectedStrategyConfig = nil // Clear stale strategy config for new chat
                    detectedAlertSuggestion = nil // Clear stale alert suggestion
                    showHistory = false
                    saveConversations()
                },
                onDeleteConversation: { convo in
                    if let idx = conversations.firstIndex(where: { $0.id == convo.id }) {
                        // If deleting the active conversation, cancel any ongoing request
                        if convo.id == activeConversationID {
                            activeAITask?.cancel()
                            activeAITask = nil
                            isThinking = false
                            AIService.shared.clearHistory()
                        }
                        
                        conversations.remove(at: idx)
                        if convo.id == activeConversationID {
                            let fallback = conversations.max(by: { ($0.lastMessageDate ?? $0.createdAt) < ($1.lastMessageDate ?? $1.createdAt) })?.id
                            activeConversationID = fallback
                            detectedTradeConfig = nil // Clear stale trade config when active conversation deleted
                            detectedBotConfig = nil // Clear stale bot config when active conversation deleted
                            detectedStrategyConfig = nil // Clear stale strategy config when active conversation deleted
                            detectedAlertSuggestion = nil // Clear stale alert suggestion
                        }
                        saveConversations()
                    }
                },
                onRenameConversation: { convo, newTitle in
                    if let idx = conversations.firstIndex(where: { $0.id == convo.id }) {
                        conversations[idx].title = newTitle.isEmpty ? "New Chat" : newTitle
                        saveConversations()
                    }
                },
                onTogglePin: { convo in
                    if let idx = conversations.firstIndex(where: { $0.id == convo.id }) {
                        conversations[idx].pinned.toggle()
                        saveConversations()
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPromptLimitView) {
            AIPromptLimitView()
        }
        .sheet(isPresented: $showStrategyBuilder) {
            if let config = detectedStrategyConfig {
                StrategyBuilderView(existingStrategy: config.toTradingStrategy())
                    .onDisappear {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            detectedStrategyConfig = nil
                        }
                    }
            }
        }
        .onAppear {
            // Reset lightweight state immediately
            isThinking = false
            activeAITask = nil
            isActiveTab = (appState.selectedTab == .ai)
            
            // On subsequent tab switches, ensure the active conversation is still valid.
            // This handles the case where the user navigated away (e.g., to TradingBotView)
            // and then returned - we need to restore the correct conversation.
            if didInitialLoad {
                // Quick validation: if activeConversationID is nil or doesn't match any
                // loaded conversation, restore from UserDefaults
                if activeConversationID == nil || !conversations.contains(where: { $0.id == activeConversationID }) {
                    if let idString = UserDefaults.standard.string(forKey: lastActiveKey),
                       let uuid = UUID(uuidString: idString),
                       conversations.contains(where: { $0.id == uuid }) {
                        activeConversationID = uuid
                    } else if let mostRecent = conversations.max(by: { ($0.lastMessageDate ?? $0.createdAt) < ($1.lastMessageDate ?? $1.createdAt) }) {
                        activeConversationID = mostRecent.id
                    }
                }
                return
            }
            didInitialLoad = true
            
            // Load conversations synchronously (from cache) - only on first load
            loadConversations()
            
            // Create initial conversation if none exist
            if conversations.isEmpty {
                let initialConvo = Conversation(title: "New Chat")
                conversations.append(initialConvo)
                activeConversationID = initialConvo.id
                saveConversations()
            }
            // Restore last active conversation if available
            else if let idString = UserDefaults.standard.string(forKey: lastActiveKey),
               let uuid = UUID(uuidString: idString),
               conversations.contains(where: { $0.id == uuid }) {
                activeConversationID = uuid
            } else if activeConversationID == nil {
                // Fallback: pick the most recently active conversation
                if let mostRecent = conversations.max(by: { ($0.lastMessageDate ?? $0.createdAt) < ($1.lastMessageDate ?? $1.createdAt) }) {
                    activeConversationID = mostRecent.id
                }
            }
            
            randomizePrompts()
            
            // Mark loading complete after all state is set
            isLoadingConversations = false
        }
        .onDisappear {
            // Defer state modification to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                isActiveTab = false  // view is off-screen; stop local activity
            }
        }
        .onChange(of: activeConversationID) { _, _ in
            // Safety: ensure loading state is always reset when conversation changes
            // This catches any edge cases not handled by specific handlers
            if isThinking {
                activeAITask?.cancel()
                activeAITask = nil
                isThinking = false
            }
            // Clear any stale suggestions
            detectedTradeConfig = nil
            detectedBotConfig = nil
            detectedStrategyConfig = nil
            detectedAlertSuggestion = nil
            // Reset the long conversation hint for the new/switched conversation
            hasShownLongConvoHint = false
        }
        .onChange(of: isInputFocused) { _, focused in
            if focused && showPromptBar {
                restorePromptBarAfterKeyboard = true
                if !hasHandledInitialKeyboardFocus {
                    // First keyboard bring-up: avoid dual animations that can briefly deform input corners.
                    hasHandledInitialKeyboardFocus = true
                    var transaction = SwiftUI.Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showPromptBar = false
                    }
                } else {
                    smoothTogglePromptBar(show: false)
                }
            } else if !focused && restorePromptBarAfterKeyboard {
                restorePromptBarAfterKeyboard = false
                smoothTogglePromptBar(show: true)
            }
        }
        .onChange(of: appState.selectedTab) { _, tab in
            DispatchQueue.main.async { isActiveTab = (tab == .ai) }
        }
        .onChange(of: authManager.currentUser?.id) { _, _ in
            reloadConversationsForCurrentUserScope()
        }
        // APP LIFECYCLE FIX: Handle returning from background
        // Only refresh prompts, don't reset scroll state (causes jitter)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && isActiveTab {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // SCROLL FIX: Don't reset hasPerformedInitialScroll - it causes
                    // unwanted scroll jumps when returning from background
                    // The scroll position is preserved by iOS automatically
                    
                    // Only refresh quick replies if empty
                    if quickReplies.isEmpty {
                        randomizePrompts()
                    }
                }
            }
        }
    }
}

// MARK: - Subviews & Helpers
extension AITabView {
    private var chatBodyView: some View {
        ZStack(alignment: .top) {
            chatScrollView
            toastOverlay
                .padding(.top, 60) // Position toast below navigation bar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputBarOverlay
        }
    }
    
    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            scrollViewWithSuggestionHandlers(proxy: proxy)
        }
    }

    private func baseChatMessagesList(proxy: ScrollViewProxy) -> some View {
        chatMessagesList
            // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + KVO tracking
            .withUIKitScrollBridge()
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                UIApplication.shared.dismissKeyboard()
            }
    }

    private func scrollViewWithCoreHandlers(proxy: ScrollViewProxy) -> AnyView {
        AnyView(
            baseChatMessagesList(proxy: proxy)
            // SCROLL FIX: Ensure scroll is at bottom when loading completes
            .onChange(of: isLoadingConversations) { _, loading in
                if !loading && !hasPerformedInitialScroll {
                    hasPerformedInitialScroll = true
                    // Use transaction to disable animation for immediate scroll
                    var transaction = SwiftUI.Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        guard activeConversationID != nil else { return }
                        // Scroll to last message if available, otherwise bottom anchor
                        if let lastMsg = currentMessages.last {
                            proxy.scrollTo(lastMsg.id, anchor: .bottom)
                        } else {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: currentMessages.count) { oldCount, newCount in
                // SCROLL FIX: Only handle message count changes after initial load
                guard !isLoadingConversations else { return }
                handleMessagesCountChange(proxy: proxy, oldCount: oldCount, newCount: newCount)
            }
            .onChange(of: activeConversationID) { _, _ in
                handleConversationChange(proxy: proxy)
            }
            .onChange(of: isThinking) { _, thinking in
                handleThinkingChange(thinking: thinking, proxy: proxy)
            }
            .onChange(of: currentMessages.last?.text.count ?? 0) { _, newCount in
                handleStreamingScroll(newCount: newCount, proxy: proxy)
            }
            .onChange(of: currentMessages.last?.isStreaming ?? false) { _, isStreaming in
                if !isStreaming {
                    finalizeScrollToBottom(proxy: proxy)
                }
            }
            // SCROLL FIX: When tool indicator clears and text starts, scroll to show AI response
            .onChange(of: activeToolName) { _, toolName in
                if toolName == nil {
                    // Tool finished, text should be flowing - scroll to AI message
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let lastMsg = currentMessages.last, lastMsg.sender == "ai" {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastMsg.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        )
    }

    private func scrollViewWithSuggestionHandlers(proxy: ScrollViewProxy) -> AnyView {
        AnyView(
            scrollViewWithCoreHandlers(proxy: proxy)
            // SCROLL FIX: Scroll to bottom when alert/trade/bot suggestion cards appear
            // This ensures the user can see the full AI response before the floating cards
            .onChange(of: detectedAlertSuggestion) { _, suggestion in
                handleSuggestionCardStateChange(proxy: proxy, isPresenting: suggestion != nil)
            }
            .onChange(of: detectedTradeConfig) { _, config in
                handleSuggestionCardStateChange(proxy: proxy, isPresenting: config != nil)
            }
            .onChange(of: detectedBotConfig) { _, config in
                handleSuggestionCardStateChange(proxy: proxy, isPresenting: config != nil)
            }
            .onChange(of: detectedStrategyConfig != nil) { _, isPresenting in
                handleSuggestionCardStateChange(proxy: proxy, isPresenting: isPresenting)
            }
        )
    }
    
    private var chatMessagesList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                Color.clear.frame(height: 12)
                
                // BLANK SCREEN FIX: Properly handle all states to prevent blank screens
                // Priority: loading > messages > thinking-only > empty welcome
                if isLoadingConversations {
                    // Initial load state - show nothing to prevent flash
                    Color.clear.frame(height: 1)
                } else if !currentMessages.isEmpty {
                    // Has messages - show them
                    // Long conversation hint - shown once when conversation exceeds threshold
                    if currentMessages.count >= 40 && !hasShownLongConvoHint {
                        LongConversationHint(onStartNewChat: {
                            startNewChatFromHint()
                        }, onDismiss: {
                            hasShownLongConvoHint = true
                        })
                        .id("long_convo_hint")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    ForEach(currentMessages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    }
                } else if isThinking {
                    // BLANK SCREEN FIX: If thinking but no messages yet, show a minimal waiting state
                    // This prevents the blank screen when quick reply is tapped on empty chat
                    VStack(spacing: 12) {
                        Spacer().frame(height: 40)
                        Text("Processing your request...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                } else {
                    // Welcome state for empty/new conversations (only when not thinking)
                    welcomeEmptyState
                }
                
                // Show tool execution indicator or generic thinking bubble
                if let toolName = activeToolName {
                    ToolExecutionBubble(toolName: toolName)
                        .id("tool_indicator_\(toolName)")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9)),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        ))
                } else if isThinking {
                    ThinkingBubble()
                        .id("thinking_indicator")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9)),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        ))
                }
                // Dynamic bottom reserve keeps final message/timestamp fully visible above input overlay.
                Color.clear
                    .frame(height: chatBottomReserveHeight)
                    .id(bottomAnchorID)
            }
            .animation(.easeOut(duration: 0.2), value: isThinking)
            // ANIMATION FIX: Only animate message count changes after initial load
            .animation(isLoadingConversations ? nil : .easeOut(duration: 0.15), value: currentMessages.count)
        }
        // SCROLL FIX: iOS 17+ - Start scroll at bottom by default
        // This ensures messages appear already scrolled to bottom, no visible scroll animation
        .defaultScrollAnchor(.bottom)
    }
    
    // MARK: - Welcome Empty State
    private var welcomeEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 60)
            
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandGold.light, BrandGold.dark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("How can I help you today?")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Ask me anything about crypto markets, trading strategies, or portfolio analysis.")
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
    
    /// Start a new chat from the long conversation hint
    private func startNewChatFromHint() {
        // Cancel any ongoing AI request and reset loading state
        activeAITask?.cancel()
        activeAITask = nil
        isThinking = false
        AIService.shared.clearHistory() // Clear AI conversation context
        
        let newConvo = Conversation(title: "New Chat")
        conversations.append(newConvo)
        activeConversationID = newConvo.id
        detectedTradeConfig = nil
        detectedBotConfig = nil
        detectedStrategyConfig = nil
        detectedAlertSuggestion = nil
        hasShownLongConvoHint = false // Reset for the new conversation
        saveConversations()
    }
    
    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = toastMessage {
            toastView(toast)
                .zIndex(100) // Ensure toast appears above all other content
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toastMessage != nil)
        }
    }
    
    // MARK: - Scroll Handlers
    private func handleMessagesCountChange(proxy: ScrollViewProxy, oldCount: Int, newCount: Int) {
        // SCROLL FIX: Skip if this is initial load (oldCount was 0 and we just loaded)
        // Initial scroll is handled by onChange(of: isLoadingConversations)
        guard oldCount > 0 || newCount == 1 else { return }
        
        guard let lastMsg = currentMessages.last else { return }
        // Only auto-scroll for user messages (to show what they sent)
        // AI messages are handled by streaming scroll to avoid overshoot
        if lastMsg.sender == "user" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastMsg.id, anchor: .bottom)
                }
            }
        }
    }
    
    private func handleConversationChange(proxy: ScrollViewProxy) {
        // SCROLL FIX: Skip during initial load - handled by isLoadingConversations onChange
        guard !isLoadingConversations else { return }
        
        // SCROLL FIX: Use immediate scroll with disabled animations for conversation switch
        // This prevents visible scroll animation when switching chats
        var transaction = SwiftUI.Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            // Scroll to last message if available for more reliable positioning
            if let lastMsg = currentMessages.last {
                proxy.scrollTo(lastMsg.id, anchor: .bottom)
            } else {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }
    
    private func handleThinkingChange(thinking: Bool, proxy: ScrollViewProxy) {
        if thinking {
            // Scroll to show thinking indicator when AI starts processing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("thinking_indicator", anchor: .bottom)
                }
            }
        } else {
            finalizeScrollToBottom(proxy: proxy)
        }
    }
    
    private func handleStreamingScroll(newCount: Int, proxy: ScrollViewProxy) {
        guard let lastMsg = currentMessages.last, lastMsg.sender == "ai" else { return }
        
        // SCROLL FIX: Much more responsive streaming scroll
        // - Always scroll on first 30 chars (ensure initial response is visible)
        // - Scroll every ~10 chars after that for smooth tracking
        // - This ensures the latest text is always visible as it streams
        let shouldScroll = newCount < 30 || newCount % 10 < 2
        guard shouldScroll else { return }
        
        // Use transaction to disable animations for smooth, non-jumpy scrolling
        var trans = SwiftUI.Transaction()
        trans.disablesAnimations = true
        withTransaction(trans) {
            // Scroll to the last message to keep it visible
            // Using .bottom anchor positions the view so the bottom of the message is visible
            proxy.scrollTo(lastMsg.id, anchor: .bottom)
        }
    }
    
    /// Scroll to show the last message when suggestion cards (alert, trade, bot) appear
    /// This ensures users can see the complete AI response before the floating action cards
    private func handleSuggestionCardAppeared(proxy: ScrollViewProxy) {
        // Small delay to let the card animate in and then force bottom alignment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            finalizeScrollToBottom(proxy: proxy)
        }
    }
    
    private func handleSuggestionCardStateChange(proxy: ScrollViewProxy, isPresenting: Bool) {
        if isPresenting {
            handleSuggestionCardAppeared(proxy: proxy)
        } else {
            // Snap again when cards dismiss so we do not leave dead space under the last message.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                finalizeScrollToBottom(proxy: proxy)
            }
        }
    }

    /// Ensure chat ends fully at the bottom after streaming finishes or cards appear.
    private func finalizeScrollToBottom(proxy: ScrollViewProxy) {
        let delays: [Double] = [0.0, 0.12, 0.28]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                var trans = SwiftUI.Transaction()
                trans.disablesAnimations = true
                withTransaction(trans) {
                    if let lastMsg = currentMessages.last {
                        proxy.scrollTo(lastMsg.id, anchor: .bottom)
                    } else {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Input Bar Overlay
    private var inputBarOverlay: some View {
        VStack(spacing: 4) {
            // AI Prompt Limit Banner - shows when near or at limit
            AIPromptLimitBanner()
                .padding(.horizontal, 16)
            
            // Floating trade button - appears when AI generates a trade config
            if let config = detectedTradeConfig {
                ExecuteTradeButton(config: config, onExecute: {
                    // Navigate to Trading tab with the trade config
                    appState.navigateToTrade(with: config)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        detectedTradeConfig = nil
                    }
                }, onDismiss: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        detectedTradeConfig = nil
                    }
                })
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }
            
            // Floating alert suggestion card - appears when AI suggests creating an alert
            if let suggestion = detectedAlertSuggestion {
                CreateAlertCard(
                    suggestion: suggestion,
                    onConfirm: {
                        // Create the alert
                        createAlertFromSuggestion(suggestion)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            detectedAlertSuggestion = nil
                        }
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            detectedAlertSuggestion = nil
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }
            
            // Floating bot creation button - appears when AI generates a bot config
            if let botConfig = detectedBotConfig {
                CreateBotButton(config: botConfig, onExecute: {
                    // Navigate to bot creation with the config
                    appState.navigateToBotCreation(with: botConfig)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        detectedBotConfig = nil
                    }
                }, onDismiss: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        detectedBotConfig = nil
                    }
                })
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }
            
            // Floating strategy review button - appears when AI generates a strategy config
            if let strategyConfig = detectedStrategyConfig {
                ReviewStrategyButton(config: strategyConfig, onReview: {
                    showStrategyBuilder = true
                }, onDismiss: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        detectedStrategyConfig = nil
                    }
                })
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                    removal: .scale(scale: 0.95).combined(with: .opacity)
                ))
            }
            
            // Remaining prompts indicator (only show for non-premium tiers)
            if subscriptionManager.currentTier != .premium && !subscriptionManager.isDeveloperMode {
                remainingPromptsIndicator
            }
            
            // VISUAL FIX: Use conditional rendering instead of ZStack with opacity
            // This prevents both views from being rendered simultaneously, avoiding
            // the gold bubble flash that occurred on tab switch
            Group {
                if showPromptBar {
                    quickReplyBar()
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                } else {
                    collapsedPromptHandle()
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                }
            }
            .frame(height: showPromptBar ? promptBarHeightExpanded : promptHandleHeight)
            .animation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0), value: showPromptBar)

            inputBar()
                .frame(height: inputBarHeight)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 2)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: InputOverlayHeightKey.self, value: proxy.size.height)
            }
        )
        .padding(.bottom, 20)  // More breathing room from tab bar
        .frame(maxWidth: .infinity)
        .background(DS.Adaptive.background)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: detectedTradeConfig != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: detectedAlertSuggestion != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: detectedBotConfig != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: detectedStrategyConfig != nil)
        .overlay(alignment: .top) {
            // Subtle top separator line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, BrandGold.light.opacity(0.12), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            // Bottom separator above tab bar
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(height: 0.5)
        }
    }
    
    // MARK: - Remaining Prompts Indicator
    private var remainingPromptsIndicator: some View {
        let remaining = subscriptionManager.remainingAIPrompts
        let isLow = remaining <= 1 && remaining > 0
        let isEmpty = remaining == 0
        
        // Don't show indicator if limit sheet is already visible (avoid redundancy)
        if showPromptLimitView {
            return AnyView(EmptyView())
        }
        
        // Show prominent banner when limit reached
        if isEmpty {
            return AnyView(
                Button {
                    showPromptLimitView = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        
                        Text("Daily limit reached")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text("Upgrade")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(
                        PremiumCompactCTAStyle(
                            height: 28,
                            horizontalPadding: 10,
                            cornerRadius: 14,
                            font: .system(size: 11, weight: .bold)
                        )
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.orange.opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.orange.opacity(colorScheme == .dark ? 0.3 : 0.18), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            )
        }
        
        // Normal pill indicator when prompts available
        return AnyView(
            HStack(spacing: 6) {
                Image(systemName: "message.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isLow ? .orange : BrandGold.light)
                
                Text("\(remaining) left today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isLow ? .orange : DS.Adaptive.textSecondary)
                
                if subscriptionManager.currentTier == .free {
                    Button {
                        showPromptLimitView = true
                    } label: {
                        Text("Upgrade")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(
                        PremiumCompactCTAStyle(
                            height: 24,
                            horizontalPadding: 8,
                            cornerRadius: 12,
                            font: .system(size: 10, weight: .bold)
                        )
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .stroke(isLow ? Color.orange.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        )
    }
    
    private func activeConversationTitle() -> String {
        guard let activeID = activeConversationID,
              let convo = conversations.first(where: { $0.id == activeID }) else {
            return "AI Chat"
        }
        return convo.title
    }
    
    private func quickReplyBar() -> some View {
        // Adaptive opacity for light/dark mode - stronger in dark mode for visibility
        let isDark = colorScheme == .dark
        let chipBgOpacity: Double = isDark ? 0.28 : 1.0
        let buttonBgOpacity: Double = isDark ? 0.3 : 1.0
        let strokeOpacity: Double = isDark ? 0.55 : 0.35
        let buttonStrokeOpacity: Double = isDark ? 0.45 : 0.25
        
        // LIGHT MODE FIX: Use warm amber gradient in light mode instead of saturated gold
        let chipGradient: LinearGradient = isDark
            ? BrandGold.horizontalGradient
            : LinearGradient(colors: [Color(red: 0.96, green: 0.88, blue: 0.65), Color(red: 0.92, green: 0.82, blue: 0.52)], startPoint: .leading, endPoint: .trailing)
        
        // LIGHT MODE FIX: Adaptive icon color for control buttons
        let controlIconColor: Color = isDark ? .black.opacity(0.7) : Color(red: 0.45, green: 0.33, blue: 0.05)
        
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Suggestion chips - adaptive styling for light/dark with press feedback
                ForEach(Array(quickReplies.enumerated()), id: \.offset) { (_, reply) in
                    QuickReplyChip(
                        text: reply,
                        chipGradient: chipGradient,
                        chipBgOpacity: chipBgOpacity,
                        strokeOpacity: strokeOpacity,
                        isDark: isDark,
                        isDisabled: isThinking,
                        onTap: { handleQuickReply(reply) }
                    )
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }

                // Trailing controls - refresh and hide
                HStack(spacing: 6) {
                    // Refresh button - using onTapGesture for reliable tap handling
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(controlIconColor)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(chipGradient)
                                .opacity(buttonBgOpacity)
                        )
                        .overlay(
                            Circle()
                                .stroke(isDark ? BrandGold.light.opacity(buttonStrokeOpacity) : Color(red: 0.80, green: 0.65, blue: 0.25).opacity(0.35), lineWidth: isDark ? 1 : 0.5)
                        )
                        .contentShape(Circle())
                        .onTapGesture {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            randomizePrompts()
                        }
                        .accessibilityLabel("Refresh suggestions")
                    
                    // Hide button - using onTapGesture for reliable tap handling
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(controlIconColor)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(chipGradient)
                                .opacity(buttonBgOpacity)
                        )
                        .overlay(
                            Circle()
                                .stroke(isDark ? BrandGold.light.opacity(buttonStrokeOpacity) : Color(red: 0.80, green: 0.65, blue: 0.25).opacity(0.35), lineWidth: isDark ? 1 : 0.5)
                        )
                        .contentShape(Circle())
                        .onTapGesture {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            smoothTogglePromptBar(show: false)
                        }
                        .accessibilityLabel("Hide suggestions bar")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.chipBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .trailing) {
            LinearGradient(colors: [Color.clear, DS.Adaptive.background.opacity(0.9)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 36)
                .opacity(showScrollHint ? 1 : 0)
                .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.88, blendDuration: 0.2), value: quickReplies)
        // Double-tap to refresh - use simultaneousGesture so it doesn't block buttons
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    randomizePrompts()
                }
        )
        // Swipe down to hide - higher minimumDistance to avoid stealing from horizontal scroll
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    let vertical = value.translation.height
                    let horizontal = abs(value.translation.width)
                    // Dismiss scroll hint on clear horizontal swipe
                    if horizontal > vertical + 10 {
                        withAnimation(.easeInOut(duration: 0.2)) { showScrollHint = false }
                    }
                    // Only hide on a clearly vertical downward swipe (not horizontal scroll)
                    if vertical > 25 && vertical > horizontal * 1.5 {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        #endif
                        smoothTogglePromptBar(show: false)
                    }
                }
        )
        // Long-press context menu
        .contextMenu {
            Button {
                randomizePrompts()
            } label: { Label("Refresh Suggestions", systemImage: "arrow.clockwise") }

            Button {
                smoothTogglePromptBar(show: false)
            } label: { Label("Hide Suggestions", systemImage: "chevron.down") }
        }
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if showPromptBar { scheduleScrollHintAutoHide() }
            }
        }
        .onChange(of: quickReplies) { _, _ in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if showPromptBar { scheduleScrollHintAutoHide() }
            }
        }
    }
    
    private func collapsedPromptHandle() -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            smoothTogglePromptBar(show: true)
        } label: {
            // Minimal thin gold bar indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [BrandGold.light.opacity(0.4), BrandGold.dark.opacity(0.6), BrandGold.light.opacity(0.4)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .frame(height: 16)
                .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        // Long-press for context menu
        .contextMenu {
            Button {
                smoothTogglePromptBar(show: true)
            } label: { Label("Show Suggestions", systemImage: "chevron.up") }
        }
        // Swipe up to expand
        .gesture(DragGesture(minimumDistance: 10, coordinateSpace: .local).onEnded { value in
            if value.translation.height < -12 {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                #endif
                smoothTogglePromptBar(show: true)
            }
        })
    }
    
    private func smoothTogglePromptBar(show: Bool) {
        let delay = 0.05 // let the context menu dismiss first for a smoother morph
        // Use slightly bouncier animation when expanding for delight
        let anim: Animation = show
            ? .spring(response: 0.38, dampingFraction: 0.72, blendDuration: 0)
            : .spring(response: 0.28, dampingFraction: 0.88, blendDuration: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(anim) {
                self.showPromptBar = show
            }
        }
    }
    
    // PERFORMANCE FIX: Use CGImageSource for efficient memory-mapped downsampling
    // This avoids creating full UIImage in memory and is much faster for large images
    private func downscaleImageData(_ data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,  // Don't cache original - we only need thumbnail
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension),
            kCGImageSourceCreateThumbnailWithTransform: true  // Apply EXIF orientation
        ]
        
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // Fallback to UIImage if CGImageSource fails
            return downscaleImageDataFallback(data, maxDimension: maxDimension, quality: quality)
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: quality)
    }
    
    // Fallback using UIGraphicsImageRenderer (slower, used only if CGImageSource fails)
    private func downscaleImageDataFallback(_ data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let maxSide = max(size.width, size.height)
        let scale = maxSide > maxDimension ? (maxDimension / maxSide) : 1
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let scaled = renderer.jpegData(withCompressionQuality: quality) { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return scaled
    }
    
    private func inputBar() -> some View {
        HStack(spacing: 10) {
            // Photos picker - refined design
            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    Circle()
                        .fill(DS.Adaptive.chipBackground)
                    Image(systemName: "photo.on.rectangle.angled")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .font(.system(size: 16, weight: .medium))
                }
                .frame(width: 36, height: 36)
                .overlay(
                    Circle().stroke(BrandGold.light.opacity(0.25), lineWidth: 1)
                )
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(BrandGold.horizontalGradient)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.black)
                        )
                        .offset(x: 2, y: 2)
                }
                .contentShape(Circle())
            }
            .accessibilityLabel("Attach image")

            // If exactly one image is attached, show a compact chip next to the button
            if pendingImages.count == 1, let ui = UIImage(data: pendingImages[0]) {
                AttachmentChip(image: ui) {
                    pendingImages.removeAll()
                }
            }

            // If more than one image, show the horizontal strip
            if pendingImages.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { idx, data in
                            if let ui = UIImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 34, height: 34)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(BrandGold.light.opacity(0.3), lineWidth: 1))
                                    Button {
                                        pendingImages.remove(at: idx)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.black)
                                            .background(Circle().fill(Color.white))
                                    }
                                    .offset(x: 5, y: -5)
                                }
                            }
                        }
                    }
                }
                .frame(height: 36)
            }

            // Text field - using UIKit-backed ChatTextField for reliable keyboard
            ChatTextField(text: $chatVM.inputText, placeholder: "Ask me anything...")
                .onSubmit {
                    guard !isThinking else { return }
                    let trimmed = chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    self.sendMessage()
                }
                .onEditingChanged { focused in
                    isInputFocused = focused
                }
                .frame(height: 42)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DS.Adaptive.chipBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isInputFocused
                                ? BrandGold.light.opacity(0.6)
                                : (isThinking ? BrandGold.light.opacity(0.4) : DS.Adaptive.stroke.opacity(0.8)),
                            lineWidth: isInputFocused ? 1.5 : 1
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: isThinking)
                .animation(.easeInOut(duration: 0.15), value: isInputFocused)

            // Send / Stop button - dual-purpose with polished styling
            let hasInput = !chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty
            let canSend = !isThinking && hasInput
            let isActive = canSend || isThinking  // Button is actionable when sending OR stopping
            // LIGHT MODE FIX: Deeper amber send button gradient in light mode
            let sendButtonGradient: LinearGradient = colorScheme == .dark
                ? BrandGold.verticalGradient
                : LinearGradient(colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.48, blue: 0.06)], startPoint: .top, endPoint: .bottom)
            let sendIconColor: Color = colorScheme == .dark ? .black : .white.opacity(0.95)
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                if isThinking {
                    // Stop generating - cancel the active AI request
                    activeAITask?.cancel()
                    activeAITask = nil
                    // State cleanup (isThinking, activeToolName) handled by CancellationError catch
                } else if canSend {
                    self.sendMessage()
                }
            } label: {
                Group {
                    if isThinking {
                        // Stop icon when AI is generating
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(sendIconColor)
                    } else {
                        // Send arrow when ready to send
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(sendIconColor)
                    }
                }
                .frame(width: 36, height: 36)
                .background(
                    ZStack {
                        Circle()
                            .fill(sendButtonGradient)
                        // Glass top shine
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(colorScheme == .dark ? 0.18 : 0.30), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [BrandGold.light.opacity(0.5), BrandColors.goldBase.opacity(0.2)]
                                    : [Color(red: 0.78, green: 0.60, blue: 0.10).opacity(0.4), Color(red: 0.78, green: 0.60, blue: 0.10).opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: colorScheme == .dark ? 0.8 : 1
                        )
                )
            }
            .disabled(!isActive)
            .opacity(isActive ? 1 : 0.45)
            .scaleEffect(isActive ? 1 : 0.95)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
            .animation(.easeInOut(duration: 0.15), value: isThinking)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            DS.Adaptive.background
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let processed = downscaleImageData(data) ?? data
                    await MainActor.run {
                        self.pendingImages.append(processed)
                        self.showToast("Added photo. Tap Send to submit.")
                    }
                }
                await MainActor.run {
                    self.selectedPhotoItem = nil
                }
            }
        }
    }
    
    private func maybeAugmentUserInput(_ input: String) async -> String {
        let lowercased = input.lowercased()
        
        // ── 0. DETECT COINS MENTIONED (for DeepSeek consultation) ──
        let detectedCoins = detectCoinsInQuery(lowercased)
        
        // ── 1. PREDICTION / FORECAST DETECTION ──
        // If the user asks for a prediction, forecast, or trade opinion on a specific coin,
        // proactively fetch the CryptoSage AI prediction and include it in context.
        // This gives the chat model the best analytical data from our prediction engine.
        let predictionKeywords = ["predict", "forecast", "prediction", "outlook", "target price",
                                   "where do you think", "where will", "price target", "gonna go",
                                   "going to go", "moon", "dump", "crash", "pump", "rally"]
        let isPredictionQuery = predictionKeywords.contains { lowercased.contains($0) }
        
        if isPredictionQuery {
            // Fetch prediction + DeepSeek consultation in parallel
            async let predictionFuture = fetchDeepSeekPredictionForChat(query: lowercased)
            async let consultationFuture = fetchDeepSeekConsultation(query: input, coins: detectedCoins)
            
            let predictionContext = await predictionFuture
            let consultationContext = await consultationFuture
            
            if !predictionContext.isEmpty || !consultationContext.isEmpty {
                let marketSummary = AIContextBuilder.shared.getMarketSummary()
                let sentimentSummary = await buildQuickSentimentContext()
                var context = ""
                if !predictionContext.isEmpty {
                    context += "[CRYPTOSAGE AI PREDICTION DATA (from our dedicated crypto prediction engine):\n\(predictionContext)]"
                }
                if !consultationContext.isEmpty {
                    context += "\n[DEEPSEEK CONSULTATION (second AI opinion from our crypto specialist):\n\(consultationContext)]"
                }
                if !sentimentSummary.isEmpty { context += "\n[SENTIMENT: \(sentimentSummary)]" }
                if !marketSummary.isEmpty { context += "\n[MARKET: \(marketSummary)]" }
                return "\(input)\n\n\(context)\n\nIMPORTANT: Base your response on the CryptoSage AI prediction data and DeepSeek consultation above. Present the prediction naturally, reference specific data points (direction, confidence, drivers, price range). If the DeepSeek consultation provides additional insights (key levels, risks, suggested actions), weave those into your analysis. Note where the prediction engine and DeepSeek agree or disagree. Always remind the user this is not financial advice."
            }
        }
        
        // ── 2. TRADING ADVICE DETECTION ──
        let tradingKeywords = ["buy", "sell", "should i", "invest", "trade", "hold", "rebalance", "allocation", "diversif"]
        let isTradingQuery = tradingKeywords.contains { lowercased.contains($0) }
        
        if isTradingQuery {
            // Fetch prediction + DeepSeek consultation + portfolio context in parallel
            async let predictionFuture = fetchDeepSeekPredictionForChat(query: lowercased)
            async let consultationFuture = fetchDeepSeekConsultation(query: input, coins: detectedCoins)
            
            let predictionContext = await predictionFuture
            let consultationContext = await consultationFuture
            
            // Inject portfolio summary for personalized advice
            let portfolioSummary = await buildQuickPortfolioContext()
            let marketSummary = AIContextBuilder.shared.getMarketSummary()
            let sentimentSummary = await buildQuickSentimentContext()
            let pairPreferences = await buildQuickTradingPairPreferences()
            
            var context = "[YOUR PORTFOLIO: \(portfolioSummary)]"
            if !predictionContext.isEmpty {
                context += "\n[DEEPSEEK AI PREDICTION: \(predictionContext)]"
            }
            if !consultationContext.isEmpty {
                context += "\n[DEEPSEEK CONSULTATION (second AI opinion from our crypto specialist):\n\(consultationContext)]"
            }
            if !sentimentSummary.isEmpty {
                context += "\n[SENTIMENT: \(sentimentSummary)]"
            }
            if !marketSummary.isEmpty {
                context += "\n[MARKET: \(marketSummary)]"
            }
            if !pairPreferences.isEmpty {
                context += "\n[PAIR PREFERENCES: \(pairPreferences)]"
            }
            return "\(input)\n\n\(context)\n\nIMPORTANT: Base your advice on MY specific portfolio, market sentiment, and trading pair preferences above. Reference my actual holdings, allocations, P/L, factor in the Fear/Greed index, and use my preferred pairs/exchanges when suggesting trades.\(predictionContext.isEmpty && consultationContext.isEmpty ? "" : " Synthesize the CryptoSage AI prediction and DeepSeek consultation data — note where both AIs agree (high-confidence signal) or disagree (mention the uncertainty). Present a unified, well-reasoned recommendation.")"
        }
        
        // ── 3. FINANCIAL / ANALYSIS QUERY DETECTION (broader DeepSeek consultation) ──
        // For queries that mention coins + financial concepts but didn't match prediction/trading keywords
        let financialKeywords = ["support", "resistance", "entry", "exit", "dip", "risk",
                                  "hedge", "stop loss", "take profit", "leverage", "margin",
                                  "technical", "chart", "pattern", "breakout", "breakdown",
                                  "accumulate", "dca", "long term", "short term",
                                  "what do you think", "good time", "bad time", "opportunity",
                                  "safe", "danger", "worry", "concern", "bottom", "top"]
        let isFinancialQuery = financialKeywords.contains { lowercased.contains($0) }
        
        if isFinancialQuery && !detectedCoins.isEmpty {
            let consultationContext = await fetchDeepSeekConsultation(query: input, coins: detectedCoins)
            let marketSummary = AIContextBuilder.shared.getMarketSummary()
            
            if !consultationContext.isEmpty {
                var context = "[DEEPSEEK CONSULTATION (second AI opinion from our crypto specialist):\n\(consultationContext)]"
                if !marketSummary.isEmpty { context += "\n[MARKET: \(marketSummary)]" }
                return "\(input)\n\n\(context)\n\nIMPORTANT: Incorporate the DeepSeek consultation data into your response. Reference specific data points like key levels, risks, and suggested actions. Present a synthesized analysis combining your reasoning with DeepSeek's crypto expertise. Always remind the user this is not financial advice."
            }
        }
        
        // ── 4. MARKET QUERY DETECTION ──
        let marketKeywords = ["price", "worth", "value", "market", "btc", "eth", "bitcoin", "ethereum", "coin"]
        let isMarketQuery = marketKeywords.contains { lowercased.contains($0) }
        
        if isMarketQuery {
            let marketSummary = AIContextBuilder.shared.getMarketSummary()
            if !marketSummary.isEmpty {
                return "\(input)\n\n[Current Market: \(marketSummary)]"
            }
        }
        
        return input
    }
    
    // MARK: - DeepSeek Multi-AI Consultation
    
    /// Consult DeepSeek for a second opinion on the user's financial query.
    /// Runs in parallel with other context-building tasks.
    /// Returns empty string if consultation fails or is not applicable.
    private func fetchDeepSeekConsultation(query: String, coins: [(symbol: String, name: String)]) async -> String {
        // Only consult if we have coins to analyze and Firebase is available
        guard !coins.isEmpty, FirebaseService.shared.useFirebaseForAI else { return "" }
        
        // Build coin data for the Firebase function
        let coinData: [[String: Any]] = coins.prefix(3).map { coin in
            var data: [String: Any] = [
                "symbol": coin.symbol,
                "name": coin.name
            ]
            // Try to include current price/change from market data if available
            if case .success(let allCoins) = MarketViewModel.shared.state,
               let marketCoin = allCoins.first(where: { $0.symbol.uppercased() == coin.symbol.uppercased() }) {
                data["price"] = marketCoin.priceUsd ?? 0
                data["change24h"] = marketCoin.priceChangePercentage24hInCurrency ?? 0
            }
            return data
        }
        
        // Build compact market context
        let marketContext = AIContextBuilder.shared.getMarketSummary()
        
        // Call DeepSeek consultation with a 5-second timeout
        // Use a task group so we can race against a timeout
        do {
            let response: DeepSeekConsultationResponse? = try await withThrowingTaskGroup(of: DeepSeekConsultationResponse?.self) { group in
                group.addTask {
                    await FirebaseService.shared.consultDeepSeek(
                        query: query,
                        coins: coinData,
                        marketContext: marketContext
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                    return nil // Timeout sentinel
                }
                // Take the first result
                if let first = try await group.next() {
                    group.cancelAll()
                    return first
                }
                return nil
            }
            
            guard let consultation = response?.consultation else { return "" }
            
            // Format the consultation into a concise context string
            return formatDeepSeekConsultation(consultation, coins: coins)
        } catch {
            #if DEBUG
            print("[Chat-DeepSeek] Consultation timeout or error: \(error.localizedDescription)")
            #endif
            return ""
        }
    }
    
    /// Format a DeepSeek consultation into a concise context string for the chat system prompt.
    private func formatDeepSeekConsultation(_ consultation: DeepSeekConsultation, coins: [(symbol: String, name: String)]) -> String {
        var lines: [String] = []
        
        let coinNames = coins.map { "\($0.name) (\($0.symbol))" }.joined(separator: ", ")
        lines.append("DeepSeek Analysis for \(coinNames):")
        
        if let direction = consultation.direction {
            lines.append("Direction: \(direction.uppercased())")
        }
        if let confidence = consultation.confidence {
            lines.append("Confidence: \(confidence)%")
        }
        if let shortTerm = consultation.shortTermOutlook, !shortTerm.isEmpty {
            lines.append("Short-term (24-48h): \(shortTerm)")
        }
        if let mediumTerm = consultation.mediumTermOutlook, !mediumTerm.isEmpty {
            lines.append("Medium-term (1-2wk): \(mediumTerm)")
        }
        if let levels = consultation.keyLevels {
            if let supports = levels.support, !supports.isEmpty {
                let supportStr = supports.map { "$\(formatCompactPrice($0))" }.joined(separator: ", ")
                lines.append("Support Levels: \(supportStr)")
            }
            if let resistances = levels.resistance, !resistances.isEmpty {
                let resistanceStr = resistances.map { "$\(formatCompactPrice($0))" }.joined(separator: ", ")
                lines.append("Resistance Levels: \(resistanceStr)")
            }
        }
        if let risks = consultation.risks, !risks.isEmpty {
            lines.append("Key Risks: \(risks.joined(separator: "; "))")
        }
        if let reasoning = consultation.reasoning, !reasoning.isEmpty {
            lines.append("Analysis: \(reasoning)")
        }
        if let action = consultation.suggestedAction, !action.isEmpty {
            lines.append("Suggested Action: \(action)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Format a price compactly (e.g., 98245.50 -> "98,245.50")
    // PERFORMANCE FIX: Reuse cached formatters for common precision tiers
    private static let _compactPrice6: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .decimal; nf.maximumFractionDigits = 6; return nf
    }()
    private static let _compactPrice2: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .decimal; nf.maximumFractionDigits = 2; return nf
    }()
    private static let _compactPrice0: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .decimal; nf.maximumFractionDigits = 0; return nf
    }()
    private func formatCompactPrice(_ price: Double) -> String {
        let formatter = price < 1 ? Self._compactPrice6 : (price < 100 ? Self._compactPrice2 : Self._compactPrice0)
        return formatter.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)
    }
    
    /// Detect coins mentioned in a query string. Returns (symbol, name) pairs.
    private func detectCoinsInQuery(_ query: String) -> [(symbol: String, name: String)] {
        let coinMappings: [(keywords: [String], symbol: String, name: String)] = [
            (["bitcoin", "btc"], "BTC", "Bitcoin"),
            (["ethereum", "eth"], "ETH", "Ethereum"),
            (["solana", "sol"], "SOL", "Solana"),
            (["cardano", "ada"], "ADA", "Cardano"),
            (["xrp", "ripple"], "XRP", "XRP"),
            (["dogecoin", "doge"], "DOGE", "Dogecoin"),
            (["polkadot", "dot"], "DOT", "Polkadot"),
            (["avalanche", "avax"], "AVAX", "Avalanche"),
            (["chainlink", "link"], "LINK", "Chainlink"),
            (["polygon", "matic", "pol"], "POL", "Polygon"),
            (["litecoin", "ltc"], "LTC", "Litecoin"),
            (["shiba", "shib"], "SHIB", "Shiba Inu"),
            (["tron", "trx"], "TRX", "TRON"),
            (["pepe"], "PEPE", "Pepe"),
            (["sui"], "SUI", "Sui"),
            (["near"], "NEAR", "NEAR Protocol"),
            (["aptos", "apt"], "APT", "Aptos"),
            (["arbitrum", "arb"], "ARB", "Arbitrum"),
            (["optimism", "op"], "OP", "Optimism"),
            (["cosmos", "atom"], "ATOM", "Cosmos"),
            (["uniswap", "uni"], "UNI", "Uniswap"),
            (["bnb", "binance coin"], "BNB", "BNB"),
            (["toncoin", "ton"], "TON", "Toncoin"),
            (["render", "rndr"], "RNDR", "Render"),
            (["fetch", "fet"], "FET", "Fetch.ai"),
        ]
        
        let lowercased = query.lowercased()
        var detected: [(symbol: String, name: String)] = []
        
        for mapping in coinMappings {
            if mapping.keywords.contains(where: { lowercased.contains($0) }) {
                detected.append((symbol: mapping.symbol, name: mapping.name))
            }
        }
        
        return detected
    }
    
    // MARK: - Smart CryptoSage AI Prediction Fetching for Chat
    
    /// Detects which coin the user is asking about and fetches a CryptoSage AI prediction on demand.
    /// This bridges our prediction engine's analytical power into the chat conversation.
    private func fetchDeepSeekPredictionForChat(query: String) async -> String {
        // Common coin name/symbol mappings for detection
        let coinMappings: [(keywords: [String], symbol: String, name: String)] = [
            (["bitcoin", "btc"], "BTC", "Bitcoin"),
            (["ethereum", "eth"], "ETH", "Ethereum"),
            (["solana", "sol"], "SOL", "Solana"),
            (["cardano", "ada"], "ADA", "Cardano"),
            (["xrp", "ripple"], "XRP", "XRP"),
            (["dogecoin", "doge"], "DOGE", "Dogecoin"),
            (["polkadot", "dot"], "DOT", "Polkadot"),
            (["avalanche", "avax"], "AVAX", "Avalanche"),
            (["chainlink", "link"], "LINK", "Chainlink"),
            (["polygon", "matic", "pol"], "POL", "Polygon"),
            (["litecoin", "ltc"], "LTC", "Litecoin"),
            (["shiba", "shib"], "SHIB", "Shiba Inu"),
            (["tron", "trx"], "TRX", "TRON"),
            (["pepe"], "PEPE", "Pepe"),
            (["sui"], "SUI", "Sui"),
            (["near"], "NEAR", "NEAR Protocol"),
            (["aptos", "apt"], "APT", "Aptos"),
            (["arbitrum", "arb"], "ARB", "Arbitrum"),
            (["optimism", "op"], "OP", "Optimism"),
            (["cosmos", "atom"], "ATOM", "Cosmos"),
            (["uniswap", "uni"], "UNI", "Uniswap"),
        ]
        
        let lowercased = query.lowercased()
        
        // Find which coin the user is asking about
        var detectedSymbol: String?
        var detectedName: String?
        for mapping in coinMappings {
            if mapping.keywords.contains(where: { lowercased.contains($0) }) {
                detectedSymbol = mapping.symbol
                detectedName = mapping.name
                break
            }
        }
        
        // Also check against loaded market coins for less common coins
        if detectedSymbol == nil {
            let marketCoins = await MainActor.run {
                if case .success(let coins) = MarketViewModel.shared.state {
                    return coins.prefix(100)
                }
                return ArraySlice<MarketCoin>([])
            }
            for coin in marketCoins {
                if lowercased.contains(coin.symbol.lowercased()) || lowercased.contains(coin.name.lowercased()) {
                    detectedSymbol = coin.symbol.uppercased()
                    detectedName = coin.name
                    break
                }
            }
        }
        
        guard let symbol = detectedSymbol, let name = detectedName else {
            return "" // No coin detected in query
        }
        
        // Check if we already have a cached prediction (no API call needed)
        let predictionService = AIPricePredictionService.shared
        let cacheKey = "\(symbol.uppercased())_day"
        if let cached = predictionService.cachedPredictions[cacheKey] {
            return formatPredictionForChat(cached, coinName: name)
        }
        
        // No cached prediction — try to fetch one from Firebase (CryptoSage AI)
        // Use a short timeout so we don't block the chat for too long
        do {
            let prediction = try await withTimeout(5) {
                try await predictionService.generatePrediction(
                    for: symbol,
                    coinName: name,
                    timeframe: .day,
                    forceRefresh: false
                )
            }
            return formatPredictionForChat(prediction, coinName: name)
        } catch {
            // If prediction fetch fails, check other timeframes in cache
            for tf in ["_week", "_fourHours", "_hour"] {
                let altKey = "\(symbol.uppercased())\(tf)"
                if let cached = predictionService.cachedPredictions[altKey] {
                    return formatPredictionForChat(cached, coinName: name)
                }
            }
            print("[Chat-Prediction] Failed to fetch prediction for \(symbol): \(error.localizedDescription)")
            return ""
        }
    }
    
    /// Format a CryptoSage AI prediction into a concise context string for the chat system prompt.
    private func formatPredictionForChat(_ prediction: AIPricePrediction, coinName: String) -> String {
        var lines: [String] = []
        lines.append("\(coinName) (\(prediction.coinSymbol)) - \(prediction.timeframe.fullName) Prediction:")
        lines.append("Direction: \(prediction.direction.displayName.uppercased())")
        lines.append("Confidence: \(prediction.confidenceScore)% (\(prediction.confidence.displayName))")
        lines.append("Predicted Change: \(prediction.formattedPriceChange)")
        lines.append("Price Range: \(prediction.priceRangeText)")
        
        let topDrivers = prediction.drivers.prefix(3)
        if !topDrivers.isEmpty {
            let driversText = topDrivers.map { "\($0.name): \($0.signal)" }.joined(separator: ", ")
            lines.append("Key Drivers: \(driversText)")
        }
        
        if !prediction.analysis.isEmpty {
            lines.append("Analysis: \(prediction.analysis)")
        }
        
        lines.append("(Generated by CryptoSage AI — our specialized crypto prediction engine)")
        return lines.joined(separator: "\n")
    }
    
    /// Build a quick summary of trading pair preferences for context augmentation
    private func buildQuickTradingPairPreferences() async -> String {
        let prefsService = await MainActor.run { TradingPairPreferencesService.shared }
        let favoritePairs = await MainActor.run { prefsService.getFavoritePairsInfo() }
        let preferredExchanges = await MainActor.run { prefsService.getPreferredExchanges() }
        let preferredQuote = await MainActor.run { prefsService.getPreferredQuoteCurrency() }
        
        // If no preferences, return empty
        guard !favoritePairs.isEmpty || !preferredExchanges.isEmpty else {
            return ""
        }
        
        var parts: [String] = []
        
        // Favorite pairs (top 3)
        if !favoritePairs.isEmpty {
            let topFavorites = favoritePairs.prefix(3).map { $0.fullDescription }.joined(separator: ", ")
            parts.append("Favorites: \(topFavorites)")
        }
        
        // Preferred exchange
        if let primaryExchange = preferredExchanges.first {
            let exchangeName: String
            switch primaryExchange.lowercased() {
            case "binance": exchangeName = "Binance"
            case "coinbase": exchangeName = "Coinbase"
            case "kraken": exchangeName = "Kraken"
            case "kucoin": exchangeName = "KuCoin"
            default: exchangeName = primaryExchange.capitalized
            }
            parts.append("Preferred Exchange: \(exchangeName)")
        }
        
        // Preferred quote
        parts.append("Quote: \(preferredQuote)")
        
        return parts.joined(separator: " | ")
    }
    
    /// Build a quick sentiment summary for augmenting trading queries
    private func buildQuickSentimentContext() async -> String {
        let sentimentVM = await MainActor.run { ExtendedFearGreedViewModel.shared }
        
        guard let currentValue = await MainActor.run(body: { sentimentVM.currentValue }) else {
            return ""
        }
        
        let classification = await MainActor.run { sentimentVM.currentClassificationKey?.capitalized ?? "Unknown" }
        let delta1d = await MainActor.run { sentimentVM.delta1d }
        let bias = await MainActor.run { sentimentVM.bias }
        
        var parts: [String] = []
        parts.append("Fear/Greed: \(currentValue)/100 (\(classification))")
        
        if let d1d = delta1d {
            let sign = d1d >= 0 ? "+" : ""
            parts.append("24h: \(sign)\(d1d)")
        }
        
        let biasStr: String
        switch bias {
        case .bullish: biasStr = "Bullish"
        case .bearish: biasStr = "Bearish"
        case .neutral: biasStr = "Neutral"
        }
        parts.append("Bias: \(biasStr)")
        
        return parts.joined(separator: " | ")
    }
    
    /// Build a quick portfolio summary for augmenting trading queries
    /// Automatically uses paper trading balances when paper trading mode is enabled
    /// Also includes real portfolio info when user has connected accounts in paper trading mode
    private func buildQuickPortfolioContext() async -> String {
        // Mode priority: Paper Trading > Demo Mode > Live Mode
        
        // Check if paper trading mode is enabled
        if PaperTradingManager.isEnabled {
            let hasConnectedAccounts = await MainActor.run { !ConnectedAccountsManager.shared.accounts.isEmpty }
            let paperContext = await buildQuickPaperTradingContext()
            
            // If user has connected accounts, also include real portfolio summary
            if hasConnectedAccounts {
                let realContext = await buildQuickRealPortfolioContext()
                return "\(paperContext) || ALSO HAS REAL: \(realContext) || Infer from context, default paper for trades"
            }
            
            return paperContext
        }
        
        // Check if demo mode is enabled
        if DemoModeManager.isEnabled {
            let hasConnectedAccounts = await MainActor.run { !ConnectedAccountsManager.shared.accounts.isEmpty }
            if hasConnectedAccounts {
                return "DEMO MODE (SAMPLE DATA) - User has real accounts connected but viewing demo data"
            } else {
                return "DEMO MODE (SAMPLE DATA) - Not real portfolio. Suggest Paper Trading or connecting an exchange."
            }
        }
        
        // Live mode - check if user has connected accounts
        let hasConnectedAccounts = await MainActor.run { !ConnectedAccountsManager.shared.accounts.isEmpty }
        let holdings = await MainActor.run { portfolioVM.holdings }
        let totalValue = await MainActor.run { portfolioVM.totalValue }
        
        guard !holdings.isEmpty else {
            if hasConnectedAccounts {
                return "LIVE MODE - Connected exchanges show no holdings (may need to fund accounts)"
            } else {
                return "NO EXCHANGES CONNECTED - Guide user to connect exchange or try Paper Trading"
            }
        }
        
        // Live mode with actual holdings
        let sortedHoldings = holdings.sorted { $0.currentValue > $1.currentValue }
        var parts: [String] = []
        
        // Indicate live mode
        parts.append("LIVE")
        
        // Total value
        parts.append("Total: $\(formatCompact(totalValue))")
        
        // Top holdings with allocation
        for holding in sortedHoldings.prefix(5) {
            let allocation = totalValue > 0 ? (holding.currentValue / totalValue) * 100 : 0
            let plPercent = holding.costBasis > 0 ? ((holding.currentPrice - holding.costBasis) / holding.costBasis) * 100 : 0
            let plSign = plPercent >= 0 ? "+" : ""
            parts.append("\(holding.coinSymbol): \(String(format: "%.1f", allocation))% (\(plSign)\(String(format: "%.1f", plPercent))% P/L)")
        }
        
        if holdings.count > 5 {
            parts.append("+\(holdings.count - 5) more")
        }
        
        return parts.joined(separator: " | ")
    }
    
    /// Build a quick paper trading portfolio summary for augmenting trading queries
    private func buildQuickPaperTradingContext() async -> String {
        let paperManager = await MainActor.run { PaperTradingManager.shared }
        let balances = await MainActor.run { paperManager.nonZeroBalances }
        
        // Get current market prices for valuation
        // PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing across all views
        let marketVM = await MainActor.run { MarketViewModel.shared }
        var prices: [String: Double] = ["USDT": 1.0, "USD": 1.0, "USDC": 1.0, "BUSD": 1.0]
        let allCoins = await MainActor.run { marketVM.allCoins }
        for coin in allCoins {
            let symbol = coin.symbol.uppercased()
            // Priority: bestPrice() > coin.priceUsd (fallback)
            let bestPriceResult: Double? = await MainActor.run { marketVM.bestPrice(for: coin.id) }
            if let price = bestPriceResult, price > 0 {
                prices[symbol] = price
            } else if let price = coin.priceUsd, price > 0 {
                prices[symbol] = price
            }
        }
        
        let totalValue = await MainActor.run { paperManager.calculatePortfolioValue(prices: prices) }
        let pnl = await MainActor.run { paperManager.calculateProfitLoss(prices: prices) }
        let pnlPercent = await MainActor.run { paperManager.calculateProfitLossPercent(prices: prices) }
        let availableUSDT = await MainActor.run { paperManager.balance(for: "USDT") }
        let totalTrades = await MainActor.run { paperManager.totalTradeCount }
        
        var parts: [String] = []
        
        // Indicate paper trading mode
        parts.append("PAPER TRADING")
        
        // Total value and P/L
        parts.append("Total: $\(formatCompact(totalValue))")
        let pnlSign = pnl >= 0 ? "+" : ""
        parts.append("P/L: \(pnlSign)\(String(format: "%.1f", pnlPercent))%")
        
        // Available cash
        parts.append("Cash: $\(formatCompact(availableUSDT))")
        
        // Crypto holdings (non-stablecoin balances)
        let cryptoBalances = balances.filter { !["USDT", "USD", "USDC", "BUSD"].contains($0.asset) }
        let sortedCrypto = cryptoBalances.sorted { item1, item2 in
            let val1 = item1.amount * (prices[item1.asset] ?? 1.0)
            let val2 = item2.amount * (prices[item2.asset] ?? 1.0)
            return val1 > val2
        }
        
        for item in sortedCrypto.prefix(4) {
            let price = prices[item.asset] ?? 1.0
            let value = item.amount * price
            let allocation = totalValue > 0 ? (value / totalValue) * 100 : 0
            parts.append("\(item.asset): \(String(format: "%.1f", allocation))%")
        }
        
        if sortedCrypto.count > 4 {
            parts.append("+\(sortedCrypto.count - 4) more")
        }
        
        // Trade count
        if totalTrades > 0 {
            parts.append("\(totalTrades) trades")
        }
        
        return parts.joined(separator: " | ")
    }
    
    /// Build a quick summary of the user's REAL portfolio (for paper trading mode with connected accounts)
    private func buildQuickRealPortfolioContext() async -> String {
        let holdings = await MainActor.run { portfolioVM.holdings }
        let totalValue = await MainActor.run { portfolioVM.totalValue }
        
        guard !holdings.isEmpty else {
            return "No real holdings"
        }
        
        let sortedHoldings = holdings.sorted { $0.currentValue > $1.currentValue }
        var parts: [String] = []
        
        parts.append("Real: $\(formatCompact(totalValue))")
        
        // Top 3 real holdings
        for holding in sortedHoldings.prefix(3) {
            let allocation = totalValue > 0 ? (holding.currentValue / totalValue) * 100 : 0
            parts.append("\(holding.coinSymbol): \(String(format: "%.1f", allocation))%")
        }
        
        if holdings.count > 3 {
            parts.append("+\(holdings.count - 3) more")
        }
        
        return parts.joined(separator: " | ")
    }
    
    private func formatCompact(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.2fK", value / 1_000)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    private func uploadImageToOpenAI(_ data: Data, filename: String = "image.jpg") async throws -> String {
        let session = AITabView.openAISession

        guard let url = URL(string: "https://api.openai.com/v1/files") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(APIConfig.openAIKey)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n".utf8))
        body.append(Data("assistants\r\n".utf8))
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        request.httpBody = body

        let (respData, resp) = try await session.data(for: request)
        logResponse(respData, resp)

        struct UploadResponse: Codable { let id: String }
        let res = try JSONDecoder().decode(UploadResponse.self, from: respData)
        return res.id
    }
    
    private func withTimeout<T>(_ seconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    /// Custom error type for AI request timeout
    private struct AIRequestTimeoutError: Error {
        let message: String
        init(_ message: String = "The request timed out. This can happen during high server load or slow network conditions. Please try again.") {
            self.message = message
        }
    }
    
    /// Timeout duration for AI requests (45 seconds - allows for complex queries and article analysis)
    private var aiRequestTimeoutSeconds: UInt64 { 45 }
    
    /// Detect if a user query likely needs web search (current news, research, real-time info)
    /// Returns true if the query should use non-streaming mode with tools enabled
    /// IMPORTANT: This should be called with the ORIGINAL user input, not augmented input
    private func needsWebResearch(_ query: String) -> Bool {
        let lowercased = query.lowercased()
        
        // EXCLUSION: App-specific queries should NEVER trigger web search
        // These are queries about local app data/features
        let appLocalKeywords = [
            "my alert", "my price alert", "price alert",
            "my portfolio", "my holdings", "my balance",
            "my bot", "my trade", "my order",
            "my watchlist", "my favorites",
            "set alert", "create alert", "add alert",
            "triggering", "close to triggering",
            "paper trad", "paper mode"
        ]
        
        for keyword in appLocalKeywords {
            if lowercased.contains(keyword) {
                return false // Explicitly NOT a web search query
            }
        }
        
        // Research intent keywords - these suggest user wants external/real-time info
        let researchKeywords = [
            "research", "look up", "search for", "find out about",
            "news about", "latest news", "recent news",
            "what happened to", "what's happening with", "update on",
            "current news", "current events",
            "right now in the market", "just announced",
            "fomc", "fed meeting", "sec filing", "regulation news",
            "announcement from", "breaking news", "report on",
            "earnings report", "quarterly results",
            "read this article", "summarize this", "http://", "https://",
            "article about", "link to"
        ]
        
        // Check for research keywords (more specific phrases to avoid false positives)
        for keyword in researchKeywords {
            if lowercased.contains(keyword) {
                return true
            }
        }
        
        // Check for URL patterns
        if lowercased.contains(".com/") || lowercased.contains(".org/") || 
           lowercased.contains(".io/") || lowercased.contains(".net/") ||
           lowercased.hasPrefix("http") {
            return true
        }
        
        return false
    }
    
    private func sendMessage() {
        // Cancel any previous AI request before starting a new one
        activeAITask?.cancel()
        activeAITask = nil
        
        // Prevent multiple submissions while AI is processing
        guard !isThinking else { return }
        
        // Check per-minute rate limit (abuse protection)
        if subscriptionManager.isRateLimited {
            let wait = subscriptionManager.rateLimitSecondsRemaining
            showToast("Slow down — try again in \(wait)s")
            return
        }
        
        // Check daily AI prompt limit
        if !subscriptionManager.canSendAIPrompt {
            showPromptLimitView = true
            return
        }
        
        // Check if API key is configured (Firebase or local)
        if !APIConfig.hasAICapability {
            showToast("AI not available - please configure API key")
            // Add a helpful message to the chat with clear instructions
            let ensuredIndex = ensureActiveConversation()
            var convo = conversations[ensuredIndex]
            let helpMsg = ChatMessage(
                sender: "ai",
                text: """
                    **AI Chat Requires Setup**
                    
                    To use CryptoSage AI, you need to add your OpenAI API key:
                    
                    1. Go to **Settings** > **API Credentials** > **AI Settings**
                    2. Enter your OpenAI API key
                    3. Get a key at platform.openai.com/api-keys
                    
                    Once configured, you can ask me anything about crypto!
                    """,
                isError: true
            )
            convo.messages.append(helpMsg)
            conversations[ensuredIndex] = convo
            saveConversations()
            return
        }
        
        // Ensure we have an active conversation index; create one if needed
        let ensuredIndex = ensureActiveConversation()

        let trimmed = chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !pendingImages.isEmpty else { return }
        
        // Clear any previous configurations to prevent stale data from showing
        detectedTradeConfig = nil
        detectedBotConfig = nil
        detectedStrategyConfig = nil
        detectedAlertSuggestion = nil
        
        // BLANK SCREEN FIX: Set isThinking FIRST before any UI updates
        // This ensures the thinking indicator shows immediately, preventing blank states
        isThinking = true
        
        // Clear input immediately for responsive feel
        let inputToSend = trimmed
        chatVM.inputText = ""
        
        // Analytics: Track AI chat message sent
        AnalyticsService.shared.track(.aiChatMessageSent)

        // Create placeholder for streaming AI response (text-only messages)
        let placeholderId = UUID()
        
        // BLANK SCREEN FIX: Build all messages atomically, then update conversation once
        // This prevents intermediate states where the view might see partial updates
        var convo = conversations[ensuredIndex]
        
        // Add user message(s)
        if pendingImages.isEmpty {
            let userMsg = ChatMessage(sender: "user", text: inputToSend)
            convo.messages.append(userMsg)
            // Add AI placeholder for streaming
            let placeholder = ChatMessage(id: placeholderId, sender: "ai", text: "", isStreaming: true)
            convo.messages.append(placeholder)
        } else {
            for (i, data) in pendingImages.enumerated() {
                let caption = (i == 0) ? inputToSend : ""
                let userMsg = ChatMessage(sender: "user", text: caption, imageData: data)
                convo.messages.append(userMsg)
            }
        }

        // Update title if this is the first message
        if convo.title == "New Chat" && convo.messages.filter({ $0.sender == "user" }).count == 1 {
            let base = inputToSend.isEmpty ? "Image" : inputToSend
            convo.title = String(base.prefix(50))
        }

        // SINGLE atomic update to the conversation
        conversations[ensuredIndex] = convo
        persistMessageImagesIfNeeded()
        saveConversations()
        
        // Store the conversation ID to verify we're still on the same conversation
        let originalConversationID = activeConversationID
        
        // Store pending images locally since self.pendingImages may change
        let imagesToProcess = pendingImages

        // Store task reference for cancellation support
        activeAITask = Task {
            do {
                // Check for cancellation early
                try Task.checkCancellation()
                
                let augmentedInput = (try? await withTimeout(2, operation: { await maybeAugmentUserInput(inputToSend) })) ?? inputToSend
                
                // Check for cancellation after augmentation
                try Task.checkCancellation()

                if imagesToProcess.isEmpty {
                    // Use streaming for text-only messages - text appears progressively
                    let aiService = AIService.shared
                    
                    // Inject current portfolio data into function tools
                    await MainActor.run {
                        AIFunctionTools.shared.updatePortfolio(
                            holdings: portfolioVM.holdings,
                            totalValue: portfolioVM.totalValue
                        )
                    }
                    
                    // Sync conversation history with AIService
                    await MainActor.run {
                        if let currentConvoIndex = conversations.firstIndex(where: { $0.id == activeConversationID }) {
                            let convoMessages = conversations[currentConvoIndex].messages.filter { !$0.text.isEmpty }
                            aiService.setHistory(from: convoMessages)
                        }
                    }
                    
                    // Use smart prompt routing - lightweight for simple queries, full context for portfolio-related
                    let systemPrompt = await AIContextBuilder.shared.getSystemPrompt(for: augmentedInput, portfolio: portfolioVM)
                    
                    // Detect if this needs full context (portfolio-related query)
                    let needsFullContext = AIContextBuilder.shared.needsFullContext(for: augmentedInput)
                    
                    // Check if query needs web research (use non-streaming with tools)
                    // IMPORTANT: Use original input, not augmented - augmented may contain keywords like "current"
                    // from portfolio context that would falsely trigger web search
                    let needsResearch = await MainActor.run { self.needsWebResearch(inputToSend) }
                    
                    // Check for cancellation before making API call
                    try Task.checkCancellation()
                    
                    if needsResearch {
                        // For research queries, call Firebase webSearch first to get real-time info
                        // This works for ALL users (free tier included) since Firebase handles it
                        var searchContext = ""
                        
                        // Show "Searching the web..." indicator
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                self.activeToolName = "web_search"
                            }
                        }
                        
                        // Try to get web search results
                        do {
                            let firebaseService = FirebaseService.shared
                            if firebaseService.hasWebSearchCapability {
                                let searchResponse = try await firebaseService.webSearch(query: augmentedInput)
                                searchContext = firebaseService.formatWebSearchForAI(searchResponse)
                                print("[AIChatView] Web search returned \(searchResponse.results.count) results")
                            }
                        } catch {
                            print("[AIChatView] Web search failed: \(error.localizedDescription)")
                            // Continue without search results - AI will use its knowledge
                        }
                        
                        // Keep the search indicator showing - it will be cleared when text starts streaming
                        // This prevents two sequential loading indicators (search bubble -> thinking bubble -> text)
                        // The streaming callback below will clear both activeToolName and isThinking when text arrives
                        
                        try Task.checkCancellation()
                        
                        // Build enhanced prompt with search results
                        var enhancedPrompt = systemPrompt
                        if !searchContext.isEmpty {
                            enhancedPrompt += "\n\n--- REAL-TIME WEB SEARCH RESULTS ---\n\(searchContext)\n--- END SEARCH RESULTS ---\n\nUse the above search results to answer the user's question with current information. Cite sources when relevant."
                        }
                        
                        // Now send to chat with enriched context (uses streaming for better UX)
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask {
                                _ = try await aiService.sendMessageStreaming(
                                    augmentedInput,
                                    systemPrompt: enhancedPrompt,
                                    usePremiumModel: needsFullContext,
                                    includeTools: false
                                ) { streamedText in
                                    DispatchQueue.main.async {
                                        guard self.activeConversationID == originalConversationID else { return }
                                        
                                        // Clear all loading indicators once text starts flowing
                                        // This prevents: search bubble -> thinking bubble -> text (two indicators)
                                        // Instead: search bubble -> text (single smooth transition)
                                        if !streamedText.isEmpty {
                                            if self.activeToolName != nil || self.isThinking {
                                                withAnimation(.easeOut(duration: 0.2)) {
                                                    self.activeToolName = nil
                                                    self.isThinking = false
                                                }
                                            }
                                        }
                                        
                                        if let idx = self.conversations.firstIndex(where: { $0.id == self.activeConversationID }),
                                           let msgIdx = self.conversations[idx].messages.firstIndex(where: { $0.id == placeholderId }) {
                                            self.conversations[idx].messages[msgIdx].text = streamedText
                                        }
                                    }
                                }
                            }
                            
                            group.addTask {
                                try await Task.sleep(nanoseconds: self.aiRequestTimeoutSeconds * 1_000_000_000)
                                throw AIRequestTimeoutError()
                            }
                            
                            do {
                                try await group.next()
                                group.cancelAll()
                            } catch {
                                group.cancelAll()
                                throw error
                            }
                        }
                    } else {
                        // Stream the response with timeout - update placeholder message as chunks arrive
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            // Task 1: The actual AI streaming request
                            group.addTask {
                                _ = try await aiService.sendMessageStreaming(
                                    augmentedInput,
                                    systemPrompt: systemPrompt,
                                    usePremiumModel: needsFullContext, // Premium model for portfolio queries only
                                    includeTools: false
                                ) { streamedText in
                                    // Ensure UI updates happen on main thread
                                    DispatchQueue.main.async {
                                        // Only update if we're still on the same conversation
                                        guard self.activeConversationID == originalConversationID else { return }
                                        
                                        // Hide thinking indicator once text starts flowing (with smooth fade out)
                                        if self.isThinking && !streamedText.isEmpty {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                self.isThinking = false
                                            }
                                        }
                                        // Update the placeholder message with streamed content
                                        // Direct updates for streaming feel most natural - no animation needed
                                        if let idx = self.conversations.firstIndex(where: { $0.id == self.activeConversationID }),
                                           let msgIdx = self.conversations[idx].messages.firstIndex(where: { $0.id == placeholderId }) {
                                            self.conversations[idx].messages[msgIdx].text = streamedText
                                        }
                                    }
                                }
                            }
                            
                            // Task 2: Timeout watchdog (30 seconds)
                            group.addTask {
                                try await Task.sleep(nanoseconds: self.aiRequestTimeoutSeconds * 1_000_000_000)
                                throw AIRequestTimeoutError()
                            }
                            
                            // Wait for the first task to complete (streaming or timeout)
                            do {
                                try await group.next()
                                // Cancel the other task
                                group.cancelAll()
                            } catch {
                                group.cancelAll()
                                throw error
                            }
                        }
                    }
                    
                    // Streaming complete - finalize (ensure on main thread)
                    await MainActor.run {
                        // Only finalize if we're still on the same conversation
                        guard self.activeConversationID == originalConversationID else { return }
                        
                        // Clear all indicators - streaming callback should have already done this,
                        // but we ensure cleanup here for robustness
                        self.activeToolName = nil
                        self.isThinking = false
                        self.activeAITask = nil
                        
                        // Mark streaming as complete (removes typing cursor)
                        if let idx = self.conversations.firstIndex(where: { $0.id == self.activeConversationID }),
                           let msgIdx = self.conversations[idx].messages.firstIndex(where: { $0.id == placeholderId }) {
                            self.conversations[idx].messages[msgIdx].isStreaming = false
                            let finalText = self.conversations[idx].messages[msgIdx].text
                            self.parseTradeConfigFromResponse(finalText, userMessage: inputToSend)
                            self.parseAlertSuggestionFromResponse(finalText, userMessage: inputToSend)
                            self.parseBotConfigFromResponse(finalText, userMessage: inputToSend)
                            self.parseStrategyConfigFromResponse(finalText, userMessage: inputToSend)
                        }
                        
                        self.saveConversations()
                        
                        // Auto-refresh prompts after AI response with conversation-aware follow-ups
                        self.refreshPersonalizedPrompts()
                        
                        // Record successful prompt usage with model info
                        let modelUsed = self.subscriptionManager.effectiveTier == .premium ? "gpt-4o" : "gpt-4o-mini"
                        self.subscriptionManager.recordAIPromptUsage(modelUsed: modelUsed)
                    }
                } else {
                    // For images, use the legacy method with Assistants API for now
                    var fileIds: [String] = []
                    for data in imagesToProcess { fileIds.append(try await uploadImageToOpenAI(data, filename: "image.jpg")) }
                    let finalPrompt = augmentedInput.isEmpty ? "Analyze the attached image(s). If relevant to crypto/finance, call it out; otherwise describe them succinctly." : augmentedInput
                    
                    // Check for cancellation before legacy API call
                    try Task.checkCancellation()
                    
                    let aiText = try await fetchAIResponseLegacy(for: finalPrompt, imageFileIds: fileIds)
                    await MainActor.run {
                        // Only finalize if we're still on the same conversation
                        guard self.activeConversationID == originalConversationID else { return }
                        guard let idx = self.conversations.firstIndex(where: { $0.id == self.activeConversationID }) else { return }
                        
                        var updatedConvo = self.conversations[idx]
                        let aiMsg = ChatMessage(sender: "ai", text: aiText)
                        updatedConvo.messages.append(aiMsg)
                        self.conversations[idx] = updatedConvo
                        self.activeToolName = nil
                        self.isThinking = false
                        self.activeAITask = nil
                        self.pendingImages.removeAll()
                        self.saveConversations()
                        
                        // Auto-refresh prompts after AI response with conversation-aware follow-ups
                        self.refreshPersonalizedPrompts()
                        
                        // Check for trade configuration, alert suggestions, bot configs, and strategy configs in the response
                        self.parseTradeConfigFromResponse(aiText, userMessage: inputToSend)
                        self.parseAlertSuggestionFromResponse(aiText, userMessage: inputToSend)
                        self.parseBotConfigFromResponse(aiText, userMessage: inputToSend)
                        self.parseStrategyConfigFromResponse(aiText, userMessage: inputToSend)
                        
                        // Record successful prompt usage with model info
                        let modelUsed = self.subscriptionManager.effectiveTier == .premium ? "gpt-4o" : "gpt-4o-mini"
                        self.subscriptionManager.recordAIPromptUsage(modelUsed: modelUsed)
                    }
                }
            } catch is CancellationError {
                // Task was cancelled (user tapped Stop, switched conversations, or started new chat)
                // Silently clean up without showing error - this is expected behavior
                await MainActor.run {
                    // Only clean up if we're still on the original conversation
                    if self.activeConversationID == originalConversationID {
                        if let idx = self.conversations.firstIndex(where: { $0.id == originalConversationID }),
                           let msgIdx = self.conversations[idx].messages.firstIndex(where: { $0.id == placeholderId }) {
                            if self.conversations[idx].messages[msgIdx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                // Empty placeholder - remove it entirely
                                self.conversations[idx].messages.remove(at: msgIdx)
                            } else {
                                // Partial response exists - keep it but mark streaming as complete
                                // so it doesn't show the typing indicator forever
                                self.conversations[idx].messages[msgIdx].isStreaming = false
                            }
                        }
                        self.activeToolName = nil
                        self.isThinking = false
                        self.activeAITask = nil
                        self.pendingImages.removeAll()
                        self.saveConversations()
                    }
                }
            } catch let error as AIRequestTimeoutError {
                // Request timed out - show user-friendly message
                await MainActor.run {
                    // Only show error if we're still on the same conversation
                    guard self.activeConversationID == originalConversationID else { return }
                    guard let idx = self.conversations.firstIndex(where: { $0.id == self.activeConversationID }) else { return }
                    
                    let errorText = error.message
                    
                    // Update placeholder if it exists (text-only), otherwise append new message
                    if let msgIdx = self.conversations[idx].messages.firstIndex(where: { $0.id == placeholderId }) {
                        self.conversations[idx].messages[msgIdx].text = errorText
                        self.conversations[idx].messages[msgIdx].isError = true
                        self.conversations[idx].messages[msgIdx].isStreaming = false
                    } else {
                        var updatedConvo = self.conversations[idx]
                        let errMsg = ChatMessage(sender: "ai", text: errorText, isError: true)
                        updatedConvo.messages.append(errMsg)
                        self.conversations[idx] = updatedConvo
                    }
                    
                    self.activeToolName = nil
                    self.isThinking = false
                    self.activeAITask = nil
                    self.pendingImages.removeAll()
                    // Clear stale configs on error to prevent showing buttons for failed requests
                    self.detectedTradeConfig = nil
                    self.detectedBotConfig = nil
                    self.detectedStrategyConfig = nil
                    self.detectedAlertSuggestion = nil
                    self.saveConversations()
                }
            } catch let error as AIServiceError {
                await MainActor.run {
                    // Only show error if we're still on the same conversation
                    guard self.activeConversationID == originalConversationID else { return }
                    guard let idx = self.conversations.firstIndex(where: { $0.id == self.activeConversationID }) else { return }
                    
                    let errorText = error.errorDescription ?? "AI request failed"
                    
                    // Update placeholder if it exists (text-only), otherwise append new message
                    if let msgIdx = self.conversations[idx].messages.firstIndex(where: { $0.id == placeholderId }) {
                        self.conversations[idx].messages[msgIdx].text = errorText
                        self.conversations[idx].messages[msgIdx].isError = true
                        self.conversations[idx].messages[msgIdx].isStreaming = false
                    } else {
                        var updatedConvo = self.conversations[idx]
                        let errMsg = ChatMessage(sender: "ai", text: errorText, isError: true)
                        updatedConvo.messages.append(errMsg)
                        self.conversations[idx] = updatedConvo
                    }
                    
                    self.activeToolName = nil
                    self.isThinking = false
                    self.activeAITask = nil
                    self.pendingImages.removeAll()
                    // Clear stale configs on error
                    self.detectedTradeConfig = nil
                    self.detectedBotConfig = nil
                    self.detectedStrategyConfig = nil
                    self.detectedAlertSuggestion = nil
                    self.saveConversations()
                }
            } catch {
                await MainActor.run {
                    // Only show error if we're still on the same conversation
                    guard self.activeConversationID == originalConversationID else { return }
                    guard let idx = self.conversations.firstIndex(where: { $0.id == self.activeConversationID }) else { return }
                    
                    // Provide more helpful error messages based on error type
                    let errorText: String
                    let errorDesc = error.localizedDescription.lowercased()
                    
                    if errorDesc.contains("network") || errorDesc.contains("internet") || errorDesc.contains("connection") {
                        errorText = "Connection Error\n\nUnable to reach AI service. Please check your internet connection and try again."
                    } else if errorDesc.contains("unauthorized") || errorDesc.contains("401") || errorDesc.contains("invalid") && errorDesc.contains("key") {
                        errorText = "API Key Error\n\nYour API key may be invalid or expired. Please check your API key in Settings > API Credentials."
                    } else if errorDesc.contains("rate") || errorDesc.contains("limit") || errorDesc.contains("429") {
                        errorText = "Rate Limited\n\nToo many requests. Please wait a moment and try again."
                    } else if errorDesc.contains("server") || errorDesc.contains("500") || errorDesc.contains("503") {
                        errorText = "Service Unavailable\n\nThe AI service is temporarily unavailable. Please try again in a few minutes."
                    } else {
                        errorText = "Request Failed\n\n\(error.localizedDescription)\n\nPlease try again or check your API key configuration in Settings."
                    }
                    
                    // Update placeholder if it exists (text-only), otherwise append new message
                    if let msgIdx = self.conversations[idx].messages.firstIndex(where: { $0.id == placeholderId }) {
                        self.conversations[idx].messages[msgIdx].text = errorText
                        self.conversations[idx].messages[msgIdx].isError = true
                        self.conversations[idx].messages[msgIdx].isStreaming = false
                    } else {
                        var updatedConvo = self.conversations[idx]
                        let errMsg = ChatMessage(sender: "ai", text: errorText, isError: true)
                        updatedConvo.messages.append(errMsg)
                        self.conversations[idx] = updatedConvo
                    }
                    
                    self.activeToolName = nil
                    self.isThinking = false
                    self.activeAITask = nil
                    self.pendingImages.removeAll()
                    // Clear stale configs on error
                    self.detectedTradeConfig = nil
                    self.detectedBotConfig = nil
                    self.detectedStrategyConfig = nil
                    self.detectedAlertSuggestion = nil
                    self.saveConversations()
                }
            }
        }
    }
    
    /// Helper to ensure we have an active conversation
    private func ensureActiveConversation() -> Int {
        if let activeID = activeConversationID,
           let idx = conversations.firstIndex(where: { $0.id == activeID }) {
            return idx
        } else {
            // Creating a new conversation - clear any stale state
            activeAITask?.cancel()
            activeAITask = nil
            isThinking = false
            AIService.shared.clearHistory()
            
            let newConvo = Conversation(title: "New Chat")
            conversations.append(newConvo)
            activeConversationID = newConvo.id
            saveConversations()
            return conversations.count - 1
        }
    }
    
    private func fetchAIResponse(for userInput: String, imageFileIds: [String] = []) async throws -> String {
        // Use the new AIService with Chat Completions API
        let aiService = AIService.shared
        
        // Inject current portfolio data into function tools
        await MainActor.run {
            AIFunctionTools.shared.updatePortfolio(
                holdings: portfolioVM.holdings,
                totalValue: portfolioVM.totalValue
            )
        }
        
        // Sync conversation history with AIService
        if let currentConvoIndex = conversations.firstIndex(where: { $0.id == activeConversationID }) {
            let convoMessages = conversations[currentConvoIndex].messages
            aiService.setHistory(from: convoMessages)
        }
        
        // Use smart prompt routing - lightweight for simple queries, full context for portfolio-related
        let systemPrompt = await AIContextBuilder.shared.getSystemPrompt(for: userInput, portfolio: portfolioVM)
        
        // Detect if this is a trading advice query that needs the premium model
        let needsFullContext = AIContextBuilder.shared.needsFullContext(for: userInput)
        
        // If we have images, we need to handle them differently
        // For now, images are described in the prompt (Vision API integration can be added later)
        var finalInput = userInput
        if !imageFileIds.isEmpty {
            finalInput = "\(userInput)\n\n[Note: \(imageFileIds.count) image(s) attached - please describe what you'd like to know about them]"
        }
        
        // Use AIService to get response with function calling
        // Use premium model only for complex portfolio-related queries
        let response = try await aiService.sendMessage(
            finalInput,
            systemPrompt: systemPrompt,
            usePremiumModel: needsFullContext, // Premium model for portfolio queries, mini for simple questions
            includeTools: needsFullContext // Only include tools for complex queries
        )
        
        return response
    }
    
    
    /// Legacy method for Assistants API (kept for image analysis fallback)
    private func fetchAIResponseLegacy(for userInput: String, imageFileIds: [String] = []) async throws -> String {
        let session = AITabView.openAISession
        
        var threadId: String
        if let currentConvoIndex = conversations.firstIndex(where: { $0.id == activeConversationID }),
           let existingThreadId = conversations[currentConvoIndex].threadId {
            threadId = existingThreadId
        } else {
            guard let threadURL = URL(string: "https://api.openai.com/v1/threads") else { throw URLError(.badURL) }
            var threadRequest = URLRequest(url: threadURL)
            threadRequest.httpMethod = "POST"
            threadRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
            threadRequest.addValue("Bearer \(APIConfig.openAIKey)", forHTTPHeaderField: "Authorization")
            threadRequest.addValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
            threadRequest.httpBody = "{}".data(using: .utf8)
            let (threadData, threadResponse) = try await session.data(for: threadRequest)
            logResponse(threadData, threadResponse)
            struct ThreadResponse: Codable { let id: String }
            let threadRes = try JSONDecoder().decode(ThreadResponse.self, from: threadData)
            threadId = threadRes.id
            if let currentConvoIndex = conversations.firstIndex(where: { $0.id == activeConversationID }) {
                conversations[currentConvoIndex].threadId = threadId
                saveConversations()
            }
        }
        
        // POST user message
        guard let messageURL = URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages") else { throw URLError(.badURL) }
        var messageRequest = URLRequest(url: messageURL)
        messageRequest.httpMethod = "POST"
        messageRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        messageRequest.addValue("Bearer \(APIConfig.openAIKey)", forHTTPHeaderField: "Authorization")
        messageRequest.addValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
        let messagePayload: [String: Any]
        if !imageFileIds.isEmpty {
            var blocks: [[String: Any]] = []
            if !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(["type": "input_text", "text": userInput])
            }
            for fid in imageFileIds {
                blocks.append(["type": "input_image", "image_file": ["file_id": fid]])
            }
            messagePayload = ["role": "user", "content": blocks]
        } else {
            messagePayload = ["role": "user", "content": userInput]
        }
        messageRequest.httpBody = try JSONSerialization.data(withJSONObject: messagePayload)
        let (msgData, msgResponse) = try await session.data(for: messageRequest)
        logResponse(msgData, msgResponse)
        
        // POST run assistant
        guard let runURL = URL(string: "https://api.openai.com/v1/threads/\(threadId)/runs") else { throw URLError(.badURL) }
        var runRequest = URLRequest(url: runURL)
        runRequest.httpMethod = "POST"
        runRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        runRequest.addValue("Bearer \(APIConfig.openAIKey)", forHTTPHeaderField: "Authorization")
        runRequest.addValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
        let runPayload: [String: Any] = ["assistant_id": "asst_YlcZqIfjPmhCl44bUO77SYaJ"]
        runRequest.httpBody = try JSONSerialization.data(withJSONObject: runPayload)
        let (runData, runResponseVal) = try await session.data(for: runRequest)
        logResponse(runData, runResponseVal)
        
        struct RunResponse: Codable { let id: String }
        let runRes = try JSONDecoder().decode(RunResponse.self, from: runData)
        let runId = runRes.id
        
        // Poll for run completion – up to 60 iterations (30 seconds total)
        var assistantReply: String? = nil
        for _ in 1...60 {
            try await Task.sleep(nanoseconds: 500_000_000)
            guard let statusURL = URL(string: "https://api.openai.com/v1/threads/\(threadId)/runs/\(runId)") else { throw URLError(.badURL) }
            var statusRequest = URLRequest(url: statusURL)
            statusRequest.httpMethod = "GET"
            statusRequest.addValue("Bearer \(APIConfig.openAIKey)", forHTTPHeaderField: "Authorization")
            statusRequest.addValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
            do {
                let (statusData, statusResp) = try await session.data(for: statusRequest)
                logResponse(statusData, statusResp)
                
                struct RunStatus: Codable { let status: String }
                let statusRes = try JSONDecoder().decode(RunStatus.self, from: statusData)
                if statusRes.status.lowercased() == "succeeded" || statusRes.status.lowercased() == "completed" {
                    // Fetch messages
                    guard let msgsURL = URL(string: "https://api.openai.com/v1/threads/\(threadId)/messages") else { throw URLError(.badURL) }
                    var msgsRequest = URLRequest(url: msgsURL)
                    msgsRequest.httpMethod = "GET"
                    msgsRequest.addValue("Bearer \(APIConfig.openAIKey)", forHTTPHeaderField: "Authorization")
                    msgsRequest.addValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
                    do {
                        let (msgsData, msgsResp) = try await session.data(for: msgsRequest)
                        logResponse(msgsData, msgsResp)
                        
                        struct ThreadMessagesResponse: Codable {
                            let object: String
                            let data: [AssistantMessage]
                            let first_id: String?
                            let last_id: String?
                            let has_more: Bool?
                        }
                        struct AssistantMessage: Codable { let id: String; let role: String; let content: [ContentBlock] }
                        struct ContentBlock: Codable { let type: String; let text: ContentText? }
                        struct ContentText: Codable { let value: String; let annotations: [String]? }
                        
                        let msgsRes = try JSONDecoder().decode(ThreadMessagesResponse.self, from: msgsData)
                        if let lastMsg = msgsRes.data.last, lastMsg.role == "assistant" {
                            let combinedText = lastMsg.content.compactMap { $0.text?.value }.joined(separator: "\n\n")
                            assistantReply = combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } catch {
                        print("Error decoding thread messages:", error)
                    }
                    if assistantReply != nil { break }
                }
            } catch {
                print("Error polling run status:", error)
            }
        }
        
        guard let reply = assistantReply, !reply.isEmpty else { throw URLError(.timedOut) }
        return reply
    }
    
    private func logResponse(_ data: Data, _ response: URLResponse) {
        #if DEBUG
        if let httpRes = response as? HTTPURLResponse {
            print("Status code: \(httpRes.statusCode)")
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            print("Response body: \(body)")
        }
        #endif
    }
    
    private func handleQuickReply(_ reply: String) {
        // QUICK REPLY FIX: Immediate visual feedback and state update
        // This prevents the blank screen issue by ensuring state is updated atomically
        
        // Guard against accidental double-taps or rapid fires
        guard !isThinking else { return }
        
        #if os(iOS)
        // Haptic feedback for responsiveness
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        
        // Set input text first
        chatVM.inputText = reply
        
        // Short delay lets the chip press animation complete before the keyboard
        // and scroll state changes from sendMessage(). 0.15s feels intentional.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.sendMessage()
        }
    }
    
    private func randomizePrompts() {
        // Use AI chat-specific starter prompts for initial load (synchronous, no delays)
        // This ensures prompts are always available immediately
        let prompts: [String]
        if currentMessages.isEmpty {
            // No conversation yet - use chat-specific starters (different from homepage)
            prompts = aiChatStarterPrompts()
        } else {
            // Has conversation - use SmartPromptService with portfolio context
            prompts = SmartPromptService.shared.buildContextualPrompts(count: promptCount, holdings: portfolioVM.holdings)
        }
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            quickReplies = prompts
        }
    }
    
    private func refreshPersonalizedPrompts() {
        isFetchingPersonalized = true
        Task {
            let prompts = await buildPersonalizedPrompts()
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    self.quickReplies = prompts.isEmpty ? SmartPromptService.shared.buildContextualPrompts(count: self.promptCount, holdings: self.portfolioVM.holdings) : prompts
                }
                self.isFetchingPersonalized = false
            }
        }
    }

    private func buildPersonalizedPrompts() async -> [String] {
        // Use recent conversation to derive context (local, no network)
        let recentText = currentMessages.suffix(20).map { $0.text }.joined(separator: " ")
        let recentTextLower = recentText.lowercased()
        let tickers = extractTickers(from: recentText)
        var candidatePrompts: [String] = []
        
        // If no conversation yet, use AI chat-specific starter prompts (different from homepage)
        if recentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return aiChatStarterPrompts()
        }
        
        // Detect conversation topics for more relevant follow-ups
        let isTradingTopic = recentTextLower.contains("buy") || recentTextLower.contains("sell") || 
                            recentTextLower.contains("trade") || recentTextLower.contains("order")
        let isPriceTopic = recentTextLower.contains("price") || recentTextLower.contains("chart") ||
                          recentTextLower.contains("technical") || recentTextLower.contains("analysis")
        let isPortfolioTopic = recentTextLower.contains("portfolio") || recentTextLower.contains("holding") ||
                              recentTextLower.contains("balance") || recentTextLower.contains("allocation")
        let isNewsTopic = recentTextLower.contains("news") || recentTextLower.contains("event") ||
                         recentTextLower.contains("announcement")
        
        // Generate ticker-specific follow-ups with variety
        if let primaryTicker = tickers.first {
            // Shuffle these to get variety on each refresh
            var tickerPrompts = [
                "What's the technical outlook for \(primaryTicker)?",
                "Show me \(primaryTicker)'s support and resistance levels",
                "Should I take profits on \(primaryTicker)?",
                "What's driving \(primaryTicker)'s price today?",
                "Is \(primaryTicker) a good entry point right now?",
                "What's the risk/reward for \(primaryTicker)?",
                "Any recent news affecting \(primaryTicker)?",
                "Set an alert for \(primaryTicker)"
            ]
            
            // Add trading-specific prompts if relevant
            if isTradingTopic {
                tickerPrompts.append(contentsOf: [
                    "Help me size a position for \(primaryTicker)",
                    "What stop loss should I use for \(primaryTicker)?",
                    "DCA into \(primaryTicker) or buy all at once?"
                ])
            }
            
            tickerPrompts.shuffle()
            candidatePrompts.append(contentsOf: tickerPrompts.prefix(2))
        }
        
        // Multi-ticker comparison prompts
        if tickers.count >= 2 {
            let t1 = tickers[0]
            let t2 = tickers[1]
            var comparisonPrompts = [
                "Compare \(t1) and \(t2) for investment",
                "Which is better: \(t1) or \(t2)?",
                "\(t1) vs \(t2) - technical comparison"
            ]
            comparisonPrompts.shuffle()
            if let prompt = comparisonPrompts.first {
                candidatePrompts.append(prompt)
            }
        }
        
        // Topic-aware general prompts (when no tickers detected)
        if tickers.isEmpty {
            if isPortfolioTopic {
                candidatePrompts.append(contentsOf: [
                    "How can I improve my diversification?",
                    "What's my portfolio risk level?"
                ].shuffled().prefix(1))
            }
            if isNewsTopic {
                candidatePrompts.append(contentsOf: [
                    "What other crypto news should I know?",
                    "Any upcoming events to watch?"
                ].shuffled().prefix(1))
            }
            if isPriceTopic {
                candidatePrompts.append(contentsOf: [
                    "Which coins are showing breakout potential?",
                    "What are the top movers today?"
                ].shuffled().prefix(1))
            }
        }

        // Deduplicate and limit
        var seen = Set<String>()
        var prompts: [String] = []
        for p in candidatePrompts {
            let normalized = p.lowercased()
            if !seen.contains(normalized) {
                seen.insert(normalized)
                prompts.append(p)
                if prompts.count >= promptCount { break }
            }
        }
        
        // Fill remaining slots with smart contextual prompts from SmartPromptService
        if prompts.count < promptCount {
            let smartPrompts = SmartPromptService.shared.buildContextualPrompts(
                count: promptCount - prompts.count,
                holdings: portfolioVM.holdings
            )
            for sp in smartPrompts {
                let normalized = sp.lowercased()
                if !seen.contains(normalized) {
                    seen.insert(normalized)
                    prompts.append(sp)
                    if prompts.count >= promptCount { break }
                }
            }
        }
        
        return Array(prompts.prefix(promptCount))
    }

    private func extractTickers(from text: String) -> [String] {
        // Simple regex for ALL-CAPS 2–6 character tokens, filtered by knownTickers
        let pattern = "\\b[A-Z]{2,6}\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        var set = Set<String>()
        for m in matches {
            if let r = Range(m.range, in: text) {
                let token = String(text[r])
                if knownTickers.contains(token) { set.insert(token) }
            }
        }
        return Array(set).sorted()
    }
    
    /// AI chat-specific starter prompts when there's no conversation yet
    /// These are intentionally different from the homepage prompts for variety
    private func aiChatStarterPrompts() -> [String] {
        let capabilities = AIChatModeCapabilities.current()
        
        // Build a pool of chat-specific starters and shuffle for variety
        var starterPool: [String] = []
        
        if capabilities.canExecutePaperTrade {
            starterPool.append(contentsOf: [
                "What trade should I practice next?",
                "Help me set up a paper trade",
                "How is my paper portfolio doing?",
                "Suggest a trading strategy to try"
            ])
        } else if capabilities.paperModeEnabled && !capabilities.paperAccessAvailable {
            starterPool.append(contentsOf: [
                "How do I unlock paper trading?",
                "Can you plan a trade setup I can review first?",
                "What can I do on the free tier right now?"
            ])
        } else if capabilities.demoModeEnabled {
            starterPool.append(contentsOf: [
                "Help me get started with CryptoSage",
                "What can paper trading help me learn?",
                "How do I connect my exchange?"
            ])
        }
        
        // Conversational starters (different from homepage info prompts)
        starterPool.append(contentsOf: [
            "What should I know about the market today?",
            "Teach me something about crypto trading",
            "What trading opportunities do you see?",
            "Help me understand my options",
            "What's the smart move right now?",
            "Walk me through a trade analysis",
            "What would you do in this market?",
            "Give me a market briefing",
            "What coins should I be watching?",
            "Help me improve my trading strategy",
            "What's the current market sentiment?",
            "Are there any alerts I should set up?",
            "What's happening with Bitcoin today?",
            "Should I be bullish or cautious right now?"
        ])
        
        // Shuffle and return the requested count
        return Array(starterPool.shuffled().prefix(promptCount))
    }
    
    private func scheduleScrollHintAutoHide() {
        showScrollHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showScrollHint = false
            }
        }
    }
    
    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            toastMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.25)) {
                toastMessage = nil
            }
        }
    }
    
    private func toastView(_ text: String) -> some View {
        let isDark = colorScheme == .dark
        let isAlertCreated = text.lowercased().contains("alert created")
        
        return HStack(spacing: 10) {
            // Success icon with animated checkmark effect
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isAlertCreated
                                ? [Color.green.opacity(0.25), Color.green.opacity(0.15)]
                                : [BrandGold.light.opacity(0.25), BrandGold.dark.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Image(systemName: isAlertCreated ? "bell.badge.checkmark.fill" : "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        isAlertCreated
                            ? AnyShapeStyle(Color.green)
                            : AnyShapeStyle(LinearGradient(
                                colors: [BrandGold.light, BrandGold.dark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    )
            }
            
            // Toast message
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isDark ? .white : DS.Adaptive.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isDark
                        ? Color(red: 0.12, green: 0.12, blue: 0.14)
                        : Color(red: 1.0, green: 0.995, blue: 0.985)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            isAlertCreated
                                ? Color.green.opacity(isDark ? 0.4 : 0.3)
                                : BrandGold.light.opacity(isDark ? 0.4 : 0.3),
                            DS.Adaptive.divider
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        // Accent bar on left edge for visual emphasis
        .overlay(alignment: .leading) {
            Capsule()
                .fill(
                    isAlertCreated
                        ? AnyShapeStyle(Color.green)
                        : AnyShapeStyle(LinearGradient(
                            colors: [BrandGold.light, BrandGold.dark],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                )
                .frame(width: 3)
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 340)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
    }

    private func clearActiveConversation() {
        guard let activeID = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == activeID }) else { return }
        var convo = conversations[index]
        convo.messages.removeAll()
        conversations[index] = convo
        saveConversations()
    }
}

// MARK: - Trade Configuration
extension AITabView {
    /// Check if the user's message indicates they want trading advice or a trade recommendation.
    /// Returns false for article summaries, general questions, research queries, etc.
    private func userAskedForTradeAdvice(_ userMessage: String) -> Bool {
        let lowered = userMessage.lowercased()
        let isExplicitBotFlow = lowered.contains("dca bot") ||
            lowered.contains("grid bot") ||
            lowered.contains("signal bot") ||
            (lowered.contains("bot") && lowered.contains("dca"))
        if isExplicitBotFlow { return false }
        
        // Explicit NON-trade intents — if the user asked for any of these, don't auto-detect trades
        let nonTradeIntents = [
            "summarize", "summary", "explain", "what is", "what are", "what does",
            "how does", "how do", "tell me about", "describe", "define", "meaning of",
            "read this", "article", "news", "research", "look up", "search for",
            "analyze this article", "break down this", "what happened",
            "who is", "history of", "compare", "difference between",
            "pros and cons", "advantages", "disadvantages",
            "translate", "rewrite", "rephrase"
        ]
        
        let hasNonTradeIntent = nonTradeIntents.contains { lowered.contains($0) }
        
        // Explicit trade intents — the user is actually asking for a trade
        let tradeIntents = [
            "should i buy", "should i sell", "trade", "trading",
            "execute", "place an order", "place a buy", "place a sell",
            "buy order", "sell order", "market order", "limit order",
            "how much should i buy", "how much should i sell",
            "entry point", "good time to buy", "good time to sell",
            "set up a trade", "make a trade", "open a position",
            "go long", "go short", "long position", "short position",
            "what should i buy", "what should i sell",
            "recommend a trade", "give me a trade", "suggest a trade",
            "paper trade", "paper trading"
        ]
        
        let hasTradeIntent = tradeIntents.contains { lowered.contains($0) }
        
        // If user explicitly asks for a trade, always allow
        if hasTradeIntent { return true }
        
        // If user has a non-trade intent, block trade detection
        if hasNonTradeIntent { return false }
        
        // Default: allow trade detection for ambiguous messages (e.g., just a coin name)
        return true
    }

    private var modeCapabilities: AIChatModeCapabilities {
        AIChatModeCapabilities.current()
    }
    
    private var majorDefaultSymbols: Set<String> {
        ["BTC", "ETH", "SOL"]
    }

    private func parserSymbolUniverse() -> Set<String> {
        var symbols = knownTickers
        symbols.formUnion(["BTC", "ETH", "SOL", "XRP", "ADA", "DOGE", "BNB", "AVAX", "DOT", "LINK"])
        let marketSymbols = MarketViewModel.shared.allCoins.map { $0.symbol.uppercased() }
        symbols.formUnion(marketSymbols)
        return Set(symbols.filter { $0.range(of: "^[A-Z0-9]{1,10}$", options: .regularExpression) != nil })
    }
    
    private func userRequestedTradeSymbols(in userMessage: String) -> Set<String> {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        let symbols = parserSymbolUniverse()
        let upper = trimmed.uppercased()
        var requested: Set<String> = []
        
        for symbol in symbols {
            if symbol.count <= 1 {
                // Avoid false positives from one-letter symbols in vague prose.
                let strictPattern = "\\(\\s*\(symbol)\\s*\\)|\\$\(symbol)\\b"
                if let regex = try? NSRegularExpression(pattern: strictPattern, options: []),
                   regex.firstMatch(in: upper, options: [], range: NSRange(upper.startIndex..., in: upper)) != nil {
                    requested.insert(symbol)
                }
                continue
            }
            
            let pattern = "\\b\(symbol)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: upper, options: [], range: NSRange(upper.startIndex..., in: upper)) != nil {
                requested.insert(symbol)
            }
        }
        
        // Support explicit asset names in user intent.
        let nameToSymbol: [String: String] = [
            "bitcoin": "BTC",
            "ethereum": "ETH",
            "solana": "SOL",
            "ripple": "XRP",
            "cardano": "ADA",
            "dogecoin": "DOGE",
            "binance": "BNB",
            "avalanche": "AVAX",
            "polkadot": "DOT",
            "chainlink": "LINK"
        ]
        let lower = trimmed.lowercased()
        for (name, symbol) in nameToSymbol where lower.contains(name) {
            requested.insert(symbol)
        }
        
        return requested
    }
    
    private func constrainTradeConfigToUserIntent(_ config: AITradeConfig, userMessage: String) -> AITradeConfig? {
        let requestedSymbols = userRequestedTradeSymbols(in: userMessage)
        let symbol = config.symbol.uppercased()
        
        if !requestedSymbols.isEmpty {
            return requestedSymbols.contains(symbol) ? config : nil
        }
        
        // Vague prompts: allow majors only; coerce other symbols to a safe major default.
        if majorDefaultSymbols.contains(symbol) {
            return config
        }
        let fallbackSymbol = safeDefaultTradeSymbol(for: userMessage)
        
        return AITradeConfig(
            symbol: fallbackSymbol,
            quoteCurrency: ComplianceManager.shared.isUSUser ? "USD" : "USDT",
            direction: config.direction,
            orderType: .market,
            amount: config.amount,
            isUSDAmount: config.isUSDAmount
        )
    }
    
    private func safeDefaultTradeSymbol(for userMessage: String) -> String {
        let lowered = userMessage.lowercased()
        if lowered.contains("eth") || lowered.contains("ethereum") { return "ETH" }
        if lowered.contains("sol") || lowered.contains("solana") { return "SOL" }
        return "BTC"
    }

    private func hasStrongTradeAction(in text: String) -> Bool {
        let lowercased = text.lowercased()
        let strongTradeIndicators = [
            "trade suggestion:", "suggestion: buy", "suggestion: sell",
            "i recommend buying", "i recommend selling",
            "i suggest buying", "i suggest selling",
            "i'd suggest buying", "i'd suggest selling",
            "i would suggest buying", "i would suggest selling",
            "consider buying", "consider selling",
            "you could buy", "you could sell",
            "buy setup", "sell setup",
            "entry:", "entry point", "entry zone",
            "limit buy order", "limit sell order",
            "market buy order", "market sell order",
            "place a buy order", "place a sell order",
            "place an order to buy", "place an order to sell",
            "execute trade button", "execute a buy", "execute a sell",
            "tap the button below to", "tap execute",
            "here's a trade", "here's the trade",
            "execute this trade", "go ahead and execute",
            "ready to execute", "set up this trade",
            "recommended trade:", "trade recommendation:"
        ]
        if strongTradeIndicators.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let actionPattern = "(?:buy|sell|long|short|entry|stop\\s*loss|take\\s*profit).{0,60}(?:\\$?[0-9]+(?:\\.[0-9]+)?|[A-Z]{1,10})"
        if let regex = try? NSRegularExpression(pattern: actionPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
        return false
    }

    private func sanitizePositiveNumber(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "%", with: "")
        guard let number = Double(cleaned), number > 0, number.isFinite else { return nil }
        return cleaned
    }

    private func validateTradeConfig(_ config: AITradeConfig) -> AITradeConfig? {
        let symbol = config.symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard symbol.range(of: "^[A-Z0-9]{1,10}$", options: .regularExpression) != nil else { return nil }

        let amount = sanitizePositiveNumber(config.amount)
        let price = sanitizePositiveNumber(config.price)
        let stopLoss = sanitizePositiveNumber(config.stopLoss)
        let takeProfit = sanitizePositiveNumber(config.takeProfit)

        if config.orderType == .limit && price == nil {
            return nil
        }

        return AITradeConfig(
            symbol: symbol,
            quoteCurrency: config.quoteCurrency,
            direction: config.direction,
            orderType: config.orderType,
            amount: amount,
            isUSDAmount: config.isUSDAmount,
            price: price,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            leverage: config.leverage
        )
    }

    private func assignDetectedTradeConfig(_ config: AITradeConfig) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.detectedTradeConfig = config
            }
        }
    }

    private func buildPartialTradeConfig(from text: String, userMessage: String) -> AITradeConfig? {
        let lowercased = text.lowercased()
        let symbols = Array(parserSymbolUniverse()).sorted { $0.count > $1.count }
        var detectedSymbol: String?
        let requestedSymbols = userRequestedTradeSymbols(in: userMessage)

        let actionSymbolPatterns = [
            "(?:buy|sell|long|short|entry|setup|trade)\\s+(?:for\\s+)?([A-Z0-9]{1,10})\\b",
            "([A-Z0-9]{1,10})\\s+(?:buy|sell|long|short|trade)"
        ]

        for pattern in actionSymbolPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let symbolRange = Range(match.range(at: 1), in: text) {
                let candidate = String(text[symbolRange]).uppercased()
                if symbols.contains(candidate) {
                    detectedSymbol = candidate
                    break
                }
            }
        }
        
        // Handle explicit Name (SYM) mentions, e.g. "MemeCore (M)".
        if detectedSymbol == nil,
           let regex = try? NSRegularExpression(pattern: "[A-Za-z][A-Za-z0-9\\-\\s]{1,40}\\(\\s*([A-Z0-9]{1,10})\\s*\\)", options: .caseInsensitive),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           let symbolRange = Range(match.range(at: 1), in: text) {
            let candidate = String(text[symbolRange]).uppercased()
            if symbols.contains(candidate) {
                detectedSymbol = candidate
            }
        }

        if detectedSymbol == nil, requestedSymbols.isEmpty {
            detectedSymbol = safeDefaultTradeSymbol(for: userMessage)
        }
        
        guard let symbol = detectedSymbol else { return nil }
        if !requestedSymbols.isEmpty && !requestedSymbols.contains(symbol) { return nil }
        if requestedSymbols.isEmpty && !majorDefaultSymbols.contains(symbol) {
            detectedSymbol = safeDefaultTradeSymbol(for: userMessage)
        }
        guard let finalSymbol = detectedSymbol else { return nil }
        let direction: AITradeConfig.TradeDirection = (lowercased.contains("sell") || lowercased.contains("short")) ? .sell : .buy
        let quote = ComplianceManager.shared.isUSUser ? "USD" : "USDT"

        return AITradeConfig(
            symbol: finalSymbol,
            quoteCurrency: quote,
            direction: direction,
            orderType: .market
        )
    }
    
    /// Parse AI response for trade recommendations using natural language detection
    /// - Parameters:
    ///   - text: The AI's response text
    ///   - userMessage: The original user message (used to check intent)
    private func parseTradeConfigFromResponse(_ text: String, userMessage: String = "") {
        // GATE 1: Check if user actually asked for trading advice
        // Skip trade detection for article summaries, research queries, explanations, etc.
        if !userMessage.isEmpty && !userAskedForTradeAdvice(userMessage) {
            #if DEBUG
            print("[AI Trade] Skipping trade detection — user intent is non-trade: \(userMessage.prefix(60))")
            #endif
            return
        }
        
        // First try to parse any JSON tags (various formats the AI might use)
        if let config = parseTradeConfigFromTags(text),
           let validated = validateTradeConfig(config),
           let constrained = constrainTradeConfigToUserIntent(validated, userMessage: userMessage) {
            assignDetectedTradeConfig(constrained)
            #if DEBUG
            print("[AI Trade] Detected trade config from tags: \(constrained.symbol) \(constrained.direction) \(constrained.orderType)")
            #endif
            return
        }
        
        // GATE 2: Natural language detection for explicit setup recommendations.
        let hasStrongTradeIntent = hasStrongTradeAction(in: text)
        guard hasStrongTradeIntent else { return }
        
        // Extract trade details from natural language
        if let config = extractTradeFromNaturalLanguage(text),
           let validated = validateTradeConfig(config),
           let constrained = constrainTradeConfigToUserIntent(validated, userMessage: userMessage) {
            assignDetectedTradeConfig(constrained)
            #if DEBUG
            print("[AI Trade] Extracted trade from natural language: \(constrained.symbol) \(constrained.direction) \(constrained.orderType)")
            #endif
            return
        }

        // Fallback: allow minimal setup card when the AI clearly proposes a trade but omitted details.
        if let fallback = buildPartialTradeConfig(from: text, userMessage: userMessage),
           let validated = validateTradeConfig(fallback),
           let constrained = constrainTradeConfigToUserIntent(validated, userMessage: userMessage) {
            assignDetectedTradeConfig(constrained)
            #if DEBUG
            print("[AI Trade] Built partial trade config fallback: \(constrained.symbol) \(constrained.direction)")
            #endif
        }
    }
    
    /// Try to parse trade config from various tag formats
    private func parseTradeConfigFromTags(_ text: String) -> AITradeConfig? {
        // Try different tag variations
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
    
    /// Extract trade config from natural language response
    private func extractTradeFromNaturalLanguage(_ text: String) -> AITradeConfig? {
        let lowercased = text.lowercased()
        let uppercased = text.uppercased()
        
        // Detect symbol FIRST — we need a specific coin to even consider a trade
        let symbols = parserSymbolUniverse()
        let symbolNames: [String: String] = [
            "Bitcoin": "BTC", "Ethereum": "ETH", "Solana": "SOL", "Cardano": "ADA",
            "Ripple": "XRP", "Polkadot": "DOT", "Avalanche": "AVAX", "Polygon": "MATIC",
            "Chainlink": "LINK", "Uniswap": "UNI", "Cosmos": "ATOM", "Litecoin": "LTC",
            "Dogecoin": "DOGE", "Shiba": "SHIB", "Binance": "BNB",
            "Celestia": "TIA", "Injective": "INJ", "Arbitrum": "ARB", "Optimism": "OP",
            "Sui": "SUI", "Sei": "SEI", "Aptos": "APT"
        ]
        
        var detectedSymbol: String? = nil
        
        // PRIORITY 1: Look for "Trade Suggestion: Buy/Sell SYMBOL" pattern (exact match from structured AI output)
        let tradeSuggestionPattern = "(?:trade\\s*suggestion|trade\\s*recommendation)\\s*:?\\s*(?:buy|sell|purchase)\\s+([A-Z0-9]{1,10})"
        if let regex = try? NSRegularExpression(pattern: tradeSuggestionPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           let symbolRange = Range(match.range(at: 1), in: text) {
            let potentialSymbol = String(text[symbolRange]).uppercased()
            if symbols.contains(potentialSymbol) {
                detectedSymbol = potentialSymbol
            }
        }
        
        // PRIORITY 2: Look for DIRECT action + symbol patterns (the AI is explicitly recommending a trade)
        // Only match when action words are directly adjacent to the symbol — not separated by paragraphs of analysis
        if detectedSymbol == nil {
            let actionPatterns = [
                // "recommend buying SOL", "suggest selling ETH" — explicit personal recommendation
                "(?:recommend|suggest|recommending|suggesting)\\s+(?:buying|selling|to\\s+buy|to\\s+sell)\\s+(?:\\$[\\d,]+(?:\\.\\d+)?\\s*(?:of|worth\\s*of)?\\s*)?([A-Z0-9]{1,10})\\b",
                // "buy $100 of BTC", "sell $500 worth of ETH" — action with amount
                "(?:buy|sell|purchase)\\s+\\$[\\d,]+(?:\\.\\d+)?\\s*(?:of|worth\\s*of)\\s+([A-Z0-9]{1,10})\\b",
                // "place a buy order for SOL" — order-specific language
                "(?:place\\s+(?:a|an)\\s+)?(?:buy|sell|market|limit)\\s+order\\s+(?:for|on)\\s+([A-Z0-9]{1,10})\\b"
            ]
            
            for pattern in actionPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
                   let symbolRange = Range(match.range(at: 1), in: text) {
                    let potentialSymbol = String(text[symbolRange]).uppercased()
                    if symbols.contains(potentialSymbol) {
                        detectedSymbol = potentialSymbol
                        break
                    }
                }
            }
        }

        // PRIORITY 2.5: Handle coin-name-with-symbol format, e.g. "MemeCore (M)".
        if detectedSymbol == nil {
            let nameWithTickerPattern = "[A-Za-z][A-Za-z0-9\\-\\s]{1,40}\\(\\s*([A-Z0-9]{1,10})\\s*\\)"
            if let regex = try? NSRegularExpression(pattern: nameWithTickerPattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let symbolRange = Range(match.range(at: 1), in: text) {
                let potentialSymbol = String(text[symbolRange]).uppercased()
                if symbols.contains(potentialSymbol) {
                    detectedSymbol = potentialSymbol
                }
            }
        }
        
        // PRIORITY 3: Look for full coin names directly after action words
        if detectedSymbol == nil {
            for (name, symbol) in symbolNames {
                // Only match direct recommendations, not general mentions
                let namePattern = "(?:recommend|suggest|recommending|suggesting)\\s+(?:buying|selling|to\\s+buy|to\\s+sell)\\s+(?:\\$[\\d,]+(?:\\.\\d+)?\\s*(?:of|worth)?\\s*)?\(name)"
                if let regex = try? NSRegularExpression(pattern: namePattern, options: .caseInsensitive),
                   regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil {
                    detectedSymbol = symbol
                    break
                }
            }
        }
        
        // PRIORITY 4: Look for "Buy/Sell X SYMBOL" patterns in structured recommendation blocks
        if detectedSymbol == nil {
            let structuredPatterns = [
                // "Buy 0.5 BTC", "Sell 100 SOL" — direct quantity trades
                "(?:buy|sell)\\s+([0-9]+(?:\\.[0-9]+)?)\\s+([A-Z0-9]{1,10})\\b",
                // "$100 of BTC" near an explicit trade context
                "\\$[\\d,]+(?:\\.\\d+)?\\s+(?:of|worth\\s*of)\\s+([A-Z0-9]{1,10})\\b"
            ]
            
            for pattern in structuredPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
                    // Get the last capture group (symbol is always last)
                    let lastGroup = match.numberOfRanges - 1
                    if let symbolRange = Range(match.range(at: lastGroup), in: text) {
                        let potentialSymbol = String(text[symbolRange]).uppercased()
                        if symbols.contains(potentialSymbol) {
                            detectedSymbol = potentialSymbol
                            break
                        }
                    }
                }
            }
        }
        
        // NO MORE FALLBACK — removed Priority 5 "closest symbol to action word" which was
        // too aggressive and matched symbols mentioned in general analysis/articles.
        // If we can't find a symbol directly attached to a trade recommendation, we don't guess.
        
        guard let symbol = detectedSymbol else { return nil }
        
        // Detect direction — require it NEAR the detected symbol, not just anywhere in text
        // This prevents "investors who buy Bitcoin" in paragraph 1 from making a TIA sell into a TIA buy
        let directionWindow = 120 // characters before/after symbol to look for direction
        var direction: AITradeConfig.TradeDirection = .buy // default
        
        if let symbolRange = uppercased.range(of: symbol) {
            let symbolIdx = uppercased.distance(from: uppercased.startIndex, to: symbolRange.lowerBound)
            let windowStart = max(0, symbolIdx - directionWindow)
            let windowEnd = min(lowercased.count, symbolIdx + directionWindow)
            let startIdx = lowercased.index(lowercased.startIndex, offsetBy: windowStart)
            let endIdx = lowercased.index(lowercased.startIndex, offsetBy: windowEnd)
            let nearby = String(lowercased[startIdx..<endIdx])
            
            let isBuyNearby = nearby.contains("buy") || nearby.contains("purchase") || nearby.contains("buying") || nearby.contains("long")
            let isSellNearby = nearby.contains("sell") || nearby.contains("selling") || nearby.contains("short")
            
            if isSellNearby && !isBuyNearby {
                direction = .sell
            } else {
                direction = .buy  // default to buy if ambiguous
            }
        }
        
        // Detect quote currency (trading pair)
        var quoteCurrency: String? = nil
        let quotePatterns = ["USDT", "USD", "BUSD", "USDC", "FDUSD"]
        // Check for explicit pair notation (e.g., "BTC/USDT", "BTC-USD", "BTCUSDT")
        for quote in quotePatterns {
            if uppercased.contains("\(symbol)/\(quote)") ||
               uppercased.contains("\(symbol)-\(quote)") ||
               uppercased.contains("\(symbol)\(quote)") ||
               (uppercased.contains(quote) && !quotePatterns.dropFirst().contains(quote)) {
                quoteCurrency = quote
                break
            }
        }
        // Default based on region if not detected
        if quoteCurrency == nil {
            quoteCurrency = ComplianceManager.shared.isUSUser ? "USD" : "USDT"
        }
        
        // Detect order type
        let isLimit = lowercased.contains("limit order") || 
                      lowercased.contains("limit buy") ||
                      lowercased.contains("limit sell")
        let orderType: AITradeConfig.OrderType = isLimit ? .limit : .market
        
        // Extract amount - detect if it's USD amount or quantity
        // IMPORTANT: Only extract amounts that are CLEARLY trade amounts, not prices, predictions, or market data
        var amount: String? = nil
        var isUSDAmount = false
        
        // Look for USD amounts that are explicitly part of a trade recommendation
        // Pattern: "$X,XXX" that appears directly after trade action words (buy/sell/purchase/invest)
        let tradeAmountPatterns = [
            // "buy $1,000 of", "sell $500 worth", "invest $2,000 in", "purchase $100 of"
            "(?:buy|sell|purchase|invest|allocate|use|spending|spend)\\s+\\$([0-9,]+(?:\\.\\d+)?)",
            // "$1,000 worth of SYMBOL", "$500 of SYMBOL"
            "\\$([0-9,]+(?:\\.\\d+)?)\\s*(?:worth\\s*of|of)\\s*(?:\(symbol))",
            // "Trade Suggestion: Buy SYMBOL at market — $1,000"
            "(?:trade\\s*suggestion|recommendation).*?\\$([0-9,]+(?:\\.\\d+)?)"
        ]
        
        for pattern in tradeAmountPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let amountRange = Range(match.range(at: 1), in: text) {
                let amountStr = String(text[amountRange]).replacingOccurrences(of: ",", with: "")
                if let amountVal = Double(amountStr), amountVal > 0 && amountVal < 1_000_000 {
                    amount = amountStr
                    isUSDAmount = true
                    break
                }
            }
        }
        
        // If no USD amount found, look for explicit quantity (e.g., "buy 0.5 BTC", "sell 1 ETH")
        // Must be directly adjacent to the symbol — not just any number near the symbol
        if amount == nil {
            let quantityPattern = "(?:buy|sell|purchase|acquire)\\s+([0-9]+(?:\\.[0-9]+)?)\\s*\(symbol)"
            if let regex = try? NSRegularExpression(pattern: quantityPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let qtyRange = Range(match.range(at: 1), in: text) {
                let digits = String(text[qtyRange])
                if let _ = Double(digits) {
                    amount = digits
                    isUSDAmount = false
                }
            }
        }
        
        // Extract price for limit orders
        var price: String? = nil
        if isLimit {
            // Try multiple patterns for price extraction (order matters - more specific first)
            let pricePatterns = [
                // "at the current price of $3,322.21" or "at the price of $3,322.21"
                "(?:at\\s+)?(?:the\\s+)?(?:current\\s+)?price\\s+(?:of\\s+)?\\$([0-9,]+(?:\\.\\d+)?)",
                // "at $3,322.21"
                "at\\s+\\$([0-9,]+(?:\\.\\d+)?)",
                // "@ $3,322.21" 
                "@\\s*\\$([0-9,]+(?:\\.\\d+)?)",
                // Just look for price followed by dollar amount as fallback
                "price[:\\s]+\\$([0-9,]+(?:\\.\\d+)?)"
            ]
            
            for pattern in pricePatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
                   let priceRange = Range(match.range(at: 1), in: text) {
                    price = String(text[priceRange]).replacingOccurrences(of: ",", with: "")
                    break
                }
            }
        }
        
        // Extract stop loss percentage
        var stopLoss: String? = nil
        if let range = text.range(of: "[0-9]+%\\s*stop", options: [.regularExpression, .caseInsensitive]) {
            let stopStr = String(text[range])
            stopLoss = stopStr.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "stop", with: "", options: .caseInsensitive)
        }
        
        // Extract take profit percentage
        var takeProfit: String? = nil
        if let range = text.range(of: "[0-9]+%\\s*(take\\s*profit|profit)", options: [.regularExpression, .caseInsensitive]) {
            let profitStr = String(text[range])
            takeProfit = profitStr.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        }
        
        // Extract leverage for derivatives/futures trades
        var leverage: Int? = nil
        let leveragePatterns = [
            // "with 10x leverage", "at 5x leverage"
            "(?:with|at|using)?\\s*(\\d+)x\\s*leverage",
            // "10x long", "5x short"
            "(\\d+)x\\s*(?:long|short)",
            // "leverage: 10x", "leverage of 5x"
            "leverage[:\\s]+(?:of\\s+)?(\\d+)x?",
            // "perpetual" or "futures" with leverage mentioned
            "(?:perpetual|futures|perp).*?(\\d+)x"
        ]
        
        for pattern in leveragePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let leverageRange = Range(match.range(at: 1), in: text),
               let lev = Int(text[leverageRange]) {
                leverage = lev
                break
            }
        }
        
        // Also detect if it's a derivatives trade without explicit leverage (default to 1x)
        let isDerivativesTrade = lowercased.contains("futures") || lowercased.contains("perpetual") || 
                                  lowercased.contains("perp") || lowercased.contains("leverage")
        if isDerivativesTrade && leverage == nil {
            leverage = 1  // Indicates it's a derivatives trade but at 1x
        }
        
        return AITradeConfig(
            symbol: symbol,
            quoteCurrency: quoteCurrency,
            direction: direction,
            orderType: orderType,
            amount: amount,
            isUSDAmount: isUSDAmount,
            price: price,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            leverage: leverage
        )
    }
}

// MARK: - Alert Suggestions
extension AITabView {
    /// Check if the user's message indicates they want alerts or price monitoring.
    private func userAskedForAlerts(_ userMessage: String) -> Bool {
        let lowered = userMessage.lowercased()
        
        // Explicit NON-alert intents
        let nonAlertIntents = [
            "summarize", "summary", "explain", "what is", "what are", "what does",
            "how does", "how do", "tell me about", "describe", "define",
            "read this", "article", "research", "look up", "search for",
            "who is", "history of", "compare", "difference between",
            "translate", "rewrite", "rephrase"
        ]
        
        let hasNonAlertIntent = nonAlertIntents.contains { lowered.contains($0) }
        
        // Explicit alert intents
        let alertIntents = [
            "alert", "notify", "notification", "watch", "monitor",
            "set up", "create", "remind me", "let me know",
            "price target", "support level", "resistance level",
            "when it hits", "when it reaches", "if it drops", "if it goes"
        ]
        
        let hasAlertIntent = alertIntents.contains { lowered.contains($0) }
        
        if hasAlertIntent { return true }
        if hasNonAlertIntent { return false }
        return true
    }
    
    /// Parse AI response for alert suggestions
    /// - Parameters:
    ///   - text: The AI's response text
    ///   - userMessage: The original user message (used to check intent)
    func parseAlertSuggestionFromResponse(_ text: String, userMessage: String = "") {
        let lowercased = text.lowercased()
        guard modeCapabilities.canCreateAlerts else { return }
        
        // GATE 1: Check if user actually asked for alerts/price monitoring
        if !userMessage.isEmpty && !userAskedForAlerts(userMessage) {
            #if DEBUG
            print("[AI Alert] Skipping alert detection — user intent is non-alert: \(userMessage.prefix(60))")
            #endif
            return
        }
        
        // First try to parse JSON tags (structured AI output — always trust these)
        if let suggestion = parseAlertSuggestionFromTags(text) {
            assignDetectedAlertSuggestion(suggestion)
            print("[AI Alert] Detected alert suggestion from tags: \(suggestion.symbol) \(suggestion.direction) \(suggestion.targetPrice)")
            return
        }
        
        // GATE 2: Natural language detection — require EXPLICIT alert-offering language from the AI
        // NOT general market commentary that happens to mention prices/levels
        let strongAlertIndicators = [
            // AI explicitly offering to create an alert
            "set up an alert", "set an alert", "create an alert",
            "i can set up an alert", "i'll set up an alert", "would you like me to set up an alert",
            "alert suggestion", "suggested alert",
            // AI explicitly offering notification
            "i can alert you", "i can notify you", "i'll notify you",
            "alert you when", "notify you when",
            // Direct recommendation to create an alert
            "recommend setting an alert", "suggest setting an alert",
            "i'd recommend an alert", "you might want an alert",
            "tap the button below to set an alert",
            "set a price alert", "price alert for", "monitor this level",
            "watch this level", "add an alert", "create price alert"
        ]
        
        let hasStrongAlertIntent = strongAlertIndicators.contains { lowercased.contains($0) }
        let hasAlertContext = lowercased.contains("alert") ||
            lowercased.contains("notify") ||
            lowercased.contains("watch") ||
            lowercased.contains("monitor") ||
            lowercased.contains("when it hits") ||
            lowercased.contains("when it reaches")
        guard hasStrongAlertIntent || hasAlertContext else { return }
        
        // Extract alert details from natural language
        if let suggestion = extractAlertFromNaturalLanguage(text) {
            assignDetectedAlertSuggestion(suggestion)
            print("[AI Alert] Extracted alert from natural language: \(suggestion.symbol) \(suggestion.direction) at \(suggestion.targetPrice)")
        }
    }

    private func assignDetectedAlertSuggestion(_ suggestion: AIAlertSuggestion) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.detectedAlertSuggestion = suggestion
            }
        }
    }
    
    /// Try to parse alert suggestion from JSON tags
    private func parseAlertSuggestionFromTags(_ text: String) -> AIAlertSuggestion? {
        let tagPatterns = [
            ("<alert_suggestion>", "</alert_suggestion>"),
            ("<alertsuggestion>", "</alertsuggestion>"),
            ("<alert-suggestion>", "</alert-suggestion>"),
            ("<alert_config>", "</alert_config>")
        ]
        
        for (startTag, endTag) in tagPatterns {
            if let startRange = text.range(of: startTag, options: .caseInsensitive),
               let endRange = text.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<text.endIndex) {
                let jsonString = String(text[startRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let jsonData = jsonString.data(using: .utf8),
                   let suggestion = try? JSONDecoder().decode(AIAlertSuggestion.self, from: jsonData) {
                    return suggestion
                }
            }
        }
        
        return nil
    }
    
    /// Extract alert suggestion from natural language response
    private func extractAlertFromNaturalLanguage(_ text: String) -> AIAlertSuggestion? {
        let lowercased = text.lowercased()
        let uppercased = text.uppercased()
        
        // Detect symbol
        let symbols = parserSymbolUniverse()
        
        var detectedSymbol: String? = nil
        
        // Look for symbol in context of alert/price discussion
        let alertSymbolPatterns = [
            "alert\\s+(?:for\\s+)?([A-Z0-9]{1,10})(?:\\b|$)",
            "([A-Z0-9]{1,10})\\s+(?:price\\s+)?alert",
            "(?:when|if)\\s+([A-Z0-9]{1,10})\\s+(?:goes|reaches|hits|drops)",
            "watch\\s+([A-Z0-9]{1,10})",
            "monitor\\s+([A-Z0-9]{1,10})"
        ]
        
        for pattern in alertSymbolPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let symbolRange = Range(match.range(at: 1), in: text) {
                let potentialSymbol = String(text[symbolRange]).uppercased()
                if symbols.contains(potentialSymbol) {
                    detectedSymbol = potentialSymbol
                    break
                }
            }
        }
        
        // Fallback: find any mentioned symbol using word boundaries
        // IMPORTANT: Use regex word boundaries to avoid false matches like "link" -> "LINK"
        if detectedSymbol == nil {
            for symbol in symbols.sorted() {
                // Use word boundary regex to ensure we match the crypto symbol, not English words
                // For example: "LINK" should not match "link between" or "linked"
                let wordBoundaryPattern = "\\b\(symbol)\\b"
                if let regex = try? NSRegularExpression(pattern: wordBoundaryPattern, options: []),
                   regex.firstMatch(in: uppercased, options: [], range: NSRange(uppercased.startIndex..., in: uppercased)) != nil {
                    // Additional context check: ensure the symbol appears near price/crypto context
                    // to avoid matching common English words that happen to be symbols (LINK, NEAR, DOT, etc.)
                    let contextWords = ["price", "crypto", "coin", "token", "buy", "sell", "trade", "market", 
                                        "alert", "usdt", "usd", "bitcoin", "ethereum", "blockchain", "$", "%"]
                    let hasRelevantContext = contextWords.contains { lowercased.contains($0) }
                    
                    // For ambiguous symbols (common English words), require context
                    let ambiguousSymbols = ["LINK", "NEAR", "DOT", "ATOM", "APT", "OP", "SUI", "SEI", "INJ", "WIF"]
                    if ambiguousSymbols.contains(symbol) && !hasRelevantContext {
                        continue // Skip ambiguous symbols without crypto context
                    }
                    
                    detectedSymbol = symbol
                    break
                }
            }
        }
        
        guard let symbol = detectedSymbol else { return nil }
        
        // Detect direction
        let isAbove = lowercased.contains("above") || lowercased.contains("rises") || 
                      lowercased.contains("goes up") || lowercased.contains("reaches") ||
                      lowercased.contains("hits") || lowercased.contains("breaks")
        let isBelow = lowercased.contains("below") || lowercased.contains("falls") || 
                      lowercased.contains("drops") || lowercased.contains("goes down") ||
                      lowercased.contains("dips")
        
        // Default to "above" if unclear
        let direction = isBelow && !isAbove ? "below" : "above"
        
        // Get current price early for validation
        let marketVM = MarketViewModel.shared
        let currentPrice = marketVM.allCoins.first(where: { $0.symbol.uppercased() == symbol })?.priceUsd
        
        // Extract target price - find ALL dollar amounts and pick the most reasonable one
        var candidatePrices: [Double] = []
        
        // Pattern: $XX,XXX or $XX.XX - but exclude if followed by trillion/billion/million
        let pricePattern = "\\$([0-9,]+(?:\\.[0-9]+)?)(?!\\s*(?:trillion|billion|million|T|B|M))"
        if let regex = try? NSRegularExpression(pattern: pricePattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let priceRange = Range(match.range(at: 1), in: text) {
                    let priceStr = String(text[priceRange]).replacingOccurrences(of: ",", with: "")
                    if let price = Double(priceStr), price > 0 {
                        candidatePrices.append(price)
                    }
                }
            }
        }
        
        // Also look for numbers near price-related words (excluding market cap contexts)
        let priceContextPattern = "(?:price|target|level|at|reaches|hits|alert)\\s*(?:of\\s*)?\\$?([0-9,]+(?:\\.[0-9]+)?)(?!\\s*(?:trillion|billion|million|T|B|M))"
        if let regex = try? NSRegularExpression(pattern: priceContextPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let priceRange = Range(match.range(at: 1), in: text) {
                    let priceStr = String(text[priceRange]).replacingOccurrences(of: ",", with: "")
                    if let price = Double(priceStr), price > 0, !candidatePrices.contains(price) {
                        candidatePrices.append(price)
                    }
                }
            }
        }
        
        // If we have a current price, filter out obviously wrong prices (more than 80% away)
        // and pick the most reasonable candidate
        var targetPrice: Double? = nil
        if let current = currentPrice, current > 0 {
            // Filter to prices within reasonable range (20% - 200% of current price)
            let reasonablePrices = candidatePrices.filter { price in
                let ratio = price / current
                return ratio >= 0.2 && ratio <= 5.0  // Between 20% and 500% of current price
            }
            
            // Pick the price closest to current price (most likely a realistic target)
            targetPrice = reasonablePrices.min(by: { abs($0 - current) < abs($1 - current) })
            
            // If no reasonable price found, don't suggest anything
            if targetPrice == nil {
                print("[AI Alert] No reasonable price found. Candidates: \(candidatePrices), current: \(current)")
                return nil
            }
        } else {
            // No current price available, use first candidate but be cautious
            targetPrice = candidatePrices.first
        }
        
        guard let price = targetPrice, price > 0 else { return nil }
        
        // Check if AI features should be enabled
        let enableAI = lowercased.contains("ai") || lowercased.contains("smart") || 
                       lowercased.contains("sentiment") || lowercased.contains("intelligent")
        
        // Generate a reason based on context
        var reason = "Price \(direction == "above" ? "target" : "support level")"
        if lowercased.contains("support") {
            reason = "Watch support level"
        } else if lowercased.contains("resistance") || lowercased.contains("breakout") {
            reason = "Watch resistance/breakout level"
        } else if lowercased.contains("take profit") {
            reason = "Take profit target"
        } else if lowercased.contains("stop loss") || lowercased.contains("protect") {
            reason = "Stop loss protection"
        } else if lowercased.contains("dip") || lowercased.contains("buy opportunity") {
            reason = "Potential buying opportunity"
        }
        
        return AIAlertSuggestion(
            symbol: symbol,
            targetPrice: price,
            direction: direction,
            reason: reason,
            enableAI: enableAI,
            currentPrice: currentPrice
        )
    }
    
    /// Create an alert from the AI suggestion
    func createAlertFromSuggestion(_ suggestion: AIAlertSuggestion) {
        NotificationsManager.shared.addAlertWithAI(
            symbol: suggestion.formattedSymbol,
            threshold: suggestion.targetPrice,
            isAbove: suggestion.isAbove,
            conditionType: suggestion.isAbove ? .priceAbove : .priceBelow,
            enablePush: true,
            enableEmail: false,
            enableTelegram: false,
            enableSentimentAnalysis: suggestion.enableAI,
            enableSmartTiming: suggestion.enableAI,
            enableAIVolumeSpike: suggestion.enableAI,
            frequency: .oneTime
        )
        
        // Show confirmation toast
        DispatchQueue.main.async {
            self.toastMessage = "Alert created for \(suggestion.symbol.uppercased()) at \(suggestion.formattedTargetPrice)"
            
            // Auto-dismiss toast after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if self.toastMessage?.contains(suggestion.symbol.uppercased()) == true {
                    self.toastMessage = nil
                }
            }
        }
        
        print("[AI Alert] Created alert: \(suggestion.formattedSymbol) \(suggestion.direction) \(suggestion.targetPrice)")
    }
}

// MARK: - Bot Configuration
extension AITabView {
    /// Parse AI response for bot configuration suggestions
    /// Check if the user's message indicates they want bot creation/configuration.
    private func userAskedForBot(_ userMessage: String) -> Bool {
        let lowered = userMessage.lowercased()
        
        // Explicit NON-bot intents
        let nonBotIntents = [
            "summarize", "summary", "explain", "what is", "what are",
            "read this", "article", "research", "look up", "search for",
            "who is", "history of", "translate", "rewrite"
        ]
        
        let hasNonBotIntent = nonBotIntents.contains { lowered.contains($0) }
        
        // Explicit bot intents
        let botIntents = [
            "bot", "dca", "dollar cost", "grid", "automate", "automated",
            "signal bot", "dca bot", "grid bot", "trading bot", "strategy bot"
        ]
        
        let hasBotIntent = botIntents.contains { lowered.contains($0) }
        
        if hasBotIntent { return true }
        if hasNonBotIntent { return false }
        return false
    }
    
    /// Parse AI response for bot configuration suggestions
    /// - Parameters:
    ///   - text: The AI's response text
    ///   - userMessage: The original user message (used to check intent)
    func parseBotConfigFromResponse(_ text: String, userMessage: String = "") {
        let lowercased = text.lowercased()
        
        // GATE 1: Check if user actually asked for bot creation
        if !userMessage.isEmpty && !userAskedForBot(userMessage) {
            #if DEBUG
            print("[AI Bot] Skipping bot detection — user intent is non-bot: \(userMessage.prefix(60))")
            #endif
            return
        }
        
        // First try to parse JSON tags
        if let config = parseBotConfigFromTags(text) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.detectedBotConfig = config
                }
            }
            print("[AI Bot] Detected bot config from tags: \(config.botType.displayName) \(config.tradingPair ?? config.marketTitle ?? "—")")
            return
        }
        
        // Natural language detection for bot creation — require explicit bot language
        let botIndicators = [
            // Bot creation phrases
            "set up a bot", "create a bot", "configure a bot", "make a bot",
            "set up a dca bot", "create a dca bot", "dca bot for",
            "set up a grid bot", "create a grid bot", "grid bot for",
            "set up a signal bot", "create a signal bot", "signal bot for",
            "set up a derivatives bot", "leverage bot", "futures bot",
            "prediction bot", "prediction market bot",
            // Bot recommendation phrases (AI explicitly offering a bot)
            "i've configured a", "i configured a", "here's the bot",
            "review and apply",
            "bot type:", "- bot type:"
        ]
        
        let hasBotIntent = botIndicators.contains { lowercased.contains($0) }
        let isDCAIntent = userMessage.lowercased().contains("dca") || userMessage.lowercased().contains("dollar cost")
        guard hasBotIntent || isDCAIntent else { return }
        
        if !hasBotIntent, isDCAIntent, let fallback = buildFallbackDCABotConfig(from: text, userMessage: userMessage) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.detectedBotConfig = fallback
                }
            }
            print("[AI Bot] Built fallback DCA bot config")
            return
        }
        
        // Extract bot details from natural language
        if let config = extractBotFromNaturalLanguage(text) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.detectedBotConfig = config
                }
            }
            print("[AI Bot] Extracted bot from natural language: \(config.botType.displayName)")
            return
        }
        
        // DCA consistency fallback: if intent is DCA bot but response is loosely structured,
        // still provide a clear bot CTA instead of silently dropping the setup.
        if isDCAIntent {
            if let fallback = buildFallbackDCABotConfig(from: text, userMessage: userMessage) {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        self.detectedBotConfig = fallback
                    }
                }
                print("[AI Bot] Built fallback DCA bot config")
            }
        }
    }
    
    private func buildFallbackDCABotConfig(from text: String, userMessage: String) -> AIBotConfig? {
        let symbols = parserSymbolUniverse()
        let candidateText = "\(userMessage) \(text)".uppercased()
        let preferred = ["BTC", "ETH", "SOL"]
        let selectedSymbol = preferred.first(where: { candidateText.contains($0) }) ?? "BTC"
        guard symbols.contains(selectedSymbol) else { return nil }
        
        let pair = "\(selectedSymbol)_\(ComplianceManager.shared.isUSUser ? "USD" : "USDT")"
        return AIBotConfig(
            botType: .dca,
            name: "\(selectedSymbol) DCA Bot",
            exchange: PaperTradingManager.isEnabled ? "Paper" : "Binance",
            direction: "Long",
            tradingPair: pair,
            baseOrderSize: "100",
            takeProfit: nil,
            stopLoss: nil,
            maxOrders: nil,
            priceDeviation: nil,
            lowerPrice: nil,
            upperPrice: nil,
            gridLevels: nil,
            maxInvestment: nil,
            leverage: nil,
            marginMode: nil,
            market: nil,
            platform: nil,
            marketId: nil,
            marketTitle: nil,
            outcome: nil,
            targetPrice: nil,
            betAmount: nil,
            category: nil
        )
    }
    
    /// Try to parse bot config from JSON tags or plain-text formats
    private func parseBotConfigFromTags(_ text: String) -> AIBotConfig? {
        // 1) Standard XML-style tags: <bot_config>{JSON}</bot_config>
        let tagPatterns = [
            ("<bot_config>", "</bot_config>"),
            ("<botconfig>", "</botconfig>"),
            ("<bot-config>", "</bot-config>"),
            ("<BOT_CONFIG>", "</BOT_CONFIG>")
        ]
        
        for (startTag, endTag) in tagPatterns {
            if let startRange = text.range(of: startTag, options: .caseInsensitive),
               let endRange = text.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<text.endIndex) {
                let jsonString = String(text[startRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let jsonData = jsonString.data(using: .utf8),
                   let config = try? JSONDecoder().decode(AIBotConfig.self, from: jsonData) {
                    return config
                }
            }
        }
        
        // 2) Plain-text formats: bot_config{key:value,...}/bot_config  or  bot_config{key:value,...}
        //    The AI sometimes outputs unquoted key:value pairs without XML tags.
        let plainTextPatterns = [
            // bot_config{...}/bot_config
            "bot_config\\{([^}]+)\\}/bot_config",
            // bot_config{...} (standalone)
            "bot_config\\{([^}]+)\\}",
            // bot_config(...)/bot_config
            "bot_config\\(([^)]+)\\)/bot_config",
            // bot_config(...)
            "bot_config\\(([^)]+)\\)"
        ]
        
        for pattern in plainTextPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let contentRange = Range(match.range(at: 1), in: text) {
                let rawContent = String(text[contentRange])
                if let config = parseUnquotedKeyValueConfig(rawContent) {
                    return config
                }
            }
        }
        
        return nil
    }
    
    /// Parse unquoted key:value pairs like "botType:signal,name:ETH Signal Bot,exchange:Paper,tradingPair:ETH_USDT"
    private func parseUnquotedKeyValueConfig(_ raw: String) -> AIBotConfig? {
        // Split by comma, then each part by the first colon
        var dict: [String: String] = [:]
        let parts = raw.components(separatedBy: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIdx])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = String(trimmed[trimmed.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && !value.isEmpty {
                dict[key] = value
            }
        }
        
        guard !dict.isEmpty else { return nil }
        
        // Map botType string to enum
        let botTypeStr = (dict["bottype"] ?? dict["bot_type"] ?? dict["type"] ?? "dca").lowercased()
        let botType: AIBotConfig.BotType
        switch botTypeStr {
        case "grid": botType = .grid
        case "signal": botType = .signal
        case "derivatives", "futures", "perp": botType = .derivatives
        case "predictionmarket", "prediction", "prediction_market": botType = .predictionMarket
        default: botType = .dca
        }
        
        // Parse leverage as Int if present
        var leverage: Int? = nil
        if let levStr = dict["leverage"] {
            leverage = Int(levStr.replacingOccurrences(of: "x", with: "", options: .caseInsensitive))
        }
        
        return AIBotConfig(
            botType: botType,
            name: dict["name"],
            exchange: dict["exchange"],
            direction: dict["direction"],
            tradingPair: dict["tradingpair"] ?? dict["trading_pair"] ?? dict["pair"],
            baseOrderSize: dict["baseordersize"] ?? dict["base_order_size"] ?? dict["ordersize"],
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
            market: dict["market"],
            platform: dict["platform"],
            marketId: dict["marketid"] ?? dict["market_id"],
            marketTitle: dict["markettitle"] ?? dict["market_title"],
            outcome: dict["outcome"],
            targetPrice: dict["targetprice"] ?? dict["target_price"],
            betAmount: dict["betamount"] ?? dict["bet_amount"],
            category: dict["category"]
        )
    }
    
    /// Extract bot config from natural language response
    private func extractBotFromNaturalLanguage(_ text: String) -> AIBotConfig? {
        let lowercased = text.lowercased()
        
        // Detect bot type
        var botType: AIBotConfig.BotType = .dca // Default to DCA
        
        if lowercased.contains("grid bot") || lowercased.contains("grid trading") ||
           (lowercased.contains("grid") && lowercased.contains("levels")) {
            botType = .grid
        } else if lowercased.contains("signal bot") || lowercased.contains("signal-based") ||
                  lowercased.contains("rsi bot") || lowercased.contains("macd bot") ||
                  lowercased.contains("indicator") {
            botType = .signal
        } else if lowercased.contains("derivatives") || lowercased.contains("futures bot") ||
                  lowercased.contains("leverage bot") || lowercased.contains("perpetual") {
            botType = .derivatives
        } else if lowercased.contains("prediction") || lowercased.contains("polymarket") ||
                  lowercased.contains("kalshi") {
            botType = .predictionMarket
        }
        
        // Detect trading pair
        var tradingPair: String? = nil
        let symbols = ["BTC", "ETH", "SOL", "ADA", "XRP", "DOT", "AVAX", "MATIC", "LINK", "UNI", "ATOM", "LTC", "DOGE", "SHIB", "BNB", "NEAR", "APT", "ARB", "OP", "SUI"]
        
        for symbol in symbols {
            let pairPatterns = [
                "\(symbol)/USDT", "\(symbol)_USDT", "\(symbol)-USDT",
                "\(symbol)/USD", "\(symbol)_USD", "\(symbol)-USD"
            ]
            for pattern in pairPatterns {
                if text.uppercased().contains(pattern) {
                    tradingPair = "\(symbol)_USDT"
                    break
                }
            }
            if tradingPair != nil { break }
            
            // Also check for just the symbol mentioned with "bot" context
            if lowercased.contains("\(symbol.lowercased()) bot") || 
               lowercased.contains("bot for \(symbol.lowercased())") ||
               lowercased.contains("dca \(symbol.lowercased())") ||
               lowercased.contains("\(symbol.lowercased()) dca") {
                tradingPair = "\(symbol)_USDT"
                break
            }
        }
        
        // Detect exchange
        var exchange: String? = nil
        let exchanges = ["Binance", "Binance US", "Coinbase", "Kraken", "KuCoin", "Bybit", "OKX", "Gate.io", "MEXC", "HTX", "Bitstamp", "Crypto.com", "Bitget", "Bitfinex"]
        for ex in exchanges {
            if lowercased.contains(ex.lowercased()) {
                exchange = ex
                break
            }
        }
        if exchange == nil {
            exchange = "Binance" // Default
        }
        
        // Extract bot name
        var botName: String? = nil
        let namePatterns = [
            "name:\\s*([^\\n,]+)",
            "bot name:\\s*([^\\n,]+)",
            "- name:\\s*([^\\n,]+)"
        ]
        for pattern in namePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let nameRange = Range(match.range(at: 1), in: text) {
                botName = String(text[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        // Extract base order size
        var baseOrderSize: String? = nil
        let orderSizePatterns = [
            "base order[:\\s]+\\$?([0-9,]+)",
            "order size[:\\s]+\\$?([0-9,]+)",
            "\\$([0-9,]+)\\s*(?:per|/)?\\s*(?:order|week|day|month)"
        ]
        for pattern in orderSizePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let sizeRange = Range(match.range(at: 1), in: text) {
                baseOrderSize = String(text[sizeRange]).replacingOccurrences(of: ",", with: "")
                break
            }
        }
        
        // Extract take profit
        var takeProfit: String? = nil
        let tpPatterns = [
            "take profit[:\\s]+([0-9.]+)%?",
            "tp[:\\s]+([0-9.]+)%?"
        ]
        for pattern in tpPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let tpRange = Range(match.range(at: 1), in: text) {
                takeProfit = String(text[tpRange])
                break
            }
        }
        
        // Extract stop loss
        var stopLoss: String? = nil
        let slPatterns = [
            "stop loss[:\\s]+([0-9.]+)%?",
            "sl[:\\s]+([0-9.]+)%?"
        ]
        for pattern in slPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let slRange = Range(match.range(at: 1), in: text) {
                stopLoss = String(text[slRange])
                break
            }
        }
        
        // Extract max orders
        var maxOrders: String? = nil
        let maxOrderPatterns = [
            "max orders[:\\s]+([0-9]+)",
            "maximum orders[:\\s]+([0-9]+)",
            "([0-9]+)\\s*(?:orders|purchases)\\s*(?:total|max)"
        ]
        for pattern in maxOrderPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let maxRange = Range(match.range(at: 1), in: text) {
                maxOrders = String(text[maxRange])
                break
            }
        }
        
        // Extract price deviation
        var priceDeviation: String? = nil
        let deviationPatterns = [
            "price deviation[:\\s]+([0-9.]+)%?",
            "deviation[:\\s]+([0-9.]+)%?"
        ]
        for pattern in deviationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let devRange = Range(match.range(at: 1), in: text) {
                priceDeviation = String(text[devRange])
                break
            }
        }
        
        // Extract grid-specific parameters
        var lowerPrice: String? = nil
        var upperPrice: String? = nil
        var gridLevels: String? = nil
        
        if botType == .grid {
            // Lower price
            if let regex = try? NSRegularExpression(pattern: "lower\\s*price[:\\s]+\\$?([0-9,]+)", options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                lowerPrice = String(text[range]).replacingOccurrences(of: ",", with: "")
            }
            
            // Upper price
            if let regex = try? NSRegularExpression(pattern: "upper\\s*price[:\\s]+\\$?([0-9,]+)", options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                upperPrice = String(text[range]).replacingOccurrences(of: ",", with: "")
            }
            
            // Grid levels
            if let regex = try? NSRegularExpression(pattern: "([0-9]+)\\s*(?:grid\\s*)?levels", options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                gridLevels = String(text[range])
            }
        }
        
        // Extract derivatives-specific parameters
        var leverage: Int? = nil
        var direction: String? = nil
        
        if botType == .derivatives {
            // Leverage
            if let regex = try? NSRegularExpression(pattern: "([0-9]+)x\\s*(?:leverage)?", options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                leverage = Int(text[range])
            }
            
            // Direction
            if lowercased.contains("long") {
                direction = "Long"
            } else if lowercased.contains("short") {
                direction = "Short"
            }
        }
        
        // Extract prediction market parameters
        var platform: String? = nil
        let marketTitle: String? = nil
        var outcome: String? = nil
        var betAmount: String? = nil
        let targetPrice: String? = nil
        
        if botType == .predictionMarket {
            if lowercased.contains("polymarket") {
                platform = "Polymarket"
            } else if lowercased.contains("kalshi") {
                platform = "Kalshi"
            }
            
            // Outcome
            if lowercased.contains("yes") && !lowercased.contains("no") {
                outcome = "YES"
            } else if lowercased.contains("no") && !lowercased.contains("yes") {
                outcome = "NO"
            }
            
            // Bet amount
            if let regex = try? NSRegularExpression(pattern: "bet\\s*(?:amount)?[:\\s]+\\$?([0-9,]+)", options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                betAmount = String(text[range]).replacingOccurrences(of: ",", with: "")
            }
        }
        
        // Must have at least a trading pair or it's a prediction market with platform
        guard tradingPair != nil || (botType == .predictionMarket && platform != nil) else {
            return nil
        }
        
        return AIBotConfig(
            botType: botType,
            name: botName,
            exchange: exchange,
            direction: direction,
            tradingPair: tradingPair,
            baseOrderSize: baseOrderSize,
            takeProfit: takeProfit,
            stopLoss: stopLoss,
            maxOrders: maxOrders,
            priceDeviation: priceDeviation,
            lowerPrice: lowerPrice,
            upperPrice: upperPrice,
            gridLevels: gridLevels,
            maxInvestment: nil,
            leverage: leverage,
            marginMode: leverage != nil ? "isolated" : nil,
            market: botType == .derivatives ? tradingPair?.replacingOccurrences(of: "_", with: "-") : nil,
            platform: platform,
            marketId: nil,
            marketTitle: marketTitle,
            outcome: outcome,
            targetPrice: targetPrice,
            betAmount: betAmount,
            category: nil
        )
    }
}

// MARK: - Strategy Configuration
extension AITabView {
    /// Parse AI response for strategy configuration tags
    /// Parse AI response for strategy configuration tags
    /// - Parameters:
    ///   - text: The AI's response text
    ///   - userMessage: The original user message (used to check intent)
    func parseStrategyConfigFromResponse(_ text: String, userMessage: String = "") {
        // GATE: Check if user actually asked for strategy/trading advice
        if !userMessage.isEmpty {
            let lowered = userMessage.lowercased()
            let nonStrategyIntents = [
                "summarize", "summary", "explain", "what is", "read this",
                "article", "research", "look up", "search for", "who is",
                "history of", "translate", "rewrite"
            ]
            let hasNonStrategyIntent = nonStrategyIntents.contains { lowered.contains($0) }
            if hasNonStrategyIntent {
                #if DEBUG
                print("[AI Strategy] Skipping strategy detection — user intent is non-strategy: \(userMessage.prefix(60))")
                #endif
                return
            }
        }
        
        // Try to parse from <strategy_config> tags
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
                    DispatchQueue.main.async {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            self.detectedStrategyConfig = config
                        }
                    }
                    print("[AI Strategy] Detected strategy config: \(config.name)")
                    return
                }
            }
        }
    }
}

// MARK: - Persistence
extension AITabView {
    private var legacyConversationsFile: String { "csai_conversations.json" }
    private var legacyLastActiveKey: String { "csai_last_active_conversation_id" }
    private var conversationScopeID: String {
        authManager.currentUser?.id ?? "guest"
    }
    private var conversationsFile: String { "csai_conversations_\(conversationScopeID).json" }
    private var lastActiveKey: String { "csai_last_active_conversation_id_\(conversationScopeID)" }

    private func saveConversations() {
        // Cap messages per conversation to avoid bloating storage
        let capped: [Conversation] = conversations.map { convo in
            var trimmed = convo
            if trimmed.messages.count > 200 {
                trimmed.messages = Array(trimmed.messages.suffix(200))
            }
            return trimmed
        }
        persistMessageImagesIfNeeded()
        CacheManager.shared.save(capped, to: conversationsFile)
        if let activeID = activeConversationID {
            UserDefaults.standard.set(activeID.uuidString, forKey: lastActiveKey)
        }
        
        // Sync to Firestore if authenticated
        Task { @MainActor in
            ConversationSyncService.shared.syncConversations(capped)
        }
    }

    private func loadConversations() {
        // Load from local cache deterministically (no scroll-time skip for critical user history).
        if let loaded: [Conversation] = CacheManager.shared.loadFromDocumentsOnly([Conversation].self, from: conversationsFile) {
            conversations = loaded
            normalizeConversationTitles()
        } else if conversationsFile != legacyConversationsFile,
                  let legacyLoaded: [Conversation] = CacheManager.shared.loadFromDocumentsOnly([Conversation].self, from: legacyConversationsFile) {
            // One-time migration from pre-scoped shared chat history.
            conversations = legacyLoaded
            normalizeConversationTitles()
            CacheManager.shared.save(legacyLoaded, to: conversationsFile)
            if UserDefaults.standard.string(forKey: lastActiveKey) == nil,
               let legacyActive = UserDefaults.standard.string(forKey: legacyLastActiveKey) {
                UserDefaults.standard.set(legacyActive, forKey: lastActiveKey)
            }
        }
        
        // Set up Firestore sync listener for cross-device updates
        // Note: No weak self needed - AITabView is a struct (value type), not a class
        ConversationSyncService.shared.onConversationsUpdated = { firestoreConversations in
            // Merge Firestore conversations with local ones
            // Local conversations with full message history take precedence
            // Firestore provides conversations from other devices
            self.mergeFirestoreConversations(firestoreConversations)
        }
        
        // Start Firestore sync if authenticated
        Task { @MainActor in
            ConversationSyncService.shared.startFirestoreSyncIfAuthenticated()
        }
    }

    private func reloadConversationsForCurrentUserScope() {
        // Avoid stale suggestions while switching conversation scope.
        activeAITask?.cancel()
        activeAITask = nil
        isThinking = false
        detectedTradeConfig = nil
        detectedAlertSuggestion = nil
        detectedBotConfig = nil
        detectedStrategyConfig = nil

        isLoadingConversations = true
        conversations = []
        activeConversationID = nil

        loadConversations()

        if conversations.isEmpty {
            let initialConvo = Conversation(title: "New Chat")
            conversations.append(initialConvo)
            activeConversationID = initialConvo.id
            saveConversations()
        } else if let idString = UserDefaults.standard.string(forKey: lastActiveKey),
                  let uuid = UUID(uuidString: idString),
                  conversations.contains(where: { $0.id == uuid }) {
            activeConversationID = uuid
        } else if let mostRecent = conversations.max(by: { ($0.lastMessageDate ?? $0.createdAt) < ($1.lastMessageDate ?? $1.createdAt) }) {
            activeConversationID = mostRecent.id
        }

        randomizePrompts()
        isLoadingConversations = false
    }
    
    /// Merge conversations from Firestore with local conversations
    /// Strategy: Local conversations with matching IDs keep their full message history
    /// Firestore conversations without local match are added (from other devices)
    private func mergeFirestoreConversations(_ firestoreConversations: [Conversation]) {
        var merged = conversations
        let localIDs = Set(conversations.map { $0.id })
        
        // Add conversations from Firestore that don't exist locally
        for firestoreConvo in firestoreConversations {
            if !localIDs.contains(firestoreConvo.id) {
                // This conversation is from another device
                merged.append(firestoreConvo)
            }
        }
        
        // Update local conversations if there are new ones from Firestore
        if merged.count > conversations.count {
            conversations = merged
            normalizeConversationTitles()
            // Save the merged list locally
            CacheManager.shared.save(conversations, to: conversationsFile)
        }
    }
    
    private func normalizeConversationTitles() {
        // Ensure all conversations have a reasonable, non-empty title
        for index in conversations.indices {
            let current = conversations[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty {
                if let firstText = conversations[index].messages.first?.text {
                    let trimmed = firstText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        conversations[index].title = String(trimmed.prefix(60))
                        continue
                    }
                }
                conversations[index].title = "New Chat"
            }
        }
    }

    private func persistMessageImagesIfNeeded() {
        // Walk through conversations and move any in-memory imageData to file paths
        for cIndex in conversations.indices {
            for mIndex in conversations[cIndex].messages.indices {
                var msg = conversations[cIndex].messages[mIndex]
                // If we already have a path or no data, continue
                if msg.imagePath != nil || msg.imageData == nil { continue }
                if let data = msg.imageData, let path = saveImageDataToDisk(data, suggestedName: msg.id.uuidString + ".jpg") {
                    msg.imagePath = path
                    msg.imageData = nil
                    conversations[cIndex].messages[mIndex] = msg
                }
            }
        }
    }

    private func saveImageDataToDisk(_ data: Data, suggestedName: String) -> String? {
        let fm = FileManager.default
        guard let doc = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = doc.appendingPathComponent("ChatImages", isDirectory: true)
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            print("[AIChatView] createDirectory error: \(error)")
            #endif
        }
        let fileURL = url.appendingPathComponent(suggestedName)
        do {
            try data.write(to: fileURL, options: [.atomic])
            return fileURL.lastPathComponent // store only the filename; we reconstruct full path when loading
        } catch {
            print("[AIChat] Failed to write image: \(error)")
            return nil
        }
    }

    // SAFETY FIX: Use safe directory accessor instead of force unwrap
    private func imageURL(for fileName: String) -> URL {
        return FileManager.documentsSubdirectory("ChatImages").appendingPathComponent(fileName)
    }
}

// PERFORMANCE FIX: Added throttling and thread safety to safe area preference keys to prevent
// "multiple updates per frame" warnings. Safe area insets rarely change,
// so we only update when there's a meaningful difference.
// THREAD SAFETY FIX: PreferenceKey reduce() can be called from background threads - use NSLock.
private struct TopSafeKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    private static let lock = NSLock()
    private static var _lastUpdateTime: CFTimeInterval = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        let now = CACurrentMediaTime()
        
        lock.lock()
        defer { lock.unlock() }
        
        // Throttle to ~5Hz (200ms between updates)
        guard now - _lastUpdateTime >= 0.2 else { return }
        // Ignore small changes (less than 1 point)
        guard abs(next - value) > 1 else { return }
        value = next
        _lastUpdateTime = now
    }
}

private struct BottomSafeKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    private static let lock = NSLock()
    private static var _lastUpdateTime: CFTimeInterval = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        let now = CACurrentMediaTime()
        
        lock.lock()
        defer { lock.unlock() }
        
        // Throttle to ~5Hz (200ms between updates)
        guard now - _lastUpdateTime >= 0.2 else { return }
        // Ignore small changes (less than 1 point)
        guard abs(next - value) > 1 else { return }
        value = next
        _lastUpdateTime = now
    }
}

private struct InputOverlayHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Micro Interactions
struct PressableScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Helpers (Attachments & Disk Image Loading)
struct DiskImageView: View {
    let url: URL
    @State private var uiImage: UIImage? = nil

    var body: some View {
        Group {
            if let ui = uiImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
        }
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        do {
            let data = try Data(contentsOf: url)
            if let img = UIImage(data: data) {
                self.uiImage = img
            }
        } catch {
            // Silent fail; show placeholder
        }
    }
}

struct AttachmentChip: View {
    let image: UIImage
    var onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.black)
                    .background(Circle().fill(Color.white))
            }
            .offset(x: 6, y: -6)
        }
    }
}

struct AnimatedTypingIndicator: View {
    var dotColor: Color = .white
    var dotSize: CGFloat = 6
    @State private var step: Int = 0
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(dotColor).frame(width: dotSize, height: dotSize).opacity(step == 0 ? 1 : 0.35)
            Circle().fill(dotColor).frame(width: dotSize, height: dotSize).opacity(step == 1 ? 1 : 0.35)
            Circle().fill(dotColor).frame(width: dotSize, height: dotSize).opacity(step == 2 ? 1 : 0.35)
        }
        .task {
            while true {
                try? await Task.sleep(nanoseconds: 450_000_000)
                step = (step + 1) % 3
            }
        }
    }
}

struct GoldSweepBorder: View {
    var cornerRadius: CGFloat = 8
    @State private var phase: CGFloat = 0
    private let seg: CGFloat = 0.28
    var body: some View {
        ZStack {
            // Base soft glow
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(BrandGold.light.opacity(0.45), lineWidth: 1.25)
            // Moving highlight segment (handles wrap-around)
            let end1 = min(phase + seg, 1)
            let overflow = max(phase + seg - 1, 0)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .trim(from: phase, to: end1)
                .stroke(
                    LinearGradient(colors: [
                        BrandGold.light.opacity(0.0),
                        BrandGold.light,
                        BrandGold.dark,
                        BrandGold.light.opacity(0.0)
                    ], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .compositingGroup()
            if overflow > 0 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .trim(from: 0, to: overflow)
                    .stroke(
                        LinearGradient(colors: [
                            BrandGold.light.opacity(0.0),
                            BrandGold.light,
                            BrandGold.dark,
                            BrandGold.light.opacity(0.0)
                        ], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .compositingGroup()
            }
        }
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
    }
}

// MARK: - Long Conversation Hint
/// Subtle hint shown when a conversation gets long, suggesting the user may want to start fresh
struct LongConversationHint: View {
    let onStartNewChat: () -> Void
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                // LIGHT MODE FIX: Deeper amber
                .foregroundColor(isDark ? BrandColors.goldLight : Color(red: 0.78, green: 0.60, blue: 0.10))
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Long conversation")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                
                Text("For best results, start a new chat")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onStartNewChat) {
                Text("New Chat")
                    .font(.system(size: 12, weight: .semibold))
                    // LIGHT MODE FIX: Adaptive text on gold button
                    .foregroundColor(isDark ? .white : .white.opacity(0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                isDark
                                    ? BrandColors.goldDiagonalGradient
                                    : LinearGradient(colors: [Color(red: 0.78, green: 0.60, blue: 0.10), Color(red: 0.65, green: 0.48, blue: 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                    )
            }
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDark ? Color(white: 0.15) : Color(white: 0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BrandColors.goldLight.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - StreamingTextView (AI text display)
/// Displays AI response text. The progressive text appearance during streaming
/// provides sufficient visual feedback - no cursor needed (matches ChatGPT/Claude).
struct StreamingTextView: View {
    let text: String
    let isStreaming: Bool
    let textColor: Color
    let fontSize: CGFloat
    
    init(text: String, isStreaming: Bool, textColor: Color = .primary, fontSize: CGFloat = 16) {
        self.text = text
        self.isStreaming = isStreaming
        self.textColor = textColor
        self.fontSize = fontSize
    }
    
    var body: some View {
        // Simple text display - streaming text appearance is the visual feedback
        Text(text)
            .font(.system(size: fontSize))
            .foregroundColor(textColor)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - QuickReplyChip (gold prompt button with press feedback)
// FIX: Replaced DragGesture(minimumDistance: 0) with Button + ButtonStyle.
// The old DragGesture captured ALL touches (including scroll starts) and fired
// onTap() when the finger lifted, making it impossible to scroll the prompt bar
// without accidentally sending a prompt. SwiftUI's Button natively cancels its
// tap gesture when the system detects a scroll, solving the conflict.

/// Custom ButtonStyle that provides scale + brightness press feedback
struct ChipPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .brightness(configuration.isPressed ? 0.1 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct QuickReplyChip: View {
    let text: String
    let chipGradient: LinearGradient
    let chipBgOpacity: Double
    let strokeOpacity: Double
    let isDark: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button {
            if !isDisabled { onTap() }
        } label: {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                // LIGHT MODE FIX: Adaptive text color - dark amber-brown in light mode
                .foregroundColor(isDark ? .black : Color(red: 0.35, green: 0.25, blue: 0.02))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    ZStack {
                        // Base gradient fill
                        RoundedRectangle(cornerRadius: 15)
                            .fill(chipGradient)
                            .opacity(chipBgOpacity)
                        // Glass top shine
                        RoundedRectangle(cornerRadius: 15)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(isDark ? 0.10 : 0.38), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(
                            LinearGradient(
                                colors: isDark
                                    ? [BrandColors.goldLight.opacity(strokeOpacity), BrandColors.goldBase.opacity(strokeOpacity * 0.4)]
                                    : [Color(red: 0.80, green: 0.65, blue: 0.25).opacity(0.35), Color(red: 0.80, green: 0.65, blue: 0.25).opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isDark ? 1 : 0.8
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(ChipPressButtonStyle())
        .opacity(isDisabled ? 0.5 : 1)
        .allowsHitTesting(!isDisabled)
    }
}

// MARK: - ThinkingBubble (AI typing indicator)
struct ThinkingBubble: View {
    @State private var dotPhase: Int = 0
    @State private var animationTimer: Timer? = nil
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(alignment: .center) {
            // Animated dots only - clean and minimal
            // LIGHT MODE FIX: Deeper amber dots in light mode
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(
                            colorScheme == .dark
                                ? BrandGold.light.opacity(dotPhase == index ? 1.0 : 0.35)
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
                    .fill(DS.Adaptive.chipBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            // LIGHT MODE FIX: Adaptive stroke color
                            .stroke(
                                colorScheme == .dark
                                    ? BrandGold.light.opacity(0.25)
                                    : Color(red: 0.78, green: 0.60, blue: 0.10).opacity(0.20),
                                lineWidth: colorScheme == .dark ? 1 : 0.5
                            )
                    )
            )
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
    }
    
    private func startAnimation() {
        animationTimer?.invalidate()
        // NOTE: SwiftUI View structs use [self] - timer invalidated in onDisappear
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [self] _ in
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

// MARK: - ToolExecutionBubble (shows which AI tool is running)
struct ToolExecutionBubble: View {
    let toolName: String
    @State private var dotPhase: Int = 0
    @State private var animationTimer: Timer? = nil
    @Environment(\.colorScheme) private var colorScheme
    
    private var displayText: String {
        switch toolName {
        case "web_search":
            return "Searching the web"
        case "read_url":
            return "Reading article"
        case "get_price":
            return "Getting live price"
        case "get_market_overview":
            return "Getting market data"
        default:
            return "Processing"
        }
    }
    
    private var iconName: String {
        switch toolName {
        case "web_search":
            return "globe"
        case "read_url":
            return "doc.text"
        case "get_price":
            return "chart.line.uptrend.xyaxis"
        case "get_market_overview":
            return "chart.bar.fill"
        default:
            return "gearshape"
        }
    }
    
    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                // Tool icon with pulse animation
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BrandGold.light)
                    .scaleEffect(dotPhase == 1 ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.4), value: dotPhase)
                
                // Status text
                Text(displayText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                // Animated dots
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(BrandGold.light.opacity(dotPhase == index ? 1.0 : 0.35))
                            .frame(width: 6, height: 6)
                            .scaleEffect(dotPhase == index ? 1.15 : 1.0)
                            .animation(.easeInOut(duration: 0.35), value: dotPhase)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.chipBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(BrandGold.light.opacity(colorScheme == .dark ? 0.3 : 0.4), lineWidth: colorScheme == .dark ? 1 : 0.5)
                    )
            )
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
    }
    
    private func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [self] _ in
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

// MARK: - ChatBubble
struct ChatBubble: View {
    let message: ChatMessage
    @State private var showTimestamp: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
    
    /// Clean message text by removing hidden config tags, markdown formatting, and any JSON/technical content
    private static func cleanMessageForDisplay(_ text: String) -> String {
        var cleaned = text
        
        // Remove various trade config tag formats (case insensitive)
        let tradeTagPatterns = [
            ("<trade_config>", "</trade_config>"),
            ("<tradeconfig>", "</tradeconfig>"),
            ("<trade-config>", "</trade-config>"),
            ("<TRADE_CONFIG>", "</TRADE_CONFIG>"),
            ("<TradeConfig>", "</TradeConfig>")
        ]
        
        for (startTag, endTag) in tradeTagPatterns {
            while let startRange = cleaned.range(of: startTag, options: .caseInsensitive),
                  let endRange = cleaned.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<cleaned.endIndex) {
                cleaned.removeSubrange(startRange.lowerBound...endRange.upperBound)
            }
        }
        
        // Remove bot_config tags
        let botTagPatterns = [
            ("<bot_config>", "</bot_config>"),
            ("<botconfig>", "</botconfig>"),
            ("<bot-config>", "</bot-config>")
        ]
        
        for (startTag, endTag) in botTagPatterns {
            while let startRange = cleaned.range(of: startTag, options: .caseInsensitive),
                  let endRange = cleaned.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<cleaned.endIndex) {
                cleaned.removeSubrange(startRange.lowerBound...endRange.upperBound)
            }
        }
        
        // Remove strategy_config tags
        let strategyTagPatterns = [
            ("<strategy_config>", "</strategy_config>"),
            ("<strategyconfig>", "</strategyconfig>"),
            ("<strategy-config>", "</strategy-config>")
        ]
        
        for (startTag, endTag) in strategyTagPatterns {
            while let startRange = cleaned.range(of: startTag, options: .caseInsensitive),
                  let endRange = cleaned.range(of: endTag, options: .caseInsensitive, range: startRange.upperBound..<cleaned.endIndex) {
                cleaned.removeSubrange(startRange.lowerBound...endRange.upperBound)
            }
        }
        
        // Remove plain-text bot_config formats (non-XML):
        //   bot_config{...}/bot_config, bot_config{...}, bot_config(...)/bot_config, bot_config(...)
        let plainConfigPatterns = [
            "bot_config\\{[^}]*\\}/bot_config",
            "bot_config\\{[^}]*\\}",
            "bot_config\\([^)]*\\)/bot_config",
            "bot_config\\([^)]*\\)",
            "trade_config\\{[^}]*\\}/trade_config",
            "trade_config\\{[^}]*\\}",
            "alert_suggestion\\{[^}]*\\}/alert_suggestion",
            "alert_suggestion\\{[^}]*\\}",
            "alertsuggestion\\{[^}]*\\}/alertsuggestion",
            "alertsuggestion\\{[^}]*\\}",
            "alert_config\\{[^}]*\\}/alert_config",
            "alert_config\\{[^}]*\\}",
            "strategy_config\\{[^}]*\\}/strategy_config",
            "strategy_config\\{[^}]*\\}"
        ]
        for pattern in plainConfigPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        
        // Remove any standalone JSON objects that contain config fields
        // Pattern: { followed by "symbol" or "botType" somewhere before }
        // SAFETY: Use half-open range to prevent String index out of bounds crash
        if let jsonStart = cleaned.range(of: "{"),
           let jsonEnd = cleaned.range(of: "}", options: [], range: jsonStart.upperBound..<cleaned.endIndex),
           jsonStart.lowerBound < jsonEnd.upperBound {
            let jsonContent = String(cleaned[jsonStart.lowerBound..<jsonEnd.upperBound])
            if jsonContent.contains("\"symbol\"") || jsonContent.contains("\"botType\"") || 
               jsonContent.contains("\"direction\"") || jsonContent.contains("\"orderType\"") ||
               jsonContent.contains("botType") || jsonContent.contains("tradingPair") {
                cleaned.removeSubrange(jsonStart.lowerBound..<jsonEnd.upperBound)
            }
        }
        
        // Remove lines that start with technical prefixes
        let technicalPrefixes = [
            "I'll set up a limit order for you:",
            "I'll set up a market order for you:",
            "Here's the configuration:",
            "Configuration:",
            "Trade config:"
        ]
        for prefix in technicalPrefixes {
            cleaned = cleaned.replacingOccurrences(of: prefix, with: "", options: .caseInsensitive)
        }
        
        // Remove bracketed action indicators (e.g., [Execute Sell Order], [Create Alert])
        let bracketedPatterns = [
            "[Execute Sell Order]",
            "[Execute Buy Order]",
            "[Execute Order]",
            "[Place Sell Order]",
            "[Place Buy Order]",
            "[Place Order]",
            "[Create Alert]",
            "[Submit Order]",
            "[Confirm Trade]",
            "[Execute Trade]"
        ]
        for pattern in bracketedPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }
        
        // Generic regex for any remaining [Action Verb + Object] patterns that look like commands
        // Matches patterns like [Execute X], [Place X], [Create X], [Submit X], [Confirm X]
        cleaned = cleaned.replacingOccurrences(
            of: "\\[(?:Execute|Place|Create|Submit|Confirm|Set|Cancel)\\s+\\w+(?:\\s+\\w+)?\\]",
            with: "",
            options: .regularExpression
        )
        
        // === MARKDOWN STRIPPING (remove asterisks/stars for clean display) ===
        
        // Remove headers (### Header -> Header)
        cleaned = cleaned.replacingOccurrences(of: "\\n#{1,6}\\s*", with: "\n", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
        
        // Remove bold (**text** or __text__ -> text) - multiple passes for nested patterns
        for _ in 0..<3 {
            cleaned = cleaned.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: "__(.+?)__", with: "$1", options: .regularExpression)
        }
        
        // Remove italic (*text* or _text_ -> text) - be careful not to affect bullet points
        for _ in 0..<2 {
            cleaned = cleaned.replacingOccurrences(of: "(?<![*\\s])\\*([^*\\n]+?)\\*(?![*])", with: "$1", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: "(?<![_\\s])_([^_\\n]+?)_(?![_])", with: "$1", options: .regularExpression)
        }
        
        // Remove code blocks (```code``` -> code)
        cleaned = cleaned.replacingOccurrences(of: "```[\\w]*\\n?([\\s\\S]*?)```", with: "$1", options: .regularExpression)
        
        // Remove inline code (`code` -> code)
        cleaned = cleaned.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        
        // Clean up any remaining stray asterisks from incomplete markdown
        cleaned = cleaned.replacingOccurrences(of: "(?<=\\s|^)\\*\\*(?=\\S)", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(?<=\\S)\\*\\*(?=\\s|$|[.,!?;:])", with: "", options: .regularExpression)
        
        // Clean up extra whitespace and newlines
        cleaned = cleaned.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    var body: some View {
        HStack(alignment: .top) {
            if message.sender == "ai" {
                aiView
                Spacer()
            } else {
                Spacer()
                userView
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        // Removed .drawingGroup() - it rasterizes into a Metal bitmap which can
        // reduce text rendering sharpness and break Dynamic Type accessibility.
        // LazyVStack already provides efficient view recycling for chat scrolling.
    }
    
    private var aiView: some View {
        let displayText = Self.cleanMessageForDisplay(message.text)
        return VStack(alignment: .leading, spacing: 6) {
            if let path = message.imagePath {
                let url = imageURL(for: path)
                DiskImageView(url: url)
                    .frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.Adaptive.stroke, lineWidth: 1))
            } else if let data = message.imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.Adaptive.stroke, lineWidth: 1))
            }
            if !displayText.isEmpty {
                // Use StreamingTextView for professional typing cursor effect
                StreamingTextView(
                    text: displayText,
                    isStreaming: message.isStreaming,
                    textColor: DS.Adaptive.textPrimary,
                    fontSize: 16
                )
            }
            // Only show timestamp when not streaming (cleaner during typing)
            if !message.isStreaming {
                Text(formattedTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
    }
    
    private var userView: some View {
        let isDark = colorScheme == .dark
        let textColor: Color = message.isError ? Color.white : Color.black.opacity(0.9)
        
        // Adaptive styling for light/dark mode
        let glossOpacity: Double = isDark ? 0.28 : 0.35
        
        // Use light-mode gradient (no dark edge) in light mode for cleaner appearance
        let bubbleGradient: LinearGradient = isDark ? BrandGold.verticalGradient : BrandGold.verticalGradientLight

        return VStack(alignment: .trailing, spacing: 6) {
            if let path = message.imagePath {
                let url = imageURL(for: path)
                DiskImageView(url: url)
                    .frame(maxWidth: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(BrandGold.light.opacity(0.4), lineWidth: 1))
            } else if let data = message.imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(BrandGold.light.opacity(0.4), lineWidth: 1))
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundColor(textColor)
            }
            if showTimestamp {
                Text("Sent at \(formattedTime(message.timestamp))")
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.7))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            Group {
                if message.isError {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.red.opacity(0.85))
                } else {
                    ZStack {
                        // Base gold gradient - adaptive for light/dark mode
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(bubbleGradient)
                        // Top gloss highlight for premium feel - slightly stronger in light mode
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(glossOpacity), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    message.isError
                        ? Color.red.opacity(0.6)
                        : BrandGold.light.opacity(isDark ? 0.6 : 0.4),
                    lineWidth: isDark ? 0.8 : 0.5
                )
        )
        .onLongPressGesture { showTimestamp.toggle() }
    }
    
    private func formattedTime(_ date: Date) -> String {
        ChatBubble.timeFormatter.string(from: date)
    }
    
    // SAFETY FIX: Use safe directory accessor instead of force unwrap
    private func imageURL(for fileName: String) -> URL {
        return FileManager.documentsSubdirectory("ChatImages").appendingPathComponent(fileName)
    }
}

// MARK: - Preview
struct AITabView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { AITabView() }
            .preferredColorScheme(.dark)
            .environmentObject(ChatViewModel())
            .environmentObject(PortfolioViewModel.sample)
            .environmentObject(AppState())
    }
}

