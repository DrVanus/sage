//
//  AddAlertView.swift
//  CryptoSage
//
//  Premium Add/Edit Alert form with glassmorphic styling.
//

import SwiftUI

fileprivate enum AddAlertDesign {
    static let sectionCornerRadius: CGFloat = 14
    static let fieldCornerRadius: CGFloat = 12
    static let controlAccent: Color = BrandColors.goldBase
}

struct AddAlertView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notificationsManager = NotificationsManager.shared
    
    // MARK: - Editing Mode
    
    /// The alert being edited (nil for new alert)
    let editingAlert: PriceAlert?
    
    /// Callback when editing completes (to delete old alert)
    var onEditComplete: (() -> Void)?
    
    /// Whether we're in edit mode
    private var isEditing: Bool { editingAlert != nil }
    
    // MARK: - Subscription Check
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showUpgradePrompt: Bool = false
    
    // Alert type enum
    enum AlertType: String, CaseIterable {
        case standard = "Standard"
        case advanced = "Advanced"
        case aiPowered = "AI-Enhanced"
        
        var displayName: String { rawValue }
        
        var description: String {
            switch self {
            case .standard: return "Simple price threshold alerts"
            case .advanced: return "RSI, volume, and % change alerts"
            case .aiPowered: return "AI-enhanced alerts with sentiment, timing, and smarter triggers"
            }
        }
        
        var iconName: String {
            switch self {
            case .standard: return "bell.fill"
            case .advanced: return "chart.xyaxis.line"
            case .aiPowered: return "wand.and.stars"
            }
        }
    }
    
    // Form state
    @State private var symbol: String = ""
    @State private var thresholdText: String = ""
    @State private var isAbove: Bool = true
    @State private var currentPrice: Double? = nil
    @State private var livePriceUpdatedAt: Date? = nil
    @State private var isLoadingPrice: Bool = false
    @State private var selectedAlertType: AlertType = .standard
    @State private var showAlertLimitReached: Bool = false
    @State private var showCoinPicker: Bool = false
    @State private var showManualSymbolEntry: Bool = false
    
    // Advanced condition type
    @State private var selectedConditionType: AlertConditionType = .priceAbove
    @State private var selectedTimeframe: AlertTimeframe = .twentyFourHours
    @State private var volumeMultiplierText: String = "2.0"
    @State private var whaleAmountText: String = "1000000"
    @State private var walletAddress: String = ""
    
    // (Exchange picker, take profit, stop loss removed — values were not persisted)
    
    // AI-enhanced alert options (Pro+ only)
    @State private var enableSmartTiming: Bool = false
    @State private var enableSentimentAnalysis: Bool = false
    @State private var enableVolumeSpike: Bool = false
    
    // AI feature info popover states
    @State private var showSentimentInfo: Bool = false
    @State private var showSmartTimingInfo: Bool = false
    @State private var showVolumeInfo: Bool = false
    
    // Alert frequency
    @State private var selectedFrequency: AlertFrequency = .oneTime
    
    // MARK: - Initializers
    
    /// Create a new alert
    init() {
        self.editingAlert = nil
        self.onEditComplete = nil
    }
    
    /// Create a new alert with prefilled symbol and price
    init(prefilledSymbol: String, prefilledPrice: Double? = nil) {
        self.editingAlert = nil
        self.onEditComplete = nil
        _symbol = State(initialValue: prefilledSymbol)
        if let price = prefilledPrice {
            _thresholdText = State(initialValue: String(format: "%.2f", price))
        }
    }
    
    /// Edit an existing alert
    init(editingAlert: PriceAlert, onEditComplete: @escaping () -> Void) {
        self.editingAlert = editingAlert
        self.onEditComplete = onEditComplete
        
        // Pre-populate state with existing values
        _symbol = State(initialValue: editingAlert.symbol)
        _thresholdText = State(initialValue: Self.formatThreshold(editingAlert.threshold))
        _isAbove = State(initialValue: editingAlert.isAbove)
        let sanitizedConditionType: AlertConditionType = editingAlert.conditionType.isComingSoon
            ? .percentChangeUp
            : editingAlert.conditionType
        _selectedConditionType = State(initialValue: sanitizedConditionType)
        _selectedTimeframe = State(initialValue: editingAlert.timeframe ?? .twentyFourHours)
        _enableSmartTiming = State(initialValue: editingAlert.enableSmartTiming)
        _enableSentimentAnalysis = State(initialValue: editingAlert.enableSentimentAnalysis)
        _enableVolumeSpike = State(initialValue: editingAlert.enableAIVolumeSpike)
        _selectedFrequency = State(initialValue: editingAlert.frequency)
        
        // Set volume multiplier if present
        if let volumeMult = editingAlert.volumeMultiplier {
            _volumeMultiplierText = State(initialValue: String(format: "%.1f", volumeMult))
        }
        
        // Set whale amount if present
        if let whaleAmount = editingAlert.minWhaleAmount {
            _whaleAmountText = State(initialValue: String(format: "%.0f", whaleAmount))
        }
        
        // Set wallet address if present
        if let wallet = editingAlert.walletAddress {
            _walletAddress = State(initialValue: wallet)
        }
        
        // Determine alert type based on features
        if editingAlert.hasAIFeatures {
            _selectedAlertType = State(initialValue: .aiPowered)
        } else if editingAlert.conditionType.isAdvanced {
            _selectedAlertType = State(initialValue: .advanced)
        } else {
            _selectedAlertType = State(initialValue: .standard)
        }
    }
    
    private static func formatThreshold(_ value: Double) -> String {
        if value >= 1 {
            return String(format: "%.2f", value)
        } else if value >= 0.01 {
            return String(format: "%.4f", value)
        } else {
            return String(format: "%.6f", value)
        }
    }
    
    private func formatPriceDisplay(_ price: Double) -> String {
        if price >= 1000 {
            return String(format: "%.2f", price)
        } else if price >= 1 {
            return String(format: "%.2f", price)
        } else if price >= 0.01 {
            return String(format: "%.4f", price)
        } else {
            return String(format: "%.6f", price)
        }
    }
    
    private func normalizeAlertSymbol(_ raw: String) -> String {
        let compact = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty else { return "" }
        let knownQuotes = ["USDT", "USD", "USDC", "BUSD", "USDP", "TUSD"]
        if knownQuotes.contains(where: { compact.hasSuffix($0) }) {
            return compact
        }
        return "\(compact)USDT"
    }
    
    private func applyPercentPreset(_ percent: Double) {
        guard let price = currentPrice, price > 0 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let multiplier = 1 + (percent / 100)
        let target = price * multiplier
        thresholdText = Self.formatThreshold(target)
        isAbove = percent >= 0
    }
    
    private func setTargetToLivePrice() {
        guard let price = currentPrice, price > 0 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        thresholdText = Self.formatThreshold(price)
    }
    
    /// Nudge target by a percent step of the current live price.
    private func nudgeTarget(byPercent percentStep: Double) {
        guard let price = currentPrice, price > 0 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let currentTarget = Double(thresholdText) ?? price
        let delta = price * (percentStep / 100.0)
        let nextTarget = max(0.0000001, currentTarget + delta)
        thresholdText = Self.formatThreshold(nextTarget)
        isAbove = nextTarget >= price
    }
    
    /// Check if user has access to advanced alerts
    private var hasAdvancedAlertAccess: Bool {
        subscriptionManager.hasAccess(to: .advancedAlerts)
    }
    
    private let popularSymbols = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT", "BNBUSDT"]
    
    /// Check if user has access to AI-enhanced alerts
    private var hasAIAlertAccess: Bool {
        subscriptionManager.hasAccess(to: .aiPoweredAlerts)
    }
    
    private var isFormValid: Bool {
        !symbol.isEmpty && !thresholdText.isEmpty && Double(thresholdText) != nil
    }
    
    private var selectedSymbolDisplay: String {
        let compact = symbol
            .uppercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        let knownQuotes = ["USDT", "USD", "USDC", "BUSD", "USDP", "TUSD"]
        for quote in knownQuotes where compact.hasSuffix(quote) {
            return String(compact.dropLast(quote.count))
        }
        return compact
    }
    
    private var selectedPairDisplay: String {
        normalizeAlertSymbol(symbol)
    }
    
    private var coinPickerSymbolBinding: Binding<String> {
        Binding(
            get: { selectedSymbolDisplay },
            set: { newValue in
                symbol = normalizeAlertSymbol(newValue)
            }
        )
    }
    
    private var thresholdDistanceText: String? {
        guard let price = currentPrice,
              let target = Double(thresholdText),
              price > 0 else { return nil }
        let percent = ((target - price) / price) * 100
        let prefix = percent >= 0 ? "+" : ""
        return "Target is \(prefix)\(String(format: "%.2f", percent))% vs live"
    }
    
    private var hasSelectedSymbol: Bool {
        !selectedSymbolDisplay.isEmpty
    }
    
    private var livePriceStatusText: String {
        if !hasSelectedSymbol {
            return "Select a coin pair to load live price"
        }
        if isLoadingPrice {
            return "Fetching \(selectedSymbolDisplay) live price..."
        }
        if let price = currentPrice {
            return "Live \(selectedSymbolDisplay): $\(formatPriceDisplay(price))"
        }
        return "Live price temporarily unavailable"
    }
    
    private var livePriceHintText: String {
        if !hasSelectedSymbol {
            return "Choose a symbol above, then set your target from live data."
        }
        if let updatedAt = livePriceUpdatedAt {
            return "Updated \(RelativeDateTimeFormatter().localizedString(for: updatedAt, relativeTo: Date()))"
        }
        if isLoadingPrice {
            return "Connecting to market feed..."
        }
        return "Tap refresh to retry."
    }
    
    /// Whether the free-tier alert limit has been reached (does not apply when editing)
    private var isAtAlertLimit: Bool {
        guard !isEditing else { return false }
        let activeCount = notificationsManager.allAlerts
            .filter { !notificationsManager.triggeredAlertIDs.contains($0.id) }
            .count
        return activeCount >= subscriptionManager.effectiveTier.maxPriceAlerts
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Adaptive.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 18) {
                        // Alert Type Selector
                        FormSection(title: "Alert Type") {
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    ForEach(AlertType.allCases, id: \.rawValue) { type in
                                        AlertTypeButton(
                                            type: type,
                                            isSelected: selectedAlertType == type,
                                            isLocked: (type == .aiPowered && !hasAIAlertAccess) || (type == .advanced && !hasAdvancedAlertAccess)
                                        ) {
                                            if type == .aiPowered && !hasAIAlertAccess {
                                                showUpgradePrompt = true
                                            } else if type == .advanced && !hasAdvancedAlertAccess {
                                                showUpgradePrompt = true
                                            } else {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                withAnimation(.spring(response: 0.3)) {
                                                    selectedAlertType = type
                                                    // Update condition type based on alert type
                                                    if type == .standard {
                                                        selectedConditionType = isAbove ? .priceAbove : .priceBelow
                                                    }
                                                    // Auto-enable all AI features when switching to AI-Enhanced
                                                    if type == .aiPowered {
                                                        enableSentimentAnalysis = true
                                                        enableSmartTiming = true
                                                        enableVolumeSpike = true
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                // Description of selected type
                                Text(selectedAlertType.description)
                                    .font(.system(size: 12))
                                    .foregroundStyle(DS.Adaptive.textTertiary)
                            }
                        }
                        
                        // AI-Enhanced explanatory banner
                        if selectedAlertType == .aiPowered && hasAIAlertAccess {
                            HStack(spacing: 10) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.58, green: 0.35, blue: 0.98))
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("AI-Enhanced Alert")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(DS.Adaptive.textPrimary)
                                    Text("Uses market sentiment, volatility analysis, and volume detection to make your alerts smarter. Customize the AI features below.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(DS.Adaptive.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(red: 0.58, green: 0.35, blue: 0.98).opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(red: 0.58, green: 0.35, blue: 0.98).opacity(0.20), lineWidth: 1)
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        // Symbol Section
                        FormSection(title: "Symbol") {
                            VStack(alignment: .leading, spacing: 12) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    showCoinPicker = true
                                } label: {
                                    HStack(spacing: 10) {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    RadialGradient(
                                                        colors: [
                                                            AddAlertDesign.controlAccent.opacity(selectedSymbolDisplay.isEmpty ? 0.18 : 0.30),
                                                            AddAlertDesign.controlAccent.opacity(0.04)
                                                        ],
                                                        center: .center,
                                                        startRadius: 0,
                                                        endRadius: 24
                                                    )
                                                )
                                                .frame(width: 40, height: 40)
                                            
                                            if selectedSymbolDisplay.isEmpty {
                                                Image(systemName: "magnifyingglass.circle.fill")
                                                    .font(.system(size: 17, weight: .semibold))
                                                    .foregroundStyle(AddAlertDesign.controlAccent)
                                            } else {
                                                CoinImageView(symbol: selectedSymbolDisplay, url: nil, size: 30)
                                            }
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(selectedPairDisplay.isEmpty ? "Select a coin pair" : selectedPairDisplay)
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundStyle(DS.Adaptive.textPrimary)
                                                .monospacedDigit()
                                            Text(selectedPairDisplay.isEmpty ? "Tap to browse full market list" : "Pair selected - tap to change")
                                                .font(.system(size: 11))
                                                .foregroundStyle(DS.Adaptive.textTertiary)
                                        }
                                        
                                        Spacer(minLength: 8)
                                        
                                        HStack(spacing: 6) {
                                            if !selectedSymbolDisplay.isEmpty {
                                                Text("PAIR")
                                                    .font(.system(size: 8, weight: .heavy))
                                                    .foregroundStyle(AddAlertDesign.controlAccent)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(
                                                        Capsule()
                                                            .fill(AddAlertDesign.controlAccent.opacity(0.14))
                                                    )
                                            }
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(DS.Adaptive.textTertiary)
                                        }
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        DS.Adaptive.chipBackground.opacity(0.95),
                                                        DS.Adaptive.chipBackground.opacity(0.76)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [
                                                        AddAlertDesign.controlAccent.opacity(selectedSymbolDisplay.isEmpty ? 0.18 : 0.35),
                                                        DS.Adaptive.stroke.opacity(0.85)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                    .shadow(
                                        color: AddAlertDesign.controlAccent.opacity(selectedSymbolDisplay.isEmpty ? 0.0 : 0.14),
                                        radius: selectedSymbolDisplay.isEmpty ? 0 : 8,
                                        x: 0,
                                        y: 3
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                if !selectedSymbolDisplay.isEmpty {
                                    HStack(spacing: 8) {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill((currentPrice != nil && !isLoadingPrice) ? Color.green : DS.Adaptive.textTertiary.opacity(0.5))
                                                .frame(width: 6, height: 6)
                                            if let price = currentPrice {
                                                Text("\(selectedSymbolDisplay) live: $\(formatPriceDisplay(price))")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(DS.Adaptive.textSecondary)
                                                    .monospacedDigit()
                                            } else if isLoadingPrice {
                                                Text("Syncing live price...")
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(DS.Adaptive.textTertiary)
                                            } else {
                                                Text("\(selectedSymbolDisplay) selected")
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(DS.Adaptive.textTertiary)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(DS.Adaptive.chipBackground.opacity(0.55))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(DS.Adaptive.stroke.opacity(0.55), lineWidth: 0.8)
                                    )
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                                
                                // Quick symbol chips
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(popularSymbols, id: \.self) { sym in
                                            Button {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                symbol = sym
                                            } label: {
                                                Text(sym.replacingOccurrences(of: "USDT", with: ""))
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(normalizeAlertSymbol(symbol) == sym ? Color.black : DS.Adaptive.textSecondary)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(
                                                        Capsule()
                                                            .fill(normalizeAlertSymbol(symbol) == sym ? AddAlertDesign.controlAccent : DS.Adaptive.chipBackground)
                                                    )
                                                    .overlay(
                                                        Capsule()
                                                            .stroke(normalizeAlertSymbol(symbol) == sym ? Color.clear : DS.Adaptive.stroke, lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                        showManualSymbolEntry.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "keyboard")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text(showManualSymbolEntry ? "Hide manual entry" : "Type symbol manually")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundStyle(DS.Adaptive.textSecondary)
                                }
                                .buttonStyle(.plain)
                                
                                if showManualSymbolEntry {
                                    PremiumTextField(
                                        placeholder: "e.g. BTCUSDT",
                                        text: $symbol,
                                        keyboardType: .default,
                                        capitalization: .characters
                                    )
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                                
                                // Live status is shown in the Price Target section to keep this block focused.
                            }
                        }
                        
                        // Threshold Section
                        FormSection(title: "Price Target") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill((currentPrice != nil && !isLoadingPrice) ? Color.green : DS.Adaptive.textTertiary.opacity(0.45))
                                            .frame(width: 7, height: 7)
                                        Text(livePriceStatusText)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle((currentPrice != nil && !isLoadingPrice) ? DS.Adaptive.textSecondary : DS.Adaptive.textTertiary)
                                            .monospacedDigit()
                                    }
                                    
                                    Spacer(minLength: 8)
                                    
                                    Button {
                                        Task { await fetchCurrentPrice() }
                                    } label: {
                                        Group {
                                            if isLoadingPrice {
                                                ProgressView()
                                                    .controlSize(.mini)
                                            } else {
                                                Image(systemName: "arrow.clockwise")
                                                    .font(.system(size: 11, weight: .bold))
                                            }
                                        }
                                        .foregroundStyle(DS.Adaptive.textSecondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(DS.Adaptive.chipBackground))
                                        .overlay(
                                            Capsule()
                                                .stroke(DS.Adaptive.stroke.opacity(0.7), lineWidth: 0.8)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isLoadingPrice || !hasSelectedSymbol)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: AddAlertDesign.fieldCornerRadius, style: .continuous)
                                        .fill(DS.Adaptive.chipBackground.opacity(0.72))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AddAlertDesign.fieldCornerRadius, style: .continuous)
                                        .stroke(DS.Adaptive.stroke.opacity(0.55), lineWidth: 0.8)
                                )
                                
                                Text(livePriceHintText)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DS.Adaptive.textTertiary)
                                
                                PremiumTextField(
                                    placeholder: "Enter target price",
                                    text: $thresholdText,
                                    keyboardType: .decimalPad
                                )
                                
                                HStack(spacing: 8) {
                                    Button {
                                        nudgeTarget(byPercent: -0.5)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.system(size: 11, weight: .bold))
                                            Text("-0.5%")
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Color.red.opacity(0.12)))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(currentPrice == nil)
                                    
                                    Button {
                                        nudgeTarget(byPercent: 0.5)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 11, weight: .bold))
                                            Text("+0.5%")
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Color.green.opacity(0.12)))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(currentPrice == nil)
                                    
                                    if currentPrice != nil {
                                        Button {
                                            setTargetToLivePrice()
                                        } label: {
                                            Text("Use Live")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(DS.Adaptive.textSecondary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Capsule().fill(DS.Adaptive.chipBackground))
                                                .overlay(
                                                    Capsule()
                                                        .stroke(DS.Adaptive.stroke.opacity(0.7), lineWidth: 0.8)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Spacer(minLength: 0)
                                }
                                
                                if !thresholdText.isEmpty && Double(thresholdText) == nil {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 12))
                                        Text("Please enter a valid number")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundStyle(.red)
                                }
                                
                                // Direction toggle
                                HStack {
                                    Text("Alert when price is")
                                        .font(.system(size: 14))
                                        .foregroundStyle(DS.Adaptive.textSecondary)
                                    
                                    Spacer()
                                    
                                    // Custom segmented control
                                    HStack(spacing: 0) {
                                        DirectionButton(
                                            title: "Above",
                                            icon: "arrow.up",
                                            isSelected: isAbove,
                                            color: .green
                                        ) {
                                            withAnimation(.spring(response: 0.3)) { isAbove = true }
                                        }
                                        
                                        DirectionButton(
                                            title: "Below",
                                            icon: "arrow.down",
                                            isSelected: !isAbove,
                                            color: .red
                                        ) {
                                            withAnimation(.spring(response: 0.3)) { isAbove = false }
                                        }
                                    }
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(DS.Adaptive.chipBackground)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                    )
                                }
                                .padding(.top, 4)
                                
                                if currentPrice != nil {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Quick target presets")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(DS.Adaptive.textSecondary)
                                        
                                        HStack(spacing: 6) {
                                            ForEach([1.0, 3.0, 5.0], id: \.self) { pct in
                                                Button {
                                                    applyPercentPreset(pct)
                                                } label: {
                                                    Text("+\(Int(pct))%")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundStyle(.green)
                                                        .padding(.horizontal, 9)
                                                        .padding(.vertical, 5)
                                                        .background(Capsule().fill(Color.green.opacity(0.15)))
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Button {
                                                    applyPercentPreset(-pct)
                                                } label: {
                                                    Text("-\(Int(pct))%")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundStyle(.red)
                                                        .padding(.horizontal, 9)
                                                        .padding(.vertical, 5)
                                                        .background(Capsule().fill(Color.red.opacity(0.15)))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        
                                        if let thresholdDistanceText {
                                            Text(thresholdDistanceText)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(DS.Adaptive.textTertiary)
                                                .monospacedDigit()
                                        }
                                        
                                        if let updatedAt = livePriceUpdatedAt {
                                            HStack(spacing: 4) {
                                                Image(systemName: "clock.arrow.circlepath")
                                                    .font(.system(size: 9, weight: .semibold))
                                                Text("Live updated \(RelativeDateTimeFormatter().localizedString(for: updatedAt, relativeTo: Date()))")
                                                    .font(.system(size: 10, weight: .medium))
                                            }
                                            .foregroundStyle(DS.Adaptive.textTertiary.opacity(0.9))
                                        }
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: AddAlertDesign.fieldCornerRadius, style: .continuous)
                                            .fill(DS.Adaptive.chipBackground.opacity(0.75))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AddAlertDesign.fieldCornerRadius, style: .continuous)
                                            .stroke(DS.Adaptive.stroke.opacity(0.7), lineWidth: 0.8)
                                    )
                                }
                            }
                        }
                        
                        // AI Features section (shown right after Price Target for visibility)
                        if selectedAlertType == .aiPowered && hasAIAlertAccess {
                            FormSection(title: "AI Features") {
                                VStack(spacing: 0) {
                                    AIFeatureToggleRowWithInfo(
                                        icon: "chart.line.text.clipboard",
                                        title: "Sentiment Analysis",
                                        subtitle: "Alert based on market sentiment changes",
                                        isOn: $enableSentimentAnalysis,
                                        showInfo: $showSentimentInfo,
                                        infoTitle: "Sentiment Analysis",
                                        infoDescription: "Monitors the Fear & Greed Index and triggers alerts when market sentiment shifts significantly (15+ points) or changes classification (e.g., Fear → Greed). This helps you catch major market mood swings that often precede price movements."
                                    )
                                    
                                    Divider()
                                        .background(DS.Adaptive.divider)
                                        .padding(.horizontal, -16)
                                    
                                    AIFeatureToggleRowWithInfo(
                                        icon: "clock.badge.checkmark.fill",
                                        title: "Smart Timing",
                                        subtitle: "AI suggests optimal alert trigger times",
                                        isOn: $enableSmartTiming,
                                        showInfo: $showSmartTimingInfo,
                                        infoTitle: "Smart Timing",
                                        infoDescription: "Analyzes market volatility to optimize when alerts trigger. During high volatility (>2% moves), alerts fire immediately. During quiet periods (<0.5% moves), alerts are delayed until price is very close to your target. This reduces noise and improves alert relevance."
                                    )
                                    
                                    Divider()
                                        .background(DS.Adaptive.divider)
                                        .padding(.horizontal, -16)
                                    
                                    AIFeatureToggleRowWithInfo(
                                        icon: "waveform.badge.plus",
                                        title: "Volume Spike Detection",
                                        subtitle: "Alert on unusual volume activity",
                                        isOn: $enableVolumeSpike,
                                        showInfo: $showVolumeInfo,
                                        infoTitle: "AI Volume Spike Detection",
                                        infoDescription: "Uses volatility-adjusted thresholds to detect significant volume spikes. During high volatility, requires larger volume spikes (1.5x threshold). During calm periods, even smaller volume increases (0.75x threshold) can trigger alerts. This adapts to market conditions for smarter detection."
                                    )
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        // Advanced Condition Selector (shown for Advanced and AI-Enhanced types)
                        if (selectedAlertType == .advanced && hasAdvancedAlertAccess) ||
                           (selectedAlertType == .aiPowered && hasAIAlertAccess) {
                            FormSection(title: "Condition Type") {
                                VStack(alignment: .leading, spacing: 12) {
                                    // Condition type picker
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(AlertConditionType.allCases.filter { $0.isAdvanced && !$0.isComingSoon }, id: \.rawValue) { condType in
                                                ConditionTypeChip(
                                                    type: condType,
                                                    isSelected: selectedConditionType == condType
                                                ) {
                                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                    withAnimation(.spring(response: 0.3)) {
                                                        selectedConditionType = condType
                                                    }
                                                }
                                            }
                                            // Coming Soon conditions (disabled, dimmed)
                                            ForEach(AlertConditionType.allCases.filter { $0.isAdvanced && $0.isComingSoon }, id: \.rawValue) { condType in
                                                HStack(spacing: 4) {
                                                    Image(systemName: condType.icon)
                                                        .font(.system(size: 11, weight: .semibold))
                                                    Text(condType.rawValue)
                                                        .font(.system(size: 11, weight: .semibold))
                                                    Text("Soon")
                                                        .font(.system(size: 8, weight: .bold))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Capsule().fill(DS.Adaptive.chipBackground))
                                                }
                                                .foregroundStyle(DS.Adaptive.textTertiary.opacity(0.55))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(
                                                    Capsule()
                                                        .fill(DS.Adaptive.chipBackground.opacity(0.5))
                                                )
                                                .overlay(
                                                    Capsule()
                                                        .stroke(DS.Adaptive.stroke.opacity(0.4), lineWidth: 1)
                                                )
                                            }
                                        }
                                    }
                                    
                                    // Description
                                    Text(selectedConditionType.description)
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Adaptive.textTertiary)
                                    
                                    // Timeframe picker for percent change alerts
                                    if selectedConditionType.requiresTimeframe {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Timeframe")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(DS.Adaptive.textSecondary)
                                            
                                            HStack(spacing: 8) {
                                                ForEach(AlertTimeframe.allCases, id: \.rawValue) { tf in
                                                    TimeframeChip(
                                                        timeframe: tf,
                                                        isSelected: selectedTimeframe == tf
                                                    ) {
                                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                        selectedTimeframe = tf
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.top, 8)
                                    }
                                    
                                    // Volume multiplier for volume spike alerts
                                    if selectedConditionType == .volumeSpike {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Volume Multiplier (x average)")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(DS.Adaptive.textSecondary)
                                            
                                            PremiumTextField(
                                                placeholder: "e.g. 2.0",
                                                text: $volumeMultiplierText,
                                                keyboardType: .decimalPad
                                            )
                                        }
                                        .padding(.top, 8)
                                    }
                                    
                                    // Whale alert settings
                                    if selectedConditionType == .whaleMovement {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Minimum Amount ($)")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(DS.Adaptive.textSecondary)
                                            
                                            PremiumTextField(
                                                placeholder: "e.g. 1000000",
                                                text: $whaleAmountText,
                                                keyboardType: .numberPad
                                            )
                                            
                                            Text("Wallet Address (optional)")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(DS.Adaptive.textSecondary)
                                            
                                            PremiumTextField(
                                                placeholder: "0x... or leave empty for all",
                                                text: $walletAddress,
                                                keyboardType: .default
                                            )
                                        }
                                        .padding(.top, 8)
                                    }
                                }
                            }
                        }
                        
                        // Notification delivery is always push for now.
                        FormSection(title: "Notification Delivery") {
                            HStack(spacing: 10) {
                                Image(systemName: "bell.badge.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AddAlertDesign.controlAccent)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(AddAlertDesign.controlAccent.opacity(0.14)))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Push notifications enabled by default")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(DS.Adaptive.textPrimary)
                                    Text("Email and Telegram are coming in a future update.")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(DS.Adaptive.textTertiary)
                                }
                                
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                        }
                        
                        // Alert Frequency Section
                        FormSection(title: "Alert Frequency") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Choose how often this alert can trigger.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DS.Adaptive.textTertiary)
                                
                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                                    spacing: 8
                                ) {
                                    ForEach(AlertFrequency.allCases, id: \.rawValue) { freq in
                                        FrequencyCard(
                                            frequency: freq,
                                            isSelected: selectedFrequency == freq
                                        ) {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            withAnimation(.spring(response: 0.3)) {
                                                selectedFrequency = freq
                                            }
                                        }
                                    }
                                }
                                
                                Text(selectedFrequency.description)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DS.Adaptive.textSecondary)
                                    .lineSpacing(1.5)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 9)
                                    .frame(minHeight: 40)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: AddAlertDesign.fieldCornerRadius, style: .continuous)
                                            .fill(DS.Adaptive.chipBackground.opacity(0.72))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AddAlertDesign.fieldCornerRadius, style: .continuous)
                                            .stroke(DS.Adaptive.stroke.opacity(0.55), lineWidth: 0.8)
                                    )
                            }
                        }
                        
                        // (Advanced Options section removed — exchange picker, take profit, stop loss
                        //  were not persisted to the alert model)
                        
                        // Alert limit banner (free tier)
                        if isAtAlertLimit {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(BrandColors.goldBase)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Alert limit reached")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(DS.Adaptive.textPrimary)
                                    Text("Free users can have up to \(subscriptionManager.effectiveTier.maxPriceAlerts) active alerts.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(DS.Adaptive.textSecondary)
                                }
                                Spacer()
                                Button {
                                    showUpgradePrompt = true
                                } label: {
                                    Text("Upgrade")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .buttonStyle(
                                    PremiumCompactCTAStyle(
                                        height: 28,
                                        horizontalPadding: 12,
                                        cornerRadius: 14,
                                        font: .system(size: 12, weight: .bold)
                                    )
                                )
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(BrandColors.goldBase.opacity(0.10))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(BrandColors.goldBase.opacity(0.30), lineWidth: 1)
                            )
                        }
                        
                        // Save Button
                        let canSave = isFormValid && !isAtAlertLimit
                        Button {
                            saveAlert()
                        } label: {
                            HStack(spacing: 9) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(canSave ? 0.12 : 0.08))
                                        .frame(width: 24, height: 24)
                                    Image(systemName: isEditing ? "checkmark.circle.fill" : "plus.circle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                Text(isEditing ? "Update Alert" : "Save Alert")
                                    .font(.system(size: 17, weight: .bold))
                                if canSave {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 12, weight: .black))
                                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(
                            PremiumAccentCTAStyle(
                                accent: AddAlertDesign.controlAccent,
                                height: 54,
                                horizontalPadding: 16,
                                cornerRadius: AddAlertDesign.sectionCornerRadius,
                                font: .system(size: 17, weight: .bold)
                            )
                        )
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.55)
                        .padding(.top, 8)
                        .accessibilityLabel(isEditing ? "Update alert" : "Save new alert")
                        .accessibilityHint(canSave ? "Double tap to save" : isAtAlertLimit ? "Alert limit reached, upgrade to continue" : "Enter symbol and target price first")
                        
                        HStack(spacing: 6) {
                            Image(systemName: canSave ? "checkmark.seal.fill" : "info.circle")
                                .font(.system(size: 11, weight: .semibold))
                            Text(
                                canSave
                                    ? "Ready to \(isEditing ? "update" : "create") \(selectedPairDisplay)"
                                    : "Select a symbol and target to enable save"
                            )
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        }
                        .foregroundStyle(canSave ? DS.Adaptive.textSecondary : DS.Adaptive.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? "Edit Alert" : "New Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    CSNavButton(
                        icon: "xmark",
                        action: { dismiss() },
                        accessibilityText: "Close",
                        accessibilityHintText: "Dismiss add alert screen",
                        compact: true
                    )
                }
                
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(isEditing ? "Edit Alert" : "New Alert")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Adaptive.textPrimary)
                        if !selectedSymbolDisplay.isEmpty {
                            Text(selectedPairDisplay)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.Adaptive.textTertiary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .unifiedPaywallSheet(feature: .aiPoweredAlerts, isPresented: $showUpgradePrompt)
            .sheet(isPresented: $showCoinPicker) {
                CoinPickerSheet(selectedSymbol: coinPickerSymbolBinding) { coin in
                    symbol = normalizeAlertSymbol(coin.symbol)
                    if let price = coin.priceUsd, price > 0 {
                        currentPrice = price
                        livePriceUpdatedAt = Date()
                        isLoadingPrice = false
                    }
                }
            }
            // Tap anywhere to dismiss keyboard
            .onTapGesture {
                UIApplication.shared.dismissKeyboard()
            }
            .onChange(of: symbol) { _, newValue in
                let normalized = normalizeAlertSymbol(newValue)
                guard normalized != symbol else {
                    Task { await fetchCurrentPrice() }
                    return
                }
                symbol = normalized
            }
        }
    }
    
    // MARK: - Actions
    
    private func saveAlert() {
        guard let threshold = Double(thresholdText), !symbol.isEmpty else { return }
        let normalizedSymbol = normalizeAlertSymbol(symbol)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // If editing, delete the old alert first
        if isEditing {
            onEditComplete?()
        }
        
        // Analytics: Track alert creation/update
        AnalyticsService.shared.track(.alertCreated, parameters: [
            "symbol": normalizedSymbol,
            "type": selectedAlertType.rawValue,
            "hasAIFeatures": String(selectedAlertType == .aiPowered),
            "isEdit": String(isEditing)
        ])
        
        let volumeMultiplier = Double(volumeMultiplierText) ?? 2.0
        let whaleAmount = Double(whaleAmountText) ?? 1_000_000
        
        // Determine condition type based on alert type
        let conditionType: AlertConditionType
        if selectedAlertType == .standard {
            conditionType = isAbove ? .priceAbove : .priceBelow
        } else {
            conditionType = selectedConditionType.isComingSoon ? .percentChangeUp : selectedConditionType
        }
        
        // Create alert with all features including AI options
        notificationsManager.addAlertWithAI(
            symbol: normalizedSymbol,
            threshold: threshold,
            isAbove: isAbove,
            conditionType: conditionType,
            timeframe: conditionType.requiresTimeframe ? selectedTimeframe : nil,
            enablePush: true,
            enableEmail: false,
            enableTelegram: false,
            minWhaleAmount: conditionType == .whaleMovement ? whaleAmount : nil,
            walletAddress: conditionType == .whaleMovement && !walletAddress.isEmpty ? walletAddress : nil,
            volumeMultiplier: conditionType == .volumeSpike ? volumeMultiplier : nil,
            enableSentimentAnalysis: selectedAlertType == .aiPowered ? enableSentimentAnalysis : false,
            enableSmartTiming: selectedAlertType == .aiPowered ? enableSmartTiming : false,
            enableAIVolumeSpike: selectedAlertType == .aiPowered ? enableVolumeSpike : false,
            frequency: selectedFrequency,
            creationPrice: currentPrice
        )
        dismiss()
    }
    
    // PERFORMANCE FIX: Static cache for price lookups
    private static var priceCache: [String: (price: Double, fetchedAt: Date)] = [:]
    private static let priceCacheTTL: TimeInterval = 15.0
    
    private func fetchCurrentPrice() async {
        guard !symbol.isEmpty else {
            await MainActor.run {
                currentPrice = nil
                livePriceUpdatedAt = nil
                isLoadingPrice = false
            }
            return
        }
        
        await MainActor.run { isLoadingPrice = true }
        
        let cacheKey = symbol.uppercased()
        
        // PERFORMANCE FIX: Check cache first
        let now = Date()
        if let cached = Self.priceCache[cacheKey],
           now.timeIntervalSince(cached.fetchedAt) < Self.priceCacheTTL {
            await MainActor.run {
                currentPrice = cached.price
                livePriceUpdatedAt = cached.fetchedAt
                isLoadingPrice = false
            }
            return
        }
        
        // PERFORMANCE FIX: Try LivePriceManager first (already has cached data)
        // PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing across all views
        let coins = await MainActor.run { LivePriceManager.shared.currentCoinsList }
        // Extract base symbol from trading pair (e.g., "BTCUSDT" -> "BTC")
        let baseSymbol = cacheKey.replacingOccurrences(of: "USDT", with: "")
                                 .replacingOccurrences(of: "USD", with: "")
        if let coin = coins.first(where: { $0.symbol.uppercased() == baseSymbol }) {
            // Use bestPrice() for consistency, fallback to coin.priceUsd from LivePriceManager
            let price = await MainActor.run { MarketViewModel.shared.bestPrice(for: coin.id) } ?? coin.priceUsd
            if let validPrice = price, validPrice > 0 {
                Self.priceCache[cacheKey] = (validPrice, Date())
                await MainActor.run {
                    currentPrice = validPrice
                    livePriceUpdatedAt = Date()
                    isLoadingPrice = false
                }
                return
            }
        }
        
        // PERFORMANCE FIX: Check rate limiter before making API request
        guard APIRequestCoordinator.shared.canMakeRequest(for: .binance) else {
            // Return cached value if available
            if let cached = Self.priceCache[cacheKey] {
                await MainActor.run {
                    currentPrice = cached.price
                    livePriceUpdatedAt = cached.fetchedAt
                    isLoadingPrice = false
                }
            } else {
                await MainActor.run { isLoadingPrice = false }
            }
            return
        }
        
        APIRequestCoordinator.shared.recordRequest(for: .binance)
        
        // FIX: Use ExchangeHostPolicy to get correct endpoint (US if geo-blocked)
        let endpoints = await ExchangeHostPolicy.shared.currentEndpoints()
        let urlString = "\(endpoints.restBase)/ticker/price?symbol=\(cacheKey)"
        guard let url = URL(string: urlString) else {
            APIRequestCoordinator.shared.recordFailure(for: .binance)
            await MainActor.run { isLoadingPrice = false }
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // FIX: Report HTTP status to policy for geo-block detection
            if let httpResponse = response as? HTTPURLResponse {
                await ExchangeHostPolicy.shared.onHTTPStatus(httpResponse.statusCode)
            }
            
            let decoded = try JSONDecoder().decode(PriceResponse.self, from: data)
            if let value = Double(decoded.price) {
                Self.priceCache[cacheKey] = (value, Date())
                APIRequestCoordinator.shared.recordSuccess(for: .binance)
                await MainActor.run {
                    currentPrice = value
                    livePriceUpdatedAt = Date()
                    isLoadingPrice = false
                }
            } else {
                APIRequestCoordinator.shared.recordFailure(for: .binance)
                await MainActor.run { isLoadingPrice = false }
            }
        } catch {
            APIRequestCoordinator.shared.recordFailure(for: .binance)
            await MainActor.run {
                currentPrice = nil
                livePriceUpdatedAt = nil
                isLoadingPrice = false
            }
        }
    }
    
    private struct PriceResponse: Codable {
        let price: String
    }
}

