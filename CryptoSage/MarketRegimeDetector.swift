//
//  MarketRegimeDetector.swift
//  CryptoSage
//
//  Detects current market regime (trending, ranging, volatile) to adjust
//  indicator weights and prediction methodology accordingly.
//

import Foundation
import SwiftUI

// MARK: - Market Regime Types

/// Represents the current market regime/condition
public enum MarketRegime: String, Codable {
    case trendingUp = "Trending Up"
    case trendingDown = "Trending Down"
    case ranging = "Range-Bound"
    case highVolatility = "High Volatility"
    case lowVolatility = "Low Volatility"
    case breakoutPotential = "Breakout Setup"
    
    /// Display name for UI
    public var displayName: String {
        rawValue
    }
    
    /// Icon for the regime
    public var icon: String {
        switch self {
        case .trendingUp: return "arrow.up.right"
        case .trendingDown: return "arrow.down.right"
        case .ranging: return "arrow.left.arrow.right"
        case .highVolatility: return "waveform.path.ecg"
        case .lowVolatility: return "minus"
        case .breakoutPotential: return "arrow.up.forward.and.arrow.down.backward"
        }
    }
    
    /// Color for the regime
    public var color: Color {
        switch self {
        case .trendingUp: return .green
        case .trendingDown: return .red
        case .ranging: return .yellow
        case .highVolatility: return .orange
        case .lowVolatility: return .blue
        case .breakoutPotential: return .purple
        }
    }
    
    /// Indicator weight adjustments for this regime
    /// Different regimes favor different types of indicators
    public var indicatorWeights: [String: Double] {
        switch self {
        case .trendingUp, .trendingDown:
            // In trends: favor trend-following indicators
            return [
                "MA": 0.85,      // Moving averages work well in trends
                "MACD": 0.80,    // MACD confirms momentum
                "ADX": 0.75,     // ADX validates trend strength
                "RSI": 0.45,     // RSI less reliable (can stay overbought/oversold)
                "BB": 0.40,      // Bollinger bands less useful
                "Volume": 0.70   // Volume confirms trend
            ]
        case .ranging:
            // In ranges: favor oscillators, mean reversion
            return [
                "MA": 0.35,      // MAs give false signals
                "MACD": 0.45,    // MACD whipsaws
                "ADX": 0.40,     // ADX confirms range
                "RSI": 0.85,     // RSI excellent for ranges
                "BB": 0.80,      // Bollinger bounces work
                "Volume": 0.50   // Volume less meaningful
            ]
        case .highVolatility:
            // High vol: reduce all confidence, widen ranges
            return [
                "MA": 0.50,
                "MACD": 0.55,
                "ADX": 0.60,
                "RSI": 0.50,
                "BB": 0.65,      // BB useful for volatility assessment
                "Volume": 0.70   // Volume spikes matter
            ]
        case .lowVolatility:
            // Low vol: potential breakout setup, watch for range expansion
            return [
                "MA": 0.60,
                "MACD": 0.60,
                "ADX": 0.55,
                "RSI": 0.65,
                "BB": 0.85,      // BB squeeze is key signal
                "Volume": 0.60
            ]
        case .breakoutPotential:
            // Breakout setup: watch for confirmation
            return [
                "MA": 0.70,
                "MACD": 0.75,
                "ADX": 0.80,     // ADX rising from low = breakout starting
                "RSI": 0.55,
                "BB": 0.85,      // BB expansion confirms breakout
                "Volume": 0.85   // Volume confirmation crucial
            ]
        }
    }
    
    /// Analysis implications for this regime
    public var implications: String {
        switch self {
        case .trendingUp:
            return "Favor long positions, use pullbacks to enter, trail stops"
        case .trendingDown:
            return "Favor short positions or stay out, avoid catching falling knives"
        case .ranging:
            return "Trade the range boundaries, buy support, sell resistance"
        case .highVolatility:
            return "Reduce position size, widen stops, expect large swings"
        case .lowVolatility:
            return "Prepare for breakout, watch for volume expansion"
        case .breakoutPotential:
            return "Watch for breakout confirmation, enter on volume spike"
        }
    }
    
    /// Confidence adjustment for predictions in this regime
    /// Some regimes are inherently harder to predict
    public var confidenceMultiplier: Double {
        switch self {
        case .trendingUp, .trendingDown:
            return 1.1  // Trends are more predictable
        case .ranging:
            return 0.95 // Ranges somewhat predictable
        case .highVolatility:
            return 0.75 // High vol = low predictability
        case .lowVolatility:
            return 0.85 // Calm before storm - uncertain
        case .breakoutPotential:
            return 0.80 // Direction uncertain until confirmed
        }
    }
}

