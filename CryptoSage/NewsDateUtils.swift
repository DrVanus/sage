import Foundation

/// Utilities for parsing and formatting news-related dates.
public struct NewsDate {
    /// Relative date time formatter configured to use abbreviated style and current locale/time zone.
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    /// Date formatter for "Yesterday, h:mm a" style, e.g. "Yesterday, 3:45 PM".
    private static let yesterdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateFormat = "'Yesterday,' h:mm a"
        return formatter
    }()
    
    /// Date formatter for "EEE, h:mm a" style, e.g. "Tue, 3:45 PM".
    private static let shortAbsoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateFormat = "EEE, h:mm a"
        return formatter
    }()
    
    /// Date formatter for "MMM d, h:mm a" style, e.g. "Nov 13, 3:45 PM".
    private static let longAbsoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()
    
    /// Returns a short, user-friendly string representation of the date relative to `now`.
    ///
    /// - Parameters:
    ///   - date: The date to format.
    ///   - now: The reference date for relative calculations. Defaults to `Date()`.
    /// - Returns: A short string representing the date: if within 24 hours, an abbreviated relative string like "3h ago";
    ///            if yesterday, "Yesterday, h:mm a"; if within 7 days, "EEE, h:mm a"; else "MMM d, h:mm a".
    public static func badgeString(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            // Within same day, show abbreviated relative time
            return relativeDateFormatter.localizedString(for: date, relativeTo: now)
        }
        
        if calendar.isDateInYesterday(date) {
            return yesterdayFormatter.string(from: date)
        }
        
        if let daysDiff = calendar.dateComponents([.day], from: date.startOfDay(in: calendar), to: now.startOfDay(in: calendar)).day,
           abs(daysDiff) < 7 {
            return shortAbsoluteFormatter.string(from: date)
        }
        
        return longAbsoluteFormatter.string(from: date)
    }
    
    /// Returns an absolute short string representation of the date: "EEE, h:mm a".
    ///
    /// - Parameter date: The date to format.
    /// - Returns: A string like "Tue, 3:45 PM".
    public static func absoluteShort(for date: Date) -> String {
        shortAbsoluteFormatter.string(from: date)
    }
    
    /// Returns a relative string representation of the date relative to `now`.
    ///
    /// - Parameters:
    ///   - date: The date to format.
    ///   - now: The reference date for relative calculations. Defaults to `Date()`.
    /// - Returns: A relative abbreviated string like "3h ago".
    public static func relative(for date: Date, now: Date = Date()) -> String {
        relativeDateFormatter.localizedString(for: date, relativeTo: now)
    }
    
    /// Clamps the date if it appears to be unrealistically in the future relative to `now`.
    ///
    /// If the date is more than 12 hours in the future but less than 7 days in the future relative to `now`,
    /// returns `now` instead to guard against bad timezone or ms/seconds confusion.
    /// Otherwise returns the original date.
    ///
    /// - Parameters:
    ///   - date: The date to clamp.
    ///   - now: The reference date. Defaults to `Date()`.
    /// - Returns: Either `now` if the date is within the unrealistic future window, or `date` unchanged.
    public static func clampIfUnrealistic(_ date: Date, now: Date = Date()) -> Date {
        let interval = date.timeIntervalSince(now)
        if interval > 12 * 3600 && interval < 7 * 24 * 3600 {
            return now
        }
        return date
    }
}

private extension Date {
    /// Returns the start of the day for the date in the given calendar.
    func startOfDay(in calendar: Calendar) -> Date {
        calendar.startOfDay(for: self)
    }
}
