import Foundation

// Centralized helpers for "best" change percentages used across the app.
// These prefer the live rolling window from LivePriceManager, fall back to
// provider (CoinGecko) values exposed via MarketCoin.unified*, and finally
// derive from the 7D sparkline when needed. All outputs are normalized to
// percent units (e.g., 5.1 == +5.1%).
@MainActor
extension MarketCoin {
    // MARK: - Internal helpers

    /// Best available series for percent derivations: prefer engine canonical, else 7D spark.
    private func bestSeriesForDerivation(livePrice: Double?) -> [Double] {
        // Try to reuse metrics engine cached output for consistency with rows and charts
        let raw = sparklineIn7d
        let cached = MarketMetricsCache.cached(
            symbol: symbol,
            rawSeries: raw,
            livePrice: livePrice,
            provider1h: unified1hPercent,
            provider24h: unified24hPercent,
            isStable: isStable,
            targetPoints: 180
        )
        if let out = cached { return out.canonical }
        // Fallback to provider sparkline (already filtered in callers)
        return raw
    }

    /// Normalize a change value into percent units.
    /// - Notes:
    ///   - Values in 0..1 are treated as fractional and scaled by 100.
    ///   - Values > 1000 are treated as over-scaled and divided by 100.
    private func normalizePercentValue(_ v: Double) -> Double {
        guard v.isFinite else { return v }
        let absV = abs(v)
        if absV <= 1.0 { return v * 100.0 }
        if absV > 1000.0 { return v / 100.0 }
        return v
    }

    /// Derive a percent change over the given lookback (in hours) from the 7D sparkline.
    /// Attempts to anchor to the latest known price when available.
    /// For short timeframes (1-2h), applies stricter guards to reduce noise.
    /// Uses smart step calculation based on actual sparkline point count.
    private func derivedPercentFromSparkline(hours: Int, anchorPrice: Double? = nil) -> Double? {
        let series = bestSeriesForDerivation(livePrice: anchorPrice).filter { $0.isFinite && $0 > 0 }
        guard !series.isEmpty, hours > 0 else { return nil }
        
        // Require more data points for short timeframes to reduce noise
        let minPointsRequired: Int = {
            if hours <= 1 { return 6 }   // 1h needs at least 6 points for reliability
            if hours <= 2 { return 5 }   // 2h needs at least 5 points
            return 4                      // Longer timeframes can work with 4+ points
        }()
        if series.count < minPointsRequired { return nil }
        
        let n = series.count
        
        // SMART STEP CALCULATION: Detect actual data coverage based on point count
        // instead of always assuming 7 days
        //
        // Common sparkline formats:
        // - 168 points (140-200): Hourly data over 7 days (Binance hourly klines)
        // - 42 points (35-55): 4-hour intervals over 7 days (Binance 4h klines)
        // - 7 points (5-14): Daily data over 7 days (Binance daily klines)
        // - Other: Calculate proportionally with validation
        
        let (estimatedTotalHours, stepHours): (Double, Double) = {
            if n >= 140 && n <= 200 {
                // Hourly data: ~168 points = 7 days, each step = 1 hour
                let totalH = Double(n - 1)
                return (totalH, 1.0)
            } else if n >= 35 && n < 140 {
                // 4-hour interval data: ~42 points = 7 days, each step = 4 hours
                let totalH = Double(n - 1) * 4.0
                return (totalH, 4.0)
            } else if n >= 5 && n < 35 {
                // Daily or sparse data: ~7 points = 7 days, each step = 24 hours
                let totalH = Double(n - 1) * 24.0
                return (totalH, 24.0)
            } else {
                // Fallback: assume 7-day coverage (legacy behavior)
                let totalH = 24.0 * 7.0
                let step = totalH / Double(max(1, n - 1))
                return (totalH, step)
            }
        }()
        
        // Validate that we have enough data coverage for the requested timeframe
        let minimumCoverageRequired = Double(hours) * 0.8  // Require 80% of requested timeframe
        if estimatedTotalHours < minimumCoverageRequired {
            return nil  // Insufficient data coverage
        }
        
        // Calculate lookback in steps
        let stepsForHours = max(1, Int(round(Double(hours) / stepHours)))
        
        // For short timeframes, ensure we have enough steps back
        let minimumSteps: Int = {
            if hours <= 1 { return 2 }   // Need at least 2 steps for 1h
            if hours <= 2 { return 3 }   // Need at least 3 steps for 2h
            return 1
        }()
        let lookback = max(minimumSteps, min(n - 1, stepsForHours))

        // Resolve last value: prefer live/provider price to reduce drift
        let lastVal: Double = {
            // Prefer the series last point to keep consistency; only use anchor if it's close
            let seriesLast = series.last ?? 0
            guard let p = anchorPrice, p.isFinite, p > 0 else { return seriesLast }
            let tol = max(0.000001, seriesLast * 0.005) // 0.5% tolerance
            return abs(seriesLast - p) <= tol ? p : seriesLast
        }()
        guard lastVal > 0 else { return nil }

        // Find a reasonable previous index near the lookback horizon
        let nominalIndex = max(0, (n - 1) - lookback)
        func nearestUsableIndex(around idx: Int, maxSteps: Int = 12) -> Int? {
            var step = 0
            while step <= maxSteps {
                let back = idx - step
                if back >= 0, series[back].isFinite, series[back] > 0 { return back }
                step += 1
            }
            step = 1
            while step <= maxSteps {
                let fwd = idx + step
                if fwd < n, series[fwd].isFinite, series[fwd] > 0 { return fwd }
                step += 1
            }
            return series.firstIndex(where: { $0.isFinite && $0 > 0 })
        }
        guard let prevIdx = nearestUsableIndex(around: nominalIndex) else { return nil }
        let prev = series[prevIdx]
        guard prev.isFinite, prev > 0 else { return nil }

        let pct = ((lastVal - prev) / prev) * 100.0
        // Remove micro-noise: return nil (not 0) so callers can fall through to
        // a better data source or show "—" instead of a misleading "0.00%"
        if abs(pct) < 0.0005 { return nil }
        
        // Apply timeframe-appropriate clamping to reduce noise
        // FIX: Consistent limits across app - ±50% for 1h, ±300% for 24h, ±500% for 7d
        let maxChange: Double = {
            if hours <= 1 { return 50.0 }    // 1h: cap at ±50%
            if hours <= 24 { return 300.0 }  // 24h: cap at ±300%
            return 500.0                      // 7d: cap at ±500%
        }()
        
        return max(-maxChange, min(maxChange, pct))
    }

