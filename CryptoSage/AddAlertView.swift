//
//  AddAlertView.swift
//  CryptoSage
//
//  Premium Add Alert form with glassmorphic styling.
//

import SwiftUI

struct AddAlertView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notificationsManager = NotificationsManager.shared
    
    // MARK: - Subscription Check
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showUpgradePrompt: Bool = false
    
    // Alert type enum
    enum AlertType: String, CaseIterable {
        case standard = "Standard"
        case aiPowered = "AI-Powered"
        
        var displayName: String { rawValue }
        
        var description: String {
            switch self {
            case .standard: return "Simple price threshold alerts"
            case .aiPowered: return "Smart alerts with AI analysis"
            }
        }
        
        var iconName: String {
            switch self {
            case .standard: return "bell.fill"
            case .aiPowered: return "brain.head.profile"
            }
        }
    }
    
    // Form state
    @State private var symbol: String = ""
    @State private var thresholdText: String = ""
    @State private var isAbove: Bool = true
    @State private var enablePush: Bool = true
    @State private var enableEmail: Bool = false
    @State private var enableTelegram: Bool = false
    @State private var showAdvancedOptions: Bool = false
    @State private var currentPrice: Double? = nil
    @State private var selectedAlertType: AlertType = .standard
    
    // Advanced options
    @State private var selectedExchange: String = "Binance"
    @State private var tradingPair: String = ""
    @State private var takeProfitText: String = ""
    @State private var stopLossText: String = ""
    
    // AI-powered alert options (Pro+ only)
    @State private var enableSmartTiming: Bool = false
    @State private var enableSentimentAnalysis: Bool = false
    @State private var enableVolumeSpike: Bool = false
    
    private let exchanges = ["Binance", "Coinbase", "Kraken"]
    private let popularSymbols = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "ADAUSDT", "DOGEUSDT", "BNBUSDT"]
    
    /// Check if user has access to AI-powered alerts
    private var hasAIAlertAccess: Bool {
        subscriptionManager.hasAccess(to: .aiPoweredAlerts)
    }
    
    private var isFormValid: Bool {
        !symbol.isEmpty && !thresholdText.isEmpty && Double(thresholdText) != nil
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Adaptive.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Alert Type Selector
                        FormSection(title: "Alert Type") {
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    ForEach(AlertType.allCases, id: \.rawValue) { type in
                                        AlertTypeButton(
                                            type: type,
                                            isSelected: selectedAlertType == type,
                                            isLocked: type == .aiPowered && !hasAIAlertAccess
                                        ) {
                                            if type == .aiPowered && !hasAIAlertAccess {
                                                showUpgradePrompt = true
                                            } else {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                withAnimation(.spring(response: 0.3)) {
                                                    selectedAlertType = type
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
                        
                        // Symbol Section
                        FormSection(title: "Symbol") {
                            VStack(alignment: .leading, spacing: 12) {
                                PremiumTextField(
                                    placeholder: "Enter symbol (e.g. BTCUSDT)",
                                    text: $symbol,
                                    keyboardType: .default,
                                    capitalization: .characters
                                )
                                .onChange(of: symbol) { _ in
                                    Task { await fetchCurrentPrice() }
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
                                                    .foregroundStyle(symbol == sym ? .black : DS.Adaptive.textSecondary)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(
                                                        Capsule()
                                                            .fill(symbol == sym ? BrandColors.goldBase : DS.Adaptive.chipBackground)
                                                    )
                                                    .overlay(
                                                        Capsule()
                                                            .stroke(symbol == sym ? Color.clear : DS.Adaptive.stroke, lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                
                                // Current price indicator
                                if let price = currentPrice {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                        Text("Current: $\(String(format: "%.2f", price))")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(DS.Adaptive.textSecondary)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                        
                        // Threshold Section
                        FormSection(title: "Price Target") {
                            VStack(alignment: .leading, spacing: 12) {
                                PremiumTextField(
                                    placeholder: "Enter target price",
                                    text: $thresholdText,
                                    keyboardType: .decimalPad
                                )
                                
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
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(DS.Adaptive.chipBackground)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                    )
                                }
                                .padding(.top, 4)
                            }
                        }
                        
                        // Notification Methods Section
                        FormSection(title: "Notification Methods") {
                            VStack(spacing: 0) {
                                PremiumToggleRow(
                                    icon: "bell.fill",
                                    title: "Push Notifications",
                                    subtitle: "Get instant alerts on your device",
                                    isOn: $enablePush
                                )
                                
                                Divider()
                                    .background(DS.Adaptive.divider)
                                    .padding(.horizontal, -16)
                                
                                PremiumToggleRow(
                                    icon: "envelope.fill",
                                    title: "Email Notifications",
                                    subtitle: "Receive alerts via email",
                                    isOn: $enableEmail
                                )
                                
                                Divider()
                                    .background(DS.Adaptive.divider)
                                    .padding(.horizontal, -16)
                                
                                PremiumToggleRow(
                                    icon: "paperplane.fill",
                                    title: "Telegram Notifications",
                                    subtitle: "Get alerts in Telegram",
                                    isOn: $enableTelegram
                                )
                            }
                        }
                        
                        // AI-Powered Options (only shown when AI-Powered type is selected)
                        if selectedAlertType == .aiPowered && hasAIAlertAccess {
                            FormSection(title: "AI Features") {
                                VStack(spacing: 0) {
                                    PremiumToggleRow(
                                        icon: "brain.head.profile",
                                        title: "Sentiment Analysis",
                                        subtitle: "Alert based on market sentiment changes",
                                        isOn: $enableSentimentAnalysis
                                    )
                                    
                                    Divider()
                                        .background(DS.Adaptive.divider)
                                        .padding(.horizontal, -16)
                                    
                                    PremiumToggleRow(
                                        icon: "clock.badge.checkmark.fill",
                                        title: "Smart Timing",
                                        subtitle: "AI suggests optimal alert trigger times",
                                        isOn: $enableSmartTiming
                                    )
                                    
                                    Divider()
                                        .background(DS.Adaptive.divider)
                                        .padding(.horizontal, -16)
                                    
                                    PremiumToggleRow(
                                        icon: "chart.bar.fill",
                                        title: "Volume Spike Detection",
                                        subtitle: "Alert on unusual volume activity",
                                        isOn: $enableVolumeSpike
                                    )
                                }
                            }
                        }
                        
                        // Advanced Options
                        FormSection(title: "Advanced", isExpandable: true, isExpanded: $showAdvancedOptions) {
                            if showAdvancedOptions {
                                VStack(spacing: 16) {
                                    // Exchange picker
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Exchange")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(DS.Adaptive.textSecondary)
                                        
                                        Menu {
                                            ForEach(exchanges, id: \.self) { exchange in
                                                Button(exchange) {
                                                    selectedExchange = exchange
                                                }
                                            }
                                        } label: {
                                            HStack {
                                                Text(selectedExchange)
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundStyle(DS.Adaptive.textPrimary)
                                                Spacer()
                                                Image(systemName: "chevron.down")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(DS.Adaptive.textSecondary)
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
                                    }
                                    
                                    // Take profit
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Take Profit (%)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(DS.Adaptive.textSecondary)
                                        PremiumTextField(
                                            placeholder: "e.g. 10",
                                            text: $takeProfitText,
                                            keyboardType: .decimalPad
                                        )
                                    }
                                    
                                    // Stop loss
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Stop Loss (%)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(DS.Adaptive.textSecondary)
                                        PremiumTextField(
                                            placeholder: "e.g. 5",
                                            text: $stopLossText,
                                            keyboardType: .decimalPad
                                        )
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                        
                        // Save Button
                        Button {
                            saveAlert()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Save Alert")
                                    .font(.system(size: 17, weight: .bold))
                            }
                            .foregroundStyle(isFormValid ? .black : DS.Adaptive.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        isFormValid
                                            ? LinearGradient(
                                                colors: [BrandColors.goldLight, BrandColors.goldBase],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                            : LinearGradient(
                                                colors: [DS.Adaptive.chipBackground, DS.Adaptive.chipBackground],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                    )
                            )
                            .shadow(color: isFormValid ? BrandColors.goldBase.opacity(0.4) : Color.clear, radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isFormValid)
                        .padding(.top, 8)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("New Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .sheet(isPresented: $showUpgradePrompt) {
                FeatureUpgradePromptView(feature: .aiPoweredAlerts)
            }
        }
    }
    
    // MARK: - Actions
    
    private func saveAlert() {
        guard let threshold = Double(thresholdText), !symbol.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Analytics: Track alert creation
        AnalyticsService.shared.track(.alertCreated, parameters: [
            "symbol": symbol.uppercased(),
            "type": isAbove ? "above" : "below"
        ])
        
        notificationsManager.addAlert(
            symbol: symbol.uppercased(),
            threshold: threshold,
            isAbove: isAbove,
            enablePush: enablePush,
            enableEmail: enableEmail,
            enableTelegram: enableTelegram
        )
        dismiss()
    }
    
    private func fetchCurrentPrice() async {
        guard !symbol.isEmpty else {
            currentPrice = nil
            return
        }
        let urlString = "https://api.binance.com/api/v3/ticker/price?symbol=\(symbol.uppercased())"
        guard let url = URL(string: urlString) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(PriceResponse.self, from: data)
            if let value = Double(decoded.price) {
                await MainActor.run {
                    currentPrice = value
                }
            }
        } catch {
            await MainActor.run {
                currentPrice = nil
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
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.Adaptive.chipBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? color : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Premium Toggle Row

private struct PremiumToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BrandColors.goldBase)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(BrandColors.goldBase.opacity(0.12))
                )
            
            // Labels
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            // Toggle
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: BrandColors.goldBase))
                .labelsHidden()
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Alert Type Button

private struct AlertTypeButton: View {
    let type: AddAlertView.AlertType
    let isSelected: Bool
    let isLocked: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? BrandColors.goldBase.opacity(0.2)
                                : DS.Adaptive.chipBackground
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: type.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? BrandColors.goldBase
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
                    .fill(isSelected ? BrandColors.goldBase.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? BrandColors.goldBase : DS.Adaptive.stroke,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddAlertView()
        .preferredColorScheme(.dark)
}
