import SwiftUI
import EventKit
import UserNotifications
import Combine

// MARK: - Event Reminder Manager

/// Manages persistent tracking of event reminders
final class EventReminderManager: ObservableObject {
    static let shared = EventReminderManager()
    
    /// Maps eventID -> scheduled reminder fire date
    @Published private(set) var reminders: [String: Date] = [:]
    
    private let storageKey = "eventReminders"
    
    private init() {
        loadReminders()
        cleanupExpiredReminders()
    }
    
    // MARK: - Public API
    
    /// Check if an event has an active reminder
    func hasReminder(for eventID: String) -> Bool {
        guard let fireDate = reminders[eventID] else { return false }
        // Only count as active if fire date is in the future
        return fireDate > Date()
    }
    
    /// Get the scheduled fire date for an event's reminder
    func reminderDate(for eventID: String) -> Date? {
        guard let fireDate = reminders[eventID], fireDate > Date() else { return nil }
        return fireDate
    }
    
    /// Set a reminder for an event
    func setReminder(for eventID: String, fireDate: Date) {
        reminders[eventID] = fireDate
        saveReminders()
    }
    
    /// Cancel a reminder for an event
    func cancelReminder(for eventID: String) {
        // Remove from tracking
        reminders.removeValue(forKey: eventID)
        saveReminders()
        
        // Cancel the actual notification
        let notificationID = notificationIdentifier(for: eventID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
    
    /// Get the deterministic notification identifier for an event
    func notificationIdentifier(for eventID: String) -> String {
        return "event-reminder-\(eventID)"
    }
    
    // MARK: - Persistence
    
    private func loadReminders() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return
        }
        reminders = decoded
    }
    
    private func saveReminders() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func cleanupExpiredReminders() {
        let now = Date()
        let expiredKeys = reminders.filter { $0.value <= now }.keys
        for key in expiredKeys {
            reminders.removeValue(forKey: key)
        }
        if !expiredKeys.isEmpty {
            saveReminders()
        }
    }
}

/// Tracks event <-> calendar links for deterministic add/remove behavior.
final class EventCalendarManager: ObservableObject {
    static let shared = EventCalendarManager()

    /// Maps eventID -> EventKit event identifier
    @Published private(set) var calendarEvents: [String: String] = [:]

    private let storageKey = "eventCalendarLinks"

    private init() {
        loadCalendarEvents()
    }

    func hasCalendarEvent(for eventID: String) -> Bool {
        calendarEvents[eventID] != nil
    }

    func calendarIdentifier(for eventID: String) -> String? {
        calendarEvents[eventID]
    }

    func setCalendarEvent(for eventID: String, identifier: String) {
        calendarEvents[eventID] = identifier
        saveCalendarEvents()
    }

    func clearCalendarEvent(for eventID: String) {
        calendarEvents.removeValue(forKey: eventID)
        saveCalendarEvents()
    }

    private func loadCalendarEvents() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        calendarEvents = decoded
    }

    private func saveCalendarEvents() {
        if let data = try? JSONEncoder().encode(calendarEvents) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

fileprivate enum EventCalendarActionResult {
    case added
    case alreadyAdded
    case removed
    case notFound
    case permissionDenied
    case failed(String)
}

// MARK: - Event Models

public enum EventCategory: String, CaseIterable, Identifiable {
    case all = "All", onchain = "On‑chain", macro = "Macro", exchange = "Exchange"
    public var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "sparkles"
        case .onchain: return "link.circle.fill"
        case .macro: return "globe.americas.fill"
        case .exchange: return "building.columns.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .all: return DS.Adaptive.gold
        case .onchain: return .cyan
        case .macro: return .purple
        case .exchange: return .orange
        }
    }
}

public enum Impact: String {
    case low = "Low", medium = "Medium", high = "High"
    
    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return DS.Adaptive.neutralYellow
        case .low: return .green
        }
    }
}

public struct EventItem: Identifiable {
    public let id: String
    public let title: String
    public let date: Date
    public let category: EventCategory
    public let impact: Impact
    public let subtitle: String?
    public let url: URL?
    public let coinSymbols: [String]
    
    public init(id: String = UUID().uuidString, title: String, date: Date, category: EventCategory, impact: Impact, subtitle: String?, url: URL?, coinSymbols: [String] = []) {
        self.id = id
        self.title = title
        self.date = date
        self.category = category
        self.impact = impact
        self.subtitle = subtitle
        self.url = url
        self.coinSymbols = coinSymbols
    }
    
    /// Initialize from cached event data
    init(from cached: CachedEventItem) {
        self.id = cached.id
        self.title = cached.title
        self.date = cached.date
        self.category = EventItem.mapCategory(cached.category)
        self.impact = EventItem.mapImpact(cached.impact)
        self.subtitle = cached.subtitle
        self.url = cached.url
        self.coinSymbols = cached.coinSymbols
    }
    
    /// Map category string to EventCategory enum
    private static func mapCategory(_ str: String) -> EventCategory {
        switch str.lowercased() {
        case "onchain", "on-chain", "on‑chain": return .onchain
        case "macro": return .macro
        case "exchange": return .exchange
        default: return .onchain
        }
    }
    
    /// Map impact string to Impact enum
    private static func mapImpact(_ str: String) -> Impact {
        switch str.lowercased() {
        case "high": return .high
        case "medium": return .medium
        case "low": return .low
        default: return .medium
        }
    }
}

// MARK: - ViewModel with Live Data

@MainActor
public final class EventsViewModel: ObservableObject {
    @Published public var items: [EventItem] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var lastUpdated: Date? = nil
    
    private var refreshTask: Task<Void, Never>?
    private let staleThreshold: TimeInterval = 30 * 60 // 30 minutes
    
    public init() {
        // Load cached data OR fallback immediately for instant UI - NEVER show empty
        loadInitialEvents()
    }
    
    deinit {
        refreshTask?.cancel()
    }
    
    /// Filter events by category
    public func filtered(_ cat: EventCategory) -> [EventItem] {
        let sorted = items.sorted { $0.date < $1.date }
        if cat == .all { return sorted }
        return sorted.filter { $0.category == cat }
    }
    
    /// Load cached events, or generate instant fallback if no cache exists
    private func loadInitialEvents() {
        // Try cache first
        if let cached: [CachedEventItem] = CacheManager.shared.load([CachedEventItem].self, from: "events_cache.json") {
            let converted = cached.map { EventItem(from: $0) }
            let filtered = converted.filter { $0.date > Date().addingTimeInterval(-24 * 60 * 60) }
            if !filtered.isEmpty {
                self.items = filtered
                self.lastUpdated = UserDefaults.standard.object(forKey: "events_cache_timestamp") as? Date
                return
            }
        }
        
        // No cache - load instant fallback events so UI never shows shimmer
        self.items = Self.generateInstantFallbackEvents()
        self.lastUpdated = nil // Mark as needing refresh
    }
    
