import Foundation

public enum PercentTrend: Sendable, Equatable {
    case positive
    case negative
    case neutral
}

public struct PercentDisplay: Sendable {
    /// Formats a fractional change (e.g., 0.051 == 5.1%) into display text, trend category, and accessibility string.
    /// - Parameter frac: Fractional value (e.g., 0.051 == 5.1%)
    /// - Returns: (text, trend, accessibilityValue)
    public static func formatFraction(_ frac: Double) -> (text: String, trend: PercentTrend, accessibility: String) {
        guard frac.isFinite else { return ("0.00%", .neutral, "0.00 percent unchanged") }
        let percent = abs(frac) * 100.0
        // Neutral only when exactly 0.00% at two decimals.
        if percent < 1e-9 { return ("0.00%", .neutral, "0.00 percent unchanged") }
        let sign = frac >= 0 ? "+" : "-"
        if percent < 0.005 {
            let dir = frac >= 0 ? "up" : "down"
            return ("\(sign)0.01%", frac >= 0 ? .positive : .negative, "0.01 percent \(dir)")
        }
        let text = "\(sign)\(String(format: "%.2f", percent))%"
        let dir = frac >= 0 ? "up" : "down"
        let acc = "\(String(format: "%.2f", percent)) percent \(dir)"
        return (text, frac >= 0 ? .positive : .negative, acc)
    }
}
