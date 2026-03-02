//
//  AdManager.swift
//  CryptoSage
//
//  Manages ad display for free tier users.
//  Integrates with Google AdMob for banner and interstitial ads.
//
//  ## AdMob vs Firebase - Important Notes
//
//  AdMob and Firebase are SEPARATE Google products:
//  - AdMob: For displaying ads and earning revenue (this file)
//  - Firebase: For analytics, crash reporting, authentication, etc.
//
//  You do NOT need Firebase to use AdMob! AdMob works standalone.
//  However, if you want advanced features like:
//  - A/B testing ad frequency
//  - Remote config to adjust ad settings without app updates
//  - Detailed analytics on ad performance
//  Then you can optionally link AdMob to Firebase Analytics.
//
//  To view your ad revenue:
//  - Go to https://admob.google.com
//  - Click "Reports" in the left sidebar
//  - View earnings, impressions, eCPM, and more
//

import SwiftUI
import UIKit
import GoogleMobileAds

// MARK: - Ad Configuration

/// Configuration for CryptoSage ads
///
/// ## How to Set Up AdMob and Get Paid
///
/// ### Step 1: Create an AdMob Account
/// 1. Go to https://admob.google.com
/// 2. Sign in with your Google account
/// 3. Accept the terms and create your AdMob account
///
/// ### Step 2: Register Your iOS App
/// 1. In AdMob dashboard, click "Apps" → "Add App"
/// 2. Select "iOS" platform
/// 3. If published: Enter your App Store listing URL
/// 4. If not published: Register manually with your app name and bundle ID
/// 5. Copy the App ID (format: ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY)
///
/// ### Step 3: Create Ad Units
/// 1. In your app's page, click "Ad units" → "Add ad unit"
/// 2. Create a "Banner" ad unit → Copy the Ad Unit ID
/// 3. Create an "Interstitial" ad unit → Copy the Ad Unit ID
///
/// ### Step 4: Update This File and Info.plist
/// 1. Replace the production Ad Unit IDs below with your real IDs
/// 2. Update Info.plist: Replace GADApplicationIdentifier with your App ID
///
/// ### Step 5: Set Up Payments to Get Paid
/// 1. In AdMob, go to "Payments" in the left sidebar
/// 2. Add your payment info (name, address must match your bank account)
/// 3. Submit tax information (W-9 for US, W-8BEN for international)
/// 4. Verify your identity if prompted
/// 5. Select payment method (EFT/wire transfer recommended)
///
/// ### Revenue Information
/// - Banner ads: ~$0.10-$1.00 CPM (per 1000 impressions)
/// - Interstitial ads: ~$1-$5 CPM (higher because full-screen)
/// - Payments issued monthly when balance reaches $100 threshold
/// - First payment may take 1-2 months to process
///
public enum AdConfig {
    // Test Ad Unit IDs (Use these during development)
    // These are Google's official test IDs - safe to use in debug builds
    
    #if DEBUG
    static let bannerAdUnitID = "ca-app-pub-3940256099942544/2934735716" // Test banner ID
    static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910" // Test interstitial ID
    #else
    // Production Ad Unit IDs - CryptoSage AI
    static let bannerAdUnitID = "ca-app-pub-8272237740560809/3689457127"       // Banner Ad Unit
    static let interstitialAdUnitID = "ca-app-pub-8272237740560809/1003644101" // Interstitial Ad Unit
    #endif
    
    // App ID (also configured in Info.plist under GADApplicationIdentifier)
    static let appID = "ca-app-pub-8272237740560809~8395048962"
    
    // Ad display settings - OPTIMIZED FOR FINANCE APPS
    // Finance apps are "non-linear" (users constantly switch tabs to check prices)
    // Google recommends being very conservative with interstitials in such apps
    // Reference: https://support.google.com/admanager/answer/6309702
    
    static let interstitialFrequency: Int = 25 // Show interstitial every N screen transitions (high for finance apps)
    static let minTimeBetweenInterstitials: TimeInterval = 300 // Minimum 5 minutes between interstitials
    static let sessionGracePeriod: TimeInterval = 600 // No interstitials in first 10 minutes of session
    static let cooldownAfterSubscriptionView: TimeInterval = 600 // 10 minute cooldown after viewing subscription
    static let cooldownAfterChartView: TimeInterval = 180 // 3 minute cooldown after viewing charts (user is analyzing)
    static let maxRetryAttempts: Int = 3 // Max retries for failed ad loads
    static let retryDelay: TimeInterval = 30 // Seconds between retry attempts
    
