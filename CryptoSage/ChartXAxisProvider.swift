//  ChartXAxisProvider.swift
//  Generates deterministic tick dates and labels for chart x-axis

import Foundation
import SwiftUI

struct ChartXAxisProvider {
    let interval: ChartInterval
    let domain: ClosedRange<Date>
    let plotWidth: CGFloat
    let uses24hClock: Bool

    // MARK: - Public API
    func ticks() -> [Date] {
        switch interval {
        case .live:
            return ticksForMinutes(allowed: [1, 2, 5], fallback: .dailyMidnight)
        case .oneMin:
            return ticksForMinutes(allowed: [1, 2, 5, 10, 15, 30], fallback: .dailyMidnight)
        case .fiveMin:
            return ticksForMinutes(allowed: [5, 10, 15, 30, 60], fallback: .dailyMidnight)

        case .fifteenMin:
            return ticksFor15m()

        case .thirtyMin:
            return ticksForIntraday(stepHours: 1, fallback: .dailyMidnight)

        case .oneHour:
            return ticksForIntraday(stepHours: 1, fallback: .dailyMidnight)

        case .fourHour:
            return ticksForIntraday(stepHours: 4, fallback: .dailyMidnight)

        case .oneWeek:
            return dailyMidnights()

        case .oneDay:
            return monthlyTicks()

        case .oneMonth:
            return weeklyTicks()

        case .threeMonth, .oneYear:
            return monthlyTicks()

        case .threeYear, .all:
            return yearlyTicks()
        }
    }

    func label(for date: Date) -> String {
        switch interval {
        case .live, .oneMin, .fiveMin, .fifteenMin:
            return formatIntraday(date)
        case .thirtyMin, .oneHour:
            // Short spans: time-of-day; long spans: day numbers (TradingView-like)
            return isShortSpanForIntraday() ? ChartDateFormatters.timeOfDayLabel(date) : ChartDateFormatters.dayNumberLabel(date)
        case .fourHour:
            // 4H keeps month/day on long spans
            return isShortSpanForIntraday() ? ChartDateFormatters.timeOfDayLabel(date) : ChartDateFormatters.monthDayLabel(date)
        case .oneWeek, .oneMonth:
            return ChartDateFormatters.monthDayLabel(date)
        case .oneDay:
            return ChartDateFormatters.monthLabel(date)
        case .threeMonth, .oneYear:
            return interval == .oneYear ? ChartDateFormatters.monthShortYearLabel(date) : ChartDateFormatters.monthLabel(date)
        case .threeYear, .all:
            return ChartDateFormatters.yearLabel(date)
        }
    }

    // MARK: - Helpers
    private enum FallbackMode { case dailyMidnight }

    private func dynamicCount() -> Int {
        // Estimate label width for time-of-day or short date
        let labelWidth: CGFloat = {
            switch interval {
            case .live, .oneMin, .fiveMin, .fifteenMin:
                return uses24hClock ? 38 : 44
            case .thirtyMin, .oneHour:
                // time strings like "3 PM" / "15:00"
                return uses24hClock ? 38 : 44
            case .fourHour:
                return uses24hClock ? 40 : 48
            case .oneWeek, .oneMonth:
                return 34
            case .oneDay:
                return 30
            case .threeMonth, .oneYear:
                return 32
            case .threeYear, .all:
                return 28
            }
        }()
        let spacing = labelWidth + 22
        let width = max(120, (plotWidth > 0 ? plotWidth : UIScreen.main.bounds.width - 32))
        let count = Int(width / spacing)
        return max(2, min(10, count))
    }

    private func evenlySpaced(count: Int) -> [Date] {
        let start = domain.lowerBound
        let end = domain.upperBound
        let span = end.timeIntervalSince(start)
        guard span > 0, count >= 2 else { return [] }
        let step = span / Double(count - 1)
        return (0..<count).map { i in start.addingTimeInterval(Double(i) * step) }
    }

    private func ticksForMinutes(allowed: [Int], fallback: FallbackMode) -> [Date] {
        // For sub-hour frames (live/1m/5m): choose a minute step that fits dynamicCount, align to next boundary
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        if !isShortSpanForIntraday() {
            // If someone zooms absurdly far out, fall back to daily midnights
            return dailyMidnights()
        }
        let cal = Calendar.current
        let maxCount = dynamicCount()
        let minutesSpan = max(1, Int(ceil(span / 60)))
        let approx = max(1, Int(ceil(Double(minutesSpan) / Double(maxCount))))
        let step = allowed.first(where: { $0 >= approx }) ?? allowed.last ?? 1

        // Align to the next multiple of `step` minutes at or after lowerBound
        let midnight = cal.startOfDay(for: domain.lowerBound)
        let comps = cal.dateComponents([.hour, .minute, .second], from: domain.lowerBound)
        var minutesFromMidnight = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if (comps.second ?? 0) > 0 { minutesFromMidnight += 1 }
        let rounded = ((minutesFromMidnight + step - 1) / step) * step
        var start = cal.date(byAdding: .minute, value: rounded, to: midnight) ?? domain.lowerBound
        while start < domain.lowerBound { start = cal.date(byAdding: .minute, value: step, to: start)! }

        var out: [Date] = []
        var cursor = start
        while cursor <= domain.upperBound {
            out.append(cursor)
            cursor = cal.date(byAdding: .minute, value: step, to: cursor)!
        }

        // Safety downsample if needed
        let maxC = dynamicCount()
        if out.count > maxC {
            let stepIdx = max(1, out.count / maxC)
            return out.enumerated().compactMap { idx, d in idx % stepIdx == 0 ? d : nil }
        }
        return out
    }