    /// Derive a 7D percent change from the sparkline (first vs last/anchor).
    private func derived7dPercent(anchorPrice: Double? = nil) -> Double? {
        let series = sparklineIn7d.filter { $0.isFinite && $0 > 0 }
        guard series.count >= 2 else { return nil }
        let first = series.first!
        let last: Double = {
            if let p = anchorPrice, p.isFinite, p > 0 { return p }
            return series.last!
        }()
        guard first > 0 else { return nil }
        let pct = ((last - first) / first) * 100.0
        // Remove micro-noise: return nil (not 0) to avoid displaying misleading "0.00%"
        if abs(pct) < 0.0005 { return nil }
        // FIX: Consistent ±500% limit for 7d changes across app
        return max(-500.0, min(500.0, pct))
    }

    // MARK: - Best-available percents
    // 
    // These properties delegate to LivePriceManager as the single source of truth.
    // This eliminates inconsistency from multiple blending layers.

    /// Best-available 24h percent change.
    /// Delegates to LivePriceManager which handles provider → cache → derivation fallback.
    var best24hPercent: Double? {
        // LivePriceManager is the authoritative source
        if let live = LivePriceManager.shared.bestChange24hPercent(for: self), live.isFinite {
            return live
        }
        // Fallback to provider value if LivePriceManager hasn't indexed this coin yet
        if let provider = unified24hPercent, provider.isFinite {
            return provider
        }
        // STALE DATA FIX: Don't derive from sparkline during startup grace period.
        // Sparklines from cache are stale and would produce wrong percentages.
        // Return nil → UI shows "—" briefly until fresh data arrives (1-3s).
        guard LivePriceManager.shared.hasReceivedFreshData else { return nil }
        // Last resort: derive from sparkline locally
        return derivedPercentFromSparkline(hours: 24, anchorPrice: priceUsd)
    }

