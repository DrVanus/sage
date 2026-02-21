import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - QRCodeView
/// Generates a QR code image from a provided string.
struct QRCodeView: View {
    let uriString: String
    
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()
    
    var body: some View {
        if let qrImage = generateQRCode(from: uriString) {
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
        } else {
            Text("Unable to generate QR Code")
                .foregroundColor(.red)
        }
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        
        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
}

// MARK: - ExchangeConnectionView
struct ExchangeConnectionView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Exchange name and connection method
    let exchangeName: String
    let connectionMethod: ConnectionType
    
    // Connected accounts manager
    @ObservedObject private var accountsManager = ConnectedAccountsManager.shared
    
    // Fields for API key input
    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    @State private var passphrase: String = "" // For exchanges that require it (KuCoin, OKX)
    
    // Field for wallet address
    @State private var walletAddress: String = ""
    @State private var detectedChain: String = ""
    
    // Connection states
    @State private var isConnecting: Bool = false
    @State private var connectionError: String? = nil
    @State private var showSuccessAlert: Bool = false
    
    // Check if already connected
    private var isAlreadyConnected: Bool {
        accountsManager.isConnected(exchangeName: exchangeName)
    }
    
    // Check if exchange requires passphrase
    private var requiresPassphrase: Bool {
        let lowercased = exchangeName.lowercased()
        return lowercased.contains("kucoin") || lowercased.contains("okx") || lowercased.contains("bitget")
    }
    
    init(exchangeName: String = "Exchange", connectionMethod: ConnectionType = .apiKey) {
        self.exchangeName = exchangeName
        self.connectionMethod = connectionMethod
    }
    
