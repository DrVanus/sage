// NumberFormatting.swift
// Shared helpers for price and large-number formatting used across views.

import Foundation

enum MarketFormat {
    // PERFORMANCE FIX: Cached formatters - creating NumberFormatter is expensive
    // These are reused across all formatting calls instead of creating new instances.
    // Locale is set from LocaleManager.current for proper number formatting
    // (e.g., "1,234.56" in English vs "1.234,56" in German).
    
    /// Rebuilds all cached formatters when the language changes.
    static func rebuildFormatters() {
        let locale = LocaleManager.current
        for f in [decimalFormatter, noDecimalFormatter, twoDecimalFormatter, smallValueFormatter, fourDecimalFormatter] {
            f.locale = locale
        }
    }
    
    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = LocaleManager.current
        return f
    }()
    
    private static let noDecimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        f.locale = LocaleManager.current
        return f
    }()
    
    private static let twoDecimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = LocaleManager.current
        return f
    }()
    
    private static let smallValueFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 8
        f.locale = LocaleManager.current
        return f
    }()
    
    private static let fourDecimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 4
        f.locale = LocaleManager.current
        return f
    }()
    
    /// Thread-safe formatter access with dynamic configuration
    private static func formatNumber(_ value: Double, minFraction: Int, maxFraction: Int) -> String {
        // Use the appropriate pre-configured formatter when possible
        if minFraction == 0 && maxFraction == 0 {
            return noDecimalFormatter.string(from: NSNumber(value: value)) ?? "0"
        } else if minFraction == 2 && maxFraction == 2 {
            return twoDecimalFormatter.string(from: NSNumber(value: value)) ?? "0.00"
        } else if minFraction == 2 && maxFraction == 8 {
            return smallValueFormatter.string(from: NSNumber(value: value)) ?? "0.00"
        } else if minFraction == 2 && maxFraction == 4 {
            return fourDecimalFormatter.string(from: NSNumber(value: value)) ?? "0.00"
        }
        
        // Fallback for dynamic configurations (less common cases)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = minFraction
        f.maximumFractionDigits = maxFraction
        return f.string(from: NSNumber(value: value)) ?? "0"
    }
    /// Formats a price with sensible fraction digits and a leading currency symbol.
    /// Uses the global CurrencyManager to determine the current display currency.
    /// Pass `useCurrentCurrency: true` to convert from USD to the user's selected currency.
    static func price(_ value: Double, currencySymbol: String? = nil, useCurrentCurrency: Bool = false) -> String {
        guard value.isFinite, value > 0 else {
            let symbol = currencySymbol ?? currentCurrencySymbol
            return "\(symbol)0.00"
        }
        
        // Determine the display value and symbol
        let displayValue: Double
        let symbol: String
        
        if useCurrentCurrency {
            // Convert from USD to current currency using static nonisolated accessor
            displayValue = CurrencyManager.convertFromUSD(value)
            symbol = currencySymbol ?? CurrencyManager.symbol
        } else {
            displayValue = value
            symbol = currencySymbol ?? currentCurrencySymbol
        }
        
        // Check if currency uses decimals
        let usesDecimals = CurrencyManager.usesDecimals
        
        // PERFORMANCE FIX: Use cached formatters instead of creating new ones
        let num: String
        if !usesDecimals {
            num = formatNumber(displayValue, minFraction: 0, maxFraction: 0)
        } else if displayValue < 1.0 {
            num = formatNumber(displayValue, minFraction: 2, maxFraction: 8)
        } else {
            num = formatNumber(displayValue, minFraction: 2, maxFraction: 2)
        }
        return symbol + num
    }
    
    /// Returns the current currency symbol from CurrencyManager
    static var currentCurrencySymbol: String {
        CurrencyManager.symbol
    }
    
    /// Compact price format for space-constrained areas (e.g., $95.4K instead of $95,432.78)
    static func priceCompact(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "\(currentCurrencySymbol)0" }
        
        let symbol = currentCurrencySymbol
        
        if value >= 1_000_000 {
            return String(format: "%@%.2fM", symbol, value / 1_000_000)
        } else if value >= 10_000 {
            return String(format: "%@%.1fK", symbol, value / 1_000)
        } else if value >= 1_000 {
            return String(format: "%@%.2fK", symbol, value / 1_000)
        } else if value >= 1 {
            return String(format: "%@%.2f", symbol, value)
        } else {
            // Small values - show more decimals
            return String(format: "%@%.4f", symbol, value)
        }
    }

    /// Formats large numeric values using thousands (K), millions (M), billions (B), and trillions (T) suffixes.
    /// Uses smart decimal precision based on magnitude to prevent truncation in tight layouts.
    static func largeNumber(_ value: Double) -> String {
        guard value.isFinite else { return "--" }
        
        // PERFORMANCE FIX: Helper to determine max decimals based on magnitude
        func maxDecimals(for short: Double) -> Int {
            if short >= 100 { return 0 }
            else if short >= 10 { return 1 }
            else { return 2 }
        }
        
        if value >= 1_000_000_000_000 {
            let short = value / 1_000_000_000_000
            let num = formatNumber(short, minFraction: 0, maxFraction: maxDecimals(for: short))
            return "\(num)T"
        } else if value >= 1_000_000_000 {
            let short = value / 1_000_000_000
            let num = formatNumber(short, minFraction: 0, maxFraction: maxDecimals(for: short))
            return "\(num)B"
        } else if value >= 1_000_000 {
            let short = value / 1_000_000
            let num = formatNumber(short, minFraction: 0, maxFraction: maxDecimals(for: short))
            return "\(num)M"
        } else if value >= 1_000 {
            let short = value / 1_000
            let num = formatNumber(short, minFraction: 0, maxFraction: maxDecimals(for: short))
            return "\(num)K"
        } else {
            return formatNumber(value, minFraction: 0, maxFraction: 2)
        }
    }

    /// Formats large numeric values as currency with thousands (K), millions (M), billions (B), or trillions (T) suffixes.
    /// Example: 1234567890 -> "$1.23B" (using current currency symbol).
    /// Pass `useCurrentCurrency: true` to convert from USD to the user's selected currency.
    static func largeCurrency(_ value: Double, currencySymbol: String? = nil, useCurrentCurrency: Bool = false) -> String {
        let displayValue: Double
        let symbol: String
        
        if useCurrentCurrency {
            displayValue = CurrencyManager.convertFromUSD(value)
            symbol = currencySymbol ?? CurrencyManager.symbol
        } else {
            displayValue = value
            symbol = currencySymbol ?? currentCurrencySymbol
        }
        
        let sign = displayValue < 0 ? "-" : ""
        let core = largeNumber(abs(displayValue))
        return sign + symbol + core
    }
    
    /// Ultra-compact volume format for narrow columns - never truncates.
    /// Prioritizes fitting in ~50-60pt width over precision.
    /// Examples: 220050000 → "220M", 8500000000 → "8.5B", 47700000 → "47.7M"
    static func compactVolume(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "—" }
        
        if value >= 1_000_000_000_000 {
            // Trillions: 1+ decimal only if < 10T
            let short = value / 1_000_000_000_000
            if short >= 10 {
                return String(format: "%.0fT", short)
            } else {
                return String(format: "%.1fT", short)
            }
        } else if value >= 1_000_000_000 {
            // Billions: 1 decimal only if < 10B
            let short = value / 1_000_000_000
            if short >= 10 {
                return String(format: "%.0fB", short)
            } else {
                return String(format: "%.1fB", short)
            }
        } else if value >= 1_000_000 {
            // Millions: 1 decimal only if < 10M
            let short = value / 1_000_000
            if short >= 10 {
                return String(format: "%.0fM", short)
            } else {
                return String(format: "%.1fM", short)
            }
        } else if value >= 1_000 {
            // Thousands: 1 decimal only if < 10K
            let short = value / 1_000
            if short >= 10 {
                return String(format: "%.0fK", short)
            } else {
                return String(format: "%.1fK", short)
            }
        } else {
            // Small values: show as integer
            return String(format: "%.0f", value)
        }
    }

    /// Formats a price into (currency symbol, number) parts using magnitude-aware precision.
    /// Returns nil for non-finite or non-positive values.
    static func priceParts(_ value: Double, currencySymbol: String? = nil) -> (currency: String, number: String)? {
        guard value.isFinite, value > 0 else { return nil }
        let currency = currencySymbol ?? (Locale.current.currencySymbol ?? "$")

        // PERFORMANCE FIX: Use cached formatters
        
        // Large numbers: no decimals
        if value >= 100_000 {
            let s = formatNumber(value, minFraction: 0, maxFraction: 0)
            return (currency, s)
        }
        // Medium: 2 decimals
        if value >= 1 {
            let s = formatNumber(value, minFraction: 2, maxFraction: 2)
            return (currency, s)
        }
        // Small: 0.01...1 => 2–4 decimals
        if value >= 0.01 {
            let s = formatNumber(value, minFraction: 2, maxFraction: 4)
            return (currency, s)
        }
        // Tiny: use significant digits and trim trailing zeros
        // Keep this as dynamic formatter since it uses special settings
        func significant(max: Int) -> String? {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.usesSignificantDigits = true
            f.minimumSignificantDigits = 2
            f.maximumSignificantDigits = max
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 8
            return f.string(from: NSNumber(value: value))
        }
        var s = significant(max: 6) ?? String(value)
        if s.count > 9 { s = significant(max: 5) ?? s }
        if s.count > 9 { s = significant(max: 4) ?? s }
        if s.contains(".") {
            while s.last == "0" { s.removeLast() }
            if s.last == "." { s.removeLast() }
        }
        return (currency, s)
    }
}
