//  ChartDateFormatters.swift
//  Centralized date formatters and helpers for chart axes and crosshair

import Foundation

struct ChartDateFormatters {
    // MARK: - Factory
    private static func make(_ format: String) -> DateFormatter {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = format
        return df
    }

    // MARK: - Formatters
    static let dfHour = make("h a")
    static let dfHourMinute = make("h:mm a")
    static let dfHour24 = make("HH")
    static let dfHourMinute24 = make("HH:mm")

    static let dfDayNumber = make("d")
    static let dfMonthDay = make("MMM d")
    static let dfMonth = make("MMM")
    static let dfMonthShortYear = make("MMM ''yy")
    static let dfYear = make("yyyy")

    static let dfCrossIntraday12 = make("EEE, MMM d • h:mm a")
    static let dfCrossIntraday24 = make("EEE, MMM d • HH:mm")
    static let dfCrossLong = make("EEE, MMM d, yyyy")

    // MARK: - Environment
    static var uses24hClock: Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !template.contains("a")
    }

    // MARK: - Labels
    static func timeOfDayLabel(_ date: Date) -> String {
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

    static func crosshairDateLabel(for interval: ChartInterval, date: Date) -> String {
        switch interval {
        case .live, .oneMin, .fiveMin, .fifteenMin, .thirtyMin, .oneHour, .fourHour:
            return uses24hClock ? dfCrossIntraday24.string(from: date) : dfCrossIntraday12.string(from: date)
        case .oneWeek, .oneMonth, .threeMonth, .oneYear, .threeYear, .all:
            return dfCrossLong.string(from: date)
        default:
            return dfCrossLong.string(from: date)
        }
    }
}
