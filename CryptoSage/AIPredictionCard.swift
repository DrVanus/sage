//
//  AIPredictionCard.swift
//  CryptoSage
//
//  Compact homepage card component for AI price predictions.
//

import SwiftUI
import Combine
import UserNotifications

// MARK: - Notification Names for Prediction Actions
extension Notification.Name {
    static let openPredictionDetailView = Notification.Name("openPredictionDetailView")
    static let clearPrediction = Notification.Name("clearPrediction")
    static let refreshPrediction = Notification.Name("refreshPrediction")
}

// MARK: - PreferenceKey for Timeframe Button Frame
// PERFORMANCE FIX v3: Thread-safe throttling to prevent "Bound preference tried to update multiple times per frame"
// This preference key captures the frame of the selected timeframe button for dropdown positioning.
// THREAD SAFETY FIX: PreferenceKey reduce() can be called from background threads - use NSLock.
private struct PredictionTimeframeButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    
    // THREAD SAFETY: Use NSLock to protect static mutable state
    private static let lock = NSLock()
    private static var _lastUpdateAt: CFTimeInterval = 0
    private static var _lastValue: CGRect = .zero
    
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        guard next != .zero else { return }
        
        let now = CACurrentMediaTime()
        
        // THREAD SAFETY: Lock before reading/writing static variables
        lock.lock()
        defer { lock.unlock() }
        
        // PERFORMANCE FIX v3: Throttle to 2Hz (0.5s) - frame rarely needs updating
        guard now - _lastUpdateAt >= 0.5 else { return }
        
        // Ignore jitter < 5px (increased from 3px for less frequent updates)
        let dx = abs(next.origin.x - _lastValue.origin.x)
        let dy = abs(next.origin.y - _lastValue.origin.y)
        if dx < 5 && dy < 5 { return }
        
        value = next
        _lastValue = next
        _lastUpdateAt = now
    }
}

// PERFORMANCE FIX v4: Simplified frame capture WITHOUT PreferenceKey
// NO PreferenceKey = NO "Bound preference tried to update multiple times per frame" warning
// Uses direct assignment with throttling instead
private struct TimeframeButtonFrameCapture: ViewModifier {
    @Binding var frame: CGRect
    let isActive: Bool
    
    // Local state for throttling
    @State private var lastCaptureTime: Date = .distantPast
    
    func body(content: Content) -> some View {
        content
            .background(
                // PERFORMANCE FIX v4: Use GeometryReader with direct assignment (no PreferenceKey)
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            captureFrame(proxy: proxy)
                        }
                        // Also capture after layout changes, but only when active
                        .onChange(of: isActive) { _, active in
                            if active {
                                captureFrame(proxy: proxy)
                            }
                        }
                }
            )
    }
    
    private func captureFrame(proxy: GeometryProxy) {
        // Throttle to max 2Hz
        let now = Date()
        guard now.timeIntervalSince(lastCaptureTime) >= 0.5 else { return }
        
        let newFrame = proxy.frame(in: .global)
        guard newFrame != .zero else { return }
        
        // Skip if no meaningful change (< 5px)
        let dx = abs(newFrame.origin.x - frame.origin.x)
        let dy = abs(newFrame.origin.y - frame.origin.y)
        guard dx > 5 || dy > 5 || frame == .zero else { return }
        
        lastCaptureTime = now
        frame = newFrame
    }
}


// MARK: - AI Prediction Section View

struct AIPredictionSectionView: View {
    @StateObject private var predictionService = AIPricePredictionService.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    // FIX v23: Replaced @EnvironmentObject MarketViewModel with direct singleton access.
    // MarketViewModel has 20+ @Published properties firing on every price update.
    // AIPredictionSectionView only reads allCoins for coin picker and bestPrice for live price.
    // With @EnvironmentObject, EVERY MVM change cascaded to this view (inside WatchlistComposite
    // at the top of the home page), causing expensive re-renders every few seconds.
    private var marketVM: MarketViewModel { MarketViewModel.shared }
    
    @State private var selectedCoin: MarketCoin?
    @State private var selectedTimeframe: PredictionTimeframe = .day  // Default to 24H - more relevant for volatile crypto markets
    @State private var currentPrediction: AIPricePrediction?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showCoinPicker: Bool = false
    @State private var showDetailView: Bool = false
    @State private var showUpgradePrompt: Bool = false
    @State private var showAISettings: Bool = false
    
    // Expiration state - shows expired message before auto-collapsing
    @State private var isShowingExpired: Bool = false
    @State private var expiredPrediction: AIPricePrediction?  // Store briefly for expired state display
    
    // Timer to periodically check prediction staleness and update UI
    @State private var stalenessCheckTimer: Timer?
    @State private var predictionUpdateTrigger: UUID = UUID()
    
    // Task handle for cancellation support
    @State private var predictionTask: Task<Void, Never>?
    
    // Safety timeout to reset stuck loading state
    // 25 seconds: accounts for Firebase timeout (8s) + technical fallback generation + network overhead
    @State private var loadingSafetyTimer: Timer?
    private let loadingSafetyTimeoutSeconds: TimeInterval = 25
    
    // Animated glow effect for active prediction
    @State private var glowPulse: Bool = false
    
    // Premium loading animation state
    @State private var loadingOrbitAngle: Double = 0
    @State private var loadingPulse: Bool = false
    @State private var loadingPhase: Int = 0
    @State private var loadingRingScale: CGFloat = 0.8
    @State private var loadingPhaseTimer: Timer?
    
    // Flag to track if initial coin setup is complete (prevents auto-prediction on launch)
    @State private var hasInitializedCoin: Bool = false
    
    // Persist user's collapse preference - when user taps collapse button, don't auto-restore on next appear
    @AppStorage("AIPrediction.UserCollapsed") private var userCollapsed: Bool = false
    
    // Track if user has dismissed the price drift warning for this prediction
    // Resets when a new prediction is generated
    @State private var driftWarningDismissed: Bool = false
    
    // Evaluated outcome for the expired prediction (populated after accuracy evaluation)
    @State private var evaluatedOutcome: StoredPrediction?
    
    // Timeframe dropdown state - exposed via binding for overlay at HomeView level
    @Binding var showTimeframePopover: Bool
    @Binding var timeframeButtonFrame: CGRect
    @Binding var selectedTimeframeBinding: PredictionTimeframe
    var onTimeframeChanged: ((PredictionTimeframe) -> Void)?
    
    init(
        showTimeframePopover: Binding<Bool> = .constant(false),
        timeframeButtonFrame: Binding<CGRect> = .constant(.zero),
        selectedTimeframeBinding: Binding<PredictionTimeframe> = .constant(.week),
        onTimeframeChanged: ((PredictionTimeframe) -> Void)? = nil
    ) {
        self._showTimeframePopover = showTimeframePopover
        self._timeframeButtonFrame = timeframeButtonFrame
        self._selectedTimeframeBinding = selectedTimeframeBinding
        self.onTimeframeChanged = onTimeframeChanged
    }
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Whether user has access to unlimited predictions
    private var hasPremiumAccess: Bool {
        subscriptionManager.hasAccess(to: .aiPricePredictions)
    }
    
    // Compute a state ID to force view recreation on state changes (prevents animation bugs)
    private var contentStateID: String {
        // During refresh (loading with existing prediction), keep the same ID to avoid recreation
        if isLoading && currentPrediction == nil { return "loading" }
        if isShowingExpired { return "expired" }
        if currentPrediction != nil { return "prediction-\(currentPrediction?.id ?? "")" }
        return "empty"
    }

    /// During fresh generation (no existing prediction), reserve expanded card height
    /// so the section transition feels intentional instead of "jumping" twice.
    private var reservedExpandedContentHeight: CGFloat {
        if isShowingExpired || currentPrediction != nil {
            return 244
        }
        return 0
    }
    
    /// Whether the current error is related to API key configuration
    private var isAPIKeyError: Bool {
        guard let error = errorMessage?.lowercased() else { return false }
        return error.contains("api key") || error.contains("openai") || 
               error.contains("quota") || error.contains("settings") ||
               error.contains("configure")
    }
    
