import SwiftUI
import UIKit
import Combine
import QuartzCore

// MARK: - DataUnavailableView

struct DataUnavailableView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textPrimary)
                .multilineTextAlignment(.center)
            Button(action: onRetry) {
                Text("Retry")
                    .font(.caption2)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(BrandColors.goldBase)
                    .cornerRadius(6)
                    .foregroundColor(.black)
            }
        }
    }
}
// MARK: - InlineErrorBanner
struct InlineErrorBanner: View {
    let message: String
    let onRetry: () -> Void
    let onUseDefault: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let onUseDefault = onUseDefault {
                        Button(action: onUseDefault) {
                            Text("Use CryptoSage AI")
                                .font(.caption2)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(DS.Adaptive.chipBackground)
                                .cornerRadius(6)
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                    }
                    Button(action: onRetry) {
                        Text("Retry")
                            .font(.caption2)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(BrandColors.goldBase)
                            .cornerRadius(6)
                            .foregroundColor(.black)
                    }
                }
            }
        }
        .padding(10)
        .background(DS.Adaptive.chipBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.Adaptive.strokeStrong, lineWidth: 0.6)
        )
        .cornerRadius(8)
    }
}

// MARK: - KeyFactorChip

/// Small chip displaying a key factor driving market sentiment
struct KeyFactorChip: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    private let gold = BrandColors.goldBase
    
    var body: some View {
        let isDark = colorScheme == .dark
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(isDark ? BrandColors.goldLight : BrandColors.goldDark)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                ZStack {
                    Capsule()
                        .fill(gold.opacity(isDark ? 0.08 : 0.05))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isDark ? 0.04 : 0.15), Color.clear],
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
                                ? [BrandColors.goldLight.opacity(0.40), BrandColors.goldBase.opacity(0.15)]
                                : [BrandColors.goldDark.opacity(0.30), BrandColors.goldBase.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isDark ? 0.8 : 1
                    )
            )
            .lineLimit(1)
    }
}

// MARK: - MarketSentimentView