    var body: some View {
        ZStack {
            if isDark {
                FuturisticBackground()
                    .ignoresSafeArea()
            } else {
                DS.Adaptive.background
                    .ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                // MARK: - Custom Top Bar
                CSPageHeader(title: "Connect \(exchangeName)") {
                    presentationMode.wrappedValue.dismiss()
                }
                
                // MARK: - Main Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Exchange logo and name
                        exchangeHeader
                        
                        if isAlreadyConnected {
                            // Already connected state
                            connectedCard
                        } else {
                            // Show appropriate connection method
                            switch connectionMethod {
                            case .oauth:
                                oauthCard
                            case .apiKey:
                                apiKeyCard
                            case .walletAddress:
                                walletAddressCard
                            case .threeCommas:
                                threeCommasCard
                            }
                        }
                        
                        Spacer(minLength: 30)
                    }
                    .padding(.bottom, 20)
                }
                .scrollViewBackSwipeFix()
            }
        }
        .alert("Connection Successful", isPresented: $showSuccessAlert) {
            Button("OK") {
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text("\(exchangeName) has been connected successfully!")
        }
        .alert("Connection Error", isPresented: .init(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )) {
            Button("OK", role: .cancel) {
                connectionError = nil
            }
        } message: {
            Text(connectionError ?? "Unknown error")
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { presentationMode.wrappedValue.dismiss() })
    }
    
    // MARK: - Exchange Header
    private var exchangeHeader: some View {
        VStack(spacing: 12) {
            ExchangeLogoView(name: exchangeName, size: 72)
            
            Text(exchangeName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            // Connection method badge
            HStack(spacing: 6) {
                Image(systemName: connectionMethodIcon)
                    .font(.caption)
                Text(connectionMethod.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(connectionMethodColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(connectionMethodColor.opacity(0.15))
            .cornerRadius(12)
            
            if isAlreadyConnected {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.top, 20)
    }
    
    private var connectionMethodIcon: String {
        switch connectionMethod {
        case .oauth: return "bolt.fill"
        case .apiKey: return "key.fill"
        case .walletAddress: return "wallet.pass.fill"
        case .threeCommas: return "link"
        }
    }
    
    private var connectionMethodColor: Color {
        switch connectionMethod {
        case .oauth: return .green
        case .apiKey: return .orange
        case .walletAddress: return .purple
        case .threeCommas: return .cyan
        }
    }
    
    // MARK: - Connected Card
    private var connectedCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("Already Connected")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("This account is already linked to your portfolio.")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
            // Disconnect button
                Button(action: {
                if let account = accountsManager.account(for: exchangeName) {
                    accountsManager.removeAccount(account)
                    presentationMode.wrappedValue.dismiss()
                }
                }) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Disconnect")
                }
                        .font(.headline)
                .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.15))
                .cornerRadius(12)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(isDark ? Color.black.opacity(0.2) : DS.Adaptive.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isDark ? Color.clear : DS.Adaptive.stroke, lineWidth: isDark ? 0 : 1)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - OAuth Card (Coinbase, Kraken, Gemini)
    private var oauthCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.circle.fill")
                    .foregroundColor(.green)
                Text("Secure Login")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            Text("Connect securely with your \(exchangeName) account. You'll be redirected to \(exchangeName) to authorize read-only access.")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            
            // Don't have an account? Sign up section
            noAccountSignUpSection
            
            // Features list
            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "checkmark.shield.fill", text: "Secure OAuth 2.0 authentication", color: .green)
                featureRow(icon: "eye.fill", text: "Read-only access to balances", color: .blue)
                featureRow(icon: "lock.fill", text: "No API keys stored", color: .purple)
            }
            .padding(.vertical, 8)
            
            Button(action: {
                connectWithOAuth()
            }) {
                HStack {
                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "person.badge.key.fill")
                        Text("Login with \(exchangeName)")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .cornerRadius(12)
            }
            .disabled(isConnecting)
        }
        .padding(20)
        .background(isDark ? Color.black.opacity(0.2) : DS.Adaptive.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isDark ? Color.clear : DS.Adaptive.stroke, lineWidth: isDark ? 0 : 1)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - API Key Card (Binance, KuCoin, etc.)
    private var apiKeyCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundColor(.orange)
                Text("API Key Setup")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            Text("Create a read-only API key on \(exchangeName) and enter it below. This allows secure portfolio tracking without trading permissions.")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            
            // Don't have an account? Sign up section
            noAccountSignUpSection
            
            // Instructions link
            Button(action: {
                openAPIDocsURL()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle")
                    Text("How to create an API key")
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            // API Key
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                TextField("Enter API Key", text: $apiKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .background(isDark ? Color.white.opacity(0.1) : Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isDark ? Color.clear : DS.Adaptive.stroke, lineWidth: isDark ? 0 : 1)
                    )
            }
            
            // API Secret
            VStack(alignment: .leading, spacing: 4) {
                Text("API Secret")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                SecureField("Enter API Secret", text: $apiSecret)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .background(isDark ? Color.white.opacity(0.1) : Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isDark ? Color.clear : DS.Adaptive.stroke, lineWidth: isDark ? 0 : 1)
                    )
            }
            
            // Passphrase (for KuCoin, OKX)
            if requiresPassphrase {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Passphrase")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    SecureField("Enter Passphrase", text: $passphrase)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding()
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .background(isDark ? Color.white.opacity(0.1) : Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isDark ? Color.clear : DS.Adaptive.stroke, lineWidth: isDark ? 0 : 1)
                        )
                }
            }
            
            Button(action: {
                connectWithAPIKey()
            }) {
                HStack {
                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Connect")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.orange.opacity(0.8), Color.orange]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(apiKey.isEmpty || apiSecret.isEmpty || isConnecting || (requiresPassphrase && passphrase.isEmpty))
            .opacity((apiKey.isEmpty || apiSecret.isEmpty || (requiresPassphrase && passphrase.isEmpty)) ? 0.6 : 1.0)
            
            // Security notice
            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .font(.caption)
                Text("Credentials stored securely in Keychain")
                    .font(.caption)
            }
            .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(20)
        .background(isDark ? Color.black.opacity(0.2) : DS.Adaptive.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isDark ? Color.clear : DS.Adaptive.stroke, lineWidth: isDark ? 0 : 1)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Wallet Address Card
    private var walletAddressCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "wallet.pass.fill")
                    .foregroundColor(.purple)
                Text("Add Wallet Address")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            Text("Paste your wallet address to track balances. No private keys or signing required - just public blockchain data.")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            
            // Supported chains
            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "checkmark.circle.fill", text: "Ethereum (ETH, ERC-20 tokens)", color: .blue)
                featureRow(icon: "checkmark.circle.fill", text: "Bitcoin (BTC)", color: .orange)
                featureRow(icon: "checkmark.circle.fill", text: "Solana (SOL, SPL tokens)", color: .purple)
                featureRow(icon: "checkmark.circle.fill", text: "Polygon, Arbitrum, Base", color: .cyan)
                featureRow(icon: "checkmark.circle.fill", text: "Avalanche, BNB Chain", color: .green)
            }
            .padding(.vertical, 8)
            
            // Wallet Address
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Wallet Address")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Spacer()
                    
                    if !detectedChain.isEmpty {
                        Text(detectedChain)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                TextField("0x... or bc1... or base58...", text: $walletAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .background(isDark ? Color.white.opacity(0.1) : Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isDark ? Color.clear : DS.Adaptive.stroke, lineWidth: isDark ? 0 : 1)
                    )
                    .onChange(of: walletAddress) { _, newValue in
                        detectChain(from: newValue)
                    }
            }
            
            // Paste from clipboard button
            Button(action: {
                if let clipboard = UIPasteboard.general.string {
                    walletAddress = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }) {
                HStack {
                    Image(systemName: "doc.on.clipboard")
                    Text("Paste from Clipboard")
                }
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Button(action: {
                connectWalletAddress()
            }) {
                HStack {
                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Wallet")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                        gradient: Gradient(colors: [Color.purple.opacity(0.8), Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                .cornerRadius(12)
            }
            .disabled(walletAddress.isEmpty || isConnecting)
            .opacity(walletAddress.isEmpty ? 0.6 : 1.0)
            
            // Privacy notice
            HStack(spacing: 4) {
                Image(systemName: "eye.slash")
                    .font(.caption)
                Text("Only public blockchain data is accessed")
                    .font(.caption)
            }
            .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(20)
        .background(isDark ? Color.black.opacity(0.2) : DS.Adaptive.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isDark ? Color.clear : DS.Adaptive.stroke, lineWidth: isDark ? 0 : 1)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - 3Commas Card (Legacy/Advanced)
    private var threeCommasCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "link.circle.fill")
                    .foregroundColor(.cyan)
                Text("3Commas Integration")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            Text("Connect via 3Commas for trading bot functionality. Requires a 3Commas account with API access.")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            
            // API Key
            VStack(alignment: .leading, spacing: 4) {
                Text("3Commas API Key")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                TextField("Enter 3Commas API Key", text: $apiKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .background(isDark ? Color.white.opacity(0.1) : Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isDark ? Color.clear : DS.Adaptive.stroke, lineWidth: isDark ? 0 : 1)
                    )
            }
            
            // API Secret
            VStack(alignment: .leading, spacing: 4) {
                Text("3Commas API Secret")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                SecureField("Enter 3Commas API Secret", text: $apiSecret)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .background(isDark ? Color.white.opacity(0.1) : Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isDark ? Color.clear : DS.Adaptive.stroke, lineWidth: isDark ? 0 : 1)
                    )
            }
            
            Button(action: {
                connectWithThreeCommas()
            }) {
                HStack {
                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Connect via 3Commas")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.cyan)
                .cornerRadius(12)
            }
            .disabled(apiKey.isEmpty || apiSecret.isEmpty || isConnecting)
            .opacity((apiKey.isEmpty || apiSecret.isEmpty) ? 0.6 : 1.0)
            
            Button(action: {
                if let url = URL(string: "https://3commas.io/") {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Learn more about 3Commas")
                    .font(.footnote)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .underline()
            }
        }
        .padding(20)
        .background(isDark ? Color.black.opacity(0.2) : DS.Adaptive.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isDark ? Color.clear : DS.Adaptive.stroke, lineWidth: isDark ? 0 : 1)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Helper Views
    
    private func featureRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
        }
    }
    
    // MARK: - No Account Sign Up Section
    
    /// Shows a "Don't have an account?" section with sign-up link
    private var noAccountSignUpSection: some View {
        let affiliateInfo = ExchangeAffiliateManager.shared.affiliateInfo(for: exchangeName)
        
        return Group {
            if affiliateInfo.bestURL != nil {
                VStack(spacing: 8) {
                    Divider()
                        .background(isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.08))
                    
                    HStack(spacing: 4) {
                        Text("Don't have a \(exchangeName) account?")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Button(action: {
                            ExchangeAffiliateManager.shared.openSignUpPage(for: exchangeName)
                        }) {
                            HStack(spacing: 4) {
                                Text("Sign up here")
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.caption2)
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                        }
                    }
                    
                    Divider()
                        .background(isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.08))
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - Connection Methods
    
    private func connectWithOAuth() {
        isConnecting = true
        
        Task {
            do {
                // Use OAuthConnectionProviderImpl for the actual OAuth flow
                let credentials = try await OAuthConnectionProviderImpl.shared.startOAuthFlow(exchangeId: exchangeName.lowercased())
                
                // Connect with the obtained credentials
                let result = try await OAuthConnectionProviderImpl.shared.connect(
                    exchangeId: exchangeName.lowercased(),
                    credentials: credentials
                )
                
                if result.success {
                    // Add to connected accounts
                    let account = ConnectedAccount(
                        id: result.accountId ?? UUID().uuidString,
                        name: result.accountName ?? exchangeName,
                        exchangeType: "exchange",
                        provider: "oauth",
                        isDefault: accountsManager.accounts.isEmpty,
                        connectedAt: Date()
                    )
                    await MainActor.run {
                        accountsManager.addAccount(account)
                        isConnecting = false
                        showSuccessAlert = true
                    }
                } else {
                    await MainActor.run {
                        isConnecting = false
                        connectionError = result.error?.localizedDescription ?? "Connection failed"
                    }
                }
            } catch let setupError as OAuthSetupError {
                // OAuth is not configured - show setup instructions
                await MainActor.run {
                    isConnecting = false
                    connectionError = """
                    \(setupError.localizedDescription)
                    
                    \(OAuthConnectionProviderImpl.shared.getSetupInstructions(for: exchangeName.lowercased()))
                    """
                }
            } catch let connError as ConnectionError {
                await MainActor.run {
                    isConnecting = false
                    if case .oauthCancelled = connError {
                        // User cancelled - don't show error
                    } else {
                        connectionError = connError.localizedDescription
                    }
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    connectionError = error.localizedDescription
                }
            }
        }
    }
    
    private func connectWithAPIKey() {
        guard !apiKey.isEmpty, !apiSecret.isEmpty else { return }
        
        isConnecting = true
        
        Task {
            do {
                let credentials = ConnectionCredentials.apiKey(
                    key: apiKey,
                    secret: apiSecret,
                    passphrase: requiresPassphrase ? passphrase : nil
                )
                
                let result = try await DirectAPIConnectionProviderImpl.shared.connect(
                    exchangeId: exchangeName.lowercased().replacingOccurrences(of: " ", with: "_"),
                    credentials: credentials
                )
                
                if result.success {
                    let account = ConnectedAccount(
                        id: result.accountId ?? UUID().uuidString,
                        name: result.accountName ?? exchangeName,
                        exchangeType: "exchange",
                        provider: "direct",
                        isDefault: accountsManager.accounts.isEmpty,
                        connectedAt: Date()
                    )
                    await MainActor.run {
                        accountsManager.addAccount(account)
                        
                        // NOTE: Portfolio connections are READ-ONLY for balance viewing
                        // Live trading is currently disabled (AppConfig.liveTradingEnabled = false)
                        // Do NOT save to TradingCredentialsManager to prevent unintended trading capability
                        // Trading credentials should only be saved from a dedicated trading setup flow
                        // when live trading is enabled and user explicitly consents
                        
                        isConnecting = false
                        showSuccessAlert = true
                    }
                } else {
                    await MainActor.run {
                        isConnecting = false
                        connectionError = result.error?.localizedDescription ?? "Invalid API credentials"
                    }
                }
            } catch let connError as ConnectionError {
                await MainActor.run {
                    isConnecting = false
                    connectionError = connError.localizedDescription
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    connectionError = error.localizedDescription
                }
            }
        }
    }
    
    /// Maps exchange name to TradingExchange enum for trading credential storage
    private func tradingExchangeForName(_ name: String) -> TradingExchange? {
        let lowercased = name.lowercased()
        if lowercased.contains("binance") && lowercased.contains("us") {
            return .binanceUS
        } else if lowercased.contains("binance") {
            return .binance
        } else if lowercased.contains("coinbase") {
            return .coinbase
        } else if lowercased.contains("kraken") {
            return .kraken
        } else if lowercased.contains("kucoin") {
            return .kucoin
        }
        return nil
    }
    
    private func connectWalletAddress() {
        guard !walletAddress.isEmpty else { return }
        
        isConnecting = true
        
        Task {
            do {
                // Auto-detect chain or use detected
                let chain = detectedChain.isEmpty ? "ETH" : detectedChain
                let credentials = ConnectionCredentials.walletAddress(address: walletAddress, chain: chain)
                
                let result = try await BlockchainConnectionProviderImpl.shared.connect(
                    exchangeId: "\(chain.lowercased())_wallet",
                    credentials: credentials
                )
                
                if result.success {
                    let account = ConnectedAccount(
                        id: result.accountId ?? UUID().uuidString,
                        name: result.accountName ?? "\(chain) Wallet",
                        exchangeType: "wallet",
                        provider: "blockchain",
                        isDefault: accountsManager.accounts.isEmpty,
                        connectedAt: Date(),
                        walletAddress: walletAddress
                    )
                    await MainActor.run {
                        accountsManager.addAccount(account)
                        isConnecting = false
                        showSuccessAlert = true
                    }
                } else {
                    await MainActor.run {
                        isConnecting = false
                        connectionError = result.error?.localizedDescription ?? "Invalid wallet address"
                    }
                }
            } catch let connError as ConnectionError {
                await MainActor.run {
                    isConnecting = false
                    connectionError = connError.localizedDescription
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    connectionError = error.localizedDescription
                }
            }
        }
    }
    
    private func connectWithThreeCommas() {
        guard !apiKey.isEmpty, !apiSecret.isEmpty else { return }
        
        isConnecting = true
        
        Task {
            do {
                let success = try await ThreeCommasAPI.shared.connect(apiKey: apiKey, apiSecret: apiSecret)
                
                await MainActor.run {
                    if success {
                        try? KeychainHelper.shared.save(apiKey, service: "CryptoSage.3Commas", account: "api_key")
                        try? KeychainHelper.shared.save(apiSecret, service: "CryptoSage.3Commas", account: "api_secret")
                        
                        let account = ConnectedAccount(
                            name: "3Commas",
                            exchangeType: "exchange",
                            provider: "3commas",
                            isDefault: accountsManager.accounts.isEmpty,
                            connectedAt: Date()
                        )
                        accountsManager.addAccount(account)
                        
                        isConnecting = false
                        showSuccessAlert = true
                    } else {
                        isConnecting = false
                        connectionError = "Invalid 3Commas credentials"
                    }
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    connectionError = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func detectChain(from address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.hasPrefix("0x") && trimmed.count == 42 {
            detectedChain = "ETH"
        } else if trimmed.hasPrefix("bc1") || trimmed.hasPrefix("1") || trimmed.hasPrefix("3") {
            if trimmed.count >= 26 && trimmed.count <= 35 {
                detectedChain = "BTC"
            } else if trimmed.hasPrefix("bc1") && trimmed.count >= 42 {
                detectedChain = "BTC"
            } else {
                detectedChain = ""
            }
        } else if trimmed.count >= 32 && trimmed.count <= 44 {
            // Potential Solana address
            detectedChain = "SOL"
        } else {
            detectedChain = ""
        }
    }
    
    private func openAPIDocsURL() {
        let lowercased = exchangeName.lowercased()
        var urlString = "https://support.\(lowercased.replacingOccurrences(of: " ", with: "")).com"
        
        // Specific help URLs
        switch lowercased {
        case "binance":
            urlString = "https://www.binance.com/en/support/faq/how-to-create-api-keys-on-binance-360002502072"
        case "binance us":
            urlString = "https://support.binance.us/hc/en-us/articles/360046787554-How-to-Create-an-API-Key"
        case "kucoin":
            urlString = "https://www.kucoin.com/support/360015102174"
        case "bybit":
            urlString = "https://www.bybit.com/en-US/help-center/bybitHC_Article?id=360039749613"
        case "okx":
            urlString = "https://www.okx.com/help/how-do-i-create-api-keys-on-okx"
        case "huobi", "htx":
            urlString = "https://www.htx.com/support/en-us/detail/360000203002"
        case "gate.io":
            urlString = "https://www.gate.io/help/guide/faq/16850/how-to-create-api-keys"
        case "mexc":
            urlString = "https://www.mexc.com/support/articles/how-to-create-api-keys"
        case "bitstamp":
            urlString = "https://www.bitstamp.net/faq/api-setup/"
        case "crypto.com":
            urlString = "https://help.crypto.com/en/articles/3511424-api"
        case "bitget":
            urlString = "https://www.bitget.com/support/articles/How-to-create-API-keys"
        case "bitfinex":
            urlString = "https://support.bitfinex.com/hc/en-us/articles/115002349625-API-Key-Setup-Login"
        default:
            break
        }
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Preview
struct ExchangeConnectionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ExchangeConnectionView(exchangeName: "Coinbase", connectionMethod: .oauth)
                .previewDisplayName("OAuth")
            ExchangeConnectionView(exchangeName: "Binance", connectionMethod: .apiKey)
                .previewDisplayName("API Key")
            ExchangeConnectionView(exchangeName: "Ethereum Wallet", connectionMethod: .walletAddress)
                .previewDisplayName("Wallet")
        }
    }
}