    // Maximum interstitials per day to prevent ad fatigue
    static let maxInterstitialsPerDay: Int = 3
}

// MARK: - Ad Manager

/// Singleton manager for handling ad display throughout the app
@MainActor
public final class AdManager: ObservableObject {
    public static let shared = AdManager()
    
    // MARK: - Published Properties
    
    /// Whether ads should be displayed (based on subscription)
    @Published public private(set) var shouldShowAds: Bool = false
    
    /// Whether the ad SDK is initialized
    @Published public private(set) var isInitialized: Bool = false
    
    /// Whether an interstitial ad is ready
    @Published public private(set) var isInterstitialReady: Bool = false
    
    /// Loading state for ads
    @Published public private(set) var isLoadingAd: Bool = false
    
    // MARK: - Private Properties
    
    private var screenTransitionCount: Int = 0
    private var lastInterstitialTime: Date = .distantPast
    private var lastSubscriptionViewTime: Date = .distantPast
    private var lastChartViewTime: Date = .distantPast
    private var sessionStartTime: Date = Date()
    private var interstitialsShownToday: Int = 0
    private var lastInterstitialDate: Date = .distantPast
    private var interstitialAd: GADInterstitialAd?
    private var loadRetryCount: Int = 0
    private var interstitialDelegate: InterstitialAdDelegate?
    // Startup safety gate: avoid initializing ad SDK during fragile launch window.
    private var startupAllowsInitialization: Bool = false
    
    // MARK: - Initialization
    
    // MEMORY FIX v8: Store observer tokens for proper cleanup
    private var subscriptionObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    
    // MEMORY FIX v8: Remove observers on deallocation
    deinit {
        if let obs = subscriptionObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = activeObserver { NotificationCenter.default.removeObserver(obs) }
    }
    