struct MarketSentimentView: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    // PERFORMANCE FIX v8: Use shared singleton instead of creating new instance
    // FIX v23: Replaced @ObservedObject with computed singleton access + debounced refresh.
    // ExtendedFearGreedViewModel has 15+ @Published properties (isLoading, errorMessage, data,
    // liveAIObservation, firebaseSentiment*, fearGreedCommentary, marketBreadth, etc.)
    // With @ObservedObject, EVERY change to any of these forced a full re-render of the
    // entire sentiment section including the gauge animation, gradient backgrounds, and text.
    // Sentiment data updates every 30-60s — a 5s debounce is perfectly fine.
    private var vm: ExtendedFearGreedViewModel { ExtendedFearGreedViewModel.shared }
    @State private var sentimentTick: UInt = 0
    @State private var metricsTick: UInt = 0   // Separate tick for sub-metrics (Breadth/BTC24h/Vol)
    @State private var retryBackoff: TimeInterval = 2
    @State private var isFetching = false
    @State private var lastFetchAt: Date? = nil
    // FIX: Source picker overlay is rendered in HomeView (above ScrollView)
    // to avoid scroll clipping. Local @State drives button styling; VM drives HomeView overlay.
    @State private var showSourcePopover: Bool = false
    private var sourceButtonFrame: CGRect {
        get { vm.sourcePickerAnchorFrame }
        nonmutating set { vm.sourcePickerAnchorFrame = newValue }
    }
    @State private var isSwitchingSource: Bool = false
    @State private var showSentimentDetail: Bool = false
    @State private var lastObservedNowScore: Int? = nil
    @State private var lastObservedSource: SentimentSource = .derived
    @State private var nowScoreDelta: Int? = nil
    // PERFORMANCE FIX v10: Stabilized gauge value to prevent onChange warnings during initial load
    // This value only updates after the view has appeared, avoiding rapid value changes during init
    @State private var stabilizedGaugeValue: Double = 50  // Default neutral value
    @State private var hasStabilizedGaugeValue: Bool = false
    // PERFORMANCE FIX v20: Increased from 30s to 60s. The ViewModel's adaptive scheduler
    // already handles timely refreshes based on server hints (30s–1800s). This gate only
    // needs to prevent rapid View-level triggers (scenePhase, pull-to-refresh).
    private let minFetchInterval: TimeInterval = 60

    // Layout constants for gauge and right panel alignment
    private let gaugeHeight: CGFloat = 160
    private let rightColumnWidth: CGFloat = 110
    private let labelRowHeight: CGFloat = 14

    private let standardBadgeSize: CGFloat = 19
    private let alignedBadgeSize: CGFloat = 18

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = .current
        df.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return df
    }()

    private var separatorColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    private var gold: Color { BrandColors.goldBase }
    
    /// Whether the current source is CryptoSage AI (shows metrics instead of historical values)
    private var isCryptoSageAI: Bool {
        vm.selectedSource == .derived
    }
    
    /// Whether the sentiment data is recent enough to show a LIVE badge (< 15 min old)
    private var isDataFresh: Bool {
        guard let tsStr = vm.data.first?.timestamp,
              let ts = Double(tsStr) else { return false }
        let age = Date().timeIntervalSince(Date(timeIntervalSince1970: ts))
        return age < 900 // 15 minutes
    }

    private var timeframeRows: [(String, FearGreedData?)] {
        // For CryptoSage AI, we only show "Now" - the other rows will be market metrics
        if isCryptoSageAI {
            return [("Now", vm.data.first)]
        }
        
        // For other sources (alternative.me, etc.), show historical comparison
        let base: [(String, FearGreedData?)] = [
            ("Now", vm.data.first),
            ("Yesterday", vm.yesterdayData),
            ("Last Week", vm.lastWeekData),
            ("Last Month", vm.lastMonthData)
        ]
        if shouldSynthesizeFromBase(base) {
            return synthesizedTimeframeRowsFromVMData()
        }
        return base
    }

    private func shouldSynthesizeFromBase(_ base: [(String, FearGreedData?)]) -> Bool {
        // Only synthesize if we're missing required data
        // Do NOT synthesize just because historical values are flat/equal - that's real data
        let allInts: [Int] = base.compactMap { $0.1?.value }.compactMap { Int($0) }
        // Require at least the "Now" value to be present
        if allInts.isEmpty { return true }
        // If we have timestamps, use the base data as-is
        let hasValidTimestamps = base.compactMap { $0.1?.timestamp }.compactMap { Int($0) }.count >= 1
        if hasValidTimestamps { return false }
        return false
    }

    private func synthesizedTimeframeRowsFromVMData() -> [(String, FearGreedData?)] {
        // 1) Build anchors from vm.data (newest-first), dedupe timestamps, clamp to [0,100], then sort ascending by timestamp
        var byTS: [Int: Int] = [:]
        for d in vm.data {
            if let ts = Int(d.timestamp), let v = Int(d.value) {
                if byTS[ts] == nil { // keep newest for a given timestamp
                    byTS[ts] = max(0, min(100, v))
                }
            }
        }
        var xs: [Int] = []
        var ys: [Int] = []
        let sortedTS = byTS.keys.sorted()
        for t in sortedTS {
            xs.append(t)
            ys.append(byTS[t]!)
        }

        // Fabricate a minimal anchor set if history is too thin
        let nowTs = Int(Date().timeIntervalSince1970)
        var calUTC = Calendar(identifier: .gregorian)
        calUTC.timeZone = TimeZone(secondsFromGMT: 0)!
        let todayStartUTC = calUTC.startOfDay(for: Date())
        let noon: TimeInterval = 60 * 60 * 12
        let yDate = calUTC.date(byAdding: .day, value: -1, to: todayStartUTC)!.addingTimeInterval(noon)
        let wDate = calUTC.date(byAdding: .day, value: -7, to: todayStartUTC)!.addingTimeInterval(noon)
        let mDate = calUTC.date(byAdding: .day, value: -30, to: todayStartUTC)!.addingTimeInterval(noon)
        let yTs = Int(yDate.timeIntervalSince1970)
        let wTs = Int(wDate.timeIntervalSince1970)
        let mTs = Int(mDate.timeIntervalSince1970)

        if xs.count < 2 {
            // Cold start: not enough history yet
            // Show current value for all timeframes (honest representation of no historical data)
            let nowV = vm.currentValue ?? 50
            func clamp(_ v: Int) -> Int { max(0, min(100, v)) }
            xs = [mTs, wTs, yTs, nowTs]
            ys = [clamp(nowV), clamp(nowV), clamp(nowV), clamp(nowV)]
        }

        // Note: Do NOT nudge historical values - they represent actual recorded history
        // If all values are the same, that's the accurate data (e.g., on cold start)

        // 3) Binary-search linear interpolation with [0,100] clamping
        func interp(_ x: Int) -> Int {
            guard xs.count == ys.count, xs.count >= 2 else { return ys.last ?? (vm.currentValue ?? 50) }
            if x <= xs.first! { return max(0, min(100, ys.first!)) }
            if x >= xs.last! { return max(0, min(100, ys.last!)) }
            var lo = 0
            var hi = xs.count - 1
            while lo + 1 < hi {
                let mid = (lo + hi) / 2
                if xs[mid] <= x { lo = mid } else { hi = mid }
            }
            let x0 = xs[lo], x1 = xs[hi]
            let y0 = Double(ys[lo]), y1 = Double(ys[hi])
            let t = Double(x - x0) / Double(max(1, x1 - x0))
            let v = y0 + t * (y1 - y0)
            return max(0, min(100, Int(round(v))))
        }

        // 4) Sample at strictly increasing UTC timestamps for Last Month, Last Week, Yesterday, Now
        var samples = [mTs, wTs, yTs, nowTs]
        for i in 1..<samples.count { if samples[i] <= samples[i-1] { samples[i] = samples[i-1] + 1 } }

        var vals = samples.map(interp)
        // Keep "Now" aligned with the gauge value when available
        if let gaugeNow = vm.currentValue { vals[3] = max(0, min(100, gaugeNow)) }

        func classify(_ v: Int) -> String {
            switch v {
            case 0...24: return "extreme fear"
            case 25...44: return "fear"
            case 45...54: return "neutral"
            case 55...74: return "greed"
            default: return "extreme greed"
            }
        }

        let month = FearGreedData(value: String(vals[0]), value_classification: classify(vals[0]), timestamp: String(samples[0]), time_until_update: nil)
        let week  = FearGreedData(value: String(vals[1]), value_classification: classify(vals[1]), timestamp: String(samples[1]), time_until_update: nil)
        let yday  = FearGreedData(value: String(vals[2]), value_classification: classify(vals[2]), timestamp: String(samples[2]), time_until_update: nil)
        let now   = FearGreedData(value: String(vals[3]), value_classification: classify(vals[3]), timestamp: String(samples[3]), time_until_update: vm.data.first?.time_until_update)

        // Keep the same display order used elsewhere
        return [("Now", now), ("Yesterday", yday), ("Last Week", week), ("Last Month", month)]
    }

    private func isConfigError(_ err: String) -> Bool { let lower = err.lowercased(); return lower.contains("missing api key") || lower.contains("missing endpoint") }

    @MainActor
    private func requestFetch(force: Bool = false) async {
        guard scenePhase == .active else { return }
        let now = Date()
        if isFetching { return }
        if let last = lastFetchAt, now.timeIntervalSince(last) < minFetchInterval, !force { return }
        isFetching = true
        defer {
            lastFetchAt = Date()
            isFetching = false
        }
        // If the currently selected source isn't implemented, default to alternative.me
        if !vm.selectedSource.isImplemented {
            vm.selectedSource = .alternativeMe
        }
        // First attempt
        await vm.fetchData()

        // Exponential backoff on transient errors
        if let err = vm.errorMessage, !isConfigError(err) {
            // increase backoff (cap at 60s)
            retryBackoff = min(retryBackoff * 2, 60)
        } else {
            // success: reset backoff
            retryBackoff = 2
        }
    }
    
    /// Formats the AI observation timestamp for display
    private func aiObservationTimestamp(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }

    var body: some View {
        // FIX v23: Reference tick to trigger re-renders on debounced sentiment updates
        let _ = sentimentTick
        
        VStack(alignment: .leading, spacing: 6) {
            // Header section - single row with title and subtitle
            HStack(alignment: .center, spacing: 8) {
                GoldHeaderGlyph(systemName: "gauge.with.dots.needle.50percent")
                
                Text("Market Sentiment")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Text("Real‑time Fear & Greed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }

            Divider()
                .background(separatorColor)

            // Main content section
            if vm.isLoading {
                SentimentShimmer()
                    .frame(maxWidth: .infinity)
                    .frame(height: gaugeHeight)
            } else if let err = vm.errorMessage {
                let lower = err.lowercased()
                let isConfig = lower.contains("missing api key") || lower.contains("missing endpoint")
                if isConfig {
                    InlineErrorBanner(
                        message: err,
                        onRetry: { Task { await requestFetch() } },
                        onUseDefault: {
                            vm.selectedSource = .derived
                            Task { await requestFetch(force: true) }
                        }
                    )
                } else {
                    DataUnavailableView(message: err, onRetry: { Task { await requestFetch() } })
                }
            } else if vm.data.isEmpty {
                DataUnavailableView(message: "No data available.", onRetry: {
                    Task { await requestFetch() }
                })
            } else {
                // Gauge and timeframe columns
                GeometryReader { geo in
                    mainColumns(geo: geo)
                }
                .opacity(isSwitchingSource ? 0.7 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: isSwitchingSource)
                .frame(height: gaugeHeight)

                // Timing and source row
                // PERFORMANCE FIX: Wrap ViewThatFits in overlay GeometryReader instead of having
                // multiple GeometryReaders in children, to avoid "Bound preference tried to update
                // multiple times per frame" warning.
                // POSITIONING FIX: Frame preference is now captured directly on source buttons
                // This ensures accurate positioning of the picker popup
                ViewThatFits(in: .horizontal) {
                    timingAndSourceSingleRowNoPreference()
                    timingAndSourceTwoRowNoPreference()
                }
                .opacity(isSwitchingSource ? 0.7 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: isSwitchingSource)
                .onPreferenceChange(SourceButtonFrameKey.self) { frame in
                    guard frame != .zero else { return }
                    DispatchQueue.main.async {
                        sourceButtonFrame = frame
                    }
                }

                Divider()
                    .background(separatorColor)
            }

            // AI Observations section
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("AI Summary")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(gold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                    
                    Spacer()
                    
                    // Timestamp or loading indicator
                    // Only show Firebase timestamp when on CryptoSage AI source (observation is from Firebase)
                    // For other sources, the observation is auto-generated from current data
                    if vm.isLoadingAIObservation {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 10, height: 10)
                            Text("Updating...")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                    } else if isCryptoSageAI, let lastFetch = vm.lastAIObservationFetch {
                        Text(aiObservationTimestamp(lastFetch))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
                
                // Short summary text (2 lines max)
                Text(vm.aiObservationCompact)
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .contentTransition(.opacity)
                    .transition(.opacity)
                    .id(vm.aiObservationCompact)
                    .animation(.easeInOut(duration: 0.3), value: vm.aiObservationCompact)
                
                // Key factors chips (compact, inline) — CryptoSage AI only
                if isCryptoSageAI, let factors = vm.firebaseSentimentKeyFactors, !factors.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(factors.prefix(2), id: \.self) { factor in
                            KeyFactorChip(text: factor)
                        }
                    }
                }
            }
            .opacity(isSwitchingSource ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.25), value: isSwitchingSource)
            
            // View Full Analysis button
            SectionCTAButton(
                title: "View Full Analysis",
                icon: "waveform.path.ecg",
                compact: true
            ) {
                showSentimentDetail = true
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.Adaptive.stroke, lineWidth: 0.8)
        )
        .frame(maxWidth: .infinity)
        // Removed nowPulse animation trigger - was causing background flickering
        // FIX v23: Debounced sentiment observation (replaces @ObservedObject)
        .onReceive(ExtendedFearGreedViewModel.shared.objectWillChange.debounce(for: .seconds(5), scheduler: DispatchQueue.main)) { _ in
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            sentimentTick &+= 1
        }
        // FIX: Non-debounced observer for sub-metrics (Breadth / BTC 24h / Volatility).
        // The 5s debounce above keeps resetting when other @Published properties change
        // (isLoading, commentary, etc.), causing these metrics to show "—" indefinitely.
        // This targeted observer fires immediately when any metric changes from nil to a value.
        .onReceive(ExtendedFearGreedViewModel.shared.$marketBreadth.combineLatest(
            ExtendedFearGreedViewModel.shared.$btc24hChange,
            ExtendedFearGreedViewModel.shared.$marketVolatility
        ).receive(on: DispatchQueue.main)) { breadth, btc, vol in
            // Only trigger re-render when transitioning from nil → value
            if breadth != nil || btc != nil || vol != nil {
                metricsTick &+= 1
            }
        }
        .onReceive(ExtendedFearGreedViewModel.shared.$data.receive(on: DispatchQueue.main)) { _ in
            updateNowScoreDeltaTracking()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await requestFetch()
            // PERFORMANCE FIX v20: Only retry on error. Previously always double-fetched
            // even on success, wasting an API call every foreground transition.
            if vm.errorMessage != nil {
                try? await Task.sleep(nanoseconds: UInt64(retryBackoff * 1_000_000_000))
                await requestFetch()
            }
        }
        .refreshable {
            await requestFetch(force: true)
        }
        // PERFORMANCE FIX v20: Increased from 120s to 300s. This is now purely a safety net.
        // The ViewModel's adaptive scheduler is the primary refresh driver.
        // PERFORMANCE FIX v19: Changed .common to .default - timer pauses during scroll
        .onReceive(Timer.publish(every: 300, on: .main, in: .default).autoconnect()) { _ in
            // PERFORMANCE FIX: Skip fetch during scroll
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Double-check scroll state after async dispatch
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                Task { await requestFetch() }
            }
        }
        .onChange(of: vm.selectedSource) { _, _ in
            DispatchQueue.main.async {
                lastObservedSource = vm.selectedSource
                lastObservedNowScore = vm.currentValue
                nowScoreDelta = nil
                withAnimation(.easeInOut(duration: 0.15)) { isSwitchingSource = true }
                // Reduced timeout from 1.0s to 0.4s for faster perceived switching
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if isSwitchingSource {
                        withAnimation(.easeInOut(duration: 0.15)) { isSwitchingSource = false }
                    }
                }
                Task { await requestFetch(force: true) }
            }
        }
        .onChange(of: vm.isLoading) { _, loading in
            DispatchQueue.main.async {
                if !loading {
                    withAnimation(.easeInOut(duration: 0.18)) { isSwitchingSource = false }
                }
            }
        }
        // PERFORMANCE FIX v10: Removed onChange(of: vm.currentValue ?? 0)
        // This was the primary source of "onChange tried to update multiple times per frame" warnings
        // The isSwitchingSource handling is already done in onChange(of: vm.isLoading)
        // FIX: Source picker overlay is now rendered in HomeView above the ScrollView
        // to avoid ScrollView clipping. MarketSentimentView sets vm.showSourcePicker
        // and vm.sourcePickerAnchorFrame to communicate with HomeView.
        // Sync local button styling state when the picker is dismissed from HomeView
        .onReceive(ExtendedFearGreedViewModel.shared.$showSourcePicker) { show in
            if showSourcePopover != show {
                showSourcePopover = show
            }
        }
        .onAppear {
            lastObservedSource = vm.selectedSource
            lastObservedNowScore = vm.currentValue
        }
        .sheet(isPresented: $showSentimentDetail) {
            MarketSentimentDetailView(vm: vm)
        }
    }

    private func timingAndSourceSingleRow() -> some View {
        HStack(alignment: .center, spacing: 6) {
            // Left: timing chip
            let timingText = buildTimingText()
            if !timingText.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .accessibilityHidden(true)
                    Text(timingText)
                        .font(.caption2)
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.7)
                        .monospacedDigit()
                        .contentTransition(.opacity)
                        .id(vm.selectedSource)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DS.Adaptive.chipBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DS.Adaptive.strokeStrong, lineWidth: 0.6)
                )
            }
            
            Spacer(minLength: 4)

            // Right: Source pill (compact name)
            // PROFESSIONAL UX: Shows active state when picker is open
            // FIX: Use overlay with GeometryReader to capture frame at tap time
            HStack(spacing: 4) {
                Text("Source")
                    .font(.caption2.weight(.semibold))
                    // PROFESSIONAL UX: Gold text when active
                    .foregroundColor(showSourcePopover ? BrandColors.goldBase : DS.Adaptive.textSecondary)
                Text("· \(vm.sourceDisplayNameWithFallback)")
                    .font(.caption2)
                    // PROFESSIONAL UX: Gold text when active
                    .foregroundColor(showSourcePopover ? BrandColors.goldBase : DS.Adaptive.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
                    .contentTransition(.opacity)
                    .id(vm.selectedSource)
                // PROFESSIONAL UX: Chevron flips up when active
                Image(systemName: showSourcePopover ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundColor(showSourcePopover ? BrandColors.goldBase : DS.Adaptive.textTertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            // PROFESSIONAL UX: Gold tint background when active
            .background(showSourcePopover ? BrandColors.goldBase.opacity(0.12) : DS.Adaptive.chipBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    // PROFESSIONAL UX: Gold border when active
                    .stroke(showSourcePopover ? BrandColors.goldBase : DS.Adaptive.strokeStrong, lineWidth: showSourcePopover ? 1.0 : 0.6)
            )
            .animation(.easeOut(duration: 0.15), value: showSourcePopover)
            // FIX: Capture frame immediately on appear AND on tap via overlay
            .overlay(
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Capture frame at tap time - guarantees accurate position
                            let frame = proxy.frame(in: .global)
                            sourceButtonFrame = frame
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            // Set both local state (for button styling) and VM state (for HomeView overlay)
                            showSourcePopover = true
                            vm.showSourcePicker = true
                        }
                        .onAppear {
                            // Also eagerly capture on appear for safety
                            DispatchQueue.main.async {
                                sourceButtonFrame = proxy.frame(in: .global)
                            }
                        }
                }
            )
        }
    }
    
    // PERFORMANCE FIX: No-preference variants for ViewThatFits (preference set at container level)
    private func timingAndSourceSingleRowNoPreference() -> some View {
        timingAndSourceSingleRow()
    }

    private func timingAndSourceTwoRow() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: timing chip full-width
            let timingText = buildTimingText()
            if !timingText.isEmpty || sentimentDataStatus != nil {
                HStack(spacing: 6) {
                    if !timingText.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textTertiary)
                                .accessibilityHidden(true)
                            Text(timingText)
                                .font(.caption2)
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .lineLimit(1)
                                .allowsTightening(true)
                                .truncationMode(.middle)
                                .minimumScaleFactor(0.7)
                                .monospacedDigit()
                                .contentTransition(.opacity)
                                .id(vm.selectedSource)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(DS.Adaptive.chipBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(DS.Adaptive.strokeStrong, lineWidth: 0.6)
                        )
                    }
                    
                }
            }

            // Row 2: source pill aligned right
            HStack {
                Spacer(minLength: 4)
                // FIX: Use overlay with GeometryReader to capture frame at tap time
                HStack(spacing: 4) {
                    Text("Source")
                        .font(.caption2.weight(.semibold))
                        // PROFESSIONAL UX: Gold text when active
                        .foregroundColor(showSourcePopover ? BrandColors.goldBase : DS.Adaptive.textSecondary)
                    Text("· \(vm.sourceDisplayNameWithFallback)")
                        .font(.caption2)
                        // PROFESSIONAL UX: Gold text when active
                        .foregroundColor(showSourcePopover ? BrandColors.goldBase : DS.Adaptive.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.65)
                        .allowsTightening(true)
                        .contentTransition(.opacity)
                        .id(vm.selectedSource)
                    // PROFESSIONAL UX: Chevron flips up when active
                    Image(systemName: showSourcePopover ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(showSourcePopover ? BrandColors.goldBase : DS.Adaptive.textTertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                // PROFESSIONAL UX: Gold tint background when active
                .background(showSourcePopover ? BrandColors.goldBase.opacity(0.12) : DS.Adaptive.chipBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        // PROFESSIONAL UX: Gold border when active
                        .stroke(showSourcePopover ? BrandColors.goldBase : DS.Adaptive.strokeStrong, lineWidth: showSourcePopover ? 1.0 : 0.6)
                )
                .animation(.easeOut(duration: 0.15), value: showSourcePopover)
                // FIX: Capture frame immediately on appear AND on tap via overlay
                .overlay(
                    GeometryReader { proxy in
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Capture frame at tap time - guarantees accurate position
                                let frame = proxy.frame(in: .global)
                                sourceButtonFrame = frame
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                // Set both local state (for button styling) and VM state (for HomeView overlay)
                                showSourcePopover = true
                                vm.showSourcePicker = true
                            }
                            .onAppear {
                                // Also eagerly capture on appear for safety
                                DispatchQueue.main.async {
                                    sourceButtonFrame = proxy.frame(in: .global)
                                }
                            }
                    }
                )
            }
        }
    }
    
    // PERFORMANCE FIX: No-preference variant for ViewThatFits (preference set at container level)
    private func timingAndSourceTwoRowNoPreference() -> some View {
        timingAndSourceTwoRow()
    }

    private func leftGaugeColumn(leftWidth: CGFloat, gaugeHeight: CGFloat) -> AnyView {
        return AnyView(
            VStack(alignment: .center, spacing: 0) {
                ZStack {
                    ImprovedHalfCircleGauge(
                        value: Double(vm.currentValue ?? 0),
                        classification: vm.data.first?.valueClassification,
                        lineWidth: 10,
                        disableBadgeAnimation: false,
                        showLiveBadge: false,
                        tickLabelOpacityFactor: 1.0,
                        gentleMode: isSwitchingSource
                    )
                }
                .id(vm.selectedSource) // Force gauge to re-initialize when source changes
                .frame(width: leftWidth, height: gaugeHeight - labelRowHeight)

                // Labels below gauge
                HStack {
                    Text("Extreme Fear")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.red.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer()
                    Text("Extreme Greed")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.green.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 2)
                .frame(height: labelRowHeight)
            }
            .frame(width: leftWidth, height: gaugeHeight)
        )
    }


    private func rightColumn(cappedRightWidth: CGFloat, gaugeHeight: CGFloat, rowHeight: CGFloat, loading: Bool) -> AnyView {
        if isCryptoSageAI {
            // CryptoSage AI: Show unified metric rows for all 4 items
            let nowClassification = (vm.data.first?.valueClassification ?? "—").capitalized
            let nowClassificationWithDelta = {
                guard let delta = nowScoreDelta, delta != 0 else { return nowClassification }
                let sign = delta > 0 ? "+" : ""
                return "\(nowClassification) (\(sign)\(delta) vs last)"
            }()
            let nowColor = color(for: vm.data.first?.valueClassification)
            let nowValue = vm.data.first.map { "\($0.value)" } ?? "—"
            
            return AnyView(
                ZStack {
                    VStack(alignment: .leading, spacing: 0) {
                        // Row 1: Now (sentiment) - unified metric style with badge
                        unifiedMetricRow(
                            label: "Now",
                            value: nowClassificationWithDelta,
                            badge: nowValue,
                            color: nowColor,
                            isHighlighted: true
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(separatorColor).frame(height: 0.5).padding(.horizontal, 6)
                        }
                        
                        // Rows 2-4: Sub-metrics (Breadth, BTC 24h, Volatility)
                        // Use let bindings to capture current values, dependent on metricsTick
                        // so SwiftUI re-evaluates when metrics arrive from Firebase
                        let _ = metricsTick  // Force re-evaluation when metrics update
                        let breadthVal = vm.marketBreadth
                        let btcVal = vm.btc24hChange
                        let volVal = vm.marketVolatility
                        
                        // Row 2: Market Breadth
                        unifiedMetricRow(
                            label: "Breadth",
                            value: breadthVal.map { String(format: "%.0f%%", $0) } ?? "—",
                            badge: nil,
                            icon: "chart.bar.fill",
                            color: breadthColor(breadthVal),
                            isHighlighted: false
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(separatorColor).frame(height: 0.5).padding(.horizontal, 6)
                        }
                        
                        // Row 3: BTC 24h Change
                        unifiedMetricRow(
                            label: "BTC 24h",
                            value: btcVal.map { String(format: "%+.1f%%", $0) } ?? "—",
                            badge: nil,
                            icon: "bitcoinsign.circle.fill",
                            color: changeColor(btcVal),
                            isHighlighted: false
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(separatorColor).frame(height: 0.5).padding(.horizontal, 6)
                        }
                        
                        // Row 4: Volatility
                        unifiedMetricRow(
                            label: "Volatility",
                            value: volatilityLabel(volVal),
                            badge: nil,
                            icon: "waveform.path",
                            color: volatilityColor(volVal),
                            isHighlighted: false
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                    }
                    .id(vm.selectedSource)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.22), value: vm.selectedSource)
                    .animation(.easeInOut(duration: 0.18), value: isSwitchingSource)

                    if loading {
                        RightColumnSkeleton(rowHeight: rowHeight, rows: 4)
                            .transition(.opacity)
                    }
                }
                .padding(.trailing, 0)
                .frame(width: cappedRightWidth, height: gaugeHeight)
            )
        } else {
            // Other sources: Show historical comparison (Now, Yesterday, Week, Month)
            return AnyView(
                ZStack {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<timeframeRows.count, id: \.self) { i in
                            timeframeRowAligned(timeframeRows[i].0, timeframeRows[i].1)
                                .frame(maxWidth: .infinity)
                                .frame(height: rowHeight)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(separatorColor)
                                        .frame(height: 0.5)
                                        .padding(.horizontal, 6)
                                        .opacity(i < timeframeRows.count - 1 ? 1 : 0)
                                }
                        }
                    }
                    .id(vm.selectedSource)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.22), value: vm.selectedSource)
                    .animation(.easeInOut(duration: 0.18), value: isSwitchingSource)

                    if loading {
                        RightColumnSkeleton(rowHeight: rowHeight, rows: timeframeRows.count)
                            .transition(.opacity)
                    }
                }
                .frame(width: cappedRightWidth, height: gaugeHeight)
            )
        }
    }
    
    // MARK: - Unified Metric Row (for CryptoSage AI mode)
    /// A consistent row style for all CryptoSage AI metrics
    /// - Parameters:
    ///   - label: Row label (e.g., "Now", "Breadth")
    ///   - value: Main display value (e.g., "Neutral", "64%")
    ///   - badge: Optional small badge value (e.g., "49" for sentiment)
    ///   - icon: Optional SF Symbol icon to display when no badge (e.g., "chart.bar.fill")
    ///   - color: Color for the value text
    ///   - isHighlighted: Whether to show subtle highlight background (for "Now" row)
    private func unifiedMetricRow(label: String, value: String, badge: String?, icon: String? = nil, color: Color, isHighlighted: Bool) -> some View {
        // Horizontal layout with label/value on left, badge/icon on right
        return HStack(alignment: .center, spacing: 0) {
            // Left: Label and value stacked
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(1)
                
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 2)
            
            // Right: Badge, icon, or placeholder for alignment
            if let badge = badge {
                SmallBadgeView(valueText: badge, size: alignedBadgeSize, color: color)
            } else if let icon = icon {
                // Display contextual icon with subtle circular background + glow
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    Circle()
                        .stroke(color.opacity(0.30), lineWidth: 1)
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(color)
                }
                .frame(width: alignedBadgeSize, height: alignedBadgeSize)
            } else {
                // Empty space to maintain consistent layout
                Color.clear
                    .frame(width: alignedBadgeSize, height: alignedBadgeSize)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHighlighted ? color.opacity(0.10) : Color.clear)
        )
    }
    
    // MARK: - CryptoSage AI Metric Row (legacy, kept for reference)
    private func cryptoSageMetricRow(label: String, value: String, detail: String?, color: Color) -> some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(1)
                if let detail = detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundColor(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
    
    private func breadthColor(_ breadth: Double?) -> Color {
        guard let b = breadth else { return .gray }
        if b >= 60 { return .green }
        if b >= 40 { return .yellow }
        return .red
    }
    
    private func changeColor(_ change: Double?) -> Color {
        guard let c = change else { return .gray }
        if c >= 1 { return .green }
        if c <= -1 { return .red }
        return .yellow
    }
    
    private func volatilityLabel(_ vol: Double?) -> String {
        guard let v = vol else { return "—" }
        if v < 3 { return "Low" }
        if v < 7 { return "Normal" }
        if v < 12 { return "High" }
        return "Extreme"
    }
    
    private func volatilityColor(_ vol: Double?) -> Color {
        guard let v = vol else { return .gray }
        if v < 3 { return .green }
        if v < 7 { return .yellow }
        if v < 12 { return .orange }
        return .red
    }
    
    private func mainColumns(geo: GeometryProxy) -> AnyView {
        // 65/35 split - gauge prominent, right panel has room for full text
        let rightRatio: CGFloat = 0.35
        let cappedRightWidth = min(rightColumnWidth, geo.size.width * rightRatio)
        let leftWidth = max(0, geo.size.width - cappedRightWidth - 8)
        
        // Right panel matches gauge height
        let rowCount = isCryptoSageAI ? 4 : timeframeRows.count
        let rightPanelHeight = gaugeHeight
        let rowHeight: CGFloat = rightPanelHeight / CGFloat(max(1, rowCount))

        let leftView: AnyView = AnyView(
            leftGaugeColumn(leftWidth: leftWidth, gaugeHeight: gaugeHeight)
        )

        let rightView: AnyView = AnyView(
            rightColumn(cappedRightWidth: cappedRightWidth, gaugeHeight: rightPanelHeight, rowHeight: rowHeight, loading: vm.isLoading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
                .opacity(isSwitchingSource ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: isSwitchingSource)
        )

        return AnyView(
            HStack(alignment: .top, spacing: 4) {
                leftView
                rightView
            }
        )
    }
    
    private func formatInterval(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return String(format: "%dh %dm", h, m) }
        if m > 0 { return String(format: "%dm", m) }
        return "<1m"
    }
    
    private func formatIntervalCompact(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "< 1 min" }
        let minutes = s / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 {
            // For long hour ranges, keep it short (e.g., 17h instead of 17h 6 min)
            if hours >= 12 { return "\(hours)h" }
            let rem = minutes % 60
            return rem > 0 ? "\(hours)h \(rem) min" : "\(hours)h"
        }
        let days = hours / 24
        if days < 7 {
            let remH = hours % 24
            return remH > 0 ? "\(days)d \(remH)h" : "\(days)d"
        }
        // 7d+ just show days
        return "\(days)d"
    }

    private func formatTimeShort(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = .current
        df.timeStyle = .short
        df.dateStyle = .none
        return df.string(from: date)
    }

    private func formatDateShort(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = .current
        df.setLocalizedDateFormatFromTemplate("MMM d")
        return df.string(from: date)
    }
    
    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        let timeDF = DateFormatter(); timeDF.locale = .current; timeDF.dateFormat = "h:mm a"
        if cal.isDateInToday(date) {
            return timeDF.string(from: date)
        }
        // For yesterday and earlier, include short date + time
        let dateDF = DateFormatter(); dateDF.locale = .current; dateDF.setLocalizedDateFormatFromTemplate("MMM d")
        return "\(dateDF.string(from: date)) \(timeDF.string(from: date))"
    }
    
    private func buildTimingText() -> String {
        var parts: [String] = []
        if let d = vm.lastUpdatedDateUTC {
            let cal = Calendar.current
            let timeStr = formatTimeShort(d)
            if cal.isDateInToday(d) {
                parts.append(timeStr)
            } else {
                // Compact date format without redundant prefix
                parts.append("\(formatDateShort(d)) \(timeStr)")
            }
        }
        if let t = vm.nextUpdateInterval {
            parts.append("Next \(formatIntervalCompact(t))")
        }
        return parts.joined(separator: " • ")
    }

    private var sentimentDataStatus: (label: String, color: Color)? {
        if vm.isLoading {
            return ("Refreshing", DS.Adaptive.textTertiary)
        }
        if vm.isUsingFallback {
            return ("Fallback", BrandColors.goldBase)
        }
        if let updated = vm.lastUpdatedDateUTC {
            let age = Date().timeIntervalSince(updated)
            if age > 20 * 60 {
                return ("Cached", DS.Adaptive.textSecondary)
            }
            return ("Live", .green)
        }
        return nil
    }

    private func updateNowScoreDeltaTracking() {
        guard let current = vm.currentValue else { return }
        if lastObservedSource != vm.selectedSource {
            lastObservedSource = vm.selectedSource
            lastObservedNowScore = current
            nowScoreDelta = nil
            return
        }
        if let previous = lastObservedNowScore {
            nowScoreDelta = (previous == current) ? nil : (current - previous)
        } else {
            nowScoreDelta = nil
        }
        lastObservedNowScore = current
    }

    private func formatDateTight(_ date: Date) -> String {
        let cal = Calendar.current
        let timeDF = DateFormatter(); timeDF.locale = .current; timeDF.dateFormat = "h:mm a"
        if cal.isDateInToday(date) { return timeDF.string(from: date) }
        let dateDF = DateFormatter(); dateDF.locale = .current; dateDF.setLocalizedDateFormatFromTemplate("MMM d")
        return dateDF.string(from: date)
    }

    private func timeframeRow(_ label: String, _ d: FearGreedData?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textSecondary)
            HStack {
                if let d = d {
                    let badgeView: AnyView = AnyView(
                        ZStack {
                            Circle()
                                .stroke(color(for: d.valueClassification).opacity(0.6), lineWidth: 2)
                                .frame(width: standardBadgeSize, height: standardBadgeSize)
                            Circle()
                                .fill(RadialGradient(
                                    gradient: Gradient(colors: [
                                        color(for: d.valueClassification).opacity(0.9),
                                        color(for: d.valueClassification).opacity(0.5)
                                    ]),
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: standardBadgeSize / 2
                                ))
                                .overlay(
                                    Circle()
                                        .stroke(color(for: d.valueClassification).opacity(0.8), lineWidth: 1.5)
                                )
                            Text("\(d.value)")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .fontWidth(.condensed)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundColor(.white.opacity(0.93))
                        }
                        .frame(width: standardBadgeSize, height: standardBadgeSize)
                    )
                    badgeView
                } else {
                    Text("—")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                }
            }
        }
    }

    private func timeframeRowAligned(_ label: String, _ d: FearGreedData?) -> AnyView {
        let isNow = label.lowercased() == "now"
        let classificationText: String = (d?.valueClassification).map { $0.capitalized } ?? "No data"
        let valueText: String = d.map { " \($0.value)" } ?? ""
        let accessibilityText = "\(label), \(classificationText)\(valueText)"
        let displayLabel: String = abbreviatedLabel(label)
        let displayClassification: String = abbreviatedClassification(d?.valueClassification)
        let classColor: Color = color(for: d?.valueClassification)
        // Static background opacity for "Now" row - removed problematic pulse animation
        // that was causing the background to flicker/disappear
        let bgOpacity: Double = isNow ? 0.12 : 0.0

        let rowCorner: CGFloat = 6

        // Horizontal layout with label/classification on left, badge on right
        let rowContent: AnyView = AnyView(
            HStack(alignment: .center, spacing: 0) {
                // Left: Label and classification stacked
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(1)
                    
                    Text(displayClassification)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(classColor)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 2)
                
                // Right: Badge
                if let d = d {
                    SmallBadgeView(valueText: "\(d.value)", size: alignedBadgeSize, color: classColor)
                } else {
                    // Empty space to maintain consistent layout
                    Color.clear
                        .frame(width: alignedBadgeSize, height: alignedBadgeSize)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: rowCorner, style: .continuous)
                    .fill(classColor.opacity(bgOpacity))
            )
        )

        return AnyView(
            rowContent
                .clipShape(RoundedRectangle(cornerRadius: rowCorner, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: rowCorner, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityHint(isNow ? "Current value" : "Historical value")
                .accessibilityValue(d.map { String($0.value) } ?? "No data")
        )
    }

    private func color(for cls: String?) -> Color {
        let key = (cls ?? "").lowercased()
        switch key {
        case "extreme fear":  return .red
        case "fear":          return .orange
        case "neutral":       return DS.Adaptive.neutralYellow
        case "greed":         return .green
        case "extreme greed": return .mint
        default:               return .gray
        }
    }
    
    // MARK: - Abbreviation Helpers for Compact Layout
    
    /// Returns full timeframe labels for the right column
    private func abbreviatedLabel(_ label: String) -> String {
        return label
    }
    
    /// Returns full classification text - no abbreviations
    private func abbreviatedClassification(_ cls: String?) -> String {
        return (cls ?? "—").capitalized
    }

    private func aiInsight(for classification: String?) -> String {
        switch (classification ?? "").lowercased() {
        case "extreme fear":  return "Extreme Fear—market is fragile."
        case "fear":          return "Fear—selective buying might be possible."
        case "neutral":       return "Neutral—monitor momentum."
        case "greed":         return "Greed—potential profit‑taking."
        case "extreme greed": return "Extreme Greed—market exuberant, consider profit‑taking."
        default:               return "Awaiting fresh sentiment…"
        }
    }

    private func trendHint(now: String?, yesterday: String?) -> String {
        guard
            let nowStr = now, let nowVal = Int(nowStr),
            let yStr = yesterday, let yVal = Int(yStr)
        else { return "Current value." }
        if nowVal > yVal { return "Up from yesterday." }
        if nowVal < yVal { return "Down from yesterday." }
        return "Unchanged from yesterday."
    }
}
// MARK: - ImprovedHalfCircleGauge

