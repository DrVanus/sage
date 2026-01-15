// NumberFormatting.swift
// Shared helpers for price and large-number formatting used across views.

import Foundation

enum MarketFormat {
    /// Formats a price with sensible fraction digits and a leading currency symbol (defaults to current locale symbol, falls back to "$"),
    /// matching common display expectations in this app.
    static func price(_ value: Double, currencySymbol: String? = nil) -> String {
        guard value.isFinite, value > 0 else { return "$0.00" }
        let symbol = currencySymbol ?? (Locale.current.currencySymbol ?? "$")
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if value < 1.0 {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 8
        } else {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }
        let num = formatter.string(from: NSNumber(value: value)) ?? "0.00"
        return symbol + num
    }

    /// Formats large numeric values using thousands (K), millions (M), and billions (B) suffixes.
    static func largeNumber(_ value: Double) -> String {
        guard value.isFinite else { return "--" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        if value >= 1_000_000_000 {
            let short = value / 1_000_000_000
            return f.string(from: NSNumber(value: short)).map { "\($0)B" } ?? "--"
        } else if value >= 1_000_000 {
            let short = value / 1_000_000
            return f.string(from: NSNumber(value: short)).map { "\($0)M" } ?? "--"
        } else if value >= 1_000 {
            let short = value / 1_000
            return f.string(from: NSNumber(value: short)).map { "\($0)K" } ?? "--"
        } else {
            return f.string(from: NSNumber(value: value)) ?? String(value)
        }
    }
}
