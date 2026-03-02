//
//  AIPredictionDetailView.swift
//  CryptoSage
//
//  Full-screen detail view for AI price predictions with complete analysis,
//  price range visualization, and disclaimer.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AIPredictionDetailView: View {
    @State private var prediction: AIPricePrediction
    @State private var selectedTimeframe: PredictionTimeframe
    @State private var isLoadingNewTimeframe: Bool = false
    
    // FIX: Persist timeframe selection so it syncs with homepage
    @AppStorage("AIPrediction.SelectedTimeframe") private var persistedTimeframeRaw: String = "1d"
    
    let coinSymbol: String
    let coinName: String
    var coinIconUrl: URL?
    var onDismiss: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Access to market data for sparkline/technical calculations
    @ObservedObject private var marketVM = MarketViewModel.shared
    
    // Track prediction accuracy for display metrics updates
    @ObservedObject private var accuracyService = PredictionAccuracyService.shared
    
    @State private var hasAppeared = false
    @State private var liveDisplayPrice: Double?
    
    @State private var sparklineTimedOut = false
    
    // Loading timeout state - show "Data unavailable" after 5 seconds of loading
    @State private var loadingTimedOut = false
    
    // Task tracking for cancellation and safety timeout
    @State private var currentLoadingTask: Task<Void, Never>?
    @State private var loadingSafetyTimer: Timer?
    private let loadingSafetyTimeoutSeconds: TimeInterval = 45
    
    // Key Drivers expand/collapse state
    @State private var showAllDrivers = false
    
    // Methodology section expand/collapse state (collapsed by default)
    @State private var showMethodology = false
    // "Powered by" info sheet showing verifiable AI credentials
    @State private var showAICredentialsSheet = false
    // Upgrade paywall prompt for free users who hit daily limits
    @State private var showUpgradePrompt = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Get sparkline data for the current coin with fallback chain.
    /// 1. CoinGecko sparkline from MarketViewModel (freshest)
    /// 2. Binance/disk-cached sparkline via WatchlistSparklineService
    /// 3. Empty array (chart shows forecast-only after timeout)
    /// Also appends the current live price as the final point so the historical
    /// line connects smoothly to the "NOW" marker without a gap.
    private var sparklineData: [Double] {
        var data: [Double] = []
        let symbolUpper = coinSymbol.uppercased()
        let resolvedCoin = marketVM.allCoins.first(where: { $0.symbol.uppercased() == symbolUpper })
        let resolvedCoinID = resolvedCoin?.id.lowercased()

        // Source 1: CoinGecko sparkline via MarketViewModel (preferred — real-time from Firestore)
        if let coin = resolvedCoin {
            let raw = coin.sparklineIn7d.filter { $0.isFinite && $0 > 0 }
            if raw.count >= 2 { data = raw }
        }

        // Source 2: Disk-cached Binance sparkline (keyed by coin id or symbol)
        if data.isEmpty {
            let diskCache = WatchlistSparklineService.loadCachedSparklinesSync()
            let symbolLower = coinSymbol.lowercased()
            // Exact deterministic lookup only: coin id, symbol, upper symbol.
            let cached = resolvedCoinID.flatMap { diskCache[$0] } ?? diskCache[symbolLower] ?? diskCache[symbolUpper]
            if let cached {
                let clean = cached.filter { $0.isFinite && $0 > 0 }
                if clean.count >= 2 { data = clean }
            }
        }

        // Append live price as tail point to eliminate gap between historical and NOW marker
        if !data.isEmpty, let live = liveDisplayPrice, live.isFinite, live > 0 {
            if let last = data.last, abs(live - last) / max(last, 1) > 0.00001 {
                data.append(live)
            }
        }

        return data
    }
    
    /// Get the best available current price for display
    /// PRICE CONSISTENCY FIX: Prefer live market price so the detail page matches the home page.
    /// Both pages use live price as the base and apply the same % change, producing identical targets.
    /// Falls back to prediction.currentPrice only when live data is unavailable.
    private var displayCurrentPrice: Double {
        if let liveDisplayPrice, liveDisplayPrice.isFinite, liveDisplayPrice > 0 {
            return liveDisplayPrice
        }
        // 1. Try live price from MarketViewModel using bestPrice (checks LivePriceManager/Firebase/Binance)
        // This matches how the home page card calculates its target: freshLivePrice → adjustedPredictedPrice
        if let coin = marketVM.allCoins.first(where: { $0.symbol.uppercased() == coinSymbol.uppercased() }),
           let livePrice = marketVM.bestPrice(for: coin.id), livePrice > 0 {
            return livePrice
        }
        // 2. Symbol-based lookup
        if let livePrice = marketVM.bestPrice(forSymbol: coinSymbol), livePrice > 0 {
            return livePrice
        }
        // 3. Fall back to prediction's stored price (from when prediction was generated)
        if prediction.currentPrice > 0 && prediction.currentPrice.isFinite {
            return prediction.currentPrice
        }
        return prediction.currentPrice // Return original even if 0 as last fallback
    }
    
    /// The price at which this prediction was originally generated
    /// Used for informational display ("Predicted at $X") but NOT for target calculations
    private var predictionBasePrice: Double {
        prediction.currentPrice
    }
    
    /// Keep target price fixed for this prediction instance.
    /// Live price should move, but the prediction target remains stable until refresh.
    private var displayPredictedPrice: Double {
        return prediction.predictedPrice
    }
    
    /// Keep prediction range fixed for this prediction instance.
    private var displayPredictedPriceLow: Double {
        prediction.predictedPriceLow
    }
    
    /// Keep prediction range fixed for this prediction instance.
    private var displayPredictedPriceHigh: Double {
        prediction.predictedPriceHigh
    }
    
    /// Get drivers with fallback - ensures Signal Overview always has data to display
    /// This handles edge cases where cached predictions might have empty drivers
    private var effectiveDrivers: [PredictionDriver] {
        if prediction.drivers.isEmpty {
            // Generate fallback drivers based on prediction direction
            let signalValue = prediction.direction == .bullish ? "bullish" : (prediction.direction == .bearish ? "bearish" : "neutral")
            return [
                PredictionDriver(
                    name: "AI Analysis",
                    value: "\(prediction.direction.displayName) outlook",
                    signal: signalValue,
                    weight: 0.5
                ),
                PredictionDriver(
                    name: "Confidence",
                    value: "\(prediction.confidenceScore)% (\(prediction.confidence.rawValue))",
                    signal: signalValue,
                    weight: 0.4
                ),
                PredictionDriver(
                    name: "Price Target",
                    value: prediction.formattedPriceChange,
                    signal: signalValue,
                    weight: 0.3
                )
            ]
        }
        return prediction.drivers
    }
    
    // Initializer to set up state from passed prediction
    init(prediction: AIPricePrediction, coinIconUrl: URL? = nil, onDismiss: (() -> Void)? = nil) {
        self._prediction = State(initialValue: prediction)
        self._selectedTimeframe = State(initialValue: prediction.timeframe)
        self.coinSymbol = prediction.coinSymbol
        self.coinName = prediction.coinName
        self.coinIconUrl = coinIconUrl
        self.onDismiss = onDismiss
    }
    
    private func closeDetail() {
        // Prefer explicit owner-driven dismissal when available (sheet state binding),
        // then try explicit nav-pop fallback, then environment dismissal.
        if let onDismiss {
            onDismiss()
            return
        }
        if popFromNavigationControllerIfPossible() { return }
        dismiss()
    }

    @discardableResult
    private func popFromNavigationControllerIfPossible() -> Bool {
#if canImport(UIKit)
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController,
              let nav = findNavigationController(from: root),
              nav.viewControllers.count > 1 else {
            return false
        }
        nav.popViewController(animated: true)
        return true
#else
        return false
#endif
    }

    private func findNavigationController(from vc: UIViewController?) -> UINavigationController? {
        guard let vc else { return nil }
        if let nav = vc as? UINavigationController { return nav }
        for child in vc.children {
            if let found = findNavigationController(from: child) { return found }
        }
        if let presented = vc.presentedViewController {
            return findNavigationController(from: presented)
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Pinned header - consistent with other pages (gold chevron back)
            SubpageHeaderBar(
                title: "Price Prediction",
                showDivider: false,
                onDismiss: { closeDetail() }
            )
            
            // Timeframe selector below header
            inlineTimeframePills
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            
            // Scrollable content
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        // === SECTION 1: PREDICTION SUMMARY ===
                        // Header card with gauge
                        headerCard
                        
                        // Full prediction chart with historical data and projected path
                        predictionChartCard
                        
                        // Price range visualization
                        priceRangeCard
                        
                        // AI analysis text - detailed explanation (moved up for better context)
                        analysisCard
                        
                        // === SECTION 2: SIGNAL ANALYSIS ===
                        // Signal summary visualization - visual indicator breakdown
                        signalSummaryCard
                        
                        // Key drivers - what influenced the prediction
                        driversCard
                        
                        // === SECTION 3: TRADING STRATEGY ===
                        // Trading action card (entry/exit suggestions)
                        tradingActionCard
                        
                        // === SECTION 4: PROFESSIONAL INSIGHTS ===
                        // Professional insights (Smart Money, Regime, Confluence)
                        // Gated behind Pro tier — free users see a locked preview with upgrade CTA
                        if SubscriptionManager.shared.hasTier(.pro) {
                            professionalInsightsCard
                        } else {
                            lockedProfessionalInsightsCard
                        }
                        
                        // Probability distribution (CoinStats-style) - if available
                        if prediction.hasProbabilityData {
                            probabilityDistributionCard
                        }
                        
                        // === SECTION 5: ACCURACY & METHODOLOGY ===
                        // Accuracy stats badge
                        PredictionAccuracyCard()
                        
                        // How the AI works explanation
                        aiMethodologySection
                        
                        // Disclaimer
                        disclaimerSection
                    }
                    .id("prediction_\(prediction.id)_\(prediction.timeframe.rawValue)_\(prediction.predictedPrice)_spark\(sparklineData.count)")
                    .opacity(isLoadingNewTimeframe ? 0.5 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isLoadingNewTimeframe)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                    .frame(width: geometry.size.width) // Lock width to prevent horizontal scroll
                }
                .scrollBounceBehavior(.basedOnSize)
                .withUIKitScrollBridge() // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .task {
            // Sparkline diagnostics only: ignore unrelated Firebase startup warnings for this flow.
            print("[AIPredictionChart] start symbol=\(coinSymbol.uppercased()) points=\(sparklineData.count)")
            
            // Backfill accuracy tracking when opening detail from any entry point.
            // Safe to call repeatedly because storePrediction de-duplicates by prediction id.
            PredictionAccuracyService.shared.storePrediction(prediction, modelProvider: "deepseek-chat")

            // Ensure market data is available for Professional Insights section
            // This triggers a refresh if data is stale or missing
            if marketVM.allCoins.isEmpty {
                await marketVM.loadAllData()
            }
            
            // Evaluate any pending predictions (ensures accuracy card shows data)
            let pendingCount = PredictionAccuracyService.shared.storedPredictions.filter { $0.isReadyForEvaluation }.count
            if pendingCount > 0 {
                await PredictionAccuracyService.shared.evaluatePendingPredictions()
            }
            refreshLivePrice()

            // --- Sparkline retry / timeout ---
            // Reset timeout flag on each task run (e.g. timeframe switches).
            sparklineTimedOut = false
            if sparklineData.isEmpty {
                // Retry after 3 seconds: force a market data refresh so CoinGecko
                // sparkline has another chance to arrive.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if sparklineData.isEmpty {
                    print("[AIPredictionChart] retry loadAllData symbol=\(coinSymbol.uppercased())")
                    await marketVM.loadAllData()
                }
                if sparklineData.isEmpty {
                    // Final timeout at ~8 seconds total: show forecast-only chart.
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if sparklineData.isEmpty {
                        sparklineTimedOut = true
                        print("[AIPredictionChart] timeout symbol=\(coinSymbol.uppercased()) points=0")
                    }
                }
            }
            if !sparklineTimedOut {
                print("[AIPredictionChart] ready symbol=\(coinSymbol.uppercased()) points=\(sparklineData.count)")
            }
        }
        .onReceive(LivePriceManager.shared.throttledPublisher) { liveCoins in
            refreshLivePrice(from: liveCoins)
        }
        .onReceive(marketVM.$allCoins) { coins in
            refreshLivePrice(from: coins)
        }
        .unifiedPaywallSheet(feature: .aiPricePredictions, isPresented: $showUpgradePrompt)
    }

    private func refreshLivePrice(from liveCoins: [MarketCoin]? = nil) {
        let symbolUpper = coinSymbol.uppercased()
        var resolvedPrice: Double?

        if let liveCoins,
           let liveCoin = liveCoins.first(where: { $0.symbol.uppercased() == symbolUpper }),
           let live = liveCoin.priceUsd,
           live.isFinite, live > 0 {
            resolvedPrice = live
        }

        if resolvedPrice == nil,
           let best = marketVM.bestPrice(forSymbol: coinSymbol),
           best.isFinite, best > 0 {
            resolvedPrice = best
        }

        guard let next = resolvedPrice else { return }
        let current = liveDisplayPrice ?? 0
        let threshold = max(abs(next) * 0.0000005, 0.0000001)
        guard liveDisplayPrice == nil || abs(current - next) > threshold else { return }
        liveDisplayPrice = next
    }
    
    // MARK: - Inline Timeframe Selector (Underline Style)
    
    private var inlineTimeframePills: some View {
        HStack(spacing: 0) {
            ForEach(PredictionTimeframe.allCases, id: \.rawValue) { tf in
                let isSelected = selectedTimeframe == tf
                
                Button {
                    guard selectedTimeframe != tf, !isLoadingNewTimeframe else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTimeframe = tf
                        // FIX: Persist timeframe so homepage shows the same selection
                        persistedTimeframeRaw = tf.rawValue
                    }
                    Task { await loadPredictionForTimeframe(tf) }
                } label: {
                    VStack(spacing: 6) {
                        Group {
                            if isLoadingNewTimeframe && isSelected {
                                ProgressView()
                                    .scaleEffect(0.4)
                                    .tint(DS.Adaptive.textPrimary)
                            } else {
                                Text(tf.displayName)
                                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                            }
                        }
                        .foregroundColor(isSelected ? DS.Adaptive.textPrimary : DS.Adaptive.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        
                        // Underline indicator
                        Rectangle()
                            .fill(isSelected ? BrandColors.goldBase : Color.clear)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingNewTimeframe)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.clear)
        )
        .overlay(
            // Bottom border line
            Rectangle()
                .fill(DS.Adaptive.stroke.opacity(0.2))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - Detail View Staleness Warning
    
    private var detailStalenessWarning: some View {
        let progressPercent = Int(prediction.timeframeProgress * 100)
        
        let canRefresh = AIPricePredictionService.shared.canGeneratePrediction
        
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if canRefresh {
                Task { await loadPredictionForTimeframe(selectedTimeframe, forceRefresh: true) }
            } else {
                showUpgradePrompt = true
            }
        } label: {
            HStack(spacing: 10) {
                // Warning icon with glow
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Prediction Getting Stale")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("\(progressPercent)%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.orange)
                            )
                    }
                    
                    Text(canRefresh
                         ? "Market conditions may have changed. Tap to refresh."
                         : "Daily limit reached. Upgrade to refresh predictions.")
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                // Refresh indicator or upgrade CTA
                HStack(spacing: 4) {
                    Image(systemName: canRefresh ? "arrow.clockwise" : "arrow.up.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(canRefresh ? "Refresh" : "Upgrade")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(canRefresh ? .orange : BrandColors.goldBase)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill((canRefresh ? Color.orange : BrandColors.goldBase).opacity(0.15))
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(isDark ? 0.12 : 0.08), Color.orange.opacity(isDark ? 0.06 : 0.04)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Paid Tier Manual Refresh Button
    
    /// Subtle refresh button for Pro/Premium users that is always visible.
    /// Shows cooldown countdown when within the cooldown window; otherwise allows immediate refresh.
    private var paidTierRefreshButton: some View {
        let predictionService = AIPricePredictionService.shared
        let cooldownLeft = predictionService.cooldownRemaining(for: coinSymbol, timeframe: selectedTimeframe)
        let canRefreshNow = cooldownLeft <= 0 && predictionService.canGeneratePrediction
        let cooldownText = formatCooldownRemaining(cooldownLeft)
        
        return Button {
            guard canRefreshNow, !isLoadingNewTimeframe else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await loadPredictionForTimeframe(selectedTimeframe, forceRefresh: true) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: canRefreshNow ? "arrow.clockwise" : "clock")
                    .font(.system(size: 11, weight: .semibold))
                
                if canRefreshNow {
                    Text("Refresh Prediction")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Text("Refresh available in \(cooldownText)")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundColor(canRefreshNow ? DS.Adaptive.textSecondary : DS.Adaptive.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isDark ? 0.04 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.Adaptive.stroke.opacity(canRefreshNow ? 0.2 : 0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .opacity(canRefreshNow ? 1 : 0.6)
        .disabled(!canRefreshNow || isLoadingNewTimeframe)
    }
    
    /// Format cooldown seconds into a human-readable string like "8m" or "1h 30m"
    private func formatCooldownRemaining(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "now" }
        let totalMinutes = Int(ceil(seconds / 60))
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }
    
    private func loadPredictionForTimeframe(_ timeframe: PredictionTimeframe, forceRefresh: Bool = false) async {
        // Cancel any existing loading task and safety timer
        currentLoadingTask?.cancel()
        loadingSafetyTimer?.invalidate()
        
        isLoadingNewTimeframe = true
        
        // Create the loading task
        let task = Task { @MainActor in
            defer {
                // Always clean up when task completes
                loadingSafetyTimer?.invalidate()
                loadingSafetyTimer = nil
                if isLoadingNewTimeframe {
                    isLoadingNewTimeframe = false
                }
            }
            
            do {
                // Check for cancellation before starting
                try Task.checkCancellation()
                
                let newPrediction = try await AIPricePredictionService.shared.generatePrediction(
                    for: coinSymbol,
                    coinName: coinName,
                    timeframe: timeframe,
                    forceRefresh: forceRefresh
                )
                
                // Check for cancellation before updating UI
                try Task.checkCancellation()
                
                // Only update if the timeframe matches what we requested
                // (prevents race conditions if user taps multiple timeframes quickly)
                guard selectedTimeframe == timeframe else {
                    return
                }
                
                withAnimation(.easeInOut(duration: 0.2)) {
                    prediction = newPrediction
                    // Ensure selectedTimeframe is in sync
                    selectedTimeframe = newPrediction.timeframe
                }
            } catch is CancellationError {
                print("[AIPrediction] Detail view loading task cancelled for \(timeframe.displayName)")
            } catch {
                print("[AIPrediction] Error loading prediction for \(timeframe.displayName): \(error.localizedDescription)")
            }
        }
        
        currentLoadingTask = task
        
        // Start safety timer that cancels the task if it takes too long.
        // Use [weak task] to avoid retaining the Task if the view is dismissed before timeout.
        loadingSafetyTimer = Timer.scheduledTimer(withTimeInterval: loadingSafetyTimeoutSeconds, repeats: false) { [weak task] _ in
            #if DEBUG
            print("[AIPrediction] Detail view safety timeout triggered - cancelling task")
            #endif
            task?.cancel()
        }
    }
    
    // MARK: - Premium Hero Card with Forecast Chart
    
    private var headerCard: some View {
        VStack(spacing: 0) {
            // Premium hero card
            VStack(spacing: 20) {
                // Top row: Coin info + Direction badge
                HStack(spacing: 12) {
                    // Coin icon - clean
                    if let url = coinIconUrl {
                        CoinImageView(symbol: prediction.coinSymbol, url: url, size: 48)
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(prediction.direction.color.opacity(0.3), lineWidth: 2)
                            )
                    } else {
                        Circle()
                            .fill(prediction.direction.color.opacity(0.15))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text(prediction.coinSymbol.prefix(2))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(prediction.direction.color)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prediction.coinName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        HStack(spacing: 6) {
                            Text(MarketFormat.price(displayCurrentPrice))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(DS.Adaptive.textSecondary)
                            
                            Text(prediction.formattedPriceChange)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(prediction.direction.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(prediction.direction.color.opacity(0.15))
                                )
                        }
                    }
                    
                    Spacer()
                    
                    // Direction indicator - clean style
                    VStack(spacing: 6) {
                        // Circle with arrow
                        ZStack {
                            Circle()
                                .fill(prediction.direction.color.opacity(0.15))
                                .frame(width: 48, height: 48)
                            
                            Circle()
                                .stroke(prediction.direction.color.opacity(0.3), lineWidth: 1.5)
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: prediction.direction == .bullish ? "arrow.up" : (prediction.direction == .bearish ? "arrow.down" : "minus"))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(prediction.direction.color)
                        }
                        
                        // Label
                        Text(prediction.direction.displayName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(prediction.direction.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(prediction.direction.color.opacity(0.15))
                            )
                    }
                }
                
                // Price comparison: Base price -> Target (fixed text scaling)
                HStack(spacing: 12) {
                    // Base price (current live price or prediction base)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BASE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .tracking(1)
                        
                        Text(formatPriceCompact(displayCurrentPrice))
                            .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Arrow with change
                    VStack(spacing: 4) {
                        Image(systemName: prediction.direction == .bullish ? "arrow.up.right" : (prediction.direction == .bearish ? "arrow.down.right" : "arrow.right"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(prediction.direction.color.opacity(0.7))
                        
                        Text(prediction.formattedPriceChange)
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundColor(prediction.direction.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(prediction.direction.color.opacity(0.15))
                            )
                    }
                    
                    // Target price (prominent)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("TARGET")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .tracking(1)
                        
                        Text(formatPriceCompact(displayPredictedPrice))
                            .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(prediction.direction.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(isDark ? 0.04 : 0.08))
                )
                
                // Confidence gauge and target date row
                HStack(spacing: 16) {
                    // Ring gauge
                    ConfidenceRingGauge(
                        score: prediction.confidenceScore,
                        confidence: prediction.confidence,
                        size: 100
                    )
                    
                    Spacer()
                    
                    // Target date section
                    VStack(alignment: .trailing, spacing: 8) {
                        Text("Prediction Target")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text(prediction.formattedTargetDate)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        // Countdown
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12))
                            Text(formatTimeRemaining(prediction.timeRemaining))
                                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        }
                        .foregroundColor(prediction.timeRemaining < 86400 ? .orange : DS.Adaptive.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(DS.Adaptive.chipBackground)
                        )
                    }
                }
                
                // Staleness warning banner when prediction is >75% through timeframe
                if prediction.needsRefresh {
                    detailStalenessWarning
                }
                
                // Manual refresh button for Pro/Premium users (always visible when not stale)
                // Free users do not see this — they rely on the staleness banner or upgrade prompt
                if !prediction.needsRefresh, SubscriptionManager.shared.hasTier(.pro) {
                    paidTierRefreshButton
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prediction.direction.color.opacity(isDark ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(prediction.direction.color.opacity(0.2), lineWidth: 1)
            )
        }
        .scaleEffect(hasAppeared ? 1 : 0.98)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    hasAppeared = true
                }
            }
            // Start timeout timer for loading states - show "Data unavailable" after 5 seconds
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                if !loadingTimedOut {
                    loadingTimedOut = true
                }
            }
        }
    }
    
    /// Format time remaining for countdown display
    private func formatTimeRemaining(_ remaining: TimeInterval) -> String {
        if remaining <= 0 { return "Expired" }
        
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h remaining"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else {
            return "\(minutes)m remaining"
        }
    }
    
    /// Format price compactly to avoid text overflow
    private func formatPriceCompact(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.currencySymbol = CurrencyManager.symbol
        
        if value >= 10000 {
            formatter.maximumFractionDigits = 0
        } else if value >= 100 {
            formatter.maximumFractionDigits = 1
        } else if value >= 1 {
            formatter.maximumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 4
        }
        
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    /// Format a price range compactly (e.g., "$89.5K-$90.2K")
    private func formatPriceRange(low: Double, high: Double) -> String {
        func compactPrice(_ value: Double) -> String {
            if value >= 1000 {
                return String(format: "$%.1fK", value / 1000)
            } else if value >= 1 {
                return String(format: "$%.0f", value)
            } else {
                return String(format: "$%.4f", value)
            }
        }
        return "\(compactPrice(low))-\(compactPrice(high))"
    }
    
    // MARK: - Prediction Chart Card (Full Visual with Historical + Projection)
    
    private var predictionChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(prediction.direction.color)
                    
                    Text("Price Trajectory")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
            }
            
            // The prediction chart - compact height for detail view
            // Uses displayCurrentPrice (live price) so chart matches header and home card
            if !sparklineData.isEmpty || sparklineTimedOut {
                MiniPredictionChart(
                    currentPrice: displayCurrentPrice,
                    predictedPrice: displayPredictedPrice,
                    direction: prediction.direction,
                    sparklineData: sparklineData.isEmpty ? nil : sparklineData,
                    livePrice: liveDisplayPrice ?? marketVM.bestPrice(forSymbol: coinSymbol),
                    timeframe: prediction.timeframe,
                    generatedAt: prediction.generatedAt
                )
                .id("mini_prediction_\(prediction.id)_\(sparklineData.count)")
                .frame(height: 170) // Taller for detail view with padding for labels
            } else {
                // Loading/placeholder state - will auto-resolve via retry or timeout
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading chart...")
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            
            // Compact price summary with change - single row
            let changePercent = displayCurrentPrice > 0 ? ((displayPredictedPrice - displayCurrentPrice) / displayCurrentPrice) * 100 : 0
            
            HStack(spacing: 8) {
                // Current price
                Text(formatPriceCompact(displayCurrentPrice))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                // Target price
                Text(formatPriceCompact(displayPredictedPrice))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(prediction.direction.color)
                
                Spacer()
                
                // Change percentage badge
                Text("\(changePercent >= 0 ? "+" : "")\(String(format: "%.1f", changePercent))%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(prediction.direction.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(prediction.direction.color.opacity(0.12))
                    )
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isDark ? 0.03 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(prediction.direction.color.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Price Range Card
    
    private var priceRangeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Clean header - removed icon for cleaner design
            HStack {
                Text("Price Range")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                // Timeframe badge
                Text(selectedTimeframe.fullName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(isDark ? 0.06 : 0.1))
                    )
            }
            
            // Enhanced price range visualization
            // Uses live-adjusted display prices for consistency with header and home card
            EnhancedPriceRangeVisualization(
                currentPrice: displayCurrentPrice,
                predictedPrice: displayPredictedPrice,
                lowPrice: displayPredictedPriceLow,
                highPrice: displayPredictedPriceHigh,
                direction: prediction.direction
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isDark ? 0.03 : 0.05))
        )
    }
    
    // MARK: - Professional Insights Card (Smart Money, Regime, Confluence)
    
    private var professionalInsightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Premium header with gold accent - matches app brand
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [BrandColors.goldBase.opacity(0.35), BrandColors.goldBase.opacity(0.08)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 14
                                )
                            )
                            .frame(width: 30, height: 30)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [BrandColors.goldLight, BrandColors.goldBase],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    Text("Professional Insights")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // PRO badge with gold gradient
                Text("PRO")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isDark ? .black : .white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
            
            Text("Live context from flow, regime, confluence, and historical hit-rate")
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textSecondary)
            
            // Volume Profile Section
            volumeProfileInsightRow
            
            // Smart Money Section
            smartMoneyInsightRow
            
            // Market Regime Section
            marketRegimeInsightRow
            
            // Multi-Timeframe Confluence
            confluenceInsightRow
            
            // Historical Accuracy
            accuracyInsightRow
        }
        .padding(14)
        .background(
            ZStack {
                // Glassmorphism base
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                
                // Subtle gold gradient overlay for premium feel
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                BrandColors.goldBase.opacity(isDark ? 0.06 : 0.04),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Gold-tinted border
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                BrandColors.goldBase.opacity(0.25),
                                BrandColors.goldBase.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
    }
    
    // Volume Profile insight row - shows trading activity relative to market cap
    private var volumeProfileInsightRow: some View {
        // Check if market data is still loading
        let isMarketLoading = marketVM.allCoins.isEmpty
        
        // Get volume and market cap data from MarketViewModel
        // Try multiple matching strategies for the coin
        let volumeData: (ratio: Double, interpretation: String, signal: String)? = {
            // Try exact symbol match first, then ID-based match for coins like "bitcoin"
            let coin = marketVM.allCoins.first(where: { $0.symbol.uppercased() == coinSymbol.uppercased() })
                ?? marketVM.allCoins.first(where: { $0.id.lowercased() == coinSymbol.lowercased() })
                ?? marketVM.allCoins.first(where: { $0.id.lowercased().contains(coinSymbol.lowercased()) })
            
            guard let foundCoin = coin else { return nil }
            
            // Try multiple volume sources (totalVolume, volumeUsd24Hr)
            let volume24h = foundCoin.totalVolume ?? foundCoin.volumeUsd24Hr ?? 0
            let marketCap = foundCoin.marketCap ?? 0
            guard volume24h > 0 && marketCap > 0 else { return nil }
            
            let volumeToMcap = (volume24h / marketCap) * 100
            let interpretation: String
            let signal: String
            
            if volumeToMcap > 25 {
                signal = "bullish"
                interpretation = "Very high activity"
            } else if volumeToMcap > 15 {
                signal = "bullish"
                interpretation = "High activity"
            } else if volumeToMcap > 8 {
                signal = "bullish"
                interpretation = "Above average"
            } else if volumeToMcap > 3 {
                signal = "neutral"
                interpretation = "Normal activity"
            } else if volumeToMcap > 0.5 {
                signal = "neutral"
                interpretation = "Below average"
            } else {
                signal = "bearish"
                interpretation = "Low activity"
            }
            
            return (volumeToMcap, interpretation, signal)
        }()
        
        // Determine color based on signal or use neutral for unavailable
        let signalColor: Color = {
            switch volumeData?.signal {
            case "bullish": return .green
            case "bearish": return .red
            case "neutral": return .yellow
            default: return DS.Adaptive.textTertiary // Neutral gray when unavailable
            }
        }()
        
        // If data is unavailable and market is loaded, use prediction direction as fallback signal
        let fallbackSignal: (label: String, color: Color)? = {
            guard volumeData == nil && !isMarketLoading else { return nil }
            // Use prediction direction as a proxy signal
            switch prediction.direction {
            case .bullish: return ("Bullish bias", .green)
            case .bearish: return ("Bearish bias", .red)
            case .neutral: return ("Neutral", .yellow)
            }
        }()
        
        let displayColor = volumeData != nil ? signalColor : (fallbackSignal?.color ?? DS.Adaptive.textTertiary)
        
        return HStack(spacing: 10) {
            // Standardized icon container (34px)
            ZStack {
                Circle()
                    .fill(displayColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                
                if isMarketLoading && volumeData == nil {
                    // Show loading spinner when market data is loading
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(displayColor)
                } else {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(displayColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Volume Profile")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                if let data = volumeData {
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f%%", data.ratio))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(signalColor)
                        
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text(data.interpretation)
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                } else if isMarketLoading {
                    // Show loading message when market data is still loading
                    Text("Gathering live data...")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                } else if let fallback = fallbackSignal {
                    // Show prediction-based fallback when volume unavailable
                    Text(fallback.label)
                        .font(.system(size: 10))
                        .foregroundColor(fallback.color.opacity(0.8))
                } else {
                    // Volume data not available for this coin
                    Text("Insufficient data")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            Spacer()
            
            // Activity indicator with trend arrow
            if let data = volumeData {
                HStack(spacing: 4) {
                    Image(systemName: data.signal == "bullish" ? "arrow.up.right" : (data.signal == "bearish" ? "arrow.down.right" : "minus"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(signalColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(signalColor.opacity(0.1))
                )
            } else if let fallback = fallbackSignal {
                // Show directional indicator based on prediction
                Image(systemName: prediction.direction == .bullish ? "arrow.up.right" : (prediction.direction == .bearish ? "arrow.down.right" : "minus"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(fallback.color.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(fallback.color.opacity(0.1))
                    )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isDark ? 0.03 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(isDark ? 0.10 : 0.14), lineWidth: 0.6)
                )
        )
    }
    
    // Smart Money insight row
    private var smartMoneyInsightRow: some View {
        let whaleService = WhaleTrackingService.shared
        let smi = whaleService.smartMoneyIndex
        let stats = whaleService.statistics
        let smiColor: Color = {
            guard let score = smi?.score else { return .purple }
            return score >= 55 ? .green : (score <= 45 ? .red : .yellow)
        }()
        
        return HStack(spacing: 10) {
            // Standardized icon container (34px)
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 34, height: 34)
                
                Image(systemName: "fish.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.purple)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Money")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                if let smi = smi {
                    HStack(spacing: 4) {
                        Text("\(smi.score)/100")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(smiColor)
                        
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text(smi.trend.rawValue)
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                } else if loadingTimedOut {
                    Text("Data unavailable")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                } else {
                    // Shimmer loading state
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .tint(DS.Adaptive.textTertiary)
                        Text("Gathering live data...")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Exchange flow indicator with trend
            if let stats = stats {
                let isOutflow = stats.netExchangeFlow < 0
                HStack(spacing: 4) {
                    Text(isOutflow ? "Outflow" : "Inflow")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isOutflow ? .green : .red)
                    
                    Image(systemName: isOutflow ? "arrow.up.right" : "arrow.down.left")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isOutflow ? .green : .red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill((isOutflow ? Color.green : Color.red).opacity(0.1))
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isDark ? 0.03 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(isDark ? 0.10 : 0.14), lineWidth: 0.6)
                )
        )
    }
    
    // Market Regime insight row
    private var marketRegimeInsightRow: some View {
        // Detect regime from sparkline data - lowered threshold from 20 to 12 for better data availability
        let regimeResult: RegimeDetectionResult? = {
            guard sparklineData.count >= 12 else { return nil }
            return MarketRegimeDetector.detectRegime(closes: sparklineData)
        }()
        
        return HStack(spacing: 10) {
            // Standardized icon container (34px)
            ZStack {
                Circle()
                    .fill(regimeResult?.regime.color.opacity(0.12) ?? Color.gray.opacity(0.10))
                    .frame(width: 34, height: 34)
                
                Image(systemName: regimeResult?.regime.icon ?? "chart.xyaxis.line")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(regimeResult?.regime.color ?? DS.Adaptive.textTertiary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Market Regime")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                if let regime = regimeResult {
                    HStack(spacing: 4) {
                        Text(regime.regime.displayName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(regime.regime.color)
                        
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text("\(Int(regime.confidence))% confidence")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                } else {
                    Text("Analyzing...")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            Spacer()
            
            // Regime implication badge - actionable guidance
            if let regime = regimeResult {
                Text(regimeImplicationBadge(regime.regime))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(regime.regime.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(regime.regime.color.opacity(0.1))
                    )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isDark ? 0.03 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(isDark ? 0.10 : 0.14), lineWidth: 0.6)
                )
        )
    }
    
    private func regimeImplicationBadge(_ regime: MarketRegime) -> String {
        switch regime {
        case .trendingUp: return "Ride Trend"
        case .trendingDown: return "Wait for Reversal"
        case .ranging: return "Trade Range"
        case .highVolatility: return "Reduce Size"
        case .lowVolatility: return "Watch Breakout"
        case .breakoutPotential: return "Prepare Entry"
        }
    }
    
    // Multi-Timeframe Confluence insight row
    private var confluenceInsightRow: some View {
        // Check confluence from sparkline - lowered threshold from 50 to 20 for better data availability
        // determineTrend() requires minimum 10 data points, so 20 allows both short and long trend analysis
        let confluence: (agrees: Bool, trend: String)? = {
            guard sparklineData.count >= 20 else { return nil }
            // Use available data: short-term is last 25% of data, long-term is full data
            let shortTermCount = max(10, sparklineData.count / 4)
            let shortTrend = determineTrend(from: Array(sparklineData.suffix(shortTermCount)))
            let longTrend = determineTrend(from: sparklineData)
            return (shortTrend == longTrend || longTrend == "neutral", longTrend)
        }()
        
        let confColor: Color = confluence?.agrees == true ? .green : .orange
        
        return HStack(spacing: 10) {
            // Standardized icon container (34px)
            ZStack {
                Circle()
                    .fill(confColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                
                Image(systemName: confluence?.agrees == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(confluence != nil ? confColor : DS.Adaptive.textTertiary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Timeframe Confluence")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                if let conf = confluence {
                    HStack(spacing: 4) {
                        Text(conf.agrees ? "Aligned" : "Divergence")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(confColor)
                        
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text("Higher TF: \(conf.trend.capitalized)")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                } else {
                    Text("Analyzing...")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            Spacer()
            
            // Action badge with trend indicator
            if let conf = confluence {
                HStack(spacing: 3) {
                    Image(systemName: conf.agrees ? "arrow.up.right" : "arrow.left.arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(confColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(confColor.opacity(0.1))
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isDark ? 0.03 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(isDark ? 0.10 : 0.14), lineWidth: 0.6)
                )
        )
    }
    
    private func determineTrend(from data: [Double]) -> String {
        // Lowered minimum from 10 to 5 for better data availability
        guard data.count >= 5 else { return "neutral" }
        guard let first = data.first, let last = data.last, first > 0 else { return "neutral" }
        let change = (last - first) / first * 100
        // Adjusted thresholds: 1.5% for limited data to account for noise
        let threshold: Double = data.count < 10 ? 1.5 : 2.0
        if change > threshold { return "bullish" }
        if change < -threshold { return "bearish" }
        return "neutral"
    }
    
    // Historical Accuracy insight row - uses gold accent for premium feel
    // Uses displayMetrics to show DeepSeek-only when available (consistent with accuracy card)
    private var accuracyInsightRow: some View {
        let metrics = accuracyService.displayMetrics
        let hasData = metrics.evaluatedPredictions >= 5
        // Use rounded percentage to match AI Prediction Accuracy card
        let roundedAccuracy = Int(round(metrics.directionAccuracyPercent))
        let accColor: Color = metrics.directionAccuracyPercent >= 60 ? .green : (metrics.directionAccuracyPercent >= 50 ? .yellow : .orange)
        
        return HStack(spacing: 10) {
            // Standardized icon container (34px) with gold accent
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldBase.opacity(0.15), BrandColors.goldBase.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                
                Image(systemName: "target")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Historical Accuracy")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                if hasData {
                    HStack(spacing: 4) {
                        // Use rounded value for consistency with AI Prediction Accuracy card
                        Text("\(roundedAccuracy)%")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(accColor)
                        
                        Text("direction")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text("\(metrics.evaluatedPredictions) samples")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                } else {
                    Text("Building history... (\(metrics.evaluatedPredictions)/5)")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            Spacer()
            
            // Avg error badge with gold accent
            if hasData {
                HStack(spacing: 4) {
                    Text("\(String(format: "%.1f", metrics.averagePriceError))%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(BrandColors.goldBase)
                    Text("avg err")
                        .font(.system(size: 8))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(BrandColors.goldBase.opacity(0.1))
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isDark ? 0.03 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(isDark ? 0.10 : 0.14), lineWidth: 0.6)
                )
        )
    }
    
    // MARK: - Locked Professional Insights (Free users)
    
    /// Locked preview of Professional Insights for free users with upgrade CTA.
    /// Shows the section header and a blurred preview with benefit bullets.
    private var lockedProfessionalInsightsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Same header as unlocked version
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [BrandColors.goldBase.opacity(0.35), BrandColors.goldBase.opacity(0.08)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 14
                                )
                            )
                            .frame(width: 30, height: 30)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [BrandColors.goldLight, BrandColors.goldBase],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    Text("Professional Insights")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Lock + PRO badge
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7, weight: .bold))
                    Text("PRO")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(isDark ? .black : .white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    LinearGradient(
                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
            
            // Blurred preview placeholder rows
            VStack(spacing: 10) {
                lockedInsightRow(icon: "chart.bar.fill", title: "Volume Profile", subtitle: "Buy & sell pressure analysis")
                lockedInsightRow(icon: "dollarsign.arrow.circlepath", title: "Institutional Flow", subtitle: "Large-order activity signals")
                lockedInsightRow(icon: "waveform.path.ecg", title: "Market Regime", subtitle: "Trend strength & reversal signals")
                lockedInsightRow(icon: "arrow.triangle.branch", title: "Timeframe Confluence", subtitle: "Multi-timeframe alignment check")
            }
            .allowsHitTesting(false)
            
            // Upgrade CTA
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showUpgradePrompt = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Unlock Professional Insights")
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                PremiumPrimaryCTAStyle(
                    height: 44,
                    horizontalPadding: 14,
                    cornerRadius: 10,
                    font: .system(size: 14, weight: .bold)
                )
            )
            
            // Benefit bullets
            VStack(alignment: .leading, spacing: 6) {
                proInsightBenefit("Institutional flow & large-order signals")
                proInsightBenefit("Market regime detection with reversal alerts")
                proInsightBenefit("Multi-timeframe confluence analysis")
                proInsightBenefit("15 AI predictions per day (50 with Premium)")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isDark ? 0.04 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BrandColors.goldBase.opacity(0.2), lineWidth: 1)
        )
    }
    
    /// A locked/blurred row for the Professional Insights preview
    private func lockedInsightRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(BrandColors.goldBase.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isDark ? 0.03 : 0.04))
        )
    }
    
    /// A checkmark bullet point for the Pro benefits list
    private func proInsightBenefit(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(BrandColors.goldBase)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Adaptive.textSecondary)
        }
    }
    
    // MARK: - Trading Action Card (Enhanced with ATR, Pivots, Fibonacci)
    
    private var tradingActionCard: some View {
        // Use displayCurrentPrice (live price) so trading levels match all other price displays
        let currentPrice = displayCurrentPrice
        
        // Calculate enhanced trading levels using ATR, Pivots, and Fibonacci
        let timeframeString: String = {
            switch prediction.timeframe {
            case .hour: return "1h"
            case .fourHours: return "4h"
            case .twelveHours: return "12h"
            case .day: return "1d"
            case .week: return "7d"
            case .month: return "30d"
            }
        }()
        
        let directionString = prediction.direction == .bullish ? "bullish" : (prediction.direction == .bearish ? "bearish" : "neutral")
        
        // Use enhanced calculation if sparkline data is available (ATR/RSI need minimum 14 points)
        let levels: TechnicalsEngine.EnhancedTradingLevels = {
            if sparklineData.count >= 14 {
                return TechnicalsEngine.calculateEnhancedTradingLevels(
                    closes: sparklineData,
                    currentPrice: currentPrice,
                    direction: directionString,
                    predictedChange: prediction.predictedPriceChange,
                    predictedHigh: displayPredictedPriceHigh,
                    predictedLow: displayPredictedPriceLow,
                    timeframe: timeframeString
                )
            } else {
                // Fallback to basic calculation when insufficient data
                return fallbackTradingLevels(currentPrice: currentPrice, direction: directionString)
            }
        }()
        
        let entryZone = (low: levels.entryZoneLow, high: levels.entryZoneHigh)
        let stopLoss = levels.stopLoss
        let takeProfit = levels.takeProfit
        let riskRewardRatio = levels.riskRewardRatio
        
        // Calculate confidence for trade setup based on R:R and signal alignment
        let tradeConfidence: (level: String, color: Color, percent: Int) = {
            var score = 50 // Base score
            
            // R:R contribution (up to +25)
            if riskRewardRatio >= 3 { score += 25 }
            else if riskRewardRatio >= 2 { score += 20 }
            else if riskRewardRatio >= 1.5 { score += 10 }
            else if riskRewardRatio < 1 { score -= 15 }
            
            // Prediction confidence contribution (up to +25)
            switch prediction.confidence {
            case .high: score += 25
            case .medium: score += 10
            case .low: score -= 5
            }
            
            // Clamp to 0-100
            score = max(0, min(100, score))
            
            let level: String
            let color: Color
            if score >= 70 {
                level = "High"
                color = .green
            } else if score >= 50 {
                level = "Medium"
                color = .yellow
            } else {
                level = "Low"
                color = .red
            }
            return (level, color, score)
        }()
        
        return VStack(alignment: .leading, spacing: 14) {
            // Premium header with gradient accent
            HStack {
                HStack(spacing: 10) {
                    // Icon with glow effect
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [BrandColors.goldBase.opacity(0.4), BrandColors.goldBase.opacity(0.1)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 16
                                )
                            )
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "scope")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(BrandColors.goldBase)
                    }
                    
                    Text("Trading Levels")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Trade setup confidence badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(tradeConfidence.color)
                        .frame(width: 6, height: 6)
                    Text("\(tradeConfidence.percent)%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(tradeConfidence.color)
                    Text("confidence")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(tradeConfidence.color.opacity(isDark ? 0.15 : 0.1))
                )
            }
            
            // Visual Price Ladder with all levels including multi-TP
            VisualPriceLadder(
                currentPrice: currentPrice,
                entryZoneLow: entryZone.low,
                entryZoneHigh: entryZone.high,
                stopLoss: stopLoss,
                takeProfit: takeProfit,
                direction: prediction.direction,
                riskRewardRatio: riskRewardRatio,
                methodology: levels.methodology,
                takeProfit1: levels.takeProfit1,
                takeProfit2: levels.takeProfit2,
                tp1Percent: levels.tp1Percent,
                tp2Percent: levels.tp2Percent,
                tp3Percent: levels.tp3Percent,
                stopLossPercent: levels.stopLossPercent,
                generatedAt: prediction.generatedAt
            )
            .id("ladder_\(prediction.id)_\(prediction.timeframe.rawValue)")
            
            // Compact stats row with glassmorphism
            let priceInEntryZone = currentPrice >= entryZone.low && currentPrice <= entryZone.high
            let entryZonePercent = currentPrice > 0
                ? abs(entryZone.high - entryZone.low) / currentPrice * 100
                : 0
            HStack(spacing: 8) {
                // Entry Zone stat - always blue for distinct identity; checkmark signals "in zone"
                let entryRangeStr = formatPriceRange(low: entryZone.low, high: entryZone.high)
                TradingLevelStat(
                    label: priceInEntryZone ? "ENTRY ✓" : "ENTRY",
                    value: entryRangeStr,
                    subValue: String(format: "Zone %.1f%%", entryZonePercent),
                    color: .blue
                )
                
                // Stop Loss stat
                TradingLevelStat(
                    label: "Stop",
                    value: formatPriceCompact(stopLoss),
                    subValue: String(format: "Risk %.1f%%", levels.stopLossPercent),
                    color: .red
                )
                
                // Take Profit stat
                TradingLevelStat(
                    label: "Target",
                    value: formatPriceCompact(takeProfit),
                    subValue: String(format: "Reward %.1f%%", levels.takeProfitPercent),
                    color: .green
                )
            }
            
            // Disclaimer with subtle styling
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.orange.opacity(0.7))
                
                Text("Example analysis for educational purposes. Not a trade signal.")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .padding(14)
        .background(
            // Glassmorphism background
            ZStack {
                // Base gradient
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                prediction.direction.color.opacity(isDark ? 0.08 : 0.04),
                                Color.white.opacity(isDark ? 0.04 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Blur overlay for glassmorphism effect
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground.opacity(isDark ? 0.6 : 0.8))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            prediction.direction.color.opacity(0.3),
                            Color.white.opacity(isDark ? 0.1 : 0.2),
                            prediction.direction.color.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    /// Fallback trading levels calculation when sparkline data is insufficient
    private func fallbackTradingLevels(currentPrice: Double, direction: String) -> TechnicalsEngine.EnhancedTradingLevels {
        let predictedChange = prediction.predictedPriceChange
        
        // Timeframe-aware stop loss percentages
        let stopLossPercent: Double = {
            switch prediction.timeframe {
            case .hour: return 1.0
            case .fourHours: return 1.5
            case .twelveHours: return 2.0
            case .day: return 2.5
            case .week: return 5.0
            case .month: return 8.0
            }
        }()
        
        var entryZoneLow: Double
        var entryZoneHigh: Double
        var stopLoss: Double
        var takeProfit: Double
        
        // Minimum move % per timeframe to prevent entry ≈ TP
        let minMovePercent: Double = {
            switch prediction.timeframe {
            case .hour: return 0.5
            case .fourHours: return 1.0
            case .twelveHours: return 1.5
            case .day: return 2.0
            case .week: return 4.0
            case .month: return 8.0
            }
        }()
        
        if direction == "bullish" {
            let pullbackPercent = min(abs(predictedChange) * 0.3, 2.0)
            entryZoneLow = currentPrice * (1 - pullbackPercent / 100)
            entryZoneHigh = currentPrice * 1.002
            let predictedStop = displayPredictedPriceLow * 0.99
            let maxStop = currentPrice * (1 - stopLossPercent / 100)
            stopLoss = max(predictedStop, maxStop)
            // Ensure TP has minimum separation from current price
            let minTP = currentPrice * (1 + minMovePercent / 100)
            takeProfit = max(displayPredictedPriceHigh, minTP)
            // Ensure entry zone high is below TP (max 35% of the move)
            let moveBull = takeProfit - currentPrice
            let maxEntryH = currentPrice + moveBull * 0.35
            if entryZoneHigh > maxEntryH { entryZoneHigh = maxEntryH }
            if entryZoneLow >= entryZoneHigh { entryZoneLow = currentPrice * 0.995 }
        } else if direction == "bearish" {
            let bouncePercent = min(abs(predictedChange) * 0.3, 2.0)
            entryZoneLow = currentPrice * 0.998
            entryZoneHigh = currentPrice * (1 + bouncePercent / 100)
            let predictedStop = displayPredictedPriceHigh * 1.01
            let maxStop = currentPrice * (1 + stopLossPercent / 100)
            stopLoss = min(predictedStop, maxStop)
            // Ensure TP has minimum separation from current price
            let maxTP = currentPrice * (1 - minMovePercent / 100)
            takeProfit = min(displayPredictedPriceLow, maxTP)
            // Ensure entry zone low is above TP
            let moveBear = currentPrice - takeProfit
            let minEntryL = currentPrice - moveBear * 0.35
            if entryZoneLow < minEntryL { entryZoneLow = minEntryL }
            if entryZoneLow >= entryZoneHigh { entryZoneHigh = currentPrice * 1.005 }
        } else {
            entryZoneLow = displayPredictedPriceLow
            entryZoneHigh = displayPredictedPriceHigh
            stopLoss = displayPredictedPriceLow * (1 - stopLossPercent / 100)
            takeProfit = displayPredictedPriceHigh
        }
        
        let risk = abs(currentPrice - stopLoss)
        let reward = abs(takeProfit - currentPrice)
        var riskRewardRatio = risk > 0 ? reward / risk : 1.5
        
        // Enforce minimum R:R of 1.5:1
        if riskRewardRatio < 1.5 && risk > 0 {
            let requiredReward = risk * 1.5
            if direction == "bullish" {
                takeProfit = currentPrice + requiredReward
            } else if direction == "bearish" {
                takeProfit = currentPrice - requiredReward
            }
            riskRewardRatio = 1.5
        }
        
        let slPercent = currentPrice > 0 ? abs((stopLoss - currentPrice) / currentPrice * 100) : 0
        let tpPercent = currentPrice > 0 ? abs((takeProfit - currentPrice) / currentPrice * 100) : 0
        
        // Calculate multiple take profit levels (33%, 66%, 100% of move)
        let priceMove = takeProfit - currentPrice
        let tp1 = currentPrice + (priceMove * 0.33)
        let tp2 = currentPrice + (priceMove * 0.66)
        let tp1Percent = abs((tp1 - currentPrice) / currentPrice * 100)
        let tp2Percent = abs((tp2 - currentPrice) / currentPrice * 100)
        
        return TechnicalsEngine.EnhancedTradingLevels(
            entryZoneLow: entryZoneLow,
            entryZoneHigh: entryZoneHigh,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            riskRewardRatio: riskRewardRatio,
            stopLossPercent: slPercent,
            takeProfitPercent: tpPercent,
            atrMultipleUsed: 0,
            pivotSupport: nil,
            pivotResistance: nil,
            fibLevel: nil,
            methodology: "Standard levels",
            takeProfit1: tp1,
            takeProfit2: tp2,
            tp1Percent: tp1Percent,
            tp2Percent: tp2Percent,
            tp3Percent: tpPercent
        )
    }
    
    // MARK: - Analysis Card (Premium Design)
    
    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Premium header with icon glow - consistent with other sections
            HStack {
                HStack(spacing: 10) {
                    // Icon with glow effect
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [BrandColors.goldBase.opacity(0.4), BrandColors.goldBase.opacity(0.1)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 16
                                )
                            )
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(BrandColors.goldBase)
                    }
                    
                    Text("CryptoSage AI Analysis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
                
                Spacer()
                
                // Timestamp badge
                Text(formattedTimestamp)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(isDark ? 0.06 : 0.1))
                    )
            }
            
            // Analysis text with accent bar
            HStack(alignment: .top, spacing: 0) {
                // Gold accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldBase, BrandColors.goldDark],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                
                // Analysis text
                Text(prediction.analysis)
                    .font(.system(size: 14))
                    .foregroundColor(DS.Adaptive.textPrimary.opacity(0.9))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isDark ? 0.03 : 0.05))
        )
    }
    
    // MARK: - Drivers Card (Premium Compact Design)
    
    private var driversCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Premium header with icon glow
            HStack {
                HStack(spacing: 10) {
                    // Icon with glow effect
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [BrandColors.goldBase.opacity(0.4), BrandColors.goldBase.opacity(0.1)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 16
                                )
                            )
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(BrandColors.goldBase)
                    }
                    
                    Text("Key Drivers")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Count badge with gradient - use effectiveDrivers count
                Text("\(effectiveDrivers.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [BrandColors.goldBase, BrandColors.goldDark],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            
            // Enhanced driver grid with 3D cards - show 6 by default, expand for more
            // Always use effectiveDrivers which provides fallback if needed
            let drivers = effectiveDrivers
            
            // Show 6 drivers by default, or all if expanded
            let visibleDrivers = showAllDrivers ? drivers : Array(drivers.prefix(6))
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(visibleDrivers, id: \.id) { driver in
                    Enhanced3DDriverCard(driver: driver)
                }
            }
            
            // Show expand/collapse button if there are more than 6 drivers
            if drivers.count > 6 {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showAllDrivers.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(showAllDrivers ? "Show Less" : "Show All \(drivers.count)")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: showAllDrivers ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(BrandColors.goldBase)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(BrandColors.goldBase.opacity(isDark ? 0.12 : 0.08))
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            // Glassmorphism background
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                BrandColors.goldBase.opacity(isDark ? 0.06 : 0.03),
                                Color.white.opacity(isDark ? 0.03 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground.opacity(isDark ? 0.5 : 0.7))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            BrandColors.goldBase.opacity(0.25),
                            Color.white.opacity(isDark ? 0.08 : 0.15),
                            BrandColors.goldBase.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Signal Summary Card (Enhanced with Animations)
    
    @State private var animateSignalBars: Bool = false
    
    private var signalSummaryCard: some View {
        // Use effectiveDrivers to ensure we always have data for Signal Overview
        let drivers = effectiveDrivers
        let bullishCount = drivers.filter { $0.signal.lowercased() == "bullish" }.count
        let bearishCount = drivers.filter { $0.signal.lowercased() == "bearish" }.count
        let neutralCount = drivers.filter { $0.signal.lowercased() == "neutral" }.count
        let total = max(drivers.count, 1)
        let netSignal = bullishCount > bearishCount ? "Bullish" : (bearishCount > bullishCount ? "Bearish" : "Mixed")
        let netColor = bullishCount > bearishCount ? Color.green : (bearishCount > bullishCount ? Color.red : Color.yellow)
        
        return VStack(spacing: 14) {
            // Premium header with animated icon
            HStack {
                HStack(spacing: 10) {
                    // Animated waveform icon
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [netColor.opacity(0.3), netColor.opacity(0.1)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 16
                                )
                            )
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(netColor)
                            .symbolEffect(.pulse, options: .repeating, value: animateSignalBars)
                    }
                    
                    Text("Signal Overview")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Animated signal badge with glow
                HStack(spacing: 5) {
                    Image(systemName: netSignal == "Bullish" ? "arrow.up.right" : (netSignal == "Bearish" ? "arrow.down.right" : "minus"))
                        .font(.system(size: 10, weight: .bold))
                    Text(netSignal)
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(netColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [netColor.opacity(0.25), netColor.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(netColor.opacity(0.3), lineWidth: 0.8)
                )
            }
            
            // Animated horizontal stacked bar
            GeometryReader { geo in
                let width = geo.size.width
                let barHeight: CGFloat = 10
                let animatedMultiplier: CGFloat = animateSignalBars ? 1.0 : 0.0
                let bullishWidth = width * CGFloat(bullishCount) / CGFloat(total) * animatedMultiplier
                let neutralWidth = width * CGFloat(neutralCount) / CGFloat(total) * animatedMultiplier
                let bearishWidth = width * CGFloat(bearishCount) / CGFloat(total) * animatedMultiplier
                
                HStack(spacing: 3) {
                    if bullishCount > 0 {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.9), Color.green.opacity(0.6)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: max(bullishWidth - 2, 6), height: barHeight)
                    }
                    if neutralCount > 0 {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.yellow.opacity(0.9), Color.yellow.opacity(0.6)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: max(neutralWidth - 2, 6), height: barHeight)
                    }
                    if bearishCount > 0 {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.9), Color.red.opacity(0.6)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: max(bearishWidth - 2, 6), height: barHeight)
                    }
                }
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: animateSignalBars)
            }
            .frame(height: 10)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(isDark ? 0.06 : 0.1))
            )
            
            // Enhanced stat pills with animation - tighter spacing
            HStack(spacing: 8) {
                AnimatedSignalPill(count: bullishCount, label: "Bullish", color: .green, delay: 0.1, animate: animateSignalBars)
                AnimatedSignalPill(count: neutralCount, label: "Neutral", color: .yellow, delay: 0.2, animate: animateSignalBars)
                AnimatedSignalPill(count: bearishCount, label: "Bearish", color: .red, delay: 0.3, animate: animateSignalBars)
            }
            
            // Explanatory note when signals are mixed but prediction has direction
            if netSignal == "Mixed" && prediction.direction != .neutral {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(BrandColors.goldBase.opacity(0.7))
                    Text("AI uses weighted analysis. Key indicators carry more weight.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(BrandColors.goldBase.opacity(isDark ? 0.08 : 0.05))
                )
            }
        }
        .padding(16)
        .background(
            // Glassmorphism background
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                netColor.opacity(isDark ? 0.06 : 0.03),
                                Color.white.opacity(isDark ? 0.03 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground.opacity(isDark ? 0.5 : 0.7))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            netColor.opacity(0.2),
                            Color.white.opacity(isDark ? 0.08 : 0.15),
                            netColor.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                animateSignalBars = true
            }
        }
    }
    
    // MARK: - Probability Distribution Card (CoinStats-style)
    
    private var probabilityDistributionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with directional score
            HStack {
                HStack(spacing: 6) {
                    // Ring-style icon to match the probability ring visualization
                    ZStack {
                        Circle()
                            .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 2)
                            .frame(width: 16, height: 16)
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(BrandColors.goldBase, lineWidth: 2)
                            .frame(width: 16, height: 16)
                            .rotationEffect(.degrees(-90))
                    }
                    
                    Text("Probability Distribution")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Directional score badge
                if let score = prediction.directionalScore {
                    HStack(spacing: 3) {
                        Image(systemName: score > 0 ? "arrow.up.right" : (score < 0 ? "arrow.down.right" : "minus"))
                            .font(.system(size: 8, weight: .bold))
                        Text(prediction.formattedDirectionalScore ?? "\(score)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(prediction.directionalScoreColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(prediction.directionalScoreColor.opacity(0.12))
                    )
                }
            }
            
            // Directional score label
            if let label = prediction.directionalScoreLabel {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            // Probability rings visualization
            VStack(spacing: 8) {
                // Upside probabilities
                if prediction.probabilityUp2Pct != nil || prediction.probabilityUp5Pct != nil || prediction.probabilityUp10Pct != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("UPSIDE PROBABILITY")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .tracking(0.5)
                        
                        HStack(spacing: 8) {
                            if let prob = prediction.probabilityUp2Pct {
                                ProbabilityRing(threshold: "+2%", probability: prob, color: .green)
                            }
                            if let prob = prediction.probabilityUp5Pct {
                                ProbabilityRing(threshold: "+5%", probability: prob, color: .green)
                            }
                            if let prob = prediction.probabilityUp10Pct {
                                ProbabilityRing(threshold: "+10%", probability: prob, color: .green)
                            }
                        }
                    }
                }
                
                Divider()
                    .background(DS.Adaptive.stroke.opacity(0.2))
                
                // Downside probabilities
                if prediction.probabilityDown2Pct != nil || prediction.probabilityDown5Pct != nil || prediction.probabilityDown10Pct != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DOWNSIDE PROBABILITY")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .tracking(0.5)
                        
                        HStack(spacing: 8) {
                            if let prob = prediction.probabilityDown2Pct {
                                ProbabilityRing(threshold: "-2%", probability: prob, color: .red)
                            }
                            if let prob = prediction.probabilityDown5Pct {
                                ProbabilityRing(threshold: "-5%", probability: prob, color: .red)
                            }
                            if let prob = prediction.probabilityDown10Pct {
                                ProbabilityRing(threshold: "-10%", probability: prob, color: .red)
                            }
                        }
                    }
                }
            }
            
            // Expected Value calculation
            let expectedValue = calculateExpectedValue()
            if let ev = expectedValue {
                HStack(spacing: 8) {
                    // EV icon
                    ZStack {
                        Circle()
                            .fill(ev >= 0 ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ev >= 0 ? .green : .red)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Expected Value")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        
                        Text(String(format: "%@%.1f%%", ev >= 0 ? "+" : "", ev))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(ev >= 0 ? .green : .red)
                    }
                    
                    Spacer()
                    
                    Text("weighted avg")
                        .font(.system(size: 9))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(isDark ? 0.05 : 0.08))
                        )
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill((ev >= 0 ? Color.green : Color.red).opacity(isDark ? 0.06 : 0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke((ev >= 0 ? Color.green : Color.red).opacity(0.15), lineWidth: 0.5)
                )
            }
            
            // Explanation note - more compact
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                Text("Probabilities show estimated chance of reaching each threshold based on current conditions")
                    .font(.system(size: 9))
            }
            .foregroundColor(DS.Adaptive.textTertiary.opacity(0.8))
            .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isDark ? 0.03 : 0.05))
        )
    }
    
    /// Calculate expected value from probability distribution
    private func calculateExpectedValue() -> Double? {
        var weightedSum: Double = 0
        var totalWeight: Double = 0
        
        // Upside contributions (positive)
        if let p2 = prediction.probabilityUp2Pct {
            weightedSum += (p2 / 100) * 2.0
            totalWeight += p2 / 100
        }
        if let p5 = prediction.probabilityUp5Pct {
            weightedSum += (p5 / 100) * 5.0
            totalWeight += p5 / 100
        }
        if let p10 = prediction.probabilityUp10Pct {
            weightedSum += (p10 / 100) * 10.0
            totalWeight += p10 / 100
        }
        
        // Downside contributions (negative)
        if let p2 = prediction.probabilityDown2Pct {
            weightedSum -= (p2 / 100) * 2.0
            totalWeight += p2 / 100
        }
        if let p5 = prediction.probabilityDown5Pct {
            weightedSum -= (p5 / 100) * 5.0
            totalWeight += p5 / 100
        }
        if let p10 = prediction.probabilityDown10Pct {
            weightedSum -= (p10 / 100) * 10.0
            totalWeight += p10 / 100
        }
        
        // Return nil if no probability data available
        guard totalWeight > 0 else { return nil }
        
        return weightedSum
    }
    
    // MARK: - AI Model Credentials Badge + Info Sheet
    
    /// Professional badge showing CryptoSage AI branding for predictions,
    /// with a tappable info button that reveals the technology and benchmark data.
    private var aiModelCredentialsBadge: some View {
        HStack(spacing: 8) {
            // AI chip icon
            Image(systemName: "cpu.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BrandColors.goldBase)
            
            Text("Powered by DeepSeek V3")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Text("#1 Crypto AI")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(BrandColors.goldBase)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(BrandColors.goldBase.opacity(0.12))
                )
            
            Spacer()
            
            // Verifiable-claim info button
            Button {
                showAICredentialsSheet = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BrandColors.goldBase.opacity(isDark ? 0.06 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BrandColors.goldBase.opacity(0.15), lineWidth: 0.5)
        )
        .sheet(isPresented: $showAICredentialsSheet) {
            aiCredentialsSheet
        }
    }
    
    /// Sheet view explaining the prediction engine technology and benchmark data.
    private var aiCredentialsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Brief intro (hero section removed – redundant with navigation title)
                    Text("Our prediction engine uses a specialized AI model selected for its proven track record in crypto market analysis. CryptoSage combines this model with 10+ real-time data sources to generate forecasts across all timeframes.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    
                    Divider()
                    
                    // Why this model
                    Text("Why DeepSeek V3")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    credentialCard(
                        icon: "trophy.fill",
                        iconColor: .yellow,
                        title: "#1 in Crypto Trading Benchmark",
                        detail: "+116.53% return — ranked first out of 20+ AI models in a standardized crypto trading simulation on Hyperliquid DEX.",
                        source: "Source: Alpha Arena Leaderboard (public benchmark)"
                    )
                    
                    credentialCard(
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: .green,
                        title: "Top-Tier Analytical Reasoning",
                        detail: "Scored in the top tier for mathematical and analytical reasoning — critical for interpreting technical indicators and market patterns.",
                        source: "Source: LiveBench.ai (independent AI evaluation)"
                    )
                    
                    credentialCard(
                        icon: "doc.text.magnifyingglass",
                        iconColor: .purple,
                        title: "128K Context Window",
                        detail: "Analyzes up to 128,000 tokens per request — enough to process weeks of market data, multiple indicators, and derivatives data simultaneously.",
                        source: "Source: DeepSeek model documentation"
                    )
                    
                    Divider()
                    
                    // What goes into each prediction
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What Goes Into Each Prediction")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        bulletPoint("Technical indicators: RSI, MACD, Bollinger Bands, ADX & more")
                        bulletPoint("On-chain data: whale movements & smart money flows")
                        bulletPoint("Derivatives: funding rates, open interest & trader positioning")
                        bulletPoint("Sentiment: Fear & Greed Index, social trends & news impact")
                        bulletPoint("Multi-timeframe analysis from 1 hour to 30 days")
                    }
                    
                    // Verify note
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                        
                        Text("All benchmark claims reference publicly available data. Verify independently at Alpha Arena or LiveBench.ai.")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.green.opacity(isDark ? 0.08 : 0.05))
                    )
                }
                .padding(20)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Prediction Technology")
            .navigationBarTitleDisplayMode(.inline)
            // LIGHT MODE FIX: Ensure navigation bar uses the correct adaptive background
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAICredentialsSheet = false
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            // LIGHT MODE FIX: Use adaptive gold
                            .foregroundStyle(DS.Adaptive.gold)
                    }
                }
            }
        }
    }
    
    /// A styled card for displaying a verifiable credential.
    @ViewBuilder
    private func credentialCard(icon: String, iconColor: Color, title: String, detail: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
                
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            Text(detail)
                .font(.system(size: 13))
                .foregroundColor(DS.Adaptive.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(source)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
                .italic()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isDark ? 0.04 : 0.06))
        )
    }
    
    /// Simple bullet point row for the credentials sheet.
    @ViewBuilder
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(BrandColors.goldBase)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(DS.Adaptive.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - AI Methodology Section (Collapsible)
    
    private var aiMethodologySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // "CryptoSage AI" badge with verifiable-claim info button
            aiModelCredentialsBadge
            
            // Collapsible "How This Works" section
            howItWorksCollapsible
        }
    }
    
    private var howItWorksCollapsible: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tappable header with expand/collapse
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showMethodology.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text("How This Works")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Spacer()
                    
                    // Expand/collapse chevron with smooth rotation
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .rotationEffect(.degrees(showMethodology ? 180 : 0))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showMethodology)
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            
            // Collapsible content with smooth height animation
            if showMethodology {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .background(DS.Adaptive.stroke.opacity(0.3))
                        .padding(.horizontal, 14)
                    
                    // Methodology items - comprehensive list
                    VStack(spacing: 8) {
                        methodologyRow(
                            icon: "chart.xyaxis.line",
                            title: "Technical Analysis",
                            description: "RSI, MACD, Stochastic RSI, ADX, Bollinger Bands, moving averages, and key support/resistance levels"
                        )
                        
                        methodologyRow(
                            icon: "building.columns",
                            title: "Smart Money Tracking",
                            description: "Whale wallet movements, exchange net flows, and institutional accumulation/distribution patterns"
                        )
                        
                        methodologyRow(
                            icon: "gauge.with.needle",
                            title: "Market Sentiment",
                            description: "Fear & Greed Index as contrarian signal, BTC dominance impact on altcoins, and volume analysis"
                        )
                        
                        methodologyRow(
                            icon: "clock.arrow.2.circlepath",
                            title: "Multi-Timeframe Confluence",
                            description: "Validates signals across multiple timeframes - predictions are stronger when trends align"
                        )
                        
                        methodologyRow(
                            icon: "waveform.path.ecg",
                            title: "Market Regime Detection",
                            description: "Identifies if market is trending, ranging, or volatile to adjust indicator interpretation"
                        )
                        
                        methodologyRow(
                            icon: "chart.bar.doc.horizontal",
                            title: "Derivatives Data",
                            description: "Funding rates (crowd sentiment) and open interest (trend strength) from futures markets"
                        )
                        
                        methodologyRow(
                            icon: "person.2.fill",
                            title: "Trader Positioning",
                            description: "Global long/short ratios (contrarian), top trader positions (smart money), and taker flow (momentum)"
                        )
                        
                        methodologyRow(
                            icon: "brain.head.profile",
                            title: "AI Synthesis",
                            description: "CryptoSage AI weighs all 10+ data sources based on timeframe relevance and historical accuracy using the #1 ranked model for crypto analysis"
                        )
                    }
                    .padding(.horizontal, 14)
                    
                    // Data sources note
                    VStack(alignment: .leading, spacing: 6) {
                        Divider()
                            .background(DS.Adaptive.stroke)
                            .padding(.vertical, 4)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(BrandColors.goldBase)
                            
                            Text("Real-Time Data Sources")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                        
                        Text("Live data from CoinGecko, Binance Futures API, and on-chain analytics. Derivatives data available for major coins (BTC, ETH, SOL, etc).")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    
                    // Learning system explanation
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(BrandColors.goldBase)
                            
                            Text("Adaptive Learning")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                        
                        Text("Every prediction is tracked and evaluated after expiration. Both your personal accuracy history and global accuracy data from all CryptoSage users help the AI calibrate confidence levels and improve over time.")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    
                    // Global learning explanation
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "globe.americas.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.blue)
                            
                            Text("Global Accuracy Tracking")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                        
                        Text("Prediction outcomes are aggregated across all users to build a shared knowledge base. The AI uses this data to identify which timeframes, directions, and market conditions produce more reliable predictions.")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    
                    // Confidence explanation
                    HStack(spacing: 6) {
                        Circle()
                            .fill(prediction.confidence.color)
                            .frame(width: 6, height: 6)
                        
                        Text("\(prediction.confidence.displayName) confidence = \(confidenceExplanation)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                    removal: .opacity
                ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isDark ? 0.03 : 0.05))
        )
        .clipped() // Prevents content from overflowing during animation
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showMethodology)
    }
    
    /// Dynamic explanation of what the confidence score means
    private var confidenceExplanation: String {
        switch prediction.confidence {
        case .high:
            return "strong signal alignment across indicators"
        case .medium:
            return "moderate agreement with some mixed signals"
        case .low:
            return "conflicting indicators, higher uncertainty"
        }
    }
    
    @ViewBuilder
    private func communityStatPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.purple.opacity(0.7))
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(DS.Adaptive.chipBackground)
        )
    }
    
    @ViewBuilder
    private func methodologyRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
    }
    
    // Keep old method for compatibility but won't be used
    @ViewBuilder
    private func methodologyCard(icon: String, title: String, description: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon with gradient background
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(isDark ? 0.2 : 0.15), color.opacity(isDark ? 0.08 : 0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(isDark ? 0.12 : 0.08), lineWidth: 0.5)
        )
    }
    
    // MARK: - Disclaimer Section
    
    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main disclaimer
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Important Disclaimer")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.orange)
                    
                    Text(AIPricePrediction.disclaimer)
                        .font(.system(size: 11))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Divider()
                .background(Color.orange.opacity(0.2))
            
            // Additional legal warnings
            VStack(alignment: .leading, spacing: 8) {
                disclaimerBullet(text: "Past performance does not guarantee future results. Historical accuracy rates are not reliable indicators of future predictions.")
                
                disclaimerBullet(text: "AI predictions are probabilistic estimates based on technical analysis and may be completely wrong.")
                
                disclaimerBullet(text: "CryptoSage is not a registered investment adviser. This is not personalized financial advice.")
                
                disclaimerBullet(text: "Only invest what you can afford to lose. Cryptocurrency markets are highly volatile.")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(isDark ? 0.08 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
    
    /// Helper for disclaimer bullet points
    private func disclaimerBullet(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 10))
                .foregroundColor(.orange.opacity(0.7))
            
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(DS.Adaptive.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Helpers
    
    private var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: prediction.generatedAt, relativeTo: Date())
    }
    
    private func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.maximumFractionDigits = value < 1 ? 6 : (value < 100 ? 4 : 2)
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    /// Better icons for direction that are more intuitive than simple arrows
    private var directionIcon: String {
        switch prediction.direction {
        case .bullish:
            return "chart.line.uptrend.xyaxis"
        case .bearish:
            return "chart.line.downtrend.xyaxis"
        case .neutral:
            return "chart.line.flattrend.xyaxis"
        }
    }
    
    /// Icon for signal badges
    private func signalIcon(for signal: String) -> String {
        switch signal.lowercased() {
        case "bullish":
            return "arrow.up.right.circle.fill"
        case "bearish":
            return "arrow.down.right.circle.fill"
        default:
            return "minus.circle.fill"
        }
    }
}

