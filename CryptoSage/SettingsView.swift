import SwiftUI
import Foundation
import StoreKit
// Trading credentials UI

struct SettingsView: View {
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    // MARK: - App Storage Defaults
    @AppStorage("Settings.DarkMode") private var isDarkMode = false
    @AppStorage("App.Appearance") private var appAppearanceRaw: String = "system"
    @AppStorage("hideBalances") private var hideBalances = false
    @AppStorage("language") private var language = "English"
    @AppStorage("selectedCurrency") private var selectedCurrency = "USD"
    
    // MARK: - Home Screen Section Visibility
    @AppStorage("Home.showWatchlist") private var showWatchlist = true
    @AppStorage("Home.showMarketStats") private var showMarketStats = true
    @AppStorage("Home.showSentiment") private var showSentiment = true
    @AppStorage("Home.showHeatmap") private var showHeatmap = true
    @AppStorage("Home.showTrending") private var showTrending = true
    @AppStorage("Home.showArbitrage") private var showArbitrage = true
    @AppStorage("Home.showEvents") private var showEvents = true
    @AppStorage("Home.showNews") private var showNews = true
    
    // Analytics
    @AppStorage("Analytics.Enabled") private var analyticsEnabled = true
    
    // State
    @State private var showAddHoldingSheet = false
    @State private var mockDailyChange: Double = 2.0
    @State private var showSignOutAlert = false
    @State private var showClearCacheAlert = false
    @State private var showShareSheet = false
    @State private var cacheSize: String = "Calculating..."
    
    // Assume PortfolioViewModel is provided via EnvironmentObject
    @EnvironmentObject var portfolioViewModel: PortfolioViewModel
    
    // Haptic generators
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Custom Header
            settingsHeader
            
