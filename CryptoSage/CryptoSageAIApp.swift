// NOTE: ATS keys are provided via App/Info.plist; set target Build Settings -> Info.plist File to App/Info.plist if using a generated plist.

import SwiftUI
import UIKit
import Combine
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import BackgroundTasks

// MARK: - Memory Emergency Notification
extension Notification.Name {
    /// Posted by the memory watchdog when critical threshold is hit.
    /// HomeView observes this to strip all sections to portfolio + footer only.
    static let memoryEmergencySectionsStrip = Notification.Name("memoryEmergencySectionsStrip")
}

// MARK: - Memory Diagnostics
/// Returns current process memory in MB (internal so HomeView can use for phase diagnostics)
func currentMemoryMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    if result == KERN_SUCCESS {
        return Double(info.resident_size) / (1024 * 1024)
    }
    return 0
}

private func logMemory(_ label: String) {
    let mb = currentMemoryMB()
    print("🧠 MEMORY [\(label)]: \(String(format: "%.1f", mb)) MB")
}

/// Returns system-reported available memory in MB (how much headroom before jetsam kills us)
private func availableMemoryMB() -> Double {
    return Double(os_proc_available_memory()) / (1024 * 1024)
}
// Feature flags for scaling/text hacks
private let __ForceLargeTextOnPhone__ = true
private let __NormalizePhoneScale__ = false
// PERFORMANCE: Disabled prewarming - it causes memory/CPU spikes on launch
// Heavy tabs (Trade, AI) are now loaded lazily when user navigates to them
private let __PrewarmHeavyTabs__ = false
private let __IdlePrewarmHeavyTabs__ = false

// FIX: Provide a minimal UIApplicationDelegate so Firebase/Google Analytics
// no longer warns "App Delegate does not conform to UIApplicationDelegate protocol".
// Also handles Google Sign-In URL callback properly.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }
    
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

