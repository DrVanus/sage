//  ChartDateFormatters.swift
//  Centralized date formatters and helpers for chart axes and crosshair
//  Respects the user's selected language for month/day names.

import Foundation

struct ChartDateFormatters {
    // MARK: - Factory
    
    /// Creates a DateFormatter with the user's selected language locale.
    /// Uses LocaleManager.current for display-facing formatters (month names, day names).
    private static func make(_ format: String) -> DateFormatter {
        let df = DateFormatter()
        df.locale = LocaleManager.current
        df.timeZone = .current
        df.dateFormat = format
        return df
    }
    
    /// Rebuilds all formatters when the language changes.
    /// Called by LocaleManager when the user selects a new language.
    static func rebuildFormatters() {
        let locale = LocaleManager.current
        let allFormatters = [
            dfHour, dfHourMinute, dfHourMinuteSecond, dfHour24, dfHourMinute24, dfHourMinuteSecond24,
            dfDayNumber, dfMonthDay, dfMonth, dfMonthShortYear, dfYear,
            dfCrossIntraday12, dfCrossIntraday24, dfCrossLong,
            dfDateTimeCompact12, dfDateTimeCompact24,
            dfShortDateTime, dfFullDate
        ]
        for df in allFormatters {
            df.locale = locale
        }
        relativeTime.locale = locale
    }

    // MARK: - Formatters
    static let dfHour = make("h a")
    static let dfHourMinute = make("h:mm a")
    static let dfHourMinuteSecond = make("h:mm:ss a")
    static let dfHour24 = make("HH")
    static let dfHourMinute24 = make("HH:mm")
    static let dfHourMinuteSecond24 = make("HH:mm:ss")

    static let dfDayNumber = make("d")
    static let dfMonthDay = make("MMM d")
    static let dfMonth = make("MMM")
    static let dfMonthShortYear = make("MMM ''yy")
    static let dfYear = make("yyyy")

    static let dfCrossIntraday12 = make("EEE, MMM d • h:mm a")
    static let dfCrossIntraday24 = make("EEE, MMM d • HH:mm")
    static let dfCrossLong = make("EEE, MMM d, yyyy")
    
    // Compact date-time formatters for multi-day views (1H timeframe)
    static let dfDateTimeCompact12 = make("M/d ha")       // "1/23 6PM"
    static let dfDateTimeCompact24 = make("M/d HH:mm")    // "1/23 18:00"