    private init() {
        // Update shouldShowAds based on subscription status
        updateAdDisplayStatus()
        
        // Listen for subscription changes
        subscriptionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SubscriptionStatusChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateAdDisplayStatus()
            }
        }
        
        // Reset session start time when app becomes active (for grace period)
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetSessionIfNeeded()
            }
        }
    }
    
    /// Reset session start time when app becomes active after being in background
    private func resetSessionIfNeeded() {
        // Only reset if it's been more than 5 minutes since last session
        let timeSinceSessionStart = Date().timeIntervalSince(sessionStartTime)
        if timeSinceSessionStart > 300 { // 5 minutes
            sessionStartTime = Date()
            #if DEBUG
            print("[Ads] Session reset - new grace period started")
            #endif
        }
    }
    
    // MARK: - Public API
    
    /// Initialize the ad SDK (call this from AppDelegate or App init)
    public func initializeAds() {
        guard !isInitialized else { return }
        #if targetEnvironment(simulator)
        #if DEBUG
        print("[Ads] Simulator detected - AdMob initialization disabled")
        #endif
        return
        #else
        guard startupAllowsInitialization else {
            #if DEBUG
            print("[Ads] Startup gate active - deferring AdMob initialization")
            #endif
            return
        }
        
        // Skip if user has subscription
        guard SubscriptionManager.shared.shouldShowAds else {
            #if DEBUG
            print("[Ads] User has subscription, skipping ad initialization")
            #endif
            return
        }
        
        #if DEBUG
        print("[Ads] Initializing AdMob SDK...")
        #endif
        
        // Initialize Google Mobile Ads SDK
        GADMobileAds.sharedInstance().start { [weak self] status in
            Task { @MainActor [weak self] in
                self?.isInitialized = true
                self?.preloadInterstitial()
                #if DEBUG
                print("[Ads] AdMob SDK initialized")
                #endif
            }
        }
        #endif
    }
    
    /// Update ad display status based on subscription
    public func updateAdDisplayStatus() {
        #if targetEnvironment(simulator)
        shouldShowAds = false
        return
        #else
        let newStatus = SubscriptionManager.shared.shouldShowAds
        
        if shouldShowAds != newStatus {
            shouldShowAds = newStatus
            
            if shouldShowAds {
                // User downgraded or is on free tier - initialize ads
                // Reset initialization flag to allow re-initialization after downgrade
                if !isInitialized {
                    initializeAds()
                } else {
                    // Already initialized, just preload interstitial
                    preloadInterstitial()
                }
                // Reset session start time for grace period
                sessionStartTime = Date()
            } else {
                // User upgraded - clean up ads immediately
                cleanupAds()
            }
            
            #if DEBUG
            print("[Ads] Ad display status: \(shouldShowAds ? "enabled" : "disabled")")
            #endif
        }
        #endif
    }
    
    /// Called by app startup once launch has stabilized.
    public func allowInitializationAfterStartup() {
        startupAllowsInitialization = true
        if shouldShowAds && !isInitialized {
            initializeAds()
        }
    }
    
    /// Clean up ads when user upgrades (to ensure immediate ad-free experience)
    private func cleanupAds() {
        interstitialAd = nil
        isInterstitialReady = false
        isLoadingAd = false
        screenTransitionCount = 0
        
        #if DEBUG
        print("[Ads] Ads cleaned up - user upgraded to premium")
        #endif
    }
    
    /// Record a screen transition (for interstitial frequency)
    /// Also checks if an interstitial should be shown and displays it automatically
    public func recordScreenTransition() {
        guard shouldShowAds else { return }
        
        screenTransitionCount += 1
        
        #if DEBUG
        print("[Ads] Screen transition count: \(screenTransitionCount)/\(AdConfig.interstitialFrequency)")
        #endif
        
        // Automatically show interstitial if conditions are met
        if shouldShowInterstitial {
            if let rootVC = InterstitialAdCoordinator.rootViewController {
                showInterstitialIfReady(from: rootVC)
            } else {
                #if DEBUG
                print("[Ads] Warning: Could not get root view controller for interstitial")
                #endif
            }
        }
    }
    
    /// Record when user views subscription/upgrade screen (to pause ads temporarily)
    public func recordSubscriptionViewShown() {
        lastSubscriptionViewTime = Date()
        #if DEBUG
        print("[Ads] Subscription view shown - starting 10 minute ad cooldown")
        #endif
    }
    
    /// Record when user views charts/detailed analysis (they're focused, don't interrupt)
    public func recordChartViewShown() {
        lastChartViewTime = Date()
        #if DEBUG
        print("[Ads] Chart view shown - starting 3 minute ad cooldown")
        #endif
    }
    
    /// Check if an interstitial should be shown
    /// This is conservative for finance apps - we prioritize user experience over ad revenue
    public var shouldShowInterstitial: Bool {
        guard shouldShowAds else { return false }
        guard isInterstitialReady else { return false }
        
        let now = Date()
        
        // Check daily limit (max 3 interstitials per day)
        if !Calendar.current.isDate(lastInterstitialDate, inSameDayAs: now) {
            // New day - reset counter
            interstitialsShownToday = 0
        }
        guard interstitialsShownToday < AdConfig.maxInterstitialsPerDay else {
            #if DEBUG
            print("[Ads] Daily interstitial limit reached (\(AdConfig.maxInterstitialsPerDay))")
            #endif
            return false
        }
        
        // Check session grace period (no ads in first 10 minutes)
        let sessionDuration = now.timeIntervalSince(sessionStartTime)
        guard sessionDuration >= AdConfig.sessionGracePeriod else {
            #if DEBUG
            print("[Ads] In session grace period (\(Int(AdConfig.sessionGracePeriod - sessionDuration))s remaining)")
            #endif
            return false
        }
        
        // Check frequency (25 tab switches for finance apps)
        guard screenTransitionCount >= AdConfig.interstitialFrequency else { return false }
        
        // Check time since last interstitial (5 minutes minimum)
        let timeSinceLast = now.timeIntervalSince(lastInterstitialTime)
        guard timeSinceLast >= AdConfig.minTimeBetweenInterstitials else { return false }
        
        // Respect cooldown after user viewed subscription (10 minutes)
        let timeSinceSubscriptionView = now.timeIntervalSince(lastSubscriptionViewTime)
        guard timeSinceSubscriptionView >= AdConfig.cooldownAfterSubscriptionView else {
            #if DEBUG
            print("[Ads] In cooldown after subscription view (\(Int(AdConfig.cooldownAfterSubscriptionView - timeSinceSubscriptionView))s remaining)")
            #endif
            return false
        }
        
        // Respect cooldown after chart/analysis view (3 minutes - user is focused)
        let timeSinceChartView = now.timeIntervalSince(lastChartViewTime)
        guard timeSinceChartView >= AdConfig.cooldownAfterChartView else {
            #if DEBUG
            print("[Ads] In cooldown after chart view (\(Int(AdConfig.cooldownAfterChartView - timeSinceChartView))s remaining)")
            #endif
            return false
        }
        
        return true
    }
    
    /// Show interstitial ad if ready and conditions are met
    /// - Parameter viewController: The view controller to present from
    public func showInterstitialIfReady(from viewController: UIViewController) {
        guard shouldShowInterstitial else { return }
        
        #if DEBUG
        print("[Ads] Showing interstitial ad (today: \(interstitialsShownToday + 1)/\(AdConfig.maxInterstitialsPerDay))...")
        #endif
        
        // Reset counter and record time
        screenTransitionCount = 0
        lastInterstitialTime = Date()
        lastInterstitialDate = Date()
        interstitialsShownToday += 1
        isInterstitialReady = false
        
        // Show the interstitial
        interstitialAd?.present(fromRootViewController: viewController)
        
        // Preload the next interstitial
        preloadInterstitial()
    }
    
    /// Preload an interstitial ad for later display
    public func preloadInterstitial() {
        guard shouldShowAds else { return }
        guard !isLoadingAd else { return }
        
        isLoadingAd = true
        
        #if DEBUG
        print("[Ads] Preloading interstitial ad (attempt \(loadRetryCount + 1)/\(AdConfig.maxRetryAttempts + 1))...")
        #endif
        
        let request = GADRequest()
        GADInterstitialAd.load(withAdUnitID: AdConfig.interstitialAdUnitID, request: request) { [weak self] ad, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isLoadingAd = false
                
                if let error = error {
                    #if DEBUG
                    print("[Ads] Failed to load interstitial: \(error.localizedDescription)")
                    #endif
                    
                    // Retry with exponential backoff
                    if self.loadRetryCount < AdConfig.maxRetryAttempts {
                        self.loadRetryCount += 1
                        let delay = AdConfig.retryDelay * Double(self.loadRetryCount)
                        #if DEBUG
                        print("[Ads] Will retry in \(Int(delay)) seconds...")
                        #endif
                        Task {
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            await MainActor.run {
                                self.preloadInterstitial()
                            }
                        }
                    }
                    return
                }
                
                // Success - reset retry count
                self.loadRetryCount = 0
                self.interstitialAd = ad
                
                // Set up delegate for tracking
                self.interstitialDelegate = InterstitialAdDelegate(adManager: self)
                self.interstitialAd?.fullScreenContentDelegate = self.interstitialDelegate
                
                self.isInterstitialReady = true
                #if DEBUG
                print("[Ads] Interstitial ad loaded successfully")
                #endif
            }
        }
    }
    
    /// Called when interstitial ad is dismissed
    fileprivate func interstitialDidDismiss() {
        interstitialAd = nil
        isInterstitialReady = false
        // Preload next ad
        preloadInterstitial()
    }
    
    /// Called when interstitial ad fails to present
    fileprivate func interstitialFailedToPresent() {
        isInterstitialReady = false
        // Try to load a new one
        preloadInterstitial()
    }
}