// MARK: - Direction Indicator View

struct DirectionIndicatorView: View {
    let direction: PredictionDirection
    
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 6) {
            // Enhanced icon with layered design
            ZStack {
                // Outer glow ring
                Circle()
                    .stroke(direction.color.opacity(0.2), lineWidth: 2)
                    .frame(width: 52, height: 52)
                
                // Background circle with gradient
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [direction.color.opacity(0.25), direction.color.opacity(0.05)],
                            center: .center,
                            startRadius: 5,
                            endRadius: 25
                        )
                    )
                    .frame(width: 48, height: 48)
                
                // Inner circle
                Circle()
                    .fill(direction.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                // Direction icon
                Group {
                    switch direction {
                    case .bullish:
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 18, weight: .bold))
                            .offset(y: isAnimating ? -2 : 0)
                    case .bearish:
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 18, weight: .bold))
                            .offset(y: isAnimating ? 2 : 0)
                    case .neutral:
                        Image(systemName: "minus")
                            .font(.system(size: 18, weight: .bold))
                    }
                }
                .foregroundColor(direction.color)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            }
            
            Text(direction.displayName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(direction.color)
            
            Text("Direction")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Confidence Level View

struct ConfidenceLevelView: View {
    let confidence: PredictionConfidence
    let score: Int
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 6) {
            // Visual confidence indicator
            ZStack {
                // Background bars - LIGHT MODE FIX: Adaptive inactive bar color
                HStack(spacing: 3) {
                    // PERFORMANCE FIX: Added explicit id to prevent SwiftUI warnings
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index < confidenceLevel ? confidence.color : (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)))
                            .frame(width: 10, height: CGFloat(12 + index * 6))
                    }
                }
            }
            .frame(height: 30)
            
            Text(confidence.displayName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(confidence.color)
            
            Text("Confidence")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            // Score badge
            Text("\(score)/100")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(DS.Adaptive.chipBackground)
                )
        }
    }
    
    private var confidenceLevel: Int {
        switch confidence {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }
}