// MARK: - Regime Detection Result

/// Result of regime detection with supporting data
public struct RegimeDetectionResult {
    public let regime: MarketRegime
    public let confidence: Double  // 0-100
    public let adxValue: Double?
    public let atrPercent: Double?
    public let trendDirection: String?  // "up", "down", "neutral"
    public let rangeTightness: Double?  // 0-1, how tight the range is
    public let detectedAt: Date
    
    public init(
        regime: MarketRegime,
        confidence: Double,
        adxValue: Double? = nil,
        atrPercent: Double? = nil,
        trendDirection: String? = nil,
        rangeTightness: Double? = nil
    ) {
        self.regime = regime
        self.confidence = confidence
        self.adxValue = adxValue
        self.atrPercent = atrPercent
        self.trendDirection = trendDirection
        self.rangeTightness = rangeTightness
        self.detectedAt = Date()
    }
    
    /// Summary string for logging/display
    public var summary: String {
        var parts: [String] = [regime.displayName]
        parts.append("(\(Int(confidence))% conf)")
        if let adx = adxValue {
            parts.append("ADX:\(String(format: "%.0f", adx))")
        }
        if let atr = atrPercent {
            parts.append("ATR:\(String(format: "%.1f", atr))%")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Market Regime Detector

/// Detects market regime from price data and technical indicators
public struct MarketRegimeDetector {
    
    // MARK: - Configuration
    
    /// ADX threshold for trend vs range
    private static let adxTrendThreshold: Double = 25.0
    private static let adxStrongTrendThreshold: Double = 40.0
    private static let adxWeakThreshold: Double = 20.0
    
    /// ATR thresholds for volatility (as % of price)
    private static let atrHighVolThreshold: Double = 5.0   // >5% daily ATR = high vol
    private static let atrLowVolThreshold: Double = 1.5    // <1.5% daily ATR = low vol
    
    /// Range tightness threshold for breakout potential
    private static let rangeTightnessThreshold: Double = 0.6
    
    // MARK: - Main Detection Method
    
    /// Detect market regime from price data
    /// - Parameters:
    ///   - closes: Array of closing prices (newest last)
    ///   - currentPrice: Current price (optional, uses last close if nil)
    /// - Returns: RegimeDetectionResult with regime and supporting data
    public static func detectRegime(
        closes: [Double],
        currentPrice: Double? = nil
    ) -> RegimeDetectionResult {
        guard closes.count >= 14 else {
            // Insufficient data - default to neutral
            return RegimeDetectionResult(
                regime: .ranging,
                confidence: 30,
                trendDirection: "neutral"
            )
        }
        
        // Calculate ADX for trend strength
        let adxResult = TechnicalsEngine.adxApprox(closes)
        let adx = adxResult?.adx
        let plusDI = adxResult?.plusDI
        let minusDI = adxResult?.minusDI
        
        // Calculate ATR for volatility
        let atrResult = TechnicalsEngine.atrApproxFromCloses(closes, period: 14)
        let atrPercent = atrResult?.atrPercent
        
        // Calculate MA alignment for trend direction
        let maResult = closes.count >= 50 ? TechnicalsEngine.maAlignment(closes: closes) : nil
        
        // Calculate range tightness
        let rangeResult = TechnicalsEngine.rangeTightness(closes: closes, period: 10)
        let rangeTightness = rangeResult?.ratio
        
        // Determine trend direction from DI crossover and MA alignment
        var trendDirection = "neutral"
        if let plus = plusDI, let minus = minusDI {
            if plus > minus + 5 {
                trendDirection = "up"
            } else if minus > plus + 5 {
                trendDirection = "down"
            }
        }
        
        // Override with MA alignment if available and strong
        if let ma = maResult {
            if ma.order == "bullish_perfect" || (ma.order == "bullish_partial" && ma.allInclining) {
                trendDirection = "up"
            } else if ma.order == "bearish_perfect" || (ma.order == "bearish_partial" && !ma.allInclining) {
                trendDirection = "down"
            }
        }
        
        // Determine regime based on indicators
        let (regime, confidence) = classifyRegime(
            adx: adx,
            atrPercent: atrPercent,
            trendDirection: trendDirection,
            rangeTightness: rangeTightness
        )
        
        return RegimeDetectionResult(
            regime: regime,
            confidence: confidence,
            adxValue: adx,
            atrPercent: atrPercent,
            trendDirection: trendDirection,
            rangeTightness: rangeTightness
        )
    }
    
    // MARK: - Classification Logic
    
    private static func classifyRegime(
        adx: Double?,
        atrPercent: Double?,
        trendDirection: String,
        rangeTightness: Double?
    ) -> (MarketRegime, Double) {
        
        var regime: MarketRegime = .ranging
        var confidence: Double = 50.0
        
        let hasADX = adx != nil
        let hasATR = atrPercent != nil
        let hasTightness = rangeTightness != nil
        
        // Priority 1: Check for high volatility (overrides other signals)
        if let atr = atrPercent, atr > atrHighVolThreshold {
            regime = .highVolatility
            confidence = min(90, 60 + (atr - atrHighVolThreshold) * 5)
            return (regime, confidence)
        }
        
        // Priority 2: Check for strong trend
        if let adx = adx, adx >= adxTrendThreshold {
            if trendDirection == "up" {
                regime = .trendingUp
                confidence = min(95, 60 + (adx - adxTrendThreshold) * 1.5)
            } else if trendDirection == "down" {
                regime = .trendingDown
                confidence = min(95, 60 + (adx - adxTrendThreshold) * 1.5)
            } else {
                // Strong ADX but no clear direction - unusual
                regime = .highVolatility
                confidence = 55
            }
            return (regime, confidence)
        }
        
        // Priority 3: Check for low volatility / breakout potential
        if let atr = atrPercent, atr < atrLowVolThreshold {
            if let tightness = rangeTightness, tightness < rangeTightnessThreshold {
                // Low ATR + tightening range = breakout potential
                regime = .breakoutPotential
                confidence = 70 + (rangeTightnessThreshold - tightness) * 30
            } else {
                regime = .lowVolatility
                confidence = 65
            }
            return (regime, confidence)
        }
        
        // Priority 4: Range-bound (weak ADX)
        if let adx = adx, adx < adxWeakThreshold {
            regime = .ranging
            confidence = 70 - adx  // Lower ADX = more confident it's ranging
            return (regime, confidence)
        }
        
        // Default: mild trend or uncertain
        if hasADX {
            if trendDirection == "up" {
                regime = .trendingUp
                confidence = 50
            } else if trendDirection == "down" {
                regime = .trendingDown
                confidence = 50
            } else {
                regime = .ranging
                confidence = 45
            }
        } else {
            // No ADX data - use ATR and tightness
            if hasATR && hasTightness {
                regime = .ranging
                confidence = 40
            } else {
                regime = .ranging
                confidence = 30
            }
        }
        
        return (regime, confidence)
    }
    
    // MARK: - Convenience Methods
    
    /// Quick check if market is in a trending state
    public static func isTrending(closes: [Double]) -> Bool {
        let result = detectRegime(closes: closes)
        return result.regime == .trendingUp || result.regime == .trendingDown
    }
    
    /// Quick check if market is ranging
    public static func isRanging(closes: [Double]) -> Bool {
        let result = detectRegime(closes: closes)
        return result.regime == .ranging
    }
    
    /// Quick check if market is volatile
    public static func isVolatile(closes: [Double]) -> Bool {
        let result = detectRegime(closes: closes)
        return result.regime == .highVolatility
    }
    
    /// Get indicator weight for a specific indicator in current regime
    public static func indicatorWeight(for indicator: String, in closes: [Double]) -> Double {
        let result = detectRegime(closes: closes)
        return result.regime.indicatorWeights[indicator] ?? 0.5
    }
}

// MARK: - Cache for Regime Detection

/// Caches regime detection results to avoid redundant calculations
@MainActor
public final class MarketRegimeCache: ObservableObject {
    public static let shared = MarketRegimeCache()
    
    @Published public private(set) var cachedRegimes: [String: RegimeDetectionResult] = [:]
    
    private let cacheValiditySeconds: TimeInterval = 300  // 5 minutes
    
    private init() {}
    
    /// Get or calculate regime for a symbol
    public func regime(for symbol: String, closes: [Double]) -> RegimeDetectionResult {
        let key = symbol.uppercased()
        
        // Check cache
        if let cached = cachedRegimes[key],
           Date().timeIntervalSince(cached.detectedAt) < cacheValiditySeconds {
            return cached
        }
        
        // Calculate and cache
        let result = MarketRegimeDetector.detectRegime(closes: closes)
        cachedRegimes[key] = result
        return result
    }
    
    /// Clear cache for a symbol or all symbols
    public func clearCache(for symbol: String? = nil) {
        if let sym = symbol {
            cachedRegimes.removeValue(forKey: sym.uppercased())
        } else {
            cachedRegimes.removeAll()
        }
    }
}
