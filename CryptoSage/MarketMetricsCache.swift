import Foundation

public struct EngineOutputs {
    public let display: [Double]
    public let canonical: [Double]
    public let isPositive7D: Bool
    public let oneHFrac: Double
    public let dayFrac: Double
}

public actor MarketMetricsCache {
    public static let shared = MarketMetricsCache()
    
    private var cache: [String: (Date, EngineOutputs)] = [:]
    
    public func compute(
        symbol: String,
        rawSeries: [Double],
        livePrice: Double?,
        provider1h: Double?,
        provider24h: Double?,
        isStable: Bool,
        seriesSpanHours: Double?,
        targetPoints: Int
    ) async -> EngineOutputs {
        
        let key = Self.makeCacheKey(
            symbol: symbol,
            rawSeries: rawSeries,
            livePrice: livePrice,
            provider1h: provider1h,
            provider24h: provider24h,
            isStable: isStable,
            targetPoints: targetPoints
        )
        
        let now = Date()
        if let (date, cached) = cache[key], now.timeIntervalSince(date) <= 60 {
            return cached
        }
        
        let computed = MarketMetricsEngine.computeAllV2(
            rawSeries: rawSeries,
            livePrice: livePrice,
            provider1h: provider1h,
            provider24h: provider24h,
            isStable: isStable,
            seriesSpanHours: seriesSpanHours,
            targetPoints: targetPoints
        )
        
        let result = EngineOutputs(
            display: computed.display,
            canonical: computed.canonical,
            isPositive7D: computed.isPositive7D,
            oneHFrac: computed.oneHFrac,
            dayFrac: computed.dayFrac
        )
        
        cache[key] = (now, result)
        
        let sym = symbol.uppercased()
        await MainActor.run {
            if !LiveChangeService.shared.haveCoverage(symbol: sym, hours: 24) {
                LiveChangeService.shared.seed(symbol: sym, series: result.canonical, livePrice: livePrice)
            } else if !LiveChangeService.shared.haveCoverage(symbol: sym, hours: 1) {
                LiveChangeService.shared.seed(symbol: sym, series: result.canonical, livePrice: livePrice)
            }
        }
        
        return result
    }
    
    public func cached(
        symbol: String,
        rawSeries: [Double],
        livePrice: Double?,
        provider1h: Double?,
        provider24h: Double?,
        isStable: Bool,
        targetPoints: Int
    ) -> EngineOutputs? {
        let key = Self.makeCacheKey(
            symbol: symbol,
            rawSeries: rawSeries,
            livePrice: livePrice,
            provider1h: provider1h,
            provider24h: provider24h,
            isStable: isStable,
            targetPoints: targetPoints
        )
        return cache[key]?.1
    }
    
    private static func makeCacheKey(
        symbol: String,
        rawSeries: [Double],
        livePrice: Double?,
        provider1h: Double?,
        provider24h: Double?,
        isStable: Bool,
        targetPoints: Int
    ) -> String {
        let symKey = symbol.uppercased()
        let rawKey = quantizeArray(rawSeries)
        let livePriceKey = quantize(livePrice)
        let p1hKey = quantize(provider1h)
        let p24hKey = quantize(provider24h)
        let stableKey = isStable ? "1" : "0"
        return "\(symKey)|\(rawKey)|\(livePriceKey)|\(p1hKey)|\(p24hKey)|\(stableKey)|\(targetPoints)"
    }
    
    private static func quantize(_ v: Double?) -> String {
        guard let v = v else { return "n" }
        return String(format: "%.6g", v)
    }
    
    private static func quantizeArray(_ array: [Double]) -> String {
        guard !array.isEmpty else { return "0,n,n" }
        let first = quantize(array.first)
        let last = quantize(array.last)
        return "\(array.count),\(first),\(last)"
    }
}