// MARK: - Compact Confidence Gauge

struct CompactConfidenceGauge: View {
    let score: Int
    let confidence: PredictionConfidence
    let direction: PredictionDirection
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    @State private var animatedProgress: Double = 0
    
    private var progress: Double {
        Double(min(100, max(0, score))) / 100.0
    }
    
    private let size: CGFloat = 72
    private let strokeWidth: CGFloat = 7
    
    var body: some View {
        ZStack {
            // Background track - LIGHT MODE FIX: Adaptive stroke
            Circle()
                .stroke(
                    isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05),
                    lineWidth: strokeWidth
                )
            
            // Progress arc with gradient
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [
                            direction.color.opacity(0.15),
                            direction.color.opacity(0.4),
                            direction.color,
                            direction.color
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            
            // Inner content - LIGHT MODE FIX: Adaptive text
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("/ 100")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                withAnimation(GaugeMotionProfile.fill) {
                    animatedProgress = progress
                }
            }
        }
        .onChange(of: score) { _, newScore in
            let newProgress = GaugeMotionProfile.clampUnit(Double(newScore) / 100.0)
            withAnimation(GaugeMotionProfile.fill) {
                animatedProgress = newProgress
            }
        }
    }
}

// MARK: - Signal Segment View

struct SignalSegment: View {
    let count: Int
    let total: Int
    let color: Color
    let icon: String
    let width: CGFloat
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        if count > 0 {
            ZStack {
                // Gradient background
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.8), color.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        // Inner highlight
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.white.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 1
                            )
                    )
                
                // Icon inside if segment is wide enough
                if width > 30 {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .frame(width: max(width, 8), height: 32)
        }
    }
}