// MARK: - Interstitial Ad Delegate

/// Delegate for handling interstitial ad events
private class InterstitialAdDelegate: NSObject, GADFullScreenContentDelegate {
    weak var adManager: AdManager?
    
    init(adManager: AdManager) {
        self.adManager = adManager
    }
    
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        #if DEBUG
        print("[Ads] Interstitial ad dismissed")
        #endif
        // Analytics: Track interstitial dismissal
        AnalyticsService.shared.track(.interstitialAdDismissed, parameters: nil)
        Task { @MainActor in
            self.adManager?.interstitialDidDismiss()
        }
    }
    
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        #if DEBUG
        print("[Ads] Interstitial failed to present: \(error.localizedDescription)")
        #endif
        // Analytics: Track interstitial failure
        AnalyticsService.shared.track(.interstitialAdFailed, parameters: ["error": error.localizedDescription])
        Task { @MainActor in
            self.adManager?.interstitialFailedToPresent()
        }
    }
    
    func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        #if DEBUG
        print("[Ads] Interstitial will present")
        #endif
        // Analytics: Track interstitial impression
        AnalyticsService.shared.track(.interstitialAdShown, parameters: nil)
    }
}

// MARK: - SwiftUI Banner Ad View

/// A SwiftUI view that displays a banner ad for free tier users
public struct BannerAdView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var adManager = AdManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showSubscriptionView = false
    
    /// Height of the banner ad (56pt for better tap target and visual breathing room)
    private let bannerHeight: CGFloat = 56
    
    public init() {}
    
    public var body: some View {
        Group {
            if subscriptionManager.shouldShowAds && shouldRenderBannerSlot {
                adBannerContent
            }
        }
        .sheet(isPresented: $showSubscriptionView) {
            NavigationStack {
                SubscriptionPricingView()
            }
        }
        .onChange(of: showSubscriptionView) { _, isShowing in
            if isShowing {
                // Record that user is viewing subscription - triggers ad cooldown
                AdManager.shared.recordSubscriptionViewShown()
            }
        }
    }

    private var isAdRuntimeAllowed: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    // Keep placement/testing parity in debug/simulator by still rendering the
    // bottom ad slot placeholder even when real ad runtime is unavailable.
    private var shouldRenderBannerSlot: Bool {
        #if DEBUG
        true
        #else
        isAdRuntimeAllowed
        #endif
    }
    
    @ViewBuilder
    private var adBannerContent: some View {
        // When GoogleMobileAds is integrated, replace with actual GADBannerView
        ZStack {
            // Background - adaptive for light/dark mode
            Rectangle()
                .fill(colorScheme == .dark ? Color.black.opacity(0.9) : Color(UIColor.systemGray6))
            
            // Placeholder content (replace with actual ad when SDK is integrated)
            #if DEBUG
            HStack(spacing: 8) {
                Image(systemName: "megaphone.fill")
                    .font(.caption2)
                    .foregroundColor(Color.gray.opacity(0.5))
                Text("Ad Placeholder")
                    .font(.caption2)
                    .foregroundColor(Color.gray.opacity(0.5))
                
                Spacer()
                
                // Upgrade button - premium glass style
                Button(action: {
                    showSubscriptionView = true
                }) {
                    Text("Remove Ads")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [BrandColors.goldLight, BrandColors.goldBase] 
                                    : [BrandColors.silverBase, BrandColors.silverDark],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            ZStack {
                                Capsule()
                                    .fill(
                                        RadialGradient(
                                            colors: colorScheme == .dark
                                                ? [BrandColors.goldBase.opacity(0.12), Color.white.opacity(0.06)]
                                                : [BrandColors.silverBase.opacity(0.08), Color.black.opacity(0.03)],
                                            center: .top,
                                            startRadius: 0,
                                            endRadius: 40
                                        )
                                    )
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(colorScheme == .dark ? 0.12 : 0.5), Color.white.opacity(0)],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [BrandColors.goldLight.opacity(0.5), BrandColors.goldBase.opacity(0.2), BrandColors.goldDark.opacity(0.1)]
                                            : [BrandColors.silverLight.opacity(0.6), BrandColors.silverBase.opacity(0.3), BrandColors.silverDark.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            #else
            // Production: Use actual AdMob banner view with upgrade button overlay
            ZStack {
                AdBannerViewRepresentable()
                
                HStack {
                    Spacer()
                    Button(action: {
                        showSubscriptionView = true
                    }) {
                        Text("Remove Ads")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [BrandColors.goldLight, BrandColors.goldBase] 
                                        : [BrandColors.silverBase, BrandColors.silverDark],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                ZStack {
                                    Capsule()
                                        .fill(
                                            RadialGradient(
                                                colors: colorScheme == .dark
                                                    ? [BrandColors.goldBase.opacity(0.12), Color.white.opacity(0.06)]
                                                    : [BrandColors.silverBase.opacity(0.08), Color.black.opacity(0.03)],
                                                center: .top,
                                                startRadius: 0,
                                                endRadius: 40
                                            )
                                        )
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(colorScheme == .dark ? 0.12 : 0.5), Color.white.opacity(0)],
                                                startPoint: .top,
                                                endPoint: .center
                                            )
                                        )
                                }
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: colorScheme == .dark
                                                ? [BrandColors.goldLight.opacity(0.5), BrandColors.goldBase.opacity(0.2), BrandColors.goldDark.opacity(0.1)]
                                                : [BrandColors.silverLight.opacity(0.6), BrandColors.silverBase.opacity(0.3), BrandColors.silverDark.opacity(0.15)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .padding(.trailing, 12)
                }
                .padding(.vertical, 8)
            }
            #endif
        }
        .frame(height: bannerHeight)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4) // Breathing room above tab bar
    }
}