struct ImprovedHalfCircleGauge: View {
    var value: Double
    var classification: String?
    var lineWidth: CGFloat = 10
    var disableBadgeAnimation: Bool = false
    var showLiveBadge: Bool = true
    var tickLabelOpacityFactor: Double = 1.0
    var gentleMode: Bool = false
    var showTicks: Bool = true
 
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var tipPulse   = false
    @State private var previousValue: Double = 0
    @State private var refreshBounce = false
    @State private var animValue: Double = 0   // spring‑animated display value (0...100)
    @State private var sweepPulse: Bool = false  // drives faint crescent highlight opacity
    @State private var lastGaugeUpdateAt: Date = .distantPast  // PERFORMANCE FIX v8: Throttle gauge updates
    @State private var hasCompletedInitialLoad: Bool = false  // PERFORMANCE FIX v9: Skip onChange during initial load

    static let segments: [(ClosedRange<Double>, Color)] = [
        (0...25,   .red),
        (25...50,  .orange),
        (50...75,  .yellow),
        (75...100, .green)
    ]

    static let arcGradientStops: [Gradient.Stop] = [
        .init(color: Self.segments[0].1.opacity(0.2),  location: 0.0),
        .init(color: Self.segments[1].1.opacity(0.2),  location: 0.25),
        .init(color: Self.segments[2].1.opacity(0.17), location: 0.49),
        .init(color: Self.segments[2].1.opacity(0.17), location: 0.51),
        .init(color: Self.segments[3].1.opacity(0.2),  location: 0.75),
        .init(color: Self.segments[3].1.opacity(0.2),  location: 1.0)
    ]