// MARK: - Enhanced Confidence Gauge (Larger)

struct EnhancedConfidenceGauge: View {
    let score: Int
    let confidence: PredictionConfidence
    let direction: PredictionDirection
    
    @State private var animatedProgress: Double = 0
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    private var progress: Double {
        Double(min(100, max(0, score))) / 100.0
    }
    
    private let size: CGFloat = 100
    private let strokeWidth: CGFloat = 10
    
    var body: some View {
        ZStack {
            // Background track - LIGHT MODE FIX: Adaptive stroke
            Circle()
                .stroke(
                    isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                    lineWidth: strokeWidth
                )
            
            // Progress arc with gradient
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [
                            direction.color.opacity(0.2),
                            direction.color.opacity(0.5),
                            direction.color,
                            direction.color
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            
            // Inner content - LIGHT MODE FIX: Adaptive text
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("/ 100")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                withAnimation(GaugeMotionProfile.fill) {
                    animatedProgress = progress
                }
            }
        }
        .onChange(of: score) { _, newScore in
            let newProgress = GaugeMotionProfile.clampUnit(Double(newScore) / 100.0)
            withAnimation(GaugeMotionProfile.fill) {
                animatedProgress = newProgress
            }
        }
    }
}

// MARK: - Enhanced Direction Badge

struct EnhancedDirectionBadge: View {
    let direction: PredictionDirection
    
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(direction.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Group {
                    switch direction {
                    case .bullish:
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 16, weight: .bold))
                            .offset(y: isAnimating ? -2 : 0)
                    case .bearish:
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 16, weight: .bold))
                            .offset(y: isAnimating ? 2 : 0)
                    case .neutral:
                        Image(systemName: "minus")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .foregroundColor(direction.color)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(direction.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(direction.color)
                
                Text("Direction")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Enhanced Confidence Badge

struct EnhancedConfidenceBadge: View {
    let confidence: PredictionConfidence
    let score: Int
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 8) {
            // Visual bars - LIGHT MODE FIX: Adaptive inactive bar color
            HStack(spacing: 3) {
                // PERFORMANCE FIX: Added explicit id to prevent SwiftUI warnings
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < confidenceLevel ? confidence.color : (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)))
                        .frame(width: 8, height: CGFloat(14 + index * 6))
                }
            }
            .frame(height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(confidence.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(confidence.color)
                
                Text("\(score)/100")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
    }
    
    private var confidenceLevel: Int {
        switch confidence {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }
}

// MARK: - Enhanced Trading Level Row

struct EnhancedTradingLevelRow: View {
    let icon: String
    let label: String
    let value: String
    var subValue: String?
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 0) {
            // Colored left border
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)
            
            HStack(spacing: 10) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 22)
                
                // Label
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(1)
                
                Spacer(minLength: 8)
                
                // Value section
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    if let sub = subValue {
                        Text(sub)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(color)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.chipBackground.opacity(isDark ? 0.4 : 0.6))
        )
    }
}

// MARK: - Enhanced Driver Row

struct EnhancedDriverRow: View {
    let driver: PredictionDriver
    let isAlternate: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 10) {
            // Enhanced signal indicator
            ZStack {
                Circle()
                    .fill(driver.signalColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                
                Image(systemName: signalIcon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(driver.signalColor)
            }
            
            // Name and value
            VStack(alignment: .leading, spacing: 2) {
                Text(driver.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                Text(driver.value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(driver.signalColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            
            Spacer(minLength: 4)
            
            // Enhanced signal badge
            HStack(spacing: 3) {
                Image(systemName: signalSmallIcon)
                    .font(.system(size: 8, weight: .bold))
                Text(driver.signal.capitalized)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [driver.signalColor, driver.signalColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isAlternate ? DS.Adaptive.chipBackground.opacity(isDark ? 0.3 : 0.5) : DS.Adaptive.chipBackground.opacity(isDark ? 0.15 : 0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(driver.signalColor.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    private var signalIcon: String {
        switch driver.signal.lowercased() {
        case "bullish": return "arrowtriangle.up.fill"
        case "bearish": return "arrowtriangle.down.fill"
        default: return "minus"
        }
    }
    
    private var signalSmallIcon: String {
        switch driver.signal.lowercased() {
        case "bullish": return "arrow.up"
        case "bearish": return "arrow.down"
        default: return "minus"
        }
    }
}

// MARK: - Enhanced Signal Segment

struct EnhancedSignalSegment: View {
    let count: Int
    let total: Int
    let color: Color
    let icon: String
    let width: CGFloat
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        if count > 0 {
            ZStack {
                // Main background with glass effect
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner shine
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .padding(1)
                
                // Icon and count
                if width > 50 {
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .bold))
                        Text("\(count)")
                            .font(.system(size: 16, weight: .bold).monospacedDigit())
                    }
                    .foregroundColor(.white)
                } else if width > 28 {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: max(width, 16), height: 50)
        }
    }
}

// MARK: - Enhanced Signal Legend

struct EnhancedSignalLegend: View {
    let icon: String
    let color: Color
    let label: String
    let count: Int
    
    var body: some View {
        VStack(spacing: 6) {
            // Colored icon circle
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 32, height: 32)
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
            }
            
            // Count and label
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .textCase(.none)
            }
        }
    }
}

// MARK: - Modern Signal Pill (Clean Compact Design)

struct ModernSignalPill: View {
    let count: Int
    let label: String
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 5) {
            // Count badge
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(color.opacity(isDark ? 0.2 : 0.15))
                )
            
            // Label
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(isDark ? 0.1 : 0.08))
        )
    }
}

// MARK: - Animated Signal Pill (With micro-animations)

struct AnimatedSignalPill: View {
    let count: Int
    let label: String
    let color: Color
    let delay: Double
    let animate: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isVisible: Bool = false
    @State private var pulseScale: CGFloat = 1.0
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 6) {
            // Animated count badge with scale effect
            ZStack {
                // Pulse ring
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .scaleEffect(pulseScale)
                    .opacity(2 - pulseScale)
                
                // Count circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(color)
            }
            .scaleEffect(isVisible ? 1.0 : 0.5)
            .opacity(isVisible ? 1.0 : 0.0)
            
            // Label
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
                .opacity(isVisible ? 1.0 : 0.0)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                // Gradient fill
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                color.opacity(isDark ? 0.15 : 0.10),
                                color.opacity(isDark ? 0.08 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Inner highlight for 3D effect
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.06 : 0.15),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 0.8)
        )
        .scaleEffect(isVisible ? 1.0 : 0.9)
        .onChange(of: animate) { _, newValue in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if newValue {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay)) {
                        isVisible = true
                    }
                    // Start pulse animation after appearing
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(delay + 0.5)) {
                        pulseScale = 1.3
                    }
                }
            }
        }
        .onAppear {
            if animate {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay)) {
                    isVisible = true
                }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(delay + 0.5)) {
                    pulseScale = 1.3
                }
            }
        }
    }
}

// MARK: - Compact Driver Cell (Grid Layout)

struct CompactDriverCell: View {
    let driver: PredictionDriver
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 8) {
            // Signal indicator dot
            Circle()
                .fill(driver.signalColor)
                .frame(width: 8, height: 8)
            
            // Name and value stacked
            VStack(alignment: .leading, spacing: 2) {
                Text(driver.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                Text(driver.value)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(driver.signalColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(driver.signalColor.opacity(isDark ? 0.1 : 0.08))
        )
    }
}

// MARK: - Enhanced 3D Driver Card (Premium Key Driver Display)

struct Enhanced3DDriverCard: View {
    let driver: PredictionDriver
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var animateRing: Bool = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Weight as percentage for ring display
    private var weightPercent: CGFloat {
        CGFloat(driver.weight * 100)
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Circular weight indicator with animation
            ZStack {
                // Background ring
                Circle()
                    .stroke(
                        driver.signalColor.opacity(0.2),
                        lineWidth: 3
                    )
                    .frame(width: 32, height: 32)
                
                // Animated progress ring
                Circle()
                    .trim(from: 0, to: animateRing ? CGFloat(driver.weight) : 0)
                    .stroke(
                        LinearGradient(
                            colors: [driver.signalColor, driver.signalColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))
                
                // Center icon/indicator
                Circle()
                    .fill(driver.signalColor.opacity(0.15))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: signalIcon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(driver.signalColor)
                    )
            }
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(driver.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                Text(driver.value)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(driver.signalColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            // 3D card effect with layered gradients
            ZStack {
                // Base layer with direction-aware gradient
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                driver.signalColor.opacity(isDark ? 0.15 : 0.10),
                                driver.signalColor.opacity(isDark ? 0.08 : 0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Highlight layer for 3D depth
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.08 : 0.3),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            // Border with glow
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            driver.signalColor.opacity(0.4),
                            driver.signalColor.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                animateRing = true
            }
        }
    }
    
    private var signalIcon: String {
        switch driver.signal.lowercased() {
        case "bullish", "buy":
            return "arrow.up"
        case "bearish", "sell":
            return "arrow.down"
        default:
            return "minus"
        }
    }
}

// MARK: - Compact Trading Level

struct CompactTradingLevel: View {
    let label: String
    let value: String
    var subValue: String? = nil
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 0) {
            // Color indicator bar
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3)
            
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    if let sub = subValue {
                        Text(sub)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(color)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(isDark ? 0.1 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(isDark ? 0.15 : 0.10), lineWidth: 0.5)
        )
    }
}

// MARK: - Smart Prediction Time Label

/// Formats a prediction's generation time into a smart, context-aware label.
/// Shows "Now" for the first 5 minutes, then switches to relative time ("2h ago", "Yesterday", etc.)
/// Designed for compact chart labels — keeps strings short.
private func predictionTimeLabel(for generatedAt: Date?) -> String {
    guard let generatedAt = generatedAt else { return "Now" }
    
    let elapsed = Date().timeIntervalSince(generatedAt)
    
    // Under 5 minutes → still "Now"
    if elapsed < 300 { return "Now" }
    
    // Under 1 hour → minutes ago
    if elapsed < 3600 {
        let mins = Int(elapsed / 60)
        return "\(mins)m ago"
    }
    
    // Under 24 hours → hours ago
    if elapsed < 86400 {
        let hours = Int(elapsed / 3600)
        return hours == 1 ? "1h ago" : "\(hours)h ago"
    }
    
    // Under 7 days → days ago
    if elapsed < 604800 {
        let days = Int(elapsed / 86400)
        return days == 1 ? "Yesterday" : "\(days)d ago"
    }
    
    // Older → short date
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM d"
    return fmt.string(from: generatedAt)
}

// MARK: - Visual Price Ladder (Premium Trading Levels Display)

/// A visual representation of trading levels showing Entry, Stop Loss, and Take Profit
/// relative to the current price on a vertical ladder
struct VisualPriceLadder: View {
    let currentPrice: Double
    let entryZoneLow: Double
    let entryZoneHigh: Double
    let stopLoss: Double
    let takeProfit: Double
    let direction: PredictionDirection
    let riskRewardRatio: Double
    let methodology: String
    
    // Multi-TP support for scale-out positions
    var takeProfit1: Double? = nil  // TP1 - 33% of move
    var takeProfit2: Double? = nil  // TP2 - 66% of move
    var tp1Percent: Double? = nil
    var tp2Percent: Double? = nil
    var tp3Percent: Double? = nil   // Full target percent
    var stopLossPercent: Double? = nil
    
    /// When the prediction was generated (nil shows "Now" as fallback)
    var generatedAt: Date? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var animateLadder: Bool = false
    @State private var pulseNow: Bool = false
    
    /// Timer-driven refresh so the label updates live (e.g. "4m ago" → "5m ago")
    @State private var timeLabelTick: UUID = UUID()
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Smart time label: "Now" for first 5 min, then relative time
    private var timeLabel: String {
        _ = timeLabelTick // Subscribe to timer updates
        return predictionTimeLabel(for: generatedAt)
    }
    
    // Colors for levels
    private var entryColor: Color { .blue }
    private var stopColor: Color { .red }
    private var targetColor: Color { .green }
    // Adaptive "Now" color - white on dark backgrounds, dark charcoal on light backgrounds
    private var currentColor: Color { isDark ? Color.white : Color(red: 0.25, green: 0.25, blue: 0.28) }
    
    // Minimum vertical separation between labels (in points)
    private let minLabelSeparation: CGFloat = 32
    
    // Calculate the price range for scaling with more padding
    private var priceRange: (min: Double, max: Double, range: Double) {
        var allPrices = [currentPrice, entryZoneLow, entryZoneHigh, stopLoss, takeProfit]
        // Include TP levels if available
        if let tp1 = takeProfit1 { allPrices.append(tp1) }
        if let tp2 = takeProfit2 { allPrices.append(tp2) }
        
        let rawMin = allPrices.min() ?? stopLoss
        let rawMax = allPrices.max() ?? takeProfit
        let rawRange = rawMax - rawMin
        // Add 15% padding for better label spacing
        let padding = rawRange * 0.15
        let minPrice = rawMin - padding
        let maxPrice = rawMax + padding
        let range = max(maxPrice - minPrice, currentPrice * 0.01)
        return (minPrice, maxPrice, range)
    }
    
    // Check if price is within entry zone
    private var isInEntryZone: Bool {
        currentPrice >= entryZoneLow && currentPrice <= entryZoneHigh
    }
    
    // Calculate distance from current price to each level
    private func distancePercent(to price: Double) -> Double {
        guard currentPrice > 0 else { return 0 }
        return ((price - currentPrice) / currentPrice) * 100
    }
    
    // Convert price to Y position (0 = top, 1 = bottom)
    // Higher prices at top, lower at bottom
    private func yPosition(for price: Double) -> CGFloat {
        let (minPrice, maxPrice, _) = priceRange
        return 1 - CGFloat((price - minPrice) / (maxPrice - minPrice))
    }
    
    /// Calculate a safe Y position for the "Now" label that avoids overlapping with other right-side markers
    /// - Parameters:
    ///   - nowY: The natural Y position for the current price marker
    ///   - slY: Stop Loss Y position (on right side)
    ///   - tpY: Take Profit Y position (on right side)
    ///   - height: Total height of the ladder view
    /// - Returns: Adjusted Y position that avoids overlaps, plus offset direction (-1 up, 0 none, 1 down)
    private func safeNowLabelPosition(nowY: CGFloat, slY: CGFloat, tpY: CGFloat, height: CGFloat) -> (y: CGFloat, offset: Int) {
        let separation = minLabelSeparation
        
        // Check if NOW overlaps with Stop Loss (both on right side)
        let distanceToSL = abs(nowY - slY)
        let distanceToTP = abs(nowY - tpY)
        
        // If no overlap issues, return original position
        if distanceToSL >= separation && distanceToTP >= separation {
            return (nowY, 0)
        }
        
        // Determine which marker is causing the overlap
        let slOverlap = distanceToSL < separation
        let tpOverlap = distanceToTP < separation
        
        // Calculate how much to offset
        var adjustedY = nowY
        var offsetDirection: Int = 0
        
        if slOverlap && !tpOverlap {
            // Only overlapping with Stop Loss
            // Move NOW away from SL (up if NOW is below SL, down if above)
            if nowY > slY {
                // NOW is below SL - move down
                adjustedY = slY + separation
                offsetDirection = 1
            } else {
                // NOW is above SL - move up
                adjustedY = slY - separation
                offsetDirection = -1
            }
        } else if tpOverlap && !slOverlap {
            // Only overlapping with Take Profit
            if nowY > tpY {
                adjustedY = tpY + separation
                offsetDirection = 1
            } else {
                adjustedY = tpY - separation
                offsetDirection = -1
            }
        } else if slOverlap && tpOverlap {
            // Overlapping with both - find the best position between them or outside
            let midPoint = (slY + tpY) / 2
            if abs(nowY - midPoint) < separation {
                // Try moving to the side with more space
                let spaceAboveTP = tpY
                let spaceBelowSL = height - slY
                
                if spaceAboveTP > spaceBelowSL && tpY > separation {
                    adjustedY = tpY - separation
                    offsetDirection = -1
                } else if slY < height - separation {
                    adjustedY = slY + separation
                    offsetDirection = 1
                }
            }
        }
        
        // Clamp to valid range with padding
        let padding: CGFloat = 15
        adjustedY = max(padding, min(height - padding, adjustedY))
        
        return (adjustedY, offsetDirection)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Header with direction, explanation, and R:R badge — premium styling
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // Direction badge with glow dot
                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(direction.color.opacity(0.30))
                                .frame(width: 14, height: 14)
                            Circle()
                                .fill(direction.color)
                                .frame(width: 7, height: 7)
                        }
                        