    var body: some View {
        let isCompact = currentPrediction == nil && !isLoading
        let hasPrediction = currentPrediction != nil
        let predictionColor = currentPrediction?.direction.color ?? BrandColors.goldBase
        
        PremiumGlassCard(showGoldAccent: true, cornerRadius: 14, enableShimmer: hasPrediction) {
            VStack(spacing: 8) {
                // Error banner - shows above content when there's an error
                // Tappable to dismiss; developer mode users get directed to AI Settings
                if let error = errorMessage {
                    Button {
                        if isAPIKeyError && SubscriptionManager.shared.isDeveloperMode {
                            // Developer mode: navigate to AI Settings for API key errors
                            showAISettings = true
                            errorMessage = nil
                        } else {
                            // Regular users: just dismiss the error
                            errorMessage = nil
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                            
                            Text(isAPIKeyError && !SubscriptionManager.shared.isDeveloperMode ? "Prediction temporarily unavailable — try again later" : error)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.orange.opacity(isDark ? 0.15 : 0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        // Auto-dismiss errors after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            if errorMessage != nil {
                                errorMessage = nil
                            }
                        }
                    }
                }
                
                // Main content
                // FIX v28: Added transitions and animation for smooth state changes.
                // Previously the Group had no .transition() and used .id(contentStateID) which
                // caused abrupt view replacement. Now each branch has a fade+scale transition
                // and the container animates height changes smoothly.
                Group {
                    if isLoading && currentPrediction == nil {
                        // Only show full loading state when there's no existing prediction
                        loadingState
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else if isShowingExpired, let expired = expiredPrediction {
                        expiredState(expired)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else if let prediction = currentPrediction {
                        // Show prediction (with loading overlay if refreshing)
                        predictionResultView(prediction)
                            .overlay {
                                // Show subtle loading indicator when refreshing existing prediction
                                if isLoading {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .tint(BrandColors.goldBase)
                                        Text("Refreshing...")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(DS.Adaptive.textSecondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(DS.Adaptive.cardBackground.opacity(0.95))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
                                    )
                                }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else {
                        emptyState
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: reservedExpandedContentHeight, alignment: .top)
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: contentStateID)
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: reservedExpandedContentHeight)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isCompact ? 10 : 12)
        }
        // Animated glow effect when prediction is active
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    predictionColor.opacity(glowPulse ? 0.6 : 0.2),
                    lineWidth: hasPrediction ? 1.5 : 0
                )
                .blur(radius: glowPulse ? 4 : 2)
                .opacity(hasPrediction ? 1 : 0)
        )
        .shadow(
            color: hasPrediction ? predictionColor.opacity(glowPulse ? 0.3 : 0.1) : .clear,
            radius: glowPulse ? 12 : 6,
            x: 0,
            y: 0
        )
        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: glowPulse)
        .onChange(of: currentPrediction?.id) { _, _ in
            // Start/stop glow animation based on prediction state
            if currentPrediction != nil {
                glowPulse = true
            } else {
                glowPulse = false
            }
        }
        .onAppear {
            initializeDefaultCoin()
            startStalenessCheckTimer()
            // Start glow if there's already a prediction
            if currentPrediction != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    glowPulse = true
                }
            }
        }
        .onDisappear {
            stopStalenessCheckTimer()
            // Cancel any in-flight prediction request
            predictionTask?.cancel()
            predictionTask = nil
            // Reset loading state if task was cancelled
            if isLoading {
                isLoading = false
            }
        }
        .sheet(isPresented: $showCoinPicker) {
            CoinPickerSheet(selectedCoin: $selectedCoin, coins: Array(marketVM.allCoins.prefix(500)))
        }
        .sheet(isPresented: $showDetailView) {
            if let prediction = currentPrediction {
                AIPredictionDetailView(
                    prediction: prediction,
                    coinIconUrl: selectedCoin?.iconUrl,
                    onDismiss: { showDetailView = false }
                )
            }
        }
        .unifiedPaywallSheet(feature: .aiPricePredictions, isPresented: $showUpgradePrompt)
        .sheet(isPresented: $showAISettings) {
            NavigationStack {
                AISettingsView()
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onChange(of: selectedCoin?.id) { _, newCoinId in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Skip auto-prediction on initial load - user must tap "Predict" or "View"
                guard hasInitializedCoin else { return }
                
                // When coin changes, update the displayed prediction
                guard newCoinId != nil else { return }
                guard let symbol = selectedCoin?.symbol else { return }
                guard symbol.uppercased() != currentPrediction?.coinSymbol else { return }
                
                // Try to load cached prediction for new coin/timeframe first
                let key = "\(symbol.uppercased())_\(selectedTimeframe.rawValue)"
                
                if let cached = predictionService.cachedPredictions[key], !cached.isExpired {
                    // Load cached prediction instantly (no API call)
                    currentPrediction = cached
                } else {
                    // No cached prediction for new coin - show empty state
                    // User must tap "Predict" to generate (cost efficiency)
                    currentPrediction = nil
                }
            }
        }
        .onChange(of: selectedTimeframeBinding) { _, newValue in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Skip during initial load - user must tap "Predict" explicitly
                guard self.hasInitializedCoin else { return }
                
                // Sync from parent when timeframe changes via overlay
                if self.selectedTimeframe != newValue {
                    print("[AIPrediction] Timeframe changed: \(self.selectedTimeframe.rawValue) -> \(newValue.rawValue)")
                    self.selectedTimeframe = newValue
                    
                    // When timeframe changes, update the displayed prediction
                    // Either load cached prediction for new timeframe or clear to show empty state
                    guard let symbol = selectedCoin?.symbol else { return }
                    let key = "\(symbol.uppercased())_\(newValue.rawValue)"
                    
                    if let cached = predictionService.cachedPredictions[key], !cached.isExpired {
                        // Load cached prediction for new timeframe instantly (no API call)
                        print("[AIPrediction] Loaded cached prediction for \(key)")
                        currentPrediction = cached
                        // User is viewing a prediction - allow auto-restore
                        userCollapsed = false
                    } else {
                        // No cached prediction for this timeframe - show empty state
                        // User must tap "Predict" to generate (cost efficiency)
                        print("[AIPrediction] No cached prediction for \(key) - showing empty state")
                        currentPrediction = nil
                    }
                }
            }
        }
        .onChange(of: selectedTimeframe) { _, newValue in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Sync to parent
                if selectedTimeframeBinding != newValue {
                    selectedTimeframeBinding = newValue
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showTimeframePopover)
        .onChange(of: scenePhase) { _, newPhase in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Dismiss sheets when app goes to background
                if newPhase == .background {
                    showDetailView = false
                    showCoinPicker = false
                    showUpgradePrompt = false
                }
                // When app becomes active, check if prediction has expired
                if newPhase == .active {
                    checkPredictionExpiry()
                }
            }
        }
        // Handle notification actions from options menu
        .onReceive(NotificationCenter.default.publisher(for: .openPredictionDetailView)) { _ in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if currentPrediction != nil {
                    showDetailView = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearPrediction)) { _ in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                resetForNewPrediction()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshPrediction)) { _ in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                generatePrediction(forceRefresh: true)
            }
        }
    }
    
    // MARK: - Prediction Lifecycle
    
    /// Clear prediction and reset to empty state for new prediction
    /// Also marks userCollapsed = true so prediction won't auto-restore on next appear
    func resetForNewPrediction() {
        currentPrediction = nil
        errorMessage = nil
        userCollapsed = true  // Remember user's intent to keep it collapsed
        driftWarningDismissed = false  // Reset drift warning state for next prediction
    }
    
    /// Refresh the current prediction with force refresh
    func refreshPrediction() {
        generatePrediction(forceRefresh: true)
    }
    
    /// Open the detail view
    func openDetailView() {
        showDetailView = true
    }
    
    /// Check if current prediction has expired or doesn't match selected timeframe
    /// Called when app becomes active to ensure UI is in sync
    private func checkPredictionExpiry() {
        guard let prediction = currentPrediction else {
            // No current prediction - try to restore cached prediction for current coin/timeframe
            // Don't auto-generate - user must tap "Predict" (cost efficiency)
            _ = restoreCachedPredictionIfValid()
            return
        }
        
        // Check if prediction timeframe matches selected timeframe
        // If not, load the correct cached prediction or clear
        if prediction.timeframe != selectedTimeframe {
            guard let symbol = selectedCoin?.symbol else {
                currentPrediction = nil
                return
            }
            let key = "\(symbol.uppercased())_\(selectedTimeframe.rawValue)"
            
            if let cached = predictionService.cachedPredictions[key], !cached.isExpired {
                currentPrediction = cached
            } else {
                // No cached prediction for correct timeframe - show empty state
                // User must tap "Predict" to generate (cost efficiency)
                currentPrediction = nil
            }
            return
        }
        
        // Check if prediction has expired
        if prediction.timeRemaining <= 0 {
            // Expired prediction - show empty state
            // User must tap "Predict" to generate new one (cost efficiency)
            currentPrediction = nil
        }
    }
    
    // MARK: - Empty State (Single Row)
    
    /// Check if there's a cached prediction for current coin/timeframe
    /// Uses binding value as source of truth for timeframe
    private var hasCachedPrediction: Bool {
        guard let symbol = selectedCoin?.symbol else { return false }
        let key = "\(symbol.uppercased())_\(selectedTimeframeBinding.rawValue)"
        if let cached = predictionService.cachedPredictions[key] {
            // Only count as cached if not expired
            return !cached.isExpired
        }
        return false
    }
    
    private var emptyState: some View {
        HStack(alignment: .center, spacing: 10) {
            // Icon + Title - keep on same line
            HStack(spacing: 6) {
                GoldHeaderGlyph(systemName: "sparkles")
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("AI")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                    Text("Prediction")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                }
            }
            
            Spacer(minLength: 8)
            
            // Coin selector - flat, no background
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showCoinPicker = true
            } label: {
                HStack(spacing: 4) {
                    if let coin = selectedCoin {
                        CoinImageView(symbol: coin.symbol, url: coin.iconUrl, size: 18)
                            .frame(width: 18, height: 18)
                            .clipShape(Circle())
                            // SCROLL FIX: Ensure coin icon is properly clipped during scroll
                            .clipped()
                    } else {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                    }
                    
                    Text(selectedCoin?.symbol.uppercased() ?? "BTC")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            .buttonStyle(.plain)
            
            // Timeframe selector - flat, inlaid style
            // Uses background GeometryReader to capture frame dynamically on tap
            // PROFESSIONAL UX: Shows active state when picker is open
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showTimeframePopover = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .medium))
                        // PROFESSIONAL UX: Brighter gold when active
                        .foregroundColor(showTimeframePopover ? BrandColors.goldBase : BrandColors.goldBase.opacity(0.7))
                    
                    Text(selectedTimeframe.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        // PROFESSIONAL UX: Gold text when active
                        .foregroundColor(showTimeframePopover ? BrandColors.goldBase : DS.Adaptive.textPrimary)
                    
                    // PROFESSIONAL UX: Chevron flips up when active
                    Image(systemName: showTimeframePopover ? "chevron.up" : "chevron.down")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(showTimeframePopover ? BrandColors.goldBase : DS.Adaptive.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.15), value: showTimeframePopover)
            // PERFORMANCE FIX v4: Only capture frame when popover is showing - eliminates continuous GeometryReader updates
            // Frame capture is only needed to position the dropdown popover
            .modifier(TimeframeButtonFrameCapture(frame: $timeframeButtonFrame, isActive: showTimeframePopover && currentPrediction == nil))
            
            // Predict / View button — premium glass capsule with radial glow + gradient border
            if hasCachedPrediction {
                // Show cached prediction - down arrow to expand
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    loadCachedPrediction()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                        Text("View")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .heavy))
                    }
                }
                .buttonStyle(
                    PremiumCompactCTAStyle(
                        height: 30,
                        horizontalPadding: 11,
                        cornerRadius: 15,
                        font: .system(size: 12, weight: .bold, design: .rounded)
                    )
                )
            } else {
                // No cached prediction - show Predict button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if !predictionService.canGeneratePrediction && !hasPremiumAccess {
                        showUpgradePrompt = true
                        return
                    }
                    generatePrediction()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                        Text("Predict")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                }
                .buttonStyle(
                    PremiumCompactCTAStyle(
                        height: 30,
                        horizontalPadding: 11,
                        cornerRadius: 15,
                        font: .system(size: 12, weight: .bold, design: .rounded)
                    )
                )
                .disabled(selectedCoin == nil)
                .opacity(selectedCoin == nil ? 0.5 : 1)
            }
        }
    }
    
    /// Load a cached prediction for the current coin/timeframe
    /// User explicitly tapped "View" to see the prediction - clear collapsed flag
    private func loadCachedPrediction() {
        guard let symbol = selectedCoin?.symbol else { return }
        // Use binding value as source of truth for timeframe
        let timeframeToUse = selectedTimeframeBinding
        let key = "\(symbol.uppercased())_\(timeframeToUse.rawValue)"
        print("[AIPrediction] Loading cached prediction for key: \(key)")
        if let cached = predictionService.cachedPredictions[key], !cached.isExpired {
            userCollapsed = false  // User wants to see prediction - allow auto-restore
            currentPrediction = cached
            // Sync local timeframe if needed
            if selectedTimeframe != timeframeToUse {
                selectedTimeframe = timeframeToUse
            }
        } else {
            print("[AIPrediction] No valid cached prediction found for \(key)")
        }
    }
    
    // MARK: - Loading Phase Descriptions
    
    private var loadingPhaseTexts: [(title: String, icon: String)] {
        [
            ("Scanning market signals", "antenna.radiowaves.left.and.right"),
            ("Analyzing price action", "chart.xyaxis.line"),
            ("Evaluating momentum", "gauge.with.dots.needle.33percent"),
            ("Generating forecast", "sparkles")
        ]
    }
    
    private func startLoadingAnimations() {
        // Reset state without animation first
        loadingPhase = 0
        loadingOrbitAngle = 0
        loadingPulse = false
        loadingRingScale = 0.8
        
        // Phase cycling timer
        loadingPhaseTimer?.invalidate()
        loadingPhaseTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                loadingPhase = (loadingPhase + 1) % loadingPhaseTexts.count
            }
        }
        
        // FIX v28: Set target values after a brief layout pass.
        // The actual repeating animation is now driven by .animation(_:value:) modifiers
        // on the views themselves, which correctly repeat. The old approach used
        // withAnimation(.repeatForever) { value = X } which only animated the single
        // transition and stopped after one cycle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            loadingOrbitAngle = 360
            loadingPulse = true
            loadingRingScale = 1.1
        }
    }
    
    private func stopLoadingAnimations() {
        loadingPhaseTimer?.invalidate()
        loadingPhaseTimer = nil
        // FIX v28: Reset without animation to avoid residual animation artifacts
        var t = SwiftUI.Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            loadingOrbitAngle = 0
            loadingPulse = false
            loadingRingScale = 0.8
        }
    }
    
    // MARK: - Loading State (Compact — Home Screen)
    
    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.82)
                .tint(BrandColors.goldBase)
                .frame(width: 18, height: 18)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Generating \(selectedCoin?.symbol.uppercased() ?? "BTC") forecast")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                HStack(spacing: 4) {
                    Image(systemName: loadingPhaseTexts[loadingPhase].icon)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(BrandColors.goldBase.opacity(0.85))
                    Text(loadingPhaseTexts[loadingPhase].title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .animation(.easeInOut(duration: 0.25), value: loadingPhase)
            }
            
            Spacer(minLength: 6)
            
            Text(selectedTimeframe.displayName)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(BrandColors.goldBase.opacity(0.9))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(BrandColors.goldBase.opacity(isDark ? 0.14 : 0.09))
                        .overlay(Capsule().stroke(BrandColors.goldBase.opacity(0.24), lineWidth: 0.6))
                )
        }
        .padding(.vertical, 4)
        .onAppear { startLoadingAnimations() }
        .onDisappear { stopLoadingAnimations() }
    }
    
    // Error state is now handled inline in body as a banner above the empty state
    
    // MARK: - Expired State
    
    private func expiredState(_ prediction: AIPricePrediction) -> some View {
        VStack(spacing: 12) {
            // Outcome banner — shows whether the prediction was correct
            if let outcome = evaluatedOutcome {
                PredictionOutcomeBanner(
                    directionCorrect: outcome.directionCorrect ?? false,
                    withinRange: outcome.withinPriceRange ?? false,
                    predictedDirection: outcome.predictedDirection,
                    actualChangePercent: outcome.actualPriceChange ?? 0
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: evaluatedOutcome?.id)
            }
            
            // Header row
            HStack(spacing: 10) {
                // Icon reflects outcome if available
                ZStack {
                    Circle()
                        .fill(expiredHeaderColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: expiredHeaderIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(expiredHeaderColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(expiredHeaderTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text("\(prediction.coinSymbol) \(prediction.timeframe.displayName) prediction has ended")
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                // Dismiss button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismissExpiredState()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(DS.Adaptive.chipBackground)
                        )
                }
                .buttonStyle(.plain)
            }
            
            // Result summary
            HStack(spacing: 16) {
                // What was predicted vs actual
                VStack(alignment: .leading, spacing: 4) {
                    Text("PREDICTED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .tracking(0.5)
                    
                    HStack(spacing: 4) {
                        Image(systemName: prediction.direction == .bullish ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(prediction.direction.displayName)
                            .font(.system(size: 12, weight: .semibold))
                        
                        // Show checkmark/cross next to direction if evaluated
                        if let outcome = evaluatedOutcome {
                            Image(systemName: outcome.directionCorrect == true ? "checkmark" : "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(outcome.directionCorrect == true ? .green : .red)
                        }
                    }
                    .foregroundColor(prediction.direction.color)
                    
                    HStack(spacing: 6) {
                        Text(prediction.formattedPriceChange)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        // Show actual change if evaluated
                        if let outcome = evaluatedOutcome, let actual = outcome.actualPriceChange {
                            Text("→")
                                .font(.system(size: 9))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(String(format: "%+.2f%%", actual))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(actual >= 0 ? .green : .red)
                        }
                    }
                }
                
                Spacer()
                
                // Generate new prediction CTA
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    dismissExpiredState()
                    // Small delay to allow dismiss animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        generatePrediction(forceRefresh: true)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text("New Prediction")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(isDark ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [BrandColors.goldLight, BrandColors.goldBase],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(expiredHeaderColor.opacity(isDark ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(expiredHeaderColor.opacity(0.2), lineWidth: 0.5)
            )
            
            // Auto-dismiss hint
            Text("This will dismiss automatically...")
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
    }
    
    // MARK: - Expired State Helpers
    
    /// Dynamic color for expired state header based on outcome
    private var expiredHeaderColor: Color {
        guard let outcome = evaluatedOutcome else { return .orange }
        if outcome.directionCorrect == true && outcome.withinPriceRange == true {
            return Color(red: 0.0, green: 0.85, blue: 0.45) // Green - correct
        } else if outcome.directionCorrect == true {
            return .yellow // Partially correct
        } else {
            return .orange // Incorrect or not evaluated
        }
    }
    
    /// Dynamic icon for expired state header based on outcome
    private var expiredHeaderIcon: String {
        guard let outcome = evaluatedOutcome else { return "clock.badge.exclamationmark" }
        if outcome.directionCorrect == true && outcome.withinPriceRange == true {
            return "checkmark.seal.fill"
        } else if outcome.directionCorrect == true {
            return "checkmark.circle"
        } else {
            return "clock.badge.exclamationmark"
        }
    }
    
    /// Dynamic title for expired state header based on outcome
    private var expiredHeaderTitle: String {
        guard let outcome = evaluatedOutcome else { return "Prediction Expired" }
        if outcome.directionCorrect == true && outcome.withinPriceRange == true {
            return "Prediction Was Correct!"
        } else if outcome.directionCorrect == true {
            return "Direction Was Right"
        } else {
            return "Prediction Expired"
        }
    }
    
    // MARK: - Prediction Correct Notification
    
    /// Send a local notification alerting the user their prediction was correct
    private func sendPredictionCorrectNotification(for prediction: StoredPrediction) {
        let content = UNMutableNotificationContent()
        
        let wasFullyCorrect = prediction.withinPriceRange == true
        let actualChange = prediction.actualPriceChange.map { String(format: "%+.1f%%", $0) } ?? ""
        
        if wasFullyCorrect {
            content.title = "Prediction Correct! \(prediction.coinSymbol)"
            content.body = "\(prediction.predictedDirection.displayName) call was right and hit the target range. Actual move: \(actualChange)"
        } else {
            content.title = "Direction Correct! \(prediction.coinSymbol)"
            content.body = "\(prediction.predictedDirection.displayName) call was right. Actual move: \(actualChange). Target range was missed."
        }
        
        content.sound = .default
        content.userInfo = ["type": "predictionOutcome", "symbol": prediction.coinSymbol]
        
        let request = UNNotificationRequest(
            identifier: "prediction_outcome_\(prediction.id)",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[AIPredictionCard] Failed to send prediction outcome notification: \(error)")
            } else {
                print("[AIPredictionCard] Sent prediction correct notification for \(prediction.coinSymbol)")
            }
        }
    }
    
    // MARK: - Chart Loading Placeholder
    
    /// Shows a clean loading placeholder while sparkline data loads
    /// This prevents the "broken" partial chart appearance on app launch
    private func chartLoadingPlaceholder(for prediction: AIPricePrediction) -> some View {
        ZStack {
            // Background matching the chart style
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isDark
                        ? Color.white.opacity(0.03)
                        : Color.black.opacity(0.02)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isDark
                                ? Color.white.opacity(0.06)
                                : Color.black.opacity(0.05),
                            lineWidth: 0.5
                        )
                )
            
            // Loading indicator with prediction info
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(prediction.direction.color)
                    
                    Text("Loading chart...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                // Keep target fixed while loading so value doesn't appear to "drift" mid-render.
                HStack(spacing: 4) {
                    let loadingTarget = prediction.predictedPrice
                    Text("Target:")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(MarketFormat.priceCompact(loadingTarget))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(prediction.direction.color)
                    Text(prediction.formattedPriceChange)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(prediction.direction.color)
                }
            }
        }
    }
    
    // MARK: - Prediction Result View
    
    private func predictionResultView(_ prediction: AIPricePrediction) -> some View {
        // IMPORTANT: Use bestPrice(forSymbol:) for live prices from Firebase/Binance
        // This ensures header, drift calculation, chart, and metrics all use the same live price
        let freshCoin = marketVM.allCoins.first { $0.id == selectedCoin?.id }
        let freshLivePrice = marketVM.bestPrice(forSymbol: freshCoin?.symbol ?? selectedCoin?.symbol ?? "") ?? freshCoin?.priceUsd ?? selectedCoin?.priceUsd
        
        // Calculate price drift from prediction base to current live price
        let livePrice = freshLivePrice ?? prediction.currentPrice
        let priceDrift = prediction.currentPrice > 0 
            ? abs((livePrice - prediction.currentPrice) / prediction.currentPrice) * 100 
            : 0
        // Show warning if price moved >3% since prediction AND prediction is at least 5 minutes old
        // The grace period prevents showing drift warning immediately after refresh/generation
        // Also respect user dismissal - don't keep showing the warning if they dismissed it
        // DEDUP: Hide the drift badge when the staleness banner is already showing (needsRefresh)
        // to avoid two "refresh" prompts on screen at the same time.
        let isNewPrediction = prediction.elapsedTime < 300 // 5 minutes grace period
        let showDriftWarning = priceDrift > 3.0 && !isNewPrediction && !driftWarningDismissed && !prediction.needsRefresh
        
        return VStack(spacing: 10) {
            // Row 1: Header - compact layout with inlaid controls
            HStack(spacing: 6) {
                // Coin selector
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showCoinPicker = true
                } label: {
                    HStack(spacing: 4) {
                        if let coin = selectedCoin {
                            CoinImageView(symbol: coin.symbol, url: coin.iconUrl, size: 18)
                                .frame(width: 18, height: 18)
                                .clipShape(Circle())
                                // SCROLL FIX: Ensure coin icon is properly clipped during scroll
                                .clipped()
                        }
                        
                        Text(prediction.coinSymbol)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                
                // Live price
                Text(formatPriceCompact(livePrice))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                // Direction badge - compact for header
                PredictionDirectionBadge(direction: prediction.direction, compact: true)
                
                Spacer(minLength: 4)
                
                // Timeframe selector - flat, inlaid style
                // PROFESSIONAL UX: Shows active state when picker is open
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showTimeframePopover = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .medium))
                            // PROFESSIONAL UX: Brighter gold when active
                            .foregroundColor(showTimeframePopover ? BrandColors.goldBase : BrandColors.goldBase.opacity(0.7))
                        
                        Text(selectedTimeframe.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            // PROFESSIONAL UX: Gold text when active
                            .foregroundColor(showTimeframePopover ? BrandColors.goldBase : DS.Adaptive.textPrimary)
                        
                        // PROFESSIONAL UX: Chevron flips up when active
                        Image(systemName: showTimeframePopover ? "chevron.up" : "chevron.down")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(showTimeframePopover ? BrandColors.goldBase : DS.Adaptive.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.15), value: showTimeframePopover)
                // PERFORMANCE FIX v4: Only capture frame when popover is showing - eliminates continuous GeometryReader updates
                // Frame capture is only needed to position the dropdown popover
                .modifier(TimeframeButtonFrameCapture(frame: $timeframeButtonFrame, isActive: showTimeframePopover))
                
                // Collapse button - flat, no background
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    resetForNewPrediction()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse prediction")
            }
            
            // Price drift warning - shows when live price has moved significantly since prediction
            // User can dismiss this warning, and it won't reappear until a new prediction is generated
            if showDriftWarning {
                PriceDriftWarningBadge(
                    driftPercent: priceDrift,
                    onRefresh: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        driftWarningDismissed = false // Reset for new prediction
                        generatePrediction(forceRefresh: true)
                    },
                    onDismiss: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.2)) {
                            driftWarningDismissed = true
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Prediction tracking status — show when prediction is on track (direction correct)
            // Only show if drift warning is NOT showing (mutually exclusive display)
            if !showDriftWarning && !isLoading {
                let priceMove = prediction.currentPrice > 0
                    ? ((livePrice - prediction.currentPrice) / prediction.currentPrice) * 100
                    : 0
                
                let isDirectionCorrect: Bool = {
                    switch prediction.direction {
                    case .bullish:  return priceMove > 0.5  // >0.5% in predicted direction
                    case .bearish:  return priceMove < -0.5
                    case .neutral:  return abs(priceMove) < 1.0
                    }
                }()
                
                let isInPriceRange = livePrice >= prediction.predictedPriceLow
                    && livePrice <= prediction.predictedPriceHigh
                let hasReachedDirectionalTarget: Bool = {
                    switch prediction.direction {
                    case .bullish:
                        // Bullish target is reached only when price trades at/above target.
                        return livePrice >= prediction.predictedPrice
                    case .bearish:
                        // Bearish target is reached only when price trades at/below target.
                        return livePrice <= prediction.predictedPrice
                    case .neutral:
                        return isInPriceRange
                    }
                }()
                
                // Show banner: "Target Hit" if in range, "On Track" if direction correct
                // Don't show if prediction is brand new (<2 min) — too early to judge
                let hasEnoughTime = prediction.elapsedTime > 120
                
                // For neutral predictions, require MORE time and MORE price stability
                // to show "Target Reached" — previously it triggered almost instantly
                // because neutral range is always centered on the current price
                let neutralMinTime: TimeInterval = {
                    switch prediction.timeframe {
                    case .hour: return 1800        // 30 min for 1H
                    case .fourHours: return 3600   // 1 hour for 4H
                    case .twelveHours: return 7200 // 2 hours for 12H
                    case .day: return 14400        // 4 hours for 24H
                    case .week: return 86400       // 1 day for 7D
                    case .month: return 259200     // 3 days for 30D
                    }
                }()
                let neutralHasEnoughTime = prediction.elapsedTime > neutralMinTime
                
                // For directional predictions: show Target Hit/On Track as before
                // For neutral predictions: only show after significant time has passed
                let shouldShowBanner: Bool = {
                    if prediction.direction == .neutral {
                        return neutralHasEnoughTime && isInPriceRange && isDirectionCorrect
                    } else {
                        return hasEnoughTime && hasReachedDirectionalTarget && isDirectionCorrect
                    }
                }()
                
                if shouldShowBanner {
                    PredictionTrackingBanner(
                        status: .targetHit,
                        directionLabel: prediction.direction.displayName,
                        movePercent: priceMove,
                        onNewPrediction: hasPremiumAccess ? {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            generatePrediction(forceRefresh: true)
                        } : nil,
                        onUpgrade: hasPremiumAccess ? nil : {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showUpgradePrompt = true
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if hasEnoughTime && isDirectionCorrect && prediction.direction != .neutral {
                    PredictionTrackingBanner(
                        status: .onTrack,
                        directionLabel: prediction.direction.displayName,
                        movePercent: priceMove
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            
            // Row 2: Chart (tappable for details) with clear NOW/TARGET labels
            // Use fresh sparkline data from freshCoin (already fetched at top of function)
            // This ensures the chart always shows current data with actual historical prices
            let freshSparklineData: [Double]? = {
                // Priority: fresh coin's raw sparkline -> selectedCoin fallback
                let live = freshLivePrice
                func withLiveTail(_ input: [Double]) -> [Double] {
                    var series = input
                    if let live, live.isFinite, live > 0, let last = series.last {
                        let drift = abs(live - last) / max(last, 1)
                        if drift > 0.0005 { series.append(live) }
                    }
                    return series
                }
                if let coin = freshCoin {
                    let rawSparkline = withLiveTail(coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 })
                    // Require at least 10 points for a smooth chart (consistent with other views)
                    if rawSparkline.count >= 10 {
                        return rawSparkline
                    }
                }
                // Fallback: use selectedCoin's raw sparkline data
                let fallback = withLiveTail(selectedCoin?.sparklineIn7d.filter { $0.isFinite && $0 > 0 } ?? [])
                if fallback.count >= 10 { return fallback }
                
                // Deterministic disk-cache fallback: exact coin id, then exact symbol key.
                let diskCache = WatchlistSparklineService.loadCachedSparklinesSync()
                let resolvedCoinID = (freshCoin?.id ?? selectedCoin?.id)?.lowercased()
                let resolvedSymbolLower = (freshCoin?.symbol ?? selectedCoin?.symbol ?? "").lowercased()
                let resolvedSymbolUpper = resolvedSymbolLower.uppercased()
                if let cached = resolvedCoinID.flatMap({ diskCache[$0] }) ?? diskCache[resolvedSymbolLower] ?? diskCache[resolvedSymbolUpper] {
                    let cleaned = withLiveTail(cached.filter { $0.isFinite && $0 > 0 })
                    if cleaned.count >= 10 {
                        return cleaned
                    }
                }
                return fallback.isEmpty ? nil : fallback
            }()
            
            // Only show chart if we have valid sparkline data (at least 10 points for smooth rendering)
            // This prevents the "broken" loading appearance when data isn't ready
            let hasValidSparkline = (freshSparklineData?.count ?? 0) >= 10
            
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showDetailView = true
            } label: {
                if hasValidSparkline {
                    // Keep target fixed for this prediction instance; only the current price is live.
                    let chartBasePrice = freshLivePrice ?? prediction.currentPrice
                    let chartTargetPrice = prediction.predictedPrice
                    
                    MiniPredictionChart(
                        currentPrice: chartBasePrice,
                        predictedPrice: chartTargetPrice,
                        direction: prediction.direction,
                        sparklineData: freshSparklineData,
                        livePrice: freshLivePrice,
                        timeframe: prediction.timeframe,  // Pass timeframe for appropriate historical data slicing
                        generatedAt: prediction.generatedAt
                    )
                    .frame(height: 130) // Chart with Y-axis and X-axis labels - taller for better readability
                    .clipped()
                } else {
                    // Loading placeholder while sparkline data loads
                    chartLoadingPlaceholder(for: prediction)
                        .frame(height: 130)
                        .clipped()
                }
            }
            .buttonStyle(.plain)
            
            // Row 3: Premium metrics bar - target remains fixed for this prediction
            PredictionMetricsBar(
                prediction: prediction,
                livePrice: freshLivePrice,
                onDetailsTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showDetailView = true
                },
                onRefreshTap: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if predictionService.canGeneratePrediction {
                        generatePrediction(forceRefresh: true)
                    } else {
                        showUpgradePrompt = true
                    }
                }
            )
            .id(predictionUpdateTrigger) // Force refresh when timer triggers staleness check
        }
    }
    
    /// Format countdown for display - handles all timeframes from 1H to 30D
    private func formatCountdown(_ remaining: TimeInterval) -> String {
        if remaining <= 0 { return "Expired" }
        
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        
        if days > 0 {
            // 7D and 30D timeframes
            return "in \(days)d \(hours)h"
        } else if hours > 0 {
            // 4H and 24H timeframes
            return "in \(hours)h \(minutes)m"
        } else if minutes > 0 {
            // 1H timeframe or final minutes
            return "in \(minutes)m"
        } else {
            // Final seconds - show urgency
            return "in \(seconds)s"
        }
    }
    
    /// Format price in compact form (e.g., $89.4K)
    private func formatPriceCompact(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.1fK", value / 1_000)
        } else if value >= 1 {
            return String(format: "$%.2f", value)
        } else {
            return String(format: "$%.4f", value)
        }
    }
    
    // MARK: - Actions
    
    private func initializeDefaultCoin() {
        // IMPORTANT: Set the flag BEFORE setting selectedCoin to prevent onChange from triggering
        // This prevents auto-prediction on app launch - user must tap "Predict" explicitly
        hasInitializedCoin = false
        
        if selectedCoin == nil {
            selectedCoin = marketVM.allCoins.first { $0.symbol.uppercased() == "BTC" }
        }
        
        // Auto-restore cached prediction if available and not expired
        // This allows the app to return to the previous state without re-loading
        restoreCachedPredictionIfValid()
        
        // Mark initialization complete after a longer delay to ensure all SwiftUI
        // onChange callbacks have finished their async dispatches
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hasInitializedCoin = true
        }
    }
    
    /// Restore a cached prediction if it exists and hasn't expired
    /// This runs on app launch to restore the previous state without triggering a new API call
    /// Respects user's collapse preference - won't auto-restore if user explicitly collapsed
    /// - Returns: true if a valid cached prediction was restored, false otherwise
    @discardableResult
    private func restoreCachedPredictionIfValid() -> Bool {
        // FIX v23: Skip if we already have a current prediction for this coin/timeframe.
        // In a LazyVStack, onAppear fires every time the section scrolls into view,
        // causing "Restored cached prediction" to log 8+ times per session.
        if currentPrediction != nil { return true }
        
        // Respect user's collapse preference - don't auto-restore if they collapsed it
        guard !userCollapsed else {
            // NOTE: This fires frequently (every scroll/onAppear). Logging removed to reduce noise.
            return false
        }
        
        guard let symbol = selectedCoin?.symbol else { return false }
        // Use binding as source of truth - it may have been updated from AppStorage before local state syncs
        let timeframeToUse = selectedTimeframeBinding
        // Also sync local state
        if selectedTimeframe != timeframeToUse {
            selectedTimeframe = timeframeToUse
        }
        let key = "\(symbol.uppercased())_\(timeframeToUse.rawValue)"
        
        // Check if we have a cached prediction
        if let cached = predictionService.cachedPredictions[key] {
            // Restore any non-expired prediction — even stale ones.
            // Stale predictions (>75% elapsed) will show the refresh warning banner,
            // which is better UX than showing an empty "Generate Prediction" state.
            // The user keeps seeing their last prediction + a prompt to refresh.
            if !cached.isExpired {
                currentPrediction = cached
                let progress = Int(cached.timeframeProgress * 100)
                print("[AIPrediction] Restored cached prediction for \(key) (\(progress)% elapsed\(cached.needsRefresh ? ", showing refresh banner" : ""))")
                // Start glow animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    glowPulse = true
                }
                return true
            }
        }
        return false
    }
    
    // MARK: - Staleness & Expiration Timer
    
    /// Start timer to check prediction staleness every 30 seconds
    private func startStalenessCheckTimer() {
        stopStalenessCheckTimer() // Clear any existing timer
        
        // TIMER LEAK FIX: Removed [self] strong capture. Added timer.isValid guard
        // so the callback exits early if the timer was invalidated in onDisappear.
        stalenessCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { timer in
            guard timer.isValid else { return }
            Task { @MainActor in
                // Trigger UI update by changing the trigger UUID
                // This causes the view to re-evaluate staleness properties
                predictionUpdateTrigger = UUID()
                
                // Auto-expire predictions with transition state
                if let prediction = currentPrediction, prediction.isExpired, !isShowingExpired {
                    // Store the prediction for the expired state display
                    expiredPrediction = prediction
                    
                    // Show expired state - no animation to prevent height jumping
                    isShowingExpired = true
                    currentPrediction = nil
                    glowPulse = false
                    evaluatedOutcome = nil
                    
                    // Trigger accuracy evaluation for this and any other expired predictions
                    // This compares the predicted price vs actual price to track accuracy
                    Task {
                        await PredictionAccuracyService.shared.evaluatePendingPredictions()
                        
                        // Look up the evaluated result for this prediction
                        let stored = PredictionAccuracyService.shared.storedPredictions
                            .first { $0.id == prediction.id && $0.isEvaluated }
                        
                        if let stored = stored {
                            evaluatedOutcome = stored
                            
                            // Send a local notification if the prediction was correct
                            if stored.directionCorrect == true {
                                sendPredictionCorrectNotification(for: stored)
                            }
                        }
                    }
                    
                    // Auto-collapse after showing expired state for 12 seconds
                    // (extended from 8s to give user time to see the outcome)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                        isShowingExpired = false
                        expiredPrediction = nil
                        evaluatedOutcome = nil
                    }
                }
            }
        }
    }
    
    private func stopStalenessCheckTimer() {
        stalenessCheckTimer?.invalidate()
        stalenessCheckTimer = nil
    }
    
    /// Dismiss expired state and reset
    private func dismissExpiredState() {
        isShowingExpired = false
        expiredPrediction = nil
    }
    
    private func generatePrediction(forceRefresh: Bool = false) {
        guard let coin = selectedCoin else { return }
        
        // Cancel any existing prediction task and safety timer
        predictionTask?.cancel()
        loadingSafetyTimer?.invalidate()
        
        // User explicitly requested a prediction - clear the collapsed flag
        // This allows auto-restore on next app open
        userCollapsed = false
        
        // IMPORTANT: Use binding value as source of truth to avoid race conditions
        // The local selectedTimeframe might be out of sync due to async onChange deferrals
        let timeframeToUse = selectedTimeframeBinding
        // Also sync local state to ensure consistency
        if selectedTimeframe != timeframeToUse {
            selectedTimeframe = timeframeToUse
        }
        
        // Don't clear currentPrediction immediately - preserve it until we have a new one
        // This prevents losing the prediction if the refresh fails
        if forceRefresh {
            print("[AIPredictionCard] Force refresh requested - preserving current prediction until success")
        }
        glowPulse = false
        // FIX v28: Wrap loading state change in animation for smooth transition
        withAnimation(.easeInOut(duration: 0.3)) {
            isLoading = true
        }
        errorMessage = nil
        
        // Create the prediction task first
        let task = Task { @MainActor in
            defer {
                // Always reset loading state and invalidate timer when task completes
                loadingSafetyTimer?.invalidate()
                loadingSafetyTimer = nil
                // Ensure loading is always cleared in defer as a safety net
                if isLoading {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isLoading = false
                    }
                }
            }
            
            do {
                // Check for cancellation before starting
                try Task.checkCancellation()
                
                let prediction = try await predictionService.generatePrediction(
                    for: coin.symbol,
                    coinName: coin.name,
                    timeframe: timeframeToUse,  // Use captured binding value
                    forceRefresh: forceRefresh
                )
                
                // DO NOT check cancellation here — if the prediction was successfully
                // generated we should always use it. The safety timer may have set the
                // cancellation flag while the service was still finishing, and throwing
                // here would discard a perfectly valid result (causing the "Request timed
                // out" error even though the prediction succeeded).
                
                // Update state - success (animated for smooth transition)
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPrediction = prediction
                    isLoading = false
                }
                errorMessage = nil  // Clear any stale timeout banner
                driftWarningDismissed = false // Reset for new prediction
            } catch is CancellationError {
                // Task was cancelled before the service could return a result.
                // Preserve the existing prediction (don't nil it out).
                print("[AIPredictionCard] Prediction task cancelled (safety timeout)")
                withAnimation(.easeInOut(duration: 0.3)) {
                    isLoading = false
                }
                if currentPrediction == nil {
                    // Only show error if there's no existing prediction to display
                    errorMessage = "Request timed out. Please try again."
                } else {
                    // We still have the old prediction — show a less alarming message
                    errorMessage = "Refresh timed out. Showing previous prediction."
                }
            } catch {
                // Handle error
                print("[AIPredictionCard] Prediction error: \(error.localizedDescription)")
                
                // Provide user-friendly error messages
                let userMessage: String
                let errorText = error.localizedDescription.lowercased()
                
                if errorText.contains("quota") || errorText.contains("exceeded") {
                    userMessage = "API quota exceeded. Add your OpenAI key in Settings."
                } else if errorText.contains("rate") && errorText.contains("limit") {
                    userMessage = "Too many requests. Please wait a moment."
                } else if errorText.contains("timeout") {
                    userMessage = "Request timed out. Please try again."
                } else if errorText.contains("api key") || errorText.contains("unauthorized") || errorText.contains("not configured") {
                    userMessage = "OpenAI API key required. Tap to configure in Settings."
                } else {
                    userMessage = "Unable to generate prediction. Tap to retry."
                }
                
                // Update state
                errorMessage = userMessage
                withAnimation(.easeInOut(duration: 0.3)) {
                    isLoading = false
                }
            }
        }
        
        // Store the task handle for cancellation support
        predictionTask = task
        
        // Start safety timer that cancels the task if it takes too long
        // The task's defer block will handle resetting UI state when cancelled
        loadingSafetyTimer = Timer.scheduledTimer(withTimeInterval: loadingSafetyTimeoutSeconds, repeats: false) { [task] _ in
            print("[AIPredictionCard] Safety timeout triggered - cancelling prediction task")
            task.cancel()
        }
    }
}