    private func formatIntraday(_ date: Date) -> String {
        // For 15m and below we already mix hour/day depending on span
        if isShortSpanForIntraday() {
            return ChartDateFormatters.timeOfDayLabel(date)
        } else {
            return ChartDateFormatters.monthDayLabel(date)
        }
    }

    private func isShortSpanForIntraday() -> Bool {
        // Consider <= 2 days as short for intraday labels
        return domain.upperBound.timeIntervalSince(domain.lowerBound) <= 2 * 86_400
    }

    private func ticksFor15m() -> [Date] {
        // If visible > 1 day -> daily midnights; else -> top-of-hour ticks
        let cal = Calendar.current
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        if span > 86_400 {
            return dailyMidnights()
        } else {
            var first = cal.nextDate(after: domain.lowerBound,
                                     matching: DateComponents(minute: 0, second: 0),
                                     matchingPolicy: .nextTime)!
            if first < domain.lowerBound { first = cal.date(byAdding: .hour, value: 1, to: first)! }
            var hourly: [Date] = []
            var cursor = first
            while cursor <= domain.upperBound {
                hourly.append(cursor)
                cursor = cal.date(byAdding: .hour, value: 1, to: cursor)!
            }
            let maxCount = dynamicCount()
            if hourly.count > maxCount {
                let hoursSpan = max(1, Int(ceil(span / 3600)))
                let approx = max(1, Int(round(Double(hoursSpan) / Double(maxCount))))
                let allowed = [1, 2, 3, 4, 6, 12, 24]
                let chosen = allowed.first(where: { $0 >= approx }) ?? allowed.last!
                return ticksForIntraday(stepHours: chosen, fallback: .dailyMidnight)
            }
            return hourly
        }
    }

    private func ticksForIntraday(stepHours: Int, fallback: FallbackMode) -> [Date] {
        let cal = Calendar.current
        if !isShortSpanForIntraday() {
            switch fallback {
            case .dailyMidnight: return dailyMidnights()
            }
        }
        // Align to stepHours boundaries (e.g., 4H -> 00,04,08,...) from midnight, next boundary >= lowerBound
        let midnight = cal.startOfDay(for: domain.lowerBound)
        let hour = cal.component(.hour, from: domain.lowerBound)
        let minute = cal.component(.minute, from: domain.lowerBound)
        let second = cal.component(.second, from: domain.lowerBound)
        var k = hour / stepHours
        if minute > 0 || second > 0 { k += 1 }
        var start = cal.date(byAdding: .hour, value: k * stepHours, to: midnight)!
        // Ensure start within domain
        while start < domain.lowerBound { start = cal.date(byAdding: .hour, value: stepHours, to: start)! }
        var out: [Date] = []
        var cursor = start
        while cursor <= domain.upperBound {
            out.append(cursor)
            cursor = cal.date(byAdding: .hour, value: stepHours, to: cursor)!
        }
        return downsample(out)
    }

    private func dailyMidnights() -> [Date] {
        let cal = Calendar.current
        var out: [Date] = []
        var start = cal.startOfDay(for: domain.lowerBound)
        if start < domain.lowerBound { start = cal.date(byAdding: .day, value: 1, to: start)! }
        var cursor = start
        while cursor <= domain.upperBound {
            out.append(cursor)
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return downsample(out)
    }

    private func weeklyTicks() -> [Date] {
        let cal = Calendar.current
        var out: [Date] = []
        let firstWeekday = cal.firstWeekday
        var start = cal.nextDate(after: domain.lowerBound,
                                 matching: DateComponents(hour: 0, minute: 0, second: 0, weekday: firstWeekday),
                                 matchingPolicy: .nextTime)
        if start == nil {
            start = cal.startOfDay(for: domain.lowerBound)
            if start! < domain.lowerBound { start = cal.date(byAdding: .day, value: 1, to: start!) }
        }
        var cursor = start!
        while cursor <= domain.upperBound {
            out.append(cursor)
            cursor = cal.date(byAdding: .day, value: 7, to: cursor)!
        }
        return downsample(out)
    }

    private func monthlyTicks() -> [Date] {
        let cal = Calendar.current
        var out: [Date] = []
        var start = cal.dateInterval(of: .month, for: domain.lowerBound)?.start ?? domain.lowerBound
        if start < domain.lowerBound { start = cal.date(byAdding: .month, value: 1, to: start)! }
        var cursor = start
        while cursor <= domain.upperBound {
            out.append(cursor)
            cursor = cal.date(byAdding: .month, value: 1, to: cursor)!
        }
        return downsample(out)
    }

    private func yearlyTicks() -> [Date] {
        let cal = Calendar.current
        var out: [Date] = []
        var start = cal.dateInterval(of: .year, for: domain.lowerBound)?.start ?? domain.lowerBound
        if start < domain.lowerBound { start = cal.date(byAdding: .year, value: 1, to: start)! }
        var cursor = start
        while cursor <= domain.upperBound {
            out.append(cursor)
            cursor = cal.date(byAdding: .year, value: 1, to: cursor)!
        }
        return downsample(out)
    }

    private func downsample(_ dates: [Date]) -> [Date] {
        let maxCount = dynamicCount()
        guard dates.count > maxCount, maxCount > 1 else { return dates }
        let step = max(1, dates.count / maxCount)
        return dates.enumerated().compactMap { idx, d in idx % step == 0 ? d : nil }
    }
}