                        Text(direction == .bullish ? "Consider Long" : (direction == .bearish ? "Consider Short" : "Range Trade"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(direction.color)
                    }
                    
                    Spacer()
                    
                    // Risk:Reward Badge — glass capsule
                    let rrColor: Color = riskRewardRatio >= 2 ? .green : (riskRewardRatio >= 1.5 ? .yellow : .orange)
                    HStack(spacing: 4) {
                        Text("R:R")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Text(String(format: "1:%.1f", riskRewardRatio))
                            .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundColor(rrColor)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(
                        Capsule()
                            .fill(rrColor.opacity(isDark ? 0.12 : 0.08))
                            .overlay(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(isDark ? 0.04 : 0.10), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            )
                    )
                    .overlay(
                        Capsule()
                            .stroke(rrColor.opacity(0.20), lineWidth: 0.5)
                    )
                }
                
                // Direction explanation
                Text(direction == .bullish
                    ? "Buy at entry zone, stop below, target above"
                    : (direction == .bearish
                        ? "Sell at entry zone, stop above, target below"
                        : "Trade within range, stop outside, target opposite side"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            // Visual Price Ladder - simplified clean design
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let ladderX = width / 2
                
                // Calculate Y positions for key levels only
                let tpY = yPosition(for: takeProfit) * height
                let entryCenter = (entryZoneLow + entryZoneHigh) / 2
                let entryY = yPosition(for: entryCenter) * height
                let currentY = yPosition(for: currentPrice) * height
                let slY = yPosition(for: stopLoss) * height
                
                ZStack {
                    // ── Price scale labels (left side) — tech-styled ──
                    Text(formatPriceCompact(priceRange.min))
                        .font(.system(size: 8, weight: .bold, design: .rounded).monospacedDigit())
                        .tracking(0.3)
                        .foregroundColor(DS.Adaptive.textTertiary.opacity(0.5))
                        .position(x: 28, y: height - 10)
                    
                    Text(formatPriceCompact(priceRange.max))
                        .font(.system(size: 8, weight: .bold, design: .rounded).monospacedDigit())
                        .tracking(0.3)
                        .foregroundColor(DS.Adaptive.textTertiary.opacity(0.5))
                        .position(x: 28, y: 10)
                    
                    // ── LADDER BACKBONE: Multi-layer neon spine ──
                    // Layer 1: Wide ambient glow
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: targetColor.opacity(0.20), location: 0.0),
                                    .init(color: Color.white.opacity(0.03), location: 0.45),
                                    .init(color: Color.white.opacity(0.03), location: 0.55),
                                    .init(color: stopColor.opacity(0.20), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 10)
                        .position(x: ladderX, y: height / 2)
                    
                    // Layer 2: Bright core line
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: targetColor.opacity(0.65), location: 0.0),
                                    .init(color: Color.white.opacity(isDark ? 0.12 : 0.08), location: 0.40),
                                    .init(color: Color.white.opacity(isDark ? 0.12 : 0.08), location: 0.60),
                                    .init(color: stopColor.opacity(0.65), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3)
                        .position(x: ladderX, y: height / 2)
                    
                    // Layer 3: Fine white center highlight
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.white.opacity(isDark ? 0.08 : 0.04))
                        .frame(width: 1)
                        .position(x: ladderX, y: height / 2)
                    
                    // ── ENTRY ZONE: Glowing band on the ladder ──
                    let entryTopY = yPosition(for: entryZoneHigh) * height
                    let entryBottomY = yPosition(for: entryZoneLow) * height
                    let entryHeight = max(entryBottomY - entryTopY, 4)
                    
                    if entryHeight > 6 {
                        // Outer glow
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(entryColor.opacity(isInEntryZone ? 0.35 : 0.10))
                            .frame(width: isInEntryZone ? 14 : 10, height: entryHeight + 4)
                            .position(x: ladderX, y: entryTopY + entryHeight / 2)
                        
                        // Core band
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(entryColor.opacity(isInEntryZone ? 0.50 : 0.15))
                            .frame(width: isInEntryZone ? 8 : 6, height: entryHeight)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .stroke(entryColor.opacity(isInEntryZone ? 0.6 : 0.25), lineWidth: 0.5)
                            )
                            .position(x: ladderX, y: entryTopY + entryHeight / 2)
                            .animation(.easeInOut(duration: 0.3), value: isInEntryZone)
                    }
                    
                    // Take Profit marker (RIGHT side) - diamond shape
                    simpleLevelMarker(
                        price: takeProfit,
                        label: "Take Profit",
                        color: targetColor,
                        icon: "flag.fill",
                        yPos: tpY,
                        width: width,
                        ladderX: ladderX,
                        onRight: true,
                        markerShape: .diamond
                    )
                    
                    // FIX v28: Add TP1/TP2 tick marks on the ladder so users can see
                    // where intermediate scale-out targets sit on the price scale.
                    if let tp1 = takeProfit1 {
                        let tp1Y = yPosition(for: tp1) * height
                        // Small tick mark on the ladder spine
                        Path { path in
                            path.move(to: CGPoint(x: ladderX - 6, y: tp1Y))
                            path.addLine(to: CGPoint(x: ladderX + 6, y: tp1Y))
                        }
                        .stroke(targetColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        
                        // Subtle label
                        Text("TP1")
                            .font(.system(size: 6, weight: .bold, design: .rounded))
                            .foregroundColor(targetColor.opacity(0.6))
                            .position(x: ladderX + 18, y: tp1Y)
                    }
                    
                    if let tp2 = takeProfit2 {
                        let tp2Y = yPosition(for: tp2) * height
                        // Small tick mark on the ladder spine
                        Path { path in
                            path.move(to: CGPoint(x: ladderX - 6, y: tp2Y))
                            path.addLine(to: CGPoint(x: ladderX + 6, y: tp2Y))
                        }
                        .stroke(targetColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        
                        // Subtle label
                        Text("TP2")
                            .font(.system(size: 6, weight: .bold, design: .rounded))
                            .foregroundColor(targetColor.opacity(0.6))
                            .position(x: ladderX + 18, y: tp2Y)
                    }
                    
                    // Entry Zone marker (LEFT side) - rectangular zone shape
                    // When price is in the zone, highlight it green with a checkmark
                    // but keep the label readable ("Buy Zone" / "Sell Zone" / "Entry Zone")
                    let entryLabel: String = {
                        if direction == .bullish {
                            return isInEntryZone ? "Buy Zone ✓" : "Buy Zone"
                        } else if direction == .bearish {
                            return isInEntryZone ? "Sell Zone ✓" : "Sell Zone"
                        }
                        return isInEntryZone ? "Entry ✓" : "Entry Zone"
                    }()
                    simpleLevelMarker(
                        price: entryCenter,
                        label: entryLabel,
                        color: entryColor,
                        icon: isInEntryZone ? "checkmark.circle.fill" : "location.fill",
                        yPos: entryY,
                        width: width,
                        ladderX: ladderX,
                        onRight: false,
                        markerShape: .zone
                    )
                    
                    // ── NOW MARKER: Premium beacon with radial glow + smart time label ──
                    let safeLabelPos = safeNowLabelPosition(nowY: currentY, slY: slY, tpY: tpY, height: height)
                    let nowLabelY = safeLabelPos.y
                    let isLabelOffset = safeLabelPos.offset != 0
                    
                    // Animated pulse ring
                    Circle()
                        .stroke(currentColor.opacity(pulseNow ? 0.0 : 0.35), lineWidth: 1.5)
                        .frame(width: pulseNow ? 24 : 10, height: pulseNow ? 24 : 10)
                        .position(x: ladderX, y: currentY)
                    
                    // Radial glow aura
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [currentColor.opacity(0.50), currentColor.opacity(0.0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 14
                            )
                        )
                        .frame(width: 28, height: 28)
                        .position(x: ladderX, y: currentY)
                    
                    // Crisp dot with white rim
                    Circle()
                        .fill(currentColor)
                        .frame(width: 10, height: 10)
                        .position(x: ladderX, y: currentY)
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 1.2)
                        .frame(width: 10, height: 10)
                        .position(x: ladderX, y: currentY)
                    
                    // Connecting line from dot to label
                    // Position the NOW label so its right edge stays within bounds.
                    // The badge is ~120pt wide; anchor center at width * 0.75 clamped to leave 6pt margin.
                    let nowLabelHalfWidth: CGFloat = 64
                    let labelCenterX = min(width * 0.75, width - nowLabelHalfWidth - 6)
                    Path { path in
                        path.move(to: CGPoint(x: ladderX + 8, y: currentY))
                        if isLabelOffset {
                            let midX = ladderX + (labelCenterX - ladderX) / 2
                            path.addLine(to: CGPoint(x: midX, y: currentY))
                            path.addLine(to: CGPoint(x: labelCenterX - nowLabelHalfWidth + 8, y: nowLabelY))
                        } else {
                            path.addLine(to: CGPoint(x: labelCenterX - nowLabelHalfWidth + 8, y: currentY))
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [currentColor.opacity(0.45), currentColor.opacity(0.15)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
                    
                    // NOW / time-ago label badge — premium gradient glass
                    HStack(spacing: 4) {
                        Circle()
                            .fill(currentColor)
                            .frame(width: 5, height: 5)
                        
                        Text(timeLabel)
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.3)
                            .foregroundColor(currentColor)
                        
                        Text(formatPriceCompact(currentPrice))
                            .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundColor(currentColor.opacity(0.9))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .fixedSize()
                    .background(
                        Capsule()
                            .fill(currentColor.opacity(isDark ? 0.12 : 0.08))
                            .overlay(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(isDark ? 0.06 : 0.15), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(currentColor.opacity(0.25), lineWidth: 0.5)
                            )
                    )
                    .position(x: labelCenterX, y: nowLabelY)
                    
                    // Stop Loss marker (RIGHT side) - octagon/stop shape
                    simpleLevelMarker(
                        price: stopLoss,
                        label: "Stop Loss",
                        color: stopColor,
                        icon: "xmark.octagon.fill",
                        yPos: slY,
                        width: width,
                        ladderX: ladderX,
                        onRight: true,
                        markerShape: .octagon
                    )
                }
            }
            .frame(height: 180) // Increased height for better label spacing
            .clipped()
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5)) {
                    animateLadder = true
                }
                // Start pulse animation for NOW indicator
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseNow = true
                }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                // Refresh the time label every minute so "Now" transitions to "5m ago", etc.
                timeLabelTick = UUID()
            }
            
            // Scale-out targets row (below ladder for clarity) - tighter spacing
            if let tp1 = takeProfit1, let tp2 = takeProfit2 {
                VStack(spacing: 5) {
                    Text("TAKE PROFIT TARGETS")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .tracking(0.8)
                    
                    HStack(spacing: 5) {
                        scaleOutTargetPill(label: "TP1", price: tp1, percent: tp1Percent, exitPct: "33%")
                        scaleOutTargetPill(label: "TP2", price: tp2, percent: tp2Percent, exitPct: "33%")
                        scaleOutTargetPill(label: "TP3", price: takeProfit, percent: tp3Percent, exitPct: "34%")
                    }
                }
                .padding(.top, 2)
            }
            
            // Contextual entry zone label - tells user if price is in, above, or below the zone
            entryZoneContextLabel
            
            // Methodology badge - user-friendly summary of how levels were calculated
            if !methodology.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 9))
                        .foregroundColor(BrandColors.goldBase)
                    
                    Text(methodology)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    BrandColors.goldBase.opacity(isDark ? 0.10 : 0.06),
                                    BrandColors.goldBase.opacity(isDark ? 0.05 : 0.03)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(BrandColors.goldBase.opacity(0.15), lineWidth: 0.5)
                )
            }
        }
    }
    
    // MARK: - Entry Zone Context Label
    
    /// Informs the user whether the current price is inside, above, or below the entry zone
    /// so they can immediately see whether the trade setup is actionable right now.
    /// Always uses the entry zone's blue color to maintain its distinct identity.
    private var entryZoneContextLabel: some View {
        let (text, icon, useWarningColor): (String, String, Bool) = {
            if isInEntryZone {
                if direction == .bullish {
                    return ("Price is in buy zone", "checkmark.circle.fill", false)
                } else if direction == .bearish {
                    return ("Price is in sell zone", "checkmark.circle.fill", false)
                }
                return ("Price is in entry zone", "checkmark.circle.fill", false)
            } else if currentPrice < entryZoneLow {
                if direction == .bullish {
                    // Bullish: price dropping toward entry = good, may trigger buy
                    return ("Price approaching buy zone", "arrow.down.to.line", false)
                } else {
                    // Bearish: price is below sell zone = missed entry or wait for bounce
                    return ("Price below sell zone — wait for bounce to enter", "arrow.up.forward", true)
                }
            } else {
                // currentPrice > entryZoneHigh
                if direction == .bullish {
                    // Bullish: price above buy zone = need a pullback to enter
                    return ("Price above buy zone — wait for pullback", "arrow.down.forward", true)
                } else {
                    // Bearish: price rising toward sell zone = good, may trigger short
                    return ("Price approaching sell zone", "arrow.up.to.line", false)
                }
            }
        }()
        
        // Use orange for "wait" states where user needs to hold off; blue otherwise
        let labelColor: Color = useWarningColor ? .orange : entryColor
        
        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(labelColor)
            
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(labelColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(labelColor.opacity(isDark ? 0.10 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isDark ? 0.04 : 0.08), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(labelColor.opacity(isDark ? 0.20 : 0.15), lineWidth: 0.5)
        )
    }
    
    // MARK: - Marker Shape Variants
    
    /// Distinct marker shapes for each trading level type
    enum LevelMarkerShape {
        case diamond     // Take Profit - upward achievement
        case zone        // Entry Zone - wide rectangular zone indicator
        case octagon     // Stop Loss - stop-sign inspired danger
    }
    
    /// Draw a diamond shape on the ladder (Take Profit) — with radial glow
    @ViewBuilder
    private func diamondMarker(color: Color, at position: CGPoint) -> some View {
        let size: CGFloat = 11
        // Glow aura
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.35), color.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 10
                )
            )
            .frame(width: 22, height: 22)
            .position(x: position.x, y: position.y)
        
        // Diamond shape
        Path { path in
            path.move(to: CGPoint(x: position.x, y: position.y - size/2))
            path.addLine(to: CGPoint(x: position.x + size/2, y: position.y))
            path.addLine(to: CGPoint(x: position.x, y: position.y + size/2))
            path.addLine(to: CGPoint(x: position.x - size/2, y: position.y))
            path.closeSubpath()
        }
        .fill(color)
        
        // White highlight edge
        Path { path in
            path.move(to: CGPoint(x: position.x, y: position.y - size/2))
            path.addLine(to: CGPoint(x: position.x + size/2, y: position.y))
            path.addLine(to: CGPoint(x: position.x, y: position.y + size/2))
            path.addLine(to: CGPoint(x: position.x - size/2, y: position.y))
            path.closeSubpath()
        }
        .stroke(Color.white.opacity(0.30), lineWidth: 0.6)
    }
    
    /// Draw a wide zone indicator on the ladder (Entry Zone) — with glow border
    @ViewBuilder
    private func zoneMarker(color: Color, at position: CGPoint) -> some View {
        // Glow
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color.opacity(0.20))
            .frame(width: 18, height: 14)
            .position(x: position.x, y: position.y)
        
        // Core shape
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color.opacity(0.30))
            .frame(width: 14, height: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(color.opacity(0.7), lineWidth: 1)
            )
            .position(x: position.x, y: position.y)
    }
    
    /// Draw an octagon/stop shape on the ladder (Stop Loss) — with danger glow
    @ViewBuilder
    private func octagonMarker(color: Color, at position: CGPoint) -> some View {
        let size: CGFloat = 11
        let inset: CGFloat = size * 0.3
        
        // Danger glow
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.35), color.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 10
                )
            )
            .frame(width: 22, height: 22)
            .position(x: position.x, y: position.y)
        
        // Octagon shape
        Path { path in
            path.move(to: CGPoint(x: position.x - size/2 + inset, y: position.y - size/2))
            path.addLine(to: CGPoint(x: position.x + size/2 - inset, y: position.y - size/2))
            path.addLine(to: CGPoint(x: position.x + size/2,         y: position.y - size/2 + inset))
            path.addLine(to: CGPoint(x: position.x + size/2,         y: position.y + size/2 - inset))
            path.addLine(to: CGPoint(x: position.x + size/2 - inset, y: position.y + size/2))
            path.addLine(to: CGPoint(x: position.x - size/2 + inset, y: position.y + size/2))
            path.addLine(to: CGPoint(x: position.x - size/2,         y: position.y + size/2 - inset))
            path.addLine(to: CGPoint(x: position.x - size/2,         y: position.y - size/2 + inset))
            path.closeSubpath()
        }
        .fill(color)
        
        // White edge highlight
        Path { path in
            path.move(to: CGPoint(x: position.x - size/2 + inset, y: position.y - size/2))
            path.addLine(to: CGPoint(x: position.x + size/2 - inset, y: position.y - size/2))
            path.addLine(to: CGPoint(x: position.x + size/2,         y: position.y - size/2 + inset))
            path.addLine(to: CGPoint(x: position.x + size/2,         y: position.y + size/2 - inset))
            path.addLine(to: CGPoint(x: position.x + size/2 - inset, y: position.y + size/2))
            path.addLine(to: CGPoint(x: position.x - size/2 + inset, y: position.y + size/2))
            path.addLine(to: CGPoint(x: position.x - size/2,         y: position.y + size/2 - inset))
            path.addLine(to: CGPoint(x: position.x - size/2,         y: position.y - size/2 + inset))
            path.closeSubpath()
        }
        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
    }
    
    @ViewBuilder
    private func simpleLevelMarker(price: Double, label: String, color: Color, icon: String, yPos: CGFloat, width: CGFloat, ladderX: CGFloat, onRight: Bool, markerShape: LevelMarkerShape = .diamond) -> some View {
        let lineLength: CGFloat = 22
        let labelWidth: CGFloat = 76
        
        let labelX: CGFloat = onRight ? ladderX + lineLength + labelWidth/2 + 3 : ladderX - lineLength - labelWidth/2 - 3
        let clampedX = min(max(labelX, labelWidth/2 + 3), width - labelWidth/2 - 3)
        
        // Distinct marker shape on ladder per level type
        let markerPos = CGPoint(x: ladderX, y: yPos)
        switch markerShape {
        case .diamond:
            diamondMarker(color: color, at: markerPos)
        case .zone:
            zoneMarker(color: color, at: markerPos)
        case .octagon:
            octagonMarker(color: color, at: markerPos)
        }
        
        // Connecting line — gradient fade
        Path { path in
            let startX = ladderX + (onRight ? 6 : -6)
            let endX = ladderX + (onRight ? lineLength : -lineLength)
            path.move(to: CGPoint(x: startX, y: yPos))
            path.addLine(to: CGPoint(x: endX, y: yPos))
        }
        .stroke(
            LinearGradient(
                colors: onRight
                    ? [color.opacity(0.40), color.opacity(0.12)]
                    : [color.opacity(0.12), color.opacity(0.40)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
        )
        
        // Label card — premium glass style
        HStack(spacing: 3) {
            if onRight { Spacer(minLength: 0) }
            
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
            
            VStack(alignment: onRight ? .trailing : .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Text(formatPriceCompact(price))
                    .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(color)
            }
            
            if !onRight { Spacer(minLength: 0) }
        }
        .frame(width: labelWidth)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(isDark ? 0.10 : 0.06))
                .overlay(
                    // Top shine
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isDark ? 0.06 : 0.12), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(color.opacity(isDark ? 0.20 : 0.15), lineWidth: 0.5)
        )
        .position(x: clampedX, y: yPos)
    }
    
    // Scale-out target pill for TP levels below ladder — premium glass cards
    // FIX v28: Added direction parameter to show correct +/- sign for bearish predictions.
    // Previously always showed "+" which was misleading when targets are below current price.
    @ViewBuilder
    private func scaleOutTargetPill(label: String, price: Double, percent: Double?, exitPct: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundColor(targetColor)
            
            Text(formatPriceCompact(price))
                .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundColor(DS.Adaptive.textPrimary)
            
            if let pct = percent {
                let sign = direction == .bearish ? "-" : "+"
                Text(String(format: "\(sign)%.1f%%", pct))
                    .font(.system(size: 8, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(targetColor.opacity(0.8))
            }
            
            Text("Exit \(exitPct)")
                .font(.system(size: 7, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(targetColor.opacity(isDark ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isDark ? 0.04 : 0.08), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(targetColor.opacity(isDark ? 0.18 : 0.12), lineWidth: 0.5)
        )
    }
    
    // Enhanced level marker with percent and exit labels (kept for backward compatibility)
    @ViewBuilder
    private func levelMarkerEnhanced(price: Double, label: String, percentLabel: String?, exitLabel: String?, color: Color, icon: String, yPos: CGFloat, width: CGFloat, ladderX: CGFloat, onRight: Bool) -> some View {
        let lineLength: CGFloat = 30
        let labelWidth: CGFloat = 85
        let labelPadding: CGFloat = 6
        
        // Calculate safe label position that stays within bounds
        let rawLabelX: CGFloat = onRight ? ladderX + lineLength + labelWidth/2 + labelPadding : ladderX - lineLength - labelWidth/2 - labelPadding
        // Clamp to stay within view bounds with margin
        let minX = labelWidth/2 + 4
        let maxX = width - labelWidth/2 - 4
        let labelOffsetX = min(max(rawLabelX, minX), maxX)
        
        // Marker dot on ladder with enhanced glow
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 16, height: 16)
            
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            
            Circle()
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                .frame(width: 10, height: 10)
        }
        .position(x: ladderX, y: yPos)
        
        // Connecting dashed line
        Path { path in
            let startX = ladderX + (onRight ? 5 : -5)
            let endX = ladderX + (onRight ? lineLength : -lineLength)
            path.move(to: CGPoint(x: startX, y: yPos))
            path.addLine(to: CGPoint(x: endX, y: yPos))
        }
        .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        
        // Enhanced label card with percent and exit info
        HStack(spacing: 3) {
            if onRight { Spacer(minLength: 0) }
            
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(color)
            
            VStack(alignment: onRight ? .trailing : .leading, spacing: 1) {
                // Main label
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                // Price
                Text(formatPriceCompact(price))
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(color)
                
                // Percent label (if provided)
                if let pctLabel = percentLabel {
                    Text(pctLabel)
                        .font(.system(size: 8, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundColor(color.opacity(0.8))
                }
                
                // Exit label (if provided)
                if let exitLbl = exitLabel {
                    Text(exitLbl)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary.opacity(0.8))
                }
            }
            
            if !onRight { Spacer(minLength: 0) }
        }
        .frame(width: labelWidth)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(isDark ? 0.12 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(color.opacity(0.15), lineWidth: 0.5)
        )
        .position(x: labelOffsetX, y: yPos)
    }
    
    // Compact level marker with label - constrained within bounds
    @ViewBuilder
    private func levelMarker(price: Double, label: String, color: Color, icon: String, yPos: CGFloat, width: CGFloat, ladderX: CGFloat, onRight: Bool) -> some View {
        let lineLength: CGFloat = 30
        let labelWidth: CGFloat = 75
        let labelPadding: CGFloat = 6
        
        // Calculate safe label position that stays within bounds
        let rawLabelX: CGFloat = onRight ? ladderX + lineLength + labelWidth/2 + labelPadding : ladderX - lineLength - labelWidth/2 - labelPadding
        // Clamp to stay within view bounds with margin
        let minX = labelWidth/2 + 4
        let maxX = width - labelWidth/2 - 4
        let labelOffsetX = min(max(rawLabelX, minX), maxX)
        
        // Marker dot on ladder
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .position(x: ladderX, y: yPos)
        
        // Connecting dashed line
        Path { path in
            let startX = ladderX + (onRight ? 5 : -5)
            let endX = ladderX + (onRight ? lineLength : -lineLength)
            path.move(to: CGPoint(x: startX, y: yPos))
            path.addLine(to: CGPoint(x: endX, y: yPos))
        }
        .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        
        // Compact label card
        HStack(spacing: 3) {
            if onRight { Spacer(minLength: 0) }
            
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(color)
            
            VStack(alignment: onRight ? .trailing : .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Text(formatPriceCompact(price))
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(color)
            }
            
            if !onRight { Spacer(minLength: 0) }
        }
        .frame(width: labelWidth)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(isDark ? 0.12 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(color.opacity(0.15), lineWidth: 0.5)
        )
        .position(x: labelOffsetX, y: yPos)
    }
    
    private func formatPriceCompact(_ value: Double) -> String {
        if value >= 10000 {
            return String(format: "$%.0f", value)
        } else if value >= 100 {
            return String(format: "$%.1f", value)
        } else if value >= 1 {
            return String(format: "$%.2f", value)
        } else {
            return String(format: "$%.4f", value)
        }
    }
}

// MARK: - Trading Level Stat (Compact glassmorphism stat cell)

struct TradingLevelStat: View {
    let label: String
    let value: String
    var subValue: String? = nil
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            // Label
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.5)
                .foregroundColor(DS.Adaptive.textTertiary)
            
            // Value
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(DS.Adaptive.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            // Sub value (percentage) - always reserve space for consistent height
            Group {
                if let sub = subValue {
                    Text(sub)
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundColor(color.opacity(0.95))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(color.opacity(isDark ? 0.18 : 0.12))
                                .overlay(
                                    Capsule()
                                        .stroke(color.opacity(0.28), lineWidth: 0.6)
                                )
                        )
                } else {
                    Text(" ")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.clear)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 58) // Consistent height across all stat cells
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(isDark ? 0.15 : 0.10),
                            color.opacity(isDark ? 0.08 : 0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Enhanced Price Range Visualization (Modern Design)

struct EnhancedPriceRangeVisualization: View {
    let currentPrice: Double
    let predictedPrice: Double
    let lowPrice: Double
    let highPrice: Double
    let direction: PredictionDirection
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var animateMarker: Bool = false
    @State private var animatedProgress: CGFloat = 0
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var priceChangePercent: Double {
        guard currentPrice > 0 else { return 0 }
        return ((predictedPrice - currentPrice) / currentPrice) * 100
    }
    
    // Calculate expanded range that includes ALL prices
    private var expandedRange: (min: Double, max: Double, range: Double) {
        let allPrices = [currentPrice, predictedPrice, lowPrice, highPrice]
        let minPrice = (allPrices.min() ?? lowPrice) * 0.998
        let maxPrice = (allPrices.max() ?? highPrice) * 1.002
        let range = max(maxPrice - minPrice, 1)
        return (minPrice, maxPrice, range)
    }
    
    private func position(for price: Double) -> CGFloat {
        let (minPrice, _, range) = expandedRange
        return CGFloat((price - minPrice) / range)
    }
    
    var body: some View {
        VStack(spacing: 18) {
            // Clean price comparison header
            HStack(alignment: .center, spacing: 0) {
                // Current price
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .tracking(0.5)
                    Text(formatCompactPrice(currentPrice))
                        .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Central change indicator
                VStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text(String(format: "%@%.1f%%", priceChangePercent >= 0 ? "+" : "", priceChangePercent))
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(direction.color)
                        )
                }
                .frame(width: 80)
                
                // Predicted price
                VStack(alignment: .trailing, spacing: 3) {
                    Text("PREDICTED")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .tracking(0.5)
                    Text(formatCompactPrice(predictedPrice))
                        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(direction.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            
            // Modern range bar with clean aesthetics
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height  // Use actual container height for proper centering
                let barHeight: CGFloat = 10
                let markerSize: CGFloat = 16  // Slightly smaller for better fit
                let centerY = height / 2      // Center markers in container, not bar
                let isNeutral = direction == .neutral
                
                let currentPos = position(for: currentPrice)
                let predictedPos = position(for: predictedPrice)
                let lowPos = position(for: lowPrice)
                let highPos = position(for: highPrice)
                
                // Active range dimensions
                let rangeStartX = lowPos * width
                let rangeEndX = highPos * width
                let rangeWidth = max(rangeEndX - rangeStartX, 4)
                
                ZStack(alignment: .center) {
                    // Background track - different gradient for neutral vs directional
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: isNeutral ? [
                                    // Neutral: subtle gray gradient emphasizing the range zone
                                    Color.gray.opacity(isDark ? 0.15 : 0.10),
                                    direction.color.opacity(isDark ? 0.20 : 0.15),
                                    Color.gray.opacity(isDark ? 0.15 : 0.10)
                                ] : [
                                    // Directional: red to green gradient
                                    Color.red.opacity(isDark ? 0.25 : 0.15),
                                    Color.yellow.opacity(isDark ? 0.2 : 0.12),
                                    Color.green.opacity(isDark ? 0.25 : 0.15)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: barHeight)
                    
                    // Active range highlight - emphasized more for neutral (trading zone)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: isNeutral ? [
                                    // Neutral: yellow/gold gradient for range-bound zone
                                    direction.color.opacity(isDark ? 0.45 : 0.35),
                                    direction.color.opacity(isDark ? 0.55 : 0.45),
                                    direction.color.opacity(isDark ? 0.45 : 0.35)
                                ] : [
                                    // Directional: red to green
                                    Color.red.opacity(isDark ? 0.5 : 0.35),
                                    Color.orange.opacity(isDark ? 0.45 : 0.3),
                                    Color.green.opacity(isDark ? 0.5 : 0.35)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: rangeWidth, height: barHeight)
                        .position(x: rangeStartX + rangeWidth / 2, y: centerY)
                    
                    if isNeutral {
                        // NEUTRAL: Single combined marker (current = target)
                        ZStack {
                            // Outer glow ring
                            Circle()
                                .fill(direction.color.opacity(0.3))
                                .frame(width: markerSize + 4, height: markerSize + 4)
                            
                            // Main marker
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white, direction.color.opacity(0.3)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: markerSize, height: markerSize)
                                .overlay(
                                    Circle()
                                        .stroke(direction.color, lineWidth: 2)
                                )
                            
                            // Horizontal arrows indicating range-bound (sideways movement)
                            HStack(spacing: 1) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 5, weight: .bold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 5, weight: .bold))
                            }
                            .foregroundColor(direction.color)
                        }
                        .position(x: currentPos * width, y: centerY)
                    } else {
                        // DIRECTIONAL: Two separate markers (current + target)
                        
                        // Current position marker (white)
                        Circle()
                            .fill(Color.white)
                            .frame(width: markerSize, height: markerSize)
                            .overlay(
                                Circle()
                                    .stroke(DS.Adaptive.textTertiary.opacity(0.3), lineWidth: 1.5)
                            )
                            .position(x: currentPos * width, y: centerY)
                        
                        // Target position marker (colored with direction arrow)
                        ZStack {
                            Circle()
                                .fill(direction.color)
                                .frame(width: markerSize, height: markerSize)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                                )
                            
                            // Direction arrow icon
                            Image(systemName: direction == .bullish ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .position(
                            x: animateMarker ? predictedPos * width : currentPos * width,
                            y: centerY
                        )
                        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: animateMarker)
                    }
                }
            }
            .frame(height: 24)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    animateMarker = true
                }
            }
            
            // Modern range labels with vertical bars and percentage context
            let lowChangePercent = currentPrice > 0 ? ((lowPrice - currentPrice) / currentPrice) * 100 : 0
            let highChangePercent = currentPrice > 0 ? ((highPrice - currentPrice) / currentPrice) * 100 : 0
            
            HStack(alignment: .top, spacing: 0) {
                // Low range
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.red)
                        .frame(width: 3, height: 36)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Low")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(formatCompactPrice(lowPrice))
                            .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(Color.red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        // Percentage change from current
                        Text(String(format: "%.1f%%", lowChangePercent))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundColor(Color.red.opacity(0.7))
                    }
                }
                
                Spacer()
                
                // High range
                HStack(spacing: 6) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("High")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(formatCompactPrice(highPrice))
                            .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(Color.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        // Percentage change from current
                        Text(String(format: "+%.1f%%", highChangePercent))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundColor(Color.green.opacity(0.7))
                    }
                    
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.green)
                        .frame(width: 3, height: 36)
                }
            }
        }
    }
    
    private func formatCompactPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.maximumFractionDigits = value < 1 ? 4 : (value < 100 ? 2 : 0)
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - Legacy Price Range Visualization (kept for compatibility)