    static let crescentGradientStops: [Gradient.Stop] = [
        .init(color: Color.white.opacity(0.0), location: 0.00),
        .init(color: Color.white.opacity(0.05), location: 0.18),
        .init(color: Color.white.opacity(0.12), location: 0.50),
        .init(color: Color.white.opacity(0.05), location: 0.82),
        .init(color: Color.white.opacity(0.0), location: 1.00)
    ]
    
    /// Adaptive arc gradient stops that use readable yellow in light mode
    private var adaptiveArcGradientStops: [Gradient.Stop] {
        let neutralColor = DS.Adaptive.neutralYellow
        return [
            .init(color: Color.red.opacity(0.2),        location: 0.0),
            .init(color: Color.orange.opacity(0.2),     location: 0.25),
            .init(color: neutralColor.opacity(0.17),    location: 0.49),
            .init(color: neutralColor.opacity(0.17),    location: 0.51),
            .init(color: Color.green.opacity(0.2),      location: 0.75),
            .init(color: Color.green.opacity(0.2),      location: 1.0)
        ]
    }
    
    private var currentColor: Color {
        switch (classification ?? "").lowercased() {
        case "extreme fear":  return .red
        case "fear":          return .orange
        case "neutral":       return DS.Adaptive.neutralYellow
        case "greed":         return .green
        case "extreme greed": return .mint
        default:               return .white
        }
    }

