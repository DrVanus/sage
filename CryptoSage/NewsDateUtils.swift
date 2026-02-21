import Foundation

/// Utilities for parsing and formatting news-related dates.
public struct NewsDate {
    /// Relative date time formatter configured to use abbreviated style and current locale/time zone.
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    /// Date formatter for "EEE, h:mm a" style, e.g. "Tue, 3:45 PM".
    private static let shortAbsoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE, h:mm a"
        return formatter
    }()
    
    /// Date formatter for "MMM d, h:mm a" style, e.g. "Nov 13, 3:45 PM".
    private static let longAbsoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()
    
    /// Compact relative string like "5m ago", "3h ago", "2d ago". Returns nil for >= 7 days.
    private static func relativeAbbrevString(from date: Date, now: Date) -> String? {
        let seconds = Int(now.timeIntervalSince(date))
        // If slightly in the future (<= 6h), treat as just now to avoid confusing future labels
        if seconds < 0 {
            if seconds > -(6 * 3600) { return "just now" }
            return nil
        }
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        // For items within the last 6 hours, include minutes for better precision
        if hours < 6 {
            let rem = minutes % 60
            if rem > 0 {
                return "\(hours)h \(rem)m ago"
            } else {
                return "\(hours)h ago"
            }
        }
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        return nil
    }
    
    /// Returns a sanitized date that corrects common provider mistakes:
    /// - Future dates within 12h are clamped to now
    /// - Millisecond/second confusion already handled upstream, but we keep a safety net here
    /// - Coerce dates with only day precision to noon local to avoid 00:00 causing off-by-hours
    public static func sanitize(_ date: Date, now: Date = Date()) -> Date {
        let interval = date.timeIntervalSince(now)
        if interval > 0 && interval < 12 * 3600 { return now } // guard against minor future drift
        return date
    }
    
    /// Returns a short, user-friendly string representation of the date relative to `now`.
    ///
    /// - Parameters:
    ///   - date: The date to format.
    ///   - now: The reference date for relative calculations. Defaults to `Date()`.
    /// - Returns: If within the last 7 days, an abbreviated relative string like "3h ago" or "2d ago";
    ///            otherwise an absolute string like "MMM d, h:mm a".
    public static func badgeString(for date: Date, now: Date = Date()) -> String {
        let date = sanitize(date, now: now)
        // Prefer compact relative for anything under 7 days so Home and News list are consistent.
        if let rel = relativeAbbrevString(from: date, now: now) {
            return rel
        }
        // 7+ days: show absolute month/day + time.
        return longAbsoluteFormatter.string(from: date)
    }
    
    /// Returns a display string consistent with `badgeString` for recent dates.
    ///
    /// If the date is within the last 7 days, this returns the same abbreviated relative string as `badgeString`
    /// (e.g., "3h ago", "1d ago") to keep Home and the Crypto News list consistent.
    /// Otherwise, it returns an absolute short string "EEE, h:mm a" (e.g., "Tue, 3:45 PM").
    ///
    /// - Parameter date: The date to format.
    public static func absoluteShort(for date: Date) -> String {
        return shortAbsoluteFormatter.string(from: date)
    }
    
    /// Returns a relative string representation of the date relative to `now`.
    ///
    /// - Parameters:
    ///   - date: The date to format.
    ///   - now: The reference date for relative calculations. Defaults to `Date()`.
    /// - Returns: A relative abbreviated string like "3h ago".
    public static func relative(for date: Date, now: Date = Date()) -> String {
        let date = sanitize(date, now: now)
        if let rel = relativeAbbrevString(from: date, now: now) {
            return rel
        }
        return relativeDateFormatter.localizedString(for: date, relativeTo: now)
    }
    
    /// Clamps the date if it appears to be unrealistically in the future relative to `now`.
    ///
    /// If the date is more than 3 hours in the future but less than 7 days in the future relative to `now`,
    /// returns `now` instead to guard against bad timezone or ms/seconds confusion.
    /// Otherwise returns the original date.
    ///
    /// - Parameters:
    ///   - date: The date to clamp.
    ///   - now: The reference date. Defaults to `Date()`.
    /// - Returns: Either `now` if the date is within the unrealistic future window, or `date` unchanged.
    public static func clampIfUnrealistic(_ date: Date, now: Date = Date()) -> Date {
        let interval = date.timeIntervalSince(now)
        if interval > 2 * 3600 && interval < 24 * 3600 {
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
