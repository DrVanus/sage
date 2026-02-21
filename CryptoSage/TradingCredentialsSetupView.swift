//
//  TradingCredentialsSetupView.swift
//  CryptoSage
//
//  Setup view for adding exchange trading credentials.
//

import SwiftUI

struct TradingCredentialsSetupView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Form State
    @State private var selectedExchange: TradingExchange = .binance
    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    @State private var passphrase: String = ""  // For Coinbase
    @State private var showApiSecret: Bool = false
    
    // Status State
    @State private var isTesting: Bool = false
    @State private var isSaving: Bool = false
    @State private var statusMessage: String?
    @State private var statusType: StatusType = .info
    @State private var hasTestedSuccessfully: Bool = false
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    enum StatusType {
        case success, error, info
        
        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .info: return DS.Adaptive.textSecondary
            }
        }
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    // Check if credentials already exist for selected exchange
    private var credentialsExist: Bool {
        TradingCredentialsManager.shared.hasCredentials(for: selectedExchange)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Exchange Selector
                    exchangeSelector
                        .padding(.top, 8)
                    
                    // Credentials exist warning
                    if credentialsExist {
                        existingCredentialsWarning
                    }
                    
                    // API Key Form
                    credentialsForm
                    
                    // Action Buttons
                    actionButtons
                    
                    // Security Notice
                    securityNotice
                    
                    // Help Section
                    helpSection
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Button(action: {
                impactLight.impactOccurred()
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            }
            
            Spacer()
            
            Text("Add Exchange")
                .font(.headline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Color.clear
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.Adaptive.background)
    }
    
    // MARK: - Exchange Selector
    
    private var exchangeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SELECT EXCHANGE")
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                ForEach(TradingExchange.allCases) { exchange in
                    Button {
                        impactLight.impactOccurred()
                        selectedExchange = exchange
                        // Reset status when changing exchange
                        statusMessage = nil
                        hasTestedSuccessfully = false
                    } label: {
                        HStack(spacing: 12) {
                            // Exchange Icon
                            ZStack {
                                Circle()
                                    .fill(exchangeColor(for: exchange).opacity(0.15))
                                    .frame(width: 40, height: 40)
                                
                                exchangeIcon(for: exchange)
                                    .font(.system(size: 18))
                                    .foregroundColor(exchangeColor(for: exchange))
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exchange.displayName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                
                                Text(exchangeRegion(for: exchange))
                                    .font(.caption)
                                    .foregroundColor(DS.Adaptive.textSecondary)
                            }
                            
                            Spacer()
                            
                            // Selection indicator
                            ZStack {
                                Circle()
                                    .stroke(selectedExchange == exchange ? BrandColors.goldBase : DS.Adaptive.stroke, lineWidth: 2)
                                    .frame(width: 22, height: 22)
                                
                                if selectedExchange == exchange {
                                    Circle()
                                        .fill(BrandColors.goldBase)
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                        .padding(12)
                    }
                    
                    if exchange != TradingExchange.allCases.last {
                        Divider()
                            .background(DS.Adaptive.stroke)
                            .padding(.leading, 64)
                    }
                }
            }
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
    
    // MARK: - Existing Credentials Warning
    
    private var existingCredentialsWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange)
            
            Text("Credentials already exist for \(selectedExchange.displayName). Saving will overwrite existing keys.")
                .font(.caption)
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Credentials Form
    
    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API CREDENTIALS")
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                // API Key Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.caption.weight(.medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    TextField("Enter your API key", text: $apiKey)
                        .font(.system(.body, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textContentType(.none)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                        )
                }
                .padding(16)
                
                Divider().background(DS.Adaptive.stroke)
                
                // API Secret Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Secret")
                        .font(.caption.weight(.medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    HStack {
                        if showApiSecret {
                            TextField("Enter your API secret", text: $apiSecret)
                                .font(.system(.body, design: .monospaced))
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .textContentType(.none)
                        } else {
                            SecureField("Enter your API secret", text: $apiSecret)
                                .font(.system(.body, design: .monospaced))
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .textContentType(.none)
                        }
                        
                        Button(action: {
                            impactLight.impactOccurred()
                            showApiSecret.toggle()
                        }) {
                            Image(systemName: showApiSecret ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 16))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.3))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                    )
                }
                .padding(16)
                
                // Passphrase (Coinbase only)
                if selectedExchange.requiresPassphrase {
                    Divider().background(DS.Adaptive.stroke)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Passphrase")
                            .font(.caption.weight(.medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        SecureField("Enter your API passphrase", text: $passphrase)
                            .font(.system(.body, design: .monospaced))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .textContentType(.none)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.3))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                            )
                        
                        Text("Coinbase requires a passphrase set during API key creation")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .padding(16)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
            
            // Status Message
            if let message = statusMessage {
                HStack(spacing: 8) {
                    Image(systemName: statusType.icon)
                        .foregroundColor(statusType.color)
                    
                    Text(message)
                        .font(.caption)
                        .foregroundColor(statusType.color)
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Test Connection Button
            Button(action: testConnection) {
                HStack(spacing: 8) {
                    if isTesting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: BrandColors.goldBase))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(isTesting ? "Testing..." : "Test Connection")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(BrandColors.goldBase)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(BrandColors.goldBase, lineWidth: 2)
                )
            }
            .disabled(!canTest || isTesting)
            .opacity(canTest ? 1 : 0.5)
            
            // Save Credentials Button
            Button(action: saveCredentials) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(isSaving ? "Saving..." : "Save & Connect")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [BrandColors.goldBase, BrandColors.goldLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .disabled(!canSave || isSaving)
            .opacity(canSave ? 1 : 0.5)
        }
    }
    
    // MARK: - Security Notice
    
    private var securityNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 24))
                .foregroundColor(BrandColors.goldBase)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Keys Are Secure")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Credentials are encrypted and stored locally in Apple's Secure Keychain. We never transmit or store your keys on our servers.")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BrandColors.goldBase.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Help Section
    
    private var helpSection: some View {
        VStack(spacing: 12) {
            Text("Need help creating API keys?")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Button(action: {
                impactLight.impactOccurred()
                openHelpURL()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 14))
                    Text("View \(selectedExchange.displayName) Setup Guide")
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(BrandColors.goldBase)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var canTest: Bool {
        !apiKey.isEmpty && !apiSecret.isEmpty &&
        (!selectedExchange.requiresPassphrase || !passphrase.isEmpty)
    }
    
    private var canSave: Bool {
        canTest // Can save if we can test (all fields filled)
    }
    
    // MARK: - Actions
    
    private func testConnection() {
        impactMedium.impactOccurred()
        isTesting = true
        statusMessage = nil
        
        Task {
            do {
                // Create temporary credentials for testing
                let credentials = TradingCredentials(
                    exchange: selectedExchange,
                    apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiSecret: apiSecret.trimmingCharacters(in: .whitespacesAndNewlines),
                    passphrase: selectedExchange.requiresPassphrase ? passphrase : nil
                )
                
                // Temporarily save to test
                try TradingCredentialsManager.shared.saveCredentials(credentials)
                
                let success = try await TradingExecutionService.shared.testConnection(exchange: selectedExchange)
                
                await MainActor.run {
                    isTesting = false
                    if success {
                        notificationFeedback.notificationOccurred(.success)
                        statusMessage = "Connection successful! API keys are valid."
                        statusType = .success
                        hasTestedSuccessfully = true
                    } else {
                        notificationFeedback.notificationOccurred(.error)
                        statusMessage = "Connection failed. Please check your credentials."
                        statusType = .error
                        hasTestedSuccessfully = false
                        // Remove invalid credentials
                        try? TradingCredentialsManager.shared.deleteCredentials(for: selectedExchange)
                    }
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    notificationFeedback.notificationOccurred(.error)
                    statusMessage = "Error: \(error.localizedDescription)"
                    statusType = .error
                    hasTestedSuccessfully = false
                    // Clean up on error
                    try? TradingCredentialsManager.shared.deleteCredentials(for: selectedExchange)
                }
            }
        }
    }
    
    private func saveCredentials() {
        impactMedium.impactOccurred()
        isSaving = true
        
        Task {
            do {
                let credentials = TradingCredentials(
                    exchange: selectedExchange,
                    apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiSecret: apiSecret.trimmingCharacters(in: .whitespacesAndNewlines),
                    passphrase: selectedExchange.requiresPassphrase ? passphrase : nil
                )
                
                try TradingCredentialsManager.shared.saveCredentials(credentials)
                
                // If not tested yet, test the connection
                if !hasTestedSuccessfully {
                    let success = try await TradingExecutionService.shared.testConnection(exchange: selectedExchange)
                    
                    await MainActor.run {
                        isSaving = false
                        if success {
                            notificationFeedback.notificationOccurred(.success)
                            statusMessage = "Credentials saved and verified!"
                            statusType = .success
                            
                            // Dismiss after brief delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                dismiss()
                            }
                        } else {
                            notificationFeedback.notificationOccurred(.warning)
                            statusMessage = "Saved but connection test failed. Please verify your keys."
                            statusType = .error
                        }
                    }
                } else {
                    await MainActor.run {
                        isSaving = false
                        notificationFeedback.notificationOccurred(.success)
                        statusMessage = "Credentials saved!"
                        statusType = .success
                        
                        // Dismiss after brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            dismiss()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    notificationFeedback.notificationOccurred(.error)
                    statusMessage = "Failed to save: \(error.localizedDescription)"
                    statusType = .error
                }
            }
        }
    }
    
    private func openHelpURL() {
        let urlString: String
        switch selectedExchange {
        case .binance:
            urlString = "https://www.binance.com/en/support/faq/how-to-create-api-keys-on-binance-360002502072"
        case .binanceUS:
            urlString = "https://support.binance.us/hc/en-us/articles/360046787554-How-to-Create-an-API-Key"
        case .coinbase:
            urlString = "https://help.coinbase.com/en/exchange/managing-my-account/how-to-create-an-api-key"
        case .kraken:
            urlString = "https://support.kraken.com/hc/en-us/articles/360000919966-How-to-create-an-API-key"
        case .kucoin:
            urlString = "https://www.kucoin.com/support/360015102174-How-to-Create-an-API"
        case .bybit:
            urlString = "https://www.bybit.com/en-US/help-center/article/How-to-create-API-key"
        case .okx:
            urlString = "https://www.okx.com/help-center/how-to-create-api-key"
        }
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Helper Methods
    
    private func exchangeColor(for exchange: TradingExchange) -> Color {
        switch exchange {
        case .binance, .binanceUS: return .yellow
        case .coinbase: return .blue
        case .kraken: return .purple
        case .kucoin: return .green
        case .bybit: return .orange
        case .okx: return .gray
        }
    }
    
    @ViewBuilder
    private func exchangeIcon(for exchange: TradingExchange) -> some View {
        switch exchange {
        case .binance, .binanceUS:
            Image(systemName: "bitcoinsign.circle.fill")
        case .coinbase:
            Image(systemName: "dollarsign.circle.fill")
        case .kraken:
            Image(systemName: "waveform.circle.fill")
        case .kucoin:
            Image(systemName: "k.circle.fill")
        case .bybit:
            Image(systemName: "b.circle.fill")
        case .okx:
            Image(systemName: "o.circle.fill")
        }
    }
    
    private func exchangeRegion(for exchange: TradingExchange) -> String {
        switch exchange {
        case .binance: return "Global"
        case .binanceUS: return "United States"
        case .coinbase: return "Global"
        case .kraken: return "Global"
        case .kucoin: return "Global"
        case .bybit: return "Global"
        case .okx: return "Global"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TradingCredentialsSetupView()
    }
    .preferredColorScheme(.dark)
}