    var body: some View {
        GeometryReader { geo in
            makeGauge(in: geo)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Market sentiment: \(Int(value)) percent, \((classification ?? "").capitalized)")
        .accessibilityHint("Current sentiment value in percent")
        .onAppear {
            // PERFORMANCE FIX v9: Set initial values and mark load time
            tipPulse = !reduceMotion
            previousValue = value
            animValue = min(max(value, 0), 100)
            lastGaugeUpdateAt = Date()
            
            // PERFORMANCE FIX v9: Mark initial load complete after 500ms
            // This prevents onChange from firing during the initial rapid data loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                hasCompletedInitialLoad = true
                // BUG FIX: Sync needle position after the blocking period ends.
                // During the 500ms initial load, onChange was blocked so animValue may be
                // stuck at the initial neutral position (50) while value already changed
                // (e.g., to 10 for "Strong Sell"). Without this catch-up, the needle
                // stays at center even though the text label shows the correct verdict.
                let target = min(max(value, 0), 100)
                if abs(animValue - target) > 0.5 {
                    withAnimation(GaugeMotionProfile.springEmphasis) {
                        animValue = target
                    }
                    previousValue = value
                }
            }
            
            // PERFORMANCE FIX v22: Removed repeatForever sweep animation.
            // This ran continuously while the gauge was visible, producing constant draw calls
            // (~60fps) even when nothing was changing. The subtle 10% opacity pulse was not worth
            // the GPU cost. Using a static opacity instead.
            sweepPulse = true
        }
        .onChange(of: value) { _, newValue in
            // PERFORMANCE FIX v9: Skip until initial load completes (first 500ms)
            guard hasCompletedInitialLoad else { return }
            
            // Skip if value hasn't meaningfully changed
            guard abs(newValue - previousValue) > 0.5 else { return }
            
            // CRITICAL FIX: ALWAYS update the needle position so it matches the verdict text.
            // Previously, ALL updates were blocked during the 4-second global startup phase
            // and during scroll, causing the needle to get stuck at neutral (center) while
            // the text correctly showed "Strong Sell" or "Strong Buy".
            withAnimation(gentleMode ? GaugeMotionProfile.settle : GaugeMotionProfile.springEmphasis) {
                animValue = min(max(newValue, 0), 100)
            }
            previousValue = newValue
            
            // Gate ONLY the heavy effects (haptics, bounce) behind performance guards.
            // These are cosmetic and safe to skip during startup/scroll.
            guard !isInGlobalStartupPhase() else { return }
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            
            let now = Date()
            guard now.timeIntervalSince(lastGaugeUpdateAt) > 0.2 else { return }
            lastGaugeUpdateAt = now
            
            let thresholds: [Double] = [25, 50, 75]
            let crossed = thresholds.contains { (previousValue < $0 && newValue >= $0) || (previousValue >= $0 && newValue < $0) }
            if crossed {
                if !UIAccessibility.isReduceMotionEnabled && !gentleMode {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred(intensity: 0.6)
                }
            }
            
            if !gentleMode {
                refreshBounce = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(GaugeMotionProfile.spring) {
                        refreshBounce = false
                    }
                }
            }
        }
    }
    
    private func makeGauge(in geo: GeometryProxy) -> AnyView {
        let w      = geo.size.width
        let h      = geo.size.height
        // Scale 0.90 for a larger gauge with room for compact badge
        let radius = (min(w, h * 2) / 2 - lineWidth / 2) * 0.90
        let needleLength = radius - (lineWidth * 0.8) * 0.35
        let centerLift: CGFloat = lineWidth * 0.8
        let center = CGPoint(x: w/2, y: h - centerLift)
        let clampedAnimated = min(max(animValue, 0), 100)
        let clampedStatic   = min(max(value, 0), 100)
        let progress = clampedAnimated / 100
        let endDeg = 180 + progress * 180

        // Compact badge sizing - small and proportional
        let liveBadgeSize: CGFloat = max(18, min(22, radius * 0.16))
        
        // Badge angle in radians (follows needle direction)
        let badgeAngleRad = endDeg.radians
        
        // BADGE POSITIONING: Smart radial placement outside the arc
        //
        // Strategy:
        // - Badge sits just outside the arc at the needle's angle
        // - Uses the arc radius (not needle length) as reference for consistent
        //   clearance from the visible arc stroke
        // - Allows negative Y (above frame) so the badge at the top of the
        //   semicircle (values ~35-65) doesn't get clamped into the arc
        // - Horizontal clamping keeps badge within the visible card width
        
        // Place badge just outside the outer edge of the arc stroke
        let arcOuterEdge = radius + (lineWidth * 0.8) / 2  // outer edge of painted arc
        let badgeClearance: CGFloat = liveBadgeSize / 2 + 6  // gap between arc edge and badge center
        let badgeDistance = arcOuterEdge + badgeClearance
        let rawBadgeX = center.x + cos(badgeAngleRad) * badgeDistance
        let rawBadgeY = center.y + sin(badgeAngleRad) * badgeDistance
        
        // Horizontal clamping: keep within visible width
        let hMargin: CGFloat = liveBadgeSize / 2 + 2
        let badgeX = max(hMargin, min(w - hMargin, rawBadgeX))
        // Vertical: allow badge to extend above the frame (SwiftUI does not clip by default)
        // Only clamp the bottom to stay within the gauge area
        let badgeY = max(-liveBadgeSize / 2, min(h - liveBadgeSize / 2 - 2, rawBadgeY))

        let baseOffset = lineWidth * 0.66
        let baseLeft = CGPoint(x: center.x + cos(endDeg.radians + .pi/2) * baseOffset,
                               y: center.y + sin(endDeg.radians + .pi/2) * baseOffset)
        let baseRight = CGPoint(x: center.x + cos(endDeg.radians - .pi/2) * baseOffset,
                                y: center.y + sin(endDeg.radians - .pi/2) * baseOffset)
        let tip = CGPoint(x: center.x + cos(endDeg.radians) * needleLength,
                          y: center.y + sin(endDeg.radians) * needleLength)

        // Inner core geometry for a two‑stage needle
        let innerOffset = baseOffset * 0.55
        let baseLeftInner = CGPoint(x: center.x + cos(endDeg.radians + .pi/2) * innerOffset,
                                    y: center.y + sin(endDeg.radians + .pi/2) * innerOffset)
        let baseRightInner = CGPoint(x: center.x + cos(endDeg.radians - .pi/2) * innerOffset,
                                     y: center.y + sin(endDeg.radians - .pi/2) * innerOffset)
        let tipInset = CGPoint(x: center.x + cos(endDeg.radians) * (needleLength - lineWidth * 0.2),
                               y: center.y + sin(endDeg.radians) * (needleLength - lineWidth * 0.2))

        // Precompute vectors and control points for the micro‑taper cubic curves
        let dirX: CGFloat = cos(endDeg.radians)
        let dirY: CGFloat = sin(endDeg.radians)
        let normX: CGFloat = cos(endDeg.radians + .pi/2)
        let normY: CGFloat = sin(endDeg.radians + .pi/2)

        let leftInner  = baseLeftInner
        let rightInner = baseRightInner

        let c1L = CGPoint(x: center.x + dirX * (needleLength * 0.35) + normX * (-innerOffset * 0.40),
                          y: center.y + dirY * (needleLength * 0.35) + normY * (-innerOffset * 0.40))
        let c2L = CGPoint(x: center.x + dirX * (needleLength * 0.75) + normX * (-innerOffset * 0.15),
                          y: center.y + dirY * (needleLength * 0.75) + normY * (-innerOffset * 0.15))
        let c1R = CGPoint(x: center.x + dirX * (needleLength * 0.75) + normX * ( innerOffset * 0.15),
                          y: center.y + dirY * (needleLength * 0.75) + normY * ( innerOffset * 0.15))
        let c2R = CGPoint(x: center.x + dirX * (needleLength * 0.35) + normX * ( innerOffset * 0.40),
                          y: center.y + dirY * (needleLength * 0.35) + normY * ( innerOffset * 0.40))

        // Prebuild gradients to simplify type checking
        // Use adaptive gradient stops for light mode readability
        let arcGradientStops: [Gradient.Stop] = adaptiveArcGradientStops
        let arcGradient = AngularGradient(
            gradient: Gradient(stops: arcGradientStops),
            center: .center,
            startAngle: .degrees(180),
            endAngle: .degrees(360)
        )

        let crescentStops: [Gradient.Stop] = Self.crescentGradientStops
        let crescentGradient = AngularGradient(
            gradient: Gradient(stops: crescentStops),
            center: .center,
            startAngle: .degrees(180),
            endAngle: .degrees(360)
        )

        // Prebuilt layers (keep outside ZStack to ease type-checking)

        let crescentHighlight: AnyView = AnyView(
            Path { p in
                p.addArc(center: center,
                         radius: radius + lineWidth * 0.52,
                         startAngle: .degrees(180),
                         endAngle: .degrees(360),
                         clockwise: false)
            }
            .stroke(crescentGradient, style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
            .opacity(reduceMotion ? 0.06 : (sweepPulse ? 0.14 : 0.04))
            // Removed redundant animation modifier - withAnimation in onAppear handles this
        )

        let motionBlur: AnyView = AnyView(
            Path { p in
                let blurStart = Angle(degrees: endDeg - 3)
                let blurEnd   = Angle(degrees: endDeg)
                p.addArc(center: center,
                         radius: radius,
                         startAngle: blurStart,
                         endAngle: blurEnd,
                         clockwise: false)
            }
            .stroke(currentColor.opacity(reduceMotion ? 0.0 : 0.16), style: StrokeStyle(lineWidth: lineWidth * 0.45, lineCap: .round))
        )

        let coverGlass: AnyView = AnyView(
            Path { p in
                p.addArc(center: center,
                         radius: radius,
                         startAngle: .degrees(180),
                         endAngle: .degrees(360),
                         clockwise: false)
            }
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.white.opacity(0.08), location: 0),
                        .init(color: Color.white.opacity(0), location: 0.5)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        )

        let innerGlass: AnyView = AnyView(
            Path { p in
                p.addArc(center: center,
                         radius: radius - 2,
                         startAngle: .degrees(180),
                         endAngle: .degrees(360),
                         clockwise: false)
            }
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.white.opacity(0.04), location: 0),
                        .init(color: Color.white.opacity(0), location: 0.5)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        )

        // Base arc and ticks (using type-erased subviews)
        let baseTicks: AnyView = AnyView(
            BaseArcTicksView(center: center, radius: radius, lineWidth: lineWidth, arcGradient: arcGradient, tickLabelOpacityFactor: tickLabelOpacityFactor, showTicks: showTicks)
        )

        let needleLayer: AnyView = AnyView(
            NeedleLayerView(
                lineWidth: lineWidth,
                baseLeft: baseLeft,
                baseRight: baseRight,
                tip: tip,
                leftInner: leftInner,
                rightInner: rightInner,
                tipInset: tipInset,
                c1L: c1L,
                c2L: c2L,
                c1R: c1R,
                c2R: c2R,
                center: center,
                currentColor: currentColor,
                colorScheme: colorScheme
            )
        )

        let hubLayer: AnyView = AnyView(
            HubLayerView(
                lineWidth: lineWidth,
                endDeg: endDeg,
                center: center,
                currentColor: currentColor,
                reduceMotion: reduceMotion,
                tipPulse: tipPulse,
                colorScheme: colorScheme
            )
        )

        let liveBadge: AnyView = AnyView(
            LiveBadgeView(
                value: Int(disableBadgeAnimation ? clampedStatic : clampedAnimated),
                position: CGPoint(x: badgeX, y: badgeY),
                size: liveBadgeSize,
                currentColor: currentColor,
                tipPulse: tipPulse,
                refreshBounce: refreshBounce,
                disableAnimation: disableBadgeAnimation
            )
        )

        // Layer 1: base arc and ticks (using type-erased subviews)
        return AnyView(
            ZStack {
                baseTicks
                crescentHighlight
                motionBlur
                needleLayer
                hubLayer
                if showLiveBadge { liveBadge }
                coverGlass
                innerGlass
            }
        )
    }
}