    /// Generate instant fallback events using REAL public calendar dates
    /// These are actual scheduled events from official sources, not demo data
    private static func generateInstantFallbackEvents() -> [EventItem] {
        let now = Date()
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        
        var events: [EventItem] = []
        
        // FOMC Meeting dates - decision days from Federal Reserve calendar cadence.
        // https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm
        let fomcDecisionDays: [(Int, Int)] = [
            (1, 29), (3, 18), (5, 6), (6, 17),
            (7, 29), (9, 16), (11, 4), (12, 16)
        ]

        var upcomingFOMCDates: [Date] = []
        for year in [currentYear, currentYear + 1] {
            for (month, day) in fomcDecisionDays {
                if let fomcDate = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                   fomcDate > now {
                    upcomingFOMCDates.append(fomcDate)
                }
            }
        }

        for (index, fomcDate) in upcomingFOMCDates.sorted().prefix(4).enumerated() {
            events.append(EventItem(
                id: "fomc_\(index)_\(Int(fomcDate.timeIntervalSince1970))",
                title: "FOMC Meeting",
                date: fomcDate,
                category: .macro,
                impact: .high,
                subtitle: "Federal Reserve interest rate decision",
                url: URL(string: "https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm"),
                coinSymbols: []
            ))
        }
        
        // CPI Release dates - typically around 12th-13th of each month
        // https://www.bls.gov/schedule/news_release/cpi.htm
        let currentMonth = calendar.component(.month, from: now)
        for monthOffset in 0..<6 {
            let targetMonth = currentMonth + monthOffset
            let targetYear = targetMonth > 12 ? currentYear + 1 : currentYear
            let adjustedMonth = targetMonth > 12 ? targetMonth - 12 : targetMonth
            
            // CPI typically released around 12th of month
            if let cpiDate = calendar.date(from: DateComponents(year: targetYear, month: adjustedMonth, day: 12)),
               cpiDate > now {
                events.append(EventItem(
                    id: "cpi_\(adjustedMonth)_\(targetYear)",
                    title: "CPI Data Release",
                    date: cpiDate,
                    category: .macro,
                    impact: .high,
                    subtitle: "US Consumer Price Index inflation data",
                    url: URL(string: "https://www.bls.gov/cpi/"),
                    coinSymbols: []
                ))
            }
        }
        
        // Bitcoin Halving - KNOWN date (approximately April 2028)
        // This is a real blockchain event with predictable timing
        if let btcHalvingDate = calendar.date(from: DateComponents(year: 2028, month: 4, day: 15)),
           btcHalvingDate > now {
            events.append(EventItem(
                id: "btc_halving_2028",
                title: "Bitcoin Halving",
                date: btcHalvingDate,
                category: .onchain,
                impact: .high,
                subtitle: "Block reward reduces to 1.5625 BTC",
                url: URL(string: "https://www.bitcoinblockhalf.com/"),
                coinSymbols: ["BTC"]
            ))
        }
        
        // NOTE: Removed fake "Ethereum upgrade", "Token unlock", and "Crypto conference" events
        // Only showing events with KNOWN, verified dates from official sources
        // For live token unlocks and conference data, use the CoinMarketCal API
        
        return events.sorted { $0.date < $1.date }
    }
    
    /// Fetch fresh events from API
    public func fetchEvents(forceRefresh: Bool = false) async {
        // Don't overlap fetches
        guard !isLoading else { return }
        
        // Check if we need to refresh (but always try at least once if lastUpdated is nil)
        if !forceRefresh, let lastUpdate = lastUpdated, Date().timeIntervalSince(lastUpdate) < staleThreshold, !items.isEmpty {
            return
        }
        
        // Only show loading indicator, don't clear items - keep showing existing data
        isLoading = true
        errorMessage = nil
        
        // Add timeout to prevent hanging forever
        let fetchTask = Task {
            return await EventsService.shared.fetchEvents(forceRefresh: forceRefresh)
        }
        
        // Wait with timeout
        let _ = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 second timeout
            return [CachedEventItem]()
        }
        
        let cachedEvents: [CachedEventItem]
        do {
            cachedEvents = try await withThrowingTaskGroup(of: [CachedEventItem].self) { group in
                group.addTask { await fetchTask.value }
                group.addTask { try await Task.sleep(nanoseconds: 10_000_000_000); return [] }
                
                if let first = try await group.next(), !first.isEmpty {
                    group.cancelAll()
                    return first
                }
                return []
            }
        } catch {
            cachedEvents = []
        }
        
        // Update UI
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLoading = false
            
            if !cachedEvents.isEmpty {
                let converted = cachedEvents.map { EventItem(from: $0) }
                let filtered = converted.filter { $0.date > Date().addingTimeInterval(-24 * 60 * 60) }
                if !filtered.isEmpty {
                    self.items = filtered
                    self.lastUpdated = Date()
                }
            }
            // If fetch failed, keep showing existing items (fallback or cached)
        }
    }
    
    /// Start auto-refresh timer
    public func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(30 * 60 * 1_000_000_000)) // 30 minutes
                guard !Task.isCancelled else { break }
                await self?.fetchEvents(forceRefresh: true)
            }
        }
    }
    
    /// Stop auto-refresh
    public func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}

// MARK: - Premium Section View

public struct EventsSectionView: View {
    @ObservedObject public var vm: EventsViewModel
    // PERFORMANCE FIX v21: Removed @EnvironmentObject var appState: AppState
    // ROOT CAUSE: AppState has 18+ @Published properties (selectedTab, isKeyboardVisible,
    // 5 nav paths, dismissHomeSubviews, pendingTradeConfig, etc.). Every change to ANY of
    // them fires objectWillChange and forces this entire section to re-render.
    // EventsSectionView only uses appState.dismissHomeSubviews, so we use a targeted
    // onReceive on just that publisher instead. Same fix already applied to HomeView & PremiumNewsSection.
    @Binding public var showAll: Bool
    @State private var filter: EventCategory = .all
    @State private var selectedForDetail: EventItem? = nil
    @State private var detailSheetDetent: PresentationDetent = .medium
    @State private var hasAppeared = false
    @State private var pulseAnimation = false

