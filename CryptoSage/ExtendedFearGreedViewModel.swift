import Foundation
import Combine
import UIKit

// MARK: - SentimentSource

enum SentimentSource: String, CaseIterable, Identifiable, Codable, Hashable {
    case derived = "on-device"
    case alternativeMe = "alternative.me"
    case coinMarketCap = "coinmarketcap.com"
    case unusualWhales = "unusualwhales.com"
    case coinglass = "coinglass.com"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alternativeMe: return "alternative.me"
        case .coinMarketCap: return "CoinMarketCap"
        case .unusualWhales: return "Unusual Whales"
        case .coinglass: return "Coinglass"
        case .derived: return "CryptoSage AI"
        }
    }

    /// Whether this source currently has an implemented fetcher in the app.
    var isImplemented: Bool {
        switch self {
        case .alternativeMe, .coinMarketCap, .unusualWhales, .coinglass, .derived: return true
        }
    }
    
    /// Whether this source has valid API configuration and provides unique data.
    /// Sources without API keys configured just show alternative.me data, so they're hidden.
    var hasValidConfiguration: Bool {
        switch self {
        case .derived:
            // CryptoSage AI always works (local computation)
            return true
        case .alternativeMe:
            // alternative.me always works (free public API)
            return true
        case .coinMarketCap:
            // Requires API key in Info.plist
            let endpoint = Bundle.main.infoDictionary?["CMC_SENTIMENT_URL"] as? String
            return endpoint != nil && !endpoint!.isEmpty
        case .unusualWhales:
            // Requires API key in Info.plist
            let endpoint = Bundle.main.infoDictionary?["UNUSUALWHALES_SENTIMENT_URL"] as? String
            return endpoint != nil && !endpoint!.isEmpty
        case .coinglass:
            // Requires API key in Info.plist
            let endpoint = Bundle.main.infoDictionary?["COINGLASS_SENTIMENT_URL"] as? String
            return endpoint != nil && !endpoint!.isEmpty
        }
    }
    
    /// Sources that should be shown in the picker (have unique data)
    static var availableSources: [SentimentSource] {
        return allCases.filter { $0.hasValidConfiguration }
    }
}

// MARK: - Data Models

struct FearGreedData: Codable {
    let value: String
    let value_classification: String
    let timestamp: String
    let time_until_update: String?  // only present on the latest data point

    // Friendly computed property for your UI
    var valueClassification: String { value_classification }
}

struct FearGreedResponse: Codable {
    let name: String
    let data: [FearGreedData]
    let metadata: FearGreedMetadata
}

struct FearGreedMetadata: Codable {
    let error: String?
}

// MARK: - ViewModel

final class ExtendedFearGreedViewModel: ObservableObject {
    /// Shared instance for global access (e.g., AI context building)
    static let shared = ExtendedFearGreedViewModel()
    
    @Published var isLoading: Bool      = false
    @Published var errorMessage: String?
    @Published var data: [FearGreedData] = []
    
    // MARK: - Source Picker State (shared so HomeView can overlay above ScrollView)
    /// Whether the source picker popover should be visible
    @Published var showSourcePicker: Bool = false
    /// The global frame of the source button (for positioning the picker)
    var sourcePickerAnchorFrame: CGRect = .zero
    
    /// Indicates if the current source is using alternative.me fallback data
    /// (true when API keys are not configured for the selected provider)
    @Published var isUsingFallback: Bool = false
    
    /// The source providing fallback data (typically "alternative.me")
    @Published var fallbackSourceName: String? = nil
    
    // MARK: - CryptoSage AI Market Metrics (only populated when source is .derived)
    /// Market breadth: percentage of top coins with positive 24h change (0-100)
    @Published var marketBreadth: Double? = nil
    /// BTC 24h change percentage
    @Published var btc24hChange: Double? = nil
    /// Market volatility/dispersion indicator (0 = calm, higher = volatile)
    @Published var marketVolatility: Double? = nil
    
    // MARK: - Live AI Observation (Firebase-backed)
    /// Live AI-generated full analysis (2-3 sentences, for detail view)
    @Published var liveAIObservation: String? = nil
    /// Live AI-generated short summary (1 sentence, for card display)
    @Published var liveAIObservationSummary: String? = nil
    /// Whether AI observation is currently being fetched
    @Published var isLoadingAIObservation: Bool = false
    /// Timestamp of last AI observation fetch (publicly accessible for display)
    @Published var lastAIObservationFetch: Date? = nil
    /// Minimum interval between AI observation fetches
    /// Extended to 4 hours since Fear & Greed Index updates only 1-2x daily
    private let aiObservationThrottleInterval: TimeInterval = 4 * 60 * 60 // 4 hours (extended from 15 min)
    
    // MARK: - Enhanced Firebase Sentiment (shared across all users)
    /// AI-computed sentiment score from Firebase (0-100)
    @Published var firebaseSentimentScore: Int? = nil
    /// AI-computed sentiment verdict ("Extreme Fear", "Fear", "Neutral", "Greed", "Extreme Greed")
    @Published var firebaseSentimentVerdict: String? = nil
    /// Confidence level of the AI analysis (0-100)
    @Published var firebaseSentimentConfidence: Int? = nil
    /// Key factors driving the AI sentiment analysis
    @Published var firebaseSentimentKeyFactors: [String]? = nil
    
    // MARK: - Fear & Greed AI Commentary
    /// AI commentary explaining the current Fear & Greed value (shared across all users with same F&G value)
    @Published var fearGreedCommentary: String? = nil
    /// Whether F&G commentary is currently being fetched
    @Published var isLoadingFearGreedCommentary: Bool = false
    /// Last F&G value for which commentary was fetched
    private var lastFearGreedCommentaryValue: Int? = nil
    
    // MARK: - AI Cache Persistence Keys
    private let aiObservationCacheKey = "FearGreed.AIObservationCache"
    private let aiObservationSummaryCacheKey = "FearGreed.AIObservationSummaryCache"
    private let aiObservationFetchKey = "FearGreed.AIObservationFetchDate"
    private let fearGreedCommentaryCacheKey = "FearGreed.CommentaryCache"
    private let fearGreedCommentaryValueKey = "FearGreed.CommentaryValue"
    