// MARK: - BaseArcTicksView (extracted to reduce type-checking load)
private struct BaseArcTicksView: View {
    let center: CGPoint
    let radius: CGFloat
    let lineWidth: CGFloat
    let arcGradient: AngularGradient
    let tickLabelOpacityFactor: Double
    let showTicks: Bool

    private let majorMarks: [Double] = [0.0, 25.0, 50.0, 75.0, 100.0]
    private let labelMarks: [Double] = [25.0, 50.0, 75.0]

    var body: some View {
        // Type-erased sublayers to reduce type-checking load
        let backgroundArc: AnyView = AnyView(
            Path { p in
                p.addArc(center: center,
                         radius: radius,
                         startAngle: .degrees(180),
                         endAngle: .degrees(360),
                         clockwise: false)
            }
            .stroke(arcGradient, style: StrokeStyle(lineWidth: lineWidth * 0.8, lineCap: .round))
        )

        let majorTicksView: AnyView = AnyView(
            Group {
                if showTicks {
                    ForEach(majorMarks, id: \.self) { mark in
                        TickLineView(mark: mark, center: center, radius: radius, lineWidth: lineWidth)
                            .opacity(mark == 50 ? 0.50 : 0.35)
                    }
                }
            }
        )

        let minorTicksView: AnyView = AnyView(
            Group {
                if showTicks {
                    ForEach(Array(stride(from: 10.0, through: 90.0, by: 10.0)), id: \.self) { mark in
                        if mark.truncatingRemainder(dividingBy: 25) != 0 {
                            MinorTickLineView(mark: mark, center: center, radius: radius, lineWidth: lineWidth)
                                .opacity(0.20)
                        }
                    }
                }
            }
        )

        let labelsView: AnyView = AnyView(
            Group {
                if showTicks {
                    ForEach(labelMarks, id: \.self) { mark in
                        TickLabelView(mark: mark, center: center, radius: radius, lineWidth: lineWidth, opacityFactor: tickLabelOpacityFactor)
                    }
                }
            }
        )

        return Group {
            backgroundArc
            majorTicksView
            minorTicksView
            labelsView
        }
    }
}

// MARK: - Gauge helper views (to reduce type-checking complexity)
private struct NeedleLayerView: View {
    let lineWidth: CGFloat
    let baseLeft: CGPoint
    let baseRight: CGPoint
    let tip: CGPoint
    let leftInner: CGPoint
    let rightInner: CGPoint
    let tipInset: CGPoint
    let c1L: CGPoint
    let c2L: CGPoint
    let c1R: CGPoint
    let c2R: CGPoint
    let center: CGPoint
    let currentColor: Color
    let colorScheme: ColorScheme
    
    // MARK: - Adaptive colors for light/dark mode
    // Light mode: silver/metallic needle; Dark mode: dark steel needle
    private var isDark: Bool { colorScheme == .dark }
    
    // Needle body colors - light mode uses silver gradient, dark mode uses black
    private var needleBodyColorTop: Color {
        isDark ? Color.black.opacity(0.85) : Color(red: 0.42, green: 0.45, blue: 0.50).opacity(0.95)
    }
    private var needleBodyColorBottom: Color {
        isDark ? Color.black.opacity(0.6) : Color(red: 0.32, green: 0.35, blue: 0.40).opacity(0.88)
    }
    private var shadowOpacity: Double { isDark ? 0.22 : 0.15 }
    private var strokeHighlightOpacity: Double { isDark ? 0.12 : 0.35 }
    private var spineHighlightOpacityTop: Double { isDark ? 0.55 : 0.25 }
    private var hairlineOpacity: Double { isDark ? 0.18 : 0.25 }
    private var fineOutlineOpacity: Double { isDark ? 0.35 : 0.20 }
    private var outerEdgeOpacity: Double { isDark ? 0.12 : 0.10 }

    var body: some View {
        // Type-erased sublayers to reduce type-checking load
        let castShadow: AnyView = AnyView(
            Path { p in
                let left  = CGPoint(x: baseLeft.x - lineWidth * 0.2, y: baseLeft.y)
                let right = CGPoint(x: baseRight.x + lineWidth * 0.2, y: baseRight.y)
                p.move(to: left)
                p.addLine(to: tip)
                p.addLine(to: right)
                p.addQuadCurve(to: left, control: center)
                p.closeSubpath()
            }
            .fill(Color.black.opacity(shadowOpacity))
            .offset(x: 0, y: isDark ? 2 : 1)
            .allowsHitTesting(false)
        )

        let mainBody: AnyView = AnyView(
            Path { p in
                let left  = CGPoint(x: baseLeft.x - lineWidth * 0.2, y: baseLeft.y)
                let right = CGPoint(x: baseRight.x + lineWidth * 0.2, y: baseRight.y)
                p.move(to: left)
                p.addLine(to: tip)
                p.addLine(to: right)
                p.addQuadCurve(to: left, control: center)
                p.closeSubpath()
            }
            .fill(LinearGradient(gradient: Gradient(colors: [
                needleBodyColorTop,
                needleBodyColorBottom
            ]), startPoint: .top, endPoint: .bottom))
            .overlay(
                Path { p in
                    let left  = CGPoint(x: baseLeft.x - lineWidth * 0.2, y: baseLeft.y)
                    let right = CGPoint(x: baseRight.x + lineWidth * 0.2, y: baseRight.y)
                    p.move(to: left)
                    p.addLine(to: tip)
                    p.addLine(to: right)
                }
                .stroke(Color.white.opacity(strokeHighlightOpacity), lineWidth: isDark ? 1.2 : 1.0)
            )
        )

        let innerCore: AnyView = AnyView(
            Path { p in
                p.move(to: leftInner)
                p.addCurve(to: tipInset, control1: c1L, control2: c2L)
                p.addCurve(to: rightInner, control1: c1R, control2: c2R)
                p.addQuadCurve(to: leftInner, control: center)
                p.closeSubpath()
            }
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        currentColor.opacity(0.95),
                        currentColor.opacity(0.45)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .opacity(0.6)
            .allowsHitTesting(false)
        )

        let spineHighlight: AnyView = AnyView(
            Path { p in
                let midLeft  = CGPoint(x: baseLeft.x - lineWidth * 0.05, y: baseLeft.y)
                let midRight = CGPoint(x: baseRight.x + lineWidth * 0.05, y: baseRight.y)
                p.move(to: midLeft)
                p.addLine(to: tip)
                p.addLine(to: midRight)
            }
            .stroke(LinearGradient(gradient: Gradient(colors: [
                Color.white.opacity(spineHighlightOpacityTop),
                Color.white.opacity(0.0)
            ]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
            .allowsHitTesting(false)
        )

        let hairlineRidge: AnyView = AnyView(
            Path { p in
                let midLeft  = CGPoint(x: baseLeft.x - lineWidth * 0.03, y: baseLeft.y)
                let midRight = CGPoint(x: baseRight.x + lineWidth * 0.03, y: baseRight.y)
                p.move(to: midLeft)
                p.addLine(to: tip)
                p.addLine(to: midRight)
            }
            .stroke(Color.white.opacity(hairlineOpacity), lineWidth: 0.3)
            .allowsHitTesting(false)
        )

        let fineOutline: AnyView = AnyView(
            Path { p in
                let left  = CGPoint(x: baseLeft.x - lineWidth * 0.2, y: baseLeft.y)
                let right = CGPoint(x: baseRight.x + lineWidth * 0.2, y: baseRight.y)
                p.move(to: left)
                p.addLine(to: tip)
                p.addLine(to: right)
            }
            .stroke(Color.black.opacity(fineOutlineOpacity), lineWidth: 0.6)
            .allowsHitTesting(false)
        )

        let outerLightEdge: AnyView = AnyView(
            Path { p in
                let left  = CGPoint(x: baseLeft.x - lineWidth * 0.2, y: baseLeft.y)
                let right = CGPoint(x: baseRight.x + lineWidth * 0.2, y: baseRight.y)
                p.move(to: left)
                p.addLine(to: tip)
                p.addLine(to: right)
            }
            .stroke(Color.white.opacity(outerEdgeOpacity), lineWidth: 0.6)
            .allowsHitTesting(false)
        )

        let tipGlow: AnyView = AnyView(
            Group {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                currentColor.opacity(0.24),
                                currentColor.opacity(0.0)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: lineWidth * 1.0
                        )
                    )
                    .frame(width: lineWidth * 2.0, height: lineWidth * 2.0)
                    .position(tip)
                    .allowsHitTesting(false)
            }
        )

        return Group {
            castShadow
            mainBody
            innerCore
            spineHighlight
            hairlineRidge
            fineOutline
            outerLightEdge
            tipGlow
        }
    }
}

private struct HubLayerView: View {
    let lineWidth: CGFloat
    let endDeg: Double
    let center: CGPoint
    let currentColor: Color
    let reduceMotion: Bool
    let tipPulse: Bool
    let colorScheme: ColorScheme
    
    // MARK: - Adaptive colors for light/dark mode
    // Light mode: silver/gray metallic look; Dark mode: dark steel look
    private var isDark: Bool { colorScheme == .dark }
    
    // Plate body colors - light mode uses silver gradient, dark mode uses black
    private var plateBodyColorTop: Color {
        isDark ? Color.black.opacity(0.85) : Color(red: 0.45, green: 0.48, blue: 0.52).opacity(0.95)
    }
    private var plateBodyColorBottom: Color {
        isDark ? Color.black.opacity(0.65) : Color(red: 0.35, green: 0.38, blue: 0.42).opacity(0.90)
    }
    private var plateShadowOpacity: Double { isDark ? 0.28 : 0.18 }
    private var plateStrokeColor: Color {
        isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.45)
    }
    private var plateInnerStrokeOpacity: Double { isDark ? 0.35 : 0.15 }
    private var rimOuterOpacity: Double { isDark ? 0.08 : 0.30 }
    
    // Axle bar colors
    private var axleBarColorTop: Color {
        isDark ? Color.black.opacity(0.85) : Color(red: 0.40, green: 0.43, blue: 0.47).opacity(0.95)
    }
    private var axleBarColorBottom: Color {
        isDark ? Color.black.opacity(0.55) : Color(red: 0.30, green: 0.33, blue: 0.37).opacity(0.90)
    }

