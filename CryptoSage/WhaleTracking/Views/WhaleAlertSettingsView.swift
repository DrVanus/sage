//
//  WhaleAlertSettingsView.swift
//  CryptoSage
//
//  Settings for whale tracking alerts.
//

import SwiftUI

struct WhaleAlertSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = WhaleTrackingService.shared
    
    @State private var minAmountText: String = ""
    @State private var enabledBlockchains: Set<WhaleBlockchain> = []
    @State private var enablePush: Bool = true
    @State private var showExchangeMovements: Bool = true
    
    // API Keys
    @State private var whaleAlertKey: String = ""
    @State private var arkhamKey: String = ""
    @State private var whaleAlertKeyConfigured: Bool = false
    @State private var arkhamKeyConfigured: Bool = false
    @State private var whaleAlertKeyWasEdited: Bool = false
    @State private var arkhamKeyWasEdited: Bool = false
    
    // Show/hide toggles for API keys
    @State private var showWhaleAlertKey: Bool = false
    @State private var showArkhamKey: Bool = false
    
    // Focus state for keyboard management
    enum Field: Hashable {
        case minAmount
        case whaleAlertKey
        case arkhamKey
    }
    @FocusState private var focusedField: Field?
    
    var body: some View {
        NavigationStack {
            Form {
                // Data Status Section - moved to top for visibility
                dataStatusSection
                
                // Threshold Section
                thresholdSection
                
                // Blockchains Section
                blockchainsSection
                
                // Notifications Section
                notificationsSection
                
                // Premium API Keys Section
                premiumAPISection
                
                // About Section
                aboutSection
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                focusedField = nil
            }
            .navigationTitle("Whale Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        saveSettings()
                    } label: {
                        Text("Save")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
            }
            .onAppear {
                loadCurrentSettings()
            }
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
        }
    }
    
    // MARK: - Data Status Section
    
    private var dataStatusSection: some View {
        Section {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                Text("Data Source")
                Spacer()
                Text(dataSourceText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Adaptive.textSecondary)
            }
            
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.purple)
                    .frame(width: 24)
                Text("Refresh Interval")
                Spacer()
                Text("90 seconds")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Adaptive.textSecondary)
            }
            
            HStack {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundStyle(.orange)
                    .frame(width: 24)
                Text("Last Updated")
                Spacer()
                Text(lastUpdatedText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Adaptive.textSecondary)
            }
            
            HStack {
                Image(systemName: "tray.full.fill")
                    .foregroundStyle(.green)
                    .frame(width: 24)
                Text("Cached Transactions")
                Spacer()
                Text("\(service.recentTransactions.count)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Adaptive.textSecondary)
            }
        } header: {
            Text("Data Status")
        }
    }
    
    // MARK: - Threshold Section
    
    private var thresholdSection: some View {
        Section {
            // Minimum amount input
            HStack {
                Text("Minimum Amount")
                Spacer()
                TextField("1000000", text: $minAmountText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                    .focused($focusedField, equals: .minAmount)
                    .textContentType(.none)
                    .onChange(of: minAmountText) { _, newValue in
                        minAmountText = sanitizeNumericInput(newValue)
                    }
            }
            
            // Format helper
            if let amount = Double(minAmountText) {
                Text("Tracks transactions > \(MarketFormat.largeCurrency(amount, useCurrentCurrency: true))")
                    .font(.caption)
                    .foregroundStyle(DS.Adaptive.textTertiary)
            }
            
            // Quick presets
            HStack(spacing: 8) {
                ForEach(["500K", "1M", "5M", "10M"], id: \.self) { preset in
                    let isSelected = Double(minAmountText) == presetValue(preset)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        let value: Double
                        switch preset {
                        case "500K": value = 500_000
                        case "1M": value = 1_000_000
                        case "5M": value = 5_000_000
                        case "10M": value = 10_000_000
                        default: value = 1_000_000
                        }
                        minAmountText = String(Int(value))
                        focusedField = nil // Dismiss keyboard when preset selected
                    } label: {
                        Text(preset)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isSelected ? .white : DS.Adaptive.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.blue : DS.Adaptive.chipBackground)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? Color.clear : DS.Adaptive.stroke, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Transaction Threshold")
        } footer: {
            Text("Only show transactions above this USD value. Lower thresholds show more activity but may be noisier.")
        }
    }
    
    // MARK: - Blockchains Section
    
    private var blockchainsSection: some View {
        Section {
            // Select All / Deselect All
            HStack {
                Button("Select All") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    enabledBlockchains = Set(WhaleBlockchain.allCases)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.blue)
                
                Spacer()
                
                Button("Deselect All") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    enabledBlockchains.removeAll()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.red)
            }
            .padding(.vertical, 4)
            
            ForEach(WhaleBlockchain.allCases, id: \.rawValue) { chain in
                Toggle(isOn: Binding(
                    get: { enabledBlockchains.contains(chain) },
                    set: { isEnabled in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if isEnabled {
                            enabledBlockchains.insert(chain)
                        } else {
                            enabledBlockchains.remove(chain)
                        }
                    }
                )) {
                    HStack(spacing: 10) {
                        Image(systemName: chain.icon)
                            .foregroundStyle(chain.color)
                            .frame(width: 24)
                        Text(chain.rawValue)
                            .foregroundStyle(DS.Adaptive.textPrimary)
                        
                        Text("(\(chain.symbol))")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                }
            }
        } header: {
            Text("Blockchains")
        } footer: {
            if enabledBlockchains.isEmpty {
                Text("No networks selected. All networks will be re-enabled when you tap Save to avoid an empty feed.")
                    .foregroundStyle(.orange)
            } else {
                Text("Only track whale activity on selected networks. \(enabledBlockchains.count) of \(WhaleBlockchain.allCases.count) networks enabled.")
            }
        }
    }
    
    // MARK: - Notifications Section
    
    private var notificationsSection: some View {
        Section {
            Toggle("Push Notifications", isOn: $enablePush)
            Toggle("Show Exchange Movements", isOn: $showExchangeMovements)
        } header: {
            Text("Notifications")
        } footer: {
            Text("Exchange movements can indicate market sentiment (deposits = bearish, withdrawals = bullish)")
        }
    }
    
    // MARK: - Premium API Section
    
    private var premiumAPISection: some View {
        Section {
            // Whale Alert API Key
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.waveform.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    Text("Whale Alert API")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    
                    Spacer()
                    
                    if whaleAlertKeyConfigured || !whaleAlertKey.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                    }
                }
                
                // Input field with show/hide toggle
                apiKeyInputField(
                    placeholder: "Enter Whale Alert API Key",
                    text: $whaleAlertKey,
                    isRevealed: $showWhaleAlertKey,
                    field: .whaleAlertKey
                )
                .onChange(of: whaleAlertKey) { _, _ in
                    whaleAlertKeyWasEdited = true
                    whaleAlertKeyConfigured = !whaleAlertKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
            .padding(.vertical, 4)
            
            // Arkham API Key
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .foregroundStyle(.purple)
                        .frame(width: 24)
                    Text("Arkham Intelligence API")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    
                    Spacer()
                    
                    if arkhamKeyConfigured || !arkhamKey.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                    }
                }
                
                // Input field with show/hide toggle
                apiKeyInputField(
                    placeholder: "Enter Arkham API Key",
                    text: $arkhamKey,
                    isRevealed: $showArkhamKey,
                    field: .arkhamKey
                )
                .onChange(of: arkhamKey) { _, _ in
                    arkhamKeyWasEdited = true
                    arkhamKeyConfigured = !arkhamKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text("Premium Data Sources")
                Spacer()
                Text("Optional")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add API keys for enhanced data from premium sources. These services provide real-time whale alerts and more comprehensive transaction data.")
                
                // How to get keys
                VStack(alignment: .leading, spacing: 4) {
                    Text("How to get API keys:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Text("• Whale Alert: developer.whale-alert.io ($30/mo, 7-day free trial)")
                        .font(.caption2)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text("• Arkham: platform.arkhamintelligence.com (varies by plan)")
                        .font(.caption2)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                // Active sources
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 12))
                    Text("Active: \(service.availableDataSources.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                if service.hasPremiumAPIKeys {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                        Text("Premium sources enabled")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }
    
    // MARK: - API Key Input Field
    
    @ViewBuilder
    private func apiKeyInputField(
        placeholder: String,
        text: Binding<String>,
        isRevealed: Binding<Bool>,
        field: Field
    ) -> some View {
        HStack(spacing: 8) {
            // Text/SecureField
            Group {
                if isRevealed.wrappedValue {
                    TextField(placeholder, text: text)
                        .textContentType(.none)
                } else {
                    SecureField(placeholder, text: text)
                        .textContentType(.none)
                }
            }
            .font(.system(size: 14, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: field)
            
            // Show/hide toggle button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isRevealed.wrappedValue.toggle()
            } label: {
                Image(systemName: isRevealed.wrappedValue ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(DS.Adaptive.textTertiary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            
            // Clear button (when field has content)
            if !text.wrappedValue.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Adaptive.textTertiary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.chipBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    focusedField == field ? Color.blue : DS.Adaptive.stroke,
                    lineWidth: focusedField == field ? 1.5 : 0.5
                )
        )
        .animation(.easeInOut(duration: 0.15), value: focusedField == field)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = field
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                // What is whale tracking
                VStack(alignment: .leading, spacing: 8) {
                    Label("What is whale tracking?", systemImage: "questionmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    
                    Text("Whale tracking monitors large cryptocurrency movements. When big players (whales) move significant amounts, it can signal upcoming market activity.")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                }
                
                Divider()
                
                // Movement types
                VStack(alignment: .leading, spacing: 12) {
                    Text("Movement Types")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    
                    movementTypeRow(
                        icon: "arrow.down.to.line",
                        title: "Exchange Deposit",
                        description: "Crypto moving TO exchange - may indicate selling intent",
                        sentiment: "Bearish",
                        color: .red
                    )
                    
                    movementTypeRow(
                        icon: "arrow.up.to.line",
                        title: "Exchange Withdrawal",
                        description: "Crypto moving FROM exchange - may indicate accumulation",
                        sentiment: "Bullish",
                        color: .green
                    )
                    
                    movementTypeRow(
                        icon: "arrow.left.arrow.right",
                        title: "Wallet Transfer",
                        description: "Between wallets - could be rebalancing or OTC trade",
                        sentiment: "Neutral",
                        color: .gray
                    )
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("About")
        }
    }
    
    // MARK: - Helper Views & Functions
    
    private var dataSourceText: String {
        let freshness: String
        if service.isDataStale {
            freshness = "Stale"
        } else if service.isUsingCachedData {
            freshness = "Cached"
        } else {
            freshness = "Live"
        }
        
        switch service.dataSourceStatus {
        case .idle: return "\(freshness) • Ready"
        case .fetching: return "Refreshing..."
        case .success(let source): return "\(freshness) • \(source)"
        case .usingFallback: return "Connecting..."
        case .error: return "Connection error"
        }
    }
    
    private var lastUpdatedText: String {
        guard let updatedAt = service.lastDataUpdatedAt else { return "Unknown" }
        return WhaleRelativeTimeFormatter.format(updatedAt)
    }
    
    private func presetValue(_ preset: String) -> Double {
        switch preset {
        case "500K": return 500_000
        case "1M": return 1_000_000
        case "5M": return 5_000_000
        case "10M": return 10_000_000
        default: return 1_000_000
        }
    }
    
    private func sanitizeNumericInput(_ input: String) -> String {
        let digitsOnly = input.filter(\.isNumber)
        // Keep UX responsive while user edits; hard bounds are applied on save.
        return String(digitsOnly.prefix(12))
    }
    
    private func clampedMinAmount(from input: String) -> Double {
        let parsed = Double(input) ?? WhaleAlertConfig.defaultConfig.minAmountUSD
        return min(max(parsed, 10_000), 100_000_000)
    }
    
    private func movementTypeRow(icon: String, title: String, description: String, sentiment: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(color.opacity(0.15))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    
                    Text("• \(sentiment)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                }
                
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Adaptive.textTertiary)
            }
        }
    }
    
    private func loadCurrentSettings() {
        let config = service.config
        minAmountText = String(Int(config.minAmountUSD))
        enabledBlockchains = config.enabledBlockchains
        enablePush = config.enablePushNotifications
        showExchangeMovements = config.showExchangeMovements
        
        // SECURITY FIX: Load API keys from Keychain via service (not UserDefaults)
        // Keys are read-only here - we just check if they exist to show "configured" state
        // Never populate text fields with masked placeholders. We only show configured state.
        whaleAlertKeyConfigured = service.hasWhaleAlertAPIKey
        arkhamKeyConfigured = service.hasArkhamAPIKey
        whaleAlertKey = ""
        arkhamKey = ""
        whaleAlertKeyWasEdited = false
        arkhamKeyWasEdited = false
    }
    
    private func saveSettings() {
        let minAmount = clampedMinAmount(from: minAmountText)
        if enabledBlockchains.isEmpty {
            enabledBlockchains = Set(WhaleBlockchain.allCases)
        }
        let newConfig = WhaleAlertConfig(
            minAmountUSD: minAmount,
            enabledBlockchains: enabledBlockchains,
            enablePushNotifications: enablePush,
            showExchangeMovements: showExchangeMovements
        )
        service.updateConfig(newConfig)
        
        // Save API keys only if user intentionally edited the field this session.
        if whaleAlertKeyWasEdited {
            let key = whaleAlertKey.trimmingCharacters(in: .whitespacesAndNewlines)
            service.setWhaleAlertAPIKey(key.isEmpty ? nil : key)
        }
        if arkhamKeyWasEdited {
            let key = arkhamKey.trimmingCharacters(in: .whitespacesAndNewlines)
            service.setArkhamAPIKey(key.isEmpty ? nil : key)
        }
        
        // Success haptic
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        dismiss()
    }
}

#Preview {
    WhaleAlertSettingsView()
        .preferredColorScheme(.dark)
}