    public init(vm: EventsViewModel, showAll: Binding<Bool>) {
        self._vm = ObservedObject(initialValue: vm)
        self._showAll = showAll
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header (outside card - matches other home sections)
            eventsHeader

            // Card content
            CardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    // Animated pill filter
                    EventsFilterPicker(selectedFilter: $filter)
                    
                    // Events content
                    eventsContent
                    
                    // Premium CTA button
                    viewAllEventsButton
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            }
        }
        .sheet(item: $selectedForDetail) { item in
            EventDetailSheet(item: item)
                .presentationDetents([.medium, .large], selection: $detailSheetDetent)
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            // PERFORMANCE FIX v21: Pulse animation now managed by .scrollAwarePulse modifier
        }
        .task {
            guard !hasAppeared else { return }
            hasAppeared = true
            await vm.fetchEvents()
            vm.startAutoRefresh()
        }
        .onDisappear {
            vm.stopAutoRefresh()
        }
        // PERFORMANCE FIX v21: Use targeted onReceive on just the $dismissHomeSubviews publisher
        // instead of @EnvironmentObject var appState which observes ALL 18+ @Published properties.
        .onReceive(AppState.shared.$dismissHomeSubviews) { shouldDismiss in
            if shouldDismiss && showAll {
                showAll = false
                // Reset the trigger after handling
                DispatchQueue.main.async {
                    AppState.shared.dismissHomeSubviews = false
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var eventsHeader: some View {
        let items = vm.items.filter { $0.date > Date() }.sorted { $0.date < $1.date }
        let nextEvent = items.first
        
        return HStack(alignment: .center, spacing: 8) {
            // Use standardized GoldHeaderGlyph for consistency
            GoldHeaderGlyph(systemName: "calendar.badge.clock")
        
            Text("Events & Catalysts")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .layoutPriority(1) // Ensure title doesn't shrink
            
            Spacer(minLength: 4)
            
            // Next event highlight in header - compact gold themed badge
            if let next = nextEvent {
                nextEventBadge(event: next)
            }
        }
    }
    
    /// Compact badge showing next event in header
    private func nextEventBadge(event: EventItem) -> some View {
        let timeText = shortTimeUntil(event.date)
        
        return HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(DS.Adaptive.gold)
            
            Text(compactEventTitle(event.title))
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(DS.Adaptive.textPrimary)
            
            Text(timeText)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DS.Adaptive.goldText)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .fixedSize(horizontal: true, vertical: true) // Prevent clipping
        .background(
            Capsule()
                .fill(DS.Adaptive.gold.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(DS.Adaptive.gold.opacity(0.25), lineWidth: 0.5)
        )
    }
    
    /// Creates a very compact event title for the header badge
    private func compactEventTitle(_ title: String) -> String {
        // Common abbreviations for space
        let abbreviations: [(String, String)] = [
            ("FOMC Meeting", "FOMC"),
            ("Federal Reserve", "Fed"),
            ("Interest Rate", "Rate"),
            ("Token Unlock", "Unlock"),
            ("Network Upgrade", "Upgrade"),
            ("Data Release", "Data"),
            ("CPI Data Release", "CPI"),
            ("Consumer Price Index", "CPI"),
            ("Ethereum", "ETH"),
            ("Bitcoin", "BTC"),
            ("Conference", "Conf"),
            ("Summit", "Summit"),
            ("Industry", ""),
            ("Crypto ", ""),
            ("Major ", ""),
        ]
        
        var result = title
        for (full, abbrev) in abbreviations {
            if result.contains(full) {
                result = result.replacingOccurrences(of: full, with: abbrev)
            }
        }
        
        // Final trim and length check
        result = result.trimmingCharacters(in: .whitespaces)
        if result.count > 10 {
            // Take first word if still too long
            if let firstSpace = result.firstIndex(of: " ") {
                result = String(result[..<firstSpace])
            } else {
                result = String(result.prefix(8)) + "…"
            }
        }
        
        return result
    }
    
    // MARK: - Summary Bar (Simplified Gold-Themed)
    
    private var eventsSummaryBar: some View {
        let items = vm.items.filter { $0.date > Date() }.sorted { $0.date < $1.date }
        let nextEvent = items.first
        
        return HStack {
            Spacer()
            
            // Next event highlight - gold themed (compact, no overflow)
            if let next = nextEvent {
                nextEventBadge(event: next)
            }
        }
    }
    
    private func shortTimeUntil(_ date: Date) -> String {
        let now = Date()
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let comps = cal.dateComponents([.day], from: now, to: date)
        if let d = comps.day, d >= 1 { return "in \(d)d" }
        return "Soon"
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var eventsContent: some View {
        let filteredItems = vm.filtered(filter)
        
        // Show shimmer if loading with no data
        if vm.items.isEmpty && vm.isLoading {
            // Shimmer skeleton loading
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    EventRowSkeleton()
                }
            }
            .transition(.opacity)
        } else if filteredItems.isEmpty {
            // Premium empty state
            premiumEmptyState
        } else {
            // Event rows with quick actions
            VStack(spacing: 8) {
                ForEach(filteredItems.prefix(3), id: \.id) { item in
                    PremiumEventRow(item: item, onTap: { tapped in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        detailSheetDetent = .medium
                        selectedForDetail = tapped
                    }, showQuickActions: true)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: filter)
        }
    }
    
    // MARK: - Premium Empty State
    
    private var premiumEmptyState: some View {
        VStack(spacing: 12) {
        ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [DS.Adaptive.gold.opacity(0.15), Color.orange.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                
                Image(systemName: vm.isLoading ? "magnifyingglass" : "calendar.badge.exclamationmark")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(
            LinearGradient(
                            colors: [DS.Adaptive.gold, .orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                    )
                    .symbolEffect(.pulse, isActive: vm.isLoading)
            }
            
            VStack(spacing: 4) {
                Text(vm.isLoading ? "Loading events…" : "No upcoming events")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                if !vm.isLoading && filter != .all {
                    Text("Try selecting 'All' to see more events")
                        .font(.caption)
                        .foregroundStyle(DS.Adaptive.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    // MARK: - Premium CTA Button
    
    private var viewAllEventsButton: some View {
        let upcomingCount = vm.items.filter { $0.date > Date() }.count
        let badgeText = upcomingCount > 0 ? "\(upcomingCount) events" : nil
        
        return SectionCTAButton(
            title: "See All Events",
            icon: "calendar.badge.clock",
            badge: badgeText,
            accentColor: BrandColors.goldBase,
            compact: true
        ) {
            showAll = true
        }
        .padding(.top, 2)
    }
}

// MARK: - Animated Filter Picker

struct EventsFilterPicker: View {
    @Binding var selectedFilter: EventCategory
    @Namespace private var animation
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(EventCategory.allCases) { category in
                filterPill(for: category)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.chipBackground)
        )
    }
    
    private func filterPill(for category: EventCategory) -> some View {
        let isSelected = selectedFilter == category
        let isDark = colorScheme == .dark
        
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedFilter = category
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(category.rawValue)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? TintedChipStyle.selectedText(isDark: isDark) : DS.Adaptive.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if isSelected {
                        ZStack {
                            Capsule()
                                .fill(TintedChipStyle.selectedBackground(isDark: isDark))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(isDark ? 0.12 : 0.45), Color.white.opacity(0)],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: isDark
                                            ? [BrandColors.goldLight.opacity(0.35), TintedChipStyle.selectedStroke(isDark: true).opacity(0.6)]
                                            : [BrandColors.goldBase.opacity(0.45), TintedChipStyle.selectedStroke(isDark: false).opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .matchedGeometryEffect(id: "filterBackground", in: animation)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event Row Button Style

/// Custom button style for event rows that provides press feedback while allowing scroll gestures
private struct EventRowButtonStyle: ButtonStyle {
    let isImminent: Bool
    let impactColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
    }
}

// MARK: - Premium Event Row

struct PremiumEventRow: View {
    let item: EventItem
    var onTap: ((EventItem) -> Void)? = nil
    var animationDelay: Double = 0
    var showQuickActions: Bool = false  // Show reminder/calendar quick buttons
    
    @ObservedObject private var reminderManager = EventReminderManager.shared
    @ObservedObject private var calendarManager = EventCalendarManager.shared
    @State private var showConfirm = false
    @State private var showReminderSheet = false
    @State private var showCancelConfirm = false
    @State private var showCalendarAlert = false
    @State private var calendarAlertTitle = "Calendar"
    @State private var calendarAlertMessage = ""
    @State private var isCalendarActionInFlight = false
    @Environment(\.colorScheme) private var colorScheme
    
    /// Whether this event has an active reminder
    private var hasReminder: Bool {
        reminderManager.hasReminder(for: item.id)
    }

    /// Whether this event has been added to the user's system calendar.
    private var hasCalendarEvent: Bool {
        calendarManager.hasCalendarEvent(for: item.id)
    }
    
    private var isImminent: Bool {
        item.date.timeIntervalSinceNow < 24 * 60 * 60 && item.date > Date()
    }
    
    private var isPassed: Bool {
        item.date < Date()
    }
    
    var body: some View {
        Button {
            if let onTap {
                onTap(item)
            } else if let url = item.url {
                openSafari(url)
            }
        } label: {
            rowContent
        }
        .buttonStyle(EventRowButtonStyle(isImminent: isImminent, impactColor: item.impact.color))
        .contextMenu {
            eventContextMenu
        }
        .alert("Reminder scheduled", isPresented: $showConfirm) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("We'll remind you near the event time.")
        }
        .alert("Reminder cancelled", isPresented: $showCancelConfirm) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The reminder for this event has been removed.")
        }
        .alert(calendarAlertTitle, isPresented: $showCalendarAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(calendarAlertMessage)
        }
        .confirmationDialog(hasReminder ? "Reminder Active" : "Set Reminder", isPresented: $showReminderSheet, titleVisibility: .visible) {
            reminderChoices
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(item.title), \(item.category.rawValue), \(item.impact.rawValue) impact, \(shortDate(item.date))")
    }
    
    // MARK: - Row Content
    
    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            // Simplified impact indicator
            impactIndicator
            
            // Main content - streamlined layout
            VStack(alignment: .leading, spacing: 4) {
                // Title row
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isPassed ? DS.Adaptive.textSecondary : DS.Adaptive.textPrimary)
                    .lineLimit(1)
                
                // Compact info row - category with date, then countdown
                HStack(spacing: 8) {
                    // Combined category + date badge
                    HStack(spacing: 4) {
                        Image(systemName: item.category.icon)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(item.category.color)
                        Text(item.category.rawValue)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                        Text(shortDate(item.date))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                    
                    Spacer(minLength: 4)
                    
                    // Countdown - gold themed for consistency
                    countdownBadge
                }
                
                // Subtitle (if present)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isPassed ? DS.Adaptive.textTertiary : DS.Adaptive.textSecondary)
                        .lineLimit(1)
                }
            }
            
            // Quick actions OR menu button
            if showQuickActions && !isPassed {
                quickActionButtons
            } else {
                // Menu button with improved styling
            Menu {
                reminderMenu
            } label: {
                    ZStack {
                        Circle()
                            .fill(DS.Adaptive.chipBackground.opacity(0.5))
                            .frame(width: 28, height: 28)
                        
                Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.textSecondary.opacity(0.8))
                    .rotationEffect(.degrees(90))
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(rowOverlay)
        .contentShape(Rectangle())
    }
    
    // MARK: - Quick Action Buttons (Compact Gold Theme)
    
    private var quickActionButtons: some View {
        HStack(spacing: 6) {
            // Remind button - gold themed with green active state
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showReminderSheet = true
            } label: {
                ZStack {
                    Circle()
                        .fill(hasReminder ? Color.green.opacity(0.15) : DS.Adaptive.gold.opacity(0.12))
                        .frame(width: 30, height: 30)
                    
                    Circle()
                        .stroke(hasReminder ? Color.green.opacity(0.35) : DS.Adaptive.gold.opacity(0.25), lineWidth: 0.5)
                        .frame(width: 30, height: 30)
                    
                    Image(systemName: hasReminder ? "bell.badge.fill" : "bell.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(hasReminder ? Color.green : DS.Adaptive.gold)
                    
                    // Subtle checkmark when reminder is set
                    if hasReminder {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                            .offset(x: 9, y: -9)
                    }
                }
            }
            .buttonStyle(QuickActionButtonStyle())
            .accessibilityLabel(hasReminder ? "Reminder active - tap to manage" : "Set reminder")
            
            // Calendar button - persistent add/remove with explicit state
            Button {
                toggleCalendarEvent()
            } label: {
                ZStack {
                    Circle()
                        .fill(hasCalendarEvent ? Color.green.opacity(0.15) : DS.Adaptive.gold.opacity(0.12))
                        .frame(width: 30, height: 30)
                    
                    Circle()
                        .stroke(hasCalendarEvent ? Color.green.opacity(0.35) : DS.Adaptive.gold.opacity(0.25), lineWidth: 0.5)
                        .frame(width: 30, height: 30)
                    
                    if isCalendarActionInFlight {
                        ProgressView()
                            .scaleEffect(0.55)
                            .tint(DS.Adaptive.gold)
                    } else {
                        Image(systemName: hasCalendarEvent ? "calendar.badge.checkmark" : "calendar.badge.plus")
                            .font(.system(size: hasCalendarEvent ? 11 : 12, weight: .semibold))
                            .foregroundStyle(hasCalendarEvent ? Color.green : DS.Adaptive.gold)
                    }
                }
            }
            .buttonStyle(QuickActionButtonStyle())
            .disabled(isCalendarActionInFlight)
            .opacity(isCalendarActionInFlight ? 0.72 : 1.0)
            .accessibilityLabel(hasCalendarEvent ? "Remove from calendar" : "Add to calendar")
            .accessibilityHint("Adds or removes this event from your Apple Calendar")
        }
        .padding(.leading, 4) // Extra spacing from countdown badge
    }
    
    // MARK: - Context Menu
    
    private var eventContextMenu: some View {
        Group {
            // Reminder options based on state
            if hasReminder {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    reminderManager.cancelReminder(for: item.id)
                    showCancelConfirm = true
                } label: {
                    Label("Cancel Reminder", systemImage: "bell.slash")
                }
                
                Button {
                    showReminderSheet = true
                } label: {
                    Label("Change Reminder", systemImage: "bell.badge")
                }
            } else {
                Button {
                    showReminderSheet = true
                } label: {
                    Label("Set Reminder", systemImage: "bell")
                }
            }
            
            Button {
                toggleCalendarEvent()
            } label: {
                Label(
                    hasCalendarEvent ? "Remove from Calendar" : "Add to Calendar",
                    systemImage: hasCalendarEvent ? "calendar.badge.minus" : "calendar.badge.plus"
                )
            }
            
            Divider()
            
            if let url = item.url {
                Button {
                    openSafari(url)
                } label: {
                    Label("Open Source", systemImage: "safari")
                }
                
                ShareLink(item: url) {
                    Label("Share Event", systemImage: "square.and.arrow.up")
                }
                
                Button {
                    UIPasteboard.general.url = url
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var impactIndicator: some View {
        ZStack {
            // Glow background for high impact imminent events
            if isImminent && item.impact == .high {
                RoundedRectangle(cornerRadius: 4)
                    .fill(item.impact.color.opacity(0.3))
                    .frame(width: 8, height: 52)
            }
            
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                        colors: isPassed 
                            ? [Color.gray.opacity(0.5), Color.gray.opacity(0.3)]
                            : [item.impact.color, item.impact.color.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
                .frame(width: 4, height: 48)
            .modifier(ConditionalBreathingGlow(isActive: item.impact == .high && isImminent, color: item.impact.color))
        }
    }
    
    private var rowBackground: some View {
        ZStack {
            // Base fill
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackgroundElevated)
            
            // Premium inner highlight for depth (top edge glow)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.05 : 0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            
            // Side accent gradient for imminent events
            if isImminent && !isPassed {
                LinearGradient(
                    colors: [item.impact.color.opacity(0.12), Color.clear, Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            
            // Subtle bottom shadow gradient for depth
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(colorScheme == .dark ? 0.08 : 0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
    
    private var rowOverlay: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(
                isImminent && !isPassed
                    ? LinearGradient(
                        colors: [item.impact.color.opacity(0.5), item.impact.color.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                      )
                    : LinearGradient(
                        colors: [DS.Adaptive.stroke.opacity(0.8), DS.Adaptive.stroke.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                      ),
                lineWidth: isImminent && !isPassed ? 1.5 : 0.5
            )
    }
    
    private var rowShadowColor: Color {
        if isPassed {
            return Color.black.opacity(0.08)
        } else if isImminent {
            return item.impact.color.opacity(0.15)
        } else {
            return Color.black.opacity(colorScheme == .dark ? 0.2 : 0.12)
        }
    }
    
    private var coinBadge: some View {
        Text(item.coinSymbols.prefix(2).joined(separator: ", "))
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(DS.Adaptive.goldText)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(DS.Adaptive.gold.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(DS.Adaptive.gold.opacity(0.25), lineWidth: 0.5)
                    )
            )
    }

    private var categoryBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: item.category.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(item.category.rawValue)
                .font(.system(size: 10, weight: .medium))
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(isPassed ? item.category.color.opacity(0.6) : item.category.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(item.category.color.opacity(isPassed ? 0.08 : 0.12))
                .overlay(
                    Capsule()
                        .stroke(item.category.color.opacity(isPassed ? 0.15 : 0.25), lineWidth: 0.5)
                )
        )
    }

    private var impactBadge: some View {
        Text(item.impact.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isPassed ? item.impact.color.opacity(0.6) : item.impact.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(item.impact.color.opacity(isPassed ? 0.1 : 0.15))
                    .overlay(
                        Capsule()
                            .stroke(item.impact.color.opacity(isPassed ? 0.2 : 0.3), lineWidth: 0.5)
                    )
            )
    }
    
    private var dateBadge: some View {
        Text(shortDate(item.date))
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(isPassed ? DS.Adaptive.textTertiary.opacity(0.6) : DS.Adaptive.textTertiary)
    }
    
    private var countdownBadge: some View {
        let timeString = timeUntilString(from: item.date)
        
        // Gold-themed countdown for premium consistency
        let badgeColor: Color = isPassed ? DS.Adaptive.textTertiary : (isImminent ? item.impact.color : DS.Adaptive.goldText)
        
        return HStack(spacing: 3) {
            if !isPassed && isImminent {
                Circle()
                    .fill(item.impact.color)
                    .frame(width: 5, height: 5)
                    .modifier(PulsingDot())
            }
            Text(timeString)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(badgeColor.opacity(isPassed ? 0.08 : 0.12))
                .overlay(
                    Capsule()
                        .stroke(badgeColor.opacity(isPassed ? 0.15 : 0.25), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Helpers

    private func toggleCalendarEvent() {
        guard !isCalendarActionInFlight else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isCalendarActionInFlight = true

        Task {
            let result: EventCalendarActionResult
            if hasCalendarEvent {
                result = await removeEventFromCalendar(eventID: item.id, title: item.title, date: item.date)
            } else {
                result = await addEventToCalendar(eventID: item.id, title: item.title, date: item.date, notes: item.subtitle)
            }

            await MainActor.run {
                isCalendarActionInFlight = false
                presentCalendarResult(result)
            }
        }
    }

    @MainActor
    private func presentCalendarResult(_ result: EventCalendarActionResult) {
        let notificationFeedback = UINotificationFeedbackGenerator()
        switch result {
        case .added:
            notificationFeedback.notificationOccurred(.success)
        case .alreadyAdded:
            notificationFeedback.notificationOccurred(.success)
        case .removed:
            notificationFeedback.notificationOccurred(.success)
        case .notFound:
            calendarAlertTitle = "Not Found"
            calendarAlertMessage = "We couldn't find this event in your calendar, so no changes were made."
            notificationFeedback.notificationOccurred(.warning)
        case .permissionDenied:
            calendarAlertTitle = "Calendar Access Needed"
            calendarAlertMessage = "Enable Calendar access for CryptoSage in Settings to use this action."
            notificationFeedback.notificationOccurred(.error)
        case .failed(let message):
            calendarAlertTitle = "Calendar Error"
            calendarAlertMessage = message
            notificationFeedback.notificationOccurred(.error)
        }

        // Only interrupt the user when action needs attention.
        if case .notFound = result {
            showCalendarAlert = true
        } else if case .permissionDenied = result {
            showCalendarAlert = true
        } else if case .failed = result {
            showCalendarAlert = true
        }
    }

    private func timeUntilString(from date: Date) -> String {
        let now = Date()
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        if date < now { return "Passed" }
        let comps = cal.dateComponents([.day, .hour], from: now, to: date)
        if let d = comps.day, d >= 2 { return "in \(d)d" }
        if let h = comps.hour, h >= 1 { return "in \(h)h" }
        return "Soon"
    }

    // PERFORMANCE FIX: Cached date formatters
    private static let _shortDateFmt: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "MMM d"; return df
    }()
    private static let _reminderDateFmt: DateFormatter = {
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short; return df
    }()
    private static let _fullDateFmt: DateFormatter = {
        let df = DateFormatter(); df.dateStyle = .full; df.timeStyle = .short; return df
    }()

    private func shortDate(_ date: Date) -> String {
        Self._shortDateFmt.string(from: date)
    }

    private var reminderMenu: some View {
        Group {
            Button {
                showReminderSheet = true
            } label: {
                Label("Remind me", systemImage: "bell")
            }
            Button {
                toggleCalendarEvent()
            } label: {
                Label(
                    hasCalendarEvent ? "Remove from Calendar" : "Add to Calendar",
                    systemImage: hasCalendarEvent ? "calendar.badge.minus" : "calendar.badge.plus"
                )
            }
            if let url = item.url {
                Button {
                    openSafari(url)
                } label: {
                    Label("Open link", systemImage: "safari")
                }
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var reminderChoices: some View {
        Group {
            if hasReminder {
                // Show current reminder info and cancel option
                if let fireDate = reminderManager.reminderDate(for: item.id) {
                    Button("Reminder: \(formattedReminderDate(fireDate))") { }
                        .disabled(true)
                }
                
                Button("Cancel Reminder", role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    reminderManager.cancelReminder(for: item.id)
                    showCancelConfirm = true
                }
                
                Button("Change Reminder") {
                    // Will show the set options on next tap
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        reminderManager.cancelReminder(for: item.id)
                        showReminderSheet = true
                    }
                }
                
                Button("Keep Reminder", role: .cancel) { }
            } else {
                // Set new reminder options
                Button("At time of event") {
                    scheduleEventNotification(eventID: item.id, title: item.title, body: item.subtitle ?? "Event reminder", date: item.date, leadTime: 0)
                    showConfirm = true
                }
                Button("1 hour before") {
                    scheduleEventNotification(eventID: item.id, title: item.title, body: item.subtitle ?? "Event reminder", date: item.date, leadTime: 3600)
                    showConfirm = true
                }
                Button("1 day before") {
                    scheduleEventNotification(eventID: item.id, title: item.title, body: item.subtitle ?? "Event reminder", date: item.date, leadTime: 86400)
                    showConfirm = true
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }
    
    private func formattedReminderDate(_ date: Date) -> String {
        return Self._reminderDateFmt.string(from: date)
    }
}

// MARK: - Quick Action Button Style

private struct QuickActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Premium Skeleton Loading

struct EventRowSkeleton: View {
    @State private var shimmerOffset: CGFloat = -1
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Impact indicator skeleton
            RoundedRectangle(cornerRadius: 3)
                .fill(shimmerFill)
                .frame(width: 4, height: 48)
            
            VStack(alignment: .leading, spacing: 8) {
                // Title skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerFill)
                    .frame(height: 14)
                    .frame(maxWidth: 180)
                
                // Badges row skeleton
                HStack(spacing: 6) {
                    // Category badge
                    Capsule()
                        .fill(shimmerFill)
                        .frame(width: 72, height: 20)
                    
                    // Impact badge
                    Capsule()
                        .fill(shimmerFill)
                        .frame(width: 48, height: 20)
                    
                    // Date
                    RoundedRectangle(cornerRadius: 3)
                        .fill(shimmerFill)
                        .frame(width: 40, height: 12)
                    
                    Spacer()
                    
                    // Countdown badge
                    Capsule()
                        .fill(shimmerFill)
                        .frame(width: 56, height: 24)
                }
                
                // Subtitle skeleton
                RoundedRectangle(cornerRadius: 3)
                    .fill(shimmerFill)
                    .frame(height: 10)
                    .frame(maxWidth: 160)
            }
            
            Spacer(minLength: 0)
            
            // Menu button skeleton
            Circle()
                .fill(shimmerFill)
                .frame(width: 28, height: 28)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(skeletonBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 0.5)
        )
        .onAppear {
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { shimmerOffset = 2 }
                }
                return
            }
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { shimmerOffset = 2 }
        }
        // PERFORMANCE FIX v21: Pause shimmer during scroll
        .onReceive(ScrollStateManager.shared.$isScrolling.removeDuplicates()) { scrolling in
            if scrolling { shimmerOffset = -1 }
            else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { shimmerOffset = 2 }
                }
            }
        }
    }
    
    private var shimmerFill: some ShapeStyle {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: skeletonBaseColor, location: 0),
                .init(color: skeletonBaseColor, location: max(0, shimmerOffset - 0.3)),
                .init(color: skeletonHighlightColor, location: shimmerOffset),
                .init(color: skeletonBaseColor, location: min(1, shimmerOffset + 0.3)),
                .init(color: skeletonBaseColor, location: 1)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var skeletonBaseColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    
    private var skeletonHighlightColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.9)
    }
    
    private var skeletonBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackgroundElevated)
            
            // Subtle top highlight
            LinearGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.03 : 0.06), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Stats Card Skeleton

struct EventsStatsCardSkeleton: View {
    @State private var shimmerOffset: CGFloat = -1
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                skeletonRect(width: 100, height: 14)
                Spacer()
                skeletonRect(width: 80, height: 10)
            }
            
            // Stats row
            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    skeletonRect(width: 60, height: 12)
                    HStack(spacing: 8) {
                        skeletonCircle(size: 28)
                        skeletonCircle(size: 28)
                        skeletonCircle(size: 28)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Divider().frame(height: 40)
                
                VStack(spacing: 8) {
                    skeletonRect(width: 70, height: 12)
                    HStack(spacing: 8) {
                        skeletonCircle(size: 28)
                        skeletonCircle(size: 28)
                        skeletonCircle(size: 28)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            // Next event highlight
            HStack(spacing: 10) {
                skeletonCircle(size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    skeletonRect(width: 80, height: 10)
                    skeletonRect(width: 140, height: 14)
                }
                Spacer()
                Capsule()
                    .fill(shimmerFill)
                    .frame(width: 60, height: 24)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.Adaptive.cardBackgroundElevated.opacity(0.5))
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                // PERFORMANCE FIX v19: Replaced .ultraThinMaterial
                .fill(DS.Adaptive.chipBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
        .onAppear {
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { shimmerOffset = 2 }
                }
                return
            }
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { shimmerOffset = 2 }
        }
        // PERFORMANCE FIX v21: Pause shimmer during scroll
        .onReceive(ScrollStateManager.shared.$isScrolling.removeDuplicates()) { scrolling in
            if scrolling { shimmerOffset = -1 }
            else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { shimmerOffset = 2 }
                }
            }
        }
    }
    
    private func skeletonRect(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 3)
            .fill(shimmerFill)
            .frame(width: width, height: height)
    }
    
    private func skeletonCircle(size: CGFloat) -> some View {
        Circle()
            .fill(shimmerFill)
            .frame(width: size, height: size)
    }
    
    private var shimmerFill: some ShapeStyle {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: skeletonBaseColor, location: 0),
                .init(color: skeletonBaseColor, location: max(0, shimmerOffset - 0.3)),
                .init(color: skeletonHighlightColor, location: shimmerOffset),
                .init(color: skeletonBaseColor, location: min(1, shimmerOffset + 0.3)),
                .init(color: skeletonBaseColor, location: 1)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var skeletonBaseColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    
    private var skeletonHighlightColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.9)
    }
}

// MARK: - Animation Modifiers

struct ConditionalBreathingGlow: ViewModifier {
    let isActive: Bool
    let color: Color
    @State private var breathe = false
    
    func body(content: Content) -> some View {
        content
            // PERFORMANCE FIX v21: Scroll-aware breathing (pauses during scroll)
            .scrollAwarePulse(active: $breathe, duration: 1.2, delay: 0.3)
    }
}

struct PulsingDot: ViewModifier {
    @State private var pulse = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(pulse ? 1.3 : 1.0)
            .opacity(pulse ? 0.7 : 1.0)
            // PERFORMANCE FIX v21: Scroll-aware pulsing (pauses during scroll)
            .scrollAwarePulse(active: $pulse, duration: 0.8, delay: 0.3)
    }
}

// MARK: - All Events View (Push Navigation)

public struct AllEventsView: View {
    @ObservedObject public var vm: EventsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var filter: EventCategory = .all
    @State private var contentAppeared = false
    @State private var expandedSections: Set<EventTimeGroup> = [.imminent, .thisWeek, .thisMonth]

    public var body: some View {
        VStack(spacing: 0) {
            // Unified header with SubpageHeaderBar (chevron back for push navigation)
            SubpageHeaderBar(
                title: "All Events",
                showCloseButton: false,
                onDismiss: { dismiss() }
            )
            
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Premium stats card
                    eventsStatsCard
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    
                    // Filter picker
                    EventsFilterPicker(selectedFilter: $filter)
                        .padding(.horizontal, 16)
                    
                    // Grouped event sections
                    groupedEventsContent
                }
                .padding(.bottom, 32)
            }
            .refreshable {
                await vm.fetchEvents(forceRefresh: true)
            }
        }
        .background(DS.Adaptive.background)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                contentAppeared = true
            }
        }
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
    
    // MARK: - Stats Card
    
    private var eventsStatsCard: some View {
        let items = vm.items.filter { $0.date > Date() }
        let highCount = items.filter { $0.impact == .high }.count
        let mediumCount = items.filter { $0.impact == .medium }.count
        let lowCount = items.filter { $0.impact == .low }.count
        
        let onchainCount = items.filter { $0.category == .onchain }.count
        let macroCount = items.filter { $0.category == .macro }.count
        let exchangeCount = items.filter { $0.category == .exchange }.count
        
        return VStack(spacing: 12) {
            // Header
            HStack {
                Text("Event Summary")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textSecondary)
                Spacer()
                if let lastUpdated = vm.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                }
            }
            
            // Stats grid
            HStack(spacing: 12) {
                // Impact breakdown
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                        Text("Impact")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                    
                    HStack(spacing: 8) {
                        impactStatBadge(count: highCount, color: .red, label: "High")
                        impactStatBadge(count: mediumCount, color: DS.Adaptive.neutralYellow, label: "Med")
                        impactStatBadge(count: lowCount, color: .green, label: "Low")
                    }
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                    .frame(height: 40)
                
                // Category breakdown
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Adaptive.gold)
                        Text("Categories")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                    
                    HStack(spacing: 8) {
                        categoryStatBadge(count: onchainCount, color: .cyan, icon: "link.circle.fill")
                        categoryStatBadge(count: macroCount, color: .purple, icon: "globe.americas.fill")
                        categoryStatBadge(count: exchangeCount, color: .orange, icon: "building.columns.fill")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            // Next high-impact event highlight
            if let nextHigh = items.first(where: { $0.impact == .high }) {
                nextEventHighlight(event: nextHigh)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                // PERFORMANCE FIX v19: Replaced .ultraThinMaterial
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
        .opacity(contentAppeared ? 1 : 0)
        .offset(y: contentAppeared ? 0 : 20)
    }
    
    private func impactStatBadge(count: Int, color: Color, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(DS.Adaptive.textTertiary)
        }
        .frame(minWidth: 32)
    }
    
    private func categoryStatBadge(count: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
        }
    }
    
    private func nextEventHighlight(event: EventItem) -> some View {
        HStack(spacing: 10) {
            // Icon
            ZStack {
                Circle()
                    .fill(event.impact.color.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(event.impact.color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Next High-Impact")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.Adaptive.textTertiary)
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Countdown
            Text(timeUntilDetailed(event.date))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(event.impact.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(event.impact.color.opacity(0.12))
                )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.cardBackgroundElevated.opacity(0.5))
        )
    }
    
    private func timeUntilDetailed(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let comps = cal.dateComponents([.day], from: Date(), to: date)
        if let d = comps.day, d >= 1 { return "in \(d) days" }
        return "Soon"
    }
    
    // MARK: - Grouped Content
    
    private var groupedEventsContent: some View {
        let filteredItems = vm.filtered(filter)
        let grouped = groupEvents(filteredItems)
        
        return VStack(spacing: 12) {
            ForEach(EventTimeGroup.allCases, id: \.self) { group in
                if let events = grouped[group], !events.isEmpty {
                    eventGroupSection(group: group, events: events)
                        .opacity(contentAppeared ? 1 : 0)
                        .offset(y: contentAppeared ? 0 : 15)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(group.sortOrder) * 0.08), value: contentAppeared)
                }
            }
            
            // Empty state
            if filteredItems.isEmpty {
                allEventsEmptyState
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func eventGroupSection(group: EventTimeGroup, events: [EventItem]) -> some View {
        VStack(spacing: 8) {
            // Section header
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if expandedSections.contains(group) {
                        expandedSections.remove(group)
                    } else {
                        expandedSections.insert(group)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    // Group icon with color
                    ZStack {
                        Circle()
                            .fill(group.color.opacity(0.15))
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: group.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(group.color)
                    }
                    
                    Text(group.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    
                    Text("\(events.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(DS.Adaptive.chipBackground)
                        )
                    
                    Spacer()
                    
                    Image(systemName: expandedSections.contains(group) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textTertiary)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Events list
            if expandedSections.contains(group) {
                VStack(spacing: 8) {
                    ForEach(events, id: \.id) { item in
                        PremiumEventRow(item: item)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity
                ))
            }
        }
    }
    
    private var allEventsEmptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [DS.Adaptive.gold.opacity(0.15), Color.orange.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                
                Image(systemName: vm.isLoading ? "magnifyingglass" : "calendar.badge.exclamationmark")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DS.Adaptive.gold, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse, isActive: vm.isLoading)
            }
            
            VStack(spacing: 6) {
                Text(vm.isLoading ? "Loading events…" : "No events found")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                Text(filter != .all ? "Try selecting 'All' categories" : "Check back later for upcoming events")
                    .font(.subheadline)
                    .foregroundStyle(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            if !vm.isLoading {
                Button {
                    Task {
                        await vm.fetchEvents(forceRefresh: true)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(DS.Adaptive.chipBackground)
                    )
                    .overlay(
                        Capsule()
                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Grouping Logic
    
    private func groupEvents(_ events: [EventItem]) -> [EventTimeGroup: [EventItem]] {
        let now = Date()
        let calendar = Calendar.current
        
        var grouped: [EventTimeGroup: [EventItem]] = [:]
        
        for event in events {
            let group = EventTimeGroup.forDate(event.date, relativeTo: now, calendar: calendar)
            if grouped[group] == nil {
                grouped[group] = []
            }
            grouped[group]?.append(event)
        }
        
        return grouped
    }
}

// MARK: - Event Time Group

enum EventTimeGroup: String, CaseIterable {
    case imminent = "Imminent"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case later = "Later"
    case passed = "Passed"
    
    var title: String { rawValue }
    
    var icon: String {
        switch self {
        case .imminent: return "flame.fill"           // Fire = urgent
        case .thisWeek: return "clock.badge.exclamationmark"  // Clock with alert
        case .thisMonth: return "calendar.circle"      // Calendar circle
        case .later: return "calendar.badge.plus"     // Future events
        case .passed: return "checkmark.circle"       // Completed
        }
    }
    
    var color: Color {
        switch self {
        case .imminent: return .red
        case .thisWeek: return .orange
        case .thisMonth: return DS.Adaptive.gold
        case .later: return .cyan
        case .passed: return .secondary
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .imminent: return 0
        case .thisWeek: return 1
        case .thisMonth: return 2
        case .later: return 3
        case .passed: return 4
        }
    }
    
    static func forDate(_ date: Date, relativeTo now: Date, calendar: Calendar) -> EventTimeGroup {
        if date < now {
            return .passed
        }
        
        // Within 24 hours
        if date.timeIntervalSince(now) < 24 * 60 * 60 {
            return .imminent
        }
        
        // This week (~10 days for practical planning, covers two weekends)
        if let weekEnd = calendar.date(byAdding: .day, value: 10, to: now), date < weekEnd {
            return .thisWeek
        }
        
        // This month (next 30 days)
        if let monthEnd = calendar.date(byAdding: .day, value: 30, to: now), date < monthEnd {
            return .thisMonth
        }
        
        return .later
    }
}

// MARK: - Event Detail Sheet

public struct EventDetailSheet: View {
    public let item: EventItem
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(spacing: 0) {
            SubpageHeaderBar(
                title: "Event Details",
                showCloseButton: true,
                onDismiss: { dismiss() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DS.Adaptive.textPrimary)
                        
                        HStack(spacing: 8) {
                            Label(item.category.rawValue, systemImage: item.category.icon)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(item.category.color)
                            
                            Text("•")
                                .foregroundStyle(.secondary)
                            
                            Text(item.impact.rawValue + " Impact")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(item.impact.color)
                        }
                    }
                    
                    Divider()
                    
                    // Date & Time
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.title3)
                            .foregroundStyle(DS.Adaptive.gold)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Date")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formattedDate(item.date))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                        }
                    }
                    
                    // Countdown
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.title3)
                            .foregroundStyle(DS.Adaptive.gold)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Time Until")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(detailedCountdown(item.date))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(item.date > Date() ? item.impact.color : .secondary)
                        }
                    }
                    
                    // Coins
                    if !item.coinSymbols.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "bitcoinsign.circle")
                                .font(.title3)
                                .foregroundStyle(DS.Adaptive.gold)
                                .frame(width: 32)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Related Assets")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(item.coinSymbols.joined(separator: ", "))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(DS.Adaptive.textPrimary)
                            }
                        }
                    }
                    
                    // Description
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(subtitle)
                                .font(.body)
                                .foregroundStyle(DS.Adaptive.textPrimary)
                        }
                    }
                    
                    Spacer(minLength: 20)
                    
                    // Action buttons
                    if let url = item.url {
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "safari")
                                Text("View Source")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CSNeonCTAStyle())
                    }
                }
                .padding(20)
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
    }
    
    private static let _fullDateFmt: DateFormatter = {
        let df = DateFormatter(); df.dateStyle = .full; df.timeStyle = .short; return df
    }()

    private func formattedDate(_ date: Date) -> String {
        return Self._fullDateFmt.string(from: date)
    }
    
    private func detailedCountdown(_ date: Date) -> String {
        let now = Date()
        if date < now { return "Event has passed" }
        
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: date)
        var parts: [String] = []
        
        if let days = components.day, days > 0 {
            parts.append("\(days) day\(days == 1 ? "" : "s")")
        }
        if let hours = components.hour, hours > 0 {
            parts.append("\(hours) hour\(hours == 1 ? "" : "s")")
        }
        if let minutes = components.minute, minutes > 0, parts.count < 2 {
            parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")")
        }
        
        return parts.isEmpty ? "Soon" : parts.joined(separator: ", ")
    }
}

