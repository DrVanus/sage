import SwiftUI
import EventKit
import UserNotifications
import Combine

public enum EventCategory: String, CaseIterable, Identifiable {
    case all = "All", onchain = "On‑chain", macro = "Macro", exchange = "Exchange"
    public var id: String { rawValue }
}

public enum Impact: String {
    case low = "Low", medium = "Medium", high = "High"
}

public struct EventItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let date: Date
    public let category: EventCategory
    public let impact: Impact
    public let subtitle: String?
    public let url: URL?
    
    public init(title: String, date: Date, category: EventCategory, impact: Impact, subtitle: String?, url: URL?) {
        self.title = title
        self.date = date
        self.category = category
        self.impact = impact
        self.subtitle = subtitle
        self.url = url
    }
}

public final class EventsViewModel: ObservableObject {
    @Published public var items: [EventItem] = [
        EventItem(title: "ETH2 Hard Fork", date: Date().addingTimeInterval(60*60*24*5), category: .onchain, impact: .high, subtitle: "Upgrade to reduce fees", url: URL(string: "https://ethereum.org/en/roadmap/")),
        EventItem(title: "DOGE Conference", date: Date().addingTimeInterval(60*60*24*12), category: .exchange, impact: .medium, subtitle: "Global doge event", url: URL(string: "https://dogecoin.com")),
        EventItem(title: "CPI Release", date: Date().addingTimeInterval(60*60*24*9), category: .macro, impact: .high, subtitle: "US inflation data", url: URL(string: "https://www.bls.gov/")),
        EventItem(title: "SOL Hackathon", date: Date().addingTimeInterval(60*60*24*15), category: .onchain, impact: .low, subtitle: "Dev grants for new apps", url: URL(string: "https://solana.com"))
    ]
    public init() {}
    public func filtered(_ cat: EventCategory) -> [EventItem] {
        let sorted = items.sorted { $0.date < $1.date }
        if cat == .all { return sorted }
        return sorted.filter { $0.category == cat }
    }
}

public struct EventsSectionView: View {
    @ObservedObject public var vm: EventsViewModel
    @Binding public var showAll: Bool
    @State private var filter: EventCategory = .all
    @State private var selectedForDetail: EventItem? = nil

    public init(vm: EventsViewModel, showAll: Binding<Bool>) {
        self._vm = ObservedObject(initialValue: vm)
        self._showAll = showAll
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "calendar")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.csGold)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text("Events & Catalysts")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button { showAll = true } label: {
                    HStack(spacing: 6) { Text("All Events"); Image(systemName: "chevron.right") }
                }
                .buttonStyle(CSSecondaryCTAButtonStyle(height: 28, cornerRadius: 10, horizontalPadding: 10, font: .caption.weight(.semibold)))
                .accessibilityLabel("See all events")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5), alignment: .bottom)

            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $filter) {
                    ForEach(EventCategory.allCases) { cat in Text(cat.rawValue).tag(cat) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                VStack(spacing: 8) {
                    ForEach(vm.filtered(filter).prefix(3), id: \.id) { item in
                        EventRow(item: item, onTap: { tapped in selectedForDetail = tapped })
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 8)
                .animation(.snappy, value: filter)
            }
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        }
        .sheet(item: $selectedForDetail) { item in
            EventDetailSheet(item: item)
        }
    }
}

public struct EventRow: View {
    public let item: EventItem
    public var onTap: ((EventItem) -> Void)? = nil
    @State private var showConfirm = false
    @State private var showReminderSheet = false