struct PriceRangeVisualization: View {
    let currentPrice: Double
    let predictedPrice: Double
    let lowPrice: Double
    let highPrice: Double
    let direction: PredictionDirection
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var animateMarker: Bool = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var priceChangePercent: Double {
        guard currentPrice > 0 else { return 0 }
        return ((predictedPrice - currentPrice) / currentPrice) * 100
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Main price display with change
            HStack(alignment: .center) {
                // Current price
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .tracking(0.5)
                    Text(formatCompactPrice(currentPrice))
                        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                // Arrow indicator
                Image(systemName: direction == .bullish ? "arrow.right" : (direction == .bearish ? "arrow.right" : "equal"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .rotationEffect(.degrees(direction == .bullish ? -30 : (direction == .bearish ? 30 : 0)))
                
                Spacer()
                
                // Predicted price with change badge
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PREDICTED")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .tracking(0.5)
                    HStack(spacing: 6) {
                        Text(formatCompactPrice(predictedPrice))
                            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(direction.color)
                        
                        // Change pill
                        HStack(spacing: 2) {
                            Image(systemName: priceChangePercent >= 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                            Text(String(format: "%.1f%%", abs(priceChangePercent)))
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(direction.color)
                        )
                    }
                }
            }
            
            // Visual range bar
            GeometryReader { geo in
                let width = geo.size.width
                let range = highPrice - lowPrice
                let currentPos = range > 0 ? CGFloat((currentPrice - lowPrice) / range) : 0.5
                let predictedPos = range > 0 ? CGFloat((predictedPrice - lowPrice) / range) : 0.5
                
                ZStack(alignment: .leading) {
                    // Background track with gradient
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.red.opacity(isDark ? 0.25 : 0.2),
                                    Color.yellow.opacity(isDark ? 0.2 : 0.15),
                                    Color.green.opacity(isDark ? 0.25 : 0.2)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                // LIGHT MODE FIX: Adaptive stroke
                                .stroke(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05), lineWidth: 1)
                        )
                    
                    // Movement path line
                    if abs(currentPos - predictedPos) > 0.02 {
                        let startX = currentPos * width
                        let endX = animateMarker ? predictedPos * width : currentPos * width
                        
                        // Animated dashed line
                        Path { path in
                            path.move(to: CGPoint(x: min(startX, endX), y: 14))
                            path.addLine(to: CGPoint(x: max(startX, endX), y: 14))
                        }
                        .stroke(
                            direction.color,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3])
                        )
                        .opacity(0.6)
                    }
                    
                    // Current price marker
                    ZStack {
                        // Outer ring
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            .frame(width: 20, height: 20)
                        
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, Color.white.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 16, height: 16)
                        
                        Circle()
                            .fill(Color.gray.opacity(0.6))
                            .frame(width: 6, height: 6)
                    }
                    .offset(x: max(0, min(width - 20, currentPos * width - 10)))
                    
                    // Predicted price marker with pulse effect
                    ZStack {
                        // Pulse ring
                        Circle()
                            .stroke(direction.color.opacity(0.3), lineWidth: 2)
                            .frame(width: 28, height: 28)
                            .scaleEffect(animateMarker ? 1.2 : 1.0)
                            .opacity(animateMarker ? 0 : 0.5)
                        
                        // Outer glow
                        Circle()
                            .fill(direction.color.opacity(0.2))
                            .frame(width: 26, height: 26)
                        
                        // Main marker
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [direction.color, direction.color.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 22, height: 22)
                        
                        // Icon
                        Image(systemName: direction == .bullish ? "chevron.up" : (direction == .bearish ? "chevron.down" : "minus"))
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                    }
                    .offset(x: max(0, min(width - 22, (animateMarker ? predictedPos : currentPos) * width - 11)))
                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: animateMarker)
                }
            }
            .frame(height: 28)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        animateMarker = true
                    }
                }
            }
            
            // Price range labels
            HStack {
                // Low
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.red.opacity(0.7))
                            .frame(width: 3, height: 10)
                        Text("Low")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    Text(formatCompactPrice(lowPrice))
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(Color.red.opacity(0.8))
                }
                
                Spacer()
                
                // High
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 2) {
                        Text("High")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.green.opacity(0.7))
                            .frame(width: 3, height: 10)
                    }
                    Text(formatCompactPrice(highPrice))
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(Color.green.opacity(0.8))
                }
            }
        }
    }
    
    // PERFORMANCE FIX: Static formatter to avoid creating new instance on every call
    private static let compactPriceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        return formatter
    }()
    
    private func formatCompactPrice(_ value: Double) -> String {
        Self.compactPriceFormatter.maximumFractionDigits = value < 1 ? 4 : (value < 100 ? 2 : 0)
        return Self.compactPriceFormatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - Prediction Countdown Timer

struct PredictionCountdown: View {
    let targetDate: Date
    let timeframe: PredictionTimeframe
    let direction: PredictionDirection
    
    @State private var timeRemaining: TimeInterval = 0
    @State private var timer: Timer?
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    private var isUrgent: Bool { timeRemaining < 24 * 3600 && timeRemaining > 0 }
    private var isExpired: Bool { timeRemaining <= 0 }
    
    var body: some View {
        VStack(spacing: 12) {
            // Target date header
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BrandColors.goldBase)
                
                Text("Prediction Target")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Spacer()
                
                if isExpired {
                    Text("EXPIRED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.red))
                } else if isUrgent {
                    Text("ENDING SOON")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange))
                }
            }
            
            // Main countdown display
            HStack(spacing: 16) {
                // Target date
                VStack(alignment: .leading, spacing: 4) {
                    Text(formattedTargetDate)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(formattedTargetTime)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                // Countdown boxes
                if !isExpired {
                    HStack(spacing: 8) {
                        CountdownUnit(value: days, label: "DAYS", isUrgent: isUrgent)
                        CountdownUnit(value: hours, label: "HRS", isUrgent: isUrgent)
                        CountdownUnit(value: minutes, label: "MIN", isUrgent: isUrgent)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                direction.color.opacity(isDark ? 0.15 : 0.10),
                                direction.color.opacity(isDark ? 0.05 : 0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(direction.color.opacity(0.2), lineWidth: 1)
            )
        }
        .onAppear {
            updateTimeRemaining()
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private var days: Int { max(0, Int(timeRemaining) / 86400) }
    private var hours: Int { max(0, (Int(timeRemaining) % 86400) / 3600) }
    private var minutes: Int { max(0, (Int(timeRemaining) % 3600) / 60) }
    
    // PERFORMANCE FIX: Static formatters to avoid creating new instances on every access
    private static let targetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()
    
    private static let targetTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    private var formattedTargetDate: String {
        Self.targetDateFormatter.string(from: targetDate)
    }
    
    private var formattedTargetTime: String {
        Self.targetTimeFormatter.string(from: targetDate)
    }
    
    private func updateTimeRemaining() {
        timeRemaining = targetDate.timeIntervalSince(Date())
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            updateTimeRemaining()
        }
    }
}

struct CountdownUnit: View {
    let value: Int
    let label: String
    let isUrgent: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(isUrgent ? .orange : DS.Adaptive.textPrimary)
            
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(DS.Adaptive.textTertiary)
                .tracking(0.5)
        }
        .frame(width: 52)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        )
    }
}

// MARK: - Mini Prediction Chart (Using SparklineView for Historical Data)

struct MiniPredictionChart: View {
    let currentPrice: Double      // Current live price (or prediction base price as fallback)
    let predictedPrice: Double    // Adjusted predicted target price (already consistent with currentPrice)
    let direction: PredictionDirection
    let sparklineData: [Double]?
    let livePrice: Double?        // Current live price (optional, for better alignment)
    let timeframe: PredictionTimeframe  // Prediction timeframe for appropriate data slicing
    
    /// When the prediction was generated (nil shows "Now" as fallback)
    var generatedAt: Date? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    
    // CRITICAL FIX: Track animation with a stable ID to prevent corruption on orientation change
    // Using @State with default of 1 ensures chart is always visible even during view recreation
    @State private var animationProgress: CGFloat = 1
    @State private var hasAnimated: Bool = true
    @State private var isInitialAppear: Bool = true
    
    // Track geometry size to detect orientation changes
    @State private var lastKnownWidth: CGFloat = 0
    
    /// Timer-driven refresh so the label updates live
    @State private var timeLabelTick: UUID = UUID()
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Smart time label: "Now" for first 5 min, then relative time
    private var timeLabel: String {
        _ = timeLabelTick
        return predictionTimeLabel(for: generatedAt)
    }
    
    /// Prediction line color
    private var predictionColor: Color { direction.color }
    
    /// Historical line color based on trend of the SLICED data (timeframe-appropriate)
    private var historicalColor: Color {
        guard let data = preparedData, data.count >= 2,
              let first = data.first, let last = data.last else {
            return .green
        }
        return last >= first ? .green : .red
    }
    
    /// Whether historical trend is positive (based on sliced data)
    private var isHistoricalPositive: Bool {
        guard let data = preparedData, data.count >= 2,
              let first = data.first, let last = data.last else {
            return true
        }
        return last >= first
    }
    
    /// Historical section width ratio - more space for historical to show full chart
    private var historicalWidthRatio: CGFloat {
        return 0.60  // 60% for historical, 40% for prediction
    }
    
    /// LTTB (Largest Triangle Three Buckets) downsampling algorithm
    /// Preserves visual features (peaks, valleys) better than simple block aggregation
    /// This is the industry-standard algorithm for sparkline downsampling used in the watchlist
    /// - Parameters:
    ///   - series: The input price data array
    ///   - maxPoints: Maximum number of points in the output
    /// - Returns: Downsampled array that preserves visual features
    private func lttbResample(_ series: [Double], maxPoints: Int) -> [Double] {
        let n = series.count
        guard n > maxPoints, maxPoints > 2 else { return series }
        
        var out: [Double] = []
        out.reserveCapacity(maxPoints)
        
        // Always include the first point
        out.append(series[0])
        
        // Bucket size (excluding first and last points)
        let bucketSize = Double(n - 2) / Double(maxPoints - 2)
        
        var previousSelectedIndex = 0
        
        for bucketIndex in 0..<(maxPoints - 2) {
            // Calculate bucket boundaries
            let bucketStart = Int(Double(bucketIndex) * bucketSize) + 1
            let bucketEnd = min(Int(Double(bucketIndex + 1) * bucketSize) + 1, n - 1)
            
            // Calculate the average point of the next bucket (for triangle area calculation)
            let nextBucketStart = bucketEnd
            let nextBucketEnd = min(Int(Double(bucketIndex + 2) * bucketSize) + 1, n)
            
            var avgX: Double = 0
            var avgY: Double = 0
            let nextBucketCount = nextBucketEnd - nextBucketStart
            
            if nextBucketCount > 0 {
                for i in nextBucketStart..<nextBucketEnd {
                    avgX += Double(i)
                    avgY += series[i]
                }
                avgX /= Double(nextBucketCount)
                avgY /= Double(nextBucketCount)
            } else {
                avgX = Double(n - 1)
                avgY = series[n - 1]
            }
            
            // Find the point in this bucket that creates the largest triangle
            var maxArea: Double = -1
            var selectedIndex = bucketStart
            
            let pointAX = Double(previousSelectedIndex)
            let pointAY = series[previousSelectedIndex]
            
            for i in bucketStart..<bucketEnd {
                // Calculate triangle area using the cross product formula
                let area = abs(
                    (pointAX - avgX) * (series[i] - pointAY) -
                    (pointAX - Double(i)) * (avgY - pointAY)
                ) * 0.5
                
                if area > maxArea {
                    maxArea = area
                    selectedIndex = i
                }
            }
            
            out.append(series[selectedIndex])
            previousSelectedIndex = selectedIndex
        }
        
        // Always include the last point
        out.append(series[n - 1])
        
        return out
    }
    
    /// Returns the number of hours of historical data to show based on prediction timeframe
    /// This slices the sparkline to show relevant context without overwhelming noise
    private var historicalHoursForTimeframe: Int {
        switch timeframe {
        case .hour:        return 24   // Show last 24 hours for 1H prediction
        case .fourHours:   return 48   // Show last 48 hours for 4H prediction
        case .twelveHours: return 48   // Show last 48 hours for 12H prediction
        case .day:         return 72   // Show last 3 days for 24H prediction
        case .week:        return 168  // Show full 7 days for 7D prediction
        case .month:       return 168  // Show full 7 days for 30D prediction (all available)
        }
    }
    
    /// Label for the historical section based on timeframe
    private var historicalLabel: String {
        switch timeframe {
        case .hour:        return "24H"
        case .fourHours:   return "48H"
        case .twelveHours: return "48H"
        case .day:         return "3D"
        case .week:        return "7D"
        case .month:       return "7D"
        }
    }
    
    /// Returns target point counts for downsampling after slicing
    /// Higher point counts preserve more price detail for realistic chart appearance
    private var targetPointsForTimeframe: Int {
        switch timeframe {
        case .hour:        return 48   // Good detail for 24h of data
        case .fourHours:   return 72   // Good detail for 48h of data
        case .twelveHours: return 72   // Good detail for 48h of data
        case .day:         return 96   // Good detail for 3 days of data
        case .week:        return 168  // Full 7-day hourly data (no downsampling)
        case .month:       return 168  // Full 7-day data
        }
    }
    