// MARK: - Form Section Component

private struct FormSection<Content: View>: View {
    let title: String
    var isExpandable: Bool = false
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content
    
    init(title: String, isExpandable: Bool = false, isExpanded: Binding<Bool> = .constant(true), @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.isExpandable = isExpandable
        self._isExpanded = isExpanded
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            if isExpandable {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        sectionTitle
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)
            } else {
                sectionTitle
            }
            
            // Content
            if !isExpandable || isExpanded {
                content()
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: AddAlertDesign.sectionCornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AddAlertDesign.sectionCornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            }
        }
    }
    
    private var sectionTitle: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(DS.Adaptive.textSecondary)
            .tracking(0.8)
    }
}

// MARK: - Premium Text Field

private struct PremiumTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never
    
    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(DS.Adaptive.textPrimary)
            .keyboardType(keyboardType)
            .textContentType(.none)
            .autocorrectionDisabled()
            .textInputAutocapitalization(capitalization)
            .submitLabel(.done)
            .onSubmit {
                UIApplication.shared.dismissKeyboard()
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
            .contentShape(Rectangle())
    }
}

// MARK: - Direction Button

private struct DirectionButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .white : DS.Adaptive.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? color : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) direction")
        .accessibilityHint(isSelected ? "Currently selected direction" : "Double tap to set alert direction")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - AI Feature Toggle Row (with sparkle accent)