    public init(item: EventItem, onTap: ((EventItem) -> Void)? = nil) {
        self.item = item
        self.onTap = onTap
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).foregroundStyle(.white).lineLimit(2)
                HStack(spacing: 8) { categoryBadge; impactBadge; Text(shortDate(item.date)).font(.caption2).foregroundStyle(.secondary); timeUntilBadge }
                if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Menu { reminderMenu } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            .alert("Reminder scheduled", isPresented: $showConfirm) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("We'll remind you near the event time.")
            }
            .confirmationDialog("Set reminder", isPresented: $showReminderSheet, titleVisibility: .visible) {
                reminderChoices
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .overlay(alignment: .leading) {
            Capsule().fill(impactColor.opacity(0.9)).frame(width: 4).padding(.vertical, 8)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if let onTap {
                onTap(item)
            } else if let url = item.url {
                openSafari(url)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(item.title), \(item.category.rawValue), \(item.impact.rawValue) impact, \(shortDate(item.date))")
    }

    private var categoryBadge: some View {
        let (icon, color): (String, Color) = {
            switch item.category {
            case .onchain: return ("link", .blue)
            case .macro: return ("globe.americas", .purple)
            case .exchange: return ("building.columns", .orange)
            case .all: return ("calendar", .gray)
            }
        }()
        return Label(item.category.rawValue, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private var impactBadge: some View {
        let color: Color = impactColor
        return Text(item.impact.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private var impactColor: Color {
        switch item.impact {
        case .high: return .red
        case .medium: return .yellow
        case .low: return .green
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

    private var timeUntilBadge: some View {
        Text(timeUntilString(from: item.date))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(impactColor.opacity(0.18)))
            .foregroundStyle(impactColor)
    }

    private func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }

    private var reminderMenu: some View {
        Group {
            Button {
                showReminderSheet = true
            } label: {
                Label("Remind me", systemImage: "bell")
            }
            Button {
                addEventToCalendar(title: item.title, date: item.date, notes: item.subtitle)
                showConfirm = true
            } label: {
                Label("Add to Calendar", systemImage: "calendar.badge.plus")
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
            Button("At time") {
                scheduleEventNotification(title: item.title, body: item.subtitle ?? "Event reminder", date: item.date, leadTime: 0)
                showConfirm = true
            }
            Button("1 hour before") {
                scheduleEventNotification(title: item.title, body: item.subtitle ?? "Event reminder", date: item.date, leadTime: 3600)
                showConfirm = true
            }
            Button("1 day before") {
                scheduleEventNotification(title: item.title, body: item.subtitle ?? "Event reminder", date: item.date, leadTime: 86400)
                showConfirm = true
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

public struct AllEventsSheet: View {
    @ObservedObject public var vm: EventsViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            List(vm.items) { item in
                Text(item.title)
            }
            .navigationTitle("Events")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

public struct EventDetailSheet: View {
    public let item: EventItem
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.title).font(.headline).foregroundStyle(.white)
                Text(item.subtitle ?? "").foregroundStyle(.secondary)
                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// Helper functions used in EventRow (assumed to be implemented elsewhere or implement here)

fileprivate func openSafari(_ url: URL) {
    #if canImport(UIKit)
    UIApplication.shared.open(url)
    #elseif canImport(AppKit)
    NSWorkspace.shared.open(url)
    #endif
}

fileprivate func addEventToCalendar(title: String, date: Date, notes: String?) {
    let eventStore = EKEventStore()
    eventStore.requestAccess(to: .event) { granted, error in
        if granted && error == nil {
            let event = EKEvent(eventStore: eventStore)
            event.title = title
            event.startDate = date
            event.endDate = date.addingTimeInterval(60*60) // 1 hour default duration
            event.notes = notes
            event.calendar = eventStore.defaultCalendarForNewEvents
            do {
                try eventStore.save(event, span: .thisEvent)
            } catch {
                // Handle error
            }
        }
    }
}

fileprivate func scheduleEventNotification(title: String, body: String, date: Date, leadTime: TimeInterval) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
        guard settings.authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let triggerDate = date.addingTimeInterval(-leadTime)
        if triggerDate < Date() { return } // Don't schedule past notifications

        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: triggerDate), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        center.add(request)
    }
}