// MARK: - UIKit Banner View Wrapper

/// UIViewRepresentable wrapper for Google AdMob banner view with adaptive sizing
struct AdBannerViewRepresentable: UIViewRepresentable {
    private func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
    }

    private func activeWindowWidth() -> CGFloat {
        if let scene = activeWindowScene(),
           let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
            return max(window.bounds.width, 1)
        }
        return max(UIScreen.main.bounds.width, 1)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        // Create a container view for the banner
        let containerView = UIView()
        containerView.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        
        // Get screen width for adaptive banner sizing
        let screenWidth = activeWindowWidth()
        let adSize = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(screenWidth)
        
        let bannerView = GADBannerView(adSize: adSize)
        bannerView.adUnitID = AdConfig.bannerAdUnitID
        bannerView.delegate = context.coordinator
        
        // Get the root view controller safely
        if let scene = activeWindowScene(),
           let rootViewController = (scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first)?.rootViewController {
            bannerView.rootViewController = rootViewController
        }
        
        bannerView.load(GADRequest())
        
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(bannerView)
        
        // Store reference for potential refresh
        context.coordinator.bannerView = bannerView
        context.coordinator.lastAppliedWidth = screenWidth
        
        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let bannerView = context.coordinator.bannerView else { return }
        let width = activeWindowWidth()
        guard abs(context.coordinator.lastAppliedWidth - width) > 1 else { return }
        context.coordinator.lastAppliedWidth = width
        bannerView.adSize = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(width)
        bannerView.load(GADRequest())
    }
    
    // MARK: - Coordinator for Banner Ad Delegate
    
    class Coordinator: NSObject, GADBannerViewDelegate {
        weak var bannerView: GADBannerView?
        var lastAppliedWidth: CGFloat = 0
        private var retryCount = 0
        private let maxRetries = 3
        
        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            #if DEBUG
            print("[Ads] Banner ad loaded successfully")
            #endif
            retryCount = 0
            
            // Fade in animation for smooth appearance
            bannerView.alpha = 0
            UIView.animate(withDuration: 0.3) {
                bannerView.alpha = 1
            }
        }
        
        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            #if DEBUG
            print("[Ads] Banner failed to load: \(error.localizedDescription)")
            #endif
            
            // Retry with delay
            if retryCount < maxRetries {
                retryCount += 1
                let delay = Double(retryCount) * 10.0 // 10s, 20s, 30s
                #if DEBUG
                print("[Ads] Banner will retry in \(Int(delay)) seconds (attempt \(retryCount)/\(maxRetries))")
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.bannerView?.load(GADRequest())
                }
            }
        }
        
        func bannerViewDidRecordImpression(_ bannerView: GADBannerView) {
            #if DEBUG
            print("[Ads] Banner impression recorded")
            #endif
            // Analytics: Track banner impression
            AnalyticsService.shared.track(.bannerAdImpression, parameters: nil)
        }
        
        func bannerViewDidRecordClick(_ bannerView: GADBannerView) {
            #if DEBUG
            print("[Ads] Banner clicked")
            #endif
            // Analytics: Track banner click
            AnalyticsService.shared.track(.bannerAdClicked, parameters: nil)
        }
    }
}