private struct AIFeatureToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    // Purple/violet gradient for AI features
    private let aiColor = Color(red: 0.58, green: 0.35, blue: 0.98)
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon with AI accent
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [aiColor.opacity(0.15), aiColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [aiColor, aiColor.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            // Labels
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    
                    // Small AI badge
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(aiColor)
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            // Toggle with AI color
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: aiColor))
                .labelsHidden()
        }
        .padding(.vertical, 12)
    }
}

// MARK: - AI Feature Toggle Row with Info Button

private struct AIFeatureToggleRowWithInfo: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @Binding var showInfo: Bool
    let infoTitle: String
    let infoDescription: String
    
    // Purple/violet gradient for AI features
    private let aiColor = Color(red: 0.58, green: 0.35, blue: 0.98)
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon with AI accent
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [aiColor.opacity(0.15), aiColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [aiColor, aiColor.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            // Labels
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    
                    // Small AI badge
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(aiColor)
                    
                    // Info button
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            // Toggle with AI color
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: aiColor))
                .labelsHidden()
        }
        .padding(.vertical, 12)
        .popover(isPresented: $showInfo, arrowEdge: .top) {
            AIFeatureInfoPopover(title: infoTitle, description: infoDescription, aiColor: aiColor)
                .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - AI Feature Info Popover

private struct AIFeatureInfoPopover: View {
    let title: String
    let description: String
    let aiColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(aiColor)
                
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
            
            // Description
            Text(description)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [aiColor.opacity(0.4), aiColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Alert Type Button

private struct AlertTypeButton: View {
    let type: AddAlertView.AlertType
    let isSelected: Bool
    let isLocked: Bool
    let action: () -> Void
    
    /// AI-Enhanced uses purple; standard alert controls use premium gold.
    private var accentColor: Color {
        type == .aiPowered ? Color(red: 0.58, green: 0.35, blue: 0.98) : AddAlertDesign.controlAccent
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? accentColor.opacity(0.2)
                                : DS.Adaptive.chipBackground
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: type.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? accentColor
                                : (isLocked ? DS.Adaptive.textTertiary : DS.Adaptive.textSecondary)
                        )
                    
                    // Lock badge for locked features
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(BrandColors.goldBase)
                            )
                            .offset(x: 16, y: -16)
                    }
                }
                
                Text(type.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        isSelected
                            ? DS.Adaptive.textPrimary
                            : (isLocked ? DS.Adaptive.textTertiary : DS.Adaptive.textSecondary)
                    )
                
                if isLocked {
                    Text("PRO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(BrandColors.goldBase)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(BrandColors.goldBase.opacity(0.15))
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? accentColor : DS.Adaptive.stroke,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            // Subtle glow behind the AI-Enhanced button when selected
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.displayName) alert type")
        .accessibilityHint(isLocked ? "Requires Pro subscription" : (isSelected ? "Currently selected" : "Double tap to select"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// (AlertExchangePicker removed — exchange picker was not saving its value)

// MARK: - Condition Type Chip

private struct ConditionTypeChip: View {
    let type: AlertConditionType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(type.rawValue)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.white : DS.Adaptive.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? AddAlertDesign.controlAccent : DS.Adaptive.chipBackground)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : DS.Adaptive.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.rawValue) condition")
        .accessibilityHint(isSelected ? "Currently selected condition type" : "Double tap to choose this condition type")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Timeframe Chip

private struct TimeframeChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let timeframe: AlertTimeframe
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        let isDark = colorScheme == .dark
        Button(action: action) {
            Text(timeframe.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : DS.Adaptive.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? AddAlertDesign.controlAccent.opacity(isDark ? 0.9 : 0.86) : DS.Adaptive.chipBackground)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? AddAlertDesign.controlAccent.opacity(isDark ? 0.7 : 0.5) : DS.Adaptive.stroke.opacity(0.85),
                            lineWidth: 0.9
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(timeframe.displayName) timeframe")
        .accessibilityHint(isSelected ? "Currently selected timeframe" : "Double tap to choose this timeframe")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Frequency Card

private struct FrequencyCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let frequency: AlertFrequency
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        let isDark = colorScheme == .dark
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: frequency.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(frequency.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : DS.Adaptive.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AddAlertDesign.controlAccent.opacity(isDark ? 0.9 : 0.86) : DS.Adaptive.chipBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? AddAlertDesign.controlAccent.opacity(isDark ? 0.7 : 0.5) : DS.Adaptive.stroke.opacity(0.8),
                        lineWidth: 0.9
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(frequency.displayName) alert frequency")
        .accessibilityHint(frequency.description)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    AddAlertView()
        .preferredColorScheme(.dark)
}