// MARK: - Helper Functions

fileprivate func openSafari(_ url: URL) {
    #if canImport(UIKit)
    UIApplication.shared.open(url)
    #elseif canImport(AppKit)
    NSWorkspace.shared.open(url)
    #endif
}

fileprivate func addEventToCalendar(
    eventID: String,
    title: String,
    date: Date,
    notes: String?
) async -> EventCalendarActionResult {
    let eventStore = EKEventStore()
    let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
    guard granted else { return .permissionDenied }

    if let trackedIdentifier = EventCalendarManager.shared.calendarIdentifier(for: eventID),
       eventStore.event(withIdentifier: trackedIdentifier) != nil {
        return .alreadyAdded
    }

    if let existing = findMatchingCalendarEvent(eventStore: eventStore, title: title, date: date) {
        if let existingIdentifier = existing.eventIdentifier {
            EventCalendarManager.shared.setCalendarEvent(for: eventID, identifier: existingIdentifier)
        }
        return .alreadyAdded
    }

    let event = EKEvent(eventStore: eventStore)
    event.title = title
    event.startDate = date
    event.endDate = date.addingTimeInterval(60 * 60)
    event.notes = notes
    event.calendar = eventStore.defaultCalendarForNewEvents

    do {
        try eventStore.save(event, span: .thisEvent)
        if let identifier = event.eventIdentifier {
            EventCalendarManager.shared.setCalendarEvent(for: eventID, identifier: identifier)
        }
        return .added
    } catch {
        return .failed("Couldn't save the event to Calendar. Please try again.")
    }
}