// MARK: - View Modifier for Banner Ads

/// View modifier to add a banner ad at the bottom of a view
public struct BannerAdModifier: ViewModifier {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    private var shouldRenderBannerSlot: Bool {
        #if DEBUG
        true
        #elseif targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }
    
    public func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            
            if subscriptionManager.shouldShowAds && shouldRenderBannerSlot {
                BannerAdView()
            }
        }
    }
}

public extension View {
    /// Adds a banner ad at the bottom of the view (only for free tier users)
    func withBannerAd() -> some View {
        modifier(BannerAdModifier())
    }
}

// MARK: - Interstitial Ad Coordinator

/// Coordinator for showing interstitial ads at appropriate times
public struct InterstitialAdCoordinator {
    /// Call this when transitioning between major screens
    public static func recordTransition() {
        Task { @MainActor in
            AdManager.shared.recordScreenTransition()
        }
    }
    
    /// Call this to potentially show an interstitial ad
    /// - Parameter viewController: The view controller to present from
    public static func showIfReady(from viewController: UIViewController) {
        Task { @MainActor in
            AdManager.shared.showInterstitialIfReady(from: viewController)
        }
    }
    
    /// Get the current root view controller
    public static var rootViewController: UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return nil
        }
        return window.rootViewController
    }
}

// MARK: - Subscription Change Notification

extension SubscriptionManager {
    /// Post notification when subscription status changes
    public func notifySubscriptionChanged() {
        NotificationCenter.default.post(
            name: NSNotification.Name("SubscriptionStatusChanged"),
            object: nil
        )
    }
}
