//  ChartXAxisProvider.swift
//  Generates deterministic tick dates and labels for chart x-axis
//  Updated to be data-driven and work with actual data bounds

import Foundation
import SwiftUI

struct ChartXAxisProvider {
    let interval: ChartInterval
    let domain: ClosedRange<Date>
    let plotWidth: CGFloat
    let uses24hClock: Bool
    
    /// Returns true if the domain spans multiple calendar days
    private var spansDays: Bool {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: domain.lowerBound)
        let endDay = cal.startOfDay(for: domain.upperBound)
        return startDay != endDay
    }
    
    /// Returns true if the given date is at midnight (00:00:00)
    /// Used for showing date markers at day transitions instead of time labels
    private func isMidnight(_ date: Date) -> Bool {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        return hour == 0 && minute == 0
    }

    // MARK: - Public API
    func ticks() -> [Date] {
        // Guard against empty or invalid domain
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0 else { return [] }
        
        // SAFETY NET: Validate that domain span is appropriate for the interval.
        // This prevents garbled X-axis when data/domain doesn't match the interval,
        // e.g., during timeframe switches or when cached data has unexpected ranges.
        // With the displayInterval fix, this should rarely trigger, but it's a safeguard.
        let minExpectedSpan: TimeInterval = {
            switch interval {
            case .threeYear: return 365 * 86_400      // At least 1 year for 3Y
            case .all: return 365 * 86_400            // At least 1 year for ALL
            case .oneYear: return 180 * 86_400        // At least 6 months for 1Y
            case .sixMonth: return 90 * 86_400        // At least 3 months for 6M
            case .threeMonth: return 30 * 86_400      // At least 30 days for 3M
            case .oneMonth: return 14 * 86_400        // At least 2 weeks for 1M
            case .oneWeek: return 3 * 86_400          // At least 3 days for 1W
            case .oneHour: return 1.5 * 86_400        // At least 1.5 days for 1H
            case .fourHour: return 5 * 86_400         // At least 5 days for 4H
            case .oneDay: return 12 * 3_600           // At least 12 hours for 1D
            case .thirtyMin: return 12 * 3_600        // At least 12 hours for 30m
            case .fifteenMin: return 6 * 3_600        // At least 6 hours for 15m
            case .fiveMin: return 2 * 3_600           // At least 2 hours for 5m
            case .oneMin: return 15 * 60              // At least 15 minutes for 1m
            case .live: return 0                      // No minimum for live
            }
        }()
        
        // Also validate domain isn't WAY too large for a short timeframe
        // e.g., a 7-day domain with 1-minute interval means data is mismatched
        let maxExpectedSpan: TimeInterval = {
            switch interval {
            case .live: return 600                    // Max 10 minutes for live
            case .oneMin: return 3 * 3_600            // Max 3 hours for 1m
            case .fiveMin: return 12 * 3_600          // Max 12 hours for 5m
            case .fifteenMin: return 48 * 3_600       // Max 48 hours for 15m
            case .thirtyMin: return 72 * 3_600        // Max 72 hours for 30m
            default: return 0                         // No maximum for longer timeframes
            }
        }()
        
        // If domain span is way too small for the interval, don't generate ticks
        // This prevents mismatched ticks/labels when data hasn't loaded yet
        if minExpectedSpan > 0 && span < minExpectedSpan * 0.3 {
            return []
        }
        
        // If domain span is way too large for a short interval, don't generate ticks
        // This prevents minute/hour ticks being generated for multi-day domains
        if maxExpectedSpan > 0 && span > maxExpectedSpan * 3.0 {
            return []
        }
        
        // Generate ticks based on interval type
        // IMPORTANT: Tick type must match label type!
        // - If showing DATES: use day/month/year ticks
        // - If showing TIMES: use hour/minute ticks
        let result: [Date] = {
            switch interval {
            case .live:
                // Live view: use second-level ticks for short windows to avoid
                // all labels showing the same minute (e.g., "8:44 PM" x5).
                // For longer windows (2+ min), use wider-spaced second ticks to prevent
                // overlap. The live window grows from ~15s to 5 minutes (300s).
                // Using 1-minute ticks produces only 2-5 labels for the 2-5min window,
                // but they use full "12:08 PM" format which is dense.
                // Instead, use second-level ticks with adaptive spacing throughout.
                let stepSec: Int
                if span < 60 {
                    stepSec = max(10, Int(span) / max(2, dynamicCount()))
                } else if span < 180 {
                    stepSec = 30  // Every 30 seconds for 1-3 min window
                } else {
                    stepSec = 60  // Every 60 seconds for 3-5 min window
                }
                return generateSecondTicks(stepSeconds: stepSec)
            case .oneMin:
                // ~1.5 hour view: time labels, minute ticks
                return generateMinuteTicks(stepMinutes: 15)
            case .fiveMin:
                // ~8 hour view: time labels, hour ticks
                return generateHourTicks(stepHours: 1)
            case .fifteenMin:
                // ~30 hour view: always use hour ticks for proper time labels
                // Day ticks only produce 1-2 midnight boundaries which is insufficient
                return generateHourTicks(stepHours: 4)
            case .thirtyMin:
                // ~36 hour view: always use hour ticks for proper time labels
                // Day ticks only produce 1-2 midnight boundaries which is insufficient
                return generateHourTicks(stepHours: 6)
            case .oneHour:
                // ~3 day view: always shows dates, use day ticks
                return generateDayTicks(stepDays: 1)
            case .fourHour:
                // ~10 day view: date labels, day ticks
                return generateDayTicks(stepDays: 2)
            case .oneDay:
                // 24-hour view: always use hour ticks for proper time labels
                // Day ticks only produce 1 midnight boundary which is insufficient
                return generateHourTicks(stepHours: 4)
            case .oneWeek:
                // 7-day view: date labels, day ticks
                return generateDayTicks(stepDays: 1)
            case .oneMonth:
                // 30-day view: date labels, day ticks
                return generateDayTicks(stepDays: 5)
            case .threeMonth:
                // 90-day view: date labels, day ticks
                return generateDayTicks(stepDays: 14)
            case .sixMonth:
                // 6-month view: month labels, month ticks
                return generateMonthTicks()
            case .oneYear:
                // 1-year view: month labels, month ticks
                return generateMonthTicks()
            case .threeYear:
                // 3-year view: quarter labels, quarter ticks
                return generateQuarterTicks()
            case .all:
                // All-time view: year labels, year ticks
                return generateYearTicks()
            }
        }()
        
        // FIX: Don't fall back to evenly spaced for long timeframes
        // Evenly spaced dates don't align with quarter/year labels and cause garbled text
        if result.isEmpty {
            // For long timeframes, return empty if no proper ticks found
            // The chart will render without X-axis labels until data loads
            switch interval {
            case .threeYear, .all, .oneYear, .sixMonth:
                return []  // Don't generate random ticks for these
            default:
                return evenlySpaced(count: dynamicCount())
            }
        }
        
        return result
    }

    func label(for date: Date) -> String {
        // Industry standard (Coinbase, Binance, TradingView mobile):
        // - Single day view: Show TIMES only (12 PM, 4 PM, 8 PM)
        // - Multi-day view: Show DATES only (Jan 29, Jan 30, Jan 31)
        // NEVER mix dates and times on the same axis - it's confusing
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        switch interval {
        case .live:
            // Live updates: always show minute:second precision since the live window
            // spans at most 5 minutes. Full "h:mm:ss a" format is too wide and causes
            // overlap, so use a compact "h:mm:ss" or just "m:ss" style.
            // For windows >= 3 min, show just minutes since ticks land on full minutes.
            if span >= 180 {
                return ChartDateFormatters.timeOfDayLabelCompact(date)
            }
            return ChartDateFormatters.timeWithSecondsLabel(date)
        case .oneMin, .fiveMin:
            // Short timeframes - typically single day, show times
            // If spans days (rare), still show times for consistency
            return ChartDateFormatters.timeOfDayLabelCompact(date)
        case .fifteenMin, .thirtyMin:
            // Medium timeframes (~30-36 hours): smart intraday labels
            // Shows date at midnight ("Feb 6") and time elsewhere ("4 PM", "8 PM")
            // This prevents confusing repeated "12 AM" labels spanning multiple days
            return ChartDateFormatters.smartIntradayLabel(date)
        case .oneHour:
            // 3-day view - always spans multiple days, show dates only
            return ChartDateFormatters.monthDayLabel(date)  // "Jan 29", "Jan 30", "Jan 31"
        case .fourHour:
            // 10.5-day view - show dates only
            return ChartDateFormatters.monthDayLabel(date)
        case .oneDay:
            // 24-hour view: smart intraday labels
            // Shows date at midnight ("Feb 6") and time elsewhere ("4 AM", "8 AM", "12 PM")
            // This provides clear day-boundary context when the view crosses midnight
            return ChartDateFormatters.smartIntradayLabel(date)
        case .oneWeek:
            // 7-day view - show dates
            return ChartDateFormatters.monthDayLabel(date)
        case .oneMonth:
            // 30-day view - show dates
            return ChartDateFormatters.monthDayLabel(date)
        case .threeMonth:
            // 90-day view - show dates
            return ChartDateFormatters.monthDayLabel(date)
        case .sixMonth:
            // 6-month view - show month with year on January
            return ChartDateFormatters.monthLabelSmartYear(date)
        case .oneYear:
            // 1-year view - show month with year on January
            return ChartDateFormatters.monthLabelSmartYear(date)
        case .threeYear:
            // 3-year view - show quarters
            return ChartDateFormatters.quarterLabel(date)
        case .all:
            // All-time view - show years
            return ChartDateFormatters.yearLabel(date)
        }
    }

    // MARK: - Tick Count
    private func dynamicCount() -> Int {
        // Label widths measured for actual rendered text
        // Industry standard: times only OR dates only (never mixed)
        // Time labels: "8 AM" (~45px 12h) or "08:00" (~42px 24h)
        // Date labels: "Jan 30" (~52px)
        let labelWidth: CGFloat = {
            switch interval {
            case .live:
                // Live windows: short windows (< 3 min) show seconds ("8:44:15 PM" / "20:44:15")
                // Longer windows (3-5 min) show compact time ("12:08" / "8 PM")
                let liveSpan = domain.upperBound.timeIntervalSince(domain.lowerBound)
                if liveSpan < 180 {
                    return uses24hClock ? 52 : 72  // "20:44:15" or "8:44:15 PM"
                }
                return uses24hClock ? 42 : 48  // "12:08" or "8:04 PM"
            case .oneMin, .fiveMin:
                // Time-only labels
                return uses24hClock ? 42 : 55  // "8 AM" or "08:00"
            case .fifteenMin, .thirtyMin:
                // Smart intraday labels: mostly time ("4 PM") with date at midnight ("Feb 6")
                // Use the wider date label width to ensure no overlap at midnight markers
                return 55
            case .oneHour:
                // Multi-day view - dates only
                return 52  // "Jan 30"
            case .fourHour:
                return 52  // "Jan 23" - date only
            case .oneDay:
                // Smart intraday labels: mostly time ("4 PM") with date at midnight ("Feb 6")
                // Use the wider date label width to ensure no overlap at midnight markers
                return 55
            case .oneWeek:
                return 52  // "Jan 13", "Jan 15"
            case .oneMonth, .threeMonth:
                return 52  // "Jan 5", "Jan 20"
            case .sixMonth, .oneYear:
                return 36  // "Jan", "Apr" (short months)
            case .threeYear:
                return 38  // "Q1 '24" - compact quarter labels
            case .all:
                return 34  // "2024" - year labels are short
            }
        }()
        // Minimum spacing between labels to prevent any overlap
        let minSpacing: CGFloat = 12
        let spacing = labelWidth + minSpacing
        let width = max(120, plotWidth > 0 ? plotWidth : UIScreen.main.bounds.width - 32)
        let count = Int(width / spacing)
        // Allow more labels for longer timeframes to show proper date distribution
        let maxLabels: Int = {
            switch interval {
            case .oneMin, .fiveMin:
                return 6  // Short timeframes need good time labels
            case .fifteenMin, .thirtyMin:
                return 8  // 30-36 hour spans need more labels for better coverage
            case .oneHour:
                return 8  // 3-day span needs more labels for clarity
            case .fourHour:
                return 10 // 10.5-day span needs more labels
            case .oneDay:
                return 6  // 24-hour view
            case .oneWeek:
                return 7  // 7-day span needs ~7 labels (daily)
            case .oneMonth:
                return 6  // Monthly view
            case .threeMonth:
                return 6  // 3-month view
            case .sixMonth:
                return 7  // Show ~7 labels for 6M (every month)
            case .oneYear:
                return 8  // Show ~8 months for 1Y
            case .threeYear:
                return 12  // Show up to 12 quarter labels for 3Y (full coverage)
            case .all:
                return 10  // Show up to 10 year labels for all-time view
            default:
                return 6
            }
        }()
        return max(2, min(maxLabels, count))
    }

    // MARK: - Evenly Spaced Fallback
    private func evenlySpaced(count: Int) -> [Date] {
        let start = domain.lowerBound
        let end = domain.upperBound
        let span = end.timeIntervalSince(start)
        guard span > 0, count >= 2 else { return [] }
        let step = span / Double(count - 1)
        return (0..<count).map { i in start.addingTimeInterval(Double(i) * step) }
    }

    // MARK: - Second-Based Ticks (for live mode short windows)
    private func generateSecondTicks(stepSeconds: Int) -> [Date] {
        let maxCount = dynamicCount()
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        
        // Calculate appropriate step based on span and desired count
        let totalSeconds = max(1, Int(span))
        var step = max(5, stepSeconds)  // Minimum 5-second intervals
        while totalSeconds / step > maxCount && step < 60 {
            step = step * 2
        }
        
        // Align ticks to clean second boundaries (multiples of step)
        let startInterval = domain.lowerBound.timeIntervalSince1970
        let alignedStart = ceil(startInterval / Double(step)) * Double(step)
        var cursor = Date(timeIntervalSince1970: alignedStart)
        
        // Ensure cursor is within domain
        while cursor < domain.lowerBound {
            cursor = cursor.addingTimeInterval(Double(step))
        }
        
        var out: [Date] = []
        while cursor <= domain.upperBound && out.count < maxCount + 2 {
            out.append(cursor)
            cursor = cursor.addingTimeInterval(Double(step))
        }
        
        return downsample(out)
    }

    // MARK: - Minute-Based Ticks
    private func generateMinuteTicks(stepMinutes: Int) -> [Date] {
        let cal = Calendar.current
        let maxCount = dynamicCount()
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        
        // Calculate appropriate step based on span and desired count
        let totalMinutes = max(1, Int(span / 60))
        var step = stepMinutes
        while totalMinutes / step > maxCount && step < 60 {
            step = step * 2
        }
        
        // Find first aligned tick AT or AFTER domain start (round UP)
        // This prevents labels from being cut off at the left edge
        let midnight = cal.startOfDay(for: domain.lowerBound)
        let comps = cal.dateComponents([.hour, .minute, .second], from: domain.lowerBound)
        let minutesFromMidnight = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let seconds = comps.second ?? 0
        // Round UP: if we're past an aligned minute boundary, go to the next one
        let alignedMinutes = seconds > 0 
            ? ((minutesFromMidnight / step) + 1) * step 
            : ((minutesFromMidnight + step - 1) / step) * step
        
        guard var cursor = cal.date(byAdding: .minute, value: alignedMinutes, to: midnight) else {
            return evenlySpaced(count: maxCount)
        }
        
        // Ensure cursor is within domain
        while cursor < domain.lowerBound {
            guard let next = cal.date(byAdding: .minute, value: step, to: cursor) else { break }
            cursor = next
        }
        
        var out: [Date] = []
        
        // Generate aligned ticks within domain
        // Professional charts only show aligned tick values (e.g., :00, :15, :30, :45)
        // Never show raw domain boundaries like "2:35 AM"
        while cursor <= domain.upperBound && out.count < maxCount + 2 {
            out.append(cursor)
            guard let next = cal.date(byAdding: .minute, value: step, to: cursor) else { break }
            cursor = next
        }
        
        return downsample(out)
    }

    // MARK: - Hour-Based Ticks
    private func generateHourTicks(stepHours: Int) -> [Date] {
        let cal = Calendar.current
        let maxCount = dynamicCount()
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        
        // Calculate appropriate step based on span and desired count
        let totalHours = max(1, Int(span / 3600))
        var step = stepHours
        while totalHours / step > maxCount && step < 24 {
            step = step * 2
        }
        
        // Find first aligned tick AT or AFTER domain start (round UP)
        // This prevents labels from being cut off at the left edge
        let midnight = cal.startOfDay(for: domain.lowerBound)
        let hour = cal.component(.hour, from: domain.lowerBound)
        let minute = cal.component(.minute, from: domain.lowerBound)
        // Round UP: if we're past an aligned hour, go to the next one
        let alignedHour = minute > 0 ? ((hour / step) + 1) * step : ((hour + step - 1) / step) * step
        
        guard var cursor = cal.date(byAdding: .hour, value: alignedHour, to: midnight) else {
            return evenlySpaced(count: maxCount)
        }
        
        // If cursor went to next day (alignedHour >= 24), it's already correct
        // Ensure cursor is within domain
        while cursor < domain.lowerBound {
            guard let next = cal.date(byAdding: .hour, value: step, to: cursor) else { break }
            cursor = next
        }
        
        var out: [Date] = []
        
        // Generate aligned ticks within domain
        // Professional charts only show aligned tick values (e.g., 8:00 AM, 12:00 PM)
        // Never show raw domain boundaries like "8:35 AM"
        while cursor <= domain.upperBound && out.count < maxCount + 2 {
            out.append(cursor)
            guard let next = cal.date(byAdding: .hour, value: step, to: cursor) else { break }
            cursor = next
        }
        
        return downsample(out)
    }

    // MARK: - Day-Based Ticks
    private func generateDayTicks(stepDays: Int) -> [Date] {
        let cal = Calendar.current
        let maxCount = dynamicCount()
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        
        // Calculate appropriate step
        let totalDays = max(1, Int(span / 86400))
        var step = stepDays
        while totalDays / step > maxCount && step < 30 {
            step = step + stepDays
        }
        
        // Start from midnight of the lower bound day
        var cursor = cal.startOfDay(for: domain.lowerBound)
        
        // If cursor (midnight) is before domain start, advance to next day's midnight
        // This prevents labels from being cut off at the left edge
        if cursor < domain.lowerBound {
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else {
                return evenlySpaced(count: maxCount)
            }
            cursor = next
        }
        
        var out: [Date] = []
        
        // Generate aligned ticks within domain
        // Professional charts only show aligned tick values (midnight boundaries)
        // Never show raw domain boundaries
        while cursor <= domain.upperBound && out.count < maxCount + 2 {
            out.append(cursor)
            guard let next = cal.date(byAdding: .day, value: step, to: cursor) else { break }
            cursor = next
        }
        
        return downsample(out)
    }

    // MARK: - Month-Based Ticks
    private func generateMonthTicks() -> [Date] {
        let cal = Calendar.current
        let maxCount = dynamicCount()
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        
        // Calculate total months in the domain
        let totalMonths = max(1, Int(span / (30.44 * 86400)))
        
        // Determine month step based on span length
        // For 1Y (~12 months), step by 2 months to show ~6 labels (Jan, Mar, May, Jul, Sep, Nov)
        let monthStep: Int = {
            if totalMonths > 18 { return 4 }      // >1.5 years: every 4 months
            if totalMonths > 9 { return 2 }       // 9-18 months: every 2 months
            return 1                               // <9 months: every month
        }()
        
        guard var cursor = cal.dateInterval(of: .month, for: domain.lowerBound)?.start else {
            return evenlySpaced(count: maxCount)
        }
        
        // Move to next month if cursor is before domain
        if cursor < domain.lowerBound {
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else {
                return evenlySpaced(count: maxCount)
            }
            cursor = next
        }
        
        // Align to step boundaries for cleaner labels (e.g., Jan, Mar, May instead of Feb, Apr, Jun)
        if monthStep > 1 {
            let month = cal.component(.month, from: cursor)
            // Align to months 1, 3, 5, 7, 9, 11 for step=2 or 1, 5, 9 for step=4
            let alignedMonth = ((month - 1 + monthStep - 1) / monthStep) * monthStep + 1
            let year = cal.component(.year, from: cursor)
            let adjustedYear = alignedMonth > 12 ? year + 1 : year
            let adjustedMonth = alignedMonth > 12 ? alignedMonth - 12 : alignedMonth
            if let aligned = cal.date(from: DateComponents(year: adjustedYear, month: adjustedMonth, day: 1)) {
                cursor = aligned
            }
        }
        
        var out: [Date] = []
        while cursor <= domain.upperBound && out.count < maxCount + 2 {
            out.append(cursor)
            guard let next = cal.date(byAdding: .month, value: monthStep, to: cursor) else { break }
            cursor = next
        }
        
        return downsample(out)
    }

    // MARK: - Quarter-Based Ticks
    private func generateQuarterTicks() -> [Date] {
        let cal = Calendar.current
        let maxCount = dynamicCount()
        
        // Find the START of the quarter containing domain.lowerBound
        let comps = cal.dateComponents([.year, .month], from: domain.lowerBound)
        let month = comps.month ?? 1
        let year = comps.year ?? 2020
        
        // Quarter start months: Q1=1, Q2=4, Q3=7, Q4=10
        // Find which quarter we're in and get its start month
        let quarterIndex = (month - 1) / 3  // 0, 1, 2, or 3
        let quarterStartMonth = quarterIndex * 3 + 1  // 1, 4, 7, or 10
        
        guard var cursor = cal.date(from: DateComponents(year: year, month: quarterStartMonth, day: 1)) else {
            return evenlySpaced(count: maxCount)
        }
        
        // Generate ALL quarters within domain - we'll downsample later if needed
        var out: [Date] = []
        while cursor <= domain.upperBound && out.count < 20 {  // Max 20 quarters (5 years)
            // Only add if within or after domain start
            if cursor >= cal.startOfDay(for: domain.lowerBound) || out.isEmpty {
                out.append(cursor)
            }
            guard let next = cal.date(byAdding: .month, value: 3, to: cursor) else { break }
            cursor = next
        }
        
        // Also include the quarter we're currently IN (might be at the end)
        if let last = out.last, let finalQuarter = cal.date(byAdding: .month, value: 3, to: last),
           finalQuarter <= domain.upperBound {
            out.append(finalQuarter)
        }
        
        // For 3Y view, we want to show quarters evenly spaced
        // If we have too many, take every Nth to get a good distribution
        if out.count > maxCount {
            let step = max(1, out.count / maxCount)
            var sampled: [Date] = []
            for (i, date) in out.enumerated() {
                if i % step == 0 {
                    sampled.append(date)
                }
            }
            // Always include the last quarter if it's close to the end
            if let lastSampled = sampled.last, let lastOriginal = out.last,
               lastSampled != lastOriginal {
                sampled.append(lastOriginal)
            }
            return sampled
        }
        
        return out
    }

    // MARK: - Year-Based Ticks
    private func generateYearTicks() -> [Date] {
        let cal = Calendar.current
        let maxCount = dynamicCount()
        
        // Get the years for start and end of domain
        let startYear = cal.component(.year, from: domain.lowerBound)
        let endYear = cal.component(.year, from: domain.upperBound)
        let totalYears = endYear - startYear + 1
        
        // Generate ALL years in the range first
        var allYears: [Date] = []
        for year in startYear...endYear {
            if let date = cal.date(from: DateComponents(year: year, month: 1, day: 1)) {
                allYears.append(date)
            }
        }
        
        // If we can show all years, do it
        if allYears.count <= maxCount {
            return allYears
        }
        
        // Otherwise, need to skip some years
        // Calculate step to show evenly distributed years
        let step: Int = {
            if totalYears > 15 { return 5 }      // Very long spans: every 5 years
            if totalYears > 10 { return 2 }      // Long spans: every 2 years
            return 1
        }()
        
        // Align to nice boundaries (e.g., 2020, 2022, 2024 instead of 2019, 2021, 2023)
        let alignedStart = (startYear / step) * step
        var out: [Date] = []
        
        var year = alignedStart
        while year <= endYear && out.count < maxCount + 2 {
            if year >= startYear {  // Only include if within domain
                if let date = cal.date(from: DateComponents(year: year, month: 1, day: 1)) {
                    out.append(date)
                }
            }
            year += step
        }
        
        // Always include the final year if it's not already included and we have room
        if let lastYear = allYears.last, !out.contains(where: { cal.component(.year, from: $0) == endYear }) {
            if out.count < maxCount {
                out.append(lastYear)
            }
        }
        
        return out
    }

    // MARK: - Downsample
    private func downsample(_ dates: [Date]) -> [Date] {
        let maxCount = dynamicCount()
        guard dates.count > maxCount, maxCount > 1 else { return filterTooClose(dates) }
        let step = max(1, (dates.count + maxCount - 1) / maxCount)
        let sampled = dates.enumerated().compactMap { idx, d in idx % step == 0 ? d : nil }
        return filterTooClose(sampled)
    }
    
    // MARK: - Filter Too-Close Labels
    // Removes labels that would overlap based on minimum pixel spacing
    private func filterTooClose(_ dates: [Date]) -> [Date] {
        guard dates.count > 1, plotWidth > 0 else { return dates }
        
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0 else { return dates }
        
        // Minimum pixels between label centers to prevent overlap
        // Industry standard: times only OR dates only (never mixed)
        let minPixelSpacing: CGFloat = {
            switch interval {
            case .oneMin, .fiveMin:
                // Time-only labels
                return uses24hClock ? 48 : 50
            case .fifteenMin, .thirtyMin:
                // Smart intraday labels with occasional date at midnight
                return 52
            case .oneHour:
                // Date-only labels for multi-day view
                return 48
            case .fourHour, .oneWeek, .oneMonth, .threeMonth:
                return 45  // Date-only labels like "Jan 22"
            case .oneDay:
                // Smart intraday labels with occasional date at midnight
                return 52
            case .sixMonth, .oneYear:
                return 36  // Short month labels like "Jan", "Mar"
            case .threeYear:
                return 35  // Quarter labels like "Q1 '24" - compact
            case .all:
                return 32  // Year labels like "2024" - compact
            default:
                return uses24hClock ? 48 : 50
            }
        }()
        // Convert to minimum time spacing
        let minTimeSpacing = (Double(minPixelSpacing) / Double(plotWidth)) * span
        
        var result: [Date] = []
        var lastDate: Date? = nil
        
        for date in dates {
            if let last = lastDate {
                let spacing = date.timeIntervalSince(last)
                if spacing >= minTimeSpacing {
                    result.append(date)
                    lastDate = date
                }
            } else {
                result.append(date)
                lastDate = date
            }
        }
        
        return result
    }
}

