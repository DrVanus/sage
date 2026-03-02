import SwiftUI
import Charts
import UIKit

private let chartGold = BrandColors.goldBase

// MARK: - Data Model
struct PortfolioDataPoint: Identifiable, Equatable {
    // Use date-based ID for stable identity across reloads (prevents unnecessary re-renders)
    var id: String { "\(Int(date.timeIntervalSince1970))" }
    let date: Date
    let value: Double
    
    static func == (lhs: PortfolioDataPoint, rhs: PortfolioDataPoint) -> Bool {
        lhs.date == rhs.date && lhs.value == rhs.value
    }
}

// How to display the y-values
private enum ValueMode: String, CaseIterable { case value = "Value", roi = "ROI %" }

// MARK: - TimeRange Enum
enum TimeRange: String, CaseIterable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case threeMonth = "3M"
    case sixMonth = "6M"
    case year = "1Y"
    case threeYear = "3Y"
    case all = "ALL"
}


// ChartViewType replaces SummaryViewMode for chart mode selection
enum ChartViewType: String, CaseIterable, Identifiable {
    case pie  = "Pie"
    case line = "Line"
    var id: String { rawValue }
}

// MARK: - Chart ViewModel

// Assuming ChartPoint is defined somewhere else, as per instruction
// struct ChartPoint { let date: Date; let value: Double }

@MainActor
class PortfolioChartViewModel: ObservableObject {
    @Published var dataPoints: [PortfolioDataPoint] = []
    @Published var selectedRange: TimeRange = .all
    
    // Metrics based on the portfolio data passed in.
    @Published var totalValue: Double = 0.0
    @Published var dailyChange: Double = 0.0  // Compute from historical data when available
    @Published var totalPL: Double = 0.0
    @Published var roiPercent: Double = 0.0
    @Published var largestHoldingName: String = "N/A"
    @Published var largestHoldingPercent: Double = 0.0
    @Published var twentyFourHrPL: Double = 0.0
    @Published var unrealizedPL: Double = 0.0
    @Published var realizedPL: Double = 0.0

    @Published var minValue: Double = 0
    @Published var maxValue: Double = 0
    @Published var rangeChangePercent: Double = 0
    
    // Debounce support to coalesce rapid updates
    private var pendingLoadWork: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.3

    private func startDate(for range: TimeRange, now: Date = Date()) -> Date {
        switch range {
        case .day:         return Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        case .week:        return Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:       return Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonth:  return Calendar.current.date(byAdding: .month, value: -3, to: now) ?? now
        case .sixMonth:    return Calendar.current.date(byAdding: .month, value: -6, to: now) ?? now
        case .year:        return Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        case .threeYear:   return Calendar.current.date(byAdding: .year, value: -3, to: now) ?? now
        case .all:         return Date.distantPast
        }
    }

    func loadData(for range: TimeRange, history: [ChartPoint], portfolioTotal: Double) {
        // Cancel any pending debounced load
        pendingLoadWork?.cancel()
        
        // Create new debounced work item
        let workItem = DispatchWorkItem { [weak self] in
            self?.performLoadData(for: range, history: history, portfolioTotal: portfolioTotal)
        }
        pendingLoadWork = workItem
        
        // Execute after debounce interval
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    /// Immediate data load for user-initiated actions (no debounce delay)
    func loadDataImmediate(for range: TimeRange, history: [ChartPoint], portfolioTotal: Double) {
        // Cancel any pending debounced load to avoid conflicts
        pendingLoadWork?.cancel()
        // Execute immediately
        performLoadData(for: range, history: history, portfolioTotal: portfolioTotal)
    }
    
    private func performLoadData(for range: TimeRange, history: [ChartPoint], portfolioTotal: Double) {
        let now = Date()
        self.totalValue = portfolioTotal

        if !history.isEmpty {
            let start = startDate(for: range, now: now)
            let filtered = history.filter { $0.date >= start }.sorted { $0.date < $1.date }
            if !filtered.isEmpty {
                self.dataPoints = filtered.map { PortfolioDataPoint(date: $0.date, value: $0.value) }
            } else {
                // If filter produced no points (e.g., very new history), use all
                self.dataPoints = history.sorted { $0.date < $1.date }.map { PortfolioDataPoint(date: $0.date, value: $0.value) }
            }
        } else {
            // Fallback to simulated data (same as before)
            let count: Int = {
                switch range {
                case .day: return 24
                case .week: return 7
                case .month: return 30
                case .threeMonth: return 90
                case .sixMonth: return 180
                case .year: return 365
                case .threeYear: return 365 * 3
                case .all: return 365 * 3
                }
            }()
            self.dataPoints = (0..<count).map { i in
                let date = Calendar.current.date(byAdding: .day, value: -(count - 1 - i), to: now) ?? now
                // Use deterministic sine wave pattern instead of random to prevent visual jitter
                let waveFactor = sin(Double(i) * 0.5) * 0.02
                let value = portfolioTotal * (1 + waveFactor)
                return PortfolioDataPoint(date: date, value: value)
            }.sorted { $0.date < $1.date }
        }

        // Derive min/max and range change
        if let minV = self.dataPoints.min(by: { $0.value < $1.value })?.value,
           let maxV = self.dataPoints.max(by: { $0.value < $1.value })?.value,
           let first = self.dataPoints.first?.value,
           let last = self.dataPoints.last?.value {
            self.minValue = minV
            self.maxValue = maxV
            self.rangeChangePercent = first == 0 ? 0 : ((last - first) / first) * 100
        } else {
            self.minValue = 0
            self.maxValue = 0
            self.rangeChangePercent = 0
        }

        // Placeholders for other metrics (unchanged)
        self.dailyChange = 0.0
        self.totalPL = 0.0
        self.roiPercent = 0.0
        self.largestHoldingName = "N/A"
        self.largestHoldingPercent = 0.0
        self.twentyFourHrPL = 0.0
        self.unrealizedPL = 0.0
        self.realizedPL = 0.0
    }
    
    // Currency formatter (cached)
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = CurrencyManager.currencyCode
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    func formatCurrency(_ value: Double) -> String {
        return Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    // Percent formatter (helper)
    func formatPercent(_ value: Double, includePlus: Bool = true, fractionDigits: Int = 2) -> String {
        let sign = (includePlus && value >= 0) ? "+" : ""
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let core = formatter.string(from: NSNumber(value: value)) ?? String(format: "%0.*f", fractionDigits, value)
        return "\(sign)\(core)%"
    }
    
    var formattedTotalValue: String {
        formatCurrency(totalValue)
    }
    
    var formattedDailyChange: String {
        String(format: "%.2f", dailyChange)
    }

    // MARK: - Axis Density Helper
    private func axisDesiredCount(for range: TimeRange) -> Int {
        switch range {
        case .day: return 6
        case .week: return 5
        case .month: return 6
        case .threeMonth: return 6
        case .sixMonth: return 6
        case .year: return 5
        case .threeYear: return 4
        case .all: return 4
        }
    }

    // MARK: - Percentile helper
    private func percentile(_ sortedValues: [Double], _ p: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let clampedP = min(max(p, 0), 1)
        let idx = Double(sortedValues.count - 1) * clampedP
        let lower = Int(floor(idx))
        let upper = Int(ceil(idx))
        if lower == upper { return sortedValues[lower] }
        let weight = idx - Double(lower)
        return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight
    }
}

// MARK: - TradingViewTimeRangeBar
struct TradingViewTimeRangeBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedRange: TimeRange
    let onRangeSelected: (TimeRange) -> Void

    @Namespace private var pillAnimation

    var body: some View {
        let isDark = colorScheme == .dark

        HStack(spacing: 2) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                let isSelected = selectedRange == range

                Text(range.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(
                        isSelected
                            ? (isDark ? .white : DS.Adaptive.textPrimary)
                            : (isDark ? .gray : DS.Adaptive.textTertiary)
                    )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isDark
                                    ? Color.white.opacity(0.12)
                                    : Color.black.opacity(0.08)
                                )
                                .matchedGeometryEffect(id: "timeframePill", in: pillAnimation)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            selectedRange = range
                        }
                        onRangeSelected(range)
                    }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDark
                    ? Color.white.opacity(0.04)
                    : Color.black.opacity(0.03)
                )
        )
    }
}

// MARK: - Premium Icon Button Style
private struct PremiumIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Premium Chart Mode Toggle (Line <-> Pie)
private struct ChartModeToggle: View {
    @Binding var mode: ChartViewType
    var height: CGFloat = 28
    var cornerRadius: CGFloat = 8
    