@main
struct CryptoSageAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: AppState
    @StateObject private var marketVM: MarketViewModel
    @StateObject private var portfolioVM: PortfolioViewModel
    @StateObject private var newsVM: CryptoNewsFeedViewModel
    // PERFORMANCE FIX: Removed segmentVM and dataModeManager from root @StateObject / .environmentObject.
    // No views in the app consume these via @EnvironmentObject, so injecting them at root
    // caused unnecessary environment propagation overhead without benefit.
    @StateObject private var homeVM: HomeViewModel
    @StateObject private var chatVM: ChatViewModel
    @StateObject private var biometricAuth = BiometricAuthManager.shared
    @StateObject private var securityManager = SecurityManager.shared
    private let secureDataManager = SecureUserDataManager.shared
    @State private var reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled
    @State private var appReady: Bool = false   // LAUNCH FIX: TabView is NOT built until this flips true
    @State private var didStartLoading: Bool = false
    @State private var showStartupSurface: Bool = true
    @State private var startupSurfaceShownAt: Date = Date()
    @State private var didStartRealtimePipeline: Bool = false
    @State private var showPeriodicUpgrade: Bool = false
    @State private var startupRecoveryMode: Bool = false
    @State private var lastForegroundLoadAt: Date = .distantPast
    @State private var lastForegroundEventAt: Date = .distantPast
    // PERFORMANCE v26: Increased from 30s to 60s. Firestore real-time listener keeps data
    // fresh between foreground events, so full reloads are only needed after extended background.
    // This prevents rapid foreground/background cycles from hammering APIs and clearing caches.
    private let foregroundLoadCooldown: TimeInterval = 60
    // PERF: Minimum interval between foreground events for lightweight operations (analytics, coordinator).
    // ScreenProtection activate/deactivate cycles cause rapid .active pulses that flood the console.
    private let foregroundEventCooldown: TimeInterval = 20
    
    // NOTE: Removed layoutRefreshID - it was causing navigation state reset on lock/unlock
    // Layout stability is now handled by .monitorLayoutStability() without destroying nav stacks
    @State private var isTransitioningFromLock: Bool = false
    
    // Onboarding: shown once on first launch
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    @AppStorage("App.Appearance") private var appAppearanceRaw: String = "dark"

    private var rootPreferredScheme: ColorScheme? {
        switch appAppearanceRaw {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    init() {
        print("🔨🔨🔨 BUILD v5.0.15 - ROBUST RELAUNCH + CLEAN SHUTDOWN GUARD 🔨🔨🔨")
        logMemory("APP INIT START")
        
        // ════════════════════════════════════════════════════════════
        // RELAUNCH FIX v5.0.15: FOUR-LAYER STARTUP GUARD
        //
        // ROOT CAUSE: "Can't get back in after crash/quit unless fresh install"
        //
        // The old crash guard only purged 8 cache files from Documents/
        // and was only armed for 45 seconds. This missed:
        //   - Force-quits (no lifecycle callback → guard already cleared)
        //   - Firestore persistent SQLite cache (Library/)
        //   - URLCache disk data, image caches
        //
        // NEW FIX: Four-layer defense:
        //
        // 1. CRASH GUARD: If the app crashed during startup (flag never cleared),
        //    do a comprehensive purge including Firestore cache.
        //
        // 2. CLEAN SHUTDOWN GUARD: Track whether the app went to background
        //    cleanly. Force-quits skip background → flag stays false → purge.
        //
        // 3. BUILD CHANGE DETECTION: Binary changed → purge.
        //
        // 4. OVERSIZED FILE CHECK: Always check for bloated caches.
        //
        // 5. CONSECUTIVE FAILURE ESCALATION: If the app fails to survive
        //    3 launches in a row, do a nuclear reset of ALL persistent state.
        // ════════════════════════════════════════════════════════════
        
        let defaults = UserDefaults.standard
        
        // ── Layer 1: Crash Guard ──
        let crashGuardKey = "AppStartupCrashGuard"
        let previousLaunchCrashed = defaults.bool(forKey: crashGuardKey)
        
        // Arm the crash guard NOW. Cleared after 20s of stable runtime.
        defaults.set(true, forKey: crashGuardKey)
        
        _startupRecoveryMode = State(initialValue: false)
        defaults.set(false, forKey: "StartupSafeModeEnabled")
        
        // ── Layer 2: Clean Shutdown Guard ──
        // "Clean shutdown" is set when the app transitions to .background.
        // Force-quit skips .background → flag stays false → triggers purge.
        // First-ever launch has no key → treat as clean (nothing to purge).
        let cleanShutdownKey = "AppCleanShutdown"
        let hasLaunchedBeforeKey = "AppHasLaunchedBefore"
        let hasLaunchedBefore = defaults.bool(forKey: hasLaunchedBeforeKey)
        let wasCleanShutdown = defaults.bool(forKey: cleanShutdownKey)
        
        // Mark as NOT clean immediately. Only set true when going to background.
        defaults.set(false, forKey: cleanShutdownKey)
        defaults.set(true, forKey: hasLaunchedBeforeKey)
        
        let wasDirtyShutdown = hasLaunchedBefore && !wasCleanShutdown && !previousLaunchCrashed
        
        // ── Layer 5 (checked first): Consecutive Failure Escalation ──
        let failCountKey = "AppConsecutiveFailCount"
        var consecutiveFailures = defaults.integer(forKey: failCountKey)

        // DIRTY SHUTDOWN TUNING: In DEBUG, Xcode stop/run cycles often terminate without
        // a background transition, which appears as a "dirty" shutdown but is not a real
        // user-facing abnormal termination. Keep strict behavior in non-DEBUG builds.
        #if DEBUG
        let shouldCountDirtyShutdownAsFailure = false
        #else
        let shouldCountDirtyShutdownAsFailure = true
        #endif
        
        if previousLaunchCrashed || (wasDirtyShutdown && shouldCountDirtyShutdownAsFailure) {
            consecutiveFailures += 1
            defaults.set(consecutiveFailures, forKey: failCountKey)
        }
        
        // Track whether we need to clear Firestore cache AFTER FirebaseApp.configure().
        // (Firestore.firestore() requires Firebase to be initialized first.)
        var needsFirestoreCacheClear = false
        
        if consecutiveFailures >= 3 {
            // NUCLEAR RESET: App has failed 3+ times in a row.
            // This replicates what "delete and reinstall" does.
            print("🚨 [NUCLEAR RESET] \(consecutiveFailures) consecutive failures — full state reset")
            CryptoSageAIApp.purgeAllCacheFiles()
            CryptoSageAIApp.clearAllTransientCaches()
            needsFirestoreCacheClear = true
            defaults.set(0, forKey: failCountKey)
        } else if previousLaunchCrashed {
            print("⚠️ [CRASH GUARD] Previous launch crashed — comprehensive purge (fail #\(consecutiveFailures))")
            CryptoSageAIApp.purgeAllCacheFiles()
            needsFirestoreCacheClear = true
        } else if wasDirtyShutdown && shouldCountDirtyShutdownAsFailure {
            print("⚠️ [DIRTY SHUTDOWN] App was force-quit or killed — purging caches (fail #\(consecutiveFailures))")
            CryptoSageAIApp.purgeAllCacheFiles()
            needsFirestoreCacheClear = true
        } else if wasDirtyShutdown {
            #if DEBUG
            print("ℹ️ [DIRTY SHUTDOWN] Detected during DEBUG run cycle — skipping purge")
            #endif
        }
        
        // ── Layer 3: Build Change Detection ──
        let buildDateKey = "LastBinaryBuildDate"
        let currentBuildDate: String = {
            guard let execURL = Bundle.main.executableURL,
                  let attrs = try? FileManager.default.attributesOfItem(atPath: execURL.path),
                  let date = attrs[.modificationDate] as? Date else { return "unknown" }
            return "\(date.timeIntervalSince1970)"
        }()
        let lastBuildDate = defaults.string(forKey: buildDateKey)
        if lastBuildDate != currentBuildDate {
            defaults.set(currentBuildDate, forKey: buildDateKey)
            if lastBuildDate != nil {
                #if DEBUG
                // Keep startup warm in iterative debug runs.
                // Full purge on every rebuild erases fast-start caches and makes
                // Home/Watchlist feel cold on nearly every launch.
                print("ℹ️ [BUILD CHANGE] Binary changed — preserving warm caches in DEBUG")
                #else
                print("🔄 [BUILD CHANGE] Binary changed — purging all caches for clean start")
                CryptoSageAIApp.purgeAllCacheFiles()
                needsFirestoreCacheClear = true
                #endif
            }
        }
        
        // ── Layer 4: Oversized File Check ──
        CryptoSageAIApp.purgeBloatedCacheFiles()
        
        // MEMORY FIX v14: Cap URLCache to 4 MB memory / 20 MB disk. The default can grow
        // much larger and accumulate JSON responses from frequent API polling (CoinGecko,
        // Firebase, Binance, Coinbase). This is cleared on every memory warning.
        URLCache.shared = URLCache(memoryCapacity: 4 * 1024 * 1024,
                                    diskCapacity: 20 * 1024 * 1024)
        
        // PERFORMANCE FIX: Firebase must be configured early, but we yield immediately after
        // to let the main run loop process pending UI work. This prevents a long blocking chain.
        FirebaseApp.configure()
        logMemory("After FirebaseApp.configure()")
        
        // RELAUNCH FIX v5.0.15: Clear Firestore cache AFTER Firebase is configured
        // but BEFORE any listeners start. Must happen here — Firestore.firestore()
        // requires FirebaseApp to be initialized.
        if needsFirestoreCacheClear {
            CryptoSageAIApp.clearFirestorePersistentCache()
        }
        
        // Configure Google Sign-In with Firebase client ID
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        logMemory("After Google Sign-In config")
        
        // PERFORMANCE FIX: Defer crash reporting setup to a background task
        // It doesn't need to block the main thread during init - crashes before this completes
        // will still be captured on next launch
        Task.detached(priority: .utility) {
            await MainActor.run {
                CrashReportingService.shared.setup()
            }
        }
        
        // PERFORMANCE FIX: Defer cache clearing to background to avoid blocking main thread at launch
        // Check flags synchronously (fast) but clear caches asynchronously (file I/O)
        let cacheRecoveryKey = "CacheRecoveryVersion"
        let currentRecoveryVersion = 4 // MEMORY FIX v5: Bumped to force cache cleanup
        let lastRecoveryVersion = UserDefaults.standard.integer(forKey: cacheRecoveryKey)
        let needsVersionRecovery = lastRecoveryVersion < currentRecoveryVersion
        let needsCorruptionRecovery = UserDefaults.standard.bool(forKey: "percent_cache_corrupted")
        
        if needsVersionRecovery || needsCorruptionRecovery {
            // Update flags immediately (synchronous, fast)
            if needsVersionRecovery {
                UserDefaults.standard.set(currentRecoveryVersion, forKey: cacheRecoveryKey)
            }
            UserDefaults.standard.set(false, forKey: "percent_cache_corrupted")
            
            // Defer actual file deletion to background thread
            Task {
                await CacheManager.shared.clearPercentCachesAsync()
                #if DEBUG
                print("🧹 [CryptoSageAIApp] Cleared percent caches (version recovery: \(needsVersionRecovery), corruption recovery: \(needsCorruptionRecovery))")
                #endif
            }
        }
        
        // PERFORMANCE FIX v20: Use singleton so HomeView can access specific publishers
        // without observing the entire AppState via @EnvironmentObject
        let appState = AppState.shared
        logMemory("After AppState.shared")
        let marketVM = MarketViewModel.shared
        logMemory("After MarketViewModel.shared")
        
        // FIX v24: Create a SINGLE PortfolioViewModel and share it with HomeViewModel.
        // Previously CryptoSageAIApp created its own instance (for .environmentObject) and
        // HomeViewModel created a separate one (for HomeView/PortfolioView). This caused
        // two independent portfolio instances with different price update timing — the Home
        // screen showed stale prices while AI Chat / Settings had different values.
        // Now we create one instance and pass it to HomeViewModel, ensuring consistency.
        let manualService = ManualPortfolioDataService()
        let liveService   = LivePortfolioDataService()
        // PERFORMANCE FIX: Use shared singleton to reduce API request storms
        let priceService  = CoinGeckoPriceService.shared
        let repository    = PortfolioRepository(
            manualService: manualService,
            liveService:   liveService,
            priceService:  priceService
        )
        let portfolioVM = PortfolioViewModel(repository: repository)
        logMemory("After PortfolioViewModel")
        
        let homeVM = HomeViewModel(portfolioVM: portfolioVM)
        let chatVM = ChatViewModel()
        logMemory("After HomeVM + ChatVM")
        _appState = StateObject(wrappedValue: appState)
        _marketVM = StateObject(wrappedValue: marketVM)
        _homeVM = StateObject(wrappedValue: homeVM)
        _chatVM = StateObject(wrappedValue: chatVM)
        _portfolioVM = StateObject(wrappedValue: portfolioVM)
        
        // Initialize screen protection (blur in app switcher - like Coinbase/Binance)
        ScreenProtectionManager.shared.setup()

        _newsVM = StateObject(wrappedValue: CryptoNewsFeedViewModel.shared)

        // Migrate legacy appearance keys to unified App.Appearance so the whole app follows Settings
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
        
        // Register background refresh task for price alert monitoring (lightweight, ~30s budget)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.dee.CryptoSage.priceAlertRefresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Task {
                await NotificationsManager.shared.checkAlerts()
                refreshTask.setTaskCompleted(success: true)
            }
            // Schedule the next refresh + processing pair
            CryptoSageAIApp.schedulePriceAlertBackgroundRefresh()
            CryptoSageAIApp.schedulePriceAlertBackgroundProcessing()
        }
        
        // Register background processing task (longer budget, runs when device is idle/charging)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.dee.CryptoSage.priceAlertProcessing",
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            
            // Handle expiration
            processingTask.expirationHandler = {
                processingTask.setTaskCompleted(success: false)
            }
            
            Task {
                await NotificationsManager.shared.checkAlerts()
                processingTask.setTaskCompleted(success: true)
            }
            // Reschedule
            CryptoSageAIApp.schedulePriceAlertBackgroundProcessing()
            CryptoSageAIApp.schedulePriceAlertBackgroundRefresh()
        }
        
        logMemory("APP INIT END")
        // Heavy loading moved to onAppear for faster splash display
    }
    
    /// Schedule a background app refresh for price alert checking (~30s execution budget)
    static func schedulePriceAlertBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.dee.CryptoSage.priceAlertRefresh")
        // Request execution no earlier than 15 minutes from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[CryptoSageAIApp] Scheduled background refresh for price alerts")
        } catch {
            print("[CryptoSageAIApp] Failed to schedule background price alert refresh: \(error)")
        }
    }
    
    /// Schedule a background processing task for price alerts (longer budget, ideal for thorough checks)
    static func schedulePriceAlertBackgroundProcessing() {
        let request = BGProcessingTaskRequest(identifier: "com.dee.CryptoSage.priceAlertProcessing")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // Run within 15 minutes
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[CryptoSageAIApp] Scheduled background processing for price alerts")
        } catch {
            print("[CryptoSageAIApp] Failed to schedule background price alert processing: \(error)")
        }
    }
    
    /// Start heavy loading tasks - called after splash is visible
    /// LEAN STARTUP v3.6: Only load cached data + Firestore sync at startup.
    /// Full API data, commodities, logos loaded ON-DEMAND when user navigates.
    private func startHeavyLoading() {
        guard !CryptoSageAIApp.isEmergencyStopActive() else {
            print("🛑 [Startup] Heavy loading skipped — emergency stop active")
            return
        }
        logMemory("startHeavyLoading BEGIN")

        #if targetEnvironment(simulator)
        if AppSettings.isSimulatorLimitedDataMode {
            // Simulator limited profile: keep startup stable while still loading core live data.
            APIRequestCoordinator.shared.appDidLaunch()
            Task { @MainActor in
                await marketVM.loadFromCacheOnly()
                logMemory("Phase 1 DONE (simulator cache + one-shot refresh)")
                LivePriceManager.shared.startPolling(interval: 45)
                print("🧪 [Startup] Simulator limited profile active — one-shot refresh + throttled polling")
                print("🧪 [SIM DIAGNOSTIC] profile=limited allCoins=\(marketVM.allCoins.count), coins=\(marketVM.coins.count)")
            }
            return
        } else {
            print("🧪 [Startup] Simulator full-data profile active — matching device startup path")
        }
        #endif

        APIRequestCoordinator.shared.appDidLaunch()
        let canRunNonCriticalPhase: (_ maxUsedMB: Double, _ minAvailMB: Double) -> Bool = { maxUsedMB, minAvailMB in
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return false }
            let used = currentMemoryMB()
            let avail = Double(os_proc_available_memory()) / (1024 * 1024)
            let availHealthy = avail <= 0 || avail >= minAvailMB
            return used <= maxUsedMB && availHealthy
        }
        
        // Phase 1 (0ms): Load cached data for instant UI
        Task { @MainActor in
            await marketVM.loadFromCacheOnly()
            logMemory("Phase 1 DONE (cache loaded)")
        }
        
        // Safe mode is permanently disabled — the NUKE death spiral was the real problem.
        
        // Data pipeline shortly after first paint.
        // Waiting too long here delays watchlist/section population on Home.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000) // +0.8s
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            
            // Startup pressure gate: defer live pipeline if memory is already high.
            let usedAtPhase2 = currentMemoryMB()
            let availAtPhase2 = Double(os_proc_available_memory()) / (1024 * 1024)
            if usedAtPhase2 > 700 || (availAtPhase2 > 0 && availAtPhase2 < 1500) {
                print("⚠️ [Phase 2] DEFERRED — used \(String(format: "%.0f", usedAtPhase2)) MB, avail \(String(format: "%.0f", availAtPhase2)) MB")
                // Retry after a shorter wait to avoid prolonged cold-start UI.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
                    guard !didStartRealtimePipeline else { return }
                    let usedRetry = currentMemoryMB()
                    let availRetry = Double(os_proc_available_memory()) / (1024 * 1024)
                    if usedRetry > 800 || (availRetry > 0 && availRetry < 1200) {
                        print("⚠️ [Phase 2] RETRY SKIPPED — used \(String(format: "%.0f", usedRetry)) MB, avail \(String(format: "%.0f", availRetry)) MB")
                        return
                    }
                    logMemory("Phase 2 BEGIN (retry)")
                    FirestoreMarketSync.shared.startListening()
                    didStartRealtimePipeline = true
                    // Keep a brief gap so UI remains smooth while enabling fresher data quickly.
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
                    LivePriceManager.shared.startPolling(interval: 30)
                    logMemory("Phase 2 DONE (retry)")
                }
                return
            }
            
            logMemory("Phase 2 BEGIN (Firestore + polling)")
            FirestoreMarketSync.shared.startListening()
            didStartRealtimePipeline = true
            // Keep a short stagger: enough to reduce contention, but not enough to feel stale.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            LivePriceManager.shared.startPolling(interval: 30)
            logMemory("Phase 2 DONE (Firestore + polling)")
        }
        
        // Phase 3: DISABLED — loadAllData() is redundant.
        // MEMORY FIX v5: Firestore real-time listener already provides full market data
        // via FirestoreMarketSync → LivePriceManager → MarketViewModel pipeline.
        // loadAllData() calls the CoinGecko API directly, creating a SECOND copy of
        // 250 coins that competes with Firestore data and doubles memory pressure.
        // Removing this eliminates a 60-100 MB spike at t+10s.
        
        // Phase 5: PERFORMANCE FIX v21 - WebKit prewarming REMOVED from startup.
        // ROOT CAUSE: WebKit spawns 3 heavy processes (WebContent: 2.3s, GPU: 2.3s, Networking: 12.7s)
        // that block the main thread and consume significant CPU/memory during startup.
        // Console showed: "Networking process took 12.713273 seconds to launch" and
        // "WebProcessProxy::didBecomeUnresponsive" - this directly competes with scroll rendering.
        // WebKit is now warmed ON-DEMAND via WebKitPrewarmer.shared.warmUpIfNeeded() which is
        // called when user navigates to Trade tab or CoinDetailView (the only views using WKWebView).
        // This eliminates ~15s of background process spawning that was degrading scroll performance.
        
        // Phase 5.5 (8s): Initialize stock price tracking if stocks are enabled
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            guard canRunNonCriticalPhase(1400, 1500) else {
                print("⏭️ [Phase 5.5] Deferred stock tracking due to startup memory pressure")
                return
            }
            
            // Check if stocks feature is enabled
            let showStocks = UserDefaults.standard.bool(forKey: "showStocksInPortfolio")
            guard showStocks else { return }
            
            // Sync brokerage holdings (stocks from Plaid)
            await BrokeragePortfolioDataService.shared.syncAllAccounts()
            
            // Start live stock price tracking for any existing stock holdings
            let stockTickers = BrokeragePortfolioDataService.shared.trackedTickers
            if !stockTickers.isEmpty && LiveStockPriceManager.shared.liveUpdatesEnabled {
                LiveStockPriceManager.shared.setTickers(stockTickers, source: "portfolio")
                LiveStockPriceManager.shared.reapplyPollingPreferences()
            }
        }
        
        // MEMORY FIX v4: Phases 6-11 deferred significantly further.
        // Previously these all ran within the first 18 seconds, competing for memory
        // during the critical startup window where the app was getting jetsammed.
        // Now they're staggered starting at 20s+ to let the app stabilize first.
        
        // Phase 6 (35s): Validate subscription/ad init after Home stabilization
        Task {
            try? await Task.sleep(nanoseconds: 35_000_000_000)
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            guard canRunNonCriticalPhase(1400, 1500) else {
                print("⏭️ [Phase 6] Deferred StoreKit/Ads init due to memory pressure")
                return
            }
            // Keep Home interactions smooth: if user is still on Home, defer monetization init once.
            if AppState.shared.selectedTab == .home {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            }
            await StoreKitManager.shared.loadProducts()
            await StoreKitManager.shared.updateSubscriptionStatus()
            ReceiptValidator.shared.validateOnLaunch()
            if AdManager.shared.shouldShowAds {
                AdManager.shared.allowInitializationAfterStartup()
            }
            
            // Initialize profile sync between Settings and Social
            _ = ProfileSyncManager.shared
        }
        
        // Phase 7 (25s): Prewarm sentiment data
        Task {
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            guard canRunNonCriticalPhase(1400, 1500) else { return }
            await ExtendedFearGreedViewModel.prewarm()
        }
        
        // Phase 7.2 (30s): Check CloudKit availability safely (async, non-blocking)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            guard canRunNonCriticalPhase(1400, 1500) else { return }
            await CommunityAccuracyService.shared.checkCloudKitAvailability()
        }
        
        // Phase 7.5 (35s): Prewarm trading pair cache
        Task {
            try? await Task.sleep(nanoseconds: 35_000_000_000)
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            guard canRunNonCriticalPhase(1400, 1500) else { return }
            TradingPairPickerViewModel.prewarmCache()
        }
        
        // Phase 8 (40s): Non-critical compliance detection
        Task {
            try? await Task.sleep(nanoseconds: 40_000_000_000)
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            guard canRunNonCriticalPhase(1400, 1500) else { return }
            ComplianceManager.shared.detectUserCountry { _ in }
        }
        
        // Phase 9 (45s): Start notifications monitoring
        NotificationsManager.shared.requestAuthorization()
        Task {
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            guard canRunNonCriticalPhase(1400, 1500) else { return }
            if NotificationsManager.shared.hasActiveAlerts {
                NotificationsManager.shared.startMonitoring()
            }
        }
        
        // Phase 9b (50s): Start AI Portfolio Monitor if enabled
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000_000)
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            guard canRunNonCriticalPhase(1400, 1500) else { return }
            if AIPortfolioMonitor.shared.isEnabled {
                AIPortfolioMonitor.shared.startMonitoring()
            }
        }
        
        // Phase 10 (55s): Evaluate expired AI predictions
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 55_000_000_000)
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            guard canRunNonCriticalPhase(1400, 1500) else { return }
            await PredictionAccuracyService.shared.evaluatePendingPredictions()
        }
        
        // Phase 10b (90s): Second evaluation pass
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            guard canRunNonCriticalPhase(1400, 1500) else { return }
            let pendingCount = PredictionAccuracyService.shared.storedPredictions.filter { $0.isReadyForEvaluation }.count
            if pendingCount > 0 {
                print("[CryptoSageAIApp] \(pendingCount) predictions still pending - running second evaluation pass")
                await PredictionAccuracyService.shared.evaluatePendingPredictions()
            }
        }
        
        // Phase 11 (60s): Sync community accuracy data
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
            guard canRunNonCriticalPhase(1400, 1500) else { return }
            guard CommunityAccuracyService.shared.isCloudKitAvailable else {
                print("[CryptoSageAIApp] Skipping community sync - CloudKit not available")
                return
            }
            await CommunityAccuracyService.shared.sync()
        }
    }
    
    // MARK: - Startup Cache Cleanup
    
    /// NUCLEAR OPTION: Deletes EVERY file in the Documents directory.
    /// This mimics what happens when you delete + reinstall the app.
    /// Called when the crash guard detects the previous launch crashed.
    private static func nukeDocumentsDirectory() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fm = FileManager.default
        var nuked = 0
        if let files = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for file in files {
                try? fm.removeItem(at: file)
                nuked += 1
            }
        }
        // Also clear the Caches directory (coin images, etc.)
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let cacheFiles = try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) {
            for file in cacheFiles {
                // Skip system files (e.g., Snapshots)
                let name = file.lastPathComponent
                if name.hasPrefix("com.apple") || name == "Snapshots" { continue }
                try? fm.removeItem(at: file)
                nuked += 1
            }
        }
        // Clear URLCache
        URLCache.shared.removeAllCachedResponses()
        
        // MEMORY FIX v8: Also clear UserDefaults keys that store cached data.
        // The crash guard nukes Documents/Caches but UserDefaults persists, causing
        // the app to follow the "returning user" code path on re-launch (more Firestore
        // listeners, heavier data loading). Clearing data caches (NOT auth state) ensures
        // a re-launch after crash behaves more like a fresh install.
        let cacheDefaults = [
            "cachedSuccessBySymbol",       // CoinImageView symbol cache
            "lastPercentSidecarSave",      // LivePriceManager sidecar timestamps
            "lastGlobalStatsCache",        // Cached global stats
            "heatmapTilesVersion",         // Heat map versioning
            "lastFirestoreSync",           // Firestore sync timestamps
        ]
        for key in cacheDefaults {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        print("🧹 [NUKE] Deleted \(nuked) files/directories from Documents + Caches + \(cacheDefaults.count) UserDefaults keys")
    }
    
    /// Purges ALL known cache files from the Documents directory.
    /// Called when the build binary changes (any Xcode rebuild).
    private static func purgeAllCacheFiles() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let filesToPurge = [
            "coins_cache.json",
            "sparklines_cache.json",
            "percent_cache_24h.json",
            "percent_cache_1h.json",
            "percent_cache_7d.json",
            "volume_cache.json",
            "global_stats_cache.json",
            "market_metrics_cache.json"
        ]
        var purged = 0
        for file in filesToPurge {
            let url = docs.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
                purged += 1
            }
        }
        if purged > 0 {
            print("🧹 [CryptoSageAIApp] Full cache purge: deleted \(purged) files for clean launch")
        }
    }
    
    /// RELAUNCH FIX v5.0.15: Clear Firestore's persistent SQLite cache.
    /// Firestore stores offline data in Library/. If the app crashes during a write,
    /// this cache can become inconsistent and cause failures on relaunch.
    /// clearPersistence() must be called BEFORE any Firestore operations.
    private static func clearFirestorePersistentCache() {
        // Firestore.firestore().clearPersistence() requires no active listeners.
        // At this point in init(), no listeners have been started yet.
        let db = Firestore.firestore()
        db.clearPersistence { error in
            if let error = error {
                print("⚠️ [Firestore] clearPersistence failed: \(error.localizedDescription)")
            } else {
                print("🧹 [Firestore] Persistent cache cleared successfully")
            }
        }
    }
    
    /// RELAUNCH FIX v5.0.15: Clear all transient caches for nuclear reset.
    /// This mimics what "delete and reinstall" achieves for cached data.
    private static func clearAllTransientCaches() {
        // URLCache
        URLCache.shared.removeAllCachedResponses()
        
        // Library/Caches directory
        if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil) {
                var cleared = 0
                for item in contents {
                    // Skip system-managed directories
                    let name = item.lastPathComponent
                    if name == "Snapshots" { continue }
                    try? fm.removeItem(at: item)
                    cleared += 1
                }
                if cleared > 0 {
                    print("🧹 [Nuclear] Cleared \(cleared) items from Library/Caches")
                }
            }
        }
        
        // tmp directory
        let tmpDir = NSTemporaryDirectory()
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: tmpDir) {
            for item in contents {
                try? FileManager.default.removeItem(atPath: (tmpDir as NSString).appendingPathComponent(item))
            }
            if !contents.isEmpty {
                print("🧹 [Nuclear] Cleared \(contents.count) items from tmp/")
            }
        }
    }
    
    /// Checks cache file sizes on EVERY launch and deletes any that are too large.
    /// This catches caches that grew during a previous session and would cause
    /// a memory spike when decoded at startup.
    ///
    /// This is WHY the app crashes after a rebuild but works after delete+reinstall:
    /// Xcode preserves the app's Documents directory between installs. A previous build
    /// may have saved a coins_cache.json with 250 coins (1.7 MB), which when decoded
    /// creates a ~10 MB in-memory representation. Combined with Firebase init (~30 MB),
    /// this pushes the app over the jetsam limit before any views appear.
    private static func purgeBloatedCacheFiles() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let coinsLimit = AppSettings.isSimulatorLimitedDataMode ? 1_500_000 : 900_000
        let sparklineLimit = AppSettings.isSimulatorLimitedDataMode ? 500_000 : 300_000
        let sizeLimits: [(String, Int)] = [
            ("coins_cache.json", coinsLimit),      // keep warm coin cache; avoid cold-start repopulation churn
            ("sparklines_cache.json", sparklineLimit),
            ("percent_cache_24h.json", 50_000),   // ~300 entries ≈ 20 KB
            ("percent_cache_1h.json", 50_000),
            ("percent_cache_7d.json", 50_000),
            ("volume_cache.json", 50_000),
        ]
        
        var purged = 0
        for (file, maxSize) in sizeLimits {
            let url = docs.appendingPathComponent(file)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int,
               size > maxSize {
                print("🧹 [Cache] \(file) is \(size / 1024) KB (limit: \(maxSize / 1024) KB) — deleting")
                try? FileManager.default.removeItem(at: url)
                purged += 1
            }
        }
        if purged > 0 {
            print("🧹 [CryptoSageAIApp] Purged \(purged) oversized cache files at startup")
        } else {
            print("✅ [CryptoSageAIApp] All cache files within size limits")
        }
    }
    
    // MARK: - Memory Management (Static to avoid capturing self)
    
    /// Executes heavy memory cleanup on main and waits briefly for completion when called off-main.
    /// This avoids purely fire-and-forget cleanup during jetsam pressure.
    private static func runMainPressureCleanup(emergencyTrim: Bool) {
        let cleanupBlock = {
            LivePriceManager.shared.stopPolling()
            LivePriceManager.shared.handleMemoryWarning()
            LiveChangeService.shared.clearAllSynchronously()
            if emergencyTrim {
                MarketViewModel.shared.emergencyTrimAllData()
            } else {
                MarketViewModel.shared.trimMemory()
            }
        }
        
        if Thread.isMainThread {
            cleanupBlock()
            return
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            cleanupBlock()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1.0)
    }
    
    /// Clears transient caches to free RAM.
    /// CRITICAL FIX: Do NOT clear CoinImageView caches here. Clearing image caches forces
    /// every visible CoinImageView/CachingAsyncImage to re-download its image from the network.
    /// This allocates MORE memory (URLSession buffers + image decoders) than the cache itself used,
    /// creating a feedback loop: cleanup → re-download → more memory → cleanup → repeat.
    /// The logs showed "freed -36 MB" (negative = grew) because of this exact loop.
    private static func handleMemoryWarning() {
        let mb = currentMemoryMB()
        let avail = availableMemoryMB()
        print("🚨 MEMORY WARNING: \(String(format: "%.0f", mb)) MB used, \(String(format: "%.0f", avail)) MB available")
        
        // MEMORY FIX v13: Skip cleanup if already in emergency mode.
        // Repeated cleanup calls trigger @Published objectWillChange → SwiftUI re-renders
        // → ~40 MB of new allocations per cycle (the "freed -40 MB" in logs).
        if hasTriggeredEmergencyStop {
            print("🧠 MEMORY: Already in emergency mode — skipping redundant cleanup")
            return
        }
        
        // Clear transient caches only (NOT image caches — those cause re-download storms)
        CacheManager.shared.clearMemoryCache()
        URLCache.shared.removeAllCachedResponses()
        MarketViewModel._cachedBundledCoins = nil
        
        runMainPressureCleanup(emergencyTrim: false)
        
        let mbAfter = currentMemoryMB()
        print("🧠 MEMORY after cleanup: \(String(format: "%.0f", mbAfter)) MB (freed \(String(format: "%.0f", mb - mbAfter)) MB)")
    }
    
    /// Background watchdog that monitors memory and triggers cleanup before iOS kills us.
    /// Uses os_proc_available_memory() on device (actual jetsam metric).
    /// Falls back to absolute memory thresholds on simulator where os_proc_available_memory() returns 0.
    ///
    /// MEMORY FIX v7: Uses GCD DispatchSourceTimer instead of Task { @MainActor in }.
    /// The previous implementation used Swift Concurrency (Task.sleep on @MainActor), which
    /// runs on the cooperative thread pool. When the main actor was saturated with SwiftUI
    /// rendering tasks, Combine sink Tasks, and .task modifier Tasks, the watchdog's Task
    /// could NEVER resume — the cooperative executor never yielded back to it.
    /// This meant: (1) no memory diagnostics, (2) no cleanup, (3) autorelease pools never
    /// drained (the run loop never iterated), causing unbounded memory growth.
    ///
    /// GCD timers fire on a KERNEL-LEVEL dispatch source, independent of Swift Concurrency.
    /// They will fire even when the main actor's cooperative queue is saturated.
    private static var watchdogTimer: DispatchSourceTimer?
    private static var watchdogTick: Int = 0
    private static var watchdogStartedAt: Date = .distantPast
    // FIX v14: Guard against queuing multiple autoreleasepool drain closures.
    // When the main thread is busy (heavy SwiftUI rendering, tab transitions),
    // these DispatchQueue.main.async closures queue up without executing.
    // Each queued closure retains context and contributes to ~0.47 MB/s leak.
    private static var isWatchdogDrainPending = false
    
    private static func startMemoryWatchdog() {
        print("🐕 MEMORY WATCHDOG: Starting (GCD timer)...")
        watchdogStartedAt = Date()
        
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 2, repeating: 3.0)
        timer.setEventHandler {
            watchdogTick += 1
            let mb = currentMemoryMB()
            let avail = availableMemoryMB()
            let elapsed = watchdogTick * 3
            
            // Keep startup visibility, then taper logs to reduce console noise.
            if elapsed <= 12 || (elapsed <= 60 && watchdogTick % 3 == 0) || watchdogTick % 10 == 0 {
                print("🐕 WATCHDOG +\(elapsed)s: \(String(format: "%.0f", mb)) MB used, \(String(format: "%.0f", avail)) MB avail")
            }
            
            // MEMORY FIX v7: Force autorelease pool drain on main thread.
            // FIX v14: Only queue one drain at a time. If the previous closure
            // hasn't executed yet (main thread busy), skip this cycle. This
            // prevents closure accumulation that causes 0.47 MB/s memory growth.
            if !isWatchdogDrainPending {
                isWatchdogDrainPending = true
                DispatchQueue.main.async {
                    autoreleasepool {
                        // Forces drain of pending autoreleased objects on main thread.
                    }
                    isWatchdogDrainPending = false
                }
            }
            
            // MEMORY FIX v12: Run memory checks on watchdog queue, not main queue.
            // If the main thread is saturated, dispatching cleanup to main means it may
            // never execute before jetsam. Keep checks off-main so emergency stop can fire.
            checkAndCleanMemory(usedMB: mb, availMB: avail)
        }
        timer.resume()
        watchdogTimer = timer
    }
    
    /// Unified memory check used by the watchdog.
    /// When os_proc_available_memory() returns 0 (simulator), falls back to absolute thresholds.
    /// Memory watchdog thresholds.
    /// Keep this conservative enough to avoid false positives during normal runtime,
    /// while still allowing a last-resort emergency path near real OOM conditions.
    // MEMORY FIX v11: Track whether emergency stop has been triggered to prevent repeated stops
    private static var hasTriggeredEmergencyStop = false
    /// Shared hard-stop gate for services/tasks that must not run after emergency mode begins.
    static func isEmergencyStopActive() -> Bool {
        hasTriggeredEmergencyStop
    }
    // Cooldowns prevent cleanup storms that keep reallocating work every watchdog tick.
    private static var lastCriticalCleanupAt: Date = .distantPast
    private static var lastElevatedCleanupAt: Date = .distantPast
    private static var lastEarlyCleanupAt: Date = .distantPast
    private static var lastEarlyCleanupUsedMB: Double = 0
    
    private static func checkAndCleanMemory(usedMB: Double, availMB: Double) {
        // Determine if we should use absolute thresholds (simulator returns 0 for available)
        let useAbsolute = availMB <= 0
        var isCritical: Bool
        var isElevated: Bool
        // MEMORY FIX v11: Early warning — memory is growing but not yet critical.
        // At this level, extend the data pipeline freeze to prevent further growth.
        var isEarlyWarning: Bool
        
        if useAbsolute {
            // Simulator fallback: absolute thresholds only.
            isCritical = usedMB > 1700
            isElevated = usedMB > 1300
            isEarlyWarning = usedMB > 950
        } else {
            // Device mode: use both used and available memory.
            // Critical should only trigger close to genuine memory pressure.
            let availCritical = availMB > 0 && availMB < 700
            let availElevated = availMB > 0 && availMB < 1000
            let availEarly = availMB > 0 && availMB < 1300
            let usedCritical = usedMB > 1700
            let usedElevated = usedMB > 1300
            let usedEarly = usedMB > 950
            
            // Require genuinely high used memory for available-memory-based triggers.
            // This prevents false positives on high-headroom devices during normal startup.
            isCritical = usedCritical || (availCritical && usedMB > 1300)
            isElevated = usedElevated || (availElevated && usedMB > 1000)
            isEarlyWarning = usedEarly || (availEarly && usedMB > 800)
        }

        // Startup grace period: avoid escalating to emergency during normal launch ramps.
        let startupElapsed = Date().timeIntervalSince(watchdogStartedAt)
        if startupElapsed < 180, usedMB < 1200 {
            isCritical = false
            isElevated = false
        }
        
        if isCritical {
            let now = Date()
            guard now.timeIntervalSince(lastCriticalCleanupAt) >= 10 else { return }
            lastCriticalCleanupAt = now
            print("🚨🚨🚨 CRITICAL: \(String(format: "%.0f", usedMB)) MB used, \(String(format: "%.0f", availMB)) MB available - emergency memory mitigation")
            
            // After the first critical mitigation, remain in observe-only mode to avoid
            // repeated cleanup storms that can allocate additional transient memory.
            if hasTriggeredEmergencyStop {
                print("🛑 [WATCHDOG] Already in emergency mode — observe-only, skipping repeated cleanup")
                return
            }
            
            handleMemoryWarning()
            // MEMORY FIX v8: Stop Firestore listeners to halt the data pipeline.
            FirestoreMarketSync.shared.stopListening()
            // Enter emergency mode once to stop repeated mitigation loops.
            hasTriggeredEmergencyStop = true
            // MEMORY FIX v16: Kill ALL shimmer/repeatForever animations globally.
            // These are the primary source of ~8 MB/s memory growth when sparkline
            // data never arrives. Once killed, animations stay off for the session.
            globalAnimationsKilled = true
            print("🛑 [WATCHDOG] Emergency stop — halting high-churn pipeline paths")
            FavoritesManager.shared.stopFirestoreSync()
            MarketDataSyncService.shared.stopPeriodicSync()
            // Clear transient data only — NOT image caches (causes re-download storm)
            CacheManager.shared.clearMemoryCache()
            URLCache.shared.removeAllCachedResponses()
            MarketViewModel._cachedBundledCoins = nil
            MarketCacheManager.shared.clearCache()
            // Run deterministic cleanup immediately (or wait briefly if called off-main).
            runMainPressureCleanup(emergencyTrim: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let mbAfter = currentMemoryMB()
                let availAfter = availableMemoryMB()
                print("🧠 MEMORY checkpoint +0.5s: \(String(format: "%.0f", mbAfter)) MB used, \(String(format: "%.0f", availAfter)) MB available")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let mbAfter = currentMemoryMB()
                let availAfter = availableMemoryMB()
                print("🧠 MEMORY checkpoint +1.5s: \(String(format: "%.0f", mbAfter)) MB used, \(String(format: "%.0f", availAfter)) MB available")
            }
        } else if isElevated {
            let now = Date()
            guard now.timeIntervalSince(lastElevatedCleanupAt) >= 20 else { return }
            lastElevatedCleanupAt = now
            print("⚠️ ELEVATED: \(String(format: "%.0f", usedMB)) MB used, \(String(format: "%.0f", availMB)) MB available - aggressive cleanup")
            // Stop data pipeline to halt new allocations — DO NOT clear image caches
            CacheManager.shared.clearMemoryCache()
            URLCache.shared.removeAllCachedResponses()
            MarketViewModel._cachedBundledCoins = nil
            runMainPressureCleanup(emergencyTrim: false)
        } else if isEarlyWarning {
            let now = Date()
            let grownSinceLastEarly = abs(usedMB - lastEarlyCleanupUsedMB) >= 48
            guard now.timeIntervalSince(lastEarlyCleanupAt) >= 30 || grownSinceLastEarly else { return }
            lastEarlyCleanupAt = now
            lastEarlyCleanupUsedMB = usedMB
            print("⚡ EARLY WARNING: \(String(format: "%.0f", usedMB)) MB used, \(String(format: "%.0f", availMB)) MB available - light cleanup")
            // Light cleanup only — DO NOT clear image/chart caches (causes re-download feedback loop)
            CacheManager.shared.clearMemoryCache()
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Keep the first SwiftUI frame lightweight while startup services boot.
                // This avoids constructing all tab trees in the initial render pass.
                if appReady {
                TabView(selection: $appState.selectedTab) {
                // PERFORMANCE: Tabs pre-built for instant switching (splash covers init time)
                NavigationStack(path: $appState.homeNavPath) {
                    HomeView(selectedTab: $appState.selectedTab)
                        .transaction { $0.animation = nil }
                }
                .tag(CustomTab.home)
                .transaction { $0.animation = nil }

                // MEMORY FIX: Wrapped MarketView in LazyView to defer initialization.
                // MarketView renders 250+ coin rows with sparklines - deferring it until
                // the user actually navigates to the Market tab saves ~50-100 MB at launch.
                NavigationStack(path: $appState.marketNavPath) {
                    LazyView(MarketView())
                        .transaction { $0.animation = nil }
                }
                .tag(CustomTab.market)
                .transaction { $0.animation = nil }

                // PERFORMANCE FIX v22: Wrap non-essential tabs in LazyView to defer initialization.
                // Previously all 5 tabs were eagerly instantiated at launch, competing for main thread
                // time during splash. Trade, Portfolio, and AI tabs don't need to be ready until the
                // user navigates to them. This eliminates ~100ms+ of synchronous init work at launch.
                NavigationStack(path: $appState.tradeNavPath) { 
                    LazyView(TradeView())
                        .transaction { $0.animation = nil }
                }
                .tag(CustomTab.trade)
                .transaction { $0.animation = nil }

                NavigationStack(path: $appState.portfolioNavPath) {
                    LazyView(PortfolioView())
                        .transaction { $0.animation = nil }
                }
                .tag(CustomTab.portfolio)
                .transaction { $0.animation = nil }

                NavigationStack(path: $appState.aiNavPath) { 
                    LazyView(AITabView())
                        .transaction { $0.animation = nil }
                }
                .tag(CustomTab.ai)
                .transaction { $0.animation = nil }
            }
            .transaction { tx in tx.animation = nil }
            .animation(nil, value: appState.selectedTab)
            .toolbar(.hidden, for: .tabBar)
            .contentShape(Rectangle())
            // PERFORMANCE: Removed OffscreenPrewarm - tabs are now loaded lazily on navigation
            .accentColor(DS.Adaptive.textPrimary)
            // NOTE: Removed .id(layoutRefreshID) - it was destroying navigation state on lock/unlock
            // The .monitorLayoutStability() modifier handles layout recovery without resetting nav stacks
            .safeAreaInset(edge: .bottom) {
                // Hide tab bar when keyboard is visible on AI tab
                if !(appState.isKeyboardVisible && appState.selectedTab == .ai) {
                    CustomTabBar(selectedTab: $appState.selectedTab)
                        .background(
                            DS.Adaptive.background
                                .ignoresSafeArea(edges: .bottom)
                        )
                        .transaction { $0.animation = nil }
                }
            }
            .transaction { $0.animation = nil }
            .animation(.easeOut(duration: 0.2), value: appState.isKeyboardVisible)
            .applyIf(rootPreferredScheme != nil) { view in
                view.toolbarColorScheme(rootPreferredScheme!, for: .navigationBar)
            }
            .environmentObject(appState)
            .environmentObject(marketVM)
            .environmentObject(portfolioVM)
            .environmentObject(newsVM)
            // PERFORMANCE FIX: Removed .environmentObject(segmentVM) and .environmentObject(dataModeManager)
            // No views consume these via @EnvironmentObject - removing them reduces environment
            // propagation overhead that caused unnecessary view tree invalidation.
            .environmentObject(homeVM)
            .environmentObject(chatVM)
            // MARK: - First Launch Onboarding
            .sheet(isPresented: $showOnboarding) {
                WelcomeOnboardingView(isPresented: $showOnboarding)
                    .interactiveDismissDisabled()
                    .onDisappear {
                        hasSeenOnboarding = true
                    }
            }
            .onAppear {
                if !hasSeenOnboarding {
                    // Delay onboarding until startup surface has fully handed off.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                        showOnboarding = true
                    }
                }
            }
            .onOpenURL { url in
                // Handle Google Sign-In callback URL
                GIDSignIn.sharedInstance.handle(url)
            }
            .animation(nil, value: appAppearanceRaw) // Instant theme switching - no animation
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
                } else {
                    // Lightweight placeholder shown once LaunchScreen hands off to SwiftUI,
                    // until startup initialization flips appReady.
                    Color.black
                        .ignoresSafeArea(.all)
                } // END appReady gating
                
                if showStartupSurface {
                    PremiumStartupView()
                        .ignoresSafeArea(.all)
                        .transition(.opacity)
                        .zIndex(1)
                }

                // Security warning banner (jailbreak detection, etc.)
                if !showStartupSurface && !biometricAuth.isLocked {
                    VStack(spacing: 8) {
                        SecurityWarningBanner()
                            .padding(.top, 8)
                        
                        Spacer()
                    }
                    .zIndex(1.5)
                    .allowsHitTesting(true)
                }
                
                // Biometric lock screen overlay (if biometric is enabled)
                // LAYOUT STABILITY: LockScreenView now uses .ignoresSafeArea(.all) to prevent
                // interference with underlying TabView layout calculations
                if !showStartupSurface && biometricAuth.isBiometricEnabled && biometricAuth.isLocked {
                    LockScreenView(authManager: biometricAuth)
                        .transition(.opacity.animation(.easeOut(duration: 0.3)))
                        .zIndex(2)
                }
            }
            // TIMING FIX: Periodic upgrade prompt sheet is now triggered from .task
            // AFTER splash ends, instead of via .withPeriodicUpgradePrompt() which
            // fired while splash was still showing, causing a blank/glitchy screen.
            .sheet(isPresented: $showPeriodicUpgrade) {
                PeriodicUpgradePromptView {
                    showPeriodicUpgrade = false
                    PaywallManager.shared.recordPromptDismissed()
                }
            }
            .task {
                // Guard against multiple triggers that cause cascading state updates
                guard !didStartLoading else { return }
                didStartLoading = true
                startupSurfaceShownAt = Date()
                
                print("🚀 [CryptoSageAIApp] .task block starting — single launch surface")
                logMemory("TASK START")
                
                // MEMORY FIX: Register for iOS memory warning notifications
                NotificationCenter.default.addObserver(
                    forName: UIApplication.didReceiveMemoryWarningNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    CryptoSageAIApp.handleMemoryWarning()
                }
                
                // MEMORY FIX: Start memory watchdog (always active, not just DEBUG)
                CryptoSageAIApp.startMemoryWatchdog()
                
                // Give LaunchScreen -> SwiftUI handoff one short frame before heavy startup work.
                try? await Task.sleep(nanoseconds: 250_000_000)
                
                // Flip appReady once launch-critical setup is complete.
                logMemory("BEFORE appReady=true")
                appReady = true
                logMemory("AFTER appReady=true")

                // Keep premium startup surface visible long enough to feel intentional.
                let minimumSurfaceDuration: TimeInterval = 1.55
                let elapsed = Date().timeIntervalSince(startupSurfaceShownAt)
                if elapsed < minimumSurfaceDuration {
                    try? await Task.sleep(nanoseconds: UInt64((minimumSurfaceDuration - elapsed) * 1_000_000_000))
                }
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.32)) {
                        showStartupSurface = false
                    }
                }

                try? await Task.sleep(nanoseconds: 300_000_000)
                logMemory("AFTER appReady pre-heavy yield")
                
                // Start analytics session
                AnalyticsService.shared.startSession()
                
                // Record app launch for periodic prompt tracking
                PaywallManager.shared.recordAppLaunch()
                
                // Start loading data after app shell is available.
                startHeavyLoading()
                
                // Emit a single startup source summary for live-data diagnostics.
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                    let tickerFresh = FirestoreMarketSync.shared.tickerFreshness.rawValue
                    let geckoFresh = FirestoreMarketSync.shared.coinGeckoFreshness.rawValue
                    print("📡 [StartupDataStatus] source=live ticker=\(tickerFresh) coingecko=\(geckoFresh)")
                }
                
                // RELAUNCH FIX v5.0.15: Clear crash guard + reset failure counter
                // after 20s of stable runtime (reduced from 45s).
                // The app reaches usable state in ~5s, so 20s is plenty of margin.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 20_000_000_000) // 20s stable runtime
                    UserDefaults.standard.set(false, forKey: "AppStartupCrashGuard")
                    UserDefaults.standard.set(false, forKey: "StartupSafeModeEnabled")
                    UserDefaults.standard.set(0, forKey: "AppConsecutiveFailCount")
                    startupRecoveryMode = false
                    print("🛡️ [CRASH GUARD] Cleared + failure counter reset after stable runtime")
                }
                
                // Show periodic upgrade prompt after core launch has settled.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if PaywallManager.shared.shouldShowPeriodicPrompt && !showOnboarding {
                    showPeriodicUpgrade = true
                    PaywallManager.shared.recordPromptShown()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // App-level scene phase handling for global data freshness and security
                DispatchQueue.main.async { [self] in
                    switch newPhase {
                    case .active:
                        // PERF: Debounce lightweight foreground operations to prevent spam from
                        // ScreenProtection activate/deactivate cycles (which rapidly toggle scene phase)
                        let fgNow = Date()
                        let shouldFireLightweight = fgNow.timeIntervalSince(lastForegroundEventAt) >= foregroundEventCooldown
                        if shouldFireLightweight {
                            lastForegroundEventAt = fgNow
                            // Analytics: Track app foreground
                            AnalyticsService.shared.appDidBecomeActive()
                            // Notify coordinator of foreground event
                            APIRequestCoordinator.shared.appDidBecomeForeground()
                        }
                        
                        // HAPTIC FIX: Reinitialize haptics on foreground
                        // Core Haptics can fail during initial app launch (timeout error)
                        // but usually works fine after the system stabilizes
                        ChartHaptics.shared.reinitialize()
                        
                        // MEMORY FIX v12: Never auto-start Firestore listeners from initial .active.
                        // The launch-time .active event fires before startup phase gating, which was
                        // bypassing delayed Phase 2 and re-triggering the memory cascade.
                        if didStartRealtimePipeline && !CryptoSageAIApp.isEmergencyStopActive() {
                            FirestoreMarketSync.shared.startListening()
                        } else {
                            print("⏳ [ScenePhase] Skipping Firestore restart — pipeline not ready or emergency stop active")
                        }
                        
                        // PERFORMANCE v26: Only clear caches AND reload when cooldown has elapsed.
                        // Previously caches were cleared on every foreground event but reloads were
                        // cooldown-gated, causing "—" dashes with no repopulation on quick cycles.
                        // Now both operations are gated together.
                        let isInitialActivePulse = !appReady || !didStartLoading
                        if isInitialActivePulse {
                            print("⏳ [ScenePhase] Initial active pulse — skipping foreground reload")
                        } else {
                            let now = Date()
                            if now.timeIntervalSince(lastForegroundLoadAt) >= foregroundLoadCooldown {
                                lastForegroundLoadAt = now
                                #if !targetEnvironment(simulator)
                                LivePriceManager.shared.clearAllSidecarCaches()
                                #endif
                                Task {
                                    guard !CryptoSageAIApp.isEmergencyStopActive() else { return }
                                    // Foreground resume should be lightweight. Full loadAllData() is expensive
                                    // and can hitch scrolling/tab transitions on return to Home.
                                    await marketVM.loadWatchlistDataImmediate()
                                }
                            }
                        }
                        
                        // Restart alert monitoring on foreground return
                        // The timer may have been invalidated while backgrounded
                        if !CryptoSageAIApp.isEmergencyStopActive(),
                           NotificationsManager.shared.hasActiveAlerts {
                            NotificationsManager.shared.resumeMonitoring()
                        }
                        
                        // Restart AI Portfolio Monitor if enabled
                        if !CryptoSageAIApp.isEmergencyStopActive(),
                           AIPortfolioMonitor.shared.isEnabled && !AIPortfolioMonitor.shared.isMonitoring {
                            AIPortfolioMonitor.shared.startMonitoring()
                        }
                        
                        // Check if we should auto-lock based on timeout
                        if securityManager.shouldAutoLock() {
                            biometricAuth.lockApp()
                        }
                        
                        // NOTE: Removed layout refresh on foreground - it was resetting navigation state
                        // The .monitorLayoutStability() modifier handles any layout issues without nav reset
                    case .background:
                        // RELAUNCH FIX v5.0.15: Mark clean shutdown.
                        // Force-quit skips .background → flag stays false → next launch purges.
                        // This is the KEY fix for "can't relaunch after quit".
                        UserDefaults.standard.set(true, forKey: "AppCleanShutdown")
                        
                        // Analytics: Track app background
                        AnalyticsService.shared.appDidEnterBackground()
                        // Track when app went to background for auto-lock timeout
                        securityManager.appDidEnterBackground()
                        // Stop AI Portfolio Monitor to save resources
                        AIPortfolioMonitor.shared.stopMonitoring()
                        
                        // MEMORY FIX v8: Stop ALL Firestore listeners on background.
                        // Listeners continue receiving snapshots even when backgrounded,
                        // wasting memory and network. They're restarted on foreground.
                        FirestoreMarketSync.shared.stopListening()
                        FavoritesManager.shared.stopFirestoreSync()
                        
                        // Clear sensitive data from memory for extra security
                        secureDataManager.clearMemoryCaches()
                        // Immediate lock if biometric enabled (can be changed to timeout-only)
                        biometricAuth.lockApp()
                        // Stop the in-app monitoring timer (it'll be restarted on foreground)
                        NotificationsManager.shared.stopMonitoring()
                        // Schedule both background tasks for price alerts so they fire even when app is closed
                        if NotificationsManager.shared.hasActiveAlerts {
                            CryptoSageAIApp.schedulePriceAlertBackgroundRefresh()
                            CryptoSageAIApp.schedulePriceAlertBackgroundProcessing()
                        }
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
            }
            .onChange(of: appState.selectedTab) { oldTab, newTab in
                // PERFORMANCE: Move analytics off main thread to not block tab switch
                Task.detached(priority: .utility) {
                    AnalyticsService.shared.trackTabSelection(newTab.rawValue)
                    InterstitialAdCoordinator.recordTransition()
                }
                
                // FIX v14: Clean up heavy resources when leaving certain tabs.
                // TabView keeps all views alive. WebViews, URLSession caches, and
                // order book data accumulate across tab switches, causing the slow
                // 0.47 MB/s leak and occasional main thread freezes.
                if oldTab == .trade || oldTab == .market {
                    Task { @MainActor in
                        // Release URLSession caches to free network buffers
                        URLCache.shared.removeAllCachedResponses()
                        // Trim image caches
                        URLCache.shared.memoryCapacity = min(URLCache.shared.memoryCapacity, 4 * 1024 * 1024)
                    }
                }
            }
            // Track lock transition state (used to coordinate animations)
            .onChange(of: biometricAuth.isLocked) { wasLocked, isLocked in
                if wasLocked && !isLocked {
                    // User just unlocked - mark transition in progress
                    isTransitioningFromLock = true
                    // Clear transition flag after animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isTransitioningFromLock = false
                        #if DEBUG
                        print("✅ [CryptoSageAIApp] Unlock transition complete - navigation state preserved")
                        #endif
                    }
                }
            }
            // LAYOUT STABILITY: Monitor for layout anomalies - logging only now
            // NOTE: Removed aggressive view ID reset as it was destroying navigation state
            // The modifier still monitors but we don't force a destructive refresh
            .monitorLayoutStability(expectedMinHeight: 420) {
                #if DEBUG
                print("🔧 [CryptoSageAIApp] Layout anomaly detected - monitoring only (nav state preserved)")
                #endif
            }
        }
    }
}

