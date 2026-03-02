//
//  APIKeySettingsView.swift
//  CryptoSage
//
//  User interface for managing API keys securely.
//  Allows users to enter, view (masked), and delete their own API keys.
//

import SwiftUI

// MARK: - API Key Settings View

struct APIKeySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // State
    @State private var openAIKey: String = ""
    @State private var newsAPIKey: String = ""
    @State private var threeCommasAPIKey: String = ""
    @State private var threeCommasSecret: String = ""
    @State private var binanceAPIKey: String = ""
    @State private var binanceSecret: String = ""
    
    // UI State
    @State private var showOpenAIKey: Bool = false
    @State private var showNewsAPIKey: Bool = false
    @State private var show3CommasKey: Bool = false
    @State private var show3CommasSecret: Bool = false
    @State private var showBinanceKey: Bool = false
    @State private var showBinanceSecret: Bool = false
    
    @State private var showSaveSuccess: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var keyToDelete: String = ""
    
    // Haptics
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    var body: some View {
        NavigationStack {
            Form {
                // Info section
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 212/255, green: 175/255, blue: 55/255),
                                             Color(red: 170/255, green: 140/255, blue: 44/255)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Secure Storage")
                                .font(.headline)
                            Text("API keys are encrypted and stored locally in your device's Keychain. They never leave your device.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // OpenAI API Key
                Section(header: Text("AI Chat (OpenAI)")) {
                    apiKeyRow(
                        title: "OpenAI API Key",
                        placeholder: "sk-...",
                        value: $openAIKey,
                        isVisible: $showOpenAIKey,
                        currentValue: maskedKey(APIConfig.openAIKey),
                        hasKey: APIConfig.hasValidOpenAIKey,
                        onSave: {
                            saveOpenAIKey()
                        },
                        onDelete: {
                            keyToDelete = "openai"
                            showDeleteConfirm = true
                        }
                    )
                    
                    Text("Required for AI chat features. Get your key from platform.openai.com")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // News API Key
                Section(header: Text("Crypto News")) {
                    apiKeyRow(
                        title: "NewsAPI Key",
                        placeholder: "Your NewsAPI key",
                        value: $newsAPIKey,
                        isVisible: $showNewsAPIKey,
                        currentValue: maskedKey(APIConfig.newsAPIKey),
                        hasKey: !APIConfig.newsAPIKey.isEmpty && APIConfig.newsAPIKey != "YOUR_NEWSAPI_KEY",
                        onSave: {
                            saveNewsAPIKey()
                        },
                        onDelete: {
                            keyToDelete = "newsapi"
                            showDeleteConfirm = true
                        }
                    )
                    
                    Text("Optional. Get a free key from newsapi.org")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 3Commas API
                Section(header: Text("3Commas Trading")) {
                    apiKeyRow(
                        title: "API Key",
                        placeholder: "3Commas API Key",
                        value: $threeCommasAPIKey,
                        isVisible: $show3CommasKey,
                        currentValue: maskedKey(ThreeCommasConfig.tradingAPIKey),
                        hasKey: !ThreeCommasConfig.tradingAPIKey.isEmpty,
                        onSave: {
                            save3CommasAPIKey()
                        },
                        onDelete: {
                            keyToDelete = "3commas_key"
                            showDeleteConfirm = true
                        }
                    )
                    
                    apiKeyRow(
                        title: "API Secret",
                        placeholder: "3Commas API Secret",
                        value: $threeCommasSecret,
                        isVisible: $show3CommasSecret,
                        currentValue: maskedKey(ThreeCommasConfig.tradingSecret),
                        hasKey: !ThreeCommasConfig.tradingSecret.isEmpty,
                        onSave: {
                            save3CommasSecret()
                        },
                        onDelete: {
                            keyToDelete = "3commas_secret"
                            showDeleteConfirm = true
                        }
                    )
                    
                    Text("Connect to 3Commas for automated trading features")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Binance API (if user wants direct connection)
                Section(header: Text("Binance Direct")) {
                    apiKeyRow(
                        title: "API Key",
                        placeholder: "Binance API Key",
                        value: $binanceAPIKey,
                        isVisible: $showBinanceKey,
                        currentValue: maskedKey(loadBinanceKey()),
                        hasKey: !loadBinanceKey().isEmpty,
                        onSave: {
                            saveBinanceAPIKey()
                        },
                        onDelete: {
                            keyToDelete = "binance_key"
                            showDeleteConfirm = true
                        }
                    )
                    
                    apiKeyRow(
                        title: "API Secret",
                        placeholder: "Binance API Secret",
                        value: $binanceSecret,
                        isVisible: $showBinanceSecret,
                        currentValue: maskedKey(loadBinanceSecret()),
                        hasKey: !loadBinanceSecret().isEmpty,
                        onSave: {
                            saveBinanceSecret()
                        },
                        onDelete: {
                            keyToDelete = "binance_secret"
                            showDeleteConfirm = true
                        }
                    )
                    
                    Text("Optional. For direct Binance API access")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Security Tips
                Section(header: Text("Security Tips")) {
                    securityTipRow(
                        icon: "checkmark.shield.fill",
                        text: "Use API keys with read-only permissions when possible"
                    )
                    securityTipRow(
                        icon: "network.badge.shield.half.filled",
                        text: "Enable IP whitelisting on exchange API settings"
                    )
                    securityTipRow(
                        icon: "exclamationmark.triangle.fill",
                        text: "Never share your API keys with anyone"
                    )
                }
            }
            .navigationTitle("API Keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
            }
            .alert("Delete API Key?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteKey(keyToDelete)
                }
            } message: {
                Text("This will remove the API key from your device. You'll need to enter it again to use related features.")
            }
            .overlay {
                if showSaveSuccess {
                    saveSuccessOverlay
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func apiKeyRow(
        title: String,
        placeholder: String,
        value: Binding<String>,
        isVisible: Binding<Bool>,
        currentValue: String,
        hasKey: Bool,
        onSave: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                
                Spacer()
                
                if hasKey {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            
            if hasKey && value.wrappedValue.isEmpty {
                // Show current (masked) value
                HStack {
                    Text(currentValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Change") {
                        impactLight.impactOccurred()
                        value.wrappedValue = ""
                        isVisible.wrappedValue = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    
                    Button("Delete") {
                        impactLight.impactOccurred()
                        onDelete()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            } else {
                // Input field
                HStack {
                    if isVisible.wrappedValue {
                        TextField(placeholder, text: value)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField(placeholder, text: value)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    
                    Button(action: {
                        isVisible.wrappedValue.toggle()
                    }) {
                        Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }
                
                if !value.wrappedValue.isEmpty {
                    HStack {
                        Spacer()
                        
                        Button("Save") {
                            impactLight.impactOccurred()
                            onSave()
                            showSaveSuccessAnimation()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 212/255, green: 175/255, blue: 55/255),
                                                 Color(red: 170/255, green: 140/255, blue: 44/255)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        
                        Button("Cancel") {
                            value.wrappedValue = ""
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func securityTipRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 24)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var saveSuccessOverlay: some View {
        VStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Saved Securely")
                .font(.headline)
                .padding(.top, 8)
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(DS.Adaptive.cardBackground)
        )
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Helpers
    
    private func maskedKey(_ key: String) -> String {
        guard !key.isEmpty, key != "YOUR_NEWSAPI_KEY", key != "keygoeshere" else {
            return "Not configured"
        }
        return APIConfig.maskAPIKey(key)
    }
    
    private func showSaveSuccessAnimation() {
        notificationFeedback.notificationOccurred(.success)
        withAnimation(.spring(response: 0.3)) {
            showSaveSuccess = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3)) {
                showSaveSuccess = false
            }
        }
    }
    
    // MARK: - Save Actions
    
    private func saveOpenAIKey() {
        guard !openAIKey.isEmpty else { return }
        do {
            try APIConfig.setOpenAIKey(openAIKey)
            openAIKey = ""
            #if DEBUG
            print("✅ OpenAI key saved to Keychain")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to save OpenAI key: \(error)")
            #endif
        }
    }
    
    private func saveNewsAPIKey() {
        guard !newsAPIKey.isEmpty else { return }
        do {
            try APIConfig.setNewsAPIKey(newsAPIKey)
            newsAPIKey = ""
            #if DEBUG
            print("✅ NewsAPI key saved to Keychain")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to save NewsAPI key: \(error)")
            #endif
        }
    }
    
    private func save3CommasAPIKey() {
        guard !threeCommasAPIKey.isEmpty else { return }
        do {
            try KeychainHelper.shared.save(
                threeCommasAPIKey,
                service: "CryptoSage.3Commas",
                account: "3COMMAS_TRADING_API_KEY"
            )
            threeCommasAPIKey = ""
            #if DEBUG
            print("✅ 3Commas API key saved to Keychain")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to save 3Commas key: \(error)")
            #endif
        }
    }
    
    private func save3CommasSecret() {
        guard !threeCommasSecret.isEmpty else { return }
        do {
            try KeychainHelper.shared.save(
                threeCommasSecret,
                service: "CryptoSage.3Commas",
                account: "3COMMAS_TRADING_SECRET"
            )
            threeCommasSecret = ""
            #if DEBUG
            print("✅ 3Commas secret saved to Keychain")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to save 3Commas secret: \(error)")
            #endif
        }
    }
    
    private func saveBinanceAPIKey() {
        guard !binanceAPIKey.isEmpty else { return }
        do {
            try SecureUserDataManager.shared.saveAPIKey(binanceAPIKey, for: "binance")
            binanceAPIKey = ""
            #if DEBUG
            print("✅ Binance API key saved to Keychain")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to save Binance key: \(error)")
            #endif
        }
    }
    
    private func saveBinanceSecret() {
        guard !binanceSecret.isEmpty else { return }
        do {
            try SecureUserDataManager.shared.saveAPISecret(binanceSecret, for: "binance")
            binanceSecret = ""
            #if DEBUG
            print("✅ Binance secret saved to Keychain")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to save Binance secret: \(error)")
            #endif
        }
    }
    
    // MARK: - Load Helpers
    
    private func loadBinanceKey() -> String {
        SecureUserDataManager.shared.loadAPIKey(for: "binance") ?? ""
    }
    
    private func loadBinanceSecret() -> String {
        SecureUserDataManager.shared.loadAPISecret(for: "binance") ?? ""
    }
    
    // MARK: - Delete Actions
    
    private func deleteKey(_ keyId: String) {
        switch keyId {
        case "openai":
            APIConfig.removeOpenAIKey()
        case "newsapi":
            try? KeychainHelper.shared.delete(service: "CryptoSage.APIKeys", account: "newsapi_key")
        case "3commas_key":
            try? KeychainHelper.shared.delete(service: "CryptoSage.3Commas", account: "3COMMAS_TRADING_API_KEY")
        case "3commas_secret":
            try? KeychainHelper.shared.delete(service: "CryptoSage.3Commas", account: "3COMMAS_TRADING_SECRET")
        case "binance_key":
            SecureUserDataManager.shared.deleteAPIKey(for: "binance")
        case "binance_secret":
            SecureUserDataManager.shared.deleteAPISecret(for: "binance")
        default:
            break
        }
        
        notificationFeedback.notificationOccurred(.success)
        #if DEBUG
        print("🗑️ Deleted key: \(keyId)")
        #endif
    }
}

// MARK: - Preview

#Preview {
    APIKeySettingsView()
}
