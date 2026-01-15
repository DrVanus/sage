// NOTE: ATS keys are provided via App/Info.plist; set target Build Settings -> Info.plist File to App/Info.plist if using a generated plist.

import SwiftUI
import UIKit
import Combine
// Feature flags for scaling/text hacks
private let __ForceLargeTextOnPhone__ = true
private let __NormalizePhoneScale__ = false
private let __PrewarmHeavyTabs__ = false
private let __IdlePrewarmHeavyTabs__ = true

@main
struct CryptoSageAIApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: AppState
    @StateObject private var marketVM: MarketViewModel
    @StateObject private var portfolioVM: PortfolioViewModel
    @StateObject private var newsVM: CryptoNewsFeedViewModel
    @StateObject private var segmentVM: MarketSegmentViewModel
    @StateObject private var dataModeManager: DataModeManager
    @StateObject private var homeVM: HomeViewModel
    @StateObject private var chatVM: ChatViewModel
    @StateObject private var biometricAuth = BiometricAuthManager.shared
    @StateObject private var securityManager = SecurityManager.shared
    private let secureDataManager = SecureUserDataManager.shared
    private let screenProtection = ScreenProtectionManager.shared
    @State private var reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled
    @State private var showSplash: Bool = true
    @State private var didStartLoading: Bool = false

    @AppStorage("App.Appearance") private var appAppearanceRaw: String = "system"

    private var rootPreferredScheme: ColorScheme? {
        switch appAppearanceRaw {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    init() {
        // Initialize crash reporting first (must be early for crash capture)
        CrashReportingService.shared.setup()
        
        let appState = AppState()
        let marketVM = MarketViewModel.shared
        let dm = DataModeManager()
        let homeVM = HomeViewModel()
        let chatVM = ChatViewModel()
        _appState = StateObject(wrappedValue: appState)
        _marketVM = StateObject(wrappedValue: marketVM)
        _dataModeManager = StateObject(wrappedValue: dm)
        _homeVM = StateObject(wrappedValue: homeVM)
        _chatVM = StateObject(wrappedValue: chatVM)
        
        // Initialize screen protection (blur in app switcher - like Coinbase/Binance)
        ScreenProtectionManager.shared.setup()

        let manualService = ManualPortfolioDataService()
        let liveService   = LivePortfolioDataService()
        let priceService  = CoinGeckoPriceService()
        let repository    = PortfolioRepository(
            manualService: manualService,
            liveService:   liveService,
            priceService:  priceService
        )
        _portfolioVM = StateObject(
            wrappedValue: PortfolioViewModel(repository: repository)
        )

        _newsVM = StateObject(wrappedValue: CryptoNewsFeedViewModel.shared)
        _segmentVM = StateObject(wrappedValue: MarketSegmentViewModel())

        // Migrate legacy appearance keys to unified App.Appearance so the whole app follows Settings
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "App.Appearance") == nil {
            if defaults.object(forKey: "Settings.DarkMode") != nil {
                let dark = defaults.bool(forKey: "Settings.DarkMode")
                defaults.set(dark ? "dark" : "light", forKey: "App.Appearance")
            } else if defaults.object(forKey: "isDarkMode") != nil {
                let old = defaults.bool(forKey: "isDarkMode")
                defaults.set(old, forKey: "Settings.DarkMode")
                defaults.set(old ? "dark" : "light", forKey: "App.Appearance")
            }
        }

        // Global navigation bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor.black
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().tintColor = .white
        
        // Heavy loading moved to onAppear for faster splash display
    }
    
    /// Start heavy loading tasks - called after splash is visible
    private func startHeavyLoading() {
        // STAGGERED STARTUP: Reduce network request storm on fresh install
        // Phase 1 (immediate): Load cached data, then prefetch coin logos
        Task {
            await marketVM.loadAllData()
            await CoinLogoPrefetcher.shared.prefetchTopCoins(count: 50)
        }
        
        // Phase 2 (0.5s): Ensure live price polling is active after initial UI renders
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            LivePriceManager.shared.startPolling(interval: 60)
        }
        
        // Phase 3 (1.0s): Prewarm sentiment after main data loads
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await ExtendedFearGreedViewModel.prewarm()
        }
        
        // Phase 4 (2.0s): Non-critical compliance detection last
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            ComplianceManager.shared.detectUserCountry { _ in }
        }
        
        // Phase 5 (2.5s): Start price alert monitoring if alerts exist
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if NotificationsManager.shared.hasActiveAlerts {
                NotificationsManager.shared.requestAuthorization()
                NotificationsManager.shared.startMonitoring()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                TabView(selection: $appState.selectedTab) {
                NavigationStack(path: $appState.homeNavPath) {
                    HomeView(selectedTab: $appState.selectedTab)
                }
                .tag(CustomTab.home)

                NavigationStack(path: $appState.marketNavPath) {
                    MarketView()
                }
                .tag(CustomTab.market)

                LazyView(NavigationStack(path: $appState.tradeNavPath) { TradeView() })
                .tag(CustomTab.trade)

                NavigationStack(path: $appState.portfolioNavPath) {
                    PortfolioView()
                }
                .tag(CustomTab.portfolio)

                LazyView(NavigationStack(path: $appState.aiNavPath) { AITabView() })
                .tag(CustomTab.ai)
            }
            .transaction { tx in tx.animation = nil }
            .animation(nil, value: appState.selectedTab)
            .toolbar(.hidden, for: .tabBar)
            .overlay(
                OffscreenPrewarm()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
            .accentColor(DS.Adaptive.textPrimary)
            .safeAreaInset(edge: .bottom) {
                CustomTabBar(selectedTab: $appState.selectedTab)
                    .background(
                        DS.Adaptive.background
                            .ignoresSafeArea(edges: .bottom)
                    )
                    .animation(nil, value: appState.selectedTab)
            }
            .applyIf(rootPreferredScheme != nil) { view in
                view.toolbarColorScheme(rootPreferredScheme!, for: .navigationBar)
            }
            .environmentObject(appState)
            .environmentObject(marketVM)
            .environmentObject(portfolioVM)
            .environmentObject(newsVM)
            .environmentObject(segmentVM)
            .environmentObject(dataModeManager)
            .environmentObject(homeVM)
            .environmentObject(chatVM)
            .preferredColorScheme(rootPreferredScheme)
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)) { _ in
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async { reduceMotion = UIAccessibility.isReduceMotionEnabled }
            }
            // Optional: Force large text size on iPhone (disabled by default to avoid layout widening)
            .applyIf(__ForceLargeTextOnPhone__) { view in
                view.forcePhoneTextCategory(.large)
            }
            // Optional: Normalize iPhone scale (disabled by default as it can stretch content)
            .applyIf(__NormalizePhoneScale__) { view in
                view.normalizePhoneScale()
            }
                
                // Splash screen overlay
                if showSplash {
                    SplashScreenView()
                        .transition(.opacity.animation(.easeOut(duration: 0.4)))
                        .zIndex(1)
                }
                
                // Security warning banner (jailbreak detection, etc.)
                if !showSplash && !biometricAuth.isLocked {
                    VStack {
                        SecurityWarningBanner()
                            .padding(.top, 8)
                        Spacer()
                    }
                    .zIndex(1.5)
                    .allowsHitTesting(true)
                }
                
                // Biometric lock screen overlay (shows after splash if biometric is enabled)
                if !showSplash && biometricAuth.isBiometricEnabled && biometricAuth.isLocked {
                    LockScreenView(authManager: biometricAuth)
                        .transition(.opacity.animation(.easeOut(duration: 0.3)))
                        .zIndex(2)
                }
            }
            .task {
                // Guard against multiple triggers that cause cascading state updates
                guard !didStartLoading else { return }
                didStartLoading = true
                
                // Start analytics session
                AnalyticsService.shared.startSession()
                
                // Start heavy loading NOW (splash is visible)
                startHeavyLoading()
                
                // Show splash for 2.5 seconds then fade to app
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // App-level scene phase handling for global data freshness and security
                DispatchQueue.main.async {
                    switch newPhase {
                    case .active:
                        // Analytics: Track app foreground
                        AnalyticsService.shared.appDidBecomeActive()
                        // Reset staleness tracking to ensure fresh percentage derivation
                        LivePriceManager.shared.clearAllSidecarCaches()
                        // Force a fresh data fetch
                        Task { await marketVM.loadAllData() }
                        // Check if we should auto-lock based on timeout
                        if securityManager.shouldAutoLock() {
                            biometricAuth.lockApp()
                        }
                    case .background:
                        // Analytics: Track app background
                        AnalyticsService.shared.appDidEnterBackground()
                        // Track when app went to background for auto-lock timeout
                        securityManager.appDidEnterBackground()
                        // Clear sensitive data from memory for extra security
                        secureDataManager.clearMemoryCaches()
                        // Immediate lock if biometric enabled (can be changed to timeout-only)
                        biometricAuth.lockApp()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
            }
            .onChange(of: appState.selectedTab) { _, newTab in
                // Analytics: Track tab switches
                AnalyticsService.shared.trackTabSelection(newTab.rawValue)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var selectedTab: CustomTab = .home
    @Published var isDarkMode: Bool = true
    
    // Navigation paths for pop-to-root functionality
    @Published var homeNavPath = NavigationPath()
    @Published var marketNavPath = NavigationPath()
    @Published var tradeNavPath = NavigationPath()
    @Published var portfolioNavPath = NavigationPath()
    @Published var aiNavPath = NavigationPath()
    
    /// Trigger to dismiss legacy NavigationLink-based subviews in Home tab
    /// Sub-views should observe this and call dismiss() when it becomes true
    @Published var dismissHomeSubviews: Bool = false
    
    /// Track keyboard visibility for hiding tab bar in AI Chat
    @Published var isKeyboardVisible: Bool = false
}

extension View {
    /// Force large font category for iPhones as default for consistent UI scaling.
    /// NOTE: This is a temporary hack until improved UI scaling is implemented.
    func forcePhoneTextCategory(_ category: ContentSizeCategory) -> some View {
        self.environment(\.sizeCategory,
                         UIDevice.current.userInterfaceIdiom == .phone ? category : .medium)
    }
}

extension View {
    /// Conditionally applies a transform to a view without shadowing Swift's `if`.
    @ViewBuilder
    func applyIf<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

/// Normalizes unexpected iPhone scaling by reading the live window size/scale
/// and applying a compensating transform so the app renders at standard points.
private struct PhoneScaleNormalizer: ViewModifier {
    @State private var scale: CGFloat = 1
    @State private var logged = false

    func body(content: Content) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            content
                .scaleEffect(scale, anchor: .topLeading)
                .background(
                    GeometryReader { _ in
                        Color.clear.onAppear { computeScaleIfNeeded() }
                    }
                )
        } else {
            content
        }
        #else
        content
        #endif
    }

    private func computeScaleIfNeeded() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let win = scene.windows.first else { return }
        let bounds = win.bounds.size
        let nativeScale = UIScreen.main.nativeScale
        let scale = UIScreen.main.scale
        let expectedWidthPoints: CGFloat = expectedStandardWidth()
        let measuredWidthPoints = bounds.width
        let factor = expectedWidthPoints > 0 ? (expectedWidthPoints / measuredWidthPoints) : 1
        if !logged {
            print("[Normalize] bounds=\(Int(bounds.width))x\(Int(bounds.height))@\(scale)x nativeScale=\(nativeScale) expectedWidth=\(expectedWidthPoints) factor=\(factor))")
        }
        // Only apply if off by more than ~10%
        if abs(1 - factor) > 0.10 {
            self.scale = factor
        } else {
            self.scale = 1
        }
    }

    private func expectedStandardWidth() -> CGFloat {
        // Coarse mapping by device class. Modern iPhones in Standard display
        // generally report these logical widths in points.
        let nativeH = UIScreen.main.nativeBounds.height
        // Use height to distinguish classes (portrait at launch)
        switch nativeH {
        case 2796, 2868, 3000, 3024: // Pro/Max classes (approx buckets across gens)
            return 430 // iPhone Pro Max logical width
        case 2556, 2622, 2658, 2700: // Pro / standard tall
            return 393 // iPhone Pro/15/16 logical width
        case 2340, 2532, 2556 - 300: // older tall buckets
            return 390 // fallback for tall phones
        default:
            return 390 // safe default for most recent non‑Max
        }
    }
}