    // LOG SPAM FIX: Throttle error logging to once every 5 minutes
    // Using static to share across all instances and prevent race conditions
    private static var lastFirebaseErrorLogAt: Date? = nil
    private static let firebaseErrorLogThrottleInterval: TimeInterval = 5 * 60 // 5 minutes
    
    private static func shouldLogFirebaseError() -> Bool {
        let now = Date()
        if lastFirebaseErrorLogAt == nil || now.timeIntervalSince(lastFirebaseErrorLogAt!) >= firebaseErrorLogThrottleInterval {
            lastFirebaseErrorLogAt = now
            return true
        }
        return false
    }
    
    // MARK: - AI Observation Daily Limits
    /// Daily AI observation limits per subscription tier (uses centralized SubscriptionManager values)
    private func aiObservationDailyLimit(for tier: SubscriptionTierType) -> Int {
        tier.fearGreedAIPerDay
    }
    
    private let aiObservationUsageKey = "FearGreed.AIObservationUsageToday"
    private let aiObservationUsageResetKey = "FearGreed.AIObservationUsageResetDate"
    @Published public private(set) var aiObservationsUsedToday: Int = 0
    private var aiObservationLastResetDate: Date = Date()
    
    /// Current user's daily AI observation limit
    @MainActor public var currentAIObservationLimit: Int {
        aiObservationDailyLimit(for: SubscriptionManager.shared.effectiveTier)
    }

    /// Whether user can generate a new AI observation
    @MainActor public var canGenerateAIObservation: Bool {
        // Developer mode bypasses all limits
        if SubscriptionManager.shared.isDeveloperMode { return true }
        checkAIObservationDailyReset()
        return aiObservationsUsedToday < currentAIObservationLimit
    }
    
    /// Remaining AI observations for today
    @MainActor public var remainingAIObservations: Int {
        checkAIObservationDailyReset()
        return max(0, currentAIObservationLimit - aiObservationsUsedToday)
    }
    
    private func checkAIObservationDailyReset() {
        if !Calendar.current.isDateInToday(aiObservationLastResetDate) {
            aiObservationsUsedToday = 0
            aiObservationLastResetDate = Date()
            saveAIObservationUsageState()
        }
    }
    
    private func loadAIObservationUsageState() {
        aiObservationsUsedToday = UserDefaults.standard.integer(forKey: aiObservationUsageKey)
        if let date = UserDefaults.standard.object(forKey: aiObservationUsageResetKey) as? Date {
            aiObservationLastResetDate = date
        }
        checkAIObservationDailyReset()
    }
    
    private func saveAIObservationUsageState() {
        UserDefaults.standard.set(aiObservationsUsedToday, forKey: aiObservationUsageKey)
        UserDefaults.standard.set(aiObservationLastResetDate, forKey: aiObservationUsageResetKey)
    }
    
    @MainActor private func recordAIObservationUsage() {
        // Don't count usage in developer mode (allows unlimited testing)
        if SubscriptionManager.shared.isDeveloperMode { return }
        checkAIObservationDailyReset()
        aiObservationsUsedToday += 1
        saveAIObservationUsageState()
    }
    
    // MARK: - AI Cache Persistence
    
    /// Load AI observation and commentary from disk
    private func loadAICacheFromDisk() {
        let defaults = UserDefaults.standard
        
        // Load AI observation (full analysis)
        if let observation = defaults.string(forKey: aiObservationCacheKey) {
            liveAIObservation = observation
        }
        // Load AI observation summary (short version for cards)
        if let summary = defaults.string(forKey: aiObservationSummaryCacheKey) {
            liveAIObservationSummary = summary
        }
        if let fetchDate = defaults.object(forKey: aiObservationFetchKey) as? Date {
            // Only use cached observation if it's still within the throttle interval
            if Date().timeIntervalSince(fetchDate) < aiObservationThrottleInterval {
                lastAIObservationFetch = fetchDate
            } else {
                // Cache expired, clear it
                liveAIObservation = nil
                liveAIObservationSummary = nil
            }
        }
        
        // Load Fear & Greed commentary
        if let commentary = defaults.string(forKey: fearGreedCommentaryCacheKey) {
            fearGreedCommentary = commentary
        }
        lastFearGreedCommentaryValue = defaults.object(forKey: fearGreedCommentaryValueKey) as? Int
        
        #if DEBUG
        if liveAIObservation != nil {
            print("[FearGreed] Loaded cached AI observation from disk")
        }
        if fearGreedCommentary != nil {
            print("[FearGreed] Loaded cached F&G commentary from disk")
        }
        #endif
    }
    
    /// Save AI observation to disk
    private func saveAIObservationToDisk() {
        let defaults = UserDefaults.standard
        if let observation = liveAIObservation {
            defaults.set(observation, forKey: aiObservationCacheKey)
        } else {
            defaults.removeObject(forKey: aiObservationCacheKey)
        }
        if let summary = liveAIObservationSummary {
            defaults.set(summary, forKey: aiObservationSummaryCacheKey)
        } else {
            defaults.removeObject(forKey: aiObservationSummaryCacheKey)
        }
        defaults.set(lastAIObservationFetch, forKey: aiObservationFetchKey)
    }
    
    /// Save Fear & Greed commentary to disk
    private func saveFearGreedCommentaryToDisk() {
        let defaults = UserDefaults.standard
        if let commentary = fearGreedCommentary {
            defaults.set(commentary, forKey: fearGreedCommentaryCacheKey)
        } else {
            defaults.removeObject(forKey: fearGreedCommentaryCacheKey)
        }
        if let value = lastFearGreedCommentaryValue {
            defaults.set(value, forKey: fearGreedCommentaryValueKey)
        } else {
            defaults.removeObject(forKey: fearGreedCommentaryValueKey)
        }
    }
    
