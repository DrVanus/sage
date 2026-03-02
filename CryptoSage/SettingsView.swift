import SwiftUI
import Foundation
import StoreKit
import Combine
import AuthenticationServices
// Trading credentials UI

struct SettingsView: View {
    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    // MARK: - App Storage Defaults
    @AppStorage("Settings.DarkMode") private var isDarkMode = false
    @AppStorage("App.Appearance") private var appAppearanceRaw: String = "system"
    @AppStorage("hideBalances") private var hideBalances = false
    @AppStorage("showStocksInPortfolio") private var showStocksInPortfolio = false  // Default OFF - opt-in feature
    @AppStorage("language") private var language = "English"
    @AppStorage("selectedCurrency") private var selectedCurrency = "USD"
    
    // MARK: - Home Screen Section Visibility
    @AppStorage("Home.showPortfolio") private var showPortfolio = true
    @AppStorage("Home.showWatchlist") private var showWatchlist = true
    @AppStorage("Home.showMarketStats") private var showMarketStats = false
    @AppStorage("Home.showSentiment") private var showSentiment = true
    @AppStorage("Home.showHeatmap") private var showHeatmap = true
    @AppStorage("Home.showTrending") private var showTrending = true
    @AppStorage("Home.showArbitrage") private var showArbitrage = true
    @AppStorage("Home.showEvents") private var showEvents = true
    @AppStorage("Home.showNews") private var showNews = true
    @AppStorage("Home.showAIInsights") private var showAIInsights = true
    @AppStorage("Home.showAIPredictions") private var showAIPredictions = true
    @AppStorage("Home.showWhaleActivity") private var showWhaleActivity = true
    @AppStorage("Home.showCommunity") private var showCommunity = true
    @AppStorage("Home.showTransactions") private var showTransactions = true
    @AppStorage("Home.showPromos") private var showPromos = true
    @AppStorage("Home.showCommoditiesOverview") private var showCommodities = true
    
    // Analytics
    @AppStorage("Analytics.Enabled") private var analyticsEnabled = true
    
    // State
    @State private var mockDailyChange: Double = 2.0
    @State private var showClearCacheAlert = false
    @State private var showShareSheet = false
    @State private var cacheSize: String = "Calculating..."
    
    // Assume PortfolioViewModel is provided via EnvironmentObject
    @EnvironmentObject var portfolioViewModel: PortfolioViewModel
    
    // Subscription manager for dynamic button text
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    // Authentication manager for sign out visibility
    @ObservedObject private var authManager = AuthenticationManager.shared
    
    // Dynamic subscription button title based on current tier
    private var subscriptionButtonTitle: String {
        switch subscriptionManager.effectiveTier {
        case .free: return "Upgrade to Pro"
        case .pro: return "Upgrade to Premium"
        case .premium: return "Manage Subscription"
        }
    }
    
    private var subscriptionSubtitle: String {
        switch subscriptionManager.effectiveTier {
        case .free: return "Unlock AI, paper trading & more"
        case .pro: return "Pro plan active"
        case .premium: return "Premium plan active"
        }
    }
    
    // State for developer quick access panel
    @State private var showDeveloperPanelSheet = false
    
    // MARK: - Developer Quick Access Section (Top of Settings)
    private var developerQuickAccessSection: some View {
        VStack(spacing: 12) {
            // Header with icon
            HStack {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                Text("DEVELOPER MODE")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.orange)
                Spacer()
                
                // Live trading status indicator — shared ModeBadge for consistency
                if subscriptionManager.developerLiveTradingEnabled {
                    ModeBadge(mode: .liveTrading, variant: .compact)
                }
            }
            
            // Tier Simulator - Compact
            VStack(spacing: 6) {
                HStack {
                    Text("Simulated Tier")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                }
                
                Picker("Tier", selection: $subscriptionManager.developerSimulatedTier) {
                    Text("Free").tag(SubscriptionTierType.free)
                    Text("Pro").tag(SubscriptionTierType.pro)
                    Text("Premium").tag(SubscriptionTierType.premium)
                }
                .pickerStyle(.segmented)
            }
            
            // Live Trading Toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Trading")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text(subscriptionManager.developerLiveTradingEnabled ? "Real money trades enabled" : "Paper trading only")
                        .font(.caption)
                        .foregroundColor(subscriptionManager.developerLiveTradingEnabled ? .red : DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $subscriptionManager.developerLiveTradingEnabled)
                    .labelsHidden()
                    .tint(.red)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(subscriptionManager.developerLiveTradingEnabled ? Color.red.opacity(0.1) : DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(subscriptionManager.developerLiveTradingEnabled ? Color.red.opacity(0.4) : DS.Adaptive.stroke, lineWidth: 1)
                    )
            )
            