class AppState: ObservableObject {
    // PERFORMANCE FIX v20: Singleton for targeted publisher access without @EnvironmentObject observation
    static let shared = AppState()
    
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
    
    /// Trigger to dismiss legacy NavigationLink-based subviews in Market tab
    @Published var dismissMarketSubviews: Bool = false
    
    /// Trigger to dismiss legacy NavigationLink-based subviews in Portfolio tab
    @Published var dismissPortfolioSubviews: Bool = false
    
    /// Track keyboard visibility for hiding tab bar in AI Chat
    @Published var isKeyboardVisible: Bool = false
    
    /// Pending trade configuration from AI Chat
    /// When set, TradeView will pick this up and pre-fill the trade form
    @Published var pendingTradeConfig: AITradeConfig? = nil
    
    /// Pending navigation to bot hub with specific bot ID to highlight
    @Published var pendingBotNavigation: UUID? = nil
    
    /// Flag to trigger BotHub navigation in TradeView
    @Published var shouldShowBotHub: Bool = false
    
    /// Flag to trigger Derivatives Bot navigation
    @Published var shouldShowDerivativesBot: Bool = false
    
    /// Pending derivatives config for pre-filling
    @Published var pendingDerivativesConfig: AITradeConfig? = nil
    
    /// Pending bot config from AI Chat for pre-filling bot creation forms
    @Published var pendingBotConfig: AIBotConfig? = nil
    