extension View {
    /// Apply a compensating scale so iPhone renders at standard logical size
    /// even if the device reports a zoomed/atypical point width.
    func normalizePhoneScale() -> some View {
        self.modifier(PhoneScaleNormalizer())
    }
}

private struct LazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) { self.build = build }
    var body: some View { build() }
}

// MARK: - Splash Screen
private struct SplashScreenView: View {
    @State private var glowPulse: Double = 1.0
    @State private var logoScale: Double = 1.0
    
    private let goldColor = Color(red: 0.831, green: 0.686, blue: 0.216)
    private let subtitleColor = Color(red: 0.6, green: 0.5, blue: 0.35)
    private let backgroundColor = Color(red: 0.075, green: 0.067, blue: 0.063)
    
    private let logoSize: CGFloat = 145
    
    var body: some View {
        ZStack {
            // Background - matched to logo's inner dark color
            backgroundColor.ignoresSafeArea()
            
            // Gold glow behind logo
            RadialGradient(
                gradient: Gradient(colors: [
                    goldColor.opacity(0.55),
                    goldColor.opacity(0.3),
                    goldColor.opacity(0.1),
                    Color.clear
                ]),
                center: .center,
                startRadius: 40,
                endRadius: 200
            )
            .frame(width: 400, height: 400)
            .scaleEffect(glowPulse)
            .offset(y: -55)
            
            // Content
            VStack(spacing: 0) {
                Spacer()
                
                // Logo - clean display
                Image("LaunchLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: logoSize, height: logoSize)
                    .scaleEffect(logoScale)
                    .shadow(color: goldColor.opacity(0.6), radius: 35, x: 0, y: 0)
                
                // App name
                Text("CryptoSage")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(goldColor)
                    .shadow(color: goldColor.opacity(0.5), radius: 12, x: 0, y: 0)
                    .padding(.top, 24)
                
                // Subtitle
                Text("AI-Powered Trading")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(subtitleColor)
                    .tracking(0.5)
                    .padding(.top, 8)
                
                Spacer()
                
                // Loading indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: goldColor))
                    .scaleEffect(1.2)
                    .padding(.bottom, 65)
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                // Glow pulse animation
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    glowPulse = 1.1
                }
                
                // Subtle logo breathing
                withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                    logoScale = 1.02
                }
            }
        }
    }
}