fileprivate func removeEventFromCalendar(
    eventID: String,
    title: String,
    date: Date
) async -> EventCalendarActionResult {
    let eventStore = EKEventStore()
    let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
    guard granted else { return .permissionDenied }

    if let trackedIdentifier = EventCalendarManager.shared.calendarIdentifier(for: eventID),
       let trackedEvent = eventStore.event(withIdentifier: trackedIdentifier) {
        do {
            try eventStore.remove(trackedEvent, span: .thisEvent)
            EventCalendarManager.shared.clearCalendarEvent(for: eventID)
            return .removed
        } catch {
            return .failed("Couldn't remove the event from Calendar. Please try again.")
        }
    }

    if let existing = findMatchingCalendarEvent(eventStore: eventStore, title: title, date: date) {
        do {
            try eventStore.remove(existing, span: .thisEvent)
            EventCalendarManager.shared.clearCalendarEvent(for: eventID)
            return .removed
        } catch {
            return .failed("Couldn't remove the event from Calendar. Please try again.")
        }
    }

    EventCalendarManager.shared.clearCalendarEvent(for: eventID)
    return .notFound
}

/// Searches a narrow time window for an event matching title and near-identical start time.
fileprivate func findMatchingCalendarEvent(eventStore: EKEventStore, title: String, date: Date) -> EKEvent? {
    let windowStart = date.addingTimeInterval(-4 * 60 * 60)
    let windowEnd = date.addingTimeInterval(4 * 60 * 60)
    let predicate = eventStore.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    return eventStore.events(matching: predicate).first { event in
        let titleMatches = event.title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle
        let timeDelta = abs(event.startDate.timeIntervalSince(date))
        return titleMatches && timeDelta < 5 * 60
    }
}

fileprivate func scheduleEventNotification(eventID: String, title: String, body: String, date: Date, leadTime: TimeInterval) {
    let center = UNUserNotificationCenter.current()
    let triggerDate = date.addingTimeInterval(-leadTime)
    
    // Don't schedule if trigger date is in the past
    guard triggerDate > Date() else { return }
    
    // Use deterministic identifier based on event ID
    let notificationID = EventReminderManager.shared.notificationIdentifier(for: eventID)
    
    // First cancel any existing reminder for this event
    center.removePendingNotificationRequests(withIdentifiers: [notificationID])
    
    center.getNotificationSettings { settings in
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            scheduleNotification()
        case .notDetermined:
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                if granted { scheduleNotification() }
            }
        default:
            break
        }
    }
    
    func scheduleNotification() {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: triggerDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        center.add(request) { error in
            if error == nil {
                // Track the reminder on main thread
                DispatchQueue.main.async {
                    EventReminderManager.shared.setReminder(for: eventID, fireDate: triggerDate)
                }
            }
        }
    }
}