    /// Flag to trigger TradingBotView navigation
    @Published var shouldShowTradingBot: Bool = false
    
    /// Flag to trigger PredictionBotView navigation
    @Published var shouldShowPredictionBot: Bool = false
    
    /// Signal used by AI CTA to force Trade tab back to Spot form root
    @Published var shouldShowSpotTradeFromAI: Bool = false
    
    /// Tracks the tab the user was on before AI-triggered navigation (e.g., .ai)
    /// Used to return the user to their previous tab when they press back from a bot creation view
    @Published var tabBeforeBotCreation: CustomTab? = nil
    
    /// Navigate to Trading tab with a pre-filled trade config
    /// Automatically routes to derivatives bot if leverage is specified
    func navigateToTrade(with config: AITradeConfig) {
        // Check if this is a derivatives trade (has leverage > 1)
        if let leverage = config.leverage, leverage > 1 {
            // Navigate to derivatives bot
            pendingTradeConfig = nil
            pendingDerivativesConfig = config
            tradeNavPath = NavigationPath()
            shouldShowDerivativesBot = true
            shouldShowSpotTradeFromAI = false
            selectedTab = .trade
        } else {
            // Navigate to regular spot trade
            pendingDerivativesConfig = nil
            pendingTradeConfig = config
            tradeNavPath = NavigationPath()
            shouldShowSpotTradeFromAI = true
            selectedTab = .trade
        }
    }
    