    var body: some View {
        let plateSize = lineWidth * 3.6
        let collarSize = lineWidth * 2.8
        let axleSize = lineWidth * 1.4

        // Type-erased sublayers to reduce type-checking load
        let plateShadow: AnyView = AnyView(
            Circle()
                .fill(Color.black.opacity(plateShadowOpacity))
                .frame(width: plateSize, height: plateSize)
                .offset(y: 1.0)
        )

        let plateBody: AnyView = AnyView(
            Circle()
                .fill(LinearGradient(gradient: Gradient(colors: [
                    plateBodyColorTop,
                    plateBodyColorBottom
                ]), startPoint: .top, endPoint: .bottom))
                .frame(width: plateSize, height: plateSize)
                .overlay(Circle().stroke(plateStrokeColor, lineWidth: isDark ? 0.8 : 1.2))
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(plateInnerStrokeOpacity), lineWidth: 1.0)
                        .offset(y: 0.4)
                        .mask(Circle())
                )
        )

        let rimOuter: AnyView = AnyView(
            Circle()
                .stroke(Color.white.opacity(rimOuterOpacity), lineWidth: max(0.6, lineWidth * 0.10))
                .frame(width: collarSize * 0.96, height: collarSize * 0.96)
        )

        // Static pulse ring - removed problematic repeatForever animation
        // that was causing the circle to jump/flicker on view re-renders
        let pulseRing: AnyView = AnyView(
            Circle()
                .stroke(currentColor.opacity(isDark ? 0.15 : 0.25), lineWidth: max(0.4, lineWidth * 0.08))
                .frame(width: collarSize * 0.98, height: collarSize * 0.98)
        )

        let dashedRingOpacity: Double = isDark ? 0.06 : 0.25
        let dashedRing: AnyView = AnyView(
            Circle()
                .stroke(Color.white.opacity(dashedRingOpacity), style: StrokeStyle(lineWidth: max(0.5, lineWidth * 0.08), lineCap: .round, dash: [max(0.5, lineWidth * 0.18), max(0.9, lineWidth * 0.30)]))
                .frame(width: collarSize * 0.90, height: collarSize * 0.90)
        )

        let innerRimOpacity: Double = isDark ? 0.10 : 0.35
        let innerRim: AnyView = AnyView(
            Circle()
                .stroke(Color.white.opacity(innerRimOpacity), lineWidth: max(0.6, lineWidth * 0.12))
                .frame(width: collarSize * 0.86, height: collarSize * 0.86)
        )

        let centerShadeOpacity: Double = isDark ? 0.35 : 0.10
        let centerShade: AnyView = AnyView(
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.black.opacity(centerShadeOpacity), location: 0.0),
                            .init(color: Color.black.opacity(0.0), location: 0.9)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: collarSize * 0.46
                    )
                )
                .frame(width: collarSize * 0.92, height: collarSize * 0.92)
                .opacity(isDark ? 0.45 : 0.20)
        )

        let axleBarStrokeOpacity: Double = isDark ? 0.15 : 0.40
        let axleBar: AnyView = AnyView(
            Capsule(style: .continuous)
                .fill(LinearGradient(gradient: Gradient(colors: [
                    axleBarColorTop,
                    axleBarColorBottom
                ]), startPoint: .top, endPoint: .bottom))
                .frame(width: axleSize * 1.25, height: max(1.2, lineWidth * 0.22))
                .overlay(Capsule().stroke(Color.white.opacity(axleBarStrokeOpacity), lineWidth: isDark ? 0.3 : 0.5))
                .rotationEffect(.degrees(endDeg))
                .opacity(0.9)
        )

        let hubShine1Opacity: Double = isDark ? 0.14 : 0.30
        let hubShine1: AnyView = AnyView(
            Circle()
                .trim(from: 0.10, to: 0.24)
                .stroke(Color.white.opacity(hubShine1Opacity), style: StrokeStyle(lineWidth: max(0.5, axleSize * 0.16), lineCap: .round))
                .frame(width: axleSize * 1.06, height: axleSize * 1.06)
                .rotationEffect(.degrees(-12))
        )

        let hubShine2Opacity: Double = isDark ? 0.18 : 0.35
        let hubShine2: AnyView = AnyView(
            Circle()
                .trim(from: 0.58, to: 0.92)
                .stroke(Color.white.opacity(hubShine2Opacity), style: StrokeStyle(lineWidth: max(0.8, plateSize * 0.06), lineCap: .round))
                .rotationEffect(.degrees(-18))
                .frame(width: plateSize, height: plateSize)
                .accessibilityHidden(true)
        )

        return ZStack {
            plateShadow
            plateBody
            rimOuter
            pulseRing
            dashedRing
            innerRim
            centerShade
            axleBar
            hubShine1
            hubShine2
        }
        .position(center)
        .accessibilityHidden(true)
    }
}

// MARK: - LiveBadgeView
struct LiveBadgeView: View {
    let value: Int
    let position: CGPoint
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let currentColor: Color
    let tipPulse: Bool
    let refreshBounce: Bool
    let disableAnimation: Bool

    @State private var fade: Double = 1.0
    @State private var hasCompletedInitialLoad: Bool = false  // PERFORMANCE FIX v9

    private var textSize: CGFloat { max(9, size * 0.60) }

    var body: some View {
        // Clean, premium badge — no bezels/halos/rotation

            let glassStops: [Gradient.Stop] = [
                .init(color: currentColor.opacity(0.80), location: 0.0),
                .init(color: currentColor.opacity(0.55), location: 0.55),
                .init(color: Color.black.opacity(0.30), location: 1.0)
            ]
            let innerRingWidth: CGFloat = max(0.5, size * 0.04)
            let highlightRangeFrom: CGFloat = 0.62
            let highlightRangeTo: CGFloat = 0.78
            // Replaced entire valueScale computation with:
            let valueScale: CGFloat = 1.0

        ZStack {
            // Soft lift shadow
            Circle()
                .fill(Color.black.opacity(0.35))
                .frame(width: size, height: size)
                .offset(y: 1)
                .accessibilityHidden(true)

            // Glass core — matte coin to blend with gauge
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: glassStops),
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    // Thin rim
                    Circle().stroke(currentColor.opacity(0.55), lineWidth: 1.4)
                )
                .overlay(
                    // Inner bevel
                    Circle()
                        .stroke(Color.black.opacity(0.25), lineWidth: 1.0)
                        .offset(y: 0.4)
                        .mask(Circle())
                )
                .overlay(
                    // Inner ring sheen
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: innerRingWidth)
                        .frame(width: size * 0.78, height: size * 0.78)
                )

            // Static highlight (no motion) — subtle
            Circle()
                .trim(from: highlightRangeFrom, to: highlightRangeTo)
                .stroke(Color.white.opacity(0.24), style: StrokeStyle(lineWidth: max(0.8, size * 0.08), lineCap: .round))
                .rotationEffect(.degrees(-25))
                .frame(width: size * 0.95, height: size * 0.95)
                .accessibilityHidden(true)

            // Value text
            Text("\(value)")
                .font(.system(size: textSize, weight: .medium, design: .default))
                .fontWidth(.condensed)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundColor(.white.opacity(0.92))
                .overlay(
                    LinearGradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0.0)], startPoint: .top, endPoint: .bottom)
                        .mask(
                            Text("\(value)")
                                .font(.system(size: textSize, weight: .medium, design: .default))
                                .fontWidth(.condensed)
                        )
                )
        }
        .scaleEffect(valueScale)
        .frame(width: size + 6, height: size + 6)
        .position(position)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.35, dampingFraction: 0.75), value: position)
        .opacity(disableAnimation ? fade : 1.0)
        .onAppear {
            fade = 1.0
            // PERFORMANCE FIX v9: Delay enabling onChange to prevent startup warnings
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                hasCompletedInitialLoad = true
            }
        }
        .onChange(of: value) { oldValue, newValue in
            // PERFORMANCE FIX v11: Skip during global startup phase
            guard !isInGlobalStartupPhase() else { return }
            
            // PERFORMANCE FIX v9: Skip until initial load completes
            guard hasCompletedInitialLoad else { return }
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            guard disableAnimation, !reduceMotion else { return }
            guard abs(newValue - oldValue) >= 1 else { return }
            
            withAnimation(.easeInOut(duration: 0.08)) { fade = 0.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeInOut(duration: 0.10)) { fade = 1.0 }
            }
        }
        .zIndex(1)
        .accessibilityHidden(true)
    }
}

// MARK: - SmallBadgeView (compact, right-column)
struct SmallBadgeView: View {
    let valueText: String
    let size: CGFloat
    let color: Color

    private var textSize: CGFloat { max(9, size * 0.60) }

    var body: some View {
            let glassStops: [Gradient.Stop] = [
                .init(color: color.opacity(0.85), location: 0.0),
                .init(color: color.opacity(0.55), location: 0.55),
                .init(color: Color.black.opacity(0.45), location: 1.0)
            ]
            let innerRingWidth: CGFloat = max(0.5, size * 0.04)
            let highlightRangeFrom: CGFloat = 0.60
            let highlightRangeTo: CGFloat = 0.78

        ZStack {
            // Glassy core with crisp ring
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: glassStops),
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )
                .overlay(Circle().stroke(color.opacity(0.7), lineWidth: 1.4))
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.35), lineWidth: 1.0)
                        .offset(y: 0.4)
                        .mask(Circle())
                )
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.black.opacity(0.22), location: 0.0),
                                    .init(color: Color.black.opacity(0.0), location: 1.0)
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.55
                            )
                        )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: innerRingWidth)
                        .frame(width: size * 0.82, height: size * 0.82)
                )

            // Static highlight to match live badge
            Circle()
                .trim(from: highlightRangeFrom, to: highlightRangeTo)
                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: max(0.9, size * 0.12), lineCap: .round))
                .rotationEffect(.degrees(-25))
                .frame(width: size * 0.95, height: size * 0.95)
                .accessibilityHidden(true)

            // Value text — slimmer, neutral digits to match live badge
            Text(valueText)
                .font(.system(size: textSize, weight: .medium, design: .default))
                .fontWidth(.condensed)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundColor(.white.opacity(0.93))
                .overlay(
                    LinearGradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0.0)], startPoint: .top, endPoint: .bottom)
                        .mask(
                            Text(valueText)
                                .font(.system(size: textSize, weight: .medium, design: .default))
                                .fontWidth(.condensed)
                        )
                )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - RightColumnSkeleton (placeholder while switching/loading)
private struct RightColumnSkeleton: View {
    let rowHeight: CGFloat
    let rows: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rows, id: \.self) { i in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 42, height: 8)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                            .frame(width: 64, height: 10)
                    }
                    Spacer()
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 22, height: 22)
                }
                .padding(.horizontal, 6)
                .frame(height: rowHeight)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: i < rows - 1 ? 1 : 0)
                        .padding(.horizontal, 10)
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

// MARK: - Double Extension

private extension Double {
    var radians: CGFloat { CGFloat(self) * .pi / 180 }
}

// MARK: - TickLineView

struct TickLineView: View {
    let mark: Double, center: CGPoint, radius: CGFloat, lineWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var rad: CGFloat {
        CGFloat(Angle(degrees: 180 + (mark / 100) * 180).radians)
    }
    private var inner: CGPoint {
        CGPoint(
            x: center.x + cos(rad) * (radius - lineWidth/2),
            y: center.y + sin(rad) * (radius - lineWidth/2)
        )
    }
    private var outer: CGPoint {
        let extra: CGFloat = (mark == 50) ? 4 : 2
        return CGPoint(
            x: center.x + cos(rad) * (radius + lineWidth/2 + extra),
            y: center.y + sin(rad) * (radius + lineWidth/2 + extra)
        )
    }
    
    // Adaptive tick color for light/dark mode
    private var tickColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    var body: some View {
        Path { p in
            p.move(to: inner)
            p.addLine(to: outer)
        }
        .stroke(tickColor.opacity(mark == 50 ? 0.5 : 1),
                style: StrokeStyle(lineWidth: 2, lineCap: .butt))
    }
}

// MARK: - MinorTickLineView
struct MinorTickLineView: View {
    let mark: Double, center: CGPoint, radius: CGFloat, lineWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var rad: CGFloat {
        CGFloat(Angle(degrees: 180 + (mark / 100) * 180).radians)
    }
    private var inner: CGPoint {
        CGPoint(
            x: center.x + cos(rad) * (radius - lineWidth/2),
            y: center.y + sin(rad) * (radius - lineWidth/2)
        )
    }
    private var outer: CGPoint {
        CGPoint(
            x: center.x + cos(rad) * (radius + lineWidth/2 + 0.0),
            y: center.y + sin(rad) * (radius + lineWidth/2 + 0.0)
        )
    }
    