    /// Prepared sparkline data - sliced to relevant timeframe and downsampled if needed
    /// Shows historical data appropriate to the prediction timeframe for meaningful context
    private var preparedData: [Double]? {
        guard var data = sparklineData, !data.isEmpty else { return nil }
        data = data.filter { $0.isFinite && $0 > 0 }
        guard data.count >= 2 else { return nil }
        
        // Slice to show only relevant historical period based on prediction timeframe
        // CoinGecko sparkline is hourly data, so historicalHoursForTimeframe = number of points to keep
        let hoursToShow = historicalHoursForTimeframe
        if data.count > hoursToShow {
            // Take the most recent data points (end of array is most recent)
            data = Array(data.suffix(hoursToShow))
        }
        
        let targetPoints = targetPointsForTimeframe
        
        // Only downsample if we have significantly more points than target
        // This preserves the real price movements
        if data.count > targetPoints + 20 {
            data = lttbResample(data, maxPoints: targetPoints)
        }
        
        return data
    }
    
    init(currentPrice: Double, predictedPrice: Double, direction: PredictionDirection, sparklineData: [Double]? = nil, livePrice: Double? = nil, timeframe: PredictionTimeframe = .week, generatedAt: Date? = nil) {
        self.currentPrice = currentPrice
        self.predictedPrice = predictedPrice
        self.direction = direction
        self.sparklineData = sparklineData
        self.livePrice = livePrice
        self.timeframe = timeframe
        self.generatedAt = generatedAt
        
        // ORIENTATION FIX: If we have data at init time, skip entrance animation
        // This prevents broken state when view is recreated during rotation
        let hasData = sparklineData != nil && (sparklineData?.count ?? 0) >= 2
        _animationProgress = State(initialValue: hasData ? 1 : 0)
        _hasAnimated = State(initialValue: hasData)
        _isInitialAppear = State(initialValue: !hasData)
    }
    
    /// Format price compactly for chart labels
    private func formatPriceCompact(_ price: Double) -> String {
        if price >= 1000 {
            return "$\(String(format: "%.1fK", price / 1000))"
        } else if price >= 1 {
            return "$\(String(format: "%.0f", price))"
        } else {
            return "$\(String(format: "%.4f", price))"
        }
    }
    
    /// Generate a natural-looking projected price path with realistic oscillations
    /// Generate a realistic chart-like path that simulates price action toward the target
    private func generateProjectedPath(from start: CGPoint, to end: CGPoint, segments: Int = 8) -> [CGPoint] {
        var points: [CGPoint] = [start]
        let totalDeltaY = end.y - start.y
        let totalDeltaX = end.x - start.x
        
        // Use price as seed for consistent patterns
        let seed = Int(predictedPrice * 1000) % 10000
        
        // More points = more chart-like appearance (like a real sparkline)
        let numPoints = 16
        
        // Scale volatility relative to the vertical delta so the path always
        // looks intentionally directional. For large moves the oscillations are
        // proportionally bigger; for small/neutral moves they stay gentle to
        // avoid noise overpowering the signal.
        let absDelta = abs(totalDeltaY)
        let volatility: CGFloat = max(2, min(8, absDelta * 0.35))
        
        var currentY = start.y
        
        for i in 1..<numPoints {
            let progress = CGFloat(i) / CGFloat(numPoints)
            let baseX = start.x + totalDeltaX * progress
            
            // Target Y at this point (where we should trend toward)
            let trendY = start.y + totalDeltaY * progress
            
            // Generate pseudo-random movement (deterministic based on seed + index)
            let hash = (seed + i * 7919) % 1000  // Prime multiplier for variation
            let randomFactor = CGFloat(hash) / 500.0 - 1.0  // -1 to +1
            
            // Chart-like movements scaled to the prediction magnitude
            let movement = randomFactor * volatility
            
            // Pull toward trend line (stronger as we approach end)
            let pullStrength = progress * progress  // Quadratic pull
            let targetPull = (trendY - currentY) * (0.3 + pullStrength * 0.5)
            
            // Apply movement + trend pull
            currentY = currentY + movement + targetPull
            
            // Clamp to reasonable bounds
            let minY = min(start.y, end.y) - volatility * 1.5
            let maxY = max(start.y, end.y) + volatility * 1.5
            currentY = max(minY, min(maxY, currentY))
            
            points.append(CGPoint(x: baseX, y: currentY))
        }
        
        // Ensure we end exactly at target
        points.append(end)
        return points
    }
    
    /// Create a smooth sparkline-style path using Catmull-Rom interpolation
    /// This matches the smooth rendering used by the premium watchlist sparklines
    /// - Parameter points: Input points to interpolate
    /// - Parameter samplesPerSegment: Number of interpolated points per segment (higher = smoother)
    /// - Returns: A smooth Path through the points
    private func smoothPath(through points: [CGPoint], samplesPerSegment: Int = 4) -> Path {
        guard points.count >= 2 else { return Path() }
        
        // For very few points, use simpler interpolation
        guard points.count >= 3, samplesPerSegment > 0 else {
            var path = Path()
            path.move(to: points[0])
            for i in 1..<points.count {
                path.addLine(to: points[i])
            }
            return path
        }
        
        // Catmull-Rom interpolation for smooth curves (Y axis only, X stays linear)
        var path = Path()
        var interpolatedPoints: [CGPoint] = []
        interpolatedPoints.reserveCapacity((points.count - 1) * samplesPerSegment + 1)
        
        let n = points.count
        let invSamples = 1.0 / CGFloat(samplesPerSegment)
        
        // Helper to safely access points with boundary clamping
        func safePoint(_ i: Int) -> CGPoint {
            points[max(0, min(n - 1, i))]
        }
        
        for i in 0..<(n - 1) {
            let p0 = safePoint(i - 1)
            let p1 = safePoint(i)
            let p2 = safePoint(i + 1)
            let p3 = safePoint(i + 2)
            
            // Pre-compute Catmull-Rom coefficients for this segment (Y axis)
            let c0 = p1.y
            let c1 = 0.5 * (-p0.y + p2.y)
            let c2 = 0.5 * (2*p0.y - 5*p1.y + 4*p2.y - p3.y)
            let c3 = 0.5 * (-p0.y + 3*p1.y - 3*p2.y + p3.y)
            
            // X interpolation values
            let xDelta = p2.x - p1.x
            
            for s in 0..<samplesPerSegment {
                let t = CGFloat(s) * invSamples
                let t2 = t * t
                let t3 = t2 * t
                
                // Linear interpolation for X (time axis must be monotonic)
                let x = p1.x + xDelta * t
                
                // Catmull-Rom interpolation for Y using pre-computed coefficients
                let y = c0 + c1*t + c2*t2 + c3*t3
                
                interpolatedPoints.append(CGPoint(x: x, y: y))
            }
        }
        
        // Always include the last point
        if let last = points.last {
            interpolatedPoints.append(last)
        }
        
        // Build the path
        guard let first = interpolatedPoints.first else { return Path() }
        path.move(to: first)
        for p in interpolatedPoints.dropFirst() {
            path.addLine(to: p)
        }
        
        return path
    }
    
    // MARK: - Layout Constants
    private let xAxisHeight: CGFloat = 14     // Height for X-axis timeframe label
    private let chartPadding: CGFloat = 12    // Internal chart padding
    
    /// Accent color for "tech" UI chrome — adapts to direction but with a cool tint
    private var techAccent: Color {
        switch direction {
        case .bullish: return Color(red: 0.0, green: 0.85, blue: 0.55)   // cyber green
        case .bearish: return Color(red: 0.95, green: 0.25, blue: 0.30)  // vivid red
        case .neutral: return BrandColors.goldBase
        }
    }
    
    /// Pulse animation for target beacon
    @State private var targetPulse: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            // Calculate chart area dimensions (no Y-axis labels - price shown above chart)
            let chartAreaWidth = w - chartPadding * 2
            let chartAreaHeight = h - xAxisHeight - chartPadding * 2
            let chartOriginX = chartPadding
            let chartOriginY = chartPadding
            
            ZStack(alignment: .topLeading) {
                // ── BACKGROUND: Deep layered glass with subtle grid ──
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isDark
                            ? LinearGradient(
                                colors: [
                                    Color(red: 0.06, green: 0.07, blue: 0.10),
                                    Color(red: 0.04, green: 0.04, blue: 0.07)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                            : LinearGradient(
                                colors: [
                                    Color(white: 0.97),
                                    Color(white: 0.94)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                    )
                    .overlay(
                        // Inner highlight rim — glass edge effect
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: isDark
                                        ? [Color.white.opacity(0.10), Color.white.opacity(0.02)]
                                        : [Color.black.opacity(0.06), Color.black.opacity(0.02)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    )
                
                if let data = preparedData {
                    // CONSISTENCY FIX: Use predictedPrice directly — it is ALREADY adjusted
                    // to the live price by the parent view (displayPredictedPrice).
                    // Previously, the chart recalculated the adjustment using livePrice/sparklineLastPrice,
                    // which produced a DIFFERENT target than the header card when these sources diverged.
                    let adjustedPredictedPrice = predictedPrice
                    
                    // Use the sparkline's last price for chart positioning reference
                    let sparklineLastPrice = data.last ?? currentPrice
                    let actualCurrentPrice = livePrice ?? sparklineLastPrice
                    
                    // Percentage change for the badge (from the passed-in prices, already consistent)
                    let originalPercentChange = currentPrice > 0 ? (predictedPrice - currentPrice) / currentPrice : 0
                    
                    // === Y-AXIS SCALING (includes both historical data AND prediction target) ===
                    // Include prediction target so the chart properly shows the full range
                    // FIX v28: Also include actualCurrentPrice in range so the "NOW" marker
                    // sits at the correct position even when sparkline last != live price.
                    let historicalMin = data.min() ?? actualCurrentPrice * 0.95
                    let historicalMax = data.max() ?? actualCurrentPrice * 1.05
                    
                    // Include predicted price AND live price in range calculation for visual coherence
                    let dataMin = min(min(historicalMin, adjustedPredictedPrice), actualCurrentPrice)
                    let dataMax = max(max(historicalMax, adjustedPredictedPrice), actualCurrentPrice)
                    
                    // Ensure minimum visual range (at least 2% of current price) to prevent flat charts
                    let minRange = actualCurrentPrice * 0.02
                    let rawRange = dataMax - dataMin
                    let dataRange = max(rawRange, minRange)
                    
                    // Add 15% padding to the range for visual breathing room
                    let yAxisPadding = dataRange * 0.15
                    let yAxisMin = dataMin - yAxisPadding
                    let yAxisMax = dataMax + yAxisPadding
                    let yAxisRange = max(yAxisMax - yAxisMin, minRange)
                    
                    // Historical section dimensions within chart area
                    let histWidth = chartAreaWidth * historicalWidthRatio
                    
                    // Helper to convert price to Y coordinate
                    let priceToY: (Double) -> CGFloat = { price in
                        let norm = (price - yAxisMin) / yAxisRange
                        return chartOriginY + chartAreaHeight * (1 - CGFloat(norm))
                    }
                    
                    // Calculate last historical point position (end of sparkline data)
                    let lastSparkValue = data.last ?? actualCurrentPrice
                    let lastSparkY = priceToY(lastSparkValue)
                    let lastSparkX = chartOriginX + histWidth
                    let lastHistPoint = CGPoint(x: lastSparkX, y: lastSparkY)
                    
                    // FIX v28: Bridge point for smooth history-to-forecast transition.
                    // When the sparkline's last price differs from the live price, use the
                    // live price as the starting point for the prediction line. This prevents
                    // a visible discontinuity/jump at the junction between historical and forecast.
                    let predStartY = priceToY(actualCurrentPrice)
                    let predStartPoint = CGPoint(x: lastSparkX, y: predStartY)
                    
                    // Calculate prediction target Y
                    let basePredTargetY = priceToY(adjustedPredictedPrice)
                    let predEndX = w - chartPadding - 6
                    
                    // Check if neutral prediction
                    let isNeutral = direction == .neutral
                    
                    // FIX v28: Use a proportional minimum slope (3% of chart height) instead of
                    // a hard 12pt value. The old 12pt minimum grossly exaggerated small predicted
                    // moves, making the chart look inaccurate vs. the displayed target price.
                    // 3% ensures visible directionality without distorting the price scale.
                    let minVisualSlope: CGFloat = chartAreaHeight * 0.03
                    
                    let predTargetY: CGFloat = {
                        // For neutral: still show the ACTUAL target price on the chart.
                        // Previously neutral forced a flat line, contradicting the displayed target.
                        // Only force truly flat if the predicted price equals current price.
                        if isNeutral {
                            // Use the real target Y — if the prediction has a target that differs
                            // from current, the chart should reflect that even for "neutral" direction.
                            // Only force flat if the target is essentially the same as current price.
                            let priceDelta = abs(adjustedPredictedPrice - (livePrice ?? sparklineLastPrice))
                            let threshold = (livePrice ?? sparklineLastPrice) * 0.001 // 0.1% dead zone
                            if priceDelta < threshold {
                                return predStartPoint.y // Truly flat — prices are effectively equal
                            }
                            // Otherwise show the real target, but no minimum slope enforcement
                            return max(chartOriginY + 8, min(chartOriginY + chartAreaHeight - 8, basePredTargetY))
                        }
                        
                        // FIX v28: Reference predStartPoint (live price) for slope enforcement,
                        // not lastHistPoint (sparkline last). This ensures the minimum slope is
                        // relative to the actual current price, not stale sparkline data.
                        if direction == .bullish {
                            let minUpY = predStartPoint.y - minVisualSlope
                            let targetY = min(basePredTargetY, minUpY)
                            return max(chartOriginY + 8, targetY)
                        } else {
                            let minDownY = predStartPoint.y + minVisualSlope
                            let targetY = max(basePredTargetY, minDownY)
                            return min(chartOriginY + chartAreaHeight - 8, targetY)
                        }
                    }()
                    
                    // ── GRID: Fine tech-style grid with subtle accent tint ──
                    // 5 horizontal lines for denser grid feel
                    ForEach(0..<5, id: \.self) { i in
                        let gridY = chartOriginY + chartAreaHeight * CGFloat(i) / 4.0
                        Path { path in
                            path.move(to: CGPoint(x: chartOriginX, y: gridY))
                            path.addLine(to: CGPoint(x: w - chartPadding, y: gridY))
                        }
                        .stroke(
                            isDark ? Color.white.opacity(i == 2 ? 0.06 : 0.03) : Color.black.opacity(i == 2 ? 0.06 : 0.03),
                            style: StrokeStyle(lineWidth: 0.5, dash: [1, 3])
                        )
                    }
                    
                    // ── ZONE LABELS: Premium pill badges ──
                    // Historical zone badge
                    Text("HISTORICAL")
                        .font(.system(size: 5.5, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(historicalColor.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(historicalColor.opacity(isDark ? 0.10 : 0.06))
                                .overlay(Capsule().stroke(historicalColor.opacity(0.15), lineWidth: 0.5))
                        )
                        .position(x: chartOriginX + 28, y: chartOriginY + 9)
                    
                    // Prediction zone badge
                    Text("AI FORECAST")
                        .font(.system(size: 5.5, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(predictionColor.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(predictionColor.opacity(isDark ? 0.10 : 0.06))
                                .overlay(Capsule().stroke(predictionColor.opacity(0.15), lineWidth: 0.5))
                        )
                        .position(x: lastSparkX + 28, y: chartOriginY + 9)
                    
                    // === HISTORICAL SECTION ===
                    // Build points from sparkline data using unified Y scaling
                    // Use ALL data points for maximum detail (like watchlist sparklines)
                    let historicalPoints: [CGPoint] = {
                        guard data.count >= 2 else { return [] }
                        let step = histWidth / CGFloat(data.count - 1)
                        return data.enumerated().map { idx, price in
                            CGPoint(x: chartOriginX + CGFloat(idx) * step, y: priceToY(price))
                        }
                    }()

                    // Seam alignment: bridge the final historical point to the live "NOW" Y.
                    // This removes the visual disconnect between history and forecast when the
                    // latest live tick differs from the last cached sparkline point.
                    let bridgedHistoricalPoints: [CGPoint] = {
                        guard !historicalPoints.isEmpty else { return historicalPoints }
                        var out = historicalPoints
                        // Blend the final few points toward NOW to avoid a harsh vertical snap
                        // at the history/forecast seam while preserving overall historical shape.
                        let blendCount = min(5, out.count)
                        if blendCount >= 2 {
                            let startIndex = out.count - blendCount
                            let startY = out[startIndex].y
                            for i in 0..<blendCount {
                                let t = CGFloat(i) / CGFloat(blendCount - 1) // 0...1
                                let idx = startIndex + i
                                out[idx].y = startY + (predStartPoint.y - startY) * t
                            }
                        } else {
                            out[out.count - 1].y = predStartPoint.y
                        }
                        return out
                    }()
                    // ── HISTORICAL SECTION: Match watchlist/market styling ──
                    if !bridgedHistoricalPoints.isEmpty {
                        let historicalPath = smoothPath(
                            through: bridgedHistoricalPoints,
                            samplesPerSegment: SparklineConsistency.listSmoothSamplesPerSegment
                        )
                        // Area fill — deeper gradient with two color stops
                        Path { path in
                            guard let first = bridgedHistoricalPoints.first, let last = bridgedHistoricalPoints.last else { return }
                            path.move(to: CGPoint(x: first.x, y: chartOriginY + chartAreaHeight))
                            path.addLine(to: first)
                            for pt in bridgedHistoricalPoints.dropFirst() {
                                path.addLine(to: pt)
                            }
                            path.addLine(to: CGPoint(x: last.x, y: chartOriginY + chartAreaHeight))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: historicalColor.opacity(isDark ? SparklineConsistency.listFillOpacity * 0.52 : SparklineConsistency.listFillOpacity * 0.34), location: 0.0),
                                    .init(color: historicalColor.opacity(isDark ? 0.06 : 0.04), location: 0.5),
                                    .init(color: historicalColor.opacity(0.0), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        
                        // Single subtle glow layer (avoid doubled historical line look)
                        historicalPath
                        .stroke(
                            historicalColor.opacity(
                                isDark
                                    ? SparklineConsistency.listGlowOpacity * 0.90
                                    : SparklineConsistency.listGlowOpacity * 0.66
                            ),
                            style: StrokeStyle(
                                lineWidth: SparklineConsistency.listGlowLineWidth * 0.92,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        
                        // Main crisp line (same weight profile as list sparklines)
                        historicalPath
                        .stroke(
                            historicalColor,
                            style: StrokeStyle(
                                lineWidth: isDark ? SparklineConsistency.listLineWidth : SparklineConsistency.listLineWidth + 0.1,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                    
                    // ── PREDICTION ZONE: Gradient backdrop with subtle scan-line effect ──
                    
                    // Base zone fill
                    Path { path in
                        path.move(to: CGPoint(x: lastHistPoint.x, y: chartOriginY))
                        path.addLine(to: CGPoint(x: w - chartPadding, y: chartOriginY))
                        path.addLine(to: CGPoint(x: w - chartPadding, y: chartOriginY + chartAreaHeight))
                        path.addLine(to: CGPoint(x: lastHistPoint.x, y: chartOriginY + chartAreaHeight))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                predictionColor.opacity(isDark ? 0.10 : 0.06),
                                predictionColor.opacity(isDark ? 0.04 : 0.02)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(animationProgress)
                    
                    // Generate projected path points — always use predTargetY (now handles neutral correctly)
                    // FIX v28: Start from predStartPoint (live price position) for accurate junction
                    let targetPoint = CGPoint(x: predEndX, y: predTargetY)
                    let projectedPoints = generateProjectedPath(from: predStartPoint, to: targetPoint, segments: 16)
                    
                    // Prediction area fill — richer 3-stop gradient
                    Path { path in
                        guard let first = projectedPoints.first, let last = projectedPoints.last else { return }
                        path.move(to: CGPoint(x: first.x, y: chartOriginY + chartAreaHeight))
                        path.addLine(to: first)
                        for pt in projectedPoints.dropFirst() {
                            path.addLine(to: pt)
                        }
                        path.addLine(to: CGPoint(x: last.x, y: chartOriginY + chartAreaHeight))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: predictionColor.opacity(isDark ? 0.34 : 0.24), location: 0.0),
                                .init(color: predictionColor.opacity(isDark ? 0.10 : 0.06), location: 0.55),
                                .init(color: predictionColor.opacity(0.0), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(animationProgress)
                    
                    // Projected path line with layered neon glow
                    let projectedPath = smoothPath(
                        through: projectedPoints,
                        samplesPerSegment: SparklineConsistency.listSmoothSamplesPerSegment
                    )
                    
                    // Layer 1: Wide ambient glow
                    projectedPath
                        .stroke(predictionColor.opacity(isDark ? 0.24 : 0.20), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                        .opacity(animationProgress * 0.30)
                    
                    // Layer 2: Core neon glow
                    projectedPath
                        .stroke(predictionColor.opacity(isDark ? 0.46 : 0.40), style: StrokeStyle(lineWidth: 3.8, lineCap: .round, lineJoin: .round))
                        .opacity(animationProgress * 0.52)
                    
                    // Layer 3: Bright white-ish core bloom
                    projectedPath
                        .stroke(Color.white.opacity(isDark ? 0.11 : 0.08), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .opacity(animationProgress * 0.40)
                    
                    // Layer 4: Crisp dashed main line
                    projectedPath
                        .trim(from: 0, to: animationProgress)
                        .stroke(
                            predictionColor,
                            style: StrokeStyle(lineWidth: isDark ? 2.2 : 2.4, lineCap: .round, lineJoin: .round, dash: [7, 4])
                        )
                    
                    // === PERCENTAGE CHANGE BADGE ===
                    // Position closer to the NOW marker (30% into prediction zone) to avoid overlap with target price
                    let percentChange = originalPercentChange * 100
                    let badgeMidX = predStartPoint.x + (predEndX - predStartPoint.x) * 0.30
                    // Smart positioning: above the line when there's room, below when line is near top
                    let badgeMidY: CGFloat = {
                        // Get the Y position at 30% along the prediction path
                        let progressY = predStartPoint.y + (predTargetY - predStartPoint.y) * 0.30
                        // Check if the line is in the upper third of the chart
                        let upperThreshold = chartOriginY + chartAreaHeight * 0.35
                        if progressY < upperThreshold {
                            // Line is near the top - place badge BELOW the line for readability
                            let idealY = progressY + 16
                            return max(chartOriginY + 8, min(chartOriginY + chartAreaHeight - 8, idealY))
                        } else {
                            // Default: place above the line
                            let idealY = progressY - 14
                            return max(chartOriginY + 8, min(chartOriginY + chartAreaHeight - 8, idealY))
                        }
                    }()
                    
                    Text(String(format: "%@%.2f%%", percentChange >= 0 ? "+" : "", percentChange))
                        .font(.system(size: 8, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [predictionColor, predictionColor.opacity(0.75)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.20), Color.clear],
                                                startPoint: .top,
                                                endPoint: .center
                                            )
                                        )
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
                                )
                        )
                        .position(x: badgeMidX, y: badgeMidY)
                        .opacity(animationProgress)
                    
                    // ── ZONE DIVIDER: Accent-tinted scan line with fade-out edges ──
                    Path { path in
                        path.move(to: CGPoint(x: lastHistPoint.x, y: chartOriginY))
                        path.addLine(to: CGPoint(x: lastHistPoint.x, y: chartOriginY + chartAreaHeight))
                    }
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: techAccent.opacity(0.0), location: 0.0),
                                .init(color: techAccent.opacity(isDark ? 0.35 : 0.22), location: 0.35),
                                .init(color: techAccent.opacity(isDark ? 0.45 : 0.28), location: 0.50),
                                .init(color: techAccent.opacity(isDark ? 0.35 : 0.22), location: 0.65),
                                .init(color: techAccent.opacity(0.0), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.2
                    )
                    .opacity(animationProgress)
                    
                    // ── NOW MARKER: Premium branded dot with glow ring + smart time label ──
                    // FIX v28: Position NOW marker at live price (predStartPoint), not sparkline last
                    let nowLabelAbove = predStartPoint.y > chartOriginY + 22
                    
                    ZStack {
                        // Outer pulse ring (subtle)
                        Circle()
                            .stroke(techAccent.opacity(0.20), lineWidth: 1)
                            .frame(width: 18, height: 18)
                        
                        // Core glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [techAccent.opacity(0.45), techAccent.opacity(0.0)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 10
                                )
                            )
                            .frame(width: 20, height: 20)
                        
                        // Crisp white-rimmed dot
                        Circle()
                            .fill(techAccent)
                            .frame(width: 7, height: 7)
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1.2)
                            .frame(width: 7, height: 7)
                        
                        // Smart time label badge
                        Text(timeLabel.uppercased())
                            .font(.system(size: 6, weight: .heavy, design: .rounded))
                            .tracking(0.3)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [techAccent, techAccent.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                    )
                            )
                            .offset(y: nowLabelAbove ? -14 : 14)
                    }
                    .position(predStartPoint)
                    .opacity(animationProgress)
                    
                    // ── TARGET MARKER: Beacon with animated pulse ring + premium label ──
                    let targetMarkerY = predTargetY
                    let safeTargetX = predEndX
                    
                    ZStack {
                        // Animated pulse ring — radiates outward
                        Circle()
                            .stroke(predictionColor.opacity(targetPulse ? 0.0 : 0.30), lineWidth: 1)
                            .frame(width: targetPulse ? 28 : 14, height: targetPulse ? 28 : 14)
                            .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: targetPulse)
                        
                        // Ambient glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [predictionColor.opacity(0.40), predictionColor.opacity(0.0)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 14
                                )
                            )
                            .frame(width: 28, height: 28)
                        
                        // Crosshair ring
                        Circle()
                            .stroke(predictionColor.opacity(0.50), lineWidth: 1)
                            .frame(width: 16, height: 16)
                        
                        // Bright core dot
                        Circle()
                            .fill(predictionColor)
                            .frame(width: 8, height: 8)
                        Circle()
                            .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                        
                        // Target price label — premium gradient badge
                        Text(formatPriceCompact(adjustedPredictedPrice))
                            .font(.system(size: 9, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [predictionColor, predictionColor.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(0.18), Color.clear],
                                                    startPoint: .top,
                                                    endPoint: .center
                                                )
                                            )
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                            .offset(
                                x: {
                                    // Use actual Y relationship (target vs current) for position decisions
                                    let targetIsBelow = targetMarkerY > predStartPoint.y // Target lower on screen = bearish
                                    let isInLowerArea = targetMarkerY > chartOriginY + chartAreaHeight - 40
                                    // For downward targets in lower chart area, position label to the LEFT
                                    // to avoid overlap with zone labels and X-axis timeframe labels
                                    if targetIsBelow && isInLowerArea {
                                        return -38  // Position to the left of the target dot
                                    }
                                    // Default: slight left offset when near right edge
                                    return predEndX > w - 50 ? -28 : 0
                                }(),
                                y: {
                                    let targetIsBelow = targetMarkerY > predStartPoint.y
                                    let isInLowerArea = targetMarkerY > chartOriginY + chartAreaHeight - 40
                                    // More generous upper area threshold - 35% of chart height
                                    let isInUpperArea = targetMarkerY < chartOriginY + chartAreaHeight * 0.35
                                    // Downward target in lower area: label to the left, no vertical offset
                                    if targetIsBelow && isInLowerArea {
                                        return 0
                                    }
                                    // When target is in the upper area, always place label below
                                    // This ensures readability when chart line trends up near the top
                                    if isInUpperArea {
                                        return 16  // Below the dot
                                    }
                                    // Upward target (or neutral-up) in mid/lower area: label above
                                    if !targetIsBelow {
                                        return -16  // Above the dot
                                    }
                                    // Downward target in mid area: label below
                                    return 16
                                }()
                            )
                    }
                    .position(x: safeTargetX, y: targetMarkerY)
                    .opacity(animationProgress)
                    
                    // ── X-AXIS: Styled timeframe indicators ──
                    HStack {
                        Text(historicalLabel)
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .tracking(0.4)
                            .foregroundColor(isDark ? Color.white.opacity(0.30) : Color.black.opacity(0.30))
                        
                        Spacer()
                        
                        HStack(spacing: 2) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 5, weight: .bold))
                            Text("+\(timeframe.displayName)")
                                .font(.system(size: 7, weight: .bold, design: .rounded))
                                .tracking(0.4)
                        }
                        .foregroundColor(predictionColor.opacity(0.55))
                    }
                    .padding(.horizontal, 4)
                    .frame(width: chartAreaWidth)
                    .offset(x: chartOriginX, y: chartOriginY + chartAreaHeight + 2)
                    
                } else {
                    // No data fallback - show chart unavailable state
                    VStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 18))
                            .foregroundColor(DS.Adaptive.textTertiary.opacity(0.5))
                        Text("Chart data unavailable")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear {
                // ORIENTATION FIX: Only animate on true initial appear, not on view recreation
                // On recreation (orientation change), animationProgress defaults to 1 so chart stays visible
                if isInitialAppear && preparedData != nil {
                    // Reset for entrance animation only on first appearance
                    animationProgress = 0
                    hasAnimated = false
                    isInitialAppear = false
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.5)) {
                            animationProgress = 1
                        }
                        hasAnimated = true
                    }
                }
                // Start target beacon pulse
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    targetPulse = true
                }
            }
            .onChange(of: sparklineData?.count ?? 0) { _, newCount in
                guard newCount >= 2, preparedData != nil else { return }
                guard animationProgress < 1 || !hasAnimated || isInitialAppear else { return }
                isInitialAppear = false
                animationProgress = 0
                hasAnimated = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        animationProgress = 1
                    }
                    hasAnimated = true
                }
            }
            .onChange(of: geo.size.width) { _, newWidth in
                // ORIENTATION FIX: When width changes significantly (rotation), ensure chart stays visible
                // Don't re-animate, just ensure animationProgress is 1
                if abs(newWidth - lastKnownWidth) > 50 && lastKnownWidth > 0 {
                    // Orientation change detected - keep chart fully visible
                    animationProgress = 1
                    hasAnimated = true
                }
                lastKnownWidth = newWidth
            }
        }
        // Note: Height should be set by the parent view via .frame(height:)
        // Default minimum height if not specified externally
        .frame(minHeight: 100)
    }
    
}