    /// Updates market metrics from MarketViewModel (called when CryptoSage AI is active)
    /// retryCount tracks automatic retries when data isn't available yet (app startup)
    @MainActor
    func updateMarketMetrics(retryCount: Int = 0) {
        guard selectedSource == .derived else {
            // Clear metrics when not using CryptoSage AI
            marketBreadth = nil
            btc24hChange = nil
            marketVolatility = nil
            return
        }
        
        // Ensure persisted Firebase metrics are loaded (survives app restarts / cache hits)
        DerivedSentimentProvider.restorePersistedMetrics()
        
        // PRIORITY 1: Use Firebase-provided metrics if available (most reliable, server-calculated)
        if let firebaseBreadth = DerivedSentimentProvider.lastFirebaseBreadth {
            marketBreadth = Double(firebaseBreadth)
        }
        if let firebaseBTC24h = DerivedSentimentProvider.lastFirebaseBTC24h {
            btc24hChange = firebaseBTC24h
        }
        if let firebaseVol = DerivedSentimentProvider.lastFirebaseVolatility {
            marketVolatility = min(20.0, firebaseVol)
        }
        
        // PRIORITY 2: Fall back to local calculation if Firebase metrics not available
        let mv = MarketViewModel.shared
        let coins = !mv.allCoins.isEmpty ? mv.allCoins : (!mv.coins.isEmpty ? mv.coins : mv.watchlistCoins)
        
        // Exclude stablecoins from breadth calculation
        let stableSet: Set<String> = ["USDT","USDC","BUSD","DAI","FDUSD","TUSD","USDP","GUSD","FRAX","LUSD"]
        let nonStableCoins = coins.filter { !stableSet.contains($0.symbol.uppercased()) }
        
        // Calculate breadth (% of coins with positive 24h change) - only if Firebase didn't provide it
        if marketBreadth == nil {
            let coinsWithChange = nonStableCoins.compactMap { $0.priceChangePercentage24hInCurrency ?? $0.changePercent24Hr }
            if !coinsWithChange.isEmpty {
                let upCount = coinsWithChange.filter { $0 >= 0 }.count
                marketBreadth = (Double(upCount) / Double(coinsWithChange.count)) * 100.0
            }
        }
        
        // Get BTC 24h change - multiple fallback sources
        if btc24hChange == nil {
            // Try 1: LivePriceManager (most real-time)
            if let liveChange = LivePriceManager.shared.bestChange24hPercent(for: "BTC"), liveChange != 0 {
                btc24hChange = liveChange
            }
            // Try 2: MarketViewModel coins
            else if let btcCoin = coins.first(where: { $0.symbol.uppercased() == "BTC" }) {
                btc24hChange = btcCoin.priceChangePercentage24hInCurrency ?? btcCoin.changePercent24Hr
            }
            // Try 3: MarketViewModel allCoins specifically
            else if let btcCoin = mv.allCoins.first(where: { $0.symbol.uppercased() == "BTC" }) {
                btc24hChange = btcCoin.priceChangePercentage24hInCurrency ?? btcCoin.changePercent24Hr
            }
        }
        
        // Calculate volatility - only if Firebase didn't provide it
        if marketVolatility == nil {
            let coinsWithChange = nonStableCoins.compactMap { $0.priceChangePercentage24hInCurrency ?? $0.changePercent24Hr }
            // Use sample variance (n-1) for unbiased estimation
            if coinsWithChange.count >= 5 {
                let mean = coinsWithChange.reduce(0, +) / Double(coinsWithChange.count)
                let variance = coinsWithChange.reduce(0) { $0 + pow($1 - mean, 2) } / Double(coinsWithChange.count - 1)
                marketVolatility = min(20.0, sqrt(variance))
            }
        }
        
        // FIX: If any metrics are still nil, schedule a retry after a short delay.
        // This handles: (a) MarketViewModel not loaded yet, (b) Firebase statics not set yet
        // due to race conditions, (c) LivePriceManager not ready. Up to 4 retries over ~10s.
        let anyMissing = marketBreadth == nil || btc24hChange == nil || marketVolatility == nil
        if anyMissing && retryCount < 4 {
            let delay: Double = Double(retryCount + 1) * 2.0  // 2s, 4s, 6s, 8s
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self?.updateMarketMetrics(retryCount: retryCount + 1)
            }
        }
    }
    
    /// Returns the display name for the current source, with fallback indicator if applicable
    var sourceDisplayNameWithFallback: String {
        let baseName = selectedSource.displayName
        if isUsingFallback, let fallback = fallbackSourceName {
            return "\(baseName) (via \(fallback))"
        }
        return baseName
    }
    
    @Published var selectedSource: SentimentSource = {
        if let raw = UserDefaults.standard.string(forKey: "sentiment.selectedSource"),
           let s = SentimentSource(rawValue: raw),
           s.hasValidConfiguration {
            return s
        }
        // Default to CryptoSage AI (always available)
        return .derived
    }() {
        didSet {
            UserDefaults.standard.set(selectedSource.rawValue, forKey: "sentiment.selectedSource")
            // Defer all state modifications to avoid "Modifying state during view update"
            let cachedData: [FearGreedData]? = CacheManager.shared.load([FearGreedData].self, from: Self.cacheFile(for: selectedSource))
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Reset fallback status until we get new data
                self.isUsingFallback = false
                self.fallbackSourceName = nil
                // Immediately swap in any cached data for the newly selected source
                if let cached = cachedData, !cached.isEmpty {
                    self.data = cached
                }
                // FIX: Immediately populate metrics when switching to CryptoSage AI
                // This prevents empty Breadth/BTC 24h/Volatility fields while fetch is in progress
                if self.selectedSource == .derived {
                    self.updateMarketMetrics()
                } else {
                    // Clear CryptoSage AI-specific metrics when switching away
                    self.marketBreadth = nil
                    self.btc24hChange = nil
                    self.marketVolatility = nil
                }
                // Clear Firebase-specific detail data (only relevant for CryptoSage AI)
                // Prevents stale AI Score/Confidence/Key Factors showing for other sources
                if self.selectedSource != .derived {
                    self.firebaseSentimentScore = nil
                    self.firebaseSentimentConfidence = nil
                    self.firebaseSentimentVerdict = nil
                    self.firebaseSentimentKeyFactors = nil
                }
                // Clear previous error
                self.errorMessage = nil
                self.scheduleNextRefresh()
            }
            // PERFORMANCE FIX v20: Removed duplicate fetchData() call here.
            // The View's .onChange(of: vm.selectedSource) already calls requestFetch(force: true),
            // which calls fetchData(). Having both caused two concurrent network requests.
        }
    }
    
    static let sample: [FearGreedData] = [
        FearGreedData(value: "48", value_classification: "neutral", timestamp: String(Int(Date().timeIntervalSince1970)), time_until_update: nil),
        FearGreedData(value: "52", value_classification: "greed", timestamp: String(Int(Date().addingTimeInterval(-86400).timeIntervalSince1970)), time_until_update: nil)
    ]
    
    private static func cacheFile(for source: SentimentSource) -> String {
        return "fear_greed_cache_\(source.id).json"
    }
    
    /// One-shot warmup that fetches and caches data without instantiating timers
    /// PERFORMANCE: Only fetches from providers with valid configurations to avoid redundant API calls
    static func prewarm() async {
        // Only fetch from sources that have valid configurations
        // This avoids redundant alternative.me fallback calls from unconfigured providers
        let availableSources = SentimentSource.availableSources
        
        for source in availableSources {
            let prov: SentimentProvider
            switch source {
            case .derived: prov = DerivedSentimentProvider()
            case .alternativeMe: prov = AlternativeMeProvider()
            case .coinMarketCap: prov = CoinMarketCapProvider()
            case .unusualWhales: prov = UnusualWhalesProvider()
            case .coinglass: prov = CoinglassProvider()
            }
            
            do {
                let list = try await prov.fetch(limit: 10, timeout: 6)
                CacheManager.shared.save(list, to: cacheFile(for: source))
                
                // Small delay between fetches to avoid rate limiting
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            } catch {
                // Ignore missing keys or endpoints; prewarm is best-effort
            }
        }
    }
    
    // Conveniences for the view (UTC day‑anchored to match Alternative.me)
    var currentValue: Int? {
        guard let raw = data.first?.value else { return nil }
        return Int(raw)
    }
    
    // UTC calendar for day boundaries
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }
    
    // Latest entry whose timestamp is <= cutoff
    private func latestOnOrBefore(_ cutoff: Date) -> FearGreedData? {
        guard !data.isEmpty else { return nil }
        let cutoffSec = cutoff.timeIntervalSince1970
        // `data` is newest first, so return the first item not after cutoff
        for d in data {
            if let ts = Double(d.timestamp), ts <= cutoffSec {
                return d
            }
        }
        return data.last
    }
    
    // Data for N days ago, using the end of that UTC day as cutoff
    private func dataDaysAgo(_ days: Int) -> FearGreedData? {
        let startOfTodayUTC = utcCalendar.startOfDay(for: Date())
        let targetDayStart = startOfTodayUTC.addingTimeInterval(-Double(days) * 86_400)
        let targetDayEnd = targetDayStart.addingTimeInterval(86_400 - 1)
        return latestOnOrBefore(targetDayEnd)
    }
    
    // Classification helper localized to the VM so we can adjust copies consistently
    private func fgClassify(_ value: Int) -> String {
        switch value {
        case 0...24: return "extreme fear"
        case 25...44: return "fear"
        case 45...54: return "neutral"
        case 55...74: return "greed"
        default: return "extreme greed"
        }
    }

    // Historical data should be returned as-is without any adjustments
    // If values are equal, that's accurate historical data (not an error to fix)

    var yesterdayData: FearGreedData? {
        return dataDaysAgo(1)
    }

    var lastWeekData: FearGreedData? {
        return dataDaysAgo(7)
    }

    var lastMonthData: FearGreedData? {
        return dataDaysAgo(30)
    }
    
    // MARK: - AI Observation helpers
    enum Bias: String { case bearish, neutral, bullish }

    /// Lowercased classification key for color/bias mapping
    var currentClassificationKey: String? { data.first?.valueClassification.lowercased() }

    /// Day-over-day delta (current - yesterday)
    var delta1d: Int? {
        guard let now = currentValue, let y = Int(yesterdayData?.value ?? "") else { return nil }
        return now - y
    }

    /// Week-over-week delta (current - last week)
    var delta7d: Int? {
        guard let now = currentValue, let w = Int(lastWeekData?.value ?? "") else { return nil }
        return now - w
    }

    /// Month-over-month delta (current - last month)
    var delta30d: Int? {
        guard let now = currentValue, let m = Int(lastMonthData?.value ?? "") else { return nil }
        return now - m
    }

    /// A coarse bias combining classification and short-term momentum
    var bias: Bias {
        let base: Bias = {
            switch (currentClassificationKey ?? "") {
            case "extreme fear", "fear": return .bearish
            case "neutral":               return .neutral
            case "greed", "extreme greed": return .bullish
            default: return .neutral
            }
        }()
        // Nudge by momentum if both deltas agree
        if let d1 = delta1d, let d7 = delta7d {
            if d1 >= 5 && d7 >= 5 { return .bullish }
            if d1 <= -5 && d7 <= -5 { return .bearish }
        }
        return base
    }

    /// One-line AI observation tied to market sentiment and momentum.
    var aiObservationText: String {
        var base: String
        switch (currentClassificationKey ?? "") {
        case "extreme fear":
            base = "Extreme risk aversion is dominating, with defensive positioning still in control."
        case "fear":
            base = "Sentiment remains cautious, with selective accumulation favoring confirmation over urgency."
        case "neutral":
            base = "Sentiment is balanced, with directional conviction still limited."
        case "greed":
            base = "Optimism is elevated, and positioning is becoming more sensitive to overextension risk."
        case "extreme greed":
            base = "Conditions look euphoric; continuation can persist, but reversal risk is materially higher."
        default:
            base = "Sentiment update pending."
        }
        var notes: [String] = []
        if let d1 = delta1d {
            if d1 > 0 { notes.append("up \(d1) vs 1d") }
            else if d1 < 0 { notes.append("down \(abs(d1)) vs 1d") }
            else { notes.append("flat vs 1d") }
        }
        if let d7 = delta7d {
            if d7 > 0 { notes.append("up \(d7) vs 7d") }
            else if d7 < 0 { notes.append("down \(abs(d7)) vs 7d") }
            else { notes.append("flat vs 7d") }
        }
        let suffix = notes.isEmpty ? "" : " Trend: " + notes.joined(separator: "; ") + "."
        return (base + suffix).replacingOccurrences(of: "  ", with: " ")
    }
    
    /// Normalizes AI text from Firebase/direct model responses for user-facing display.
    private func sanitizeAIText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let redundantPrefixes = [
            "cryptosage ai summary:",
            "cryptosage ai analysis:",
            "cryptosage ai reads",
            "cryptosage ai indicates",
            "cryptosage ai detects",
            "cryptosage ai identifies",
            "cryptosage ai flags",
            "cryptosage ai:"
        ]
        let cleanedLower = cleaned.lowercased()
        if let prefix = redundantPrefixes.first(where: { cleanedLower.hasPrefix($0) }) {
            cleaned = cleaned.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix == "cryptosage ai reads" || prefix == "cryptosage ai indicates" || prefix == "cryptosage ai detects" || prefix == "cryptosage ai identifies" || prefix == "cryptosage ai flags" {
                cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
            }
        }
        
        if cleaned.hasPrefix("\""), cleaned.hasSuffix("\""), cleaned.count >= 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        
        cleaned = cleaned.replacingOccurrences(of: " . ", with: ". ")
        cleaned = cleaned.replacingOccurrences(of: " ,", with: ",")
        cleaned = cleaned.replacingOccurrences(of: " ;", with: ";")
        
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        
        if !cleaned.isEmpty, !cleaned.hasSuffix("."), !cleaned.hasSuffix("!"), !cleaned.hasSuffix("?") {
            cleaned += "."
        }
        
        return cleaned
    }
    
    /// Short AI observation for card display (1-2 lines max).
    /// Uses live AI summary if available, otherwise falls back to dynamic contextual strings.
    /// Source-aware and score-validated to avoid contradictory text.
    var aiObservationCompact: String {
        // Only use Firebase AI observations when on CryptoSage AI source
        if selectedSource == .derived {
            // Return short summary if available and consistent
            if let summary = liveAIObservationSummary, !summary.isEmpty,
               isObservationConsistentWithScore(summary) {
                return summary
            }
            
            // Fallback: Use first sentence of full observation if available and consistent
            if let liveObs = liveAIObservation, !liveObs.isEmpty,
               isObservationConsistentWithScore(liveObs) {
                let firstSentence = liveObs.components(separatedBy: ".").first ?? liveObs
                return firstSentence.trimmingCharacters(in: .whitespaces) + (firstSentence.hasSuffix(".") ? "" : ".")
            }
        }
        
        // Enhanced fallback with dynamic context from actual sentiment data
        let clsKey = (currentClassificationKey ?? "")
        let value = currentValue ?? 50
        let trendPhrase = buildCompactTrendPhrase()
        
        switch clsKey {
        case "extreme fear":
            return "Extreme Fear (\(value))\(trendPhrase). Position defensively until stability improves."
        case "fear":
            return "Fear (\(value))\(trendPhrase). Watch for confirmation before increasing risk."
        case "neutral":
            return "Neutral (\(value))\(trendPhrase). Momentum is mixed; wait for clearer direction."
        case "greed":
            return "Greed (\(value))\(trendPhrase). Manage exposure as extension risk rises."
        case "extreme greed":
            return "Extreme Greed (\(value))\(trendPhrase). Pullback risk is elevated."
        default:
            return "Sentiment updating…"
        }
    }
    
    /// Full AI observation for detail view (2-3 sentences).
    /// Returns the complete analysis text from Firebase or local generation.
    /// Source-aware: Firebase observation is only used for CryptoSage AI source.
    /// Score-validated: If cached text contradicts the current sentiment, falls back to dynamic text.
    var aiObservationFull: String {
        // Only use Firebase AI observation when on CryptoSage AI source
        // The observation was generated specifically for CryptoSage AI data
        guard selectedSource == .derived else {
            return aiObservationText
        }
        
        // Return full analysis if available and consistent with current score
        if let liveObs = liveAIObservation, !liveObs.isEmpty {
            // Validate: cached observation shouldn't contradict current sentiment
            if isObservationConsistentWithScore(liveObs) {
                return liveObs
            }
            // Observation is stale/contradictory — use dynamic fallback
        }
        
        // Fallback to detailed observation text based on actual current data
        return aiObservationText
    }
    
    /// Checks if the cached AI observation text is broadly consistent with the current score.
    /// Prevents showing "greed" analysis when the market is in Fear, etc.
    private func isObservationConsistentWithScore(_ text: String) -> Bool {
        guard let cls = currentClassificationKey else { return true }
        let lowerText = text.lowercased()
        
        switch cls {
        case "extreme fear", "fear":
            // Flag if text talks about greed, surge, rally, optimism
            let greedTerms = ["phase of greed", "greed driven", "extreme greed", "euphoria", "rally in altcoins", "investor confidence"]
            for term in greedTerms {
                if lowerText.contains(term) { return false }
            }
        case "greed", "extreme greed":
            // Flag if text talks about extreme fear, crash, capitulation
            let fearTerms = ["extreme fear", "capitulation", "crash", "panic selling", "market collapse"]
            for term in fearTerms {
                if lowerText.contains(term) { return false }
            }
        default:
            break
        }
        return true
    }
    
    /// Whether detailed AI data is available (score, confidence, key factors)
    var hasDetailedSentimentData: Bool {
        return firebaseSentimentScore != nil || 
               firebaseSentimentConfidence != nil || 
               (firebaseSentimentKeyFactors != nil && !(firebaseSentimentKeyFactors?.isEmpty ?? true))
    }
    
    /// Builds a compact trend phrase based on 1d and 7d deltas
    private func buildCompactTrendPhrase() -> String {
        var parts: [String] = []
        
        if let d1 = delta1d {
            if d1 > 0 {
                parts.append("up \(d1) today")
            } else if d1 < 0 {
                parts.append("down \(abs(d1)) today")
            }
        }
        
        if let d7 = delta7d {
            if d7 > 5 {
                parts.append("improving weekly")
            } else if d7 < -5 {
                parts.append("weakening weekly")
            }
        }
        
        if parts.isEmpty {
            return ""
        }
        return " (\(parts.joined(separator: ", ")))"
    }
    
    /// Fetches a live AI observation based on current market sentiment, news, and market data.
    /// Uses Firebase shared cache when available - all users get the same AI observation.
    /// Falls back to direct OpenAI call if Firebase unavailable.
    @MainActor
    func fetchAIObservation(forceRefresh: Bool = false) async {
        // Throttle: don't fetch if we recently fetched (unless forced)
        if !forceRefresh, let lastFetch = lastAIObservationFetch,
           Date().timeIntervalSince(lastFetch) < aiObservationThrottleInterval {
            return
        }
        
        // Don't fetch if already loading
        guard !isLoadingAIObservation else { return }
        
        isLoadingAIObservation = true
        defer { isLoadingAIObservation = false }
        
        // FIREBASE: Try shared cache first - all users get the same observation
        // This is the preferred path as it reduces API costs and ensures consistency
        if FirebaseService.shared.useFirebaseForAI {
            do {
                let response = try await FirebaseService.shared.getMarketSentiment()
                
                // Clean up the full analysis text
                let cleanAnalysis = sanitizeAIText(response.content)
                
                // Clean up the summary text (use displaySummary which has fallback logic)
                let cleanSummary = sanitizeAIText(response.displaySummary)
                
                // Update if valid
                if !cleanAnalysis.isEmpty && cleanAnalysis.count < 500 {
                    liveAIObservation = cleanAnalysis
                    liveAIObservationSummary = cleanSummary
                    lastAIObservationFetch = Date()
                    
                    // Store enhanced Firebase sentiment data (shared across all users)
                    firebaseSentimentScore = response.score
                    firebaseSentimentVerdict = response.verdict
                    firebaseSentimentConfidence = response.confidence
                    firebaseSentimentKeyFactors = response.keyFactors
                    
                    saveAIObservationToDisk()
                    
                    #if DEBUG
                    if let score = response.score {
                        print("[FearGreed] Firebase sentiment: score=\(score), verdict=\(response.verdict ?? "N/A"), confidence=\(response.confidence ?? 0)%")
                    }
                    print("[FearGreed] AI observation loaded from Firebase (cached: \(response.cached))")
                    print("[FearGreed] Summary: \(cleanSummary)")
                    #endif
                }
                return // Success - don't fall through to direct API
            } catch {
                #if DEBUG
                // LOG SPAM FIX: Only log Firebase errors once every 5 minutes
                if Self.shouldLogFirebaseError() {
                    print("[FearGreed] Firebase AI observation failed: \(error.localizedDescription), falling back to direct API")
                }
                #endif
                // Fall through to direct API call
            }
        }
        
        // FALLBACK: Direct OpenAI call (when Firebase unavailable)
        // Check if API key is available for direct calls
        guard APIConfig.hasValidOpenAIKey else {
            return // Silently use fallback strings
        }
        
        // Check daily limit for direct API calls
        guard canGenerateAIObservation else {
            #if DEBUG
            print("[FearGreed] AI observation daily limit reached (\(currentAIObservationLimit)/day)")
            #endif
            return
        }
        
        // Build rich context for AI
        let contextData = buildAIObservationContext()
        
        let systemPrompt = """
        You are a senior crypto market analyst providing real-time insight for the CryptoSage app. Your role is to analyze the current market data and explain what's happening and why.

        REQUIREMENTS:
        - Provide ONE insightful observation in 15-25 words
        - Focus on the "why" - explain what's driving current sentiment
        - Reference specific data points (news, price moves, market trends) when relevant
        - Be actionable but not financial advice
        - Sound professional but approachable
        - Don't just repeat the sentiment - add value with analysis
        
        GOOD EXAMPLES:
        - "BTC dominance rising as altcoins sell off - flight to quality typical in uncertain markets."
        - "ETF inflows driving optimism, but RSI suggests potential pullback ahead."
        - "Market breadth narrowing despite BTC gains - watch for rotation or correction."
        
        BAD EXAMPLES (don't do these):
        - "The market is neutral right now." (just repeats data)
        - "Consider buying the dip." (generic advice)
        - "Sentiment is at 50." (no insight)
        """
        
        let userMessage = """
        CURRENT MARKET DATA:
        \(contextData)
        
        Based on this data, what's the key insight traders should know right now?
        """
        
        do {
            let response = try await AIService.shared.sendMessage(
                userMessage,
                systemPrompt: systemPrompt,
                usePremiumModel: false,
                includeTools: false,
                isAutomatedFeature: false, // Use Firebase backend for all users
                maxTokens: 128 // Very brief observations (<200 chars)
            )
            
            // Clean up the response (remove quotes if present)
            let cleanResponse = sanitizeAIText(response)
            
            // Only update if we got a reasonable response
            if !cleanResponse.isEmpty && cleanResponse.count < 200 {
                liveAIObservation = cleanResponse
                lastAIObservationFetch = Date()
                saveAIObservationToDisk()
                recordAIObservationUsage() // Count against daily limit
            }
        } catch {
            // Silently fail - fallback strings will be used
            #if DEBUG
            // LOG SPAM FIX: Throttle to once every 5 minutes (shares throttle with Firebase errors)
            if Self.shouldLogFirebaseError() {
                print("AI Observation fetch failed: \(error.localizedDescription)")
            }
            #endif
        }
    }
    
    /// Fetches AI commentary explaining the current Fear & Greed value.
    /// Uses Firebase shared cache - all users seeing the same F&G value get the same commentary.
    @MainActor
    func fetchFearGreedCommentary() async {
        // Get current F&G value
        guard let value = currentValue else { return }
        
        // Don't refetch if we already have commentary for a similar value (within 5 points)
        if let lastValue = lastFearGreedCommentaryValue,
           abs(lastValue - value) <= 5,
           fearGreedCommentary != nil {
            return
        }
        
        // Don't fetch if already loading
        guard !isLoadingFearGreedCommentary else { return }
        
        isLoadingFearGreedCommentary = true
        defer { isLoadingFearGreedCommentary = false }
        
        // FIREBASE: Get shared commentary - all users with similar F&G value get the same commentary
        if FirebaseService.shared.useFirebaseForAI {
            do {
                let classification = (currentClassificationKey ?? "neutral").capitalized
                let response = try await FirebaseService.shared.getFearGreedCommentary(
                    value: value,
                    classification: classification
                )
                
                fearGreedCommentary = response.commentary
                lastFearGreedCommentaryValue = value
                saveFearGreedCommentaryToDisk()
                
                #if DEBUG
                print("[FearGreed] Commentary loaded from Firebase (cached: \(response.cached))")
                #endif
                return
            } catch {
                #if DEBUG
                // LOG SPAM FIX: Throttle Firebase errors
                if Self.shouldLogFirebaseError() {
                    print("[FearGreed] Firebase commentary failed: \(error.localizedDescription)")
                }
                #endif
            }
        }
        
        // Fallback: Use preset commentary based on classification
        let classification = currentClassificationKey ?? "neutral"
        switch classification.lowercased() {
        case "extreme fear":
            fearGreedCommentary = "Extreme fear reflects broad risk reduction. Historically, this can precede stabilization, but volatility usually remains elevated."
        case "fear":
            fearGreedCommentary = "Fear suggests cautious positioning and selective participation while markets search for support."
        case "neutral":
            fearGreedCommentary = "Neutral sentiment indicates balanced positioning, with direction likely to depend on the next macro or price catalyst."
        case "greed":
            fearGreedCommentary = "Greed signals rising optimism and stronger participation, while sensitivity to negative surprises increases."
        case "extreme greed":
            fearGreedCommentary = "Extreme greed reflects stretched risk appetite and often coincides with higher short-term correction probability."
        default:
            fearGreedCommentary = nil
        }
        lastFearGreedCommentaryValue = value
        saveFearGreedCommentaryToDisk()
    }
    
    /// Builds rich context data for AI observation including sentiment, market data, and news
    @MainActor
    private func buildAIObservationContext() -> String {
        var lines: [String] = []
        
        // Sentiment data
        let value = currentValue ?? 0
        let classification = (currentClassificationKey ?? "neutral").capitalized
        lines.append("Fear & Greed Index: \(value)/100 (\(classification))")
        
        // Sentiment trend
        if let d1 = delta1d {
            let sign = d1 >= 0 ? "+" : ""
            lines.append("24h sentiment change: \(sign)\(d1) points")
        }
        if let d7 = delta7d {
            let sign = d7 >= 0 ? "+" : ""
            lines.append("7d sentiment change: \(sign)\(d7) points")
        }
        
        // Market metrics (if available)
        if let breadth = marketBreadth {
            lines.append("Market breadth: \(String(format: "%.0f", breadth))% of coins positive")
        }
        if let btcChange = btc24hChange {
            lines.append("BTC 24h: \(String(format: "%+.1f", btcChange))%")
        }
        if let vol = marketVolatility {
            let volLevel = vol < 3 ? "Low" : (vol < 7 ? "Normal" : "High")
            lines.append("Market volatility: \(volLevel)")
        }
        
        // Global market data from MarketViewModel
        let marketVM = MarketViewModel.shared
        if let globalChange = marketVM.globalChange24hPercent {
            lines.append("Total market 24h: \(String(format: "%+.1f", globalChange))%")
        }
        if let btcDom = marketVM.btcDominance, btcDom > 0 {
            lines.append("BTC dominance: \(String(format: "%.1f", btcDom))%")
        }
        
        // Top gainers/losers for context
        let gainers = marketVM.topGainers.prefix(2)
        if !gainers.isEmpty {
            let gainerStr = gainers.map { "\($0.symbol.uppercased()) +\(String(format: "%.0f", $0.priceChangePercentage24hInCurrency ?? 0))%" }.joined(separator: ", ")
            lines.append("Top gainers: \(gainerStr)")
        }
        
        let losers = marketVM.topLosers.prefix(2)
        if !losers.isEmpty {
            let loserStr = losers.map { "\($0.symbol.uppercased()) \(String(format: "%.0f", $0.priceChangePercentage24hInCurrency ?? 0))%" }.joined(separator: ", ")
            lines.append("Top losers: \(loserStr)")
        }
        
        // Recent news headlines (top 3)
        let newsVM = CryptoNewsFeedViewModel.shared
        let recentNews = newsVM.articles.prefix(3)
        if !recentNews.isEmpty {
            lines.append("")
            lines.append("Recent headlines:")
            for article in recentNews {
                let title = article.title.count > 60 ? String(article.title.prefix(57)) + "..." : article.title
                lines.append("- \(title)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    // Expose provider timings for attribution/labels
    var lastUpdatedDateUTC: Date? {
        guard let tsStr = data.first?.timestamp, let ts = Double(tsStr) else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    var nextUpdateInterval: TimeInterval? {
        guard let s = data.first?.time_until_update, let secs = Double(s) else { return nil }
        return secs
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var refreshCancellable: AnyCancellable?
    private var nextFetchWorkItem: DispatchWorkItem?
    private var allowPeriodicRefresh = true
    
    init() {
        // PERFORMANCE FIX v9: Defer initial data loading to next run loop
        // This prevents multiple @Published updates from firing onChange handlers 
        // in views before they've set up their initial load guards
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let cached = self.loadCache(), !cached.isEmpty {
                self.data = cached
            }
            self.loadAIObservationUsageState()
            self.loadAICacheFromDisk()
        }
        
        if AppSettings.isSimulatorLimitedDataMode {
            // Limited simulator profile: one immediate fetch for parity, no periodic loop.
            allowPeriodicRefresh = false
            #if DEBUG
            print("🧪 [FearGreedVM] Simulator limited profile: single fetch, periodic refresh disabled")
            #endif
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000) // 250ms
                await self?.fetchData()
            }
        } else {
            // Schedule refresh on next run loop
            Task { @MainActor [weak self] in
                // Small delay to let views finish initializing
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                self?.scheduleNextRefresh()
            }
        }
        
        // PERFORMANCE FIX v20: Removed the 60s safety-net timer.
        // The adaptive scheduleNextRefresh() already handles periodic fetches using
        // the server's time_until_update hint (30s–1800s). The View-level 120s timer
        // in MarketSentimentView provides additional redundancy.
        // Having a separate 60s timer caused double-firing and redundant API calls.
        
        // Subscribe to fallback status notifications
        NotificationCenter.default.publisher(for: .sentimentFallbackStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                guard let userInfo = notification.userInfo,
                      let sourceStr = userInfo["source"] as? String else { return }
                
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // Only update if this notification is for our currently selected source
                    if sourceStr == "\(self.selectedSource)" {
                        self.isUsingFallback = (userInfo["usingFallback"] as? Bool) ?? false
                        self.fallbackSourceName = userInfo["fallbackSource"] as? String
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadCache() -> [FearGreedData]? {
        CacheManager.shared.load([FearGreedData].self, from: Self.cacheFile(for: selectedSource))
    }
    private func loadCache(for source: SentimentSource) -> [FearGreedData]? {
        CacheManager.shared.load([FearGreedData].self, from: Self.cacheFile(for: source))
    }
    private func saveCache(_ data: [FearGreedData]) {
        saveCache(data, for: selectedSource)
    }
    private func saveCache(_ data: [FearGreedData], for source: SentimentSource) {
        CacheManager.shared.save(data, to: Self.cacheFile(for: source))
    }
    
    private func scheduleNextRefresh() {
        guard allowPeriodicRefresh else { return }
        // Cancel any pending one-shot fetch
        nextFetchWorkItem?.cancel()
        nextFetchWorkItem = nil
        // PERFORMANCE FIX v21: Increased minimum from 30s to 120s, default from 60s to 180s.
        // Sentiment data changes slowly. The old 30-60s schedule was the #1 source of redundant
        // Firebase calls in the logs (getCryptoSageAISentiment called 10+ times per session).
        let base: TimeInterval = {
            if let s = data.first?.time_until_update, let secs = Double(s), secs.isFinite {
                return max(120, min(1800, secs))
            }
            return 180
        }()
        // Add small deterministic jitter to avoid sync storms across views
        let jitter = base * Double.random(in: 0.9...1.1)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task { await self.fetchData() }
        }
        nextFetchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + jitter, execute: work)
    }
    
    func isSourceAvailable(_ source: SentimentSource) -> Bool { source.isImplemented }
    
    private func provider(for source: SentimentSource) -> SentimentProvider {
        switch source {
        case .alternativeMe:   return AlternativeMeProvider()
        case .coinMarketCap:   return CoinMarketCapProvider()
        case .unusualWhales:   return UnusualWhalesProvider()
        case .coinglass:       return CoinglassProvider()
        case .derived:         return DerivedSentimentProvider()
        }
    }
    
    // PERFORMANCE FIX v21: ViewModel-level dedup increased from 15s to 60s.
    // Logs show getCryptoSageAISentiment being called every 15-30s from competing schedulers.
    // Sentiment data only changes every ~60s on the backend, so 60s minimum prevents waste.
    @MainActor private var isFetchingData = false
    @MainActor private var lastFetchDataAt: Date = .distantPast
    private let minFetchDataInterval: TimeInterval = 60 // Minimum 60s between fetches
    
    @MainActor func fetchData() async {
        // Dedup: skip if already fetching or too soon since last fetch
        guard !isFetchingData else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFetchDataAt) >= minFetchDataInterval else { return }
        isFetchingData = true
        defer {
            isFetchingData = false
            lastFetchDataAt = Date()
        }
        
        let timeout: TimeInterval = 8
        let src = selectedSource
        let prov = provider(for: src)
        // Defer state modifications to avoid "Modifying state during view update"
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isLoading = self.data.isEmpty
            self.errorMessage = nil
        }

        do {
            let list = try await prov.fetch(limit: 30, timeout: timeout)
            // Only apply to UI if the source hasn't changed during the await
            // Defer state modifications to avoid "Modifying state during view update"
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if src == self.selectedSource {
                    self.data = list
                    if let first = list.first, let intVal = Int(first.value) {
                        WidgetBridge.syncFearGreed(value: intVal, classification: first.value_classification)
                    }
                }
            }
            self.saveCache(list, for: src)

            // Validate historical data - detect when all values match (indicates data issue)
            let values = list.compactMap { Int($0.value) }
            let uniqueValues = Set(values)
            if values.count >= 3 && uniqueValues.count == 1 {
                // All values are the same - log a warning as this likely indicates a data issue
                let singleValue = uniqueValues.first ?? 0
                DebugLog.log("SentimentVM", "⚠️ WARNING: All \(values.count) sentiment values are identical (\(singleValue)) - historical data may not be available")
                #if DEBUG
                print("[SentimentVM] ⚠️ Historical data issue: all \(values.count) values = \(singleValue) for source=\(src)")
                #endif
            } else if values.count >= 2 {
                DebugLog.log("SentimentVM", "Historical data OK: \(uniqueValues.count) unique values across \(values.count) entries")
            }

#if DEBUG
            do {
                let ts = list.compactMap { Int($0.timestamp) }
                let minTs = ts.min() ?? 0
                let maxTs = ts.max() ?? 0
                DebugLog.log("SentimentVM", "fetched source=\(src) count=\(list.count) tsRange=\(minTs)...\(maxTs) uniqueValues=\(uniqueValues.count)")
            }
#endif

            // Update market metrics for CryptoSage AI — call DIRECTLY (already on @MainActor)
            // Do NOT wrap in Task{} — that defers execution and the 5s debounced view
            // observer may miss the change or reset its timer from subsequent state changes.
            if src == .derived {
                self.updateMarketMetrics()
            }

            // Defer state modifications to avoid "Modifying state during view update"
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isLoading = false
                self.errorMessage = nil
                
                // Fetch Fear & Greed AI commentary (shared via Firebase)
                // This runs automatically when sentiment data loads
                await self.fetchFearGreedCommentary()
                
                // Fetch AI observation if AI capability is available (Firebase or local API key)
                // This enables dynamic AI-generated observations instead of hardcoded fallbacks
                if APIConfig.hasAICapability {
                    await self.fetchAIObservation()
                }
            }
            
            // Re-schedule the next adaptive refresh based on the latest hint
            self.scheduleNextRefresh()
            return
        } catch {
            // Attempt cache fallback
            let errorDesc = (error as? LocalizedError)?.errorDescription
            if let cached = loadCache(for: src), !cached.isEmpty {
                // Defer state modifications to avoid "Modifying state during view update"
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.data = cached
                    self.isLoading = false
                    self.errorMessage = errorDesc
                }
                self.scheduleNextRefresh()
            } else {
                // Defer state modifications to avoid "Modifying state during view update"
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.data = Self.sample
                    self.isLoading = false
                    self.errorMessage = errorDesc
                }
                self.scheduleNextRefresh()
            }
        }
    }
}

import SwiftUI

struct SentimentShimmer: View {
    @State private var animate = false
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.06))
            .overlay(
                LinearGradient(colors: [Color.clear, Color.white.opacity(0.25), Color.clear], startPoint: .leading, endPoint: .trailing)
                    .offset(x: animate ? 240 : -240)
            )
            .frame(height: 120)
            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: animate)
            .onAppear { DispatchQueue.main.async { animate = true } }
    }
}