// MARK: - Mini Confidence Bar

struct MiniConfidenceBar: View {
    let score: Int
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background - LIGHT MODE FIX: Adaptive bar background
                Capsule()
                    .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                
                // Fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.6), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(min(100, max(0, score))) / 100)
            }
        }
    }
}

// MARK: - Coin Picker Sheet

struct CoinPickerSheet: View {
    // MARK: - Flexible API
    // Mode 1 (AI Predictions): Pass selectedCoin binding + coins array
    // Mode 2 (Trading): Pass selectedSymbol binding + onSelect callback (self-loads coins)
    
    @Binding private var selectedCoin: MarketCoin?
    @Binding private var selectedSymbol: String
    private let externalCoins: [MarketCoin]?
    private let onSelectCallback: ((MarketCoin) -> Void)?
    private let selfLoading: Bool
    
    // Mode 1: AI Predictions (external coins provided)
    init(selectedCoin: Binding<MarketCoin?>, coins: [MarketCoin]) {
        self._selectedCoin = selectedCoin
        self._selectedSymbol = .constant("")
        self.externalCoins = coins
        self.onSelectCallback = nil
        self.selfLoading = false
    }
    
    // Mode 2: Trading / general use (self-loads coins from LivePriceManager)
    init(selectedSymbol: Binding<String>, onSelect: ((MarketCoin) -> Void)? = nil) {
        self._selectedCoin = .constant(nil)
        self._selectedSymbol = selectedSymbol
        self.externalCoins = nil
        self.onSelectCallback = onSelect
        self.selfLoading = true
    }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    
    // Self-loading state (Mode 2)
    @State private var loadedCoins: [MarketCoin] = []
    @State private var isLoading: Bool = false
    