    /// Best-available 1h percent change.
    /// Delegates to LivePriceManager which handles provider → cache → sparkline derivation fallback.
    var best1hPercent: Double? {
        // LivePriceManager is the authoritative source (includes sparkline derivation)
        if let live = LivePriceManager.shared.bestChange1hPercent(for: self), live.isFinite {
            return live
        }
        // Fallback to provider value if available
        if let provider = unified1hPercent, provider.isFinite {
            return provider
        }
        // STALE DATA FIX: Don't derive from sparkline during startup grace period.
        guard LivePriceManager.shared.hasReceivedFreshData else { return nil }
        // Last resort: derive from sparkline locally (better than estimating from 24h)
        // The 24h/12 formula was mathematically incorrect - a coin can be +10% over 24h but -2% in the last hour
        // FIX: Consistent ±50% limit for 1h changes across app
        if let derived = derivedPercentFromSparkline(hours: 1, anchorPrice: priceUsd) {
            return max(-50.0, min(50.0, derived))
        }
        return nil
    }

    /// Best-available 7d percent change.
    /// Delegates to LivePriceManager which handles provider → cache → derivation fallback.
    var best7dPercent: Double? {
        // LivePriceManager is the authoritative source
        if let live = LivePriceManager.shared.bestChange7dPercent(for: self), live.isFinite {
            return normalizePercentValue(live)
        }
        // Fallback to provider value
        if let provider = unified7dPercent, provider.isFinite {
            return normalizePercentValue(provider)
        }
        // STALE DATA FIX: Don't derive from sparkline during startup grace period.
        guard LivePriceManager.shared.hasReceivedFreshData else { return nil }
        // Last resort: derive from sparkline (most accurate for 7d since sparkline covers 7 days)
        return derived7dPercent(anchorPrice: priceUsd)
    }

    // Fractions (e.g., 0.051 == 5.1%) derived from best percents.
    var best24hFraction: Double? { best24hPercent.map { $0 / 100.0 } }
    var best1hFraction: Double? { best1hPercent.map { $0 / 100.0 } }
    var best7dFraction: Double? { best7dPercent.map { $0 / 100.0 } }

    /// Best-available percent change for a given chart timeframe.
    /// - Note: Supports 1h, 24h (and live), and 7d mappings. Other timeframes return nil.
    func bestPercent(for timeframe: ChartTimeframe) -> Double? {
        switch timeframe {
        case .oneHour:
            return best1hPercent
        case .oneDay, .live:
            return best24hPercent
        case .oneWeek:
            return best7dPercent
        default:
            return nil
        }
    }

    /// Fraction form (e.g., 0.051 == 5.1%) for a given chart timeframe where applicable.
    func bestFraction(for timeframe: ChartTimeframe) -> Double? {
        bestPercent(for: timeframe).map { $0 / 100.0 }
    }

    // MARK: - Optional: per-coin 24h volatility proxy
    /// Estimated 24h volatility for this coin as the standard deviation of hourly returns over ~24h.
    /// Uses the 7D sparkline as a data source. Result is in percent units.
    var derived24hVolatilityPercent: Double? {
        let series = sparklineIn7d.filter { $0.isFinite && $0 > 0 }
        guard series.count >= 4 else { return nil }
        let n = series.count
        
        // SMART STEP CALCULATION: Detect actual data coverage based on point count
        let stepHours: Double = {
            if n >= 140 && n <= 200 { return 1.0 }  // Hourly data
            else if n >= 35 && n < 140 { return 4.0 }  // 4-hour interval
            else if n >= 5 && n < 35 { return 24.0 }  // Daily data
            else { return (24.0 * 7.0) / Double(max(1, n - 1)) }  // Fallback
        }()
        let pointsPerHour = max(1, Int(round(1.0 / stepHours)))
        let window = max(3, min(n - 1, pointsPerHour * 24))
        let startIdx = max(0, (n - 1) - window)
        var returns: [Double] = []
        var prev: Double? = nil
        for i in startIdx..<(n) {
            let v = series[i]
            if let p = prev, p > 0 {
                returns.append((v / p) - 1.0)
            }
            prev = v
        }
        guard returns.count >= 2 else { return nil }
        let mean = returns.reduce(0, +) / Double(returns.count)
        // Use sample variance (n-1) for unbiased estimation
        let variance = returns.reduce(0) { $0 + pow($1 - mean, 2) } / Double(returns.count - 1)
        let std = sqrt(variance)
        let pct = std * 100.0
        if !pct.isFinite { return nil }
        return max(0, min(100, pct))
    }
}

