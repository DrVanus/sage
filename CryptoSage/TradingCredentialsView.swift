//
//  TradingCredentialsView.swift
//  CryptoSage
//
//  Exchange API credentials management with enhanced UI.
//

import SwiftUI

struct TradingCredentialsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    @State private var showApiKey: Bool = false
    @State private var isConnected: Bool = false
    @State private var isTesting: Bool = false
    @State private var isSaving: Bool = false
    @State private var statusMessage: String?
    @State private var statusType: StatusType = .info
    
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
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            credentialsHeader
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Hero Section
                    heroSection
                        .padding(.top, 8)
                    
                    // Connection Status
                    connectionStatusCard
                    
                    // API Credentials Form
                    credentialsForm
                    
                    // Action Buttons
                    actionButtons
                    
                    // Security Notice
                    securityNotice
                    
                    // Help Link
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
        .onAppear {
            loadExistingCredentials()
        }
    }
    
    // MARK: - Header
    
    private var credentialsHeader: some View {
        HStack {
            CSNavButton(
                icon: "chevron.left",
                action: { dismiss() }
            )
            
            Spacer()
            
            Text("Exchange API Keys")
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
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [BrandColors.goldBase.opacity(0.3), BrandColors.goldBase.opacity(0)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldBase.opacity(0.2), BrandColors.goldDark.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                    .overlay(
                        Circle()
                            .stroke(BrandColors.goldBase.opacity(0.4), lineWidth: 2)
                    )
                
                Image(systemName: "key.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldBase, BrandColors.goldLight],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            Text("Connect Your Exchange")
                .font(.title2.weight(.bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Add your API credentials to enable portfolio syncing and trade execution.")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Connection Status Card
    
    private var connectionStatusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isConnected ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isConnected ? .green : DS.Adaptive.textTertiary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Connection Status")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(isConnected ? "Connected & Active" : "Not Connected")
                    .font(.caption)
                    .foregroundColor(isConnected ? .green : DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            if isConnected {
                Text("Active")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isConnected ? Color.green.opacity(0.5) : DS.Adaptive.stroke, lineWidth: isConnected ? 1.5 : 0.5)
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
                    
                    HStack {
                        if showApiKey {
                            TextField("Enter your API key", text: $apiKey)
                                .font(.system(.body, design: .monospaced))
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("Enter your API key", text: $apiKey)
                                .font(.system(.body, design: .monospaced))
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        
                        Button(action: {
                            impactLight.impactOccurred()
                            showApiKey.toggle()
                        }) {
                            Image(systemName: showApiKey ? "eye.slash.fill" : "eye.fill")
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
                
                Divider().background(DS.Adaptive.stroke)
                
                // API Secret Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Secret")
                        .font(.caption.weight(.medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    SecureField("Enter your API secret", text: $apiSecret)
                        .font(.system(.body, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
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
                    Image(systemName: statusType == .success ? "checkmark.circle.fill" : (statusType == .error ? "exclamationmark.circle.fill" : "info.circle.fill"))
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
            .disabled(apiKey.isEmpty || apiSecret.isEmpty || isTesting)
            .opacity((apiKey.isEmpty || apiSecret.isEmpty) ? 0.5 : 1)
            
            // Save Credentials Button
            Button(action: saveCredentials) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(isSaving ? "Saving..." : "Save Credentials")
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
            .disabled(apiKey.isEmpty || apiSecret.isEmpty || isSaving)
            .opacity((apiKey.isEmpty || apiSecret.isEmpty) ? 0.5 : 1)
            
            // Remove Credentials Button (if connected)
            if isConnected {
                Button(action: removeCredentials) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Remove Credentials")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(.red)
                }
                        .padding(.top, 8)
            }
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
            Text("Need help finding your API keys?")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Button(action: {
                impactLight.impactOccurred()
                if let url = URL(string: "https://www.3commas.io/blog/how-to-create-api-keys") {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 14))
                    Text("View Setup Guide")
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(BrandColors.goldBase)
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadExistingCredentials() {
        do {
            let savedKey = try KeychainHelper.shared.read(service: "3Commas", account: "trading_key")
            let savedSecret = try KeychainHelper.shared.read(service: "3Commas", account: "trading_secret")
            apiKey = savedKey
            apiSecret = savedSecret
            isConnected = true
        } catch {
            // No existing credentials
            isConnected = false
        }
    }
    
    private func testConnection() {
        impactMedium.impactOccurred()
        isTesting = true
        statusMessage = nil
        
        Task {
            do {
                // Actually test connection with 3Commas API
                let success = try await ThreeCommasAPI.shared.connect(
                    apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiSecret: apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                
                await MainActor.run {
                    isTesting = false
                    if success {
                        notificationFeedback.notificationOccurred(.success)
                        statusMessage = "Connection successful! API keys are valid."
                        statusType = .success
                    } else {
                        notificationFeedback.notificationOccurred(.error)
                        statusMessage = "Connection failed. Please check your credentials."
                        statusType = .error
                    }
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    notificationFeedback.notificationOccurred(.error)
                    statusMessage = "Error: \(error.localizedDescription)"
                    statusType = .error
                }
            }
        }
    }

    private func saveCredentials() {
        impactMedium.impactOccurred()
        isSaving = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        do {
            try KeychainHelper.shared.save(apiKey, service: "3Commas", account: "trading_key")
            try KeychainHelper.shared.save(apiSecret, service: "3Commas", account: "trading_secret")
                
                notificationFeedback.notificationOccurred(.success)
                statusMessage = "Credentials saved securely!"
                statusType = .success
                isConnected = true
            } catch {
                notificationFeedback.notificationOccurred(.error)
                statusMessage = "Error saving: \(error.localizedDescription)"
                statusType = .error
            }
            
            isSaving = false
        }
    }
    
    private func removeCredentials() {
        impactMedium.impactOccurred()
        
        do {
            try KeychainHelper.shared.delete(service: "3Commas", account: "trading_key")
            try KeychainHelper.shared.delete(service: "3Commas", account: "trading_secret")
            
            apiKey = ""
            apiSecret = ""
            isConnected = false
            notificationFeedback.notificationOccurred(.success)
            statusMessage = "Credentials removed."
            statusType = .info
        } catch {
            notificationFeedback.notificationOccurred(.error)
            statusMessage = "Error removing credentials."
            statusType = .error
        }
    }
}

// MARK: - Preview

struct TradingCredentialsView_Previews: PreviewProvider {
    static var previews: some View {
        TradingCredentialsView()
            .preferredColorScheme(.dark)
    }
}