    /// Prevents coin list updates after a selection is made,
    /// which would cause SwiftUI to rebuild views and flash all logos blank.
    @State private var isDismissing: Bool = false
    
    // Recent coins persistence
    @State private var recentSymbols: [String] = []
    private static let recentCoinsKey = "coin_picker_recent_coins"
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Resolved coins: external or self-loaded
    private var coins: [MarketCoin] {
        externalCoins ?? loadedCoins
    }
    
    // Whether the current coin is selected (works for both modes)
    private func isSelected(_ coin: MarketCoin) -> Bool {
        if selfLoading {
            return coin.symbol.uppercased() == selectedSymbol.uppercased()
        }
        return selectedCoin?.id == coin.id
    }
    
    // Stablecoins to exclude from predictions (no point predicting $1)
    private static let stablecoins: Set<String> = [
        "usdt", "usdc", "dai", "busd", "tusd", "usdp", "usdd", "gusd", 
        "frax", "lusd", "susd", "eurs", "eurt", "usdn", "husd", "fdusd",
        "pyusd", "eurc", "ustc", "pax", "cusd", "ceur"
    ]
    
    // Popular coins for quick access
    private static let popularSymbols: [String] = [
        "btc", "eth", "sol", "xrp", "bnb", "ada", "doge", "avax", "dot", "matic", "link", "shib"
    ]
    