    /// Navigate directly to derivatives bot with optional config
    func navigateToDerivatives(with config: AITradeConfig? = nil) {
        pendingDerivativesConfig = config
        tradeNavPath = NavigationPath()
        shouldShowDerivativesBot = true
        selectedTab = .trade
    }
    
    /// Navigate to Trading tab > BotHub to view a specific bot
    func navigateToBotHub(botId: UUID? = nil) {
        pendingBotNavigation = botId
        tradeNavPath = NavigationPath() // Reset nav stack to root
        shouldShowBotHub = true
        selectedTab = .trade
    }
    
    /// Navigate to Trading tab > TradingBotView with a pre-filled config
    func navigateToBotCreation(with config: AIBotConfig) {
        pendingBotConfig = config
        
        // Remember which tab the user was on so we can return them there on back
        tabBeforeBotCreation = selectedTab
        
        tradeNavPath = NavigationPath()
        
        // Route to appropriate view based on bot type
        switch config.botType {
        case .predictionMarket:
            shouldShowPredictionBot = true
        case .derivatives:
            // Convert bot config to trade config for derivatives
            if let leverage = config.leverage {
                let tradeConfig = AITradeConfig(
                    symbol: config.tradingPair?.components(separatedBy: "_").first ?? "BTC",
                    quoteCurrency: nil,
                    direction: config.direction?.lowercased() == "long" ? .buy : .sell,
                    orderType: .market,
                    amount: config.baseOrderSize,
                    isUSDAmount: true,
                    price: nil,
                    stopLoss: config.stopLoss,
                    takeProfit: config.takeProfit,
                    leverage: leverage
                )
                pendingDerivativesConfig = tradeConfig
                shouldShowDerivativesBot = true
            }
        default:
            shouldShowTradingBot = true
        }
        
        selectedTab = .trade
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupKeyboardObservers()
    }
    