            // Open Full Developer Panel Button
            Button {
                impactLight.impactOccurred()
                showDeveloperPanelSheet = true
            } label: {
                HStack {
                    Text("Open Developer Panel")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundColor(.orange)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1.5)
                )
        )
        .sheet(isPresented: $showDeveloperPanelSheet) {
            DeveloperModeEntryView(
                code: .constant(""),
                onSubmit: { _ in },
                onDisable: {
                    subscriptionManager.disableDeveloperMode()
                },
                isDeveloperMode: true
            )
        }
    }
    
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
                VStack(spacing: 8) {
                    // MARK: - Developer Mode Quick Access (Top of Settings when active)
                    if subscriptionManager.isDeveloperMode {
                        developerQuickAccessSection
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }
                    
                    // MARK: - Profile Card (Tappable)
                    NavigationLink(destination: ProfileView()) {
                        ProfileHeaderView()
                    }
                    .buttonStyle(ProfileCardButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.top, subscriptionManager.isDeveloperMode ? 0 : 4)
                    
                    // MARK: - Settings Sections
                        // MARK: - Account & Sign In (Prominent location for cloud sync)
                        SettingsSection(title: "ACCOUNT") {
                            AccountSignInSection()
                        }
                        // MARK: - Subscription (prominent position for discoverability)
                        SettingsSection(title: "SUBSCRIPTION") {
                            NavigationLink(destination: SubscriptionPricingView()) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(
                                                subscriptionManager.effectiveTier == .free
                                                    ? BrandColors.goldBase.opacity(0.12)
                                                    : Color.green.opacity(0.15)
                                            )
                                            .frame(width: 30, height: 30)
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(
                                                subscriptionManager.effectiveTier == .free
                                                    ? BrandColors.goldBase
                                                    : .green
                                            )
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(subscriptionButtonTitle)
                                            .font(.body)
                                            .foregroundColor(DS.Adaptive.textPrimary)
                                        Text(subscriptionSubtitle)
                                            .font(.caption)
                                            .foregroundColor(DS.Adaptive.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                }
                                .padding(.vertical, 4)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(subscriptionButtonTitle), \(subscriptionSubtitle)")
                                .accessibilityAddTraits(.isButton)
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }

                        // MARK: - AI Agent
                        SettingsSection(title: "AI AGENT") {
                            NavigationLink(destination: AgentSettingsView()) {
                                SettingsRow(icon: "brain.head.profile", title: "AI Agent")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })

                            if AgentConnectionService.shared.isConnected {
                                SettingsDivider()
                                NavigationLink(destination: AgentPortfolioView()) {
                                    SettingsRow(icon: "chart.pie", title: "Agent Portfolio")
                                }
                                .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })

                                SettingsDivider()
                                NavigationLink(destination: AgentSignalFeedView()) {
                                    SettingsRow(icon: "waveform.path.ecg", title: "Agent Signals")
                                }
                                .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                            }
                        }

                        // MARK: - Paper Trading (prominent — visible to all users including free)
                        PaperTradingSettingsSection(
                            selectionFeedback: selectionFeedback,
                            impactLight: impactLight
                        )
                        
                        // MARK: - Trading Mode Quick Switch
                        TradingModeSettingsSection(
                            selectionFeedback: selectionFeedback,
                            impactLight: impactLight
                        )
                        
                        // MARK: - Appearance
                        SettingsSection(title: "APPEARANCE") {
                            SettingsToggleRow(
                                icon: isDarkMode ? "moon.fill" : "sun.max.fill",
                                title: isDarkMode ? "Dark Mode" : "Light Mode",
                                isOn: $isDarkMode
                            )
                            .onChange(of: isDarkMode) { _, newValue in
                                selectionFeedback.selectionChanged()
                                withAnimation(nil) {
                                    appAppearanceRaw = newValue ? "dark" : "light"
                                }
                            }
                            SettingsDivider()
                            SettingsToggleRow(icon: "eye.slash", title: "Privacy Mode", isOn: $hideBalances)
                                .onChange(of: hideBalances) { _, _ in selectionFeedback.selectionChanged() }
                        }
                        
                        // MARK: - Connections (simplified — DeFi & Brokerages accessible from Exchanges page)
                        SettingsSection(title: "CONNECTIONS") {
                            NavigationLink(destination: ExchangeWalletRouterView()) {
                                SettingsRow(icon: "wallet.pass", title: "Exchanges & Wallets")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                            // API Keys (DeFi) - Only show for developers
                            if SubscriptionManager.shared.isDeveloperMode {
                                SettingsDivider()
                                NavigationLink(destination: APIConfigurationView()) {
                                    SettingsRow(icon: "key.fill", title: "API Keys")
                                }
                                .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                            }
                            SettingsDivider()
                            NavigationLink(destination: CSVImportView().environmentObject(portfolioViewModel)) {
                                SettingsRow(icon: "doc.text.fill", title: "Import from CSV")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                            SettingsDivider()
                            NavigationLink(destination: ConnectionHealthView()) {
                                SettingsRow(icon: "link", title: "Connections")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - Portfolio (Demo Mode)
                        SettingsSection(title: "PORTFOLIO") {
                            // Demo Mode restrictions:
                            // 1. Locked when Paper Trading is active
                            // 2. Hidden when user has connected accounts (they have real data)
                            let isPaperTradingActive = PaperTradingManager.shared.isPaperTradingEnabled
                            let hasConnectedAccounts = !ConnectedAccountsManager.shared.accounts.isEmpty
                            let canShowDemoToggle = !hasConnectedAccounts
                            
                            if canShowDemoToggle {
                                SettingsToggleRow(
                                    icon: AppTradingMode.demo.icon,
                                    title: "Demo Mode",
                                    isOn: Binding(
                                        get: { DemoModeManager.shared.isDemoMode },
                                        set: { newVal in
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
                                    Text("Shows sample portfolio data for new users exploring the app")
                                        .font(.caption)
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        
                        // MARK: - Notifications
                        SettingsSection(title: "NOTIFICATIONS") {
                            // Push notification status
                            HStack {
                                Image(systemName: "bell.badge.fill")
                                    .foregroundColor(PushNotificationManager.shared.isPushEnabled ? .green : DS.Adaptive.textTertiary)
                                    .frame(width: 24)
                                Text("Push Notifications")
                                    .font(.subheadline)
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                Spacer()
                                if PushNotificationManager.shared.isPushEnabled {
                                    Text("Enabled")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Button("Enable") {
                                        Task {
                                            await PushNotificationManager.shared.registerForPushNotifications()
                                        }
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(BrandColors.goldBase)
                                }
                            }
                            .padding(.vertical, 4)

                            NavigationLink(destination: NotificationsView()) {
                                SettingsRow(icon: "bell", title: "Price Alerts")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })

                            let aiMonitor = AIPortfolioMonitor.shared
                            let hasPro = SubscriptionManager.shared.hasAccess(to: .aiPoweredAlerts)

                            VStack(alignment: .leading, spacing: 4) {
                                SettingsToggleRow(
                                    icon: "sparkles",
                                    title: "AI Market Alerts",
                                    isOn: Binding(
                                        get: { aiMonitor.isEnabled },
                                        set: { newVal in
                                            guard hasPro else { return }
                                            selectionFeedback.selectionChanged()
                                            aiMonitor.isEnabled = newVal
                                        }
                                    ),
                                    iconColor: Color(red: 0.58, green: 0.35, blue: 0.98)
                                )
                                .disabled(!hasPro)
                                .opacity(hasPro ? 1.0 : 0.5)

                                Text(hasPro
                                    ? "AI monitors macro market shifts plus your portfolio/watchlist relevance and sends smart notifications."
                                    : "Upgrade to Pro to enable AI market and portfolio notifications.")
                                    .font(.caption)
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                    .padding(.top, 4)
                            }
                        }
                        
                        // MARK: - Home Screen Customization
                        SettingsSection(title: "HOME SCREEN") {
                            NavigationLink(destination: HomeCustomizationView()) {
                                SettingsRow(icon: "square.grid.2x2", title: "Customize Sections")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - Security
                        SettingsSection(title: "SECURITY") {
                            NavigationLink(destination: SecuritySettingsView()) {
                                SettingsRow(icon: "lock.shield", title: "Security & Login")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - Preferences (Language & Currency)
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
                        
                        // MARK: - API Credentials (Developer Only)
                        // This entire section is hidden for regular users since all items are developer features
                        if subscriptionManager.isDeveloperMode {
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
                                    SettingsRow(icon: "cpu", title: "CryptoSage AI Settings")
                                }
                                .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                            }
                        }
                        
                        // MARK: - Privacy & Analytics
                        SettingsSection(title: "PRIVACY & ANALYTICS") {
                            SettingsToggleRow(
                                icon: "chart.bar.xaxis",
                                title: "Share Analytics",
                                isOn: $analyticsEnabled
                            )
                            .onChange(of: analyticsEnabled) { _, newValue in
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
                        
                        // MARK: - Tax Reporting
                        SettingsSection(title: "TAX & REPORTS") {
                            NavigationLink(destination: TaxSettingsView().environmentObject(portfolioViewModel)) {
                                SettingsRow(icon: "doc.text.fill", title: "Tax Settings")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                            SettingsDivider()
                            NavigationLink(destination: TaxReportView()) {
                                SettingsRow(icon: "chart.bar.doc.horizontal", title: "Generate Tax Report")
                            }
                            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                        }
                        
                        // MARK: - Live Trading Bots (3Commas) - Developer Only
                        if subscriptionManager.isDeveloperMode {
                            LiveTradingBotsSettingsSection(
                                selectionFeedback: selectionFeedback,
                                impactLight: impactLight
                            )
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
                        
                    // Sign Out moved to Profile page — Profile is the canonical account hub
                    
                    // MARK: - App Info Footer
                    appInfoFooter
                        .padding(.top, 20)
                        .padding(.bottom, 30)
                }
            }
            // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
            .withUIKitScrollBridge()
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .onAppear {
            impactLight.prepare()
            impactMedium.prepare()
            selectionFeedback.prepare()
            
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
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [URL(string: "https://apps.apple.com/app/cryptosage-ai")!])
        }
        .alert("Clear Cache", isPresented: $showClearCacheAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) { clearCache() }
        } message: {
            Text("This will clear cached images and data. Your portfolio and settings will not be affected.")
        }
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
    
    // MARK: - Custom Header
    private var settingsHeader: some View {
        HStack {
            CSNavButton(
                icon: "chevron.left",
                action: { dismiss() }
            )
            
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
        VStack(spacing: 6) {
            // App logo
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            Text("CryptoSage AI")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Version \(appVersion) (\(buildNumber))")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
        }
    }
    
    // MARK: - Helpers
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    // Sign Out moved to ProfileView — Profile is the canonical account hub
    
    private func requestAppReview() {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            AppStore.requestReview(in: scene)
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
        
        // Clear AI prediction cache (fixes 0% prediction bug from stale data)
        AIPricePredictionService.shared.clearCache()
        
        // Recalculate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            calculateCacheSize()
        }
    }
}

// MARK: - Profile Card Button Style
// NOTE: SettingsSection, SettingsDivider, SettingsRow, SettingsToggleRow, ProfileHeaderView moved to SettingsComponents.swift
// NOTE: SecuritySettingsView, SecurityStatusRow, AccountSignInSection moved to SecuritySettingsView.swift
// NOTE: ProfileView and related components moved to ProfileView.swift

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
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 0) {
            CSPageHeader(title: "About", leadingAction: { dismiss() })
            
            ScrollView {
                VStack(spacing: 20) {
                    // App Logo
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.top, 30)
                    
                    VStack(spacing: 4) {
                        Text("CryptoSage AI")
                            .font(.title2.weight(.bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        // Version text with secret developer tap gesture
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textTertiary)
                            #if DEBUG
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
                            #endif
                    }
                    
                    Text("Your all-in-one crypto portfolio tracker. Monitor holdings across exchanges, get AI-powered insights, and stay ahead of the market.")
                        .font(.body)
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    
                    // MARK: - Social Proof Section
                    socialProofSection
                    
                    // Developer mode indicator (only shown when active)
                    if subscriptionManager.isDeveloperMode {
                        developerModeIndicator
                    }
                    
                    Spacer()
                }
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
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
    
    // MARK: - Social Proof Section
    private var socialProofSection: some View {
        VStack(spacing: 20) {
            // App Stats Card
            VStack(spacing: 14) {
                Text("WHY CRYPTOSAGE")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .tracking(1.2)
                
                // Stats Grid
                HStack(spacing: 0) {
                    aboutStat(value: "15+", label: "Exchanges", icon: "link.circle.fill", color: .blue)
                    
                    Rectangle()
                        .fill(DS.Adaptive.stroke)
                        .frame(width: 0.5, height: 40)
                    
                    aboutStat(value: "10K+", label: "Coins", icon: "bitcoinsign.circle.fill", color: BrandColors.goldBase)
                    
                    Rectangle()
                        .fill(DS.Adaptive.stroke)
                        .frame(width: 0.5, height: 40)
                    
                    aboutStat(value: "AI", label: "Insights", icon: "sparkles", color: .purple)
                    
                    Rectangle()
                        .fill(DS.Adaptive.stroke)
                        .frame(width: 0.5, height: 40)
                    
                    aboutStat(value: "24/7", label: "Data", icon: "clock.fill", color: .green)
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
            .padding(.horizontal, 20)
            
            // Feature Highlights
            VStack(alignment: .leading, spacing: 14) {
                aboutFeature(icon: "lock.shield.fill", text: "API keys encrypted in Apple Keychain", color: .green)
                aboutFeature(icon: "iphone.and.arrow.forward", text: "Local-first — your data stays on your device", color: .blue)
                aboutFeature(icon: "chart.line.uptrend.xyaxis", text: "Real-time prices, charts, and heatmaps", color: BrandColors.goldBase)
                aboutFeature(icon: "brain", text: "AI-powered predictions and market analysis", color: .purple)
                aboutFeature(icon: "doc.text.fill", text: "Paper Trading with $100K virtual funds", color: .cyan)
            }
            .padding(.horizontal, 24)
            
            // Rate & Share Buttons
            VStack(spacing: 10) {
                Button {
                    requestAppReview()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Rate CryptoSage")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(isDark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: isDark
                                ? [BrandColors.goldBase, BrandColors.goldLight]
                                : [BrandColors.goldBase, BrandColors.goldDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 20)
                
                Button {
                    impactLight.impactOccurred()
                    let url = URL(string: "https://apps.apple.com/app/cryptosage-ai")!
                    let activityVC = UIActivityViewController(
                        activityItems: ["Check out CryptoSage AI — the smartest crypto portfolio tracker!", url],
                        applicationActivities: nil
                    )
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        rootVC.present(activityVC, animated: true)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Share with Friends")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.Adaptive.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                    )
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 4)
            
            // Copyright & Links
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("Made with")
                        .font(.caption)
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text("for crypto enthusiasts")
                        .font(.caption)
                }
                .foregroundColor(DS.Adaptive.textTertiary)
                
                Text("© 2026 CryptoSage AI. All rights reserved.")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .padding(.top, 20)
    }
    
    private func aboutStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
            
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func aboutFeature(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Spacer()
        }
    }
    
    private func requestAppReview() {
        impactLight.impactOccurred()
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            AppStore.requestReview(in: scene)
        }
    }
    
    private var developerModeIndicator: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 14))
                Text("Developer Mode Active")
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(.orange)
            
            // Show live trading status
            HStack(spacing: 6) {
                Image(systemName: subscriptionManager.developerLiveTradingEnabled 
                    ? "exclamationmark.triangle.fill" 
                    : "lock.shield.fill")
                    .font(.system(size: 10))
                Text(subscriptionManager.developerLiveTradingEnabled 
                    ? "Live Trading ON" 
                    : "Live Trading OFF (Safe)")
                    .font(.caption2.weight(.medium))
            }
            .foregroundColor(subscriptionManager.developerLiveTradingEnabled ? .red : .green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(subscriptionManager.developerLiveTradingEnabled 
                            ? Color.red.opacity(0.5) 
                            : Color.orange.opacity(0.3), lineWidth: 1)
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
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isCodeFieldFocused: Bool
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        NavigationStack {
            ScrollView {
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
                        // Already in developer mode - show status and tier simulator
                        VStack(spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Developer mode is active")
                                    .foregroundColor(DS.Adaptive.textPrimary)
                            }
                            .font(.subheadline.weight(.medium))
                            
                            // Tier Simulator Section
                            VStack(spacing: 12) {
                                Text("Simulate Subscription Tier")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                
                                // Tier Picker (all tiers including Platinum)
                                Picker("Tier", selection: $subscriptionManager.developerSimulatedTier) {
                                    Text("Free").tag(SubscriptionTierType.free)
                                    Text("Pro").tag(SubscriptionTierType.pro)
                                    Text("Premium").tag(SubscriptionTierType.premium)
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal, 24)
                                
                                // Current simulated tier info
                                tierInfoCard
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(DS.Adaptive.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                    )
                            )
                            .padding(.horizontal, 24)
                            
                            Text("Test how features behave for each subscription tier without actually subscribing.")
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            
                            // MARK: - Live Trading Toggle (Developer Only)
                            liveTradingToggleSection
                            
                            // MARK: - Developer Tools Section
                            developerToolsSection
                            
                            // MARK: - App Info Section
                            appInfoSection
                            
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
                            let isDark = colorScheme == .dark
                            Text("Activate")
                                .font(.headline)
                                .foregroundColor(BrandColors.ctaTextColor(isDark: isDark))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    AdaptiveGradients.goldButton(isDark: isDark)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AdaptiveGradients.ctaRimStroke(isDark: isDark), lineWidth: 0.8)
                                )
                                .cornerRadius(14)
                        }
                        .padding(.horizontal, 24)
                        .disabled(code.isEmpty)
                        .opacity(code.isEmpty ? 0.6 : 1)
                    }
                }
                
                Spacer(minLength: 40)
                }
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
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Tier Info Card
    private var tierInfoCard: some View {
        let tier = subscriptionManager.developerSimulatedTier
        
        return VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Simulating: \(tier.displayName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(tierColor(for: tier))
                    
                    Text("AI Prompts: \(tier.aiPromptsDisplay)")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: tierIcon(for: tier))
                    .font(.title2)
                    .foregroundColor(tierColor(for: tier))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(tierColor(for: tier).opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tierColor(for: tier).opacity(0.3), lineWidth: 1)
                    )
            )
            
            // Feature access summary
            HStack(spacing: 16) {
                featureIndicator(
                    icon: "arrow.left.arrow.right.circle.fill",
                    label: "Trade",
                    isEnabled: subscriptionManager.hasAccess(to: .tradeExecution)
                )
                featureIndicator(
                    icon: "cpu.fill",
                    label: "Bots",
                    isEnabled: subscriptionManager.hasAccess(to: .tradingBots)
                )
                featureIndicator(
                    icon: "chart.line.uptrend.xyaxis",
                    label: "Derivatives",
                    isEnabled: subscriptionManager.hasAccess(to: .derivativesFeatures)
                )
                featureIndicator(
                    icon: "megaphone.fill",
                    label: "Ads",
                    isEnabled: !subscriptionManager.shouldShowAds,
                    invertLabel: true
                )
            }
        }
    }
    
    private func featureIndicator(icon: String, label: String, isEnabled: Bool, invertLabel: Bool = false) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isEnabled ? .green : .red.opacity(0.6))
            Text(label)
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textSecondary)
            Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2)
                .foregroundColor(isEnabled ? .green : .red.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func tierColor(for tier: SubscriptionTierType) -> Color {
        switch tier {
        case .free: return .gray
        case .pro: return BrandColors.goldBase
        case .premium: return .purple
        }
    }
    
    private func tierIcon(for tier: SubscriptionTierType) -> String {
        switch tier {
        case .free: return "person.circle.fill"
        case .pro: return "bolt.circle.fill"
        case .premium: return "crown.fill"
        }
    }
    
    // MARK: - Live Trading Toggle Section
    private var liveTradingToggleSection: some View {
        VStack(spacing: 12) {
            // Section Header with Warning
            HStack(spacing: 8) {
                Image(systemName: subscriptionManager.developerLiveTradingEnabled ? "exclamationmark.triangle.fill" : "lock.shield.fill")
                    .foregroundColor(subscriptionManager.developerLiveTradingEnabled ? .red : .green)
                Text(subscriptionManager.developerLiveTradingEnabled ? "LIVE TRADING ENABLED" : "Live Trading Disabled")
                    .font(.caption.weight(.bold))
                    .foregroundColor(subscriptionManager.developerLiveTradingEnabled ? .red : .green)
            }
            
            // Toggle Row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Live Trading")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text(subscriptionManager.developerLiveTradingEnabled 
                        ? "Real trades will execute with real money!"
                        : "Safe mode - all trades are paper/simulated")
                        .font(.caption)
                        .foregroundColor(subscriptionManager.developerLiveTradingEnabled ? .red : DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $subscriptionManager.developerLiveTradingEnabled)
                    .labelsHidden()
                    .tint(.red)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(subscriptionManager.developerLiveTradingEnabled 
                        ? Color.red.opacity(0.1) 
                        : Color.green.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(subscriptionManager.developerLiveTradingEnabled 
                                ? Color.red.opacity(0.5) 
                                : Color.green.opacity(0.3), lineWidth: 1)
                    )
            )
            
            // Safety Info
            if subscriptionManager.developerLiveTradingEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text("3Commas bots, AI trades, and all trading features will use REAL MONEY")
                        .font(.caption2)
                }
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                
                Divider().padding(.vertical, 8)
                
                // Exchange Selector for Algo Trading
                algoTradingExchangeSelector
                
            } else {
                Text("You can safely test all tiers and features without executing real trades.")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(subscriptionManager.developerLiveTradingEnabled 
                            ? Color.red.opacity(0.5) 
                            : DS.Adaptive.stroke, lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
    
    /// Exchange selector for algo/Sage trading when live trading is enabled
    @ViewBuilder
    private var algoTradingExchangeSelector: some View {
        let connectedExchanges = TradingCredentialsManager.shared.getConnectedExchanges()
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Algo Trading Exchange")
                .font(.caption.weight(.medium))
                .foregroundColor(DS.Adaptive.textSecondary)
            
            if connectedExchanges.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("No exchanges connected. Add API keys in Settings.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else {
                HStack {
                    Text("Execute trades on:")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Spacer()
                    
                    Menu {
                        ForEach(connectedExchanges, id: \.self) { exchange in
                            Button {
                                SageTradingService.shared.defaultExchange = exchange
                                // Update quote currency based on exchange
                                if exchange == .coinbase {
                                    SageTradingService.shared.quoteCurrency = "USD"
                                } else {
                                    SageTradingService.shared.quoteCurrency = "USDT"
                                }
                            } label: {
                                HStack {
                                    Text(exchange.displayName)
                                    if SageTradingService.shared.defaultExchange == exchange {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(SageTradingService.shared.defaultExchange.displayName)
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.8))
                        )
                    }
                }
                
                Text("Sage algorithms will execute real trades on \(SageTradingService.shared.defaultExchange.displayName)")
                    .font(.caption2)
                    .foregroundColor(.red.opacity(0.8))
            }
        }
    }
    
    // MARK: - Developer Tools Section
    @State private var showClearCacheConfirm = false
    @State private var showResetPaperTradingConfirm = false
    
    private var developerToolsSection: some View {
        VStack(spacing: 12) {
            // Section Header
            HStack {
                Image(systemName: "hammer.fill")
                    .foregroundColor(.blue)
                Text("Developer Tools")
                    .font(.caption.weight(.bold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                Spacer()
            }
            
            // Paper Trading Reset
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset Paper Trading")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text("Balance: \(PaperTradingManager.shared.calculatePortfolioValue(prices: PaperTradingManager.shared.buildCurrentPrices()), specifier: "$%.2f")")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                Spacer()
                Button {
                    impactLight.impactOccurred()
                    showResetPaperTradingConfirm = true
                } label: {
                    Text("Reset")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DS.Adaptive.cardBackground)
            )
            
            // Clear All Caches
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clear All Caches")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text("AI predictions, market data, images")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                Spacer()
                Button {
                    impactLight.impactOccurred()
                    showClearCacheConfirm = true
                } label: {
                    Text("Clear")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.blue))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DS.Adaptive.cardBackground)
            )
            
            // Connected Exchanges Status
            let connectedCount = TradingCredentialsManager.shared.getConnectedExchanges().count
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected Exchanges")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text(connectedCount == 0 ? "None connected" : "\(connectedCount) exchange\(connectedCount == 1 ? "" : "s") ready")
                        .font(.caption)
                        .foregroundColor(connectedCount > 0 ? .green : DS.Adaptive.textSecondary)
                }
                Spacer()
                Image(systemName: connectedCount > 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(connectedCount > 0 ? .green : .red.opacity(0.6))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DS.Adaptive.cardBackground)
            )
            
            // Firebase Connection Status
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Firebase Status")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text("Cloud functions active")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DS.Adaptive.cardBackground)
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .alert("Reset Paper Trading?", isPresented: $showResetPaperTradingConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                PaperTradingManager.shared.resetPaperTrading()
            }
        } message: {
            Text("This will reset your paper trading balance to $100,000 and clear all trade history.")
        }
        .alert("Clear All Caches?", isPresented: $showClearCacheConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearAllDeveloperCaches()
            }
        } message: {
            Text("This will clear all cached data including AI predictions, market data, and images. The app may be slower temporarily while data reloads.")
        }
    }
    
    private func clearAllDeveloperCaches() {
        // Clear URL cache
        URLCache.shared.removeAllCachedResponses()
        
        // Clear AI caches
        AIPricePredictionService.shared.clearCache()
        AIInsightService.shared.clearCache()
        
        // Clear market caches
        MarketCacheManager.shared.clearCache()
        
        // Clear Coinbase cache
        Task { await CoinbaseService.shared.clearCache() }
        
        // Haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    // MARK: - App Info Section
    private var appInfoSection: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        
        return VStack(spacing: 8) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(DS.Adaptive.textTertiary)
                Text("App Info")
                    .font(.caption.weight(.bold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                Spacer()
            }
            
            HStack {
                Text("Version")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                Spacer()
                Text("\(version) (\(build))")
                    .font(.caption.weight(.medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            HStack {
                Text("Developer Code")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                Spacer()
                Text("CSDEV2026")
                    .font(.caption.weight(.medium).monospaced())
                    .foregroundColor(.orange)
            }
            
            HStack {
                Text("Live Trading")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                Spacer()
                Text(subscriptionManager.developerLiveTradingEnabled ? "ENABLED" : "Disabled")
                    .font(.caption.weight(.bold))
                    .foregroundColor(subscriptionManager.developerLiveTradingEnabled ? .red : .green)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    @State private var expandedFAQ: String? = nil
    @State private var searchText: String = ""
    @State private var showingFeedback: Bool = false
    @State private var feedbackText: String = ""
    @State private var feedbackType: FeedbackType = .suggestion
    @State private var showFeedbackSuccess: Bool = false
    @State private var scrollToFAQ: Bool = false
    @FocusState private var searchFocused: Bool
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    enum FeedbackType: String, CaseIterable {
        case bug = "Bug Report"
        case suggestion = "Suggestion"
        case question = "Question"
        case other = "Other"
        
        var icon: String {
            switch self {
            case .bug: return "ladybug.fill"
            case .suggestion: return "lightbulb.fill"
            case .question: return "questionmark.circle.fill"
            case .other: return "ellipsis.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .bug: return .red
            case .suggestion: return .yellow
            case .question: return .blue
            case .other: return .purple
            }
        }
    }
    
    // Comprehensive FAQ Data with categories - covers all app features
    private let faqItems: [(id: String, category: String, question: String, answer: String)] = [
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Getting Started
        // ═══════════════════════════════════════════════════════════════
        (
            id: "app-overview",
            category: "Getting Started",
            question: "What is CryptoSage AI?",
            answer: "CryptoSage AI is your all-in-one cryptocurrency companion that combines:\n\n📊 Portfolio Tracking\nConnect exchanges or manually track your holdings across all your accounts in one place.\n\n🤖 AI-Powered Insights\nChat with an AI that understands crypto markets, your portfolio, and can answer any question.\n\n📈 Real-Time Market Data\nLive prices, charts, heatmaps, and news for 10,000+ cryptocurrencies.\n\n💹 Paper Trading\nPractice trading strategies with $100K in virtual funds. Test your skills risk-free before trading with real money.\n\n🐋 Smart Money Tracking\nFollow whale wallets and get alerts when big players move.\n\nWhether you're a beginner checking Bitcoin prices or an advanced trader testing strategies with Paper Trading, CryptoSage has the tools you need."
        ),
        (
            id: "getting-started",
            category: "Getting Started",
            question: "How do I get started?",
            answer: "Welcome to CryptoSage! Here's your quickstart guide:\n\n1️⃣ Explore the Market Tab\nBrowse 10,000+ cryptocurrencies, view charts, and read news.\n\n2️⃣ Build Your Watchlist\nTap the star icon on any coin to add it to your Home screen watchlist.\n\n3️⃣ Track Your Portfolio\nGo to Portfolio tab > tap + to add holdings manually, or connect an exchange for automatic sync.\n\n4️⃣ Try the AI Chat\nTap the AI Chat tab and ask anything: \"What is Bitcoin?\", \"Analyze my portfolio\", or \"What's the market sentiment today?\"\n\n5️⃣ Set Price Alerts\nOn any coin detail page, tap the bell icon to get notified when prices move.\n\n💡 Pro tip: The app works great even without connecting exchanges - start by exploring, then connect accounts when you're ready!"
        ),
        (
            id: "tabs-explained",
            category: "Getting Started",
            question: "What do the different tabs do?",
            answer: "CryptoSage has 5 main tabs:\n\n🏠 Home\nYour personalized dashboard with:\n• Watchlist of favorite coins\n• Market heatmaps showing top movers\n• Fear & Greed sentiment index\n• Trending coins\n• Crypto news feed\n• AI insights and predictions\n• Whale activity alerts\n\n📈 Market\nExplore all cryptocurrencies:\n• Browse 10,000+ coins\n• Filter by price, volume, market cap\n• View detailed charts & technicals\n• Read coin-specific news\n• Check order books\n\n💹 Trading\nPractice and manage trades:\n• Paper Trading with $100K virtual funds\n• Place market, limit, and stop orders\n• View open orders and trade history\n• Automated trading bots (Premium)\n\n💼 Portfolio\nTrack your holdings:\n• Total value & daily change\n• Asset allocation chart\n• Performance history\n• Individual position details\n• Profit/loss tracking\n\n🤖 AI Chat\nYour crypto AI assistant:\n• Ask any question\n• Get market analysis\n• Portfolio recommendations\n• Learn crypto concepts"
        ),
        (
            id: "exchanges",
            category: "Getting Started",
            question: "How do I connect my exchanges?",
            answer: "Connect your exchange accounts for automatic portfolio syncing:\n\n📍 Where to Connect\nSettings > Linked Accounts > Add Connection\n\n🔐 Connection Methods\n\n• OAuth (Coinbase, Kraken, Gemini)\nOne-tap secure authorization. No API keys needed.\n\n• API Keys (Binance, KuCoin, Bybit, OKX, Gate.io, and more)\n1. Log into your exchange\n2. Go to API Management\n3. Create a new API key\n4. Enable \"Read\" permissions\n5. Copy the API key and secret\n6. Paste into CryptoSage\n\n• Wallet Addresses\nPaste any public blockchain address (Ethereum, Bitcoin, Solana, and more) to track its holdings.\n\n🛡️ Security Tips\n• Use read-only API keys when possible\n• Never enable withdrawal permissions\n• Your keys are encrypted in Apple's Keychain\n• We never store credentials on our servers\n\nSupported: Coinbase, Binance, Kraken, KuCoin, Bybit, Gemini, OKX, Gate.io, Crypto.com, Bitstamp, MEXC, and more!"
        ),
        (
            id: "watchlist",
            category: "Getting Started",
            question: "How do I create and manage my watchlist?",
            answer: "Your watchlist appears on the Home tab for quick access:\n\n⭐ Adding Coins\n• In Market tab, tap the star icon on any coin\n• In search results, tap the star\n• On a coin detail page, tap \"Add to Watchlist\"\n\n📝 Managing Your Watchlist\n• Swipe left on a coin to remove it\n• Tap \"Edit\" to reorder by dragging\n• Long-press to see quick actions\n\n🔄 Watchlist Sync\nYour watchlist syncs automatically across sessions. It's stored locally on your device for privacy.\n\n💡 Tips\n• Add coins you're researching or considering buying\n• The watchlist shows live prices, 24h change, and sparklines\n• Tap any coin to see full details, charts, and news"
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Market & Charts
        // ═══════════════════════════════════════════════════════════════
        (
            id: "market-data",
            category: "Market & Charts",
            question: "Where does market data come from?",
            answer: "CryptoSage aggregates data from multiple premium sources:\n\n📊 Price Data\n• CoinGecko - Global average prices for 10,000+ coins\n• Binance - Real-time prices and order books\n• Connected Exchanges - Your specific exchange prices\n\n📰 News\n• Major crypto news outlets\n• RSS feeds from 20+ sources\n• Real-time updates\n\n📈 Market Stats\n• Global market cap and volume\n• Bitcoin dominance\n• DeFi total value locked\n• Fear & Greed Index\n\n⏱️ Update Frequency\n• Prices: Every 10-30 seconds\n• Charts: Real-time with WebSocket\n• News: Every 5 minutes\n• Market stats: Every minute\n\nPrices may vary slightly between sources due to exchange differences - this is normal and creates arbitrage opportunities."
        ),
        (
            id: "charts",
            category: "Market & Charts",
            question: "How do I use the price charts?",
            answer: "CryptoSage offers powerful interactive charts:\n\n📅 Timeframes\nTap the timeframe pills to switch: 1H, 24H, 7D, 1M, 3M, 1Y, ALL\n\n🎨 Chart Types\n• Line - Clean price trend\n• Candlestick - OHLC data for traders\n• Area - Filled chart for visual impact\n\n📐 Technical Indicators\nTap the indicators button to add:\n• Moving Averages (SMA, EMA)\n• RSI (Relative Strength Index)\n• MACD\n• Bollinger Bands\n• Volume\n• And many more...\n\n👆 Interactions\n• Drag to scroll through time\n• Pinch to zoom in/out\n• Tap and hold for crosshair with exact values\n• Double-tap to reset view\n\n💡 Pro Tip: Tap \"TradingView\" button for advanced charting with 100+ indicators and drawing tools."
        ),
        (
            id: "technicals",
            category: "Market & Charts",
            question: "What do the technical indicators mean?",
            answer: "Technical indicators help analyze price trends:\n\n📊 Trend Indicators\n\n• Moving Averages (MA)\nSmooths price data to show trend direction. When price is above MA = bullish, below = bearish.\n\n• MACD\nShows momentum. When MACD line crosses above signal line = bullish signal.\n\n📈 Momentum Indicators\n\n• RSI (0-100)\nMeasures overbought/oversold conditions.\n> 70 = Overbought (may drop)\n< 30 = Oversold (may rise)\n\n• Stochastic\nSimilar to RSI, compares closing price to price range.\n\n📉 Volatility Indicators\n\n• Bollinger Bands\nShows volatility. Price touching upper band = potentially overbought. Price touching lower = potentially oversold.\n\n• ATR (Average True Range)\nMeasures volatility level, useful for setting stop losses.\n\n⚠️ Important: Indicators are tools for analysis, not guarantees. Always combine multiple indicators and do your own research."
        ),
        (
            id: "heatmap",
            category: "Market & Charts",
            question: "How do I read the market heatmap?",
            answer: "The heatmap gives you a visual overview of market performance:\n\n🟢 Green = Price Up\n• Light green: 0-3% gain\n• Medium green: 3-7% gain\n• Dark green: 7%+ gain\n\n🔴 Red = Price Down\n• Light red: 0-3% loss\n• Medium red: 3-7% loss\n• Dark red: 7%+ loss\n\n📦 Box Size\nLarger boxes = Higher market cap. Bitcoin and Ethereum are usually the biggest boxes.\n\n⚙️ Customization\nTap the settings icon to change:\n• Timeframe (1H, 24H, 7D)\n• Sort by (Market Cap, Volume, Change)\n• Number of coins shown\n• Color intensity\n\n💡 Using the Heatmap\n• Quickly spot market trends (all green = bull market)\n• Find outliers (one red in sea of green = potential issue)\n• Identify sector trends (all DeFi coins moving together)"
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Portfolio
        // ═══════════════════════════════════════════════════════════════
        (
            id: "portfolio-tracking",
            category: "Portfolio",
            question: "How do I track my portfolio?",
            answer: "Track all your crypto in one place:\n\n🔄 Automatic Sync\nConnect your exchanges (Settings > Linked Accounts) and your holdings sync automatically every few minutes.\n\n✏️ Manual Entry\n1. Go to Portfolio tab\n2. Tap the + button\n3. Search for the coin\n4. Enter amount and purchase price\n5. Optionally add the date\n\n📊 What You'll See\n• Total portfolio value\n• 24h change in $ and %\n• Allocation pie chart\n• Individual holdings with P&L\n• Performance over time\n\n🔀 Multiple Accounts\nCryptoSage combines all connected exchanges and manual entries into one unified view. You can also view accounts separately in the filter menu.\n\n📈 Performance Tracking\nSee your portfolio's historical performance with the chart at the top. Switch timeframes to see daily, weekly, or all-time gains."
        ),
        (
            id: "portfolio-value",
            category: "Portfolio",
            question: "Why does my portfolio value differ from my exchange?",
            answer: "Small differences are normal:\n\n💱 Price Source\nCryptoSage uses global average prices by default. Your exchange may have slightly different prices.\n\n💵 Currency Conversion\nIf your exchange shows value in EUR but CryptoSage is set to USD, conversion rates may vary.\n\n⏱️ Timing\nThere's a small delay (seconds to minutes) between exchange updates and app sync.\n\n🔧 How to Match\n1. Go to Settings > Price Settings\n2. Enable \"Show Exchange Prices\"\n3. Select your preferred exchange\n\n📝 Note: For tax and accounting purposes, always use your exchange's official records. CryptoSage is for tracking and analysis."
        ),
        (
            id: "add-holdings",
            category: "Portfolio",
            question: "How do I add or edit holdings?",
            answer: "Managing your portfolio is easy:\n\n➕ Adding Holdings\n1. Portfolio tab > tap +\n2. Search for the cryptocurrency\n3. Enter the amount you own\n4. Add purchase price (optional but recommended for P&L tracking)\n5. Add purchase date (optional)\n6. Tap Save\n\n✏️ Editing Holdings\n1. Tap on any holding\n2. Tap Edit in the detail view\n3. Update amount, price, or date\n4. Tap Save\n\n🗑️ Removing Holdings\n• Swipe left on any holding to delete\n• Or tap the holding > Edit > Delete\n\n📥 Importing Transactions\nFor connected exchanges, transactions import automatically. For CSV import, go to Settings > Import Data.\n\n💡 Tip: Adding accurate purchase prices lets CryptoSage calculate your true profit/loss and cost basis for taxes."
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - AI Features
        // ═══════════════════════════════════════════════════════════════
        (
            id: "ai-chat",
            category: "AI Features",
            question: "How does AI Chat work?",
            answer: "CryptoSage AI is your personal crypto expert:\n\n🧠 What It Can Do\n• Answer any crypto question\n• Explain concepts (\"What is DeFi?\")\n• Analyze specific coins (\"Tell me about Solana\")\n• Review your portfolio (\"How diversified am I?\")\n• Summarize news (\"What's happening with Bitcoin today?\")\n• Explain technicals (\"What does the RSI indicate for ETH?\")\n\n🔌 Real-Time Data Access\nThe AI has access to:\n• Live market prices\n• Your portfolio (if connected)\n• Recent crypto news\n• Technical indicators\n• Market sentiment data\n\n💬 Tips for Better Responses\n• Be specific: \"Analyze BTC/USD 4H chart\" vs \"Tell me about Bitcoin\"\n• Ask follow-ups: \"Why?\" or \"Explain more\"\n• Request formats: \"Give me a bullet point summary\"\n\n⚡ Powered by advanced AI models optimized for speed and accuracy based on your subscription tier."
        ),
        (
            id: "ai-prompts",
            category: "AI Features",
            question: "What are some good AI prompts to try?",
            answer: "Here are powerful prompts to get started:\n\n📊 Market Analysis\n• \"What's the current crypto market sentiment?\"\n• \"Which coins are trending today and why?\"\n• \"Summarize today's most important crypto news\"\n• \"Compare Bitcoin and Ethereum performance this month\"\n\n💼 Portfolio Help\n• \"Analyze my portfolio allocation\"\n• \"How can I reduce risk in my portfolio?\"\n• \"Which of my holdings has the best momentum?\"\n• \"Should I rebalance? What would you suggest?\"\n\n📚 Learning\n• \"Explain yield farming like I'm a beginner\"\n• \"What are the risks of DeFi?\"\n• \"How do crypto taxes work?\"\n• \"What is a rug pull and how do I avoid them?\"\n\n📈 Technical Analysis\n• \"What does Bitcoin's RSI indicate right now?\"\n• \"Is ETH in an uptrend or downtrend?\"\n• \"Explain the current BTC support and resistance levels\"\n\n🐋 Advanced\n• \"Are whales buying or selling Bitcoin?\"\n• \"What smart money is doing with Solana?\"\n• \"Find coins with bullish divergence\""
        ),
        (
            id: "ai-settings",
            category: "AI Features",
            question: "How does CryptoSage AI work?",
            answer: "CryptoSage AI is our proprietary AI system built for crypto analysis:\n\n🧠 How It Works\nCryptoSage AI is built on top of the most advanced AI models available, fine-tuned with crypto-specific context including live market data, technical indicators, sentiment analysis, and on-chain data. No setup required — it works automatically based on your subscription tier.\n\n⚡ AI Tiers\n• Free: Basic CryptoSage AI with limited daily usage\n• Pro: Full CryptoSage AI with generous daily limits\n• Premium: The most powerful CryptoSage AI with unlimited chat and the highest quality responses\n\n🔮 Predictions\nCryptoSage AI predictions analyze 10+ real-time data sources including technical indicators, whale movements, derivatives data, and market sentiment to generate price forecasts.\n\n💡 Everything is automatic — just use the app and CryptoSage AI handles the rest. Premium subscribers get the most capable AI model for deeper, more nuanced analysis."
        ),
        (
            id: "ai-predictions",
            category: "AI Features",
            question: "How do AI price predictions work?",
            answer: "AI Predictions analyze patterns to forecast prices (Pro feature):\n\n🔮 How It Works\n1. AI analyzes historical price patterns\n2. Considers technical indicators\n3. Factors in market sentiment\n4. Reviews recent news impact\n5. Generates short-term predictions\n\n📊 What You See\n• Predicted price range\n• Confidence level (Low/Medium/High)\n• Key factors influencing the prediction\n• Historical accuracy for that coin\n\n⚠️ Important Disclaimers\n• Predictions are for entertainment/educational purposes\n• Crypto markets are highly unpredictable\n• Past performance doesn't guarantee future results\n• NEVER invest based solely on AI predictions\n• Always do your own research (DYOR)\n\n📈 Track Accuracy\nView prediction history and accuracy rates in Settings > AI Predictions to see how well predictions have performed."
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Trading
        // ═══════════════════════════════════════════════════════════════
        (
            id: "trading-basics",
            category: "Trading",
            question: "How do I trade through CryptoSage?",
            answer: "CryptoSage offers Paper Trading to practice strategies with virtual funds:\n\n📍 Getting Started\n1. Go to Trading tab\n2. Paper Trading mode is enabled automatically\n3. Select a trading pair (e.g., BTC/USD)\n4. Choose Buy or Sell\n\n💰 Paper Trading\nYou start with $100,000 in virtual funds to practice with. All trades are simulated using real market prices - no real money is at risk.\n\n📋 Order Types\n\n• Market Order\nExecutes immediately at current price.\n\n• Limit Order\nSets your desired price. Only executes when market reaches that price.\n\n• Stop-Loss\nAutomatically sells if price drops to your set level.\n\n• Take-Profit\nAutomatically sells when price rises to your target.\n\n✅ Execution Flow\n1. Enter amount and price\n2. Review order details\n3. Confirm the trade\n4. Trade executes with virtual funds\n5. Track your paper trading P&L\n\n💡 Paper Trading is perfect for learning without risk!"
        ),
        (
            id: "paper-trading",
            category: "Trading",
            question: "What is paper trading?",
            answer: "Paper trading lets you practice with virtual money:\n\n🎮 How It Works\n• Start with $100,000 virtual balance\n• Execute trades using real market prices\n• Track your virtual portfolio performance\n• No real money at risk\n\n📍 Getting Started\n1. Go to the Trading tab\n2. Paper Trading is enabled automatically\n3. You'll see a paper trading indicator\n4. Place orders as normal\n5. They execute against real prices but with virtual funds\n\n💡 Why Use Paper Trading\n• Learn how trading works risk-free\n• Test strategies before committing real funds\n• Practice with different order types\n• Build confidence and skill\n• Track your performance over time\n\n📊 Tracking Performance\nView your paper trading history and P&L in Settings > Paper Trading.\n\n🏆 Benefits\nPaper Trading is the perfect way to learn cryptocurrency trading without risking real money. Test your strategies, learn from mistakes, and build confidence!"
        ),
        (
            id: "trading-bots",
            category: "Trading",
            question: "How do trading bots work?",
            answer: "Automated trading bots execute strategies for you (Premium feature):\n\n🤖 Bot Types\n\n• DCA Bot (Dollar Cost Average)\nAutomatically buys fixed amounts at regular intervals. Great for long-term accumulation.\n\n• Grid Bot\nPlaces buy/sell orders at set intervals. Profits from price swings in ranging markets.\n\n• Signal Bot\nExecutes trades based on technical indicator signals.\n\n📍 Setting Up a Bot\n1. Trading tab > Bots\n2. Tap \"Create Bot\"\n3. Choose bot type\n4. Configure settings (amount, frequency, coin)\n5. Set risk limits (stop-loss, max investment)\n6. Review and activate\n\n📊 Monitoring\n• View active bots and their performance\n• See each trade the bot made\n• Pause or stop anytime\n• Adjust settings as needed\n\n⚠️ Note\nTrading bots currently operate in Paper Trading mode with virtual funds. Practice strategies risk-free before going live."
        ),
        (
            id: "supported-exchanges",
            category: "Trading",
            question: "Which exchanges can I trade on?",
            answer: "CryptoSage supports 15+ exchanges and wallets:\n\n🔗 Quick Connect (OAuth)\n\n• Coinbase\nOne-tap authorization, easy setup.\n\n• Kraken\nOAuth connection, known for security.\n\n• Gemini\nOAuth connection, regulated and reliable.\n\n🔑 API Key Connection\n\n• Binance / Binance US\nLargest selection of trading pairs.\n\n• KuCoin\nMany altcoins available.\n\n• Bybit\nSpot and derivatives data.\n\n• OKX, Gate.io, MEXC, Crypto.com\nAnd more — all via read-only API keys.\n\n• Bitstamp, Bitget, Bitfinex, HTX\nFull portfolio sync support.\n\n📱 Wallet Tracking\nPaste any public address to track:\n• Ethereum, Bitcoin, Solana, Polygon\n• Arbitrum, Base, Avalanche, BNB Chain\n• MetaMask, Trust Wallet, Ledger Live\n\n💡 Request an Exchange\nUse Send Feedback to request support for your exchange. We prioritize based on demand."
        ),
        (
            id: "trading-safe",
            category: "Trading",
            question: "Is trading through CryptoSage safe?",
            answer: "Absolutely! CryptoSage is designed with safety in mind:\n\n🎮 Paper Trading = Zero Risk\nAll trading in CryptoSage uses virtual funds by default. No real money is ever at risk — you practice with $100K in simulated balance using live market prices.\n\n🔐 API Key Security\n• Your keys are encrypted using Apple's Secure Keychain, the same technology protecting your passwords and Face ID data.\n• We recommend using read-only API keys for portfolio tracking.\n• We NEVER request withdrawal permissions.\n\n🛡️ Your Data is Protected\n• Portfolio data stays on your device\n• All connections use TLS encryption\n• No account required to use the app\n• Delete your data anytime\n\n💡 Safety Tips\n• Use read-only API keys whenever possible\n• Never share your API keys with anyone\n• Keep your device passcode and biometrics enabled\n• Enable Face ID / Touch ID in CryptoSage settings"
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Advanced Features
        // ═══════════════════════════════════════════════════════════════
        (
            id: "whale-tracking",
            category: "Advanced Features",
            question: "What is whale tracking?",
            answer: "Track large crypto holders (\"whales\") to spot market-moving activity (Pro feature):\n\n🐋 What Are Whales?\nWallets holding significant amounts of crypto. Their trades can move markets.\n\n📊 What You'll See\n• Large transactions (1000+ BTC, 10000+ ETH, etc.)\n• Whale wallet balances and changes\n• Accumulation vs distribution patterns\n• Smart money movements\n\n🔔 Whale Alerts\nGet notified when:\n• Large transfers between wallets\n• Big deposits to exchanges (potential sell)\n• Big withdrawals from exchanges (potential hold)\n• Known whale wallets make moves\n\n📍 How to Use\n1. Home tab > Whale Activity section\n2. Or: Market tab > select coin > Whale tab\n3. Enable alerts in Settings > Notifications\n\n💡 Interpretation\n• Whales moving TO exchange = May sell = bearish\n• Whales moving FROM exchange = Holding = bullish\n• Accumulation by smart money = Follow the smart money"
        ),
        (
            id: "price-alerts",
            category: "Advanced Features",
            question: "How do I set price alerts?",
            answer: "Get notified when prices hit your targets:\n\n📍 Creating an Alert\n1. Go to any coin's detail page\n2. Tap the bell icon 🔔\n3. Set your target price\n4. Choose alert type:\n   • Price Above (bullish target)\n   • Price Below (stop-loss level)\n   • Percent Change (±X%)\n5. Tap Create Alert\n\n⚙️ Managing Alerts\nSettings > Notifications > Price Alerts\n• View all active alerts\n• Edit or delete alerts\n• See triggered alert history\n\n🔔 Notification Options\n• Push notification (instant)\n• Sound alert\n• Badge on app icon\n\n💡 Tips\n• Set alerts for key support/resistance levels\n• Use percent change for volatility alerts\n• Create both upside targets and downside protection\n• Don't set too many - alert fatigue is real!\n\n⚠️ Alerts require Background App Refresh to be enabled in iOS Settings."
        ),
        (
            id: "tax-reports",
            category: "Advanced Features",
            question: "How do tax reports work?",
            answer: "Generate tax reports for your crypto activity (Pro feature):\n\n📊 What's Included\n• Capital gains and losses\n• Cost basis calculations\n• Holding periods (short vs long term)\n• Transaction history\n• Multiple accounting methods (FIFO, LIFO, HIFO)\n\n📍 Generating a Report\n1. Settings > Tax Reports\n2. Select tax year\n3. Choose accounting method\n4. Select exchanges/wallets to include\n5. Generate report\n6. Export as PDF or CSV\n\n🌍 Supported Regions\n• United States (IRS Form 8949 format)\n• United Kingdom\n• Canada\n• Australia\n• EU countries\n• Generic format for other regions\n\n⚠️ Important Disclaimers\n• Reports are for informational purposes\n• Consult a tax professional for advice\n• Verify all data with exchange records\n• CryptoSage is not a tax advisor\n\n💡 Tip: Connect all your exchanges for accurate reporting. Missing transactions affect accuracy."
        ),
        (
            id: "defi-nft",
            category: "Advanced Features",
            question: "Can I track DeFi and NFTs?",
            answer: "Yes! Track your DeFi positions and NFT collection:\n\n🏦 DeFi Dashboard\n• View liquidity pool positions\n• Track yield farming returns\n• Monitor staking rewards\n• See lending/borrowing positions\n• Supported protocols: Uniswap, Aave, Compound, Curve, and more\n\n📍 How to Access\n1. Connect your wallet address (Settings > Linked Accounts)\n2. Portfolio tab > DeFi section\n\n🖼️ NFT Gallery\n• View your NFT collection\n• See floor prices and estimated value\n• Track NFT market trends\n• Supported: Ethereum, Polygon, Solana NFTs\n\n📍 Accessing NFTs\nPortfolio tab > NFTs section (requires wallet connection)\n\n💡 Requirements\n• Must connect wallet address (not exchange)\n• Supports EVM chains (Ethereum, Polygon, Arbitrum, etc.)\n• Solana wallet support included\n• Some DeFi protocols may have delayed data"
        ),
        (
            id: "hardware-wallets",
            category: "Advanced Features",
            question: "Can I connect hardware wallets?",
            answer: "Yes! Connect Ledger and Trezor for secure tracking:\n\n🔐 Supported Hardware Wallets\n• Ledger Nano S / S Plus / X\n• Trezor Model One / T / Safe 3\n\n📍 How to Connect\n1. Settings > Linked Accounts\n2. Tap \"Hardware Wallet\"\n3. Select Ledger or Trezor\n4. Follow the connection guide\n5. Approve on your device\n\n📊 What You Can Do\n• View all addresses on your hardware wallet\n• Track balances across chains\n• See transaction history\n• Include in portfolio totals\n\n⚠️ What You CAN'T Do\n• Sign transactions (security feature)\n• Move funds through CryptoSage\n• Access private keys\n\n🔒 Security Note\nCryptoSage only reads public addresses from your hardware wallet. Your private keys never leave the device. This is read-only portfolio tracking, not a wallet app."
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Subscriptions
        // ═══════════════════════════════════════════════════════════════
        (
            id: "subscriptions",
            category: "Subscriptions",
            question: "What's included in each plan?",
            answer: "Choose the plan that fits your needs:\n\n🆓 FREE\n• Portfolio tracking (unlimited holdings)\n• Market data for 10,000+ coins\n• Interactive charts with basic indicators\n• Watchlist (up to 20 coins)\n• AI Chat & Insights (limited daily usage)\n• News feed\n• Price alerts (up to 3)\n\n⭐ PRO - $9.99/month\nEverything in Free, plus:\n• Smart AI Assistant with portfolio analysis\n• AI Price Forecasts for all coins\n• AI Market Analysis & Insights\n• AI Risk Reports\n• Paper Trading ($100K virtual)\n• Whale activity tracking\n• Unlimited watchlist\n• Unlimited price alerts\n• Tax reports (up to 2,500 transactions)\n• Ad-free experience\n\n👑 PREMIUM - $19.99/month\nEverything in Pro, plus:\n• Unlimited AI Chat with most powerful model\n• Advanced AI Predictions\n• Paper Trading Bots (DCA, Grid, Signal)\n• Paper Derivatives (futures & perpetuals)\n• Custom Strategy Builder\n• Strategy & Bot Marketplace\n• Arbitrage Scanner\n• Unlimited tax transactions\n• DeFi Yield Insights\n• Early access to new features"
        ),
        (
            id: "free-trial",
            category: "Subscriptions",
            question: "Is there a free trial?",
            answer: "Yes! Try Pro or Premium with a free trial:\n\n🎁 How to Start\n1. Tap \"Upgrade\" anywhere in the app\n2. Select Pro or Premium plan\n3. If a free trial is available, you'll see \"Start Free Trial\"\n4. Confirm with your Apple ID\n\n📅 Trial Details\n• Full access to all features during the trial\n• No charge until the trial period ends\n• Cancel anytime before the trial ends — you won't be charged\n• Converts to a paid subscription if not cancelled\n\n⏰ Before Trial Ends\nYou can check your trial status and cancel anytime in iOS Settings > Subscriptions.\n\n💡 Tips\n• Try all premium features during your trial\n• Test paper trading strategies\n• Explore AI predictions and whale tracking\n• See if the features are worth it for you\n\nStandard Apple subscription — cancel easily anytime. No tricks."
        ),
        (
            id: "cancel-subscription",
            category: "Subscriptions",
            question: "How do I cancel my subscription?",
            answer: "Subscriptions are managed through Apple:\n\n📍 How to Cancel\n1. Open iOS Settings app\n2. Tap your name at the top\n3. Tap \"Subscriptions\"\n4. Find \"CryptoSage AI\"\n5. Tap \"Cancel Subscription\"\n6. Confirm cancellation\n\n📅 What Happens Next\n• You keep access until the end of your billing period\n• After that, you'll revert to the free plan\n• Your data and portfolio remain intact\n• You can resubscribe anytime\n\n🔄 Resubscribing\nJust tap \"Upgrade\" in the app and select a plan. Your previous settings will be restored.\n\n💡 Pausing Instead\nApple doesn't offer pause, but you can cancel and resubscribe later. Your data is always saved.\n\n❓ Issues?\nIf you have billing issues, contact Apple Support directly as they handle all subscription payments."
        ),
        (
            id: "restore-purchase",
            category: "Subscriptions",
            question: "How do I restore my purchase?",
            answer: "If your subscription isn't showing:\n\n🔄 Restore Steps\n1. Go to Settings in CryptoSage\n2. Tap \"Subscription\"\n3. Tap \"Restore Purchases\"\n4. Sign in with your Apple ID if prompted\n5. Wait for confirmation\n\n❓ Still Not Working?\n\n• Same Apple ID?\nMake sure you're using the same Apple ID that made the purchase.\n\n• Family Sharing?\nCryptoSage subscriptions don't transfer via Family Sharing.\n\n• Different Device?\nYour subscription works on any device with the same Apple ID.\n\n• Subscription Active?\nCheck iOS Settings > Subscriptions to verify it's still active.\n\n📧 Need Help?\nIf restore doesn't work, contact us at hypersageai@gmail.com with:\n• Your Apple ID email\n• Screenshot of your Apple subscription\n• Device info\n\nWe'll help sort it out!"
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Security & Privacy
        // ═══════════════════════════════════════════════════════════════
        (
            id: "security",
            category: "Security & Privacy",
            question: "How secure is CryptoSage?",
            answer: "Security is our top priority:\n\n🔐 Data Encryption\n• API keys: Encrypted in Apple's Secure Keychain\n• Network: All connections use TLS 1.3\n• Local data: Encrypted on device\n\n🛡️ Access Protection\n• Face ID / Touch ID support\n• PIN code option\n• Auto-lock timeout\n• Screen blur in app switcher\n\n🏗️ Architecture\n• Local-first: Most data stays on your device\n• No account required: Use without signing up\n• Minimal cloud: Only for optional sync features\n\n🔒 API Key Safety\n• We NEVER request withdrawal permissions\n• Keys stored in same system as Apple Pay\n• You can use read-only keys\n• Delete keys anytime\n\n🚫 What We DON'T Do\n• Store your private keys\n• Have access to move your funds\n• Sell your data\n• Track you across apps\n\n✅ Regular security audits and updates to protect you."
        ),
        (
            id: "data-collection",
            category: "Security & Privacy",
            question: "What data does CryptoSage collect?",
            answer: "We believe in minimal data collection:\n\n✅ Collected (Anonymous & Aggregated)\n\n• Crash Reports\nAnonymous crash data helps us fix bugs quickly. Processed by Sentry.\n\n• Usage Analytics\nFeature usage patterns (not personal data) help us improve. Processed by TelemetryDeck.\n\n• Device Info\nDevice type and iOS version for compatibility testing.\n\n❌ NOT Collected\n\n• Personal Information\nNo name, email, phone, or address.\n\n• Financial Data\nYour portfolio values never leave your device.\n\n• Trading History\nYour trades stay between you and your exchange.\n\n• Location\nWe don't access GPS or location services.\n\n• Contacts/Photos\nNo access to other personal data.\n\n🔒 Third-Party Services\n• TelemetryDeck: Privacy-focused analytics\n• Sentry: Crash reporting\n• OpenAI: Processes AI chat (your prompts only)\n\nAll services chosen for their privacy-first approach."
        ),
        (
            id: "biometric",
            category: "Security & Privacy",
            question: "How do I enable Face ID / Touch ID?",
            answer: "Add biometric security to protect your app:\n\n📍 Enable Biometrics\n1. Go to Settings\n2. Tap \"Security\"\n3. Toggle on \"Face ID\" or \"Touch ID\"\n4. Authenticate to confirm\n\n🔒 What It Protects\n• App launch (require auth to open)\n• Viewing sensitive data (balances)\n• Executing trades\n• Accessing API key settings\n\n⚙️ Additional Options\n• Auto-lock timeout (1min, 5min, 15min)\n• Require auth for trades only\n• Blur screenshots (screen protection)\n\n💡 Tips\n• Enable for extra peace of mind\n• Great if others use your phone\n• Doesn't affect performance\n• Falls back to device passcode if biometrics fail\n\n📱 Requirements\n• Device with Face ID or Touch ID\n• Biometrics enabled in iOS Settings\n• Passcode set on device"
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Troubleshooting
        // ═══════════════════════════════════════════════════════════════
        (
            id: "sync-issues",
            category: "Troubleshooting",
            question: "Why isn't my portfolio syncing?",
            answer: "If your portfolio isn't updating:\n\n🔍 Quick Checks\n1. Internet connection working?\n2. Pull down to force refresh\n3. Check last sync time in Portfolio header\n\n🔑 API Key Issues\n1. Go to Settings > Linked Accounts\n2. Check connection status (green = good)\n3. If red/yellow, tap to see error\n4. Try \"Test Connection\"\n5. Re-enter API keys if expired\n\n🔄 Exchange-Specific\n\n• Coinbase OAuth\nTry disconnecting and reconnecting. OAuth tokens can expire.\n\n• Binance\nCheck if API key has IP restrictions that block mobile.\n\n• Others\nVerify API key hasn't been revoked on exchange.\n\n🧹 Nuclear Options\n1. Settings > Data Management > Clear Cache\n2. Delete and re-add the connection\n3. Uninstall/reinstall app (data backed up to Keychain)\n\n📧 Still Stuck?\nContact hypersageai@gmail.com with:\n• Exchange name\n• Error message (screenshot)\n• Device and iOS version"
        ),
        (
            id: "price-diff",
            category: "Troubleshooting",
            question: "Why are prices different from my exchange?",
            answer: "Price differences are normal and expected:\n\n🌍 Why Prices Differ\n\n• Different Markets\nEach exchange is a separate market with its own supply/demand.\n\n• Global Average\nCryptoSage shows weighted average across exchanges by default.\n\n• Timing\nPrices update every few seconds, small delays can cause differences.\n\n• Currency Conversion\nExchange rates for fiat conversion may vary.\n\n🔧 How to Match Your Exchange\n1. Go to Settings > Price Settings\n2. Enable \"Show Exchange Prices\"\n3. Select your preferred exchange\n4. Now prices will match that exchange\n\n💡 Understanding the Difference\n• 0.1-0.5% difference: Normal\n• 0.5-2% difference: Market volatility or low liquidity\n• 2%+ difference: Potential arbitrage opportunity!\n\n📊 For Accuracy\nFor tax/accounting purposes, always use your exchange's official records and statements."
        ),
        (
            id: "notifications-not-working",
            category: "Troubleshooting",
            question: "Why aren't my notifications working?",
            answer: "Check these settings to fix notifications:\n\n📱 iOS Settings\n1. Settings > CryptoSage\n2. Tap \"Notifications\"\n3. Enable \"Allow Notifications\"\n4. Enable: Sounds, Badges, Banners\n5. Set to \"Immediate Delivery\"\n\n🔋 Background Refresh\n1. Settings > General > Background App Refresh\n2. Enable for CryptoSage\n3. Make sure it's not in Low Power Mode\n\n🌙 Focus/DND\n1. Check if Do Not Disturb is on\n2. Check Focus mode settings\n3. Add CryptoSage to allowed apps\n\n📍 In-App Settings\n1. CryptoSage > Settings > Notifications\n2. Verify alert toggles are on\n3. Check specific alert settings\n\n⚠️ Common Issues\n• Battery optimization killing background refresh\n• Alert price already passed\n• App not opened recently (iOS may deprioritize)\n\n🔄 Reset\nTry toggling notifications off and on, both in iOS and in-app."
        ),
        (
            id: "app-slow",
            category: "Troubleshooting",
            question: "Why is the app running slowly?",
            answer: "Here's how to speed things up:\n\n🧹 Clear Cache\n1. Settings > Data Management\n2. Tap \"Clear Cache\"\n3. Restart the app\n\n📊 Reduce Data Load\n• Limit watchlist to essential coins\n• Disable unused home screen sections\n• Use shorter chart timeframes\n\n📱 Device Health\n• Free up storage space (iOS needs room)\n• Close other apps\n• Restart your device\n• Check for iOS updates\n\n🌐 Network\n• Switch between WiFi and cellular\n• Check internet speed\n• Disable VPN temporarily\n\n⚙️ App Settings\n• Disable real-time updates if not needed\n• Reduce refresh frequency\n• Disable animations (Accessibility)\n\n💡 Note\nSome slowness during market volatility is normal - everyone's refreshing data at once!\n\n📧 Persistent Issues?\nContact support with device model and iOS version."
        ),
        (
            id: "data-reset",
            category: "Troubleshooting",
            question: "How do I reset my data or start fresh?",
            answer: "Options for resetting:\n\n🗑️ Clear Cache Only\nKeeps your accounts and settings, removes temporary data:\n1. Settings > Data Management\n2. Tap \"Clear Cache\"\n\n📊 Reset Specific Data\n• Watchlist: Edit > Remove All\n• Alerts: Settings > Notifications > Delete All\n• Manual holdings: Portfolio > Edit > Remove\n\n🔗 Disconnect Accounts\nSettings > Linked Accounts > Tap account > Remove\n\n🔄 Full Reset\nTo completely start fresh:\n1. Delete the CryptoSage app\n2. Go to iOS Settings > General > iPhone Storage\n3. Find CryptoSage > Delete App (removes all data)\n4. Reinstall from App Store\n\n⚠️ What's Preserved\n• Subscription status (tied to Apple ID)\n• API keys in Keychain (can be cleared in iOS Settings > Passwords)\n\n💡 Before Reset\nExport any data you want to keep (transaction history, etc.)"
        ),
        
        // ═══════════════════════════════════════════════════════════════
        // MARK: - Account & Support
        // ═══════════════════════════════════════════════════════════════
        (
            id: "no-account",
            category: "Account & Support",
            question: "Do I need to create an account?",
            answer: "No account required!\n\n🔓 Use Without Account\nCryptoSage works fully without creating an account:\n• Track portfolio\n• View market data\n• Use AI chat\n• Connect exchanges\n• Everything stored locally\n\n✨ Benefits of No Account\n• Maximum privacy\n• No email required\n• No password to remember\n• Your data stays on your device\n\n📱 Switching Devices\nWithout an account, data doesn't automatically transfer. To move:\n1. Export your data (Settings > Export)\n2. Set up new device\n3. Import data\n\n🔮 Future: Optional Account\nWe may add optional accounts for:\n• Cross-device sync\n• Cloud backup\n• Social features\n\nThis will always be optional. Privacy-first users can continue without accounts."
        ),
        (
            id: "contact-support",
            category: "Account & Support",
            question: "How do I contact support?",
            answer: "We're here to help!\n\n📧 Email Support\nhypersageai@gmail.com\n• Response within 24-48 hours\n• Best for detailed issues\n• Include screenshots if helpful\n\n🐦 Twitter / X\n@CryptoSageAI\n• Quick questions\n• Updates and announcements\n• Community discussions\n\n💬 Discord Community\n• Real-time help from community\n• Feature discussions\n• Early access announcements\n\n📱 In-App Feedback\nHelp & Support > Send Feedback\n• Bug reports\n• Feature requests\n• General suggestions\n• Automatically includes device info\n\n💡 For Faster Help, Include:\n• Device model and iOS version\n• App version (shown at bottom of Help)\n• Screenshots of the issue\n• Steps to reproduce the problem\n\nWe respond to all users within 24-48 hours!"
        ),
        (
            id: "feature-request",
            category: "Account & Support",
            question: "How do I request a feature?",
            answer: "We love hearing your ideas!\n\n📱 In-App Feedback (Preferred)\n1. Help & Support > Send Feedback\n2. Select \"Suggestion\"\n3. Describe your idea\n4. Tap Send\n\n💬 Discord\nJoin our Discord and post in #feature-requests\n• Community can vote on ideas\n• Discuss with other users\n• Get updates on implementation\n\n📧 Email\nhypersageai@gmail.com\nSubject: \"Feature Request: [Your Idea]\"\n\n🐦 Twitter\nTweet @CryptoSageAI or DM us\n\n✅ What Makes a Great Request\n• Specific use case: \"I want X because Y\"\n• How it would help you\n• Any examples from other apps\n\n📊 How We Prioritize\n1. Impact: How many users benefit?\n2. Alignment: Fits our vision?\n3. Feasibility: Can we build it well?\n4. Votes: Community demand\n\nWe can't implement everything, but we read every suggestion!"
        )
    ]
    
    // Filtered FAQs based on search
    private var filteredFAQs: [(id: String, category: String, question: String, answer: String)] {
        if searchText.isEmpty {
            return faqItems
        }
        return faqItems.filter { item in
            item.question.localizedCaseInsensitiveContains(searchText) ||
            item.answer.localizedCaseInsensitiveContains(searchText) ||
            item.category.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // Group FAQs by category
    private var groupedFAQs: [(category: String, items: [(id: String, category: String, question: String, answer: String)])] {
        let grouped = Dictionary(grouping: filteredFAQs) { $0.category }
        let categoryOrder = [
            "Getting Started",
            "Market & Charts",
            "Portfolio",
            "AI Features",
            "Trading",
            "Advanced Features",
            "Subscriptions",
            "Security & Privacy",
            "Troubleshooting",
            "Account & Support"
        ]
        return categoryOrder.compactMap { category in
            if let items = grouped[category], !items.isEmpty {
                return (category: category, items: items)
            }
            return nil
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            helpHeader
            
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Hero Section
                        heroSection
                            .padding(.top, 8)
                        
                        // Search Bar
                        searchBar
                        
                        // Quick Actions
                        quickActionsSection
                        
                        // Contact Section
                        contactSection
                        
                        // FAQ Section
                        faqSection
                            .id("faqSection")
                        
                        // Resources Section
                        resourcesSection
                        
                        // App Info
                        appInfoSection
                            .padding(.bottom, 32)
                    }
                    .padding(.horizontal, 20)
                }
                .onChange(of: scrollToFAQ) { _, shouldScroll in
                    if shouldScroll {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("faqSection", anchor: .top)
                        }
                        scrollToFAQ = false
                    }
                }
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .sheet(isPresented: $showingFeedback) {
            feedbackSheet
        }
        .alert("Feedback Sent", isPresented: $showFeedbackSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thank you for your feedback! We read every message and will use it to improve CryptoSage.")
        }
    }
    
    // MARK: - Header
    
    private var helpHeader: some View {
        CSPageHeader(title: "Help & Support", leadingAction: {
            dismiss()
        })
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: isDark
                                ? [BrandColors.goldBase.opacity(0.3), BrandColors.goldBase.opacity(0)]
                                : [BrandColors.goldBase.opacity(0.15), BrandColors.goldBase.opacity(0)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [BrandColors.goldBase.opacity(0.2), BrandColors.goldDark.opacity(0.1)]
                                : [BrandColors.goldBase.opacity(0.12), BrandColors.goldBase.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                    .overlay(
                        Circle()
                            .stroke(
                                isDark ? BrandColors.goldBase.opacity(0.4) : BrandColors.goldBase.opacity(0.25),
                                lineWidth: isDark ? 2 : 1.5
                            )
                    )
                
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isDark
                                ? [BrandColors.goldBase, BrandColors.goldLight]
                                : [BrandColors.goldBase, BrandColors.goldDark],
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
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DS.Adaptive.textSecondary)
            
            TextField("Search help articles...", text: $searchText)
                .font(.body)
                .foregroundColor(DS.Adaptive.textPrimary)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .submitLabel(.search)
            
            if !searchText.isEmpty {
                Button(action: {
                    impactLight.impactOccurred()
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
        }
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture {
            searchFocused = true
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(searchFocused ? BrandColors.goldBase.opacity(0.5) : DS.Adaptive.stroke, lineWidth: searchFocused ? 1.5 : 0.5)
        )
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            QuickActionCard(
                icon: "envelope.badge.fill",
                title: "Send Feedback",
                color: BrandColors.goldBase
            ) {
                impactMedium.impactOccurred()
                showingFeedback = true
            }
            
            QuickActionCard(
                icon: "doc.text.fill",
                title: "FAQ",
                color: .blue
            ) {
                impactLight.impactOccurred()
                // Scroll to FAQ section
                scrollToFAQ = true
            }
            
            QuickActionCard(
                icon: "video.fill",
                title: "Tutorials",
                color: .purple
            ) {
                impactLight.impactOccurred()
                if let url = URL(string: "https://youtube.com/@cryptosageai") {
                    UIApplication.shared.open(url)
                }
            }
        }
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
                    subtitle: "hypersageai@gmail.com",
                    responseTime: "Usually responds within 24 hours",
                    color: .blue
                ) {
                    impactLight.impactOccurred()
                    if let url = URL(string: "mailto:hypersageai@gmail.com?subject=CryptoSage%20Support%20Request") {
                        UIApplication.shared.open(url)
                    }
                }
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                
                ContactCard(
                    icon: "at",
                    title: "Twitter / X",
                    subtitle: "@CryptoSageAI",
                    responseTime: "Quick updates & announcements",
                    color: Color(red: 0.11, green: 0.63, blue: 0.95)
                ) {
                    impactLight.impactOccurred()
                    if let url = URL(string: "https://twitter.com/cryptosageai") {
                        UIApplication.shared.open(url)
                    }
                }
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                
                ContactCard(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Discord Community",
                    subtitle: "Join our community",
                    responseTime: "Active community & live support",
                    color: Color(red: 0.34, green: 0.39, blue: 0.95)
                ) {
                    impactLight.impactOccurred()
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
            HStack {
                Text("FREQUENTLY ASKED QUESTIONS")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Spacer()
                
                if !searchText.isEmpty {
                    Text("\(filteredFAQs.count) results")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            .padding(.leading, 4)
            
            if filteredFAQs.isEmpty {
                // No results
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text("No results found")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Text("Try different keywords or contact support")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                )
            } else {
                // Grouped FAQs
                ForEach(groupedFAQs, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        // Category Header
                        HStack(spacing: 8) {
                            Image(systemName: categoryIcon(for: group.category))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(categoryColor(for: group.category))
                            
                            Text(group.category)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                        .padding(.leading, 4)
                        .padding(.top, group.category == groupedFAQs.first?.category ? 0 : 8)
                        
                        // FAQ Items
                        VStack(spacing: 0) {
                            ForEach(group.items, id: \.id) { item in
                                FAQRow(
                                    question: item.question,
                                    answer: item.answer,
                                    isExpanded: expandedFAQ == item.id,
                                    searchQuery: searchText,
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
                                
                                if item.id != group.items.last?.id {
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
            }
        }
    }
    
    private func categoryIcon(for category: String) -> String {
        switch category {
        case "Getting Started": return "sparkles"
        case "Market & Charts": return "chart.xyaxis.line"
        case "Portfolio": return "chart.pie.fill"
        case "AI Features": return "brain"
        case "Trading": return "arrow.left.arrow.right.circle.fill"
        case "Advanced Features": return "star.circle.fill"
        case "Subscriptions": return "crown.fill"
        case "Security & Privacy": return "lock.shield.fill"
        case "Troubleshooting": return "wrench.and.screwdriver.fill"
        case "Account & Support": return "person.crop.circle.fill"
        default: return "questionmark.circle"
        }
    }
    
    private func categoryColor(for category: String) -> Color {
        switch category {
        case "Getting Started": return .blue
        case "Market & Charts": return .cyan
        case "Portfolio": return .indigo
        case "AI Features": return .purple
        case "Trading": return .green
        case "Advanced Features": return .pink
        case "Subscriptions": return BrandColors.goldBase
        case "Security & Privacy": return .mint
        case "Troubleshooting": return .orange
        case "Account & Support": return .teal
        default: return DS.Adaptive.textSecondary
        }
    }
    
    // MARK: - Resources Section
    
    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LEGAL & RESOURCES")
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                NavigationLink(destination: PrivacyPolicyView()) {
                    ResourceRow(icon: "hand.raised.fill", title: "Privacy Policy", subtitle: "How we handle your data", color: .purple)
                }
                .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                
                NavigationLink(destination: TermsOfServiceView()) {
                    ResourceRow(icon: "doc.text.fill", title: "Terms of Service", subtitle: "Usage terms & conditions", color: .orange)
                }
                .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                
                // Trading Acknowledgments - only shown for developer mode (live trading)
                if SubscriptionManager.shared.isDeveloperMode {
                    Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                    
                    NavigationLink(destination: TradingAcknowledgmentStatusView()) {
                        ResourceRow(icon: "checkmark.shield.fill", title: "Trading Acknowledgments", subtitle: "Risk disclosures (Developer)", color: .green)
                    }
                    .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                }
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                
                ResourceRow(icon: "star.fill", title: "Rate CryptoSage", subtitle: "Help us grow with a review", color: .yellow) {
                    impactMedium.impactOccurred()
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        AppStore.requestReview(in: scene)
                    }
                }
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                
                ResourceRow(icon: "square.and.arrow.up.fill", title: "Share CryptoSage", subtitle: "Tell your friends", color: .blue) {
                    impactLight.impactOccurred()
                    let url = URL(string: "https://apps.apple.com/app/cryptosage-ai")!
                    let activityVC = UIActivityViewController(activityItems: ["Check out CryptoSage AI - the smartest crypto portfolio tracker!", url], applicationActivities: nil)
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        rootVC.present(activityVC, animated: true)
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
        VStack(spacing: 12) {
            // App Logo
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: isDark
                                ? [BrandColors.goldBase.opacity(0.2), BrandColors.goldBase.opacity(0)]
                                : [BrandColors.goldBase.opacity(0.1), BrandColors.goldBase.opacity(0)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            
            Text("CryptoSage AI")
                .font(.headline.weight(.bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
            
            HStack(spacing: 4) {
                Text("Made with")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                Text("for crypto enthusiasts")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            // Copyright
            Text("© 2026 CryptoSage AI. All rights reserved.")
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
    
    // MARK: - Feedback Sheet
    
    private var feedbackSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Feedback Type Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("What type of feedback?")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    HStack(spacing: 8) {
                        ForEach(FeedbackType.allCases, id: \.self) { type in
                            Button(action: {
                                impactLight.impactOccurred()
                                feedbackType = type
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: type.icon)
                                        .font(.system(size: 20))
                                        .foregroundColor(feedbackType == type ? type.color : DS.Adaptive.textSecondary)
                                    
                                    Text(type.rawValue)
                                        .font(.caption2)
                                        .foregroundColor(feedbackType == type ? type.color : DS.Adaptive.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(feedbackType == type ? type.color.opacity(0.15) : DS.Adaptive.cardBackgroundElevated)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(feedbackType == type ? type.color.opacity(0.5) : DS.Adaptive.stroke, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Feedback Text
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your feedback")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    TextEditor(text: $feedbackText)
                        .font(.body)
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 150)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DS.Adaptive.cardBackgroundElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                        )
                    
                    Text("\(feedbackText.count)/500 characters")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                // Device Info Note
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text("Device info will be included to help us debug issues")
                        .font(.caption)
                }
                .foregroundColor(DS.Adaptive.textTertiary)
                
                Spacer()
                
                // Send Button
                Button(action: sendFeedback) {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Send Feedback")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(isDark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: feedbackText.isEmpty 
                                ? [Color.gray.opacity(0.3), Color.gray.opacity(0.2)]
                                : isDark
                                    ? [BrandColors.goldBase, BrandColors.goldLight]
                                    : [BrandColors.goldBase, BrandColors.goldDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                }
                .disabled(feedbackText.isEmpty)
            }
            .padding(20)
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingFeedback = false
                    }
                    .foregroundColor(DS.Adaptive.gold)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    
    private func sendFeedback() {
        impactMedium.impactOccurred()
        
        // Compose email with feedback
        let deviceInfo = """
        
        ---
        Device: \(UIDevice.current.model)
        iOS: \(UIDevice.current.systemVersion)
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
        Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
        Feedback Type: \(feedbackType.rawValue)
        """
        
        let body = feedbackText + deviceInfo
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedSubject = "[\(feedbackType.rawValue)] CryptoSage Feedback".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        if let url = URL(string: "mailto:hypersageai@gmail.com?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url) { success in
                if success {
                    showingFeedback = false
                    feedbackText = ""
                    notificationFeedback.notificationOccurred(.success)
                    showFeedbackSuccess = true
                }
            }
        }
    }
}

// MARK: - Quick Action Card

private struct QuickActionCard: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Contact Card Component

private struct ContactCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var responseTime: String? = nil
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    if let responseTime = responseTime {
                        Text(responseTime)
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FAQ Row Component

private struct FAQRow: View {
    let question: String
    let answer: String
    let isExpanded: Bool
    var searchQuery: String = ""
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack {
                    Text(highlightedText(question, highlight: searchQuery))
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
    
    private func highlightedText(_ text: String, highlight: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        if !highlight.isEmpty, let range = attributedString.range(of: highlight, options: .caseInsensitive) {
            attributedString[range].foregroundColor = BrandColors.goldBase
            attributedString[range].font = .subheadline.weight(.bold)
        }
        
        return attributedString
    }
}

// MARK: - Resource Row Component

private struct ResourceRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
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
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(14)
    }
}

// MARK: - Privacy Policy View

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            CSPageHeader(title: "Privacy Policy", leadingAction: { dismiss() })
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Last Updated: February 10, 2026")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    PolicySection(title: "1. Information We Collect", content: """
                    Information you provide directly:
                    • Display name and preferences you configure
                    • Portfolio data from connected exchanges (via read-only API keys)
                    • Transaction history you choose to import (CSV or exchange sync)
                    • AI chat conversations (processed via encrypted API calls)
                    
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
                        
                        To submit a data access or deletion request, contact hypersageai@gmail.com.
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
                    Email: hypersageai@gmail.com
                    
                    For data access or deletion requests, include "Data Request" in your subject line.
                    """)
                }
                .padding(20)
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
}

// MARK: - Terms of Service View

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            CSPageHeader(title: "Terms of Service", leadingAction: { dismiss() })
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Last Updated: February 10, 2026")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    // Critical regulatory warning
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Important Regulatory Disclosure")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.red)
                        }
                        
                        Text("""
                        CryptoSage AI is a portfolio tracking and market research tool. It is NOT registered as an investment adviser, broker-dealer, or financial institution with the SEC or any regulatory authority. We do not provide personalized investment advice, execute real trades, or manage funds. No fiduciary relationship is created by your use of this app.
                        """)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
                    
                    PolicySection(title: "1. Acceptance of Terms", content: """
                    By using CryptoSage AI, you agree to these Terms of Service. If you do not agree, please do not use the app. You must be at least 18 years old to use this app.
                    """)
                    
                    PolicySection(title: "2. Service Description", content: """
                    CryptoSage AI is a cryptocurrency portfolio tracking and market research app. The app provides:
                    
                    • Cryptocurrency portfolio tracking across exchanges and wallets
                    • Real-time market data, charts, and heatmaps for 10,000+ coins
                    • AI-powered market insights, analysis, and chat
                    • AI-generated price predictions and sentiment analysis
                    • Paper Trading with virtual funds ($100K) for practice
                    • Automated Paper Trading bots (DCA, Grid, Signal)
                    • Exchange and wallet integrations for read-only portfolio syncing
                    • Price alerts and notifications
                    • News aggregation from 20+ sources
                    
                    CryptoSage does NOT facilitate real-money trading. Paper Trading uses simulated virtual funds only — no real money is at risk.
                    
                    IMPORTANT: All information, AI insights, and predictions are for educational and informational purposes only and do NOT constitute financial, investment, or trading advice.
                    """)
                    
                    PolicySection(title: "3. AI Disclaimer", content: """
                    AI features are NOT provided by licensed financial advisors. AI-generated predictions, analysis, and suggestions may be inaccurate or wrong. We make no warranties regarding accuracy.
                    
                    • AI can "hallucinate" or produce false information
                    • Predictions are probabilistic estimates, not guarantees
                    • Past performance does not predict future results
                    • Always verify information independently
                    """)
                    
                    PolicySection(title: "4. Paper Trading & Simulated Features", content: """
                    CryptoSage includes Paper Trading — a practice mode that uses virtual funds to simulate trades. No real money is involved.
                    
                    • Paper Trading uses $100,000 in virtual (simulated) funds
                    • All Paper Trading results are hypothetical and for educational purposes
                    • Past simulated performance does not predict future real-world results
                    • AI predictions and bot strategies are for learning and analysis only
                    • CryptoSage does not execute real trades on your behalf
                    
                    Exchange connections are used solely for read-only portfolio tracking. CryptoSage never initiates transfers, withdrawals, or real trades on any connected exchange.
                    """)
                    
                    PolicySection(title: "5. User Responsibilities", content: """
                    You are responsible for:
                    • All investment decisions you make outside of CryptoSage
                    • Understanding that cryptocurrency markets are volatile and risky
                    • Complying with all applicable laws in your jurisdiction
                    • Maintaining security of your device and API credentials
                    • Not relying solely on AI features or predictions for financial decisions
                    • Conducting your own research before making any investment
                    """)
                    
                    PolicySection(title: "6. Disclaimer of Warranties", content: """
                    CryptoSage AI is provided "AS IS" without warranties of any kind. We do not guarantee:
                    • Accuracy of price data, market data, or AI insights
                    • Continuous, uninterrupted service
                    • Accuracy or profitability of any AI prediction or analysis
                    • Compatibility with all exchanges or wallet providers
                    
                    CRYPTOCURRENCY MARKETS ARE HIGHLY VOLATILE. Information displayed in CryptoSage is for informational purposes only. Always do your own research and consult a qualified financial advisor before making investment decisions.
                    """)
                    
                    PolicySection(title: "7. Limitation of Liability", content: """
                    To the maximum extent permitted by law, we are NOT liable for:
                    • Financial losses from any investment decisions you make
                    • Losses from reliance on AI-generated insights or predictions
                    • Third-party exchange or data provider failures or errors
                    • Inaccurate price data or delayed market information
                    • Data loss or security breaches beyond our control
                    • Indirect, incidental, or consequential damages
                    
                    Our total liability shall not exceed amounts you paid us in the prior 12 months or $100, whichever is greater.
                    """)
                    
                    PolicySection(title: "8. Indemnification", content: """
                    You agree to indemnify and hold harmless CryptoSage from any claims, damages, or expenses arising from your use of the App, trading decisions, violation of these terms, or violation of any law.
                    """)
                    
                    PolicySection(title: "9. Arbitration & Class Action Waiver", content: """
                    Any disputes will be resolved through binding individual arbitration rather than court, except for small claims court. 
                    
                    YOU WAIVE YOUR RIGHT TO PARTICIPATE IN CLASS ACTIONS OR CLASS ARBITRATIONS.
                    
                    You may opt out within 30 days by emailing hypersageai@gmail.com.
                    """)
                    
                    PolicySection(title: "10. Subscriptions & Payments", content: """
                    • Subscriptions are billed through Apple's App Store
                    • Prices may change with notice
                    • Refunds are handled by Apple
                    • Cancellation takes effect at period end
                    """)
                    
                    PolicySection(title: "11. Governing Law", content: """
                    These terms are governed by the laws of the State of Delaware, United States. Any legal action shall be brought in Delaware courts.
                    """)
                    
                    PolicySection(title: "12. Contact", content: """
                    Questions about these terms:
                    Email: hypersageai@gmail.com
                    
                    For privacy inquiries:
                    Email: hypersageai@gmail.com
                    """)
                }
                .padding(20)
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
}

// MARK: - Analytics Info View

struct AnalyticsInfoView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            CSPageHeader(title: "Analytics & Data", leadingAction: { dismiss() })
            
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
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
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

// MARK: - Trading Acknowledgment Status View

struct TradingAcknowledgmentStatusView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirmation = false
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    private var riskManager: TradingRiskAcknowledgmentManager { .shared }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                CSNavButton(
                    icon: "chevron.left",
                    action: { dismiss() }
                )
                
                Spacer()
                
                Text("Trading Acknowledgments")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Explanation
                    Text("These acknowledgments confirm you understand the risks of trading. They're required before executing real trades.")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    // Basic Trading Acknowledgment
                    acknowledgmentRow(
                        title: "Basic Trading Risks",
                        description: "General cryptocurrency trading risks",
                        isAcknowledged: riskManager.hasValidAcknowledgment,
                        date: riskManager.acknowledgmentDateString
                    )
                    
                    // Derivatives Acknowledgment
                    acknowledgmentRow(
                        title: "Derivatives & Leverage Risks",
                        description: "Leverage trading and liquidation risks",
                        isAcknowledged: riskManager.hasAcknowledgedDerivatives,
                        date: nil
                    )
                    
                    // Bot Trading Acknowledgment
                    acknowledgmentRow(
                        title: "Automated Bot Trading Risks",
                        description: "Risks of automated 24/7 trading",
                        isAcknowledged: riskManager.hasAcknowledgedBotTrading,
                        date: nil
                    )
                    
                    Divider()
                        .padding(.vertical, 10)
                    
                    // Paper Trading Note
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Paper Trading")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            Text("Paper trading (practice mode) does not require acknowledgments since no real money is at risk.")
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                    
                    // Reset Button
                    Button {
                        showResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset All Acknowledgments")
                        }
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                    Text("Resetting will require you to re-acknowledge risks before your next real trade.")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(20)
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .alert("Reset Acknowledgments?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                riskManager.resetAllAcknowledgments()
            }
        } message: {
            Text("You will need to re-acknowledge trading risks before your next real trade or bot creation.")
        }
    }
    
    private func acknowledgmentRow(title: String, description: String, isAcknowledged: Bool, date: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isAcknowledged ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(isAcknowledged ? .green : DS.Adaptive.textTertiary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                if let date = date {
                    Text("Acknowledged: \(date)")
                        .font(.caption2)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            Spacer()
            
            if isAcknowledged {
                Text("Done")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
            } else {
                Text("Pending")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(6)
            }
        }
        .padding(12)
        .background(DS.Adaptive.cardBackground)
        .cornerRadius(10)
    }
}

struct LanguageSettingsView: View {
    @Binding var selectedLanguage: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    // Supported languages with native names and flags
    private let languages: [(code: String, name: String, nativeName: String, flag: String)] = [
        ("English", "English", "English", "🇺🇸"),
        ("Spanish", "Spanish", "Español", "🇪🇸"),
        ("French", "French", "Français", "🇫🇷"),
        ("German", "German", "Deutsch", "🇩🇪"),
        ("Italian", "Italian", "Italiano", "🇮🇹"),
        ("Portuguese", "Portuguese", "Português", "🇧🇷"),
        ("Japanese", "Japanese", "日本語", "🇯🇵"),
        ("Korean", "Korean", "한국어", "🇰🇷"),
        ("Chinese", "Chinese (Simplified)", "简体中文", "🇨🇳"),
        ("Russian", "Russian", "Русский", "🇷🇺"),
        ("Arabic", "Arabic", "العربية", "🇸🇦"),
        ("Hindi", "Hindi", "हिन्दी", "🇮🇳"),
        ("Turkish", "Turkish", "Türkçe", "🇹🇷"),
        ("Dutch", "Dutch", "Nederlands", "🇳🇱"),
        ("Polish", "Polish", "Polski", "🇵🇱"),
        ("Vietnamese", "Vietnamese", "Tiếng Việt", "🇻🇳"),
        ("Thai", "Thai", "ไทย", "🇹🇭"),
        ("Indonesian", "Indonesian", "Bahasa Indonesia", "🇮🇩")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header — uses shared CSPageHeader component
            CSPageHeader(title: "Language", leadingAction: { dismiss() })
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Info Banner
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [BrandColors.goldBase, BrandColors.goldLight],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .font(.system(size: 18))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("App Language")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            Text("Changes how dates and numbers are formatted (e.g., month names, decimal separators). Market data remains in original format.")
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(BrandColors.goldBase.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(BrandColors.goldBase.opacity(0.15), lineWidth: 0.5)
                            )
                    )
                    
                    // Language List
                    VStack(spacing: 0) {
                        ForEach(languages, id: \.code) { language in
                            Button(action: {
                                impactLight.impactOccurred()
                                selectedLanguage = language.code
                            }) {
                                HStack(spacing: 14) {
                                    Text(language.flag)
                                        .font(.title2)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(language.name)
                                            .font(.body.weight(.medium))
                                            .foregroundColor(DS.Adaptive.textPrimary)
                                        
                                        Text(language.nativeName)
                                            .font(.caption)
                                            .foregroundColor(DS.Adaptive.textSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedLanguage == language.code {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [BrandColors.goldBase, BrandColors.goldLight],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(
                                    selectedLanguage == language.code
                                        ? BrandColors.goldBase.opacity(0.08)
                                        : Color.clear
                                )
                            }
                            .buttonStyle(.plain)
                            
                            if language.code != languages.last?.code {
                                Rectangle()
                                    .fill(DS.Adaptive.stroke)
                                    .frame(height: 0.5)
                                    .padding(.leading, 60)
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
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
}

struct CurrencySettingsView: View {
    @Binding var selectedCurrency: String
    @StateObject private var currencyManager = CurrencyManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header — uses shared CSPageHeader with refresh trailing button
            CSPageHeader(title: "Currency", leadingAction: { dismiss() }) {
                Button {
                    impactLight.impactOccurred()
                    Task { await currencyManager.refreshRates() }
                } label: {
                    Group {
                        if currencyManager.isFetchingRates {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [BrandColors.goldBase, BrandColors.goldLight],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DS.Adaptive.chipBackground))
                    .overlay(Circle().stroke(DS.Adaptive.stroke, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .disabled(currencyManager.isFetchingRates)
            }
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Section Header
                    HStack {
                        Text("DISPLAY CURRENCY")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Spacer()
                        if let lastFetch = currencyManager.lastRateFetch {
                            Text("Updated \(lastFetch, style: .relative) ago")
                                .font(.caption2)
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                    }
                    .padding(.horizontal, 4)
                    
                    // Currency List
                    VStack(spacing: 0) {
                        ForEach(DisplayCurrency.allCases, id: \.rawValue) { currency in
                            Button {
                                impactLight.impactOccurred()
                                selectedCurrency = currency.rawValue
                                currencyManager.setCurrency(currency)
                            } label: {
                                HStack(spacing: 14) {
                                    Text(currency.flag)
                                        .font(.title2)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(currency.rawValue)
                                            .font(.body.weight(.medium))
                                            .foregroundColor(DS.Adaptive.textPrimary)
                                        Text(currency.displayName)
                                            .font(.caption)
                                            .foregroundColor(DS.Adaptive.textSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(currency.symbol)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(DS.Adaptive.textSecondary)
                                    
                                    if selectedCurrency == currency.rawValue {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [BrandColors.goldBase, BrandColors.goldLight],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(
                                    selectedCurrency == currency.rawValue
                                        ? BrandColors.goldBase.opacity(0.08)
                                        : Color.clear
                                )
                            }
                            .buttonStyle(.plain)
                            
                            if currency != DisplayCurrency.allCases.last {
                                Rectangle()
                                    .fill(DS.Adaptive.stroke)
                                    .frame(height: 0.5)
                                    .padding(.leading, 60)
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
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
}

// MARK: - Smart Exchange Router
// Routes to PortfolioPaymentMethodsView if no accounts, LinkedAccountsView if accounts exist

struct ExchangeWalletRouterView: View {
    @ObservedObject private var accountsManager = ConnectedAccountsManager.shared
    
    var body: some View {
        Group {
            if accountsManager.accounts.isEmpty {
                // No accounts - go directly to connections page
                PortfolioPaymentMethodsView()
            } else {
                // Has accounts - show linked accounts management
                LinkedAccountsView()
            }
        }
    }
}

// MARK: - Linked Accounts View

struct LinkedAccountsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var accountsManager = ConnectedAccountsManager.shared
    
    @State private var accountToRemove: ConnectedAccount?
    @State private var showRemoveConfirmation = false
    @State private var accountToRename: ConnectedAccount?
    @State private var renameText: String = ""
    @State private var showRenameSheet = false
    @State private var showAddConnections = false
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    
    // Use real connected accounts data
    private var displayAccounts: [ConnectedAccount] {
        accountsManager.accounts
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            linkedAccountsHeader
            
            if displayAccounts.isEmpty {
                // Empty state - redirect to connections
                Color.clear
                    .onAppear {
                        showAddConnections = true
                    }
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
                            ForEach(displayAccounts, id: \.id) { account in
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
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
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
            CSNavButton(
                icon: "chevron.left",
                action: { dismiss() }
            )
            
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
        let isDark = colorScheme == .dark
        
        return VStack(spacing: 0) {
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
                .foregroundColor(BrandColors.ctaTextColor(isDark: isDark))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    AdaptiveGradients.goldButton(isDark: isDark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AdaptiveGradients.ctaRimStroke(isDark: isDark), lineWidth: 0.8)
                )
                .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24) // Extra bottom padding for safe area
            .background(DS.Adaptive.background)
        }
        .padding(.bottom, 8) // Additional spacing from tab bar
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
    @State private var showActionMenu: Bool = false
    
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
            
            // Action menu button
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showActionMenu = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showActionMenu, arrowEdge: .leading) {
                LinkedAccountActionMenu(
                    isPresented: $showActionMenu,
                    onRename: onRename,
                    onRemove: onRemove
                )
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Linked Account Action Menu (Styled popover)
private struct LinkedAccountActionMenu: View {
    @Binding var isPresented: Bool
    let onRename: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 2) {
            actionRow(title: "Rename", icon: "pencil", action: onRename)
            
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            
            actionRow(title: "Disconnect", icon: "xmark.circle", isDestructive: true, action: onRemove)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(DS.Adaptive.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            LinearGradient(colors: [Color.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                .allowsHitTesting(false)
        )
        .frame(minWidth: 140, maxWidth: 180)
    }
    
    @ViewBuilder
    private func actionRow(title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDestructive ? Color.red : Color.white.opacity(0.9))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDestructive ? Color.red : Color.white.opacity(0.92))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// NOTE: PINActionMenu moved to SecuritySettingsView.swift

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

// MARK: - Home Screen Customization View (Drag-to-Reorder + Toggle)

struct HomeCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    /// Current section order (drives the reorderable list)
    @State private var sectionOrder: [HomeSection] = []
    
    // Section visibility toggles (direct @AppStorage — no bindings needed)
    @AppStorage("Home.showPortfolio")           private var showPortfolio: Bool = true
    @AppStorage("Home.showAIInsights")          private var showAIInsights: Bool = true
    @AppStorage("Home.showAIPredictions")       private var showAIPredictions: Bool = true
    @AppStorage("Home.showStocksOverview")      private var showStocksOverview: Bool = true
    @AppStorage("Home.showWatchlist")           private var showWatchlist: Bool = true
    @AppStorage("Home.showMarketStats")         private var showMarketStats: Bool = false
    @AppStorage("Home.showSentiment")           private var showSentiment: Bool = true
    @AppStorage("Home.showHeatmap")             private var showHeatmap: Bool = true
    @AppStorage("Home.showTrending")            private var showTrending: Bool = true
    @AppStorage("Home.showArbitrage")           private var showArbitrage: Bool = true
    @AppStorage("Home.showWhaleActivity")       private var showWhaleActivity: Bool = true
    @AppStorage("Home.showCommoditiesOverview") private var showCommodities: Bool = true
    @AppStorage("Home.showEvents")              private var showEvents: Bool = true
    @AppStorage("Home.showNews")                private var showNews: Bool = true
    @AppStorage("Home.showPromos")              private var showPromos: Bool = true
    @AppStorage("Home.showTransactions")        private var showTransactions: Bool = true
    @AppStorage("Home.showCommunity")           private var showCommunity: Bool = true
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            customizeHeader
            
            List {
                // Hero info card
                heroInfoCard
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                
                // Instruction hint
                HStack(spacing: 6) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text("Hold and drag")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .bold))
                    Text("to reorder")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(DS.Adaptive.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                
                // Reorderable section rows
                ForEach(sectionOrder, id: \.self) { section in
                    HomeSectionReorderRow(
                        section: section,
                        isOn: binding(for: section),
                        isDark: isDark,
                        onChange: { selectionFeedback.selectionChanged() }
                    )
                    .listRowBackground(
                        isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.02)
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 8))
                    .listRowSeparator(.visible, edges: .bottom)
                }
                .onMove(perform: moveSection)
                
                // Reset button
                HStack {
                    Spacer()
                    resetButton
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 60, trailing: 16))
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .tint(BrandColors.goldBase)
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                sectionOrder = HomeSectionOrderManager.shared.getOrder()
            }
        }
    }
    
    // MARK: - Binding Helper
    
    private func binding(for section: HomeSection) -> Binding<Bool> {
        switch section {
        case .portfolio:           return $showPortfolio
        case .aiInsights:          return $showAIInsights
        case .aiPredictions:       return $showAIPredictions
        case .stocksOverview:      return $showStocksOverview
        case .watchlist:           return $showWatchlist
        case .marketStats:         return $showMarketStats
        case .sentiment:           return $showSentiment
        case .heatmap:             return $showHeatmap
        case .trending:            return $showTrending
        case .arbitrage:           return $showArbitrage
        case .whaleActivity:       return $showWhaleActivity
        case .commoditiesOverview: return $showCommodities
        case .events:              return $showEvents
        case .news:                return $showNews
        case .promos:              return $showPromos
        case .transactions:        return $showTransactions
        case .community:           return $showCommunity
        default:                   return .constant(true)
        }
    }
    
    // MARK: - Move Handler
    
    private func moveSection(from: IndexSet, to: Int) {
        sectionOrder.move(fromOffsets: from, toOffset: to)
        impactMedium.impactOccurred()
        HomeSectionOrderManager.shared.saveOrder(sectionOrder)
    }
    
    // MARK: - Header
    
    private var customizeHeader: some View {
        HStack {
            CSNavButton(
                icon: "chevron.left",
                action: { dismiss() }
            )
            
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
    }
    
    // MARK: - Hero Info Card
    
    private var heroInfoCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldLight.opacity(0.3), BrandColors.goldDark.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(chipGoldGradient)
            }
            
            Text("Home Sections")
                .font(.title3.weight(.bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Drag to reorder. Toggle to show or hide.")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.03),
                            isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.01)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [BrandColors.goldBase.opacity(0.4), BrandColors.goldBase.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - Reset Button
    
    private var resetButton: some View {
        Button(action: {
            impactLight.impactOccurred()
            resetToDefaults()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                Text("Reset to Defaults")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(BrandColors.goldBase)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(BrandColors.goldBase.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
    
    private func resetToDefaults() {
        // Reset order
        HomeSectionOrderManager.shared.resetOrder()
        withAnimation(.easeInOut(duration: 0.3)) {
            sectionOrder = HomeSectionOrderManager.shared.getOrder()
        }
        
        // Reset visibility
        showPortfolio = true
        showAIInsights = true
        showAIPredictions = true
        showStocksOverview = true
        showWatchlist = true
        showMarketStats = false  // Market Stats already shown on Market tab header
        showSentiment = true
        showHeatmap = true
        showTrending = true
        showArbitrage = true
        showWhaleActivity = true
        showCommodities = true
        showEvents = true
        showNews = true
        showPromos = true
        showTransactions = true
        showCommunity = true
    }
}

// MARK: - Home Section Reorder Row (Drag Handle + Icon + Title + Toggle)

private struct HomeSectionReorderRow: View {
    let section: HomeSection
    @Binding var isOn: Bool
    let isDark: Bool
    let onChange: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Premium icon circle
            ZStack {
                // Subtle glow when enabled
                Circle()
                    .fill(
                        RadialGradient(
                            colors: isOn ? [
                                section.accentColor.opacity(0.20),
                                section.accentColor.opacity(0.04),
                                Color.clear
                            ] : [Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 22
                        )
                    )
                    .frame(width: 44, height: 44)
                
                // Icon background circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isOn ? [
                                section.accentColor.opacity(isDark ? 0.22 : 0.28),
                                section.accentColor.opacity(isDark ? 0.10 : 0.14)
                            ] : [
                                Color.gray.opacity(isDark ? 0.15 : 0.10),
                                Color.gray.opacity(isDark ? 0.08 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: isOn ? [
                                        section.accentColor.opacity(0.5),
                                        section.accentColor.opacity(0.2)
                                    ] : [
                                        Color.gray.opacity(0.25),
                                        Color.gray.opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                    )
                
                // Section icon
                Image(systemName: section.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        isOn ? LinearGradient(
                            colors: [section.accentColor, section.accentColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) : LinearGradient(
                            colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            // Title and description
            VStack(alignment: .leading, spacing: 2) {
                Text(section.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isOn ? DS.Adaptive.textPrimary : DS.Adaptive.textSecondary)
                
                Text(section.sectionDescription)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 4)
            
            // Gold-tinted toggle
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(BrandColors.goldBase)
                .onChange(of: isOn) { _, _ in onChange() }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.2), value: isOn)
    }
}

// MARK: - Trading Mode Settings Section

/// Quick switch between Portfolio, Paper Trading, and Demo modes
struct TradingModeSettingsSection: View {
    let selectionFeedback: UISelectionFeedbackGenerator
    let impactLight: UIImpactFeedbackGenerator
    
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showUpgradeSheet = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var currentMode: AppTradingMode {
        if paperTradingManager.isPaperTradingEnabled { return .paper }
        if demoModeManager.isDemoMode { return .demo }
        if subscriptionManager.isDeveloperMode && SubscriptionManager.shared.developerLiveTradingEnabled {
            return .liveTrading
        }
        return .portfolio
    }
    
    private var hasConnectedAccounts: Bool {
        !ConnectedAccountsManager.shared.accounts.isEmpty
    }
    
    /// Available modes — matches homepage header logic exactly
    private var availableModes: [AppTradingMode] {
        var modes: [AppTradingMode] = [.portfolio, .paper]
        
        // Demo is available for:
        // - Developers (for testing/exploring sample data)
        // - Regular users who haven't connected an exchange yet
        if subscriptionManager.isDeveloperMode || (!hasConnectedAccounts && !paperTradingManager.isPaperTradingEnabled) {
            modes.append(.demo)
        }
        
        // Live Trading only for developers (real money execution)
        if subscriptionManager.isDeveloperMode {
            modes.append(.liveTrading)
        }
        
        return modes
    }
    
    /// Adaptive sizing when 4+ modes visible (developer mode)
    private var isCompactToggle: Bool { availableModes.count > 3 }
    
    var body: some View {
        SettingsSection(title: "TRADING MODE") {
            VStack(spacing: 12) {
                // Current mode display - premium glass icon
                HStack {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: isDark
                                        ? [currentMode.color.opacity(0.25), currentMode.color.opacity(0.08)]
                                        : [currentMode.color.opacity(0.18), currentMode.color.opacity(0.06)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 20
                                )
                            )
                            .frame(width: 36, height: 36)
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(isDark ? 0.15 : 0.5), Color.white.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(width: 36, height: 36)
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        currentMode.color.opacity(isDark ? 0.8 : 0.6),
                                        currentMode.color.opacity(isDark ? 0.4 : 0.25)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                            .frame(width: 36, height: 36)
                        Image(systemName: currentMode.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(currentMode.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Mode")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(currentMode.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(currentMode.color)
                    }
                    
                    Spacer()
                }
                
                // Mode buttons - premium glass container matching homepage header
                HStack(spacing: isCompactToggle ? 2 : 6) {
                    ForEach(availableModes, id: \.self) { mode in
                        modeButton(mode)
                    }
                }
                .padding(3)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(isDark ? 0.06 : 0.35), Color.white.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: isDark
                                    ? [Color.white.opacity(0.12), Color.white.opacity(0.04)]
                                    : [Color.black.opacity(0.06), Color.black.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
            }
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showUpgradeSheet) {
            UnifiedPaywallSheet(feature: .paperTrading)
        }
    }
    
    @ViewBuilder
    private func modeButton(_ mode: AppTradingMode) -> some View {
        let isSelected = currentMode == mode
        let isLocked = mode == .paper && !paperTradingManager.hasAccess
        let selectedColor = currentMode.color
        
        // Adaptive sizing for compact toggle (4+ modes)
        let iconSize: CGFloat = isCompactToggle ? 10 : 12
        let textSize: CGFloat = isCompactToggle ? 10 : 11
        let hPad: CGFloat = isCompactToggle ? 4 : 6
        let vPad: CGFloat = isCompactToggle ? 8 : 10
        let lockSize: CGFloat = isCompactToggle ? 6 : 7
        
        Button {
            if isLocked {
                impactLight.impactOccurred()
                showUpgradeSheet = true
            } else {
                impactLight.impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    selectMode(mode)
                }
            }
        } label: {
            HStack(spacing: isCompactToggle ? 3 : 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: iconSize, weight: .semibold))
                Text(mode.rawValue)
                    .font(.system(size: textSize, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: lockSize))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isDark ? [BrandColors.goldLight, BrandColors.goldBase] : [BrandColors.silverBase, BrandColors.silverDark],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .foregroundColor(isSelected ? (isDark ? .white : .black) : (isLocked ? .secondary.opacity(0.35) : .secondary.opacity(0.7)))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(
                ZStack {
                    if isSelected {
                        // Premium glass fill — radial gradient for depth
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                RadialGradient(
                                    colors: isDark
                                        ? [selectedColor.opacity(0.3), selectedColor.opacity(0.12)]
                                        : [selectedColor.opacity(0.22), selectedColor.opacity(0.08)],
                                    center: .top,
                                    startRadius: 0,
                                    endRadius: 50
                                )
                            )
                        
                        // Top-shine highlight
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isDark ? 0.18 : 0.5),
                                        Color.white.opacity(0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                        
                        // Gradient border
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        selectedColor.opacity(isDark ? 0.8 : 0.6),
                                        selectedColor.opacity(isDark ? 0.4 : 0.25),
                                        selectedColor.opacity(isDark ? 0.2 : 0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    } else {
                        // Unselected: subtle glass for depth
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(isDark ? 0.03 : 0.2), Color.white.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
    
    private func selectMode(_ mode: AppTradingMode) {
        selectionFeedback.selectionChanged()
        switch mode {
        case .portfolio:
            paperTradingManager.disablePaperTrading()
            demoModeManager.disableDemoMode()
            if subscriptionManager.isDeveloperMode {
                SubscriptionManager.shared.developerLiveTradingEnabled = false
            }
        case .paper:
            demoModeManager.disableDemoMode()
            _ = paperTradingManager.enablePaperTrading()
            if subscriptionManager.isDeveloperMode {
                SubscriptionManager.shared.developerLiveTradingEnabled = false
            }
        case .liveTrading:
            paperTradingManager.disablePaperTrading()
            demoModeManager.disableDemoMode()
            SubscriptionManager.shared.developerLiveTradingEnabled = true
        case .demo:
            paperTradingManager.disablePaperTrading()
            demoModeManager.enableDemoMode()
            if subscriptionManager.isDeveloperMode {
                SubscriptionManager.shared.developerLiveTradingEnabled = false
            }
        }
    }
}

// MARK: - Paper Trading Settings Section

/// A dedicated section for Paper Trading with subscription gating
struct PaperTradingSettingsSection: View {
    let selectionFeedback: UISelectionFeedbackGenerator
    let impactLight: UIImpactFeedbackGenerator
    
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showUpgradePrompt = false
    @State private var currentPrices: [String: Double] = [:]
    @State private var pricesCancellable: AnyCancellable?
    
    private var hasAccess: Bool {
        subscriptionManager.hasAccess(to: .paperTrading)
    }
    
    /// Calculate total portfolio value from all holdings using live prices
    private var portfolioValue: Double {
        paperTradingManager.calculatePortfolioValue(prices: currentPrices)
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
        .onAppear {
            setupLivePrices()
        }
        .onDisappear {
            pricesCancellable?.cancel()
        }
    }
    
    /// Subscribe to live prices for portfolio value calculation
    private func setupLivePrices() {
        // Use MarketViewModel.shared.allCoins for consistency with other views (Home, Portfolio)
        // This ensures Paper Trading values match across the entire app
        var prices: [String: Double] = [
            // Stablecoins are always 1:1 with USD
            "USDT": 1.0, "USD": 1.0, "USDC": 1.0, "BUSD": 1.0, "FDUSD": 1.0
        ]
        
        // Load prices from MarketViewModel (same source as PortfolioSectionView)
        for coin in MarketViewModel.shared.allCoins {
            if let price = coin.priceUsd, price > 0 {
                prices[coin.symbol.uppercased()] = price
            }
        }
        
        currentPrices = prices
        
        // Subscribe to live price updates
        // PERFORMANCE FIX v22: Use slowPublisher (2s throttle) instead of raw unthrottled publisher.
        // Settings screen doesn't need real-time prices — raw publisher fires on every emission,
        // wasting CPU processing 250 coins when user is just browsing settings.
        pricesCancellable = LivePriceManager.shared.slowPublisher
            .receive(on: DispatchQueue.main)
            .sink { coins in
                var newPrices = currentPrices
                for coin in coins {
                    if let price = coin.priceUsd, price > 0 {
                        newPrices[coin.symbol.uppercased()] = price
                    }
                }
                currentPrices = newPrices
            }
    }
    
    /// Paper trading's canonical amber/orange color
    private var paperColor: Color { AppTradingMode.paper.color }
    private var paperColorLight: Color { AppTradingMode.paper.secondaryColor }
    
    private var enabledContent: some View {
        let isDark = colorScheme == .dark
        let startingBalance: Double = 100_000
        let pnl = portfolioValue - startingBalance
        let pnlPercent = startingBalance > 0 ? (pnl / startingBalance) * 100 : 0
        let pnlPositive = pnl >= 0
        
        return VStack(spacing: 0) {
            SettingsToggleRow(
                icon: "banknote.fill",
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
                iconColor: paperColor
            )
            
            // Show stats when paper trading is enabled
            if paperTradingManager.isPaperTradingEnabled {
                VStack(spacing: 10) {
                    // Balance row — prominent
                    HStack(alignment: .firstTextBaseline) {
                        Text(formatPortfolioValue(portfolioValue))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Spacer()
                        
                        // P&L pill
                        HStack(spacing: 3) {
                            Image(systemName: pnlPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                            Text(String(format: "%@%.2f%%", pnlPositive ? "+" : "", pnlPercent))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(pnlPositive ? .green : .red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill((pnlPositive ? Color.green : Color.red).opacity(isDark ? 0.15 : 0.10))
                        )
                    }
                    
                    // Stats row — trades & P&L
                    HStack(spacing: 0) {
                        let tradeCount = paperTradingManager.paperTradeHistory.count
                        
                        // Trades stat
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(paperColor)
                            Text("\(tradeCount) Trade\(tradeCount == 1 ? "" : "s")")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                        
                        Spacer()
                        
                        // P&L amount
                        HStack(spacing: 4) {
                            Text("P&L")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(String(format: "%@%@", pnlPositive ? "+" : "", formatPortfolioValue(pnl)))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(pnlPositive ? .green : .red)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: isDark
                                        ? [paperColor.opacity(0.10), paperColor.opacity(0.04)]
                                        : [paperColor.opacity(0.07), paperColor.opacity(0.02)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(isDark ? 0.06 : 0.35), Color.white.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isDark
                                    ? [paperColor.opacity(0.30), paperColor.opacity(0.08)]
                                    : [paperColor.opacity(0.25), paperColor.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
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
                SettingsRow(icon: "slider.horizontal.3", title: "Paper Trading Settings", iconColor: paperColor)
            }
            .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
        }
    }
    
    /// Format portfolio value for display
    // PERFORMANCE FIX: Cached formatter
    private static let _portfolioCurrencyFmt: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode
        nf.maximumFractionDigits = 2; nf.minimumFractionDigits = 2; return nf
    }()
    private func formatPortfolioValue(_ value: Double) -> String {
        return Self._portfolioCurrencyFmt.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
    
    private var lockedContent: some View {
        let isDark = colorScheme == .dark
        let upgradeCtaText = StoreKitManager.shared.hasAnyTrialAvailable
            ? "Start Free Trial to Unlock"
            : "Upgrade to Pro to Unlock"
        
        return VStack(spacing: 12) {
            // Locked toggle row
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(paperColor.opacity(0.1))
                        .frame(width: 30, height: 30)
                    
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(paperColor.opacity(0.5))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Paper Trading")
                            .font(.body)
                            .foregroundColor(DS.Adaptive.textPrimary.opacity(0.6))
                        
                        LockedFeatureBadge(feature: .paperTrading, style: .compact)
                    }
                    
                    Text("Practice with $100,000 virtual funds")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isDark ? BrandColors.goldBase : BrandColors.goldDark)
            }
            .padding(.vertical, 4)
            
            // Upgrade prompt — adaptive CTA (gold in dark, charcoal in light)
            Button {
                impactLight.impactOccurred()
                showUpgradePrompt = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(upgradeCtaText)
                        .font(.subheadline.weight(.bold))
                }
            }
            .buttonStyle(
                PremiumPrimaryCTAStyle(
                    height: 40,
                    horizontalPadding: 14,
                    cornerRadius: 10,
                    font: .subheadline.weight(.bold)
                )
            )
            .padding(.top, 4)
        }
        .unifiedPaywallSheet(feature: .paperTrading, isPresented: $showUpgradePrompt)
    }
}

// MARK: - Live Trading Bots Settings Section

/// A dedicated section for Live Trading Bots (3Commas integration)
/// Only visible when 3Commas is configured
struct LiveTradingBotsSettingsSection: View {
    let selectionFeedback: UISelectionFeedbackGenerator
    let impactLight: UIImpactFeedbackGenerator
    
    @ObservedObject private var liveBotManager = LiveBotManager.shared
    
    var body: some View {
        // Only show this section if 3Commas is configured
        if liveBotManager.isConfigured {
            SettingsSection(title: "LIVE TRADING BOTS") {
                VStack(spacing: 0) {
                    // Summary stats
                    if !liveBotManager.bots.isEmpty {
                        statsRow
                            .padding(.vertical, 8)
                    }
                    
                    // Bot preview (show first 2)
                    if !liveBotManager.bots.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(liveBotManager.bots.prefix(2)) { bot in
                                botPreviewRow(bot: bot)
                            }
                            
                            // Show "and X more" if there are more bots
                            if liveBotManager.bots.count > 2 {
                                HStack {
                                    Spacer()
                                    Text("and \(liveBotManager.bots.count - 2) more...")
                                        .font(.system(size: 12))
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                                )
                        )
                        .padding(.bottom, 8)
                    } else {
                        // Empty state
                        HStack {
                            Image(systemName: "cpu")
                                .font(.system(size: 14))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text("No live bots yet")
                                .font(.system(size: 14))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    
                    SettingsDivider()
                    
                    NavigationLink(destination: LiveBotsListView()) {
                        SettingsRow(icon: "cpu", title: "Manage Live Bots", iconColor: .blue)
                    }
                    .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
                }
            }
            .onAppear {
                // Fetch bots when section appears
                Task {
                    await liveBotManager.refreshBots()
                }
            }
        }
    }
    
    private var statsRow: some View {
        HStack(spacing: 16) {
            // Total bots
            VStack(alignment: .leading, spacing: 2) {
                Text("Total")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
                Text("\(liveBotManager.totalBotCount)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            // Running bots
            VStack(alignment: .leading, spacing: 2) {
                Text("Running")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("\(liveBotManager.enabledBotCount)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            // Total profit
            VStack(alignment: .trailing, spacing: 2) {
                Text("Total Profit")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
                Text(formatProfit(liveBotManager.totalProfitUsd))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(liveBotManager.totalProfitUsd >= 0 ? .green : .red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
    }
    
    private func botPreviewRow(bot: ThreeCommasBot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: bot.strategy.icon)
                .font(.system(size: 14))
                .foregroundColor(bot.strategy.color)
                .frame(width: 24)
            
            Text(bot.name)
                .font(.system(size: 13))
                .foregroundColor(DS.Adaptive.textPrimary)
                .lineLimit(1)
            
            Spacer()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(bot.status.color)
                    .frame(width: 6, height: 6)
                Text(bot.status.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(bot.status.color)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatProfit(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        if abs(value) >= 1000 {
            return "\(prefix)$\(String(format: "%.1fK", value / 1000))"
        }
        return "\(prefix)$\(String(format: "%.2f", value))"
    }
}

// MARK: - Stocks & ETFs Settings Section

/// Dedicated section for Stocks & ETFs settings - follows standard SettingsSection pattern
struct StocksSettingsSection: View {
    @Binding var showStocksInPortfolio: Bool
    @ObservedObject var portfolioViewModel: PortfolioViewModel
    let selectionFeedback: UISelectionFeedbackGenerator
    let impactLight: UIImpactFeedbackGenerator
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Stock-specific settings
    @AppStorage("liveStockUpdatesEnabled") private var liveUpdatesEnabled: Bool = true
    @AppStorage("stockPollingMarketHoursOnly") private var marketHoursOnly: Bool = false
    @AppStorage("showStockLogos") private var showStockLogos: Bool = true
    @AppStorage("includeStocksInPieChart") private var includeStocksInPieChart: Bool = true
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        SettingsSection(title: "STOCKS & ETFs") {
            // Main toggle - Show Stocks in Portfolio
            SettingsToggleRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Show Stocks in Portfolio",
                isOn: $showStocksInPortfolio
            )
            .onChange(of: showStocksInPortfolio) { _, newValue in
                selectionFeedback.selectionChanged()
                handleStocksToggle(enabled: newValue)
            }
            
            // Description text
            Text("Display stock and ETF holdings alongside your crypto portfolio")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.top, 4)
            
            // Show sub-options only when stocks are enabled
            if showStocksInPortfolio {
                // Divider before sub-options
                SettingsDivider()
                    .padding(.top, 8)
                
                // Live Price Updates
                SettingsToggleRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Live Price Updates",
                    isOn: $liveUpdatesEnabled
                )
                .onChange(of: liveUpdatesEnabled) { _, newValue in
                    selectionFeedback.selectionChanged()
                    LiveStockPriceManager.shared.liveUpdatesEnabled = newValue
                    LiveStockPriceManager.shared.reapplyPollingPreferences()
                }
                
                // Market Hours Only (only show when live updates enabled)
                if liveUpdatesEnabled {
                    SettingsDivider()
                    SettingsToggleRow(
                        icon: "clock",
                        title: "Market Hours Only",
                        isOn: $marketHoursOnly
                    )
                    .onChange(of: marketHoursOnly) { _, newValue in
                        selectionFeedback.selectionChanged()
                        LiveStockPriceManager.shared.marketHoursOnly = newValue
                        LiveStockPriceManager.shared.reapplyPollingPreferences()
                    }
                    
                    Text("Pause price updates outside US market hours")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .padding(.top, 2)
                }
                
                SettingsDivider()
                
                // Company Logos
                SettingsToggleRow(
                    icon: "photo.circle",
                    title: "Company Logos",
                    isOn: $showStockLogos
                )
                .onChange(of: showStockLogos) { _, _ in selectionFeedback.selectionChanged() }
                
                SettingsDivider()
                
                // Include in Pie Chart
                SettingsToggleRow(
                    icon: "chart.pie",
                    title: "Include in Allocation Chart",
                    isOn: $includeStocksInPieChart
                )
                .onChange(of: includeStocksInPieChart) { _, _ in selectionFeedback.selectionChanged() }
                
                // Market Status indicator
                SettingsDivider()
                    .padding(.top, 4)
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(LiveStockPriceManager.shared.isMarketOpen ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(LiveStockPriceManager.shared.isMarketOpen ? "US Market Open" : "US Market Closed")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    if let lastUpdate = LiveStockPriceManager.shared.lastUpdateAt {
                        Text("Updated \(lastUpdate.formatted(.relative(presentation: .numeric)))")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                .padding(.top, 8)
                
                // Connect Brokerage link
                SettingsDivider()
                    .padding(.top, 4)
                
                NavigationLink(destination: BrokerageConnectionView()) {
                    SettingsRow(icon: "building.columns.fill", title: "Connect Brokerage Account")
                }
                .simultaneousGesture(TapGesture().onEnded { impactLight.impactOccurred() })
            }
        }
    }
    
    /// Handle enabling/disabling the stocks feature
    private func handleStocksToggle(enabled: Bool) {
        let isInDemoMode = portfolioViewModel.demoOverrideEnabled
        
        if enabled {
            if isInDemoMode {
                portfolioViewModel.refreshDemoDataForStocksToggle()
            } else {
                Task {
                    await BrokeragePortfolioDataService.shared.onStocksFeatureEnabled()
                    await MainActor.run {
                        let tickers = BrokeragePortfolioDataService.shared.trackedTickers
                        if !tickers.isEmpty && LiveStockPriceManager.shared.liveUpdatesEnabled {
                            LiveStockPriceManager.shared.setTickers(tickers, source: "portfolio")
                            LiveStockPriceManager.shared.reapplyPollingPreferences()
                        }
                    }
                }
            }
        } else {
            if isInDemoMode {
                portfolioViewModel.refreshDemoDataForStocksToggle()
            } else {
                Task { @MainActor in
                    LiveStockPriceManager.shared.setTickers([], source: "portfolio")
                    LiveStockPriceManager.shared.stopPolling()
                    BrokeragePortfolioDataService.shared.onStocksFeatureDisabled()
                }
            }
        }
    }
}

// MARK: - Legacy Stock Settings Sub-Section (kept for backwards compatibility)

/// Sub-settings for stock portfolio features - legacy, use StocksSettingsSection instead
private struct StockSettingsSubSection: View {
    let selectionFeedback: UISelectionFeedbackGenerator
    
    @Environment(\.colorScheme) private var colorScheme
    
    @AppStorage("liveStockUpdatesEnabled") private var liveUpdatesEnabled: Bool = true
    @AppStorage("stockPollingMarketHoursOnly") private var marketHoursOnly: Bool = false
    @AppStorage("showStockLogos") private var showStockLogos: Bool = true
    @AppStorage("includeStocksInPieChart") private var includeStocksInPieChart: Bool = true
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        EmptyView() // Deprecated - use StocksSettingsSection
    }
    
    @ViewBuilder
    private func stockToggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AssetType.stock.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
                .scaleEffect(0.85)
                .onChange(of: isOn.wrappedValue) { _, _ in
                    selectionFeedback.selectionChanged()
                }
        }
        .padding(.vertical, 6)
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