    private var nonStableCoins: [MarketCoin] {
        let base = coins.filter { coin in
            !Self.stablecoins.contains(coin.symbol.lowercased())
        }
        // Sort by CoinGecko rank first (most reliable, always set for top coins),
        // then fall back to market cap for coins without a rank.
        // This ensures BTC (#1) always appears first even when marketCap is nil.
        return base.sorted { a, b in
            let aRank = a.marketCapRank ?? Int.max
            let bRank = b.marketCapRank ?? Int.max
            
            // If at least one coin has a valid rank, sort by rank ascending (lower = better)
            if aRank != Int.max || bRank != Int.max {
                if aRank != bRank { return aRank < bRank }
            }
            
            // Both lack rank: fall back to market cap descending
            let aCap = a.marketCap ?? 0
            let bCap = b.marketCap ?? 0
            return aCap > bCap
        }
    }
    
    private var popularCoins: [MarketCoin] {
        Self.popularSymbols.compactMap { symbol in
            nonStableCoins.first { $0.symbol.lowercased() == symbol }
        }
    }
    
    private var topGainers: [MarketCoin] {
        nonStableCoins
            .filter { ($0.priceChangePercentage24hInCurrency ?? 0) > 0 }
            .sorted(by: { ($0.priceChangePercentage24hInCurrency ?? 0) > ($1.priceChangePercentage24hInCurrency ?? 0) })
            .prefix(8)
            .map { $0 }
    }
    
    private var filteredCoins: [MarketCoin] {
        if searchText.isEmpty {
            return nonStableCoins
        }
        let query = searchText.lowercased()
        return nonStableCoins.filter {
            $0.symbol.lowercased().contains(query) ||
            $0.name.lowercased().contains(query)
        }.sorted { a, b in
            // Exact symbol match first
            let aExact = a.symbol.lowercased() == query
            let bExact = b.symbol.lowercased() == query
            if aExact != bExact { return aExact }
            // Then by rank (reliable even when marketCap is nil)
            let aRank = a.marketCapRank ?? Int.max
            let bRank = b.marketCapRank ?? Int.max
            if aRank != bRank { return aRank < bRank }
            return (a.marketCap ?? 0) > (b.marketCap ?? 0)
        }
    }
    
    private var isSearching: Bool {
        !searchText.isEmpty
    }
    
    // Recent coins resolved from saved symbols
    private var recentCoins: [MarketCoin] {
        recentSymbols.compactMap { symbol in
            coins.first { $0.symbol.uppercased() == symbol.uppercased() }
        }
    }
    
    // Sparkline direction helper
    private func is7dPositive(for coin: MarketCoin) -> Bool {
        let data = coin.sparklineIn7d
        if data.count > 10,
           let first = data.first, let last = data.last,
           first > 0, last > 0 {
            let relDiff = (last - first) / first
            if abs(relDiff) > 0.005 { return relDiff >= 0 }
        }
        if let p7 = coin.priceChangePercentage7dInCurrency, p7.isFinite { return p7 >= 0 }
        guard let first = data.first, let last = data.last,
              first > 0, last > 0 else { return true }
        return last >= first
    }
    
    // MARK: - Selection Action
    
    private func selectCoin(_ coin: MarketCoin) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        saveToRecentCoins(coin.symbol)
        
        // LOGO FIX: Freeze the coin list BEFORE any state changes.
        // Without this, the binding/callback changes trigger LivePriceManager
        // to publish a new coins array, which causes SwiftUI to rebuild every
        // coin row and flash all logos blank during the dismiss animation.
        isDismissing = true
        