    private func setupKeyboardObservers() {
        // Observe keyboard will show
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isKeyboardVisible = true
            }
            .store(in: &cancellables)
        
        // Observe keyboard will hide
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isKeyboardVisible = false
            }
            .store(in: &cancellables)
    }
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

// PERFORMANCE NOTE: LazyView defers content creation using @autoclosure
// The content is built when body is first evaluated (when tab becomes visible)
// Individual views should guard their onAppear/task blocks to skip redundant work on tab switches
struct LazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) { self.build = build }
    var body: some View { build() }
}

private struct PremiumStartupView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.02, blue: 0.03),
                    Color(red: 0.06, green: 0.05, blue: 0.04),
                    Color(red: 0.03, green: 0.025, blue: 0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color(red: 212/255, green: 175/255, blue: 55/255).opacity(0.22),
                    Color(red: 212/255, green: 175/255, blue: 55/255).opacity(0.06),
                    .clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 340
            )
            .blendMode(.screen)

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color(red: 212/255, green: 175/255, blue: 55/255).opacity(0.24), lineWidth: 1.5)
                        .frame(width: 120, height: 120)

                    Image(systemName: "shield.fill")
                        .font(.system(size: 66, weight: .regular))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 243/255, green: 211/255, blue: 109/255),
                                    Color(red: 212/255, green: 175/255, blue: 55/255),
                                    Color(red: 140/255, green: 107/255, blue: 0/255)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(Color.black.opacity(0.82))
                        }
                }
                .padding(.bottom, 10)

                Text("CryptoSage AI")
                    .font(.system(size: 48, weight: .bold, design: .default))
                    .foregroundColor(Color(red: 243/255, green: 211/255, blue: 109/255))

                Text("AI-Powered Insights")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                Text("Privacy Mode")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(red: 212/255, green: 175/255, blue: 55/255))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.07))
                    )
                    .overlay(
                        Capsule().stroke(Color(red: 212/255, green: 175/255, blue: 55/255).opacity(0.24), lineWidth: 0.8)
                    )
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
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