private struct OffscreenPrewarm: View {
    @State private var didLayout = false
    @State private var prewarmMarket = false
    @State private var prewarmTrade = false
    @State private var prewarmPortfolio = false
    @State private var prewarmAI = false

    var body: some View {
        Group {
            if didLayout {
                EmptyView()
            } else {
                GeometryReader { proxy in
                    ZStack {
                        if prewarmMarket {
                            MarketView()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .offset(y: proxy.size.height * 2)
                        }
                        if prewarmTrade {
                            TradeView()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .offset(y: proxy.size.height * 3)
                        }
                        if prewarmPortfolio {
                            PortfolioView()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .offset(y: proxy.size.height * 4)
                        }
                        if prewarmAI {
                            AITabView()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .offset(y: proxy.size.height * 5)
                        }
                    }
                    .opacity(0.01)
                    .onAppear {
                        // Stagger prewarm to avoid a single-frame layout spike.
                        // Only prewarm heavy tabs (Trade, AI) when enabled, or lightly after idle.
                        let heavy = __PrewarmHeavyTabs__
                        let idleHeavy = __IdlePrewarmHeavyTabs__
                        DispatchQueue.main.async { prewarmMarket = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { prewarmPortfolio = true }
                        if heavy {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { prewarmTrade = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { prewarmAI = true }
                            // After a short delay, drop the views so they stop consuming resources
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) { didLayout = true }
                        } else if idleHeavy {
                            // Idle prewarm: wait a moment so Home/Market settle, then lightly warm heavy tabs
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.90) { prewarmTrade = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.00) { prewarmAI = true }
                            // Release shortly after to free resources
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { didLayout = true }
                        } else {
                            // No heavy prewarm; release earlier
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { didLayout = true }
                        }
                    }
                }
            }
        }
    }
}