    private var tickOpacity: Double {
        let d = abs(mark - 50)
        // Taper from 0.6 at the edges to ~0.45 near the center (40 points span)
        let t = max(0.0, 1.0 - d / 40.0)
        // UPDATED OPACITY TAPER (slightly increased)
        return 0.65 - 0.15 * t
    }
    
    // Adaptive tick color for light/dark mode
    private var tickColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    var body: some View {
        Path { p in
            p.move(to: inner)
            p.addLine(to: outer)
        }
        .stroke(tickColor.opacity(tickOpacity), style: StrokeStyle(lineWidth: 1, lineCap: .butt))
    }
}

// MARK: - TickLabelView

struct TickLabelView: View {
    let mark: Double, center: CGPoint, radius: CGFloat, lineWidth: CGFloat
    let opacityFactor: Double

    private var rad: CGFloat {
        CGFloat(Angle(degrees: 180 + (mark / 100) * 180).radians)
    }
    private var labelRadius: CGFloat {
        switch mark {
        case 50:  return radius - lineWidth * 1.6
        default:  return radius - lineWidth * 1.1 - 2
        }
    }
    private var pos: CGPoint {
        CGPoint(
            x: center.x + cos(rad) * labelRadius,
            y: center.y + sin(rad) * labelRadius
        )
    }

    var body: some View {
        Text("\(Int(mark))")
            .font(.system(size: 9, weight: .bold))
            .monospacedDigit()
            .opacity((mark == 50 ? 0.65 : 0.58) * opacityFactor)
            .foregroundColor(DS.Adaptive.textPrimary)
            .position(x: pos.x, y: pos.y)
    }
}

// MARK: - GaugeEndCapsOverlay (minus/plus at arc ends)
private struct GaugeEndCapsOverlay: View {
    let lineWidth: CGFloat

    private func point(center: CGPoint, radius: CGFloat, mark: Double, offset: CGFloat) -> CGPoint {
        let deg = 180 + (mark / 100.0) * 180.0
        let r = radius + offset
        let rad = CGFloat(deg) * .pi / 180
        return CGPoint(x: center.x + cos(rad) * r, y: center.y + sin(rad) * r)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let radius = (min(w, h * 2) / 2 - lineWidth / 2) * 0.96
            let centerLift = lineWidth * 0.8
            let center = CGPoint(x: w / 2, y: h - centerLift)
            let offset = lineWidth * 0.9 + 6

            ZStack {
                Image(systemName: "minus")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white.opacity(0.5))
                    .position(point(center: center, radius: radius, mark: 0, offset: offset))
                Image(systemName: "plus")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white.opacity(0.5))
                    .position(point(center: center, radius: radius, mark: 100, offset: offset))
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Preference Keys (local)
private struct SourceButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    // THREAD SAFETY: Use NSLock to protect static mutable state
    private static let lock = NSLock()
    private static var _lastUpdateAt: CFTimeInterval = 0
    private static var _hasInitialized: Bool = false
    
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        // Ignore zero frames
        guard next != .zero else { return }
        
        let now = CACurrentMediaTime()
        
        lock.lock()
        defer { lock.unlock() }
        
        // PERFORMANCE FIX v7: After initial value, throttle to 0.5Hz (every 2s)
        // Button frame rarely changes - only on rotation/resize
        if _hasInitialized {
            guard now - _lastUpdateAt >= 2.0 else { return }
        }
        
        // Ignore jitter < 5px
        let dx = abs(next.origin.x - value.origin.x)
        let dy = abs(next.origin.y - value.origin.y)
        let dw = abs(next.size.width - value.size.width)
        let dh = abs(next.size.height - value.size.height)
        if dx < 5 && dy < 5 && dw < 5 && dh < 5 { return }
        
        value = next
        _lastUpdateAt = now
        _hasInitialized = true
    }
}

// MARK: - Source Picker (elegant list style)
// PROFESSIONAL UX: Selection confirmation, press states, and smooth transitions

// FIX: Changed from private to internal so HomeView can render this above the ScrollView
struct SourcePickerPopover: View {
    @Binding var isPresented: Bool
    let selected: SentimentSource
    let anchorRect: CGRect
    let onSelect: (SentimentSource) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    // PROFESSIONAL UX: Track pending selection for immediate visual feedback
    @State private var pendingSelection: SentimentSource? = nil
    @State private var isClosing: Bool = false
    
    private var sources: [SentimentSource] {
        SentimentSource.availableSources
    }
    
    // The visually selected item (pending selection takes precedence for immediate feedback)
    private var visuallySelected: SentimentSource {
        pendingSelection ?? selected
    }
    
    // Adaptive colors for light/dark mode
    private var backdropColor: Color { isDark ? Color.black.opacity(0.55) : Color.black.opacity(0.3) }
    private var headerTextColor: Color { isDark ? .white.opacity(0.9) : .black.opacity(0.85) }
    private var closeButtonTextColor: Color { isDark ? .white.opacity(0.4) : .black.opacity(0.4) }
    private var closeButtonBgColor: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
    private var dividerColors: [Color] { 
        isDark 
            ? [Color.white.opacity(0.0), Color.white.opacity(0.1), Color.white.opacity(0.0)]
            : [Color.black.opacity(0.0), Color.black.opacity(0.08), Color.black.opacity(0.0)]
    }
    // OPACITY FIX: Use fully opaque background so content behind doesn't bleed through
    private var panelOverlayColor: Color { isDark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color(red: 0.97, green: 0.97, blue: 0.97) }
    private var strokeColors: [Color] {
        isDark 
            ? [Color.white.opacity(0.2), Color.white.opacity(0.08)]
            : [Color.black.opacity(0.08), Color.black.opacity(0.04)]
    }
    private var shadowColor: Color { isDark ? Color.black.opacity(0.5) : Color.black.opacity(0.15) }

    var body: some View {
        // FIX: Rendered in HomeView's root ZStack above ScrollView, so the
        // GeometryReader fills the full screen without scroll clipping.
        GeometryReader { geo in
            ZStack {
                // Full-screen backdrop
                backdropColor
                    .ignoresSafeArea()
                    .onTapGesture {
                        guard !isClosing else { return }
                        isPresented = false
                    }
                
                // Elegant picker panel positioned relative to the source button
                sourcePickerPanel
                    .position(panelPosition(in: geo))
                    .transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isPresented)
    }
    
    private var sourcePickerPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BrandColors.goldBase)
                    Text("Data Source")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(headerTextColor)
                }
                Spacer()
                Button(action: {
                    guard !isClosing else { return }
                    isPresented = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(closeButtonTextColor)
                        .frame(width: 20, height: 20)
                        .background(closeButtonBgColor, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            
            // Divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: dividerColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 8)
            
            // Source options
            VStack(spacing: 4) {
                ForEach(sources, id: \.self) { source in
                    sourceRow(for: source)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        // PERFORMANCE FIX v19: Replaced .ultraThinMaterial with solid color overlay
        // Material effects perform real-time Gaussian blur every frame during scroll
        // OPACITY FIX: Use fully opaque background so picker panel isn't see-through
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(panelOverlayColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: strokeColors,
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .frame(width: 230)
    }
    
    @ViewBuilder
    private func sourceRow(for source: SentimentSource) -> some View {
        // PROFESSIONAL UX: Use visuallySelected to show immediate feedback on tap
        let isSelected = (source == visuallySelected)
        let isNewSelection = source == pendingSelection && source != selected
        let isEnabled = source.isImplemented
        
        // Adaptive row colors
        let primaryTextColor: Color = isDark 
            ? (isSelected ? .white : (isEnabled ? .white.opacity(0.9) : .white.opacity(0.4)))
            : (isSelected ? .black : (isEnabled ? .black.opacity(0.85) : .black.opacity(0.35)))
        let secondaryTextColor: Color = isDark 
            ? (isEnabled ? .white.opacity(0.5) : .white.opacity(0.25))
            : (isEnabled ? .black.opacity(0.5) : .black.opacity(0.25))
        let rowBgColor: Color = isDark 
            ? (isSelected ? BrandColors.goldBase.opacity(0.12) : Color.white.opacity(0.03))
            : (isSelected ? BrandColors.goldBase.opacity(0.12) : Color.black.opacity(0.03))
        let rowStrokeColor: Color = isDark 
            ? (isSelected ? BrandColors.goldBase.opacity(0.4) : Color.white.opacity(0.06))
            : (isSelected ? BrandColors.goldBase.opacity(0.5) : Color.black.opacity(0.06))
        
        Button {
            guard isEnabled, !isClosing else { return }
            
            #if os(iOS)
            // Stronger haptic for selection confirmation
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            
            // If tapping the already-selected item, just close immediately
            if source == selected {
                isPresented = false
                return
            }
            
            // PROFESSIONAL UX: Show selection confirmation before closing
            // 1. Immediately highlight the tapped item
            withAnimation(.easeOut(duration: 0.15)) {
                pendingSelection = source
            }
            
            // 2. Trigger the actual selection change
            onSelect(source)
            
            // 3. Brief delay to show the highlight, then close smoothly
            isClosing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 0.15)) {
                    isPresented = false
                }
            }
        } label: {
            HStack(spacing: 10) {
                // Name and description
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.displayName)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(primaryTextColor)
                    Text(descriptionForSource(source))
                        .font(.system(size: 10))
                        .foregroundStyle(secondaryTextColor)
                }
                
                Spacer()
                
                // Checkmark for selected
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(BrandColors.goldBase)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(rowBgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(rowStrokeColor, lineWidth: isDark ? 1 : 0.5)
            )
            // PROFESSIONAL UX: Subtle scale animation for new selection confirmation
            .scaleEffect(isNewSelection ? 1.02 : 1.0)
        }
        .buttonStyle(SourceRowButtonStyle())
        .disabled(!isEnabled)
    }
    
    private func descriptionForSource(_ source: SentimentSource) -> String {
        switch source {
        case .derived: return "AI-powered analysis"
        case .alternativeMe: return "Fear & Greed Index"
        case .coinMarketCap: return "Market sentiment data"
        case .unusualWhales: return "Whale activity signals"
        case .coinglass: return "Derivatives sentiment"
        }
    }
    
    private func panelPosition(in geo: GeometryProxy) -> CGPoint {
        let containerGlobal = geo.frame(in: .global)
        let screenBounds = containerGlobal
        
        // Estimate panel height
        let estimatedHeight: CGFloat = 50 + CGFloat(sources.count) * 56 + 16
        
        // Position above the anchor button
        let globalY: CGFloat
        let spaceAbove = anchorRect.minY - screenBounds.minY - 60
        let spaceBelow = screenBounds.maxY - anchorRect.maxY - 20
        
        if spaceAbove >= estimatedHeight || spaceAbove >= spaceBelow {
            // Place above
            globalY = anchorRect.minY - 8 - estimatedHeight / 2
        } else {
            // Place below
            globalY = anchorRect.maxY + 8 + estimatedHeight / 2
        }
        
        // Horizontal: center on anchor, clamped to screen edges
        let panelWidth: CGFloat = 230
        let halfW = panelWidth / 2
        var globalX = anchorRect.midX
        globalX = max(12 + halfW, min(screenBounds.width - 12 - halfW, globalX))
        
        // Convert to local coordinates
        let localX = globalX - containerGlobal.minX
        let localY = globalY - containerGlobal.minY
        
        return CGPoint(x: localX, y: localY)
    }
}

// PROFESSIONAL UX: Button style with press state feedback for source rows
struct SourceRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}