    // MARK: - Environment
    static var uses24hClock: Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !template.contains("a")
    }

    // MARK: - Labels
    /// Time of day label - always includes minutes for consistency (like professional charts)
    static func timeOfDayLabel(_ date: Date) -> String {
        // Always show HH:mm or h:mm a for consistent label widths
        if uses24hClock {
            return dfHourMinute24.string(from: date)
        } else {
            return dfHourMinute.string(from: date)
        }
    }
    
    /// Time label with seconds precision - used for live charts with short windows (< 2 minutes)
    /// where minute-precision labels would show the same time for all ticks.
    /// Shows "8:44:15 PM" (12h) or "20:44:15" (24h)
    static func timeWithSecondsLabel(_ date: Date) -> String {
        if uses24hClock {
            return dfHourMinuteSecond24.string(from: date)
        } else {
            return dfHourMinuteSecond.string(from: date)
        }
    }
    
    /// Compact time label - shows just hour when minute is 0 (for dense tick layouts)
    static func timeOfDayLabelCompact(_ date: Date) -> String {
        let minute = Calendar.current.component(.minute, from: date)
        if uses24hClock {
            return minute == 0 ? dfHour24.string(from: date) : dfHourMinute24.string(from: date)
        } else {
            return minute == 0 ? dfHour.string(from: date) : dfHourMinute.string(from: date)
        }
    }

    static func dayNumberLabel(_ date: Date) -> String { dfDayNumber.string(from: date) }
    static func monthDayLabel(_ date: Date) -> String { dfMonthDay.string(from: date) }
    static func monthLabel(_ date: Date) -> String { dfMonth.string(from: date) }
    static func monthShortYearLabel(_ date: Date) -> String { dfMonthShortYear.string(from: date) }
    static func yearLabel(_ date: Date) -> String { dfYear.string(from: date) }
    
    /// Smart month label that only shows year on January (for 1Y timeframe)
    /// Returns "Jan '26" for January, "Feb", "Mar", etc. for other months
    static func monthLabelSmartYear(_ date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        if month == 1 {
            // January - show with year
            return dfMonthShortYear.string(from: date)
        } else {
            // Other months - just show month name
            return dfMonth.string(from: date)
        }
    }
    
    /// Quarter label formatter for 3Y timeframe (e.g., "Q1 '25", "Q2 '25")
    static func quarterLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let year = cal.component(.year, from: date)
        let quarter = ((month - 1) / 3) + 1
        let shortYear = year % 100
        return "Q\(quarter) '\(String(format: "%02d", shortYear))"
    }
    
    /// Semi-monthly label for 3M timeframe (shows "MMM d" format)
    static func semiMonthlyLabel(_ date: Date) -> String {
        return dfMonthDay.string(from: date)
    }
    
    /// Compact date-time label for multi-day intraday views (e.g., 1H timeframe spanning 2 days)
    /// Returns "1/23 6PM" (12h) or "1/23 18:00" (24h) for consistent date+time context
    static func dateTimeCompactLabel(_ date: Date) -> String {
        if uses24hClock {
            return dfDateTimeCompact24.string(from: date)
        } else {
            return dfDateTimeCompact12.string(from: date)
        }
    }
    
    /// Smart intraday label for multi-day hour views (15m, 30m, 1D timeframes)
    /// Shows date ("Feb 6") at midnight boundaries and time ("4 PM") at all other hours.
    /// This matches TradingView/Binance behavior and prevents confusing repeated "12 AM" labels.
    static func smartIntradayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        
        // At midnight (00:00): show the date for day-boundary context
        if hour == 0 && minute == 0 {
            return dfMonthDay.string(from: date)  // "Feb 6", "Jan 31"
        }
        
        // All other hours: show the time
        return timeOfDayLabelCompact(date)
    }

    static func crosshairDateLabel(for interval: ChartInterval, date: Date) -> String {
        switch interval {
        case .live, .oneMin, .fiveMin, .fifteenMin, .thirtyMin, .oneHour, .fourHour:
            return uses24hClock ? dfCrossIntraday24.string(from: date) : dfCrossIntraday12.string(from: date)
        case .oneDay, .oneWeek, .oneMonth, .threeMonth, .sixMonth, .oneYear, .threeYear, .all:
            return dfCrossLong.string(from: date)
        }
    }
    
    // MARK: - Common App Formatters (CONSOLIDATION: Used across multiple files)
    
    /// ISO 8601 formatter - reuse instead of creating new instances
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    /// ISO 8601 without fractional seconds
    static let iso8601NoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    /// Relative time formatter (e.g., "2 hours ago") — respects selected language
    static let relativeTime: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = LocaleManager.current
        return formatter
    }()
    
    /// Short date-time for lists and rows (e.g., "Jan 15, 3:45 PM")
    static let dfShortDateTime = make("MMM d, h:mm a")
    
    /// Full date (e.g., "January 15, 2026")
    static let dfFullDate = make("MMMM d, yyyy")
    
    // MARK: - Convenience Methods
    
    /// Formats a date as relative time (e.g., "2h ago")
    static func relativeTimeLabel(_ date: Date) -> String {
        relativeTime.localizedString(for: date, relativeTo: Date())
    }
    
    /// Formats a date for display in lists (e.g., "Jan 15, 3:45 PM")
    static func shortDateTimeLabel(_ date: Date) -> String {
        dfShortDateTime.string(from: date)
    }
    
    /// Parses an ISO 8601 date string (tries with and without fractional seconds)
    static func parseISO8601(_ string: String) -> Date? {
        iso8601.date(from: string) ?? iso8601NoFraction.date(from: string)
    }
}