    @Namespace private var toggleNS
    @Environment(\.colorScheme) private var colorScheme
    
    // Accent color for selected state
    private let accentGreen = Color(red: 0.2, green: 0.78, blue: 0.5)

    var body: some View {
        HStack(spacing: 0) {
            iconButton(.line, "chart.line.uptrend.xyaxis")
            iconButton(.pie, "chart.pie.fill")
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DS.Adaptive.chipBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart mode")
    }

    @ViewBuilder
    private func iconButton(_ value: ChartViewType, _ systemName: String) -> some View {
        let selected = mode == value
        let isDark = colorScheme == .dark
        let innerRadius = cornerRadius - 2
        
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { mode = value }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                        .fill(accentGreen.opacity(isDark ? 0.22 : 0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                                .stroke(accentGreen.opacity(isDark ? 0.5 : 0.35), lineWidth: 0.5)
                        )
                        .matchedGeometryEffect(id: "chartModeIndicator", in: toggleNS)
                }
                
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selected ? DS.Adaptive.textPrimary : DS.Adaptive.textTertiary)
            }
            .frame(width: height + 4, height: height)  // Slightly wider than tall for icons
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main PortfolioChartView
/// This view takes a PortfolioViewModel reference so it can use the current portfolio total.
struct PortfolioChartView: View {
    // MARK: - Environment
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Animation & Selection State
    @State private var selectedSliceSymbol: String?
    @Namespace private var chartAnim

    // Inject the main portfolio view model.
    @ObservedObject var portfolioVM: PortfolioViewModel
    /// When false, hide the six-metric grid below the chart
    var showMetrics: Bool = true
    /// When false, hide the Allocation/Trend selector
    var showSelector: Bool = true

    // Binding for chart mode (pie/line)
    @Binding var chartMode: ChartViewType

    /// Optional override for allocation data (used for Paper Trading mode)
    var overrideAllocationData: [PortfolioViewModel.AllocationSlice]? = nil
    
    /// Optional override for total value (used for Paper Trading mode)
    var overrideTotalValue: Double? = nil
    
    /// Optional override for chart history (used for Paper Trading mode)
    var overrideHistory: [ChartPoint]? = nil

    @StateObject private var chartVM: PortfolioChartViewModel = PortfolioChartViewModel()

    // Crosshair states
    @State private var selectedValue: PortfolioDataPoint? = nil
    @State private var showCrosshair: Bool = false
    @State private var valueMode: ValueMode = .value
    @AppStorage("portfolio_selected_range") private var storedRangeRaw: String = TimeRange.week.rawValue
    @AppStorage("portfolio_value_mode") private var storedValueModeRaw: String = ValueMode.value.rawValue

    @AppStorage("Haptics.TickInterval") private var hTickInterval: Double = 0.045
    @AppStorage("Haptics.MajorInterval") private var hMajorInterval: Double = 0.22
    @AppStorage("hideBalances") private var hideBalances: Bool = false

    @State private var lastGridSegmentIndex: Int? = nil
    @State private var lastAboveBaseline: Bool? = nil

    @State private var lastHapticTime: TimeInterval = 0
    @State private var showChartOptions: Bool = false

    @State private var scrubActive: Bool = false
    @State private var lastSelectedIndex: Int? = nil
    
    // Pulsing live dot animation state
    @State private var pulse: Bool = false
    
    // Chart geometry for floating tooltip positioning
    @State private var plotAreaFrame: CGRect = .zero
    
    // Track last known total to avoid reloading chart for trivial changes
    @State private var lastKnownTotal: Double = 0
    // Minimum percentage change threshold to trigger chart reload (0.5%)
    private let updateThreshold: Double = 0.005
    
    // PERFORMANCE FIX: Track last history update to prevent multiple updates per frame
    @State private var lastHistoryUpdateTime: CFTimeInterval = 0
    private let historyUpdateMinInterval: CFTimeInterval = 0.1  // 100ms throttle

    private func axisDesiredCount(for range: TimeRange) -> Int {
        switch range {
        case .day: return 6
        case .week: return 5
        case .month: return 6
        case .threeMonth: return 6
        case .sixMonth: return 6
        case .year: return 5
        case .threeYear: return 4
        case .all: return 4
        }
    }

    private func percentile(_ sortedValues: [Double], _ p: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let clampedP = min(max(p, 0), 1)
        let idx = Double(sortedValues.count - 1) * clampedP
        let lower = Int(floor(idx))
        let upper = Int(ceil(idx))
        if lower == upper { return sortedValues[lower] }
        let weight = idx - Double(lower)
        return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight
    }
    
    private func nextRange(after current: TimeRange) -> TimeRange {
        let all = TimeRange.allCases
        if let idx = all.firstIndex(of: current) {
            return all[(idx + 1) % all.count]
        }
        return current
    }

