import SwiftUI
import UIKit

/// Official 3commas brand color (#14c9bc)
private let threeCommasColor = Color(red: 0.078, green: 0.784, blue: 0.737)

struct Link3CommasView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var accountsManager = ConnectedAccountsManager.shared

    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    @State private var isSaving: Bool = false
    @State private var showSuccessAlert: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    private var isDark: Bool { colorScheme == .dark }

    private var isFormValid: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty &&
        !apiSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            // Adaptive background
            if isDark {
                FuturisticBackground()
                    .ignoresSafeArea()
            } else {
                DS.Adaptive.background
                    .ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                // Custom top bar
                CSPageHeader(title: "3Commas", leadingAction: {
                    presentationMode.wrappedValue.dismiss()
                })
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header with logo
                        headerSection
                        
                        // Input fields
                        inputSection
                        
                        // Connect button
                        connectButton
                        
                        // Help links
                        helpSection
                        
                        // Security notice
                        securityNotice
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 20)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .alert("Connected Successfully", isPresented: $showSuccessAlert) {
            Button("Done") {
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text("Your 3Commas account has been linked successfully.")
        }
        .alert("Connection Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { presentationMode.wrappedValue.dismiss() })
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // 3Commas logo placeholder
            ZStack {
                Circle()
                    .fill(threeCommasColor.opacity(isDark ? 0.15 : 0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(threeCommasColor)
            }
            
            VStack(spacing: 8) {
                Text("Connect 3Commas")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Link your 3Commas account to enable\ntrading bots and advanced features")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        VStack(spacing: 16) {
            // API Key Field
            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                TextField("Enter your 3Commas API key", text: $apiKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .background(isDark ? Color.white.opacity(0.08) : DS.Adaptive.cardBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isDark ? Color.white.opacity(0.1) : DS.Adaptive.stroke, lineWidth: 1)
                    )
            }
            
            // API Secret Field
            VStack(alignment: .leading, spacing: 6) {
                Text("API Secret")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                SecureField("Enter your 3Commas API secret", text: $apiSecret)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .background(isDark ? Color.white.opacity(0.08) : DS.Adaptive.cardBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isDark ? Color.white.opacity(0.1) : DS.Adaptive.stroke, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Connect Button
    
    private var connectButton: some View {
        Button(action: saveCredentials) {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Connect Account")
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: isFormValid
                        ? [threeCommasColor, threeCommasColor.opacity(0.8)]
                        : [Color.gray.opacity(isDark ? 0.3 : 0.4), Color.gray.opacity(isDark ? 0.2 : 0.3)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(14)
        }
        .disabled(!isFormValid || isSaving)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Help Section
    
    private var helpSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                if let url = URL(string: "https://3commas.io/api_access_tokens") {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill")
                        .font(.caption)
                    Text("Get your API key from 3commas.io")
                        .font(.subheadline)
                }
                .foregroundColor(threeCommasColor)
            }
            
            Button(action: {
                if let url = URL(string: "https://3commas.io/help/articles/setting-up-api-access-tokens") {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                    Text("How to create an API key")
                        .font(.subheadline)
                }
                .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
    }
    
    // MARK: - Security Notice
    
    private var securityNotice: some View {
        VStack(spacing: 8) {
            Divider()
                .background(isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.08))
                .padding(.horizontal, 40)
            
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("Credentials stored securely in Keychain")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Text("Use read-only API permissions for portfolio tracking.\nEnable trading permissions only if needed.")
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
    
    // MARK: - Save Credentials
    
    private func saveCredentials() {
        guard isFormValid else { return }
        
        isSaving = true
        
        Task {
            do {
                let success = try await ThreeCommasAPI.shared.connect(
                    apiKey: apiKey.trimmingCharacters(in: .whitespaces),
                    apiSecret: apiSecret.trimmingCharacters(in: .whitespaces)
                )
                
                await MainActor.run {
                    isSaving = false
                    
                    if success {
                        // Save to keychain
                        try? KeychainHelper.shared.save(apiKey, service: "CryptoSage.3Commas", account: "api_key")
                        try? KeychainHelper.shared.save(apiSecret, service: "CryptoSage.3Commas", account: "api_secret")
                        
                        // Add to connected accounts
                        let account = ConnectedAccount(
                            name: "3Commas",
                            exchangeType: "exchange",
                            provider: "3commas",
                            isDefault: accountsManager.accounts.isEmpty,
                            connectedAt: Date()
                        )
                        accountsManager.addAccount(account)
                        
                        showSuccessAlert = true
                    } else {
                        errorMessage = "Invalid API credentials. Please check your API key and secret."
                        showErrorAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}

struct Link3CommasView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            Link3CommasView()
        }
    }
}