        if selfLoading {
            // CRITICAL: Call callback FIRST so supporting state (quote, exchange)
            // is set before the symbol binding triggers handleSymbolChange()
            onSelectCallback?(coin)
            selectedSymbol = coin.symbol.uppercased()
        } else {
            selectedCoin = coin
        }
        dismiss()
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Search bar
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    
                    if isLoading && coins.isEmpty {
                        // Loading state
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(BrandColors.goldBase)
                                .scaleEffect(1.2)
                            Text("Loading coins...")
                                .font(.system(size: 14))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else if isSearching {
                        // Search results
                        searchResultsSection
                    } else {
                        // Recent coins (if any)
                        if !recentCoins.isEmpty {
                            recentCoinsSection
                        }
                        
                        // Popular coins horizontal scroll
                        popularCoinsSection
                        
                        // Top gainers section
                        if !topGainers.isEmpty {
                            topGainersSection
                        }
                        
                        // All coins section
                        allCoinsSection
                    }
                }
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Select Coin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [BrandColors.goldBase, BrandColors.goldBase.opacity(0.82)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Done")
                    .accessibilityHint("Close coin picker")
                }
            }
            .task {
                loadRecentCoins()
                if selfLoading {
                    await loadCoins()
                }
            }
            // Real-time price updates (applies to both modes)
            .onReceive(LivePriceManager.shared.throttledPublisher) { updatedCoins in
                // LOGO FIX: Skip updates once a coin has been selected.
                // Replacing loadedCoins during the dismiss animation would force
                // SwiftUI to rebuild all coin rows, creating new CachingAsyncImage
                // instances that start blank while re-loading from cache/network.
                guard !isDismissing else { return }
                // MEMORY FIX v7: Defer state changes to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    if selfLoading && !updatedCoins.isEmpty {
                        loadedCoins = updatedCoins
                        if isLoading { isLoading = false }
                    }
                }
            }
        }
    }
    
    // MARK: - Data Loading (Mode 2: self-loading)
    
    @MainActor
    private func loadCoins() async {
        isLoading = true
        
        // Try LivePriceManager first (unified prices)
        let liveCoins = LivePriceManager.shared.currentCoinsList
        if !liveCoins.isEmpty {
            loadedCoins = liveCoins
            isLoading = false
            return
        }
        
        // Fallback to MarketViewModel
        let marketCoins = MarketViewModel.shared.allCoins
        loadedCoins = marketCoins
        isLoading = false
    }
    
    // MARK: - Recent Coins Persistence
    
    private func loadRecentCoins() {
        if let symbols = UserDefaults.standard.stringArray(forKey: Self.recentCoinsKey) {
            recentSymbols = symbols
        }
    }
    
    private func saveToRecentCoins(_ symbol: String) {
        var recent = recentSymbols
        recent.removeAll { $0.uppercased() == symbol.uppercased() }
        recent.insert(symbol.uppercased(), at: 0)
        if recent.count > 5 { recent = Array(recent.prefix(5)) }
        recentSymbols = recent
        UserDefaults.standard.set(recent, forKey: Self.recentCoinsKey)
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            TextField("Search coins...", text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(DS.Adaptive.textPrimary)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchFocused = true
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isDark ? 0.06 : 0.1))
        )
    }
    
    // MARK: - Recent Coins Section
    
    private var recentCoinsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Recent", icon: "clock.arrow.circlepath")
                .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentCoins, id: \.id) { coin in
                        Button {
                            selectCoin(coin)
                        } label: {
                            HStack(spacing: 6) {
                                CoinImageView(symbol: coin.symbol, url: coin.iconUrl, size: 24)
                                    .frame(width: 24, height: 24)
                                    .clipShape(Circle())
                                
                                Text(coin.symbol.uppercased())
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(isSelected(coin) ? Color.black : DS.Adaptive.textPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isSelected(coin) ? BrandColors.goldBase : Color.white.opacity(isDark ? 0.06 : 0.08))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isSelected(coin) ? BrandColors.goldBase.opacity(0.8) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Popular Coins Section
    
    private var popularCoinsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Popular", icon: "star.fill")
                .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(popularCoins, id: \.id) { coin in
                        popularCoinChip(coin)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 20)
    }
    
    private func popularCoinChip(_ coin: MarketCoin) -> some View {
        Button {
            selectCoin(coin)
        } label: {
            HStack(spacing: 8) {
                CoinImageView(symbol: coin.symbol, url: coin.iconUrl, size: 28)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(coin.symbol.uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                    
                    if let change = coin.priceChangePercentage24hInCurrency {
                        Text(String(format: "%@%.1f%%", change >= 0 ? "+" : "", change))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundColor(change >= 0 ? .green : .red)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isDark ? 0.05 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected(coin) ? BrandColors.goldBase.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Top Gainers Section
    
    private var topGainersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Top Gainers", icon: "chart.line.uptrend.xyaxis")
                .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(topGainers, id: \.id) { coin in
                        topGainerCard(coin)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 20)
    }
    
    private func topGainerCard(_ coin: MarketCoin) -> some View {
        Button {
            selectCoin(coin)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Top row: icon + name
                HStack(spacing: 8) {
                    CoinImageView(symbol: coin.symbol, url: coin.iconUrl, size: 32)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(coin.symbol.uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .lineLimit(1)
                        
                        Text(coin.name)
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .lineLimit(1)
                    }
                }
                
                // Bottom: price on one line, percentage badge on next
                VStack(alignment: .leading, spacing: 5) {
                    // PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing
                    if let price = MarketViewModel.shared.bestPrice(for: coin.id) ?? coin.priceUsd {
                        Text(MarketFormat.price(price))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    
                    if let change = coin.priceChangePercentage24hInCurrency {
                        Text(String(format: "+%.1f%%", change))
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundColor(.green)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.15))
                            )
                    }
                }
            }
            .padding(12)
            .frame(width: 148)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isDark ? 0.04 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected(coin) ? BrandColors.goldBase.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - All Coins Section
    
    private var allCoinsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "All Coins", icon: "list.bullet", count: nonStableCoins.count)
                .padding(.horizontal, 16)
            
            LazyVStack(spacing: 0) {
                ForEach(Array(nonStableCoins.enumerated()), id: \.element.id) { index, coin in
                    coinRow(coin, displayRank: index + 1)
                    
                    if coin.id != nonStableCoins.last?.id {
                        Divider()
                            .background(DS.Adaptive.divider)
                            .padding(.leading, 78)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isDark ? 0.03 : 0.05))
                    .padding(.horizontal, 16)
            )
        }
    }
    
    // MARK: - Search Results Section
    
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if filteredCoins.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text("No coins found")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Text("Try a different search term")
                        .font(.system(size: 13))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                sectionHeader(title: "Results", icon: "magnifyingglass", count: filteredCoins.count)
                    .padding(.horizontal, 16)
                
                LazyVStack(spacing: 0) {
                    ForEach(filteredCoins, id: \.id) { coin in
                        coinRow(coin, displayRank: coin.marketCapRank)
                        
                        if coin.id != filteredCoins.last?.id {
                            Divider()
                                .background(DS.Adaptive.divider)
                                .padding(.leading, 78)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(isDark ? 0.03 : 0.05))
                        .padding(.horizontal, 16)
                )
            }
        }
    }
    
    // MARK: - Coin Row (with rank, sparkline, price, change, selection)
    
    private func coinRow(_ coin: MarketCoin, displayRank: Int? = nil) -> some View {
        let selected = isSelected(coin)
        return Button {
            selectCoin(coin)
        } label: {
            HStack(spacing: 0) {
                // Rank number (sequential from list position, or API rank for search)
                if let rank = displayRank {
                    Text("\(rank)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(selected ? BrandColors.goldBase : DS.Adaptive.textTertiary)
                        .frame(width: 26, alignment: .trailing)
                } else {
                    Color.clear.frame(width: 26)
                }
                
                // Icon
                Group {
                    CoinImageView(symbol: coin.symbol, url: coin.iconUrl, size: 36)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                }
                .padding(.leading, 8)
                
                // Name and symbol — fixed width to keep trailing columns aligned
                VStack(alignment: .leading, spacing: 2) {
                    Text(coin.symbol.uppercased())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(selected ? BrandColors.goldBase : DS.Adaptive.textPrimary)
                        .lineLimit(1)
                    
                    Text(coin.name)
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 7-day sparkline (upgraded to match market page quality)
                Group {
                    if coin.sparklineIn7d.count >= 10 {
                        SparklineView(
                            data: coin.sparklineIn7d,
                            isPositive: is7dPositive(for: coin),
                            overrideColor: coin.isStable ? Color.gray.opacity(0.5) : nil,
                            height: 30,
                            lineWidth: coin.isStable ? SparklineConsistency.listStableLineWidth : SparklineConsistency.listLineWidth,
                            verticalPaddingRatio: SparklineConsistency.listVerticalPaddingRatio,
                            fillOpacity: coin.isStable ? SparklineConsistency.listStableFillOpacity : SparklineConsistency.listFillOpacity,
                            gradientStroke: true,
                            showEndDot: true,
                            leadingFade: 0.0,
                            trailingFade: 0.0,
                            showTrailHighlight: false,
                            trailLengthRatio: 0.0,
                            minWidth: 56,
                            endDotPulse: false,
                            showMinMaxTicks: false,
                            preferredWidth: 56,
                            showBaseline: false,
                            backgroundStyle: .none,
                            cornerRadius: 0,
                            glowOpacity: coin.isStable ? 0.0 : SparklineConsistency.listGlowOpacity,
                            glowLineWidth: SparklineConsistency.listGlowLineWidth,
                            smoothSamplesPerSegment: SparklineConsistency.listSmoothSamplesPerSegment,
                            maxPlottedPoints: SparklineConsistency.listMaxPlottedPoints,
                            rawMode: false,
                            showBackground: false,
                            gridEnabled: false,
                            showExtremaDots: false,
                            neonTrail: false,
                            crispEnds: true,
                            horizontalInset: SparklineConsistency.listHorizontalInset,
                            compact: false,
                            seriesOrder: .oldestToNewest
                        )
                        .allowsHitTesting(false)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 60, height: 30)
                .clipped()
                
                // Price and change (consistent with market page via bestPrice)
                VStack(alignment: .trailing, spacing: 2) {
                    if let price = MarketViewModel.shared.bestPrice(for: coin.id) ?? coin.priceUsd {
                        Text(MarketFormat.price(price))
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    
                    if let change = coin.priceChangePercentage24hInCurrency {
                        Text(String(format: "%@%.2f%%", change >= 0 ? "+" : "", change))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundColor(change >= 0 ? .green : .red)
                            .lineLimit(1)
                    }
                }
                .frame(width: 90, alignment: .trailing)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? BrandColors.goldBase.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? BrandColors.goldBase.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Section Header
    
    private func sectionHeader(title: String, icon: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BrandColors.goldBase)
            
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            if let count = count {
                Text("(\(count))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Prediction Direction Badge

/// Clean, minimal direction badge
struct PredictionDirectionBadge: View {
    let direction: PredictionDirection
    var compact: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    private var icon: String {
        switch direction {
        case .bullish: return "arrow.up.right"
        case .bearish: return "arrow.down.right"
        case .neutral: return "arrow.right"
        }
    }
    
    private var tintColor: Color {
        switch direction {
        case .bullish: return isDark ? Color.green : Color(red: 0.13, green: 0.55, blue: 0.13)
        case .bearish: return Color.red
        case .neutral: return isDark ? Color.yellow : Color(red: 0.72, green: 0.55, blue: 0.10) // Warm amber in light
        }
    }
    
    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            Image(systemName: icon)
                .font(.system(size: compact ? 8 : 9, weight: .bold))
            Text(direction.displayName)
                .font(.system(size: compact ? 9 : 10, weight: .bold))
        }
        .foregroundColor(tintColor)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 4 : 5)
        .background(
            Capsule()
                .fill(tintColor.opacity(isDark ? 0.18 : 0.14))
        )
        .overlay(
            Capsule()
                .stroke(tintColor.opacity(isDark ? 0.35 : 0.30), lineWidth: 0.5)
        )
    }
}

// MARK: - Expiration Countdown Badge

/// Compact badge showing time until prediction expires
struct ExpirationCountdownBadge: View {
    let timeRemaining: TimeInterval
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    /// Whether countdown is urgent (< 1 hour remaining)
    private var isUrgent: Bool { timeRemaining > 0 && timeRemaining < 3600 }
    
    /// Whether prediction has expired
    private var isExpired: Bool { timeRemaining <= 0 }
    
    /// Badge color based on urgency
    private var badgeColor: Color {
        if isExpired { return .red }
        if isUrgent { return .orange }
        return DS.Adaptive.textTertiary
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isExpired ? "clock.badge.xmark" : "clock")
                .font(.system(size: 8, weight: .semibold))
            Text(formattedCountdown)
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
        }
        .foregroundColor(badgeColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(badgeColor.opacity(isDark ? 0.12 : 0.08))
        )
    }
    
    private var formattedCountdown: String {
        if isExpired { return "Expired" }
        
        let days = Int(timeRemaining) / 86400
        let hours = (Int(timeRemaining) % 86400) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Price Drift Warning Badge

/// Shows when live price has moved significantly since prediction was generated
/// Informs users that the target has been auto-adjusted to reflect the same % change from current price
/// User can dismiss this warning or refresh to get a new prediction
struct PriceDriftWarningBadge: View {
    let driftPercent: Double
    let onRefresh: () -> Void
    let onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    /// Use info icon for moderate drift (target adjusted), warning icon for large drift (consider refresh)
    private var isLargeDrift: Bool { driftPercent > 5.0 }
    private var accentColor: Color { isLargeDrift ? .orange : .blue }
    
    init(driftPercent: Double, onRefresh: @escaping () -> Void, onDismiss: (() -> Void)? = nil) {
        self.driftPercent = driftPercent
        self.onRefresh = onRefresh
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isLargeDrift ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(accentColor)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Price moved \(String(format: "%.1f", driftPercent))% since prediction")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Text("Target stays locked until refresh")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            Button(action: onRefresh) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Refresh")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(accentColor)
            }
            .buttonStyle(.plain)
            
            // Dismiss button - allows user to hide this warning
            if let dismiss = onDismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss warning")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accentColor.opacity(isDark ? 0.10 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accentColor.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Prediction Tracking Banner

/// Shows a positive status when the live prediction is on track or has hit the target range.
/// Displayed on the active prediction card between the header and chart.
struct PredictionTrackingBanner: View {
    let status: TrackingStatus
    let directionLabel: String  // e.g. "Bullish"
    let movePercent: Double     // how far price moved in predicted direction
    
    /// Action to generate a new prediction (nil = no button shown)
    var onNewPrediction: (() -> Void)?
    /// Action to show upgrade prompt (nil = no upgrade button)
    var onUpgrade: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    enum TrackingStatus {
        /// Price is within the predicted range AND direction is correct
        case targetHit
        /// Direction is correct but price hasn't reached the predicted range yet
        case onTrack
    }
    
    private var icon: String {
        switch status {
        case .targetHit: return "target"
        case .onTrack:   return "checkmark.circle.fill"
        }
    }
    
    private var title: String {
        switch status {
        case .targetHit: return "Target Reached!"
        case .onTrack:   return "Prediction On Track"
        }
    }
    
    private var subtitle: String {
        let formatted = String(format: "%.1f", abs(movePercent))
        switch status {
        case .targetHit:
            if directionLabel.lowercased() == "neutral" {
                return "Price stayed within the predicted range (\(formatted)% move)"
            }
            return "Price reached the predicted \(directionLabel.lowercased()) target (\(formatted)%)"
        case .onTrack:
            return "\(directionLabel) call confirmed · moved \(formatted)% in predicted direction"
        }
    }
    
    private var accentColor: Color {
        switch status {
        case .targetHit: return Color(red: 0.0, green: 0.85, blue: 0.45)  // Bright green
        case .onTrack:   return Color(red: 0.2, green: 0.78, blue: 0.35)  // Softer green
        }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(accentColor)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accentColor)
                    
                    Text(subtitle)
                        .font(.system(size: 8, weight: .regular))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                // Show action button when target is hit
                if status == .targetHit {
                    if let onNew = onNewPrediction {
                        // Paid tier: can generate a new prediction
                        Button(action: onNew) {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("New Prediction")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(isDark ? .black : .white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(accentColor)
                            )
                        }
                        .buttonStyle(.plain)
                    } else if let onUpg = onUpgrade {
                        // Free tier: show upgrade prompt
                        Button(action: onUpg) {
                            HStack(spacing: 3) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("Upgrade")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .buttonStyle(
                            PremiumCompactCTAStyle(
                                height: 24,
                                horizontalPadding: 8,
                                cornerRadius: 12,
                                font: .system(size: 10, weight: .semibold)
                            )
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accentColor.opacity(isDark ? 0.10 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accentColor.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Prediction Outcome Banner (for expired predictions)

/// Shows whether an expired prediction was correct, partially correct, or wrong.
struct PredictionOutcomeBanner: View {
    let directionCorrect: Bool
    let withinRange: Bool
    let predictedDirection: PredictionDirection
    let actualChangePercent: Double
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    private var outcome: Outcome {
        if directionCorrect && withinRange {
            return .correct
        } else if directionCorrect {
            return .partiallyCorrect
        } else {
            return .incorrect
        }
    }
    
    private enum Outcome {
        case correct, partiallyCorrect, incorrect
    }
    
    private var icon: String {
        switch outcome {
        case .correct:          return "checkmark.seal.fill"
        case .partiallyCorrect: return "checkmark.circle"
        case .incorrect:        return "xmark.circle"
        }
    }
    
    private var title: String {
        switch outcome {
        case .correct:          return "Prediction Correct!"
        case .partiallyCorrect: return "Direction Was Right"
        case .incorrect:        return "Prediction Missed"
        }
    }
    
    private var subtitle: String {
        let formatted = String(format: "%.1f", abs(actualChangePercent))
        switch outcome {
        case .correct:
            return "Price moved \(formatted)% — direction and target range were both correct"
        case .partiallyCorrect:
            return "\(predictedDirection.displayName) call was right (\(formatted)% move) but price missed the target range"
        case .incorrect:
            return "Price moved \(formatted)% against the \(predictedDirection.displayName.lowercased()) prediction"
        }
    }
    
    private var accentColor: Color {
        switch outcome {
        case .correct:          return Color(red: 0.0, green: 0.85, blue: 0.45)
        case .partiallyCorrect: return .yellow
        case .incorrect:        return .red.opacity(0.8)
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accentColor)
                
                Text(subtitle)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accentColor.opacity(isDark ? 0.12 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accentColor.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Prediction Metrics Bar

/// Premium metrics bar with icons and glass morphism
struct PredictionMetricsBar: View {
    let prediction: AIPricePrediction
    let livePrice: Double?  // Reserved for future metrics that compare live vs locked target
    let onDetailsTap: () -> Void
    let onRefreshTap: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    /// Fixed target for this prediction instance.
    private var targetPrice: Double {
        prediction.predictedPrice
    }
    
    /// Remaining move from current live price to locked target.
    /// Falls back to model forecast percent when live price is unavailable.
    private var targetMoveBadge: String {
        guard let live = livePrice, live.isFinite, live > 0 else {
            return prediction.formattedPriceChange
        }
        let pct = ((targetPrice - live) / live) * 100
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", pct))%"
    }
    
    init(prediction: AIPricePrediction, livePrice: Double? = nil, onDetailsTap: @escaping () -> Void, onRefreshTap: (() -> Void)? = nil) {
        self.prediction = prediction
        self.livePrice = livePrice
        self.onDetailsTap = onDetailsTap
        self.onRefreshTap = onRefreshTap
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Staleness indicator banner (when prediction is getting old)
            if prediction.needsRefresh, let refreshAction = onRefreshTap {
                stalenessRefreshBanner(action: refreshAction)
            }
            
            // Clean metrics row - no heavy backgrounds
            HStack(spacing: 0) {
                // Target Price - fixed for this prediction instance.
                metricCell(
                    label: "TARGET",
                    value: MarketFormat.priceCompact(targetPrice),
                    badge: targetMoveBadge,
                    badgeColor: prediction.direction.color
                )
                
                metricDivider
                
                // Expires
                metricCell(
                    label: "EXPIRES",
                    value: prediction.shortTargetDate,
                    badge: formatCountdown(prediction.timeRemaining),
                    badgeColor: prediction.timeRemaining < 86400 ? .orange : DS.Adaptive.textTertiary
                )
                
                metricDivider
                
                // Confidence - simplified
                VStack(spacing: 3) {
                    Text("CONFIDENCE")
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.3)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    HStack(spacing: 3) {
                        Circle()
                            .fill(prediction.confidence.color)
                            .frame(width: 6, height: 6)
                        Text("\(prediction.confidenceScore)%")
                            .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    // Show data sources count instead of just confidence name
                    HStack(spacing: 2) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text("\(prediction.drivers.count) signals")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Details button - premium glass style
                Button(action: onDetailsTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Details")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: isDark ? [BrandColors.goldLight, BrandColors.goldBase] : [BrandColors.silverBase, BrandColors.silverDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        ZStack {
                            Capsule()
                                .fill(
                                    RadialGradient(
                                        colors: isDark
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
                                        colors: [Color.white.opacity(isDark ? 0.12 : 0.5), Color.white.opacity(0)],
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
                                    colors: isDark
                                        ? [BrandColors.goldLight.opacity(0.5), BrandColors.goldBase.opacity(0.2), BrandColors.goldDark.opacity(0.1)]
                                        : [BrandColors.silverLight.opacity(0.6), BrandColors.silverBase.opacity(0.3), BrandColors.silverDark.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isDark 
                            ? Color.white.opacity(0.04)
                            : Color.black.opacity(0.03)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isDark
                            ? Color.white.opacity(0.06)
                            : Color.black.opacity(0.04),
                        lineWidth: 0.5
                    )
            )
        }
    }
    
    /// Enhanced staleness warning banner with context
    /// Handles all timeframes (1H, 4H, 24H, 7D, 30D) with appropriate messaging.
    /// Shows "Upgrade" CTA for free users who have exhausted their daily predictions.
    private func stalenessRefreshBanner(action: @escaping () -> Void) -> some View {
        let progressPercent = min(99, Int(prediction.timeframeProgress * 100)) // Cap at 99% to avoid showing 100%+ before expired
        let timeElapsed = prediction.generatedAgoText
        _ = prediction.timeRemaining
        let canRefresh = AIPricePredictionService.shared.canGeneratePrediction
        
        let subtitleText = canRefresh
            ? "Generated \(timeElapsed) • Tap to refresh with latest data"
            : "Daily limit reached • Upgrade to refresh predictions"
        
        let accentColor: Color = canRefresh ? .orange : BrandColors.goldBase
        
        return Button(action: action) {
            HStack(spacing: 10) {
                // Animated warning icon
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: canRefresh ? "exclamationmark.triangle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Market has moved")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        // Progress indicator - shows how much of the prediction timeframe has elapsed
                        Text("\(progressPercent)% elapsed")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(progressPercent >= 90 ? Color.red : Color.orange)
                            )
                    }
                    
                    Text(subtitleText)
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                // Refresh or upgrade icon
                Image(systemName: canRefresh ? "arrow.clockwise" : "crown.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(isDark ? 0.15 : 0.10), accentColor.opacity(isDark ? 0.08 : 0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func metricCell(label: String, value: String, badge: String, badgeColor: Color) -> some View {
        VStack(spacing: 3) {
            // Label - small caps style
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .tracking(0.3)
                .foregroundColor(DS.Adaptive.textTertiary)
            
            // Value
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(DS.Adaptive.textPrimary)
                .lineLimit(1)
            
            // Badge
            Text(badge)
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundColor(badgeColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var metricDivider: some View {
        Rectangle()
            // LIGHT MODE FIX: Adaptive divider
            .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
            .frame(width: 1, height: 32)
    }
    
    /// Format countdown for display - handles all timeframes from 1H to 30D
    private func formatCountdown(_ remaining: TimeInterval) -> String {
        if remaining <= 0 { return "Expired" }
        
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        
        if days > 0 {
            // 7D and 30D timeframes
            return "in \(days)d \(hours)h"
        } else if hours > 0 {
            // 4H and 24H timeframes
            return "in \(hours)h \(minutes)m"
        } else if minutes > 0 {
            // 1H timeframe or final minutes
            return "in \(minutes)m"
        } else {
            // Final seconds - show urgency
            return "in \(seconds)s"
        }
    }
}

// MARK: - AI Prediction Sheet (Full-Screen Modal)

/// Sheet-based AI Prediction interface - triggered from Watchlist CTA button
struct AIPredictionSheet: View {
    @StateObject private var predictionService = AIPricePredictionService.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    // FIX v23: Same as AIPredictionSectionView - removed @EnvironmentObject to break observation cascade
    private var marketVM: MarketViewModel { MarketViewModel.shared }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Initial coin passed from caller
    var defaultCoin: MarketCoin?
    
    @State private var selectedCoin: MarketCoin?
    @State private var selectedTimeframe: PredictionTimeframe = .day
    @State private var currentPrediction: AIPricePrediction?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showCoinPicker: Bool = false
    @State private var showDetailView: Bool = false
    @State private var showUpgradePrompt: Bool = false
    @State private var predictionTask: Task<Void, Never>?
    
    // Premium loading animation state
    @State private var loadingOrbitAngle: Double = 0
    @State private var loadingPulse: Bool = false
    @State private var loadingPhase: Int = 0
    @State private var loadingRingScale: CGFloat = 0.8
    @State private var loadingPhaseTimer: Timer?
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var hasPremiumAccess: Bool {
        subscriptionManager.hasAccess(to: .aiPricePredictions)
    }
    
    private var loadingPhaseTexts: [(title: String, icon: String)] {
        [
            ("Scanning market signals", "antenna.radiowaves.left.and.right"),
            ("Analyzing price action", "chart.xyaxis.line"),
            ("Evaluating momentum", "gauge.with.dots.needle.33percent"),
            ("Generating forecast", "sparkles")
        ]
    }
    
    private func startLoadingAnimations() {
        loadingPhase = 0
        loadingOrbitAngle = 0
        loadingPulse = false
        loadingRingScale = 0.8
        
        loadingPhaseTimer?.invalidate()
        loadingPhaseTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                loadingPhase = (loadingPhase + 1) % loadingPhaseTexts.count
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                loadingOrbitAngle = 360
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                loadingPulse = true
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                loadingRingScale = 1.1
            }
        }
    }
    
    private func stopLoadingAnimations() {
        loadingPhaseTimer?.invalidate()
        loadingPhaseTimer = nil
        loadingOrbitAngle = 0
        loadingPulse = false
        loadingRingScale = 0.8
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Adaptive.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Coin & Timeframe Selection Card
                        selectionCard
                        
                        // Prediction Result / Loading / Error
                        if isLoading && currentPrediction == nil {
                            loadingCard
                        } else if let prediction = currentPrediction {
                            predictionResultCard(prediction)
                                .overlay {
                                    // Show subtle loading indicator when refreshing
                                    if isLoading {
                                        VStack {
                                            HStack(spacing: 8) {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                    .tint(BrandColors.goldBase)
                                                Text("Refreshing prediction...")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(DS.Adaptive.textSecondary)
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(
                                                Capsule()
                                                    .fill(DS.Adaptive.cardBackground.opacity(0.95))
                                            )
                                            .overlay(
                                                Capsule()
                                                    .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
                                            )
                                            Spacer()
                                        }
                                        .padding(.top, 8)
                                    }
                                }
                        } else if let error = errorMessage {
                            errorCard(error)
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("AI Price Prediction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(BrandColors.goldBase)
                }
            }
        }
        .onAppear {
            initializeDefaultCoin()
        }
        .onDisappear {
            predictionTask?.cancel()
            predictionTask = nil
        }
        .sheet(isPresented: $showCoinPicker) {
            CoinPickerSheet(selectedCoin: $selectedCoin, coins: Array(marketVM.allCoins.prefix(500)))
        }
        .sheet(isPresented: $showDetailView) {
            if let prediction = currentPrediction {
                AIPredictionDetailView(
                    prediction: prediction,
                    coinIconUrl: selectedCoin?.iconUrl,
                    onDismiss: { showDetailView = false }
                )
            }
        }
        .unifiedPaywallSheet(feature: .aiPricePredictions, isPresented: $showUpgradePrompt)
    }
    
    // MARK: - Selection Card
    
    private var selectionCard: some View {
        PremiumGlassCard(showGoldAccent: true, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 16) {
                // Coin Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Coin")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showCoinPicker = true
                    } label: {
                        HStack(spacing: 10) {
                            if let coin = selectedCoin {
                                CoinImageView(symbol: coin.symbol, url: coin.iconUrl, size: 32)
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                                    // SCROLL FIX: Ensure coin icon is properly clipped during scroll
                                    .clipped()
                            } else {
                                Image(systemName: "bitcoinsign.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.orange)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedCoin?.symbol.uppercased() ?? "BTC")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                
                                if let name = selectedCoin?.name {
                                    Text(name)
                                        .font(.system(size: 12))
                                        .foregroundColor(DS.Adaptive.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // Timeframe Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prediction Timeframe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    // Grid of timeframe options
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(PredictionTimeframe.allCases, id: \.self) { timeframe in
                            timeframeButton(timeframe)
                        }
                    }
                }
                
                // Predict Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if !predictionService.canGeneratePrediction && !hasPremiumAccess {
                        showUpgradePrompt = true
                        return
                    }
                    generatePrediction()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Generate Prediction")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(isDark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(selectedCoin == nil || isLoading)
                .opacity(selectedCoin == nil || isLoading ? 0.6 : 1)
            }
            .padding(16)
        }
    }
    
    private func timeframeButton(_ timeframe: PredictionTimeframe) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedTimeframe = timeframe
        } label: {
            VStack(spacing: 4) {
                Text(timeframe.displayName)
                    .font(.system(size: 14, weight: selectedTimeframe == timeframe ? .bold : .medium))
                Text(timeframe.shortDescription)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            .foregroundColor(selectedTimeframe == timeframe ? BrandColors.goldBase : DS.Adaptive.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedTimeframe == timeframe
                          ? BrandColors.goldBase.opacity(0.15)
                          : (isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selectedTimeframe == timeframe
                            ? BrandColors.goldBase.opacity(0.5)
                            : DS.Adaptive.stroke.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Loading Card (Full — Detail View)
    
    private var loadingCard: some View {
        PremiumGlassCard(showGoldAccent: true, cornerRadius: 14) {
            VStack(spacing: 20) {
                // Premium animated icon with concentric rings + orbiting particles
                ZStack {
                    // Outermost pulsing ring
                    Circle()
                        .stroke(BrandColors.goldBase.opacity(0.08), lineWidth: 1)
                        .frame(width: 100, height: 100)
                        .scaleEffect(loadingPulse ? 1.15 : 0.9)
                        .opacity(loadingPulse ? 0.0 : 0.5)
                    
                    // Second pulsing ring
                    Circle()
                        .stroke(BrandColors.goldBase.opacity(0.12), lineWidth: 1)
                        .frame(width: 82, height: 82)
                        .scaleEffect(loadingPulse ? 1.1 : 0.95)
                        .opacity(loadingPulse ? 0.2 : 0.6)
                    
                    // Main orbiting gradient ring
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    BrandColors.goldLight.opacity(0.0),
                                    BrandColors.goldBase.opacity(0.5),
                                    BrandColors.goldLight.opacity(0.9),
                                    BrandColors.goldBase.opacity(0.5),
                                    BrandColors.goldLight.opacity(0.0)
                                ],
                                center: .center
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: 66, height: 66)
                        .rotationEffect(.degrees(loadingOrbitAngle))
                    
                    // Inner glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [BrandColors.goldBase.opacity(loadingPulse ? 0.2 : 0.06), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 36
                            )
                        )
                        .frame(width: 60, height: 60)
                    
                    // Coin icon
                    if let coin = selectedCoin {
                        CoinImageView(symbol: coin.symbol, url: coin.iconUrl, size: 48)
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            .scaleEffect(loadingPulse ? 1.05 : 0.95)
                    }
                    
                    // Orbiting particles (3 at different radii & speeds)
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(BrandColors.goldLight)
                            .frame(width: CGFloat(5 - i), height: CGFloat(5 - i))
                            .offset(y: CGFloat(-33 - i * 10))
                            .rotationEffect(.degrees(loadingOrbitAngle * (i == 1 ? 0.7 : i == 2 ? 1.4 : 1.0) + Double(i * 120)))
                    }
                }
                .frame(width: 100, height: 100)
                
                // Title + phase text
                VStack(spacing: 6) {
                    Text("Analyzing \(selectedCoin?.symbol.uppercased() ?? "coin")")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // Current phase with icon
                    HStack(spacing: 5) {
                        Image(systemName: loadingPhaseTexts[loadingPhase].icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(BrandColors.goldBase)
                        
                        Text(loadingPhaseTexts[loadingPhase].title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    .animation(.easeInOut(duration: 0.3), value: loadingPhase)
                }
                
                // Step progress bar
                VStack(spacing: 8) {
                    // Progress dots with connecting lines
                    HStack(spacing: 0) {
                        ForEach(0..<loadingPhaseTexts.count, id: \.self) { idx in
                            // Dot
                            ZStack {
                                Circle()
                                    .fill(idx <= loadingPhase ? BrandColors.goldBase : DS.Adaptive.divider.opacity(0.3))
                                    .frame(width: idx == loadingPhase ? 10 : 7, height: idx == loadingPhase ? 10 : 7)
                                
                                if idx == loadingPhase {
                                    Circle()
                                        .stroke(BrandColors.goldLight.opacity(0.5), lineWidth: 2)
                                        .frame(width: 16, height: 16)
                                        .scaleEffect(loadingPulse ? 1.3 : 0.8)
                                        .opacity(loadingPulse ? 0.0 : 0.8)
                                }
                            }
                            .frame(width: 16, height: 16)
                            .animation(.easeInOut(duration: 0.3), value: loadingPhase)
                            
                            // Connecting line (not after last dot)
                            if idx < loadingPhaseTexts.count - 1 {
                                Rectangle()
                                    .fill(idx < loadingPhase ? BrandColors.goldBase.opacity(0.5) : DS.Adaptive.divider.opacity(0.2))
                                    .frame(height: 1.5)
                                    .animation(.easeInOut(duration: 0.3), value: loadingPhase)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Step labels
                    HStack {
                        ForEach(0..<loadingPhaseTexts.count, id: \.self) { idx in
                            Text(["Scan", "Analyze", "Evaluate", "Forecast"][idx])
                                .font(.system(size: 8, weight: idx <= loadingPhase ? .semibold : .regular, design: .rounded))
                                .foregroundColor(idx <= loadingPhase ? BrandColors.goldBase.opacity(0.9) : DS.Adaptive.textTertiary.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .animation(.easeInOut(duration: 0.3), value: loadingPhase)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                
                // Timeframe label + Cancel
                HStack {
                    Text("\(selectedTimeframe.fullName) forecast")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Spacer()
                    
                    Button {
                        predictionTask?.cancel()
                        predictionTask = nil
                        isLoading = false
                        stopLoadingAnimations()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .stroke(DS.Adaptive.divider.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .onAppear { startLoadingAnimations() }
        .onDisappear { stopLoadingAnimations() }
    }
    
    // MARK: - Error Card
    
    private func errorCard(_ message: String) -> some View {
        PremiumGlassCard(showGoldAccent: false, cornerRadius: 14) {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
                
                Text("Prediction Failed")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                
                Button {
                    errorMessage = nil
                } label: {
                    Text("Try Again")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BrandColors.goldBase)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Prediction Result Card
    
    private func predictionResultCard(_ prediction: AIPricePrediction) -> some View {
        // PRICE CONSISTENCY FIX: Use live price as base (same as predictionResultView and detail page)
        let freshSparkline = (marketVM.allCoins.first(where: { $0.symbol.uppercased() == prediction.coinSymbol.uppercased() })?.sparklineIn7d ?? []).filter { $0.isFinite && $0 > 0 }
        let freshLivePrice = marketVM.bestPrice(forSymbol: prediction.coinSymbol)
        let currentDisplayPrice = freshLivePrice ?? prediction.currentPrice
        let adjustedTarget = prediction.predictedPrice
        
        let priceChange = adjustedTarget - currentDisplayPrice
        let priceChangePercent = currentDisplayPrice > 0 ? (priceChange / currentDisplayPrice) * 100 : 0
        let isPositive = priceChange >= 0
        let accentColor = isPositive ? Color.green : Color.red
        
        return PremiumGlassCard(showGoldAccent: true, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with coin info
                HStack(spacing: 10) {
                    if let coin = selectedCoin {
                        CoinImageView(symbol: coin.symbol, url: coin.iconUrl, size: 40)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(prediction.coinSymbol) \(selectedTimeframe.displayName) Prediction")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Generated \(prediction.generatedAt.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    
                    Spacer()
                    
                    // Direction badge
                    HStack(spacing: 4) {
                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(isPositive ? "Bullish" : "Bearish")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.15))
                    .clipShape(Capsule())
                }
                
                Divider()
                    .background(DS.Adaptive.divider)
                
                // Prediction Chart - shows historical data + projected path
                // Require at least 10 points for a smooth chart
                if freshSparkline.count >= 10 {
                    MiniPredictionChart(
                        currentPrice: currentDisplayPrice,
                        predictedPrice: adjustedTarget,
                        direction: prediction.direction,
                        sparklineData: freshSparkline,
                        livePrice: freshLivePrice,
                        timeframe: prediction.timeframe,
                        generatedAt: prediction.generatedAt
                    )
                    .frame(height: 120)
                    .clipped()
                    .padding(.vertical, 4)
                }
                
                // Price prediction - uses live-adjusted prices for consistency
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Price")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Text(formatCurrency(currentDisplayPrice))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Predicted Price")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Text(formatCurrency(adjustedTarget))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(accentColor)
                    }
                }
                
                // Change summary
                HStack {
                    Text("Expected Change:")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Spacer()
                    
                    Text("\(isPositive ? "+" : "")\(formatCurrency(priceChange)) (\(String(format: "%+.2f%%", priceChangePercent)))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)
                }
                .padding(10)
                .background(accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                
                // Confidence
                HStack(spacing: 8) {
                    Text("Confidence:")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    let confidenceScore = Int(prediction.confidence.score * 100)
                    MiniConfidenceBar(score: confidenceScore, color: confidenceColor(confidenceScore))
                        .frame(width: 60, height: 6)
                    
                    Text("\(confidenceScore)%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(confidenceColor(confidenceScore))
                }
                
                // View Details Button
                Button {
                    showDetailView = true
                } label: {
                    HStack {
                        Text("View Full Analysis")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(BrandColors.goldBase)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(BrandColors.goldBase.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                
                // New prediction button
                Button {
                    withAnimation {
                        currentPrediction = nil
                    }
                } label: {
                    Text("New Prediction")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }
    
    // MARK: - Helpers
    
    private func initializeDefaultCoin() {
        if selectedCoin == nil {
            selectedCoin = defaultCoin ?? marketVM.allCoins.first { $0.symbol.uppercased() == "BTC" }
        }
    }
    
    private func generatePrediction(forceRefresh: Bool = false) {
        guard let coin = selectedCoin else { return }
        
        predictionTask?.cancel()
        
        // Don't clear current prediction - preserve it until we have a new one
        // This prevents losing the prediction if the refresh fails
        if forceRefresh {
            print("[FullscreenPrediction] Force refresh requested - preserving current prediction until success")
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isLoading = true
        }
        errorMessage = nil
        
        predictionTask = Task { @MainActor in
            defer {
                // Always reset loading state when task completes (including cancellation)
                if Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isLoading = false
                    }
                }
            }
            
            do {
                try Task.checkCancellation()
                
                let prediction = try await predictionService.generatePrediction(
                    for: coin.symbol,
                    coinName: coin.name,
                    timeframe: selectedTimeframe,
                    forceRefresh: forceRefresh
                )
                
                try Task.checkCancellation()
                
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPrediction = prediction
                    isLoading = false
                }
            } catch is CancellationError {
                // Cancelled - defer will reset isLoading
                print("[FullscreenPrediction] Prediction task cancelled")
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isLoading = false
                    }
                }
            }
        }
    }
    
    // PERFORMANCE FIX: Cached currency formatters
    private static let _currFmt2: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode
        nf.minimumFractionDigits = 2; nf.maximumFractionDigits = 2; return nf
    }()
    private static let _currFmt6: NumberFormatter = {
        let nf = NumberFormatter(); nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode
        nf.minimumFractionDigits = 4; nf.maximumFractionDigits = 6; return nf
    }()
    private func formatCurrency(_ value: Double) -> String {
        let formatter = value < 1 ? Self._currFmt6 : Self._currFmt2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    private func formatPriceCompact(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.1fK", value / 1_000)
        } else if value >= 1 {
            return String(format: "$%.2f", value)
        } else {
            return String(format: "$%.4f", value)
        }
    }
    
    private func confidenceColor(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }
}

// MARK: - Timeframe Extension for Sheet

private extension PredictionTimeframe {
    var shortDescription: String {
        switch self {
        case .hour: return "Next hour"
        case .fourHours: return "4 hours"
        case .twelveHours: return "12 hours"
        case .day: return "24 hours"
        case .week: return "7 days"
        case .month: return "30 days"
        }
    }
}

// MARK: - Prediction Timeframe Picker (Premium Anchored Popover)

/// A premium anchored timeframe picker for AI predictions.
/// Features solid glass background, gold accents, and recommended badge for 24H.
struct PredictionTimeframePicker: View {
    @Binding var isPresented: Bool
    @Binding var selection: PredictionTimeframe
    let buttonFrame: CGRect
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmerOffset: CGFloat = -1
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        GeometryReader { geo in
            let safeArea = geo.safeAreaInsets
            
            // Calculate position - center horizontally, position above button with safe margins
            let xPos = min(max(pickerWidth / 2 + 16, buttonFrame.midX), geo.size.width - pickerWidth / 2 - 16)
            // Position above the button, but ensure we don't go above safe area
            let yAboveButton = buttonFrame.minY - pickerHeight / 2 - 16
            let minY = pickerHeight / 2 + safeArea.top + 20
            let yPos = max(yAboveButton, minY)
            
            ZStack {
                // Dismiss background with stronger dim for better visibility
                Color.black.opacity(isDark ? 0.55 : 0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            isPresented = false
                        }
                    }
                
                // Picker content positioned above the button
                pickerContent
                    .position(x: xPos, y: yPos)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
        .onAppear {
            // Animate shimmer on appear
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                shimmerOffset = 1
            }
        }
    }
    
    private var pickerWidth: CGFloat { 280 }  // Wider for full title
    private var pickerHeight: CGFloat { 320 }  // Slightly taller for breathing room
    
    private var pickerContent: some View {
        VStack(spacing: 8) {
            // Premium Header with shimmer
            ZStack {
                // Shimmer effect
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                BrandColors.goldBase.opacity(0.15),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: shimmerOffset * pickerWidth)
                    .mask(
                        Rectangle()
                            .frame(height: 50)
                    )
                
                HStack(spacing: 8) {
                    // Gold clock icon with glow
                    ZStack {
                        Circle()
                            .fill(BrandColors.goldBase.opacity(0.2))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "clock.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [BrandColors.goldLight, BrandColors.goldBase],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    
                    Text("Select Timeframe")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                        .fixedSize(horizontal: true, vertical: false)  // Prevent truncation
                    
                    Spacer(minLength: 8)
                    
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            isPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                            .frame(width: 26, height: 26)
                            .background(
                                Circle()
                                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            
            // Divider with gold accent
            HStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, BrandColors.goldBase.opacity(0.4), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }
            .padding(.horizontal, 12)
            
            // Timeframe options with larger touch targets
            VStack(spacing: 6) {
                ForEach(PredictionTimeframe.allCases, id: \.self) { timeframe in
                    timeframeRow(timeframe)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
        .frame(width: pickerWidth)
        .background(
            ZStack {
                // Use material blur for real device compatibility - much more opaque
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThickMaterial)
                
                // Dark overlay to ensure readability on real devices
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(isDark ? 0.6 : 0.1))
                
                // Gold accent glow at top
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [BrandColors.goldBase.opacity(0.1), Color.clear],
                            center: .top,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            BrandColors.goldBase.opacity(0.6),
                            BrandColors.goldBase.opacity(0.3),
                            Color.white.opacity(isDark ? 0.15 : 0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }
    
    private func timeframeRow(_ timeframe: PredictionTimeframe) -> some View {
        let isSelected = timeframe == selection
        let isRecommended = timeframe == .day // 24H is most relevant for crypto
        
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                selection = timeframe
            }
            // Delay before dismissing for visual feedback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    isPresented = false
                }
            }
        } label: {
            HStack(spacing: 12) {
                // Icon with background
                ZStack {
                    Circle()
                        .fill(isSelected 
                              ? BrandColors.goldBase.opacity(0.2) 
                              : (isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: timeframeIcon(for: timeframe))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelected ? BrandColors.goldBase : DS.Adaptive.textSecondary)
                }
                
                // Label and description
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(timeframe.displayName)
                            .font(.system(size: 15, weight: isSelected ? .bold : .semibold))
                            .foregroundColor(isSelected ? DS.Adaptive.textPrimary : DS.Adaptive.textSecondary)
                        
                        // Recommended badge for 24H
                        if isRecommended {
                            Text("REC")
                                .font(.system(size: 8, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.green, Color.green.opacity(0.7)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                        }
                    }
                    
                    Text(timeframe.fullName)
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? BrandColors.goldBase : DS.Adaptive.textTertiary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    
                    if isSelected {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [BrandColors.goldLight, BrandColors.goldBase],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected 
                          ? BrandColors.goldBase.opacity(isDark ? 0.12 : 0.08)
                          : (isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected 
                            ? BrandColors.goldBase.opacity(0.4) 
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func timeframeIcon(for timeframe: PredictionTimeframe) -> String {
        switch timeframe {
        case .hour: return "clock"
        case .fourHours: return "clock.badge.checkmark"
        case .twelveHours: return "clock.arrow.circlepath"
        case .day: return "sun.max.fill"
        case .week: return "calendar"
        case .month: return "calendar.badge.clock"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AIPredictionSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.Adaptive.background.ignoresSafeArea()
            
            VStack {
                AIPredictionSectionView()
                    .environmentObject(MarketViewModel.shared)
                
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct AIPredictionSheet_Previews: PreviewProvider {
    static var previews: some View {
        AIPredictionSheet()
            .environmentObject(MarketViewModel.shared)
            .preferredColorScheme(.dark)
    }
}
#endif