    // MARK: - X-Axis Tick Generation (Professional quality matching trading charts)
    private func xAxisTickDates(for range: TimeRange, points: [PortfolioDataPoint]) -> [Date] {
        guard let first = points.first?.date, let last = points.last?.date, first < last else { return [] }
        let cal = Calendar.current
        let span = last.timeIntervalSince(first)
        
        // Target number of ticks for clean, uncluttered axis
        let targetTickCount = 5
        
        // Helper to generate evenly-spaced ticks when aligned ticks don't work
        func evenlySpacedTicks(count: Int) -> [Date] {
            guard count >= 2 else { return [first, last] }
            let step = span / Double(count - 1)
            return (0..<count).map { i in
                first.addingTimeInterval(Double(i) * step)
            }
        }
        
        var ticks: [Date] = []
        
        switch range {
        case .day:
            // 4-hour aligned ticks for 1-day view (gives ~6 labels for 24h)
            var comps = cal.dateComponents([.year, .month, .day, .hour], from: first)
            let hour = comps.hour ?? 0
            comps.hour = (hour / 4) * 4
            comps.minute = 0
            comps.second = 0
            guard var d = cal.date(from: comps) else { return evenlySpacedTicks(count: targetTickCount) }
            if d < first { d = cal.date(byAdding: .hour, value: 4, to: d) ?? d }
            while d <= last {
                ticks.append(d)
                d = cal.date(byAdding: .hour, value: 4, to: d) ?? d
            }
            // Fallback if not enough ticks
            if ticks.count < 2 { return evenlySpacedTicks(count: targetTickCount) }
            
        case .week:
            // Daily ticks for 1-week view
            var d = cal.startOfDay(for: first)
            if d < first { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
            while d <= last {
                ticks.append(d)
                d = cal.date(byAdding: .day, value: 1, to: d) ?? d
            }
            // Downsample if too many
            if ticks.count > targetTickCount + 2 {
                let step = max(1, ticks.count / targetTickCount)
                ticks = ticks.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
            }
            if ticks.count < 2 { return evenlySpacedTicks(count: targetTickCount) }
            
        case .month:
            // Generate ticks every ~5-7 days for 1-month view
            var d = cal.startOfDay(for: first)
            let totalDays = Int(span / 86400)
            let dayStep = max(5, totalDays / targetTickCount)
            if d < first { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
            while d <= last {
                ticks.append(d)
                d = cal.date(byAdding: .day, value: dayStep, to: d) ?? d
            }
            if ticks.count < 2 { return evenlySpacedTicks(count: targetTickCount) }
            
        case .threeMonth:
            // Generate monthly ticks or bi-weekly if span is shorter
            let totalDays = Int(span / 86400)
            if totalDays < 60 {
                // Less than 2 months: use bi-weekly
                var d = cal.startOfDay(for: first)
                while d <= last {
                    ticks.append(d)
                    d = cal.date(byAdding: .day, value: 14, to: d) ?? d
                }
            } else {
                // Monthly ticks
                var comps = cal.dateComponents([.year, .month], from: first)
                comps.day = 1
                guard var d = cal.date(from: comps) else { return evenlySpacedTicks(count: targetTickCount) }
                // Include the starting month even if it's slightly before first
                while d <= last {
                    if d >= cal.date(byAdding: .day, value: -7, to: first)! {
                        ticks.append(d)
                    }
                    d = cal.date(byAdding: .month, value: 1, to: d) ?? d
                }
            }
            if ticks.count < 2 { return evenlySpacedTicks(count: targetTickCount) }
            
        case .sixMonth:
            // Monthly ticks
            var comps = cal.dateComponents([.year, .month], from: first)
            comps.day = 1
            guard var d = cal.date(from: comps) else { return evenlySpacedTicks(count: targetTickCount) }
            // Include the starting month
            while d <= last {
                if d >= cal.date(byAdding: .day, value: -7, to: first)! {
                    ticks.append(d)
                }
                d = cal.date(byAdding: .month, value: 1, to: d) ?? d
            }
            // Downsample if needed
            if ticks.count > 7 {
                let step = max(1, ticks.count / 6)
                ticks = ticks.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
            }
            if ticks.count < 2 { return evenlySpacedTicks(count: targetTickCount) }
            
        case .year:
            // For 1Y: show monthly ticks, evenly distributed
            let totalDays = Int(span / 86400)
            if totalDays < 90 {
                // Less than 3 months of data: use weekly/bi-weekly ticks
                let dayStep = max(7, totalDays / targetTickCount)
                var d = cal.startOfDay(for: first)
                while d <= last {
                    ticks.append(d)
                    d = cal.date(byAdding: .day, value: dayStep, to: d) ?? d
                }
            } else {
                // Generate monthly ticks
                var comps = cal.dateComponents([.year, .month], from: first)
                comps.day = 1
                guard var d = cal.date(from: comps) else { return evenlySpacedTicks(count: targetTickCount) }
                while d <= last {
                    if d >= cal.date(byAdding: .day, value: -7, to: first)! {
                        ticks.append(d)
                    }
                    d = cal.date(byAdding: .month, value: 1, to: d) ?? d
                }
                // Downsample: show every 2nd month if too many
                if ticks.count > 7 {
                    ticks = ticks.enumerated().compactMap { $0.offset % 2 == 0 ? $0.element : nil }
                }
            }
            if ticks.count < 2 { return evenlySpacedTicks(count: targetTickCount) }
            
        case .threeYear:
            // For 3Y: show quarterly ticks or monthly if data span is short
            let totalDays = Int(span / 86400)
            if totalDays < 180 {
                // Less than 6 months: use monthly ticks
                var comps = cal.dateComponents([.year, .month], from: first)
                comps.day = 1
                guard var d = cal.date(from: comps) else { return evenlySpacedTicks(count: targetTickCount) }
                while d <= last {
                    if d >= cal.date(byAdding: .day, value: -7, to: first)! {
                        ticks.append(d)
                    }
                    d = cal.date(byAdding: .month, value: 1, to: d) ?? d
                }
            } else {
                // Quarterly ticks
                var comps = cal.dateComponents([.year, .month], from: first)
                let month = comps.month ?? 1
                let quarterStartMonth = ((month - 1) / 3) * 3 + 1
                comps.month = quarterStartMonth
                comps.day = 1
                guard var d = cal.date(from: comps) else { return evenlySpacedTicks(count: targetTickCount) }
                while d <= last {
                    if d >= cal.date(byAdding: .day, value: -30, to: first)! {
                        ticks.append(d)
                    }
                    d = cal.date(byAdding: .month, value: 3, to: d) ?? d
                }
            }
            // Downsample if too many
            if ticks.count > targetTickCount + 2 {
                let step = max(1, ticks.count / targetTickCount)
                ticks = ticks.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
            }
            if ticks.count < 2 { return evenlySpacedTicks(count: targetTickCount) }
            
        case .all:
            // For ALL: adapt to data span with better granularity
            let totalDays = Int(span / 86400)
            if totalDays < 180 {
                // Less than 6 months: use monthly ticks
                var comps = cal.dateComponents([.year, .month], from: first)
                comps.day = 1
                guard var d = cal.date(from: comps) else { return evenlySpacedTicks(count: targetTickCount) }
                while d <= last {
                    if d >= cal.date(byAdding: .day, value: -7, to: first)! {
                        ticks.append(d)
                    }
                    d = cal.date(byAdding: .month, value: 1, to: d) ?? d
                }
                // Downsample if needed
                if ticks.count > 6 {
                    let step = max(1, ticks.count / 5)
                    ticks = ticks.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
                }
            } else if totalDays < 730 {
                // 6 months to 2 years: use quarterly ticks for better context
                var comps = cal.dateComponents([.year, .month], from: first)
                let month = comps.month ?? 1
                // Align to quarter start (Jan, Apr, Jul, Oct)
                let quarterStartMonth = ((month - 1) / 3) * 3 + 1
                comps.month = quarterStartMonth
                comps.day = 1
                guard var d = cal.date(from: comps) else { return evenlySpacedTicks(count: targetTickCount) }
                while d <= last {
                    if d >= cal.date(byAdding: .day, value: -30, to: first)! {
                        ticks.append(d)
                    }
                    d = cal.date(byAdding: .month, value: 3, to: d) ?? d
                }
                // Downsample if too many
                if ticks.count > 8 {
                    let step = max(1, ticks.count / 6)
                    ticks = ticks.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
                }
            } else {
                // More than 2 years: use semi-annual ticks (Jan and Jul)
                var comps = cal.dateComponents([.year, .month], from: first)
                let month = comps.month ?? 1
                // Align to semi-annual (Jan or Jul)
                comps.month = month <= 6 ? 1 : 7
                comps.day = 1
                guard var d = cal.date(from: comps) else { return evenlySpacedTicks(count: targetTickCount) }
                while d <= last {
                    if d >= cal.date(byAdding: .month, value: -3, to: first)! {
                        ticks.append(d)
                    }
                    d = cal.date(byAdding: .month, value: 6, to: d) ?? d
                }
                // Downsample if too many
                if ticks.count > targetTickCount + 2 {
                    let step = max(1, ticks.count / targetTickCount)
                    ticks = ticks.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
                }
            }
            if ticks.count < 2 { return evenlySpacedTicks(count: targetTickCount) }
        }
        
        // Filter out ticks too close to the end (last 5% of span) to prevent label clipping
        let edgeBuffer = span * 0.05
        let filteredTicks = ticks.filter { tick in
            let distanceFromEnd = last.timeIntervalSince(tick)
            return distanceFromEnd > edgeBuffer || ticks.count <= 2
        }
        
        // If filtering removed all but one, keep original
        return filteredTicks.count >= 2 ? filteredTicks : ticks
    }

    // MARK: - Unified Control Height
    private let controlHeight: CGFloat = 28
    private let controlCornerRadius: CGFloat = 8
    
    // MARK: - Chart Header (legacy — now handled by persistentChartToolbar)

    // MARK: - Chart Options Popover
    private var chartOptionsPopover: some View {
        let isDark = colorScheme == .dark
        let goldColor = DS.Colors.gold
        let bgColors: [Color] = isDark
            ? [Color(red: 0.10, green: 0.10, blue: 0.12), Color(red: 0.06, green: 0.06, blue: 0.08)]
            : [Color(red: 0.98, green: 0.97, blue: 0.95), Color(red: 0.96, green: 0.95, blue: 0.93)]
        let textSecondary: Color = isDark ? .white.opacity(0.6) : .primary.opacity(0.55)
        let cardBg: Color = isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
        let selectedBg: Color = goldColor
        
        return VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Chart Options")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(isDark ? .white : .primary)
                Spacer()
            }
            
            // Value mode segmented control
            HStack(spacing: 8) {
                ForEach(ValueMode.allCases, id: \.self) { mode in
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        valueMode = mode
                        storedValueModeRaw = mode.rawValue
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(valueMode == mode ? (isDark ? .black : .white) : (isDark ? .white.opacity(0.8) : .primary.opacity(0.7)))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(
                                Capsule()
                                    .fill(valueMode == mode ? selectedBg : cardBg)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(valueMode == mode ? goldColor.opacity(0.6) : (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Range section
            VStack(alignment: .leading, spacing: 10) {
                Text("Range")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(textSecondary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 40), spacing: 8), count: 4), spacing: 8) {
                    ForEach(TimeRange.allCases, id: \.self) { r in
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            chartVM.selectedRange = r
                            storedRangeRaw = r.rawValue
                            // Use override values for Paper Trading mode
                            let effectiveTotal = overrideTotalValue ?? portfolioVM.totalValue
                            let effectiveHistory = overrideHistory ?? portfolioVM.history
                            chartVM.loadDataImmediate(for: r, history: effectiveHistory, portfolioTotal: effectiveTotal)
                        } label: {
                            Text(r.rawValue)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                // LIGHT MODE FIX: Use dark brown text on amber gold pill for readability
                                .foregroundColor(chartVM.selectedRange == r ? (isDark ? .black : Color(red: 0.30, green: 0.22, blue: 0.02)) : (isDark ? .white.opacity(0.8) : .primary.opacity(0.7)))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(chartVM.selectedRange == r ? selectedBg : cardBg)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(chartVM.selectedRange == r ? goldColor.opacity(0.5) : (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Divider
            Rectangle()
                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                .frame(height: 1)
            
            // Haptics section
            VStack(alignment: .leading, spacing: 10) {
                Text("Haptics")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(textSecondary)
                
                VStack(spacing: 12) {
                    // Tick Cadence
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Tick Cadence")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundColor(textSecondary)
                            Spacer()
                            Text(String(format: "%.0f ms", hTickInterval * 1000))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(goldColor)
                                .monospacedDigit()
                        }
                        Slider(value: $hTickInterval, in: 0.02...0.12, step: 0.005)
                            .tint(goldColor)
                    }
                    
                    // Major Throttle
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Major Throttle")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundColor(textSecondary)
                            Spacer()
                            Text(String(format: "%.0f ms", hMajorInterval * 1000))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(goldColor)
                                .monospacedDigit()
                        }
                        Slider(value: $hMajorInterval, in: 0.12...0.60, step: 0.01)
                            .tint(goldColor)
                    }
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                // Glass background
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(colors: bgColors, startPoint: .top, endPoint: .bottom)
                    )
                
                // Top highlight for glass effect
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.8), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: isDark
                            ? [goldColor.opacity(0.25), goldColor.opacity(0.08)]
                            : [goldColor.opacity(0.3), goldColor.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Line Chart Section with Selector
    @ViewBuilder
    /// Line chart body — header is now in persistentChartToolbar
    private var lineChartBody: some View {
        VStack(spacing: 4) {
            chartContent()
            TradingViewTimeRangeBar(selectedRange: $chartVM.selectedRange) { newRange in
                storedRangeRaw = newRange.rawValue
                // Use override values for Paper Trading mode
                let effectiveTotal = overrideTotalValue ?? portfolioVM.totalValue
                let effectiveHistory = overrideHistory ?? portfolioVM.history
                chartVM.loadDataImmediate(for: newRange, history: effectiveHistory, portfolioTotal: effectiveTotal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Pie chart body — header is now in persistentChartToolbar
    private var bigPieBody: some View {
        ThemedPortfolioPieChartView(
            portfolioVM: portfolioVM,
            showLegend: .constant(false),
            allowRotation: false,  // Disabled: professional pie charts don't rotate on selection
            allowSweepOscillation: false,
            showSweepIndicator: true,
            allowHoverScrub: true,
            showSliceCallouts: false,
            showRotatingSheen: false,  // Disabled: forever-spinning sheen adds visual noise
            showIdleCenterRing: true,
            showActiveStartTick: false,  // Disabled: not needed when sweep indicator is enabled
            showSliceSeparators: false,  // Disabled: separators can cause visual artifacts
            showSideInfoPanel: false,  // Disabled for consistent width with line chart
            overrideAllocationData: overrideAllocationData,
            overrideTotalValue: overrideTotalValue,
            centerMode: .normal,
            onSelectSymbol: nil,
            onActivateSymbol: { sym in
                NotificationCenter.default.post(name: NSNotification.Name("OpenTradeForSymbol"), object: sym)
            },
            onUpdateColors: nil
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Expand to fill all available space
        .padding(.horizontal, 20) // Room for sweep indicator orb and glow effects
        .contentShape(Rectangle())
        .background(Color.clear)
        // MEMORY FIX: .drawingGroup() removed - GPU offscreen buffer savings
    }
    
    // MARK: - Pie Chart Header (legacy — now handled by persistentChartToolbar)
    
    // MARK: - Content Switcher
    // Unified height for both modes so Holdings section stays in place when switching
    private let chartCardHeight: CGFloat = 310  // Reduced from 350 for tighter layout
    
    @ViewBuilder
    private var chartContentView: some View {
        VStack(spacing: 6) {
            // Persistent toolbar — toggle buttons stay in the exact same position
            // regardless of chart mode, so switching feels seamless
            persistentChartToolbar

            // Chart content area — both views stacked in a ZStack with crossfade
            ZStack {
                lineChartBody
                    .opacity(chartMode == .line ? 1 : 0)
                    .scaleEffect(chartMode == .line ? 1 : 0.97)
                    .zIndex(chartMode == .line ? 1 : 0)
                    .allowsHitTesting(chartMode == .line)

                bigPieBody
                    .opacity(chartMode == .pie ? 1 : 0)
                    .scaleEffect(chartMode == .pie ? 1 : 0.97)
                    .zIndex(chartMode == .pie ? 1 : 0)
                    .allowsHitTesting(chartMode == .pie)
            }
            .frame(height: chartCardHeight)
        }
    }

    // MARK: - Persistent Chart Toolbar
    /// Unified toolbar that stays in place across chart mode switches.
    /// Left side crossfades between mode-specific info; right side is always the toggle.
    private var persistentChartToolbar: some View {
        let isDark = colorScheme == .dark
        let slices = overrideAllocationData ?? portfolioVM.allocationData
        let assetCount = slices.count

        let isUpRange = chartVM.rangeChangePercent >= 0

        return HStack(alignment: .center, spacing: 8) {
            // Left side — crossfades between line/pie mode info
            ZStack {
                // Line mode: change % pill + Value/ROI toggle
                HStack(spacing: 6) {
                    // Percentage pill — compact colored indicator for at-a-glance chart context
                    Text(hideBalances ? "•••%" : chartVM.formatPercent(chartVM.rangeChangePercent))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(isUpRange ? .green : .red)
                        .padding(.horizontal, 8)
                        .frame(height: controlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                                .fill((isUpRange ? Color.green : Color.red).opacity(isDark ? 0.15 : 0.10))
                        )

                    HStack(spacing: 0) {
                        ForEach(ValueMode.allCases, id: \.self) { mode in
                            Button(action: {
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    valueMode = mode
                                    storedValueModeRaw = mode.rawValue
                                }
                            }) {
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(valueMode == mode ? DS.Adaptive.textPrimary : DS.Adaptive.textTertiary)
                                    .padding(.horizontal, 10)
                                    .frame(height: controlHeight)
                                    .background(
                                        RoundedRectangle(cornerRadius: controlCornerRadius - 2, style: .continuous)
                                            .fill(valueMode == mode ? DS.Adaptive.chipBackgroundActive : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                            .fill(DS.Adaptive.chipBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                            .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                    )
                }
                .opacity(chartMode == .line ? 1 : 0)

                // Pie mode: asset count label
                HStack(spacing: 5) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)

                    Text("\(assetCount) Asset\(assetCount == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .padding(.horizontal, 10)
                .frame(height: controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                        .fill(DS.Adaptive.chipBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(chartMode == .pie ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.25), value: chartMode)

            // Right side — always visible, never moves
            HStack(spacing: 6) {
                // Settings button — keeps its frame in both modes to prevent layout shift;
                // just fades out in pie mode
                Button {
                    showChartOptions.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .frame(width: controlHeight, height: controlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                                .fill(DS.Adaptive.chipBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                                .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                        )
                }
                .buttonStyle(PremiumIconButtonStyle())
                .opacity(chartMode == .line ? 1 : 0)
                .allowsHitTesting(chartMode == .line)
                .animation(.easeInOut(duration: 0.25), value: chartMode)
                .popover(isPresented: $showChartOptions, attachmentAnchor: .point(.topTrailing), arrowEdge: .top) {
                    chartOptionsPopover
                        .presentationCompactAdaptation(.none)
                }

                // Chart mode toggle — always visible, always in same position
                if showSelector {
                    ChartModeToggle(mode: $chartMode, height: controlHeight, cornerRadius: controlCornerRadius)
                }
            }
        }
    }

    // MARK: - Card Background
    private var cardBackground: some View {
        let isDark = colorScheme == .dark
        
        // Warm brown for light mode strokes and shadows
        let warmBrown = Color(red: 0.55, green: 0.45, blue: 0.33)
        
        return ZStack {
            // Base gradient fill - adaptive for light/dark mode
            LinearGradient(
                gradient: Gradient(colors: isDark ? [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.80)
                ] : [
                    // Light mode: warm cream with subtle depth (matching DS.Adaptive.cardBackground)
                    Color(red: 1.0, green: 0.992, blue: 0.973),   // Warm cream top
                    Color(red: 0.995, green: 0.985, blue: 0.965)  // Slightly warmer bottom
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Subtle top highlight for glass effect - adaptive
            LinearGradient(
                colors: [
                    isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.7),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            
            // Inner shadow at bottom for depth
            LinearGradient(
                colors: [
                    Color.clear,
                    isDark ? Color.black.opacity(0.15) : Color.black.opacity(0.04)
                ],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: isDark ? [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.05)
                        ] : [
                            // Warm brown stroke for light mode
                            warmBrown.opacity(0.15),
                            warmBrown.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
    }

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chartContentView

            if chartMode == .line && showMetrics {
                Group {
                    if #available(iOS 16.0, *) { metricsSixGrid } else { metricsSixFallback }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: chartMode)
        .frame(maxWidth: .infinity) // Ensure consistent width regardless of content
        .padding(.vertical, 10)  // Reduced from 12
        .padding(.horizontal, 14)  // Reduced from 16
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            // CHART LOAD FIX: Load immediately on appear to avoid 0.3s delay
            // Use override values for Paper Trading mode
            let effectiveTotal = overrideTotalValue ?? portfolioVM.totalValue
            let effectiveHistory = overrideHistory ?? portfolioVM.history
            
            if let storedRange = TimeRange(rawValue: storedRangeRaw) {
                chartVM.selectedRange = storedRange
            }
            if let storedMode = ValueMode(rawValue: storedValueModeRaw) {
                valueMode = storedMode
            }
            
            // Load data IMMEDIATELY (no debounce) on first appear
            lastKnownTotal = effectiveTotal
            chartVM.loadDataImmediate(for: chartVM.selectedRange, history: effectiveHistory, portfolioTotal: effectiveTotal)
            showCrosshair = false
            selectedValue = nil
            #if os(iOS)
            ChartHaptics.shared.minTickInterval = hTickInterval
            ChartHaptics.shared.minMajorInterval = hMajorInterval
            #endif
        }
        .onChange(of: portfolioVM.totalValue) { _, newValue in
            // STARTUP FIX v25: Allow significant corrections during startup
            let significantCorrection = newValue > 0  // Any positive value during startup should be allowed
            if isInGlobalStartupPhase() && !significantCorrection { return }
            // PERFORMANCE FIX: Skip during scroll to prevent "multiple updates per frame"
            guard !ScrollStateManager.shared.isScrolling || significantCorrection else { return }
            
            // Skip if using override (Paper Trading mode handles its own updates)
            guard overrideTotalValue == nil else { return }
            
            // Only reload if value changed by more than threshold (0.5%) to avoid visual jitter
            DispatchQueue.main.async {
                let changePercent = lastKnownTotal > 0 ? abs(newValue - lastKnownTotal) / lastKnownTotal : 1.0
                guard changePercent >= updateThreshold else { return }
                lastKnownTotal = newValue
                chartVM.loadData(for: chartVM.selectedRange, history: portfolioVM.history, portfolioTotal: newValue)
            }
        }
        // PERFORMANCE FIX: Observe history count instead of whole array to prevent
        // "tried to update multiple times per frame" warning
        .onChange(of: portfolioVM.history.count) { _, newCount in
            // PERFORMANCE FIX: Skip during scroll to prevent jank
            guard !ScrollStateManager.shared.isScrolling else { return }
            
            // Skip if using override (Paper Trading mode handles its own updates)
            guard overrideHistory == nil else { return }
            
            // PERFORMANCE FIX: Throttle to prevent rapid updates
            let now = CACurrentMediaTime()
            guard now - lastHistoryUpdateTime >= historyUpdateMinInterval else { return }
            lastHistoryUpdateTime = now
            
            // Only reload if history actually changed meaningfully
            let currentCount = chartVM.dataPoints.count
            // Reload if count changed significantly or if this is initial load
            guard currentCount == 0 || abs(newCount - currentCount) > 0 else { return }
            chartVM.loadData(for: chartVM.selectedRange, history: portfolioVM.history, portfolioTotal: portfolioVM.totalValue)
        }
        .onChange(of: overrideTotalValue) { _, newOverrideTotal in
            // STARTUP FIX v25: Allow significant corrections during startup
            let significantCorrection = newOverrideTotal != nil && newOverrideTotal! > 0
            if isInGlobalStartupPhase() && !significantCorrection { return }
            // PERFORMANCE FIX: Skip during scroll to prevent "multiple updates per frame"
            guard !ScrollStateManager.shared.isScrolling || significantCorrection else { return }
            
            // Handle Paper Trading mode total value changes
            guard let newTotal = newOverrideTotal else { return }
            
            DispatchQueue.main.async {
                // Only reload if value changed by more than threshold to avoid jitter
                let changePercent = lastKnownTotal > 0 ? abs(newTotal - lastKnownTotal) / lastKnownTotal : 1.0
                guard changePercent >= updateThreshold else { return }
                lastKnownTotal = newTotal
                let effectiveHistory = overrideHistory ?? portfolioVM.history
                chartVM.loadData(for: chartVM.selectedRange, history: effectiveHistory, portfolioTotal: newTotal)
            }
        }
        // PERFORMANCE FIX: Observe override history count instead of whole array to prevent
        // "tried to update multiple times per frame" warning
        .onChange(of: overrideHistory?.count) { _, newCount in
            // Handle Paper Trading mode history changes
            guard let newHistory = overrideHistory, newCount != nil else { return }
            
            // PERFORMANCE FIX: Throttle to prevent rapid updates
            let now = CACurrentMediaTime()
            guard now - lastHistoryUpdateTime >= historyUpdateMinInterval else { return }
            lastHistoryUpdateTime = now
            
            let effectiveTotal = overrideTotalValue ?? portfolioVM.totalValue
            chartVM.loadData(for: chartVM.selectedRange, history: newHistory, portfolioTotal: effectiveTotal)
        }
        .onChange(of: chartVM.selectedRange) { _, newRange in
            DispatchQueue.main.async { storedRangeRaw = newRange.rawValue }
        }
        .onChange(of: hTickInterval) { _, new in
            #if os(iOS)
            DispatchQueue.main.async { ChartHaptics.shared.minTickInterval = new }
            #endif
        }
        .onChange(of: hMajorInterval) { _, new in
            #if os(iOS)
            DispatchQueue.main.async { ChartHaptics.shared.minMajorInterval = new }
            #endif
        }
    }

    // MARK: - Chart Content
    @ViewBuilder
    private func chartContent() -> some View {
        let rawPoints = chartVM.dataPoints
        let firstRaw = rawPoints.first?.value ?? 0

        // Transform for ROI mode (percent since range start)
        let transformed: [PortfolioDataPoint] = {
            guard valueMode == .roi, firstRaw != 0 else { return rawPoints }
            return rawPoints.map { PortfolioDataPoint(date: $0.date, value: (($0.value / firstRaw) - 1) * 100) }
        }()

        // Simple downsampling to keep rendering smooth on long ranges
        let plotPoints: [PortfolioDataPoint] = {
            let maxCount = 400
            guard transformed.count > maxCount else { return transformed }
            let strideBy = max(2, transformed.count / maxCount)
            return transformed.enumerated().compactMap { idx, p in idx % strideBy == 0 ? p : nil }
        }()

        if plotPoints.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    // LIGHT MODE FIX: Adaptive empty state background
                    .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.03))
                Text("No data yet")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .frame(height: 180)
            .padding(.horizontal, 12)
        } else {
            // Use rangeChangePercent for consistent color with header pill
            let isUp = chartVM.rangeChangePercent >= 0
            let lineColor: Color = isUp ? .green : .red
            let minV = plotPoints.map(\.value).min() ?? 0
            let maxV = plotPoints.map(\.value).max() ?? 0
            let padding = max(1, (maxV - minV) * 0.08)

            // Outlier-aware domain using percentiles to prevent spikes from flattening the trend
            let sortedVals = plotPoints.map(\.value).sorted()
            let pLow = percentile(sortedVals, 0.02)
            let pHigh = percentile(sortedVals, 0.98)
            let domainMin = min(minV, pLow)
            let domainMax = max(maxV, pHigh)
            let yLower = domainMin - padding

            let areaBaseline = (valueMode == .roi) ? 0.0 : yLower

            let yUpper = domainMax + padding

            let showZeroBaseline = (valueMode == .roi)
            let xTickDates = xAxisTickDates(for: chartVM.selectedRange, points: plotPoints)
            // SAFETY: Use optional binding instead of force unwraps
            if let firstPoint = plotPoints.first, let lastPoint = plotPoints.last {
                let firstDate = firstPoint.date
                let lastDate = lastPoint.date

                Chart {
                areaLayer(plotPoints, color: lineColor, baseline: areaBaseline)
                lineLayer(plotPoints, color: lineColor)
                extremaLayer(points: plotPoints, minV: minV, maxV: maxV)
                if showZeroBaseline { zeroBaselineLayer() }
                
                // "Now" indicator line - subtle dashed line at current time
                // Only show when now is within the visible date range
                let now = Date()
                if now >= firstDate && now <= lastDate {
                    RuleMark(x: .value("Now", now))
                        .foregroundStyle(Color.yellow.opacity(0.22))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                // Crosshair marks (tooltip is rendered via overlay for better positioning)
                if showCrosshair, let sv = selectedValue {
                    // Vertical crosshair line (dashed for professional look)
                    RuleMark(x: .value("Selected Date", sv.date))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))

                    // Horizontal crosshair line at value level
                    RuleMark(y: .value("Selected Value", sv.value))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))

                    // Crosshair point with outer glow
                    PointMark(
                        x: .value("Date", sv.date),
                        y: .value("Value", sv.value)
                    )
                    .symbolSize(50)
                    .foregroundStyle(lineColor.opacity(0.3))
                    
                    PointMark(
                        x: .value("Date", sv.date),
                        y: .value("Value", sv.value)
                    )
                    .symbolSize(25)
                    .foregroundStyle(lineColor)
                    // NOTE: Tooltip is now rendered in chartOverlay for proper edge clamping
                } else if let last = plotPoints.last {
                    // Last point marker (badge is rendered via overlay for proper edge clamping)
                    PointMark(x: .value("Date", last.date), y: .value("Value", last.value))
                        .symbolSize(0) // Hidden - pulsing dot and badge rendered in overlay
                        .foregroundStyle(Color.clear)
                }
            }
            .chartXScale(domain: firstDate...lastDate)
            .chartXScale(range: .plotDimension(padding: 28))  // Extra padding to prevent label clipping at edges
            .chartXAxis {
                let isDark = colorScheme == .dark
                if !xTickDates.isEmpty {
                    AxisMarks(values: xTickDates) { value in
                        // Professional dashed grid lines (TradingView/Bloomberg style)
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                        AxisTick(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                        if let d = value.as(Date.self) {
                            AxisValueLabel {
                                Text(dateLabel(for: chartVM.selectedRange, date: d))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                } else {
                    AxisMarks(values: .automatic(desiredCount: axisDesiredCount(for: chartVM.selectedRange))) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                        AxisTick(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                        if let d = value.as(Date.self) {
                            AxisValueLabel {
                                Text(dateLabel(for: chartVM.selectedRange, date: d))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                let isDark = colorScheme == .dark
                // Professional Y-axis with refined grid lines (TradingView/Bloomberg style)
                AxisMarks(position: .leading) { value in
                    if let v = value.as(Double.self) {
                        AxisValueLabel {
                            if valueMode == .roi {
                                Text(chartVM.formatPercent(v, includePlus: true, fractionDigits: 0))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            } else {
                                Text(abbreviatedCurrency(v))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                    AxisTick(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                }
            }
            .chartYScale(domain: yLower...yUpper)
            .chartYScale(range: .plotDimension(padding: 20))  // Increased padding for better edge spacing
            .chartPlotStyle { plotArea in
                let isDark = colorScheme == .dark
                plotArea
                    .background(
                        ZStack {
                            // Base subtle gradient
                            LinearGradient(
                                colors: isDark
                                    ? [Color.white.opacity(0.04), Color.clear]
                                    : [Color.black.opacity(0.02), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            
                            // Top highlight for glass effect
                            LinearGradient(
                                colors: [
                                    isDark ? Color.white.opacity(0.03) : Color.white.opacity(0.4),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                            
                            // Bottom shadow for depth
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    isDark ? Color.black.opacity(0.08) : Color.black.opacity(0.02)
                                ],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        }
                    )
                    .cornerRadius(10)
                    .clipped()
            }
            // MEMORY FIX: .drawingGroup() removed - GPU offscreen buffer savings
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let baselineValue: Double = {
                        if valueMode == .roi { return 0.0 }
                        return plotPoints.last?.value ?? (chartVM.dataPoints.last?.value ?? 0.0)
                    }()

                    ZStack {
                        // Measure plot area for tooltip positioning
                        Color.clear
                            .onAppear {
                                if let frameAnchor = proxy.plotFrame {
                                    plotAreaFrame = geo[frameAnchor]
                                }
                            }
                            .onChange(of: geo.size) { _, _ in
                                if let frameAnchor = proxy.plotFrame {
                                    plotAreaFrame = geo[frameAnchor]
                                }
                            }
                        
                        // Gesture handling layer
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                LongPressGesture(minimumDuration: 0.18)
                                    .onEnded { _ in
                                        scrubActive = true
                                        showCrosshair = true
                                        #if os(iOS)
                                        ChartHaptics.shared.begin()
                                        #endif
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { drag in
                                        guard scrubActive else { return }
                                        if let frameAnchor = proxy.plotFrame {
                                            let plotFrame = geo[frameAnchor]
                                            // Clamp xPos to plot bounds so edge touches still select first/last data points
                                            let rawX = drag.location.x - plotFrame.origin.x
                                            let xPos = min(max(rawX, 0), plotFrame.width)
                                            if let date: Date = proxy.value(atX: xPos),
                                               let closest = findClosest(date: date, in: plotPoints),
                                               let idx = plotPoints.firstIndex(where: { $0.id == closest.id }) {

                                                // Selection tick when index changes
                                                if lastSelectedIndex != idx {
                                                    #if os(iOS)
                                                    ChartHaptics.shared.tickIfNeeded()
                                                    #endif
                                                    lastSelectedIndex = idx
                                                }

                                                selectedValue = closest

                                                // Zero-crossing vs current baseline (ROI uses y=0)
                                                let isAbove = closest.value >= baselineValue
                                                if let prev = lastAboveBaseline, prev != isAbove {
                                                    #if os(iOS)
                                                    ChartHaptics.shared.majorIfNeeded(intensity: 0.9)
                                                    #endif
                                                }
                                                lastAboveBaseline = isAbove

                                                // Gridline bumps when crossing x-axis tick segments
                                                let ticks = xTickDates
                                                if !ticks.isEmpty {
                                                    // segment index: latest tick <= date
                                                    var seg = 0
                                                    for i in 0..<(ticks.count) {
                                                        if ticks[i] <= date { seg = i } else { break }
                                                    }
                                                    if lastGridSegmentIndex != seg {
                                                        #if os(iOS)
                                                        ChartHaptics.shared.majorIfNeeded(intensity: 0.7)
                                                        #endif
                                                        lastGridSegmentIndex = seg
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        selectedValue = nil
                                        showCrosshair = false
                                        scrubActive = false
                                        lastSelectedIndex = nil
                                        lastGridSegmentIndex = nil
                                        lastAboveBaseline = nil
                                        #if os(iOS)
                                        ChartHaptics.shared.end()
                                        #endif
                                    }
                            )
                        
                        // MARK: - Floating Crosshair Tooltip (with edge clamping)
                        // Rendered in overlay for proper positioning that doesn't clip at edges
                        if showCrosshair, let sv = selectedValue,
                           let frameAnchor = proxy.plotFrame,
                           let xPos = proxy.position(forX: sv.date),
                           let yPos = proxy.position(forY: sv.value) {
                            let plotFrame = geo[frameAnchor]
                            let origin = plotFrame.origin
                            let baseX = origin.x + xPos
                            let baseY = origin.y + yPos
                            
                            // Tooltip dimensions (wider to accommodate detailed date)
                            let tooltipWidth: CGFloat = 160
                            let tooltipHeight: CGFloat = 54
                            
                            // Calculate clamped position to keep tooltip within plot bounds
                            let plotLeftEdge = origin.x
                            let plotRightEdge = origin.x + plotFrame.width
                            let leftBound = plotLeftEdge + tooltipWidth / 2 + 8
                            let rightBound = plotRightEdge - tooltipWidth / 2 - 8
                            
                            // Clamp X to stay within bounds
                            let clampedX = min(max(baseX, leftBound), rightBound)
                            // Position tooltip above the crosshair point, with minimum Y
                            let tooltipY = max(origin.y + tooltipHeight / 2 + 8, baseY - tooltipHeight / 2 - 20)
                            
                            let isDark = colorScheme == .dark
                            let tooltipBgColors: [Color] = isDark
                                ? [Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.95),
                                   Color(red: 0.06, green: 0.06, blue: 0.08).opacity(0.95)]
                                : [Color.white.opacity(0.98),
                                   Color(red: 0.96, green: 0.96, blue: 0.97).opacity(0.98)]
                            let tooltipTextColor: Color = isDark ? .white.opacity(0.75) : .primary.opacity(0.65)
                            
                            VStack(spacing: 4) {
                                // Value with gold styling
                                Text(hideBalances ? "•••••" : (valueMode == .roi ? chartVM.formatPercent(sv.value) : chartVM.formatCurrency(sv.value)))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(DS.Colors.gold)
                                // Date label (detailed for tooltip)
                                Text(tooltipDateLabel(for: chartVM.selectedRange, date: sv.date))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(tooltipTextColor)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: tooltipBgColors,
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [DS.Colors.gold.opacity(0.5), DS.Colors.gold.opacity(0.2)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .position(x: clampedX, y: tooltipY)
                            .allowsHitTesting(false)
                        }
                        
                        // MARK: - Live Price Indicator (refined, professional styling)
                        // Only show when crosshair is not active
                        if !showCrosshair,
                           let lastPoint = plotPoints.last,
                           let frameAnchor = proxy.plotFrame,
                           let xPos = proxy.position(forX: lastPoint.date),
                           let yPos = proxy.position(forY: lastPoint.value) {
                            let plotFrame = geo[frameAnchor]
                            let origin = plotFrame.origin
                            let dotX = origin.x + xPos
                            let dotY = origin.y + yPos
                            
                            // Badge dimensions - more compact
                            let badgeOffset: CGFloat = 8
                            
                            // Determine if badge should go left or right of the dot
                            let plotRightEdge = origin.x + plotFrame.width
                            let plotLeftEdge = origin.x
                            
                            let isDark = colorScheme == .dark
                            
                            // Use line color for the indicator (matches chart line)
                            let indicatorColor = lineColor
                            
                            // Compact badge background
                            let badgeBgColors: [Color] = isDark
                                ? [Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.92),
                                   Color(red: 0.04, green: 0.04, blue: 0.06).opacity(0.92)]
                                : [Color.white.opacity(0.96),
                                   Color(red: 0.96, green: 0.96, blue: 0.98).opacity(0.96)]
                            
                            // Calculate badge width dynamically based on content
                            let displayText = hideBalances ? "•••••" : (valueMode == .roi ? chartVM.formatPercent(lastPoint.value) : chartVM.formatCurrency(lastPoint.value))
                            let estimatedWidth: CGFloat = CGFloat(displayText.count) * 8 + 20  // Rough estimate
                            let badgeWidth = min(estimatedWidth, 100)
                            
                            // If dot is close to right edge, put badge on left; otherwise on right
                            let useLeftPosition = (dotX + badgeWidth + badgeOffset) > plotRightEdge
                            
                            // Calculate badge X position with clamping
                            let badgeX: CGFloat = {
                                if useLeftPosition {
                                    // Badge to the left of dot
                                    let x = dotX - badgeWidth / 2 - badgeOffset
                                    return max(plotLeftEdge + badgeWidth / 2 + 4, x)
                                } else {
                                    // Badge to the right of dot
                                    let x = dotX + badgeWidth / 2 + badgeOffset
                                    return min(plotRightEdge - badgeWidth / 2 - 4, x)
                                }
                            }()
                            
                            // Subtle connecting line from badge to dot
                            Path { path in
                                let lineStartX = useLeftPosition ? badgeX + badgeWidth / 2 - 2 : badgeX - badgeWidth / 2 + 2
                                path.move(to: CGPoint(x: lineStartX, y: dotY))
                                path.addLine(to: CGPoint(x: dotX, y: dotY))
                            }
                            .stroke(
                                indicatorColor.opacity(0.3),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                            )
                            .allowsHitTesting(false)
                            
                            // Price badge with cleaner styling
                            Text(displayText)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(indicatorColor)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: badgeBgColors,
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(
                                            indicatorColor.opacity(isDark ? 0.35 : 0.25),
                                            lineWidth: 0.6
                                        )
                                )
                                .position(x: badgeX, y: dotY)
                                .allowsHitTesting(false)
                            
                            // Refined pulsing live dot - matches chart line color
                            ZStack {
                                // Outer pulse ring
                                Circle()
                                    .stroke(indicatorColor.opacity(pulse ? 0.2 : 0.4), lineWidth: 1.5)
                                    .frame(width: pulse ? 16 : 10, height: pulse ? 16 : 10)
                                
                                // Inner solid dot
                                Circle()
                                    .fill(indicatorColor)
                                    .frame(width: 6, height: 6)
                            }
                            .position(x: dotX, y: dotY)
                            .onAppear {
                                DispatchQueue.main.async {
                                    // MEMORY FIX v19: Disable repeating pulse animation.
                                    pulse = false
                                }
                            }
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
            .frame(height: 200)
            .accessibilityLabel("Portfolio performance chart")
            .accessibilityHint(valueMode == .roi ? "Shows percentage return over selected range" : "Shows portfolio value over selected range")
            .padding(.horizontal, 6)
            } // Close if let firstPoint, lastPoint
        }
    }

    // MARK: - Chart Content Helpers
    @ChartContentBuilder
    private func lineLayer(_ points: [PortfolioDataPoint], color: Color) -> some ChartContent {
        ForEach(points) { dp in
            LineMark(
                x: .value("Date", dp.date),
                y: .value("Value", dp.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            // LIGHT MODE FIX: Reduce shadow intensity to avoid muddy glow on light backgrounds
        }
    }

    @ChartContentBuilder
    private func areaLayer(_ points: [PortfolioDataPoint], color: Color, baseline: Double) -> some ChartContent {
        ForEach(points) { dp in
            AreaMark(
                x: .value("Date", dp.date),
                yStart: .value("Base", baseline),
                yEnd: .value("Value", dp.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                // Professional 5-stop gradient matching other charts (HomeLineChart, EnhancedCryptoChartView)
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: color.opacity(0.42), location: 0.0),   // Top - vibrant
                        .init(color: color.opacity(0.28), location: 0.25), // Upper mid
                        .init(color: color.opacity(0.12), location: 0.55), // Lower mid
                        .init(color: color.opacity(0.04), location: 0.80), // Near bottom
                        .init(color: .clear, location: 1.0)                // Bottom - clear
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    @ChartContentBuilder
    private func extremaLayer(points: [PortfolioDataPoint], minV: Double, maxV: Double) -> some ChartContent {
        let isDark = colorScheme == .dark
        if minV < maxV {
            // LIGHT MODE FIX: Use adaptive rule mark and annotation colors
            RuleMark(y: .value("Min", minV)).foregroundStyle(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            RuleMark(y: .value("Max", maxV)).foregroundStyle(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            if let minPoint = points.min(by: { $0.value < $1.value }) {
                PointMark(x: .value("Date", minPoint.date), y: .value("Value", minPoint.value))
                    .foregroundStyle(isDark ? Color.white : Color.black.opacity(0.7))
                    .annotation(position: .bottomLeading) {
                        Text("L")
                            .font(.caption2)
                            .foregroundColor(isDark ? .white : .white)
                            .padding(4)
                            .background(isDark ? Color.black.opacity(0.7) : Color.black.opacity(0.55))
                            .clipShape(Capsule())
                    }
            }
            if let maxPoint = points.max(by: { $0.value < $1.value }) {
                PointMark(x: .value("Date", maxPoint.date), y: .value("Value", maxPoint.value))
                    .foregroundStyle(isDark ? Color.white : Color.black.opacity(0.7))
                    .annotation(position: .topTrailing) {
                        Text("H")
                            .font(.caption2.bold())
                            .foregroundColor(isDark ? .white : .white)
                            .padding(4)
                            .background(isDark ? Color.black.opacity(0.7) : Color.black.opacity(0.55))
                            .clipShape(Capsule())
                    }
            }
        }
    }

    @ChartContentBuilder
    private func zeroBaselineLayer() -> some ChartContent {
        // LIGHT MODE FIX: Adaptive baseline color
        let isDark = colorScheme == .dark
        RuleMark(y: .value("Zero", 0))
            .foregroundStyle(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    // MARK: - Grid-based 6-Metric Layout (iOS 16+)
    @available(iOS 16.0, *)
    private var metricsSixGrid: some View {
        Grid(horizontalSpacing: 20, verticalSpacing: 12) {
            GridRow {
                metricCell(title: "Total P/L",
                           value: chartVM.formatCurrency(chartVM.totalPL),
                           isPositive: chartVM.totalPL >= 0)
                metricCell(title: "Largest Holding",
                           value: "\(chartVM.largestHoldingName) (\(String(format: "%.0f", chartVM.largestHoldingPercent))%)",
                           isPositive: true,
                           textColor: .white)
                metricCell(title: "Overall ROI",
                           value: "\(String(format: "%.1f", chartVM.roiPercent))%",
                           isPositive: chartVM.roiPercent >= 0)
            }
            GridRow {
                metricCell(title: "24H P/L",
                           value: chartVM.formatCurrency(chartVM.twentyFourHrPL),
                           isPositive: chartVM.twentyFourHrPL >= 0)
                metricCell(title: "Realized P/L",
                           value: chartVM.formatCurrency(chartVM.realizedPL),
                           isPositive: chartVM.realizedPL >= 0)
                metricCell(title: "Unrealized P/L",
                           value: chartVM.formatCurrency(chartVM.unrealizedPL),
                           isPositive: chartVM.unrealizedPL >= 0)
            }
        }
    }
    
    // MARK: - Fallback 6-Metric Layout for < iOS 16
    private var metricsSixFallback: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                metricCell(
                    title: "Total P/L",
                    value: chartVM.formatCurrency(chartVM.totalPL),
                    isPositive: chartVM.totalPL >= 0
                )
                metricCell(
                    title: "Largest Holding",
                    value: "\(chartVM.largestHoldingName) (\(String(format: "%.0f", chartVM.largestHoldingPercent))%)",
                    isPositive: true,
                    textColor: .white
                )
                metricCell(
                    title: "Overall ROI",
                    value: "\(String(format: "%.1f", chartVM.roiPercent))%",
                    isPositive: chartVM.roiPercent >= 0
                )
            }
            HStack(spacing: 20) {
                metricCell(
                    title: "24H P/L",
                    value: chartVM.formatCurrency(chartVM.twentyFourHrPL),
                    isPositive: chartVM.twentyFourHrPL >= 0
                )
                metricCell(
                    title: "Realized P/L",
                    value: chartVM.formatCurrency(chartVM.realizedPL),
                    isPositive: chartVM.realizedPL >= 0
                )
                metricCell(
                    title: "Unrealized P/L",
                    value: chartVM.formatCurrency(chartVM.unrealizedPL),
                    isPositive: chartVM.unrealizedPL >= 0
                )
            }
        }
    }
    
    // MARK: - Metric Cell
    private func metricCell(title: String,
                            value: String,
                            isPositive: Bool = true,
                            textColor: Color = .green) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            Text(value)
                .font(.callout)
                // LIGHT MODE FIX: "white" text color was invisible in light mode
                // Use adaptive primary text for neutral metrics (like Largest Holding)
                .foregroundColor(isPositive ? (textColor == .white ? DS.Adaptive.textPrimary : textColor) : .red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Crosshair Helper
    // SAFETY FIX: Removed force unwraps, added proper optional handling
    // PERFORMANCE: Uses binary search for O(log n) instead of O(n) linear scan
    private func findClosest(date: Date, in points: [PortfolioDataPoint]) -> PortfolioDataPoint? {
        guard !points.isEmpty else { return nil }
        let sorted = points.sorted { $0.date < $1.date }
        
        // Safe optional access
        guard let first = sorted.first, let last = sorted.last else { return nil }
        
        // Edge cases - date is outside data range
        if date <= first.date { return first }
        if date >= last.date { return last }
        
        // Binary search for O(log n) performance
        var low = 0
        var high = sorted.count - 1
        
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid].date < date {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        // Check neighbors to find closest
        let candidates = [
            low > 0 ? sorted[low - 1] : nil,
            low < sorted.count ? sorted[low] : nil
        ].compactMap { $0 }
        
        return candidates.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    // MARK: - Date Label Helpers (Professional quality matching trading charts)
    
    /// Returns whether to use 24-hour clock based on user's locale
    private var uses24hClock: Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !template.contains("a")
    }
    
    // Cached date formatters for performance
    private static let dfHour12 = { () -> DateFormatter in
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "ha"  // Compact: "6AM" instead of "6 AM"
        df.amSymbol = "A"  // Shorter AM/PM
        df.pmSymbol = "P"
        return df
    }()
    
    private static let dfHour24 = { () -> DateFormatter in
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "HH"  // Just hours for 24h: "18" instead of "18:00"
        return df
    }()
    
    private static let dfDayShort = { () -> DateFormatter in
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "EEE"
        return df
    }()
    
    private static let dfMonthDay = { () -> DateFormatter in
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "MMM d"
        return df
    }()
    
    private static let dfMonth = { () -> DateFormatter in
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "MMM"
        return df
    }()
    
    private static let dfMonthShortYear = { () -> DateFormatter in
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "MMM ''yy"
        return df
    }()
    
    private static let dfYear = { () -> DateFormatter in
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "yyyy"
        return df
    }()
    
    /// Professional date label for chart axis (matches trading charts)
    private func dateLabel(for range: TimeRange, date: Date) -> String {
        let cal = Calendar.current
        
        switch range {
        case .day:
            // Clean time format for 1-day view
            if uses24hClock {
                return Self.dfHour24.string(from: date)
            } else {
                // More compact 12h format
                let hour = cal.component(.hour, from: date)
                if hour == 0 || hour == 12 {
                    return hour == 0 ? "12a" : "12p"
                }
                let displayHour = hour > 12 ? hour - 12 : hour
                return "\(displayHour)\(hour < 12 ? "a" : "p")"
            }
            
        case .week:
            // Day name for 1-week view (Mon, Tue, Wed)
            return Self.dfDayShort.string(from: date)
            
        case .month:
            // Month + day for 1-month view (Jan 15)
            return Self.dfMonthDay.string(from: date)
            
        case .threeMonth:
            // Month name only for cleaner 3-month view (Nov, Dec, Jan)
            return Self.dfMonth.string(from: date)
            
        case .sixMonth:
            // Month only for 6-month view (Jan, Feb, Mar)
            return Self.dfMonth.string(from: date)
            
        case .year:
            // Month with smart year for 1-year view
            // Show year only on January for context
            let month = cal.component(.month, from: date)
            if month == 1 {
                return Self.dfMonthShortYear.string(from: date)
            }
            return Self.dfMonth.string(from: date)
            
        case .threeYear:
            // Quarter label for 3-year view (Q1 '24, Q2 '24)
            let month = cal.component(.month, from: date)
            let year = cal.component(.year, from: date)
            let quarter = ((month - 1) / 3) + 1
            let shortYear = year % 100
            return "Q\(quarter) '\(String(format: "%02d", shortYear))"
            
        case .all:
            // Smart labeling for all-time view based on month
            let month = cal.component(.month, from: date)
            let year = cal.component(.year, from: date)
            let shortYear = year % 100
            
            // For January: show just year
            if month == 1 {
                return "'\(String(format: "%02d", shortYear))"
            }
            // For July: show "Jul 'YY" for mid-year context
            if month == 7 {
                return "Jul '\(String(format: "%02d", shortYear))"
            }
            // For quarters (Apr, Oct): show month + year
            if month == 4 || month == 10 {
                let monthStr = Self.dfMonth.string(from: date)
                return "\(monthStr) '\(String(format: "%02d", shortYear))"
            }
            // Default: month abbreviation
            return Self.dfMonth.string(from: date)
        }
    }
    
    /// Tooltip date label (more detailed than axis labels)
    private func tooltipDateLabel(for range: TimeRange, date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale.current
        
        switch range {
        case .day:
            df.dateFormat = uses24hClock ? "EEE, MMM d • HH:mm" : "EEE, MMM d • h:mm a"
        case .week:
            df.dateFormat = uses24hClock ? "EEE, MMM d • HH:mm" : "EEE, MMM d • h:mm a"
        case .month, .threeMonth, .sixMonth:
            df.dateFormat = "EEE, MMM d, yyyy"
        case .year, .threeYear, .all:
            df.dateFormat = "MMM d, yyyy"
        }
        return df.string(from: date)
    }

    // MARK: - Abbreviated Currency Formatter
    private func abbreviatedCurrency(_ value: Double) -> String {
        return MarketFormat.largeCurrency(value)
    }
}

// MARK: - Symbol Color Helper
private func colorForSymbol(_ symbol: String) -> Color {
    switch symbol {
    case "BTC": return .blue
    case "ETH": return .green
    case "SOL": return .orange
    default:    return .gray
    }
}


