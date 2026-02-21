import SwiftUI

/// Shared column width constants for the Market list so header and rows align perfectly on all devices.
/// PERFORMANCE: Layout is cached and only recomputed when screen width changes.
enum MarketColumns {
    static let horizontalPadding: CGFloat = 14
    static let gutter: CGFloat = 6

    /// Horizontal padding used around rows/headers in MarketView (leading + trailing).
    /// We budget 36pt by default to match `.padding(.horizontal)` used in views.
    private static var horizontalPaddingBudget: CGFloat { horizontalPadding * 2 }

    // PERFORMANCE: Cache the screen width and layout to avoid recomputation on every property access
    private static var cachedScreenWidth: CGFloat = 0
    private static var cachedLayout: Layout?
    
    /// Shared column width constants for the Market list so header and rows align perfectly on all devices.
    /// These are adaptive, computed from the current screen width to avoid stretched or cramped layouts.
    private static var screenWidth: CGFloat {
        // Prefer the active key window for the current orientation.
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }),
           let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
            return window.bounds.width
        }
        return UIScreen.main.bounds.width
    }

    /// Total available content width inside the row after subtracting padding.
    private static func contentWidth(for width: CGFloat) -> CGFloat {
        // Cap to a readable width so columns don't over-stretch on large devices.
        // 420 keeps rows compact and prevents a stretched feel on large phones.
        let maxReadable: CGFloat = 420
        let effective = min(width, maxReadable)
        return max(0, effective - horizontalPaddingBudget)
    }

    // Centralized layout pass to ensure columns never overflow and text remains readable.
    private struct Layout {
        let star: CGFloat
        let spark: CGFloat
        let price: CGFloat
        let change: CGFloat
        let volume: CGFloat
        let coin: CGFloat
    }

    /// PERFORMANCE: Cached layout getter - only recomputes when screen width changes
    private static var layout: Layout {
        let currentWidth = screenWidth
        
        // Return cached layout if screen width hasn't changed
        if let cached = cachedLayout, abs(cachedScreenWidth - currentWidth) < 1.0 {
            return cached
        }
        
        // Recompute layout for new screen width
        let computed = computeLayout(for: currentWidth)
        cachedScreenWidth = currentWidth
        cachedLayout = computed
        return computed
    }
    
    /// Computes layout for a given screen width
    private static func computeLayout(for width: CGFloat) -> Layout {
        let contentWidth = contentWidth(for: width)
        
        // Fixed/star and adaptive columns with comfortable targets and clamps
        let star: CGFloat = 20 // small but tappable alongside the row's own touch area

        // Target widths computed from contentWidth
        let tSpark = contentWidth * 0.06
        let tPrice = contentWidth * 0.160
        let tChange = contentWidth * 0.135
        let tVolume = contentWidth * 0.10

        // Clamps for adaptive columns
        let minSpark: CGFloat = 34, maxSpark: CGFloat = 42
        let minPrice: CGFloat = 102, maxPrice: CGFloat = 134
        let minChange: CGFloat = 58, maxChange: CGFloat = 94
        let minVolume: CGFloat = 50, maxVolume: CGFloat = 72

        var spark = clamp(tSpark, min: minSpark, max: maxSpark)
        var price = clamp(tPrice, min: minPrice, max: maxPrice)
        var change = clamp(tChange, min: minChange, max: maxChange)
        var volume = clamp(tVolume, min: minVolume, max: maxVolume)

        // Compute remainder for the Coin column with a desired minimum
        let guttersCount: CGFloat = 5 // Coin|7D|Price|24h|Vol|Fav
        let guttersTotal = gutter * guttersCount
        let used = star + spark + price + change + volume
        let remainder = contentWidth - used - guttersTotal

        let desiredCoinMin: CGFloat = 130
        let desiredCoinMax: CGFloat = 138

        if remainder >= desiredCoinMin {
            // If we have more than we need for Coin, cap Coin and distribute surplus to the right-side columns.
            let surplus = max(0, remainder - desiredCoinMax)
            if surplus > 0 {
                // Try to expand change, then price, then volume, then spark up to their maxes.
                let growChange = min(surplus, max(0, maxChange - change))
                change += growChange
                var remaining = surplus - growChange

                let growPrice = min(remaining, max(0, maxPrice - price))
                price += growPrice
                remaining -= growPrice

                let growVolume = min(remaining, max(0, maxVolume - volume))
                volume += growVolume
                remaining -= growVolume

                let growSpark = min(remaining, max(0, maxSpark - spark))
                spark += growSpark
                remaining -= growSpark

                let coin = min(desiredCoinMax, remainder)
                return Layout(star: star, spark: spark, price: price, change: change, volume: volume, coin: coin)
            } else {
                // Enough for Coin but not beyond its max — use the remainder directly.
                let coin = max(desiredCoinMin, remainder)
                return Layout(star: star, spark: spark, price: price, change: change, volume: volume, coin: coin)
            }
        }

        // We need to reclaim space from adaptive columns to give Coin its minimum.
        let deficit = desiredCoinMin - max(0, remainder)
        let sparkCap = spark - minSpark
        let priceCap = price - minPrice
        let changeCap = change - minChange
        let volumeCap = volume - minVolume
        let totalCap = max(0, sparkCap) + max(0, priceCap) + max(0, changeCap) + max(0, volumeCap)

        if totalCap <= 0 {
            // Nothing to reclaim; accept a smaller coin column, but never negative.
            return Layout(star: star, spark: spark, price: price, change: change, volume: volume, coin: max(0, remainder))
        }

        let ratio = min(1, deficit / totalCap)
        spark -= sparkCap * ratio
        price -= priceCap * ratio
        change -= changeCap * ratio
        volume -= volumeCap * ratio

        // Recalculate coin with reclaimed space
        let newUsed = star + spark + price + change + volume
        let newRemainder = contentWidth - newUsed - guttersTotal
        let coin = max(0, newRemainder)

        return Layout(star: star, spark: spark, price: price, change: change, volume: volume, coin: coin)
    }

    /// Favorite star column stays fairly small and fixed.
    static var starColumnWidth: CGFloat { layout.star }

    /// 7D sparkline gets a compact but visible area.
    static var sparklineWidth: CGFloat { layout.spark }

    /// Price column uses monospaced digits; give it a healthy width but cap it for large phones.
    static var priceWidth: CGFloat { layout.price }

    /// 24h change column is short text like "+1.23%".
    static var changeWidth: CGFloat { layout.change }

    /// Volume column shows abbreviated numbers (e.g., 56.9B).
    static var volumeWidth: CGFloat { layout.volume }

    /// Coin column takes exactly the remainder so nothing overflows.
    static var coinColumnWidth: CGFloat { layout.coin }

    /// Clamp helper
    private static func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }
    
    /// Call this to invalidate the cached layout (e.g., on device rotation)
    static func invalidateCache() {
        cachedLayout = nil
        cachedScreenWidth = 0
    }
}