            // MARK: - Content
            ScrollView {
                VStack(spacing: 14) {
                    // MARK: - Profile Card (Tappable)
                    NavigationLink(destination: ProfileView()) {
                        ProfileHeaderView()
                    }
                    .buttonStyle(ProfileCardButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    
                    // Settings Sections
                    VStack(spacing: 10) {
                        // MARK: - Account
                        SettingsSection(title: "ACCOUNT") {
                            NavigationLink(destination: ProfileView()) {
                                SettingsRow(icon: "person.crop.circle", title: "Profile & Personal Info")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                            SettingsDivider()
                            NavigationLink(destination: LinkedAccountsView()) {
                                SettingsRow(icon: "wallet.pass", title: "Linked Accounts")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - Paper Trading (Practice with virtual money)
                        PaperTradingSettingsSection(
                            selectionFeedback: selectionFeedback,
                            impactLight: impactLight
                        )
                        
                        // MARK: - Portfolio Management (moved up for easy Demo Mode access)
                        SettingsSection(title: "PORTFOLIO") {
                            Button(action: {
                                impactLight.impactOccurred()
                                showAddHoldingSheet = true
                            }) {
                                SettingsRow(icon: "plus.circle", title: "Add Holdings", showChevron: false)
                            }
                            SettingsDivider()
                            
                            // Demo Mode is locked when Paper Trading is active
                            let isPaperTradingActive = PaperTradingManager.shared.isPaperTradingEnabled
                            
                            SettingsToggleRow(
                                icon: "wand.and.stars",
                                title: "Demo Mode",
                                isOn: Binding(
                                    get: { DemoModeManager.shared.isDemoMode },
                                    set: { newVal in
                                        // Prevent enabling if Paper Trading is active
                                        guard !isPaperTradingActive else { return }
                                        selectionFeedback.selectionChanged()
                                        if newVal {
                                            DemoModeManager.shared.enableDemoMode()
                                            portfolioViewModel.enableDemoMode()
                                        } else {
                                            DemoModeManager.shared.disableDemoMode()
                                            portfolioViewModel.disableDemoMode()
                                        }
                                    }
                                )
                            )
                            .disabled(isPaperTradingActive)
                            .opacity(isPaperTradingActive ? 0.5 : 1.0)
                            
                            if isPaperTradingActive {
                                HStack(spacing: 4) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10))
                                    Text("Locked while Paper Trading is active")
                                        .font(.caption)
                                }
                                .foregroundColor(.orange)
                                .padding(.top, 4)
                            } else {
                                Text("Shows sample portfolio and trading data when enabled")
                                    .font(.caption)
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                    .padding(.top, 4)
                            }
                        }
                        
                        // MARK: - Security
                        SettingsSection(title: "SECURITY") {
                            NavigationLink(destination: SecuritySettingsView()) {
                                SettingsRow(icon: "lock.shield", title: "Security & Login")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - API Credentials
                        SettingsSection(title: "API CREDENTIALS") {
                            NavigationLink(destination: TradingAPIKeysView()) {
                                SettingsRow(icon: "key.fill", title: "Trading API Keys")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                            SettingsDivider()
                            NavigationLink(destination: TradingCredentialsView()) {
                                SettingsRow(icon: "link", title: "3Commas Integration")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                            SettingsDivider()
                            NavigationLink(destination: AISettingsView()) {
                                SettingsRow(icon: "cpu", title: "AI Settings (OpenAI)")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - Appearance
                        SettingsSection(title: "APPEARANCE") {
                            SettingsToggleRow(
                                icon: isDarkMode ? "moon.fill" : "sun.max.fill",
                                title: isDarkMode ? "Dark Mode" : "Light Mode",
                                isOn: $isDarkMode
                            )
                            .onChange(of: isDarkMode) { newValue in
                                selectionFeedback.selectionChanged()
                                // Update both the raw preference and the app-wide color scheme synchronously
                                appAppearanceRaw = newValue ? "dark" : "light"
                                AppTheme.currentColorScheme = newValue ? .dark : .light
                            }
                            SettingsDivider()
                            SettingsToggleRow(icon: "eye.slash", title: "Privacy Mode", isOn: $hideBalances)
                                .onChange(of: hideBalances) { _ in selectionFeedback.selectionChanged() }
                        }
                        
                        // MARK: - Home Screen Customization
                        SettingsSection(title: "HOME SCREEN") {
                            NavigationLink(destination: HomeCustomizationView(
                                showWatchlist: $showWatchlist,
                                showMarketStats: $showMarketStats,
                                showSentiment: $showSentiment,
                                showHeatmap: $showHeatmap,
                                showTrending: $showTrending,
                                showArbitrage: $showArbitrage,
                                showEvents: $showEvents,
                                showNews: $showNews
                            )) {
                                SettingsRow(icon: "square.grid.2x2", title: "Customize Sections")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - Privacy & Analytics
                        SettingsSection(title: "PRIVACY & ANALYTICS") {
                            SettingsToggleRow(
                                icon: "chart.bar.xaxis",
                                title: "Share Analytics",
                                isOn: $analyticsEnabled
                            )
                            .onChange(of: analyticsEnabled) { newValue in
                                selectionFeedback.selectionChanged()
                                AnalyticsService.shared.isEnabled = newValue
                                if newValue {
                                    AnalyticsService.shared.track(.analyticsOptIn)
                                }
                            }
                            Text("Help improve CryptoSage by sharing anonymous usage data. No personal or financial data is ever collected.")
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textTertiary)
                                .padding(.top, 4)
                            
                            SettingsDivider()
                            
                            NavigationLink(destination: AnalyticsInfoView()) {
                                SettingsRow(icon: "info.circle", title: "What We Collect")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - Preferences
                        SettingsSection(title: "PREFERENCES") {
                            NavigationLink(destination: LanguageSettingsView(selectedLanguage: $language)) {
                                SettingsRowWithValue(icon: "globe", title: "Language", value: language)
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                            SettingsDivider()
                            NavigationLink(destination: CurrencySettingsView(selectedCurrency: $selectedCurrency)) {
                                SettingsRowWithValue(icon: "dollarsign.circle", title: "Currency", value: selectedCurrency)
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - Connected Accounts
                        SettingsSection(title: "CONNECTED ACCOUNTS") {
                            NavigationLink(destination: PortfolioPaymentMethodsView()) {
                                SettingsRow(icon: "link", title: "Manage Exchanges")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - Subscription
                        SettingsSection(title: "SUBSCRIPTION") {
                            NavigationLink(destination: SubscriptionPricingView()) {
                                SettingsRow(icon: "crown.fill", title: "Upgrade to Pro")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - Support & Feedback
                        SettingsSection(title: "SUPPORT") {
                            Button(action: {
                                impactLight.impactOccurred()
                                requestAppReview()
                            }) {
                                SettingsRow(icon: "star.fill", title: "Rate App", showChevron: false, iconColor: .yellow)
                            }
                            SettingsDivider()
                            Button(action: {
                                impactLight.impactOccurred()
                                showShareSheet = true
                            }) {
                                SettingsRow(icon: "square.and.arrow.up", title: "Share App", showChevron: false, iconColor: .blue)
                            }
                            SettingsDivider()
                            NavigationLink(destination: HelpView()) {
                                SettingsRow(icon: "questionmark.circle", title: "Help & Support")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - Data Management
                        SettingsSection(title: "DATA") {
                            Button(action: {
                                impactMedium.impactOccurred()
                                showClearCacheAlert = true
                            }) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.orange.opacity(0.15))
                                            .frame(width: 30, height: 30)
                                        Image(systemName: "trash")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.orange)
                                    }
                                    Text("Clear Cache")
                                        .font(.body)
                                        .foregroundColor(DS.Adaptive.textPrimary)
                                    Spacer()
                                    Text(cacheSize)
                                        .font(.subheadline)
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            SettingsDivider()
                            NavigationLink(destination: AboutView()) {
                                SettingsRow(icon: "info.circle", title: "About")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                            SettingsDivider()
                            NavigationLink(destination: PrivacyPolicyView()) {
                                SettingsRow(icon: "hand.raised.fill", title: "Privacy Policy")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - Sign Out Button
                        Button(action: {
                            impactMedium.impactOccurred()
                            showSignOutAlert = true
                        }) {
                            HStack {
                                Spacer()
                                HStack(spacing: 8) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Sign Out")
                                        .font(.body.weight(.semibold))
                                }
                                .foregroundColor(.red)
                                Spacer()
                            }
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.red.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.red.opacity(0.25), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                    }
                    
                    // MARK: - App Info Footer
                    appInfoFooter
                        .padding(.top, 20)
                        .padding(.bottom, 30)
                }
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear {
            impactLight.prepare()
            impactMedium.prepare()
            selectionFeedback.prepare()
            
            // Sync AppTheme with the stored dark mode preference
            AppTheme.currentColorScheme = isDarkMode ? .dark : .light
            
            // Defer state modifications to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                let key = "portfolio_mock_daily_change"
                if let v = UserDefaults.standard.object(forKey: key) as? Double {
                    mockDailyChange = v
                } else {
                    mockDailyChange = 2.0
                }
                
                // Migrate legacy key if present and new key is unset
                let defaults = UserDefaults.standard
                if defaults.object(forKey: "isDarkMode") != nil && defaults.object(forKey: "Settings.DarkMode") == nil {
                    let old = defaults.bool(forKey: "isDarkMode")
                    defaults.set(old, forKey: "Settings.DarkMode")
                }
                
                // Calculate cache size
                calculateCacheSize()
            }
        }
        .sheet(isPresented: $showAddHoldingSheet) {
            AddTransactionView(viewModel: portfolioViewModel)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [URL(string: "https://apps.apple.com/app/cryptosage-ai")!])
        }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) { handleSignOut() }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Clear Cache", isPresented: $showClearCacheAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) { clearCache() }
        } message: {
            Text("This will clear cached images and data. Your portfolio and settings will not be affected.")
        }
    }
    
    // MARK: - Custom Header
    private var settingsHeader: some View {
        HStack {
            Button(action: {
                impactLight.impactOccurred()
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(chipGoldGradient)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DS.Adaptive.chipBackground))
                    .overlay(Circle().stroke(DS.Adaptive.stroke, lineWidth: 0.8))
            }
            
            Spacer()
            
            Text("Settings")
                .font(.headline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            // Invisible balance spacer
            Color.clear
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.Adaptive.background)
    }
    
    // MARK: - App Info Footer
    private var appInfoFooter: some View {
        VStack(spacing: 8) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldLight.opacity(0.3), BrandColors.goldDark.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            Text("CryptoSage AI")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Version \(appVersion) (\(buildNumber))")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
            
            Text("Made with ♥ for crypto traders")
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.top, 2)
        }
    }
    
    // MARK: - Helpers
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    private func handleSignOut() {
        UserDefaults.standard.removeObject(forKey: "userToken")
        UserDefaults.standard.removeObject(forKey: "userEmail")
        UserDefaults.standard.removeObject(forKey: "isLoggedIn")
        NotificationCenter.default.post(name: NSNotification.Name("UserDidSignOut"), object: nil)
        dismiss()
    }
    
    private func requestAppReview() {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
    
    private func calculateCacheSize() {
        DispatchQueue.global(qos: .utility).async {
            var totalSize: Int64 = 0
            
            // URLCache
            totalSize += Int64(URLCache.shared.currentDiskUsage)
            
            // Caches directory
            if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                totalSize += directorySize(url: cachesURL)
            }
            
            DispatchQueue.main.async {
                if totalSize < 1024 {
                    cacheSize = "\(totalSize) B"
                } else if totalSize < 1024 * 1024 {
                    cacheSize = String(format: "%.1f KB", Double(totalSize) / 1024.0)
                } else {
                    cacheSize = String(format: "%.1f MB", Double(totalSize) / (1024.0 * 1024.0))
                }
            }
        }
    }
    
    private func directorySize(url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
    
    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        
        if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: cachesURL)
            try? FileManager.default.createDirectory(at: cachesURL, withIntermediateDirectories: true)
        }
        
        // Recalculate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            calculateCacheSize()
        }
    }
}

// MARK: - Profile Card Button Style
private struct ProfileCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Share Sheet
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Settings Section Container
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Settings Divider
private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Adaptive.stroke)
            .frame(height: 0.5)
            .padding(.leading, 44)
    }
}

// MARK: - Profile Header
struct ProfileHeaderView: View {
    var body: some View {
        HStack(spacing: 14) {
            // Avatar with gold ring
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase, BrandColors.goldDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                
                Circle()
                    .fill(DS.Adaptive.cardBackgroundElevated)
                    .frame(width: 50, height: 50)
                
                Image(systemName: "person.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("John Doe")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("john.doe@example.com")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                    Text("Free Plan")
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(BrandColors.goldBase)
                .padding(.top, 1)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackgroundElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    BrandColors.goldBase.opacity(0.5),
                                    BrandColors.goldBase.opacity(0.15),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Settings Row
struct SettingsRow: View {
    let icon: String
    let title: String
    var showChevron: Bool = true
    var iconColor: Color = BrandColors.goldBase
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor)
            }
            
            Text(title)
                .font(.body)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

// MARK: - Settings Row with Value
private struct SettingsRowWithValue: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(BrandColors.goldBase.opacity(0.12))
                    .frame(width: 30, height: 30)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            Text(title)
                .font(.body)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

// MARK: - Settings Toggle Row
private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    var iconColor: Color? = nil  // Optional custom icon color
    
    private var effectiveIconColor: Color {
        iconColor ?? BrandColors.goldBase
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(effectiveIconColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(effectiveIconColor)
            }
            
            Text(title)
                .font(.body)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(effectiveIconColor)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Security & Login View
struct SecuritySettingsView: View {
    @StateObject private var biometricAuth = BiometricAuthManager.shared
    @StateObject private var securityManager = SecurityManager.shared
    @StateObject private var pinManager = PINAuthManager.shared
    @AppStorage("isPasscodeEnabled") private var isPasscodeEnabled = false
    @AppStorage("enable2FA") private var enable2FA = false
    @State private var isTogglingBiometric = false
    @State private var showBiometricError = false
    @State private var biometricErrorMessage = ""
    @State private var showPINSetup = false
    @State private var showPINChange = false
    @State private var showAPIKeySettings = false
    @State private var showRemovePINAlert = false
    
    private let autoLockOptions: [(String, TimeInterval)] = [
        ("Immediately", 0),
        ("After 1 minute", 60),
        ("After 5 minutes", 300),
        ("After 15 minutes", 900),
        ("After 30 minutes", 1800)
    ]
    
    var body: some View {
        Form {
            Section(header: Text("App Protection")) {
                // Biometric toggle with proper authentication
                HStack {
                    Image(systemName: biometricAuth.biometricType.iconName)
                        .foregroundColor(BrandColors.goldBase)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lock with \(biometricAuth.biometricType.displayName)")
                        if !biometricAuth.canUseBiometric && biometricAuth.biometricType == .none {
                            Text("Not available on this device")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if isTogglingBiometric {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { biometricAuth.isBiometricEnabled },
                            set: { _ in toggleBiometric() }
                        ))
                        .labelsHidden()
                        .disabled(!biometricAuth.canUseDeviceAuth)
                    }
                }
                
                // PIN code backup (like Coinbase/Binance)
                HStack {
                    Image(systemName: "rectangle.grid.3x3")
                        .foregroundColor(BrandColors.goldBase)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PIN Code")
                        Text(pinManager.isPINSet ? "Enabled as backup" : "Set up a 6-digit PIN")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if pinManager.isPINSet {
                        Menu {
                            Button(action: { showPINChange = true }) {
                                Label("Change PIN", systemImage: "pencil")
                            }
                            Button(role: .destructive, action: { showRemovePINAlert = true }) {
                                Label("Remove PIN", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(BrandColors.goldBase)
                        }
                    } else {
                        Button("Set Up") {
                            showPINSetup = true
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(BrandColors.goldBase)
                    }
                }
                
                // Auto-lock timeout picker (only show if any lock is enabled)
                if biometricAuth.isBiometricEnabled || pinManager.isPINSet {
                    Picker("Auto-Lock", selection: $securityManager.autoLockTimeout) {
                        ForEach(autoLockOptions, id: \.1) { option in
                            Text(option.0).tag(option.1)
                        }
                    }
                }
            }
            
            // API Keys Section
            Section(header: Text("API Keys")) {
                Button(action: { showAPIKeySettings = true }) {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(BrandColors.goldBase)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manage API Keys")
                            Text("OpenAI, Binance, 3Commas, and more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.primary)
            }
            
            Section(header: Text("Two-Factor Authentication")) {
                Toggle("Enable 2FA for Trading", isOn: $enable2FA)
                NavigationLink("Trusted Devices", destination: TrustedDevicesView())
            }
            
            Section(header: Text("Password Management")) {
                NavigationLink("Change Password", destination: ChangePasswordView())
            }
            
            Section(header: Text("Security Warnings")) {
                Toggle("Show Security Alerts", isOn: $securityManager.showSecurityWarnings)
                
                if securityManager.isDeviceCompromised {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Device security may be compromised")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Section(header: Text("Security Status")) {
                VStack(alignment: .leading, spacing: 8) {
                    SecurityStatusRow(
                        icon: "lock.shield.fill",
                        title: "API Keys",
                        status: "Encrypted in Keychain",
                        isSecure: true
                    )
                    SecurityStatusRow(
                        icon: "network.badge.shield.half.filled",
                        title: "Network",
                        status: "TLS 1.2+ Enforced",
                        isSecure: true
                    )
                    SecurityStatusRow(
                        icon: "iphone.badge.checkmark",
                        title: "Device",
                        status: securityManager.isDeviceCompromised ? "Potentially Compromised" : "Secure",
                        isSecure: !securityManager.isDeviceCompromised
                    )
                    SecurityStatusRow(
                        icon: biometricAuth.biometricType.iconName,
                        title: "Biometric Lock",
                        status: biometricAuth.isBiometricEnabled ? "Enabled" : "Disabled",
                        isSecure: biometricAuth.isBiometricEnabled
                    )
                    SecurityStatusRow(
                        icon: "externaldrive.fill.badge.checkmark",
                        title: "Portfolio Data",
                        status: "AES-256 Encrypted",
                        isSecure: true
                    )
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("Data Management")) {
                Button(action: { showWipeDataAlert = true }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                        Text("Wipe All User Data")
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
                
                Text("This will permanently delete all portfolio data, transactions, connected accounts, and API keys from this device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .tint(BrandColors.goldBase)
        .navigationTitle("Security & Login")
        .alert("Authentication Error", isPresented: $showBiometricError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(biometricErrorMessage)
        }
        .alert("Wipe All Data?", isPresented: $showWipeDataAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Wipe Everything", role: .destructive) {
                SecureUserDataManager.shared.wipeAllDataIncludingSecrets()
                // Provide feedback
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)
            }
        } message: {
            Text("This will permanently delete all your data including API keys. This action cannot be undone.")
        }
        .alert("Remove PIN?", isPresented: $showRemovePINAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                pinManager.removePIN()
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)
            }
        } message: {
            Text("This will remove your PIN code. You'll need to set it up again if you want to use PIN authentication.")
        }
        .sheet(isPresented: $showPINSetup) {
            NavigationView {
                PINEntryView(mode: .setup) { success in
                    showPINSetup = false
                    if success {
                        biometricAuth.enablePINFallback()
                    }
                }
                .navigationTitle("Set Up PIN")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showPINChange) {
            NavigationView {
                PINEntryView(mode: .change) { success in
                    showPINChange = false
                }
                .navigationTitle("Change PIN")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showAPIKeySettings) {
            APIKeySettingsView()
        }
    }
    
    @State private var showWipeDataAlert = false
    
    private func toggleBiometric() {
        isTogglingBiometric = true
        Task {
            let success = await biometricAuth.toggleBiometric()
            await MainActor.run {
                isTogglingBiometric = false
                if !success, let error = biometricAuth.authError {
                    biometricErrorMessage = error
                    showBiometricError = true
                }
            }
        }
    }
}

// MARK: - Security Status Row
private struct SecurityStatusRow: View {
    let icon: String
    let title: String
    let status: String
    let isSecure: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isSecure ? .green : .orange)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
                Text(status)
                    .font(.caption2)
                    .foregroundColor(isSecure ? .secondary : .orange)
            }
            
            Spacer()
            
            Image(systemName: isSecure ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundColor(isSecure ? .green : .orange)
        }
    }
}

struct TrustedDevicesView: View {
    var body: some View {
        Text("Manage your trusted devices here.")
            .navigationTitle("Trusted Devices")
    }
}

struct ChangePasswordView: View {
    var body: some View {
        Text("Change your password here.")
            .navigationTitle("Change Password")
    }
}

// MARK: - Profile View
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    
    // User profile data (stored in UserDefaults for persistence)
    @AppStorage("profile.displayName") private var displayName: String = "John Doe"
    @AppStorage("profile.email") private var email: String = "john.doe@example.com"
    @AppStorage("profile.phone") private var phone: String = ""
    @AppStorage("profile.bio") private var bio: String = ""
    
    @State private var isEditingName = false
    @State private var isEditingEmail = false
    @State private var isEditingPhone = false
    @State private var isEditingBio = false
    @State private var tempValue: String = ""
    @State private var showImagePicker = false
    @State private var profileImage: UIImage? = nil
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            profileHeader
            
            ScrollView {
                VStack(spacing: 20) {
                    // Profile Avatar Section
                    profileAvatarSection
                        .padding(.top, 20)
                    
                    // Personal Info Section
                    ProfileSection(title: "PERSONAL INFORMATION") {
                        ProfileEditableRow(
                            icon: "person.fill",
                            title: "Display Name",
                            value: displayName,
                            isEditing: $isEditingName,
                            tempValue: $tempValue,
                            onSave: { displayName = tempValue }
                        )
                        ProfileDivider()
                        ProfileEditableRow(
                            icon: "envelope.fill",
                            title: "Email",
                            value: email,
                            isEditing: $isEditingEmail,
                            tempValue: $tempValue,
                            onSave: { email = tempValue },
                            keyboardType: .emailAddress
                        )
                        ProfileDivider()
                        ProfileEditableRow(
                            icon: "phone.fill",
                            title: "Phone",
                            value: phone.isEmpty ? "Not set" : phone,
                            isEditing: $isEditingPhone,
                            tempValue: $tempValue,
                            onSave: { phone = tempValue },
                            keyboardType: .phonePad
                        )
                    }
                    
                    // Bio Section
                    ProfileSection(title: "ABOUT") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(BrandColors.goldBase.opacity(0.12))
                                        .frame(width: 30, height: 30)
                                    Image(systemName: "text.quote")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(BrandColors.goldBase)
                                }
                                Text("Bio")
                                    .font(.body)
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                Spacer()
                                Button(action: {
                                    impactLight.impactOccurred()
                                    tempValue = bio
                                    isEditingBio = true
                                }) {
                                    Text(bio.isEmpty ? "Add" : "Edit")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(BrandColors.goldBase)
                                }
                            }
                            if !bio.isEmpty {
                                Text(bio)
                                    .font(.subheadline)
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                    .padding(.leading, 42)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    
                    // Account Info Section
                    ProfileSection(title: "ACCOUNT") {
                        ProfileInfoRow(icon: "calendar", title: "Member Since", value: "January 2025")
                        ProfileDivider()
                        ProfileInfoRow(icon: "star.fill", title: "Plan", value: "Free Plan", valueColor: BrandColors.goldBase)
                        ProfileDivider()
                        ProfileInfoRow(icon: "checkmark.shield.fill", title: "Verified", value: "Email verified", valueColor: .green)
                    }
                    
                    // Danger Zone
                    ProfileSection(title: "ACCOUNT ACTIONS") {
                        Button(action: {
                            impactLight.impactOccurred()
                            // Reset profile to defaults
                            displayName = "John Doe"
                            email = "john.doe@example.com"
                            phone = ""
                            bio = ""
                        }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.orange.opacity(0.12))
                                        .frame(width: 30, height: 30)
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.orange)
                                }
                                Text("Reset Profile")
                                    .font(.body)
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $isEditingBio) {
            ProfileBioEditor(bio: $bio, tempValue: $tempValue, isPresented: $isEditingBio)
        }
    }
    
    // MARK: - Profile Header
    private var profileHeader: some View {
        HStack {
            Button(action: {
                impactLight.impactOccurred()
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(chipGoldGradient)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            }
            
            Spacer()
            
            Text("Profile")
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
    
    // MARK: - Profile Avatar Section
    private var profileAvatarSection: some View {
        VStack(spacing: 12) {
            ZStack {
                // Avatar circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldLight.opacity(0.3), BrandColors.goldDark.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [BrandColors.goldBase.opacity(0.6), BrandColors.goldBase.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                // Initials or image
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                } else {
                    Text(initials)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandColors.goldBase)
                }
                
                // Edit badge
                Button(action: {
                    impactLight.impactOccurred()
                    showImagePicker = true
                }) {
                    ZStack {
                        Circle()
                            .fill(BrandColors.goldBase)
                            .frame(width: 32, height: 32)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .offset(x: 35, y: 35)
            }
            
            VStack(spacing: 4) {
                Text(displayName)
                    .font(.title2.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(email)
                    .font(.subheadline)
                    .foregroundColor(BrandColors.goldBase)
            }
        }
        .padding(.vertical, 20)
    }
    
    private var initials: String {
        let components = displayName.split(separator: " ")
        let firstInitial = components.first?.first.map(String.init) ?? ""
        let lastInitial = components.count > 1 ? components.last?.first.map(String.init) ?? "" : ""
        return (firstInitial + lastInitial).uppercased()
    }
}

// MARK: - Profile Section Container
private struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.bottom, 6)
            
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                    )
            )
        }
    }
}

// MARK: - Profile Divider
private struct ProfileDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Adaptive.stroke)
            .frame(height: 0.5)
            .padding(.leading, 44)
    }
}

// MARK: - Profile Editable Row
private struct ProfileEditableRow: View {
    let icon: String
    let title: String
    let value: String
    @Binding var isEditing: Bool
    @Binding var tempValue: String
    let onSave: () -> Void
    var keyboardType: UIKeyboardType = .default
    
    @State private var localEditing = false
    @FocusState private var isFocused: Bool
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(BrandColors.goldBase.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                if localEditing {
                    TextField("", text: $tempValue)
                        .font(.body)
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .keyboardType(keyboardType)
                        .focused($isFocused)
                        .onSubmit {
                            onSave()
                            localEditing = false
                        }
                } else {
                    Text(value)
                        .font(.body)
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
            }
            
            Spacer()
            
            if localEditing {
                Button(action: {
                    impactLight.impactOccurred()
                    onSave()
                    localEditing = false
                }) {
                    Text("Save")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(BrandColors.goldBase)
                }
            } else {
                Button(action: {
                    impactLight.impactOccurred()
                    tempValue = value == "Not set" ? "" : value
                    localEditing = true
                    DispatchQueue.main.async {
                        isFocused = true
                    }
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Profile Info Row (Non-editable)
private struct ProfileInfoRow: View {
    let icon: String
    let title: String
    let value: String
    var valueColor: Color = DS.Adaptive.textSecondary
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(BrandColors.goldBase.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            Text(title)
                .font(.body)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(valueColor)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Bio Editor Sheet
private struct ProfileBioEditor: View {
    @Binding var bio: String
    @Binding var tempValue: String
    @Binding var isPresented: Bool
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $tempValue)
                    .font(.body)
                    .padding()
                    .scrollContentBackground(.hidden)
                    .background(DS.Adaptive.cardBackground)
                
                Text("\(tempValue.count)/250 characters")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .padding(.bottom, 16)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Edit Bio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        impactLight.impactOccurred()
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        impactLight.impactOccurred()
                        bio = String(tempValue.prefix(250))
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// PaymentMethodsView and ConnectedAccountsView now redirect to PortfolioPaymentMethodsView
// which provides full exchange/wallet connection functionality

struct AboutView: View {
    @State private var developerTapCount: Int = 0
    @State private var showDeveloperEntry: Bool = false
    @State private var developerCode: String = ""
    @State private var showDeveloperAlert: Bool = false
    @State private var developerAlertMessage: String = ""
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [BrandColors.goldLight.opacity(0.3), BrandColors.goldDark.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(BrandColors.goldBase)
                }
                .padding(.top, 30)
                
                VStack(spacing: 4) {
                    Text("CryptoSage AI")
                        .font(.title2.weight(.bold))
                    
                    // Version text with secret developer tap gesture
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .onTapGesture(count: 1) {
                            developerTapCount += 1
                            if developerTapCount >= 5 {
                                impactHeavy.impactOccurred()
                                showDeveloperEntry = true
                                developerTapCount = 0
                            } else if developerTapCount >= 3 {
                                impactLight.impactOccurred()
                            }
                        }
                }
                
                Text("Your intelligent crypto trading companion. Track portfolios, analyze markets, and make smarter trades with AI-powered insights.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                
                // Developer mode indicator (only shown when active)
                if subscriptionManager.isDeveloperMode {
                    developerModeIndicator
                }
                
                Spacer()
            }
        }
        .navigationTitle("About")
        .sheet(isPresented: $showDeveloperEntry) {
            DeveloperModeEntryView(
                code: $developerCode,
                onSubmit: { enteredCode in
                    if subscriptionManager.enableDeveloperMode(code: enteredCode) {
                        developerAlertMessage = "Developer mode enabled! All features are now unlocked."
                        showDeveloperAlert = true
                    } else {
                        developerAlertMessage = "Invalid code. Please try again."
                        showDeveloperAlert = true
                    }
                    developerCode = ""
                },
                onDisable: {
                    subscriptionManager.disableDeveloperMode()
                    developerAlertMessage = "Developer mode disabled."
                    showDeveloperAlert = true
                },
                isDeveloperMode: subscriptionManager.isDeveloperMode
            )
        }
        .alert("Developer Mode", isPresented: $showDeveloperAlert) {
            Button("OK") { }
        } message: {
            Text(developerAlertMessage)
        }
    }
    
    private var developerModeIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 14))
            Text("Developer Mode Active")
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.top, 8)
    }
}

// MARK: - Developer Mode Entry View
struct DeveloperModeEntryView: View {
    @Binding var code: String
    var onSubmit: (String) -> Void
    var onDisable: () -> Void
    var isDeveloperMode: Bool
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isCodeFieldFocused: Bool
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                }
                .padding(.top, 20)
                
                Text("Developer Mode")
                    .font(.title2.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                if isDeveloperMode {
                    // Already in developer mode - show status
                    VStack(spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Developer mode is active")
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                        .font(.subheadline.weight(.medium))
                        
                        Text("All subscription features are unlocked. AI prompts are unlimited.")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        Button {
                            impactLight.impactOccurred()
                            onDisable()
                            dismiss()
                        } label: {
                            Text("Disable Developer Mode")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.red)
                                .cornerRadius(14)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    }
                } else {
                    // Not in developer mode - show code entry
                    VStack(spacing: 16) {
                        Text("Enter the developer code to unlock all features for testing.")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        SecureField("Developer Code", text: $code)
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(DS.Adaptive.cardBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
                            )
                            .padding(.horizontal, 24)
                            .focused($isCodeFieldFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                        
                        Button {
                            impactLight.impactOccurred()
                            onSubmit(code)
                            dismiss()
                        } label: {
                            Text("Activate")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(14)
                        }
                        .padding(.horizontal, 24)
                        .disabled(code.isEmpty)
                        .opacity(code.isEmpty ? 0.6 : 1)
                    }
                }
                
                Spacer()
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isCodeFieldFocused = !isDeveloperMode
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expandedFAQ: String? = nil
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    // FAQ Data
    private let faqItems: [(id: String, question: String, answer: String)] = [
        (
            id: "exchanges",
            question: "How do I connect my exchanges?",
            answer: "Go to Settings > Linked Accounts > Add New Connection. You can connect via OAuth (Coinbase), API keys (Binance, Kraken, etc.), or by adding wallet addresses. Your credentials are stored securely in your device's keychain."
        ),
        (
            id: "ai-prompts",
            question: "How do AI prompts work?",
            answer: "CryptoSage AI uses advanced language models to analyze your portfolio, answer crypto questions, and provide market insights. Free users get 3 prompts/day, Pro users get 20/day, and Elite users have unlimited access."
        ),
        (
            id: "subscriptions",
            question: "What's the difference between plans?",
            answer: "Free: Basic features with ads and 3 AI prompts/day.\nPro ($9/mo): 20 AI prompts/day, trade execution, smart alerts, ad-free.\nElite ($19/mo): Unlimited AI, automated trading bots, custom strategies, priority support."
        ),
        (
            id: "security",
            question: "How is my data kept secure?",
            answer: "All sensitive data (API keys, credentials) is encrypted and stored in Apple's Secure Keychain. We never store your private keys on our servers. Exchange connections use read-only API permissions by default."
        ),
        (
            id: "sync",
            question: "Why isn't my portfolio syncing?",
            answer: "Check your internet connection and ensure your API keys haven't expired. Go to Linked Accounts to verify connection status. If issues persist, try removing and re-adding the connection."
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            helpHeader
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Hero Section
                    heroSection
                        .padding(.top, 8)
                    
                    // Contact Section
                    contactSection
                    
                    // FAQ Section
                    faqSection
                    
                    // Resources Section
                    resourcesSection
                    
                    // App Info
                    appInfoSection
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
    
    // MARK: - Header
    
    private var helpHeader: some View {
        HStack {
            Button(action: {
                impactLight.impactOccurred()
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldBase, BrandColors.goldLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            }
            
            Spacer()
            
            Text("Help & Support")
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
                
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldBase, BrandColors.goldLight],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            Text("How can we help?")
                .font(.title2.weight(.bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Find answers to common questions or reach out to our support team.")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Contact Section
    
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONTACT US")
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                ContactCard(
                    icon: "envelope.fill",
                    title: "Email Support",
                    subtitle: "support@cryptosage.ai",
                    color: .blue
                ) {
                    if let url = URL(string: "mailto:support@cryptosage.ai") {
                        UIApplication.shared.open(url)
                    }
                }
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 52)
                
                ContactCard(
                    icon: "at",
                    title: "Twitter / X",
                    subtitle: "@CryptoSageAI",
                    color: Color(red: 0.11, green: 0.63, blue: 0.95)
                ) {
                    if let url = URL(string: "https://twitter.com/cryptosageai") {
                        UIApplication.shared.open(url)
                    }
                }
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 52)
                
                ContactCard(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Discord Community",
                    subtitle: "Join 10k+ members",
                    color: Color(red: 0.34, green: 0.39, blue: 0.95)
                ) {
                    if let url = URL(string: "https://discord.gg/cryptosage") {
                        UIApplication.shared.open(url)
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
    
    // MARK: - FAQ Section
    
    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FREQUENTLY ASKED QUESTIONS")
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                ForEach(faqItems, id: \.id) { item in
                    FAQRow(
                        question: item.question,
                        answer: item.answer,
                        isExpanded: expandedFAQ == item.id,
                        onTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if expandedFAQ == item.id {
                                    expandedFAQ = nil
                                } else {
                                    expandedFAQ = item.id
                                }
                            }
                            impactLight.impactOccurred()
                        }
                    )
                    
                    if item.id != faqItems.last?.id {
                        Divider().background(DS.Adaptive.stroke).padding(.leading, 16)
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
    
    // MARK: - Resources Section
    
    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RESOURCES")
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                NavigationLink(destination: PrivacyPolicyView()) {
                    ResourceRow(icon: "hand.raised.fill", title: "Privacy Policy", color: .purple)
                }
                .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 52)
                
                NavigationLink(destination: TermsOfServiceView()) {
                    ResourceRow(icon: "doc.text.fill", title: "Terms of Service", color: .orange)
                }
                .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 52)
                
                ResourceRow(icon: "star.fill", title: "Rate App", color: .yellow) {
                    // Request app review
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        SKStoreReviewController.requestReview(in: scene)
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
    
    // MARK: - App Info Section
    
    private var appInfoSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandColors.goldBase, BrandColors.goldLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("CryptoSage AI")
                .font(.headline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
            
            Text("Made with ❤️ for crypto enthusiasts")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}

// MARK: - Contact Card Component

private struct ContactCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FAQ Row Component

private struct FAQRow: View {
    let question: String
    let answer: String
    let isExpanded: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack {
                    Text(question)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BrandColors.goldBase)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Text(answer)
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Resource Row Component

private struct ResourceRow: View {
    let icon: String
    let title: String
    let color: Color
    var action: (() -> Void)? = nil
    
    var body: some View {
        Group {
            if let action = action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
    }
    
    private var rowContent: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(12)
    }
}

// MARK: - Privacy Policy View

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    impactLight.impactOccurred()
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BrandColors.goldDiagonalGradient)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                
                Spacer()
                
                Text("Privacy Policy")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Last Updated: January 2026")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    PolicySection(title: "1. Information We Collect", content: """
                    Information you provide directly:
                    • Display name and preferences
                    • Portfolio data from connected exchanges (via read-only API)
                    • Transaction history you choose to import
                    • AI chat conversations (processed via OpenAI)
                    
                    Automatically collected (anonymous):
                    • Device type and iOS version
                    • App usage analytics (screens viewed, features used)
                    • Crash reports and performance metrics
                    • Session duration and frequency
                    
                    We do NOT collect:
                    • Your name, email, or contact information
                    • Precise location data
                    • Contacts, photos, or other device data
                    • Exchange passwords (only encrypted API keys)
                    """)
                    
                    PolicySection(title: "2. How We Use Your Information", content: """
                    Your information is used to:
                    • Provide and improve CryptoSage AI services
                    • Display your portfolio from connected exchanges
                    • Generate personalized AI insights
                    • Send price alerts and notifications you configure
                    • Fix bugs and improve app stability
                    • Understand which features to prioritize
                    
                    We use TelemetryDeck for anonymous analytics and Sentry for crash reporting. Both services are privacy-focused and do not track you across apps.
                    """)
                    
                    PolicySection(title: "3. Data Security", content: """
                    We implement industry-standard security measures:
                    • API keys are encrypted in Apple's Secure Keychain
                    • All data transmission uses TLS 1.3 encryption
                    • We never store your exchange passwords
                    • Read-only API permissions by default
                    • Biometric authentication available
                    • Screen protection in app switcher
                    • No data stored on our servers (local-first architecture)
                    """)
                    
                    PolicySection(title: "4. Data Sharing", content: """
                    We do NOT sell your personal data.
                    
                    We may share anonymized, aggregated data with:
                    • Analytics providers (TelemetryDeck) for app improvement
                    • Crash reporting services (Sentry) for bug fixes
                    
                    We may share data when required by:
                    • Legal authorities with valid legal process
                    • To protect our rights or safety
                    
                    Third-party services we integrate with:
                    • OpenAI (AI chat - your prompts are sent to their API)
                    • CoinGecko (market data, prices, coin information)
                    • Binance (real-time prices, order books, charts)
                    • TradingView (charts and technical analysis, if enabled)
                    • Your connected exchanges (Coinbase, Binance, Kraken, etc.)
                    
                    These services receive API requests from your device. Your IP address may be logged by these services per their respective privacy policies.
                    """)
                    
                    PolicySection(title: "5. Your Rights", content: """
                    You have the right to:
                    • Access your personal data stored locally
                    • Request data deletion (clear app data)
                    • Export your portfolio data
                    • Opt out of analytics (Settings > Privacy)
                    • Disconnect linked exchanges at any time
                    • Delete your AI chat history
                    
                    To exercise these rights, use the in-app settings or contact us at the email below.
                    """)
                    
                    // CCPA Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("6. California Privacy Rights (CCPA)")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("""
                        If you are a California resident, you have the right to:
                        • Know what personal information we collect
                        • Request deletion of your personal information
                        • Opt out of the "sale" of personal information
                        
                        CryptoSage does NOT sell your personal information.
                        
                        To opt out of analytics collection, go to Settings > Privacy & Analytics and disable "Share Analytics".
                        
                        To submit a data access or deletion request, contact privacy@cryptosage.ai.
                        """)
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // GDPR Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("7. European Privacy Rights (GDPR)")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("""
                        If you are in the European Economic Area, you have:
                        • Right to access your data
                        • Right to rectification
                        • Right to erasure ("right to be forgotten")
                        • Right to restrict processing
                        • Right to data portability
                        • Right to object to processing
                        
                        Our analytics provider (TelemetryDeck) is EU-based and GDPR-compliant by design.
                        """)
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    PolicySection(title: "8. Children's Privacy", content: """
                    CryptoSage is not intended for users under 18. We do not knowingly collect information from children.
                    """)
                    
                    PolicySection(title: "9. Data Retention", content: """
                    Local data (stored on your device):
                    • Portfolio data: Kept until you disconnect the exchange
                    • AI chat history: Kept until you delete it manually
                    • Preferences and settings: Kept until you reset the app
                    • Price alerts: Kept until you delete them
                    
                    Analytics data (TelemetryDeck):
                    • Retained for 90 days, then automatically deleted
                    • Fully anonymous and not linked to your identity
                    
                    Crash reports (Sentry):
                    • Retained for 90 days, then automatically deleted
                    • Contains no personal information
                    
                    You can delete all local data at any time by uninstalling the app or clearing app data in iOS Settings.
                    """)
                    
                    PolicySection(title: "10. Changes to This Policy", content: """
                    We may update this Privacy Policy periodically. We will notify you of significant changes through the app or by other means.
                    """)
                    
                    PolicySection(title: "11. Contact Us", content: """
                    For privacy-related inquiries:
                    Email: privacy@cryptosage.ai
                    
                    For data access or deletion requests, include "Data Request" in your subject line.
                    """)
                }
                .padding(20)
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

// MARK: - Terms of Service View

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    impactLight.impactOccurred()
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BrandColors.goldDiagonalGradient)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                
                Spacer()
                
                Text("Terms of Service")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Last Updated: January 2026")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    PolicySection(title: "1. Acceptance of Terms", content: """
                    By using CryptoSage AI, you agree to these Terms of Service. If you do not agree, please do not use the app.
                    """)
                    
                    PolicySection(title: "2. Service Description", content: """
                    CryptoSage AI provides:
                    • Cryptocurrency portfolio tracking
                    • AI-powered market insights and chat
                    • Exchange and wallet integrations
                    • Price alerts and notifications
                    
                    We do not provide financial advice. All information is for educational purposes only.
                    """)
                    
                    PolicySection(title: "3. User Responsibilities", content: """
                    You are responsible for:
                    • Maintaining account security
                    • Ensuring accurate information
                    • Complying with local laws regarding cryptocurrency
                    • Your own trading decisions
                    • Keeping API keys secure
                    """)
                    
                    PolicySection(title: "4. Disclaimer of Warranties", content: """
                    CryptoSage AI is provided "as is" without warranties. We do not guarantee:
                    • Accuracy of price data or AI insights
                    • Continuous, uninterrupted service
                    • Compatibility with all exchanges
                    • Investment returns or outcomes
                    """)
                    
                    PolicySection(title: "5. Limitation of Liability", content: """
                    We are not liable for:
                    • Financial losses from trading decisions
                    • Data loss or security breaches beyond our control
                    • Third-party exchange issues
                    • Indirect or consequential damages
                    """)
                    
                    PolicySection(title: "6. Subscriptions & Payments", content: """
                    • Subscriptions are billed through Apple's App Store
                    • Prices may change with notice
                    • Refunds are handled by Apple
                    • Cancellation takes effect at period end
                    """)
                    
                    PolicySection(title: "7. Termination", content: """
                    We may terminate or suspend access for:
                    • Violation of these terms
                    • Fraudulent or illegal activity
                    • Non-payment of subscription fees
                    """)
                    
                    PolicySection(title: "8. Contact", content: """
                    Questions about these terms:
                    Email: legal@cryptosage.ai
                    """)
                }
                .padding(20)
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

// MARK: - Analytics Info View

struct AnalyticsInfoView: View {
    @Environment(\.dismiss) private var dismiss
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    impactLight.impactOccurred()
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BrandColors.goldDiagonalGradient)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                
                Spacer()
                
                Text("Analytics & Data")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Privacy Badge
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        Text("Privacy-First Analytics")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(8)
                    
                    PolicySection(title: "What We Collect", content: """
                    We collect anonymous usage data to improve CryptoSage:
                    
                    • Which features you use most (screens, tabs)
                    • App performance (load times, errors)
                    • Device type and iOS version
                    • Session duration
                    
                    This helps us understand what features to improve and prioritize.
                    """)
                    
                    PolicySection(title: "What We DON'T Collect", content: """
                    We never collect or store:
                    
                    • Your name, email, or personal info
                    • Portfolio values or holdings
                    • Exchange API keys or credentials
                    • Transaction history or trade details
                    • Wallet addresses
                    • Location data
                    • Contacts or photos
                    """)
                    
                    PolicySection(title: "How Data is Used", content: """
                    Anonymous analytics help us:
                    
                    • Fix crashes and bugs faster
                    • Improve slow features
                    • Decide which features to build next
                    • Ensure the app works well on all devices
                    
                    We do NOT sell your data to third parties.
                    """)
                    
                    PolicySection(title: "Your Control", content: """
                    You have full control:
                    
                    • Toggle analytics off in Settings anytime
                    • When disabled, zero data is sent
                    • No tracking across other apps
                    • No advertising or retargeting
                    """)
                    
                    // CCPA Notice
                    VStack(alignment: .leading, spacing: 8) {
                        Text("California Residents (CCPA)")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Under the California Consumer Privacy Act, you have the right to know what data we collect and to opt out. CryptoSage does not sell personal information. Use the toggle in Settings to opt out of analytics collection.")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(20)
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

// MARK: - Policy Section Component

private struct PolicySection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text(content)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LanguageSettingsView: View {
    @Binding var selectedLanguage: String
    
    var body: some View {
        Form {
            Picker("Language", selection: $selectedLanguage) {
                Text("English").tag("English")
                Text("Spanish").tag("Spanish")
                Text("French").tag("French")
            }
            .pickerStyle(.inline)
        }
        .navigationTitle("Language")
    }
}

struct CurrencySettingsView: View {
    @Binding var selectedCurrency: String
    
    var body: some View {
        Form {
            Picker("Display Currency", selection: $selectedCurrency) {
                Text("USD - US Dollar").tag("USD")
                Text("EUR - Euro").tag("EUR")
                Text("GBP - British Pound").tag("GBP")
                Text("JPY - Japanese Yen").tag("JPY")
                Text("CAD - Canadian Dollar").tag("CAD")
                Text("AUD - Australian Dollar").tag("AUD")
            }
            .pickerStyle(.inline)
        }
        .navigationTitle("Currency")
    }
}

// MARK: - Linked Accounts View

struct LinkedAccountsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var accountsManager = ConnectedAccountsManager.shared
    
    @State private var accountToRemove: ConnectedAccount?
    @State private var showRemoveConfirmation = false
    @State private var accountToRename: ConnectedAccount?
    @State private var renameText: String = ""
    @State private var showRenameSheet = false
    @State private var showAddConnections = false
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    
    // MARK: - Mock Data for Design Preview (Remove in production)
    private let mockAccounts: [ConnectedAccount] = [
        ConnectedAccount(
            id: "mock-1",
            name: "Coinbase",
            exchangeType: "exchange",
            provider: "oauth",
            isDefault: true,
            connectedAt: Date().addingTimeInterval(-86400 * 30), // 30 days ago
            lastSyncAt: Date().addingTimeInterval(-3600) // 1 hour ago
        ),
        ConnectedAccount(
            id: "mock-2",
            name: "Binance US",
            exchangeType: "exchange",
            provider: "direct",
            isDefault: false,
            connectedAt: Date().addingTimeInterval(-86400 * 15), // 15 days ago
            lastSyncAt: Date().addingTimeInterval(-7200) // 2 hours ago
        ),
        ConnectedAccount(
            id: "mock-3",
            name: "ETH Wallet",
            exchangeType: "wallet",
            provider: "blockchain",
            isDefault: false,
            connectedAt: Date().addingTimeInterval(-86400 * 7), // 7 days ago
            lastSyncAt: Date(),
            walletAddress: "0x742d...F3e8"
        ),
        ConnectedAccount(
            id: "mock-4",
            name: "Bitcoin Wallet",
            exchangeType: "wallet",
            provider: "blockchain",
            isDefault: false,
            connectedAt: Date().addingTimeInterval(-86400 * 3), // 3 days ago
            lastSyncAt: Date().addingTimeInterval(-1800), // 30 min ago
            walletAddress: "bc1q...9xkp"
        )
    ]
    
    // Use mock data for preview, real data otherwise
    // TODO: Set this to false for production release
    private let useMockData = true
    
    private var displayAccounts: [ConnectedAccount] {
        useMockData ? mockAccounts : accountsManager.accounts
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            linkedAccountsHeader
            
            if displayAccounts.isEmpty {
                // Empty state
                emptyStateView
            } else {
                // Accounts list
                ScrollView {
                    VStack(spacing: 16) {
                        // Stats summary
                        statsSummary
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                        
                        // Connected accounts list
                        VStack(spacing: 0) {
                            ForEach(displayAccounts) { account in
                                LinkedAccountRow(
                                    account: account,
                                    onRemove: {
                                        accountToRemove = account
                                        showRemoveConfirmation = true
                                    },
                                    onRename: {
                                        accountToRename = account
                                        renameText = account.name
                                        showRenameSheet = true
                                    }
                                )
                                
                                if account.id != displayAccounts.last?.id {
                                    Divider()
                                        .background(DS.Adaptive.stroke)
                                        .padding(.leading, 60)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DS.Adaptive.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                                )
                        )
                        .padding(.horizontal, 16)
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            
            // Add New Connection Button (always visible at bottom)
            addConnectionButton
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showAddConnections) {
            PortfolioPaymentMethodsView()
        }
        .confirmationDialog(
            "Remove \(accountToRemove?.name ?? "this account")?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let account = accountToRemove {
                    impactMedium.impactOccurred()
                    accountsManager.removeAccount(account)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will disconnect the account from your portfolio.")
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameAccountSheet(accountName: $renameText) {
                if let account = accountToRename {
                    accountsManager.renameAccount(account, newName: renameText)
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var linkedAccountsHeader: some View {
        HStack {
            Button(action: {
                impactLight.impactOccurred()
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(chipGoldGradient)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            }
            
            Spacer()
            
            Text("Linked Accounts")
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
    
    // MARK: - Stats Summary
    
    private var statsSummary: some View {
        HStack(spacing: 16) {
            StatBadge(
                icon: "link.circle.fill",
                value: "\(displayAccounts.count)",
                label: "Connected",
                color: .green
            )
            
            let exchangeCount = displayAccounts.filter { $0.exchangeType == "exchange" }.count
            StatBadge(
                icon: "building.columns.fill",
                value: "\(exchangeCount)",
                label: "Exchanges",
                color: BrandColors.goldBase
            )
            
            let walletCount = displayAccounts.filter { $0.exchangeType == "wallet" }.count
            StatBadge(
                icon: "wallet.pass.fill",
                value: "\(walletCount)",
                label: "Wallets",
                color: .purple
            )
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldLight.opacity(0.2), BrandColors.goldDark.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            Text("No Accounts Linked")
                .font(.title3.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Connect your exchanges and wallets to track your crypto portfolio in one place.")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    // MARK: - Add Connection Button
    
    private var addConnectionButton: some View {
        VStack(spacing: 0) {
            Divider()
                .background(DS.Adaptive.stroke)
            
            Button(action: {
                impactLight.impactOccurred()
                showAddConnections = true
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                    Text("Add New Connection")
                        .font(.headline)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DS.Adaptive.background)
        }
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Linked Account Row

private struct LinkedAccountRow: View {
    let account: ConnectedAccount
    let onRemove: () -> Void
    let onRename: () -> Void
    
    private var providerColor: Color {
        switch account.provider {
        case "oauth": return .green
        case "direct": return .orange
        case "blockchain": return .purple
        case "3commas": return .cyan
        default: return BrandColors.goldBase
        }
    }
    
    private var providerIcon: String {
        switch account.provider {
        case "oauth": return "bolt.fill"
        case "direct": return "key.fill"
        case "blockchain": return "wallet.pass.fill"
        case "3commas": return "gearshape.2.fill"
        default: return "link"
        }
    }
    
    private var typeLabel: String {
        account.exchangeType == "wallet" ? "Wallet" : "Exchange"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(providerColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                Image(systemName: providerIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(providerColor)
            }
            
            // Account info
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .font(.body.weight(.medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(typeLabel)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text(account.provider.capitalized)
                        .font(.caption)
                        .foregroundColor(providerColor)
                    
                    if account.isDefault {
                        Text("• Default")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            // Menu
            Menu {
                Button {
                    onRename()
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Rename Account Sheet

private struct RenameAccountSheet: View {
    @Binding var accountName: String
    var onSave: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account Name")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    TextField("Enter name", text: $accountName)
                        .padding()
                        .background(DS.Adaptive.cardBackground)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(DS.Adaptive.stroke, lineWidth: 1)
                        )
                }
                .padding(.horizontal, 20)
                
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(DS.Adaptive.cardBackground)
                            .cornerRadius(12)
                    }
                    
                    Button {
                        impactLight.impactOccurred()
                        onSave()
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(BrandColors.goldBase)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .padding(.top, 20)
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Rename Account")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Home Screen Customization View

struct HomeCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var showWatchlist: Bool
    @Binding var showMarketStats: Bool
    @Binding var showSentiment: Bool
    @Binding var showHeatmap: Bool
    @Binding var showTrending: Bool
    @Binding var showArbitrage: Bool
    @Binding var showEvents: Bool
    @Binding var showNews: Bool
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            HStack {
                Button(action: {
                    impactLight.impactOccurred()
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(chipGoldGradient)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                }
                
                Spacer()
                
                Text("Customize Home")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Color.clear
                    .frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(DS.Adaptive.background)
            
            ScrollView {
                VStack(spacing: 16) {
                    // Info card
                    VStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 32))
                            .foregroundColor(BrandColors.goldBase)
                        
                        Text("Customize Your Home Screen")
                            .font(.headline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Toggle sections on or off to personalize your home screen experience.")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DS.Adaptive.cardBackgroundElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Section toggles
                    VStack(spacing: 0) {
                        HomeSectionToggle(
                            icon: "star.fill",
                            title: "Watchlist",
                            description: "Your favorite coins and quick access",
                            isOn: $showWatchlist,
                            onChange: { selectionFeedback.selectionChanged() }
                        )
                        
                        SettingsDivider()
                        
                        HomeSectionToggle(
                            icon: "chart.bar.xaxis",
                            title: "Market Stats",
                            description: "Global market cap, volume, and dominance",
                            isOn: $showMarketStats,
                            onChange: { selectionFeedback.selectionChanged() }
                        )
                        
                        SettingsDivider()
                        
                        HomeSectionToggle(
                            icon: "face.smiling",
                            title: "Market Sentiment",
                            description: "Fear & Greed index and market mood",
                            isOn: $showSentiment,
                            onChange: { selectionFeedback.selectionChanged() }
                        )
                        
                        SettingsDivider()
                        
                        HomeSectionToggle(
                            icon: "square.grid.2x2",
                            title: "Heat Map",
                            description: "Visual market performance overview",
                            isOn: $showHeatmap,
                            onChange: { selectionFeedback.selectionChanged() }
                        )
                        
                        SettingsDivider()
                        
                        HomeSectionToggle(
                            icon: "flame.fill",
                            title: "Trending",
                            description: "Hot and trending cryptocurrencies",
                            isOn: $showTrending,
                            onChange: { selectionFeedback.selectionChanged() }
                        )
                        
                        SettingsDivider()
                        
                        HomeSectionToggle(
                            icon: "arrow.left.arrow.right",
                            title: "Arbitrage",
                            description: "Price differences across exchanges",
                            isOn: $showArbitrage,
                            onChange: { selectionFeedback.selectionChanged() }
                        )
                        
                        SettingsDivider()
                        
                        HomeSectionToggle(
                            icon: "calendar",
                            title: "Events",
                            description: "Upcoming crypto events and launches",
                            isOn: $showEvents,
                            onChange: { selectionFeedback.selectionChanged() }
                        )
                        
                        SettingsDivider()
                        
                        HomeSectionToggle(
                            icon: "newspaper.fill",
                            title: "News",
                            description: "Latest cryptocurrency news",
                            isOn: $showNews,
                            onChange: { selectionFeedback.selectionChanged() }
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.Adaptive.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                            )
                    )
                    .padding(.horizontal, 16)
                    
                    // Reset button
                    Button(action: {
                        impactLight.impactOccurred()
                        resetToDefaults()
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Defaults")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(BrandColors.goldBase)
                    }
                    .padding(.top, 8)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
    
    private func resetToDefaults() {
        showWatchlist = true
        showMarketStats = true
        showSentiment = true
        showHeatmap = true
        showTrending = true
        showArbitrage = true
        showEvents = true
        showNews = true
    }
}

// MARK: - Home Section Toggle Row

private struct HomeSectionToggle: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool
    let onChange: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BrandColors.goldBase.opacity(isOn ? 0.15 : 0.08))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isOn ? BrandColors.goldBase : DS.Adaptive.textTertiary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(BrandColors.goldBase)
                .onChange(of: isOn) { _ in onChange() }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Paper Trading Settings Section

/// A dedicated section for Paper Trading with subscription gating
struct PaperTradingSettingsSection: View {
    let selectionFeedback: UISelectionFeedbackGenerator
    let impactLight: UIImpactFeedbackGenerator
    
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @State private var showUpgradePrompt = false
    
    private var hasAccess: Bool {
        subscriptionManager.hasAccess(to: .paperTrading)
    }
    
    var body: some View {
        SettingsSection(title: "PAPER TRADING") {
            if hasAccess {
                // Full access - show toggle and stats
                enabledContent
            } else {
                // Locked - show upgrade prompt
                lockedContent
            }
        }
    }
    
    private var enabledContent: some View {
        VStack(spacing: 0) {
            SettingsToggleRow(
                icon: "doc.text.fill",
                title: "Paper Trading",
                isOn: Binding(
                    get: { paperTradingManager.isPaperTradingEnabled },
                    set: { newVal in
                        selectionFeedback.selectionChanged()
                        if newVal {
                            paperTradingManager.enablePaperTrading()
                        } else {
                            paperTradingManager.disablePaperTrading()
                        }
                    }
                ),
                iconColor: .blue
            )
            
            // Show stats when paper trading is enabled
            if paperTradingManager.isPaperTradingEnabled {
                VStack(spacing: 8) {
                    // Balance and Badge row
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Balance")
                                .font(.system(size: 11))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text("$\(Int(paperTradingManager.balance(for: "USDT")).formatted())")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                        
                        // Trade count
                        let tradeCount = paperTradingManager.paperTradeHistory.count
                        if tradeCount > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Trades")
                                    .font(.system(size: 11))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                Text("\(tradeCount)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                            }
                        }
                        
                        PaperTradeBadge()
                            .scaleEffect(0.85)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                )
                .padding(.top, 8)
            } else {
                Text("Practice trading with $100,000 virtual money")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .padding(.top, 4)
            }
            
            SettingsDivider()
            
            NavigationLink(destination: PaperTradingSettingsView()) {
                SettingsRow(icon: "slider.horizontal.3", title: "Paper Trading Settings")
            }
            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
        }
    }
    
    private var lockedContent: some View {
        VStack(spacing: 12) {
            // Locked toggle row
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue.opacity(0.5))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Paper Trading")
                            .font(.body)
                            .foregroundColor(DS.Adaptive.textPrimary.opacity(0.6))
                        
                        LockedFeatureBadge(feature: .paperTrading, style: .compact)
                    }
                    
                    Text("Practice with $100,000 virtual money")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundColor(BrandColors.goldBase)
            }
            .padding(.vertical, 4)
            
            // Upgrade prompt
            Button {
                impactLight.impactOccurred()
                showUpgradePrompt = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14))
                    Text("Upgrade to Pro to Unlock")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(10)
            }
            .padding(.top, 4)
        }
        .sheet(isPresented: $showUpgradePrompt) {
            FeatureUpgradePromptView(feature: .paperTrading)
        }
    }
}

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView()
                .environmentObject(PortfolioViewModel.sample)
        }
    }
}