// MARK: - Forecast Chart View (for detail page)

struct ForecastChartView: View {
    let currentPrice: Double
    let predictedPrice: Double
    let lowPrice: Double
    let highPrice: Double
    let direction: PredictionDirection
    let targetDate: Date
    let sparklineData: [Double]
    
    /// When the prediction was generated (nil shows "Now" as fallback)
    var generatedAt: Date? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    
    // ORIENTATION FIX: Default to true to prevent broken state on view recreation during rotation
    @State private var animateChart: Bool = true
    @State private var selectedPoint: Int?
    @State private var isInitialAppear: Bool = true
    @State private var lastKnownWidth: CGFloat = 0
    
    /// Timer-driven refresh so the label updates live
    @State private var timeLabelTick: UUID = UUID()
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Smart time label
    private var timeLabel: String {
        _ = timeLabelTick
        return predictionTimeLabel(for: generatedAt)
    }
    
    // Combine historical data with prediction
    private var chartData: [Double] {
        var data = sparklineData
        // Add prediction points (interpolated path to target)
        let steps = 10
        let priceStep = (predictedPrice - currentPrice) / Double(steps)
        for i in 1...steps {
            data.append(currentPrice + priceStep * Double(i))
        }
        return data
    }
    
    private var historicalCount: Int { sparklineData.count }
    
    var body: some View {
        VStack(spacing: 0) {
            // Chart area
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let data = chartData
                let minPrice = min(data.min() ?? lowPrice, lowPrice) * 0.995
                let maxPrice = max(data.max() ?? highPrice, highPrice) * 1.005
                let priceRange = maxPrice - minPrice
                
                ZStack {
                    // Grid lines (subtle dashed)
                    VStack(spacing: 0) {
                        // PERFORMANCE FIX: Added explicit id to prevent SwiftUI warnings
                        ForEach(0..<4, id: \.self) { i in
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: 0))
                                path.addLine(to: CGPoint(x: width, y: 0))
                            }
                            // LIGHT MODE FIX: Adaptive grid lines
                            .stroke(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            if i < 3 { Spacer() }
                        }
                    }
                    
                    // Gradient fill under historical line (HomeLineChart style)
                    if animateChart && !sparklineData.isEmpty {
                        Path { path in
                            guard let firstPrice = sparklineData.first else { return }
                            let firstX: CGFloat = 0
                            let firstY = height * (1 - CGFloat((firstPrice - minPrice) / priceRange))
                            
                            path.move(to: CGPoint(x: firstX, y: height))
                            path.addLine(to: CGPoint(x: firstX, y: firstY))
                            
                            for (index, price) in sparklineData.enumerated() {
                                let x = width * CGFloat(index) / CGFloat(data.count - 1)
                                let y = height * (1 - CGFloat((price - minPrice) / priceRange))
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                            
                            let lastX = width * CGFloat(sparklineData.count - 1) / CGFloat(data.count - 1)
                            path.addLine(to: CGPoint(x: lastX, y: height))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [DS.Adaptive.textSecondary.opacity(0.18), DS.Adaptive.textSecondary.opacity(0.02)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    
                    // Confidence band (shaded area for prediction zone)
                    if animateChart {
                        Path { path in
                            let startX = width * CGFloat(historicalCount) / CGFloat(data.count)
                            let lowY = height * (1 - CGFloat((lowPrice - minPrice) / priceRange))
                            let highY = height * (1 - CGFloat((highPrice - minPrice) / priceRange))
                            
                            path.move(to: CGPoint(x: startX, y: lowY))
                            path.addLine(to: CGPoint(x: width, y: lowY))
                            path.addLine(to: CGPoint(x: width, y: highY))
                            path.addLine(to: CGPoint(x: startX, y: highY))
                            path.closeSubpath()
                        }
                        .fill(direction.color.opacity(0.12))
                    }
                    
                    // Historical line glow (subtle)
                    Path { path in
                        for (index, price) in sparklineData.enumerated() {
                            let x = width * CGFloat(index) / CGFloat(data.count - 1)
                            let y = height * (1 - CGFloat((price - minPrice) / priceRange))
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .trim(from: 0, to: animateChart ? 1 : 0)
                    .stroke(DS.Adaptive.textSecondary.opacity(0.3), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .opacity(0.4)
                    
                    // Historical price line
                    Path { path in
                        for (index, price) in sparklineData.enumerated() {
                            let x = width * CGFloat(index) / CGFloat(data.count - 1)
                            let y = height * (1 - CGFloat((price - minPrice) / priceRange))
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .trim(from: 0, to: animateChart ? 1 : 0)
                    .stroke(
                        DS.Adaptive.textSecondary,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    
                    // Prediction line (dashed)
                    if animateChart {
                        Path { path in
                            let startIndex = historicalCount - 1
                            for i in startIndex..<data.count {
                                let x = width * CGFloat(i) / CGFloat(data.count - 1)
                                let y = height * (1 - CGFloat((data[i] - minPrice) / priceRange))
                                
                                if i == startIndex {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(
                            direction.color,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [6, 4])
                        )
                    }
                    
                    // Current price marker
                    if animateChart {
                        let currentX = width * CGFloat(historicalCount - 1) / CGFloat(data.count - 1)
                        let currentY = height * (1 - CGFloat((currentPrice - minPrice) / priceRange))
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                            .position(x: currentX, y: currentY)
                        
                        // Time label: "Now" for first 5min, then relative time
                        Text(timeLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .position(x: currentX, y: height + 12)
                    }
                    
                    // Target price marker
                    if animateChart {
                        let targetY = height * (1 - CGFloat((predictedPrice - minPrice) / priceRange))
                        
                        // Determine icon from actual price direction, not just classification
                        let targetIcon: String = {
                            if predictedPrice > currentPrice * 1.001 {
                                return "arrow.up"
                            } else if predictedPrice < currentPrice * 0.999 {
                                return "arrow.down"
                            } else {
                                return "arrow.right"
                            }
                        }()
                        
                        ZStack {
                            Circle()
                                .fill(direction.color)
                                .frame(width: 14, height: 14)
                            
                            Image(systemName: targetIcon)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .position(x: width - 7, y: targetY)
                    }
                }
            }
            .frame(height: 180)
            .padding(.bottom, 20)
            
            // Price labels
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(formatPrice(currentPrice))
                        .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Arrow
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Target")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(formatPrice(predictedPrice))
                        .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(direction.color)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        )
        .onAppear {
            // ORIENTATION FIX: Only animate on true initial appear, not on view recreation
            if isInitialAppear && !sparklineData.isEmpty {
                animateChart = false  // Start hidden for entrance animation
                isInitialAppear = false
                
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeOut(duration: 1.0)) {
                        animateChart = true
                    }
                }
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            // Refresh the time label every minute
            timeLabelTick = UUID()
        }
    }
    
    private func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.maximumFractionDigits = value < 1 ? 4 : (value < 100 ? 2 : 0)
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - Confidence Ring Gauge (Modern Semi-Arc Design)

struct ConfidenceRingGauge: View {
    let score: Int
    let confidence: PredictionConfidence
    let size: CGFloat
    
    @State private var animatedProgress: Double = 0
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var progress: Double {
        Double(min(100, max(0, score))) / 100.0
    }
    
    private var strokeWidth: CGFloat { size * 0.09 }
    
    // Semi-arc spans 180 degrees (bottom half)
    private let startAngle: Double = 135  // Start at bottom-left
    private let endAngle: Double = 405    // End at bottom-right (270 degree arc)
    private let arcSpan: Double = 270     // Total arc degrees
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Background arc track - LIGHT MODE FIX: Use black opacity in light mode
                Circle()
                    .trim(from: 0, to: arcSpan / 360)
                    .stroke(
                        LinearGradient(
                            colors: isDark
                                ? [Color.white.opacity(0.06), Color.white.opacity(0.03)]
                                : [Color.black.opacity(0.08), Color.black.opacity(0.04)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(startAngle))
                
                // Progress arc
                Circle()
                    .trim(from: 0, to: animatedProgress * (arcSpan / 360))
                    .stroke(
                        LinearGradient(
                            colors: progressGradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(startAngle))
                
                // Center content
                VStack(spacing: 1) {
                    Text("\(score)")
                        .font(.system(size: size * 0.28, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(confidence.displayName)
                        .font(.system(size: size * 0.11, weight: .semibold))
                        .foregroundColor(confidence.color)
                    
                    Text("Confidence")
                        .font(.system(size: size * 0.08, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .offset(y: size * 0.04)
            }
            .frame(width: size, height: size)
        }
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                withAnimation(GaugeMotionProfile.springEmphasis) {
                    animatedProgress = progress
                }
            }
        }
        .onChange(of: score) { _, newScore in
            let newProgress = GaugeMotionProfile.clampUnit(Double(newScore) / 100.0)
            withAnimation(GaugeMotionProfile.springEmphasis) {
                animatedProgress = newProgress
            }
        }
    }
    
    private var endProgressAngle: Double {
        startAngle + (animatedProgress * arcSpan)
    }
    
    private var progressGradientColors: [Color] {
        switch confidence {
        case .low:
            return [Color.red.opacity(0.7), Color.red, Color.red]
        case .medium:
            return [Color.yellow.opacity(0.7), Color.yellow, Color.orange]
        case .high:
            return [Color.green.opacity(0.7), Color.green, Color(red: 0.2, green: 0.9, blue: 0.4)]
        }
    }
}

// MARK: - Premium Prediction Hero Card

struct PredictionHeroCard: View {
    let prediction: AIPricePrediction
    let sparklineData: [Double]
    var coinIconUrl: URL?
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasAppeared = false
    @ObservedObject private var marketVM = MarketViewModel.shared
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Get the best available current price for display
    /// PRICE CONSISTENCY FIX: Prefer live market price so this view matches the home page card.
    private var displayCurrentPrice: Double {
        // 1. Try live price from MarketViewModel (matches home page behavior)
        if let coin = marketVM.allCoins.first(where: { $0.symbol.uppercased() == prediction.coinSymbol.uppercased() }),
           let livePrice = marketVM.bestPrice(for: coin.id), livePrice > 0 {
            return livePrice
        }
        if let livePrice = marketVM.bestPrice(forSymbol: prediction.coinSymbol), livePrice > 0 {
            return livePrice
        }
        // 2. Fall back to prediction's stored price
        if prediction.currentPrice > 0 && prediction.currentPrice.isFinite {
            return prediction.currentPrice
        }
        return prediction.currentPrice
    }
    
    /// Keep target price fixed for this prediction instance.
    private var displayPredictedPrice: Double {
        return prediction.predictedPrice
    }
    
    /// Keep prediction range fixed for this prediction instance.
    private var displayPredictedPriceLow: Double {
        prediction.predictedPriceLow
    }
    
    /// Keep prediction range fixed for this prediction instance.
    private var displayPredictedPriceHigh: Double {
        prediction.predictedPriceHigh
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Top row: Coin info + Direction
            HStack(spacing: 14) {
                // Coin icon
                if let url = coinIconUrl {
                    CoinImageView(symbol: prediction.coinSymbol, url: url, size: 48)
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(prediction.direction.color.opacity(0.5), lineWidth: 2.5)
                        )
                } else {
                    Circle()
                        .fill(prediction.direction.color.opacity(0.15))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(prediction.coinSymbol.prefix(2))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(prediction.direction.color)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(prediction.coinName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(prediction.coinSymbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                
                Spacer()
                
                // Large direction badge
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(prediction.direction.color.opacity(0.15))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: prediction.direction == .bullish ? "arrow.up" : (prediction.direction == .bearish ? "arrow.down" : "minus"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(prediction.direction.color)
                    }
                    
                    Text(prediction.direction.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(prediction.direction.color)
                }
            }
            
            // Forecast chart
            if !sparklineData.isEmpty {
                ForecastChartView(
                    currentPrice: displayCurrentPrice,
                    predictedPrice: displayPredictedPrice,
                    lowPrice: displayPredictedPriceLow,
                    highPrice: displayPredictedPriceHigh,
                    direction: prediction.direction,
                    targetDate: prediction.targetDate,
                    sparklineData: sparklineData,
                    generatedAt: prediction.generatedAt
                )
            }
            
            // Price display row
            HStack(alignment: .center, spacing: 16) {
                // Current price
                VStack(alignment: .leading, spacing: 4) {
                    Text("BASE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .tracking(0.8)
                    
                    Text(MarketFormat.price(displayCurrentPrice))
                        .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                // Arrow with change
                VStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text(prediction.formattedPriceChange)
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundColor(prediction.direction.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(prediction.direction.color.opacity(0.15))
                        )
                }
                
                // Target price
                VStack(alignment: .trailing, spacing: 4) {
                    Text("TARGET")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .tracking(0.8)
                    
                    Text(MarketFormat.price(displayPredictedPrice))
                        .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(prediction.direction.color)
                }
            }
            
            // Confidence gauge and countdown row
            HStack(spacing: 20) {
                // Confidence ring
                ConfidenceRingGauge(
                    score: prediction.confidenceScore,
                    confidence: prediction.confidence,
                    size: 90
                )
                
                Spacer()
                
                // Countdown
                VStack(alignment: .trailing, spacing: 8) {
                    Text(prediction.formattedTargetDate)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // Compact countdown
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                        Text(formattedTimeRemaining)
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    }
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(DS.Adaptive.chipBackground)
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            prediction.direction.color.opacity(isDark ? 0.08 : 0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            prediction.direction.color.opacity(0.3),
                            prediction.direction.color.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .scaleEffect(hasAppeared ? 1 : 0.95)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    hasAppeared = true
                }
            }
        }
    }
    
    private var formattedTimeRemaining: String {
        let remaining = prediction.timeRemaining
        if remaining <= 0 { return "Expired" }
        
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        
        if days > 0 {
            return "\(days)d \(hours)h remaining"
        } else {
            let minutes = (Int(remaining) % 3600) / 60
            return "\(hours)h \(minutes)m remaining"
        }
    }
}

// MARK: - Probability Ring Component

/// Visual ring showing probability for a specific threshold with fill animation
private struct ProbabilityRing: View {
    let threshold: String
    let probability: Double
    let color: Color
    var isBestRisk: Bool = false  // Highlight if this has best risk/reward
    
    @State private var animatedProgress: CGFloat = 0
    @State private var hasAppeared: Bool = false
    
    var body: some View {
        VStack(spacing: 6) {
            // Circular progress ring with animation
            ZStack {
                // Background ring
                Circle()
                    .stroke(
                        color.opacity(0.15),
                        lineWidth: 6
                    )
                
                // Animated progress ring
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                
                // Glow effect for best risk/reward
                if isBestRisk {
                    Circle()
                        .trim(from: 0, to: animatedProgress)
                        .stroke(
                            color.opacity(0.4),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                
                // Percentage text with fade-in
                Text("\(Int(probability))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .opacity(hasAppeared ? 1 : 0)
            }
            .frame(width: 56, height: 56)
            
            // Threshold label
            Text(threshold)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            // Animate the ring fill on appear
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                animatedProgress = CGFloat(probability / 100)
            }
            withAnimation(.easeIn(duration: 0.3).delay(0.5)) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AIPredictionDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let samplePrediction = AIPricePrediction(
            id: "test",
            coinSymbol: "BTC",
            coinName: "Bitcoin",
            currentPrice: 75000,
            predictedPriceChange: 8.5,
            predictedPriceLow: 72000,
            predictedPriceHigh: 105000,
            confidenceScore: 72,
            confidence: .medium,
            direction: .bullish,
            timeframe: .week,
            drivers: [
                PredictionDriver(name: "RSI(14)", value: "42.3", signal: "neutral"),
                PredictionDriver(name: "MACD", value: "Bullish crossover", signal: "bullish"),
                PredictionDriver(name: "Fear & Greed", value: "65 - Greed", signal: "bearish"),
                PredictionDriver(name: "MA Alignment", value: "Bullish partial", signal: "bullish")
            ],
            analysis: "Bitcoin shows bullish momentum with RSI indicating room for upside. The recent MACD crossover suggests continued buying pressure. However, elevated Fear & Greed levels warrant caution as the market may be overheating.",
            generatedAt: Date(),
            probabilityUp2Pct: 68,
            probabilityUp5Pct: 52,
            probabilityUp10Pct: 35,
            probabilityDown2Pct: 28,
            probabilityDown5Pct: 18,
            probabilityDown10Pct: 8,
            directionalScore: 42
        )
        
        AIPredictionDetailView(prediction: samplePrediction)
            .preferredColorScheme(.dark)
    }
}
#endif