// MARK: - Layout Stability Monitor
// This modifier detects layout anomalies and can trigger recovery
// Implements professional-grade layout monitoring with debouncing and telemetry

/// Monitors view layout and posts notifications when anomalies are detected
/// Use this to detect and recover from layout bugs caused by safe area miscalculations
private struct LayoutStabilityMonitor: ViewModifier {
    let expectedMinHeight: CGFloat
    let onLayoutAnomaly: () -> Void
    
    @State private var lastValidHeight: CGFloat = 0
    @State private var anomalyCount: Int = 0
    @State private var lastRecoveryTime: Date = .distantPast
    @State private var totalRecoveries: Int = 0
    
    // Configuration for professional-grade monitoring
    private let maxAnomaliesBeforeRecovery = 2
    private let minimumRecoveryInterval: TimeInterval = 1.0 // Debounce: minimum 1s between recoveries
    private let maxRecoveriesPerSession = 5 // Prevent infinite recovery loops
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            checkLayout(size: geo.size)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            checkLayout(size: newSize)
                        }
                }
            )
    }
    
    private func checkLayout(size: CGSize) {
        // Detect if the height is suspiciously small (layout collapsed).
        // Use a tolerance band because transient states (keyboard/transition) can validly dip.
        let anomalyThreshold = max(expectedMinHeight * 0.85, 320)
        if size.height < anomalyThreshold && size.height > 0 {
            anomalyCount += 1
            #if DEBUG
            print("⚠️ [LayoutStabilityMonitor] Anomaly detected: height=\(size.height), threshold<\(anomalyThreshold), expected>=\(expectedMinHeight), count=\(anomalyCount)")
            #endif
            
            // Check if we should trigger recovery
            let now = Date()
            let timeSinceLastRecovery = now.timeIntervalSince(lastRecoveryTime)
            let canRecover = timeSinceLastRecovery >= minimumRecoveryInterval && totalRecoveries < maxRecoveriesPerSession
            
            if anomalyCount >= maxAnomaliesBeforeRecovery && canRecover {
                // Trigger recovery after multiple anomalies
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    lastRecoveryTime = Date()
                    totalRecoveries += 1
                    anomalyCount = 0
                    
                    #if DEBUG
                    print("🔧 [LayoutStabilityMonitor] Triggering recovery #\(totalRecoveries)")
                    #endif
                    
                    // Log to crash reporting for telemetry (non-fatal)
                    CrashReportingService.shared.logNonFatalEvent(
                        name: "LayoutAnomalyRecovery",
                        attributes: [
                            "detected_height": "\(size.height)",
                            "expected_min_height": "\(expectedMinHeight)",
                            "recovery_count": "\(totalRecoveries)"
                        ]
                    )
                    
                    onLayoutAnomaly()
                }
            } else if totalRecoveries >= maxRecoveriesPerSession {
                // Exceeded recovery limit - log but don't spam
                #if DEBUG
                print("⚠️ [LayoutStabilityMonitor] Max recoveries reached (\(maxRecoveriesPerSession)), skipping")
                #endif
            }
        } else if size.height >= anomalyThreshold {
            // Layout looks good, reset anomaly counter
            lastValidHeight = size.height
            anomalyCount = 0
            
            // Reset recovery counter periodically when layout is stable
            let now = Date()
            if now.timeIntervalSince(lastRecoveryTime) > 30 {
                totalRecoveries = 0
            }
        }
    }
}

extension View {
    /// Monitors layout stability and calls the handler when anomalies are detected
    /// - Parameters:
    ///   - expectedMinHeight: The minimum expected height for this view
    ///   - onLayoutAnomaly: Handler called when layout appears collapsed/broken
    func monitorLayoutStability(expectedMinHeight: CGFloat, onLayoutAnomaly: @escaping () -> Void) -> some View {
        self.modifier(LayoutStabilityMonitor(expectedMinHeight: expectedMinHeight, onLayoutAnomaly: onLayoutAnomaly))
    }
}