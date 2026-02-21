//
//  AITradingSignalService.swift
//  CryptoSage
//
//  AI-powered trading signal service.
//  Calls the getTradingSignal Firebase Cloud Function (DeepSeek V3.2)
//  with local algorithmic fallback for offline/error scenarios.
//

import Foundation

// MARK: - AI Trading Signal Service

/// Service that fetches AI-powered trading signals from Firebase Cloud Functions.
/// Falls back to local technical analysis when Firebase is unavailable.
final class AITradingSignalService {
    static let shared = AITradingSignalService()
    
    /// In-memory cache to avoid redundant calls within the same session
    private var cache: [String: CachedSignal] = [:]
    private let cacheDuration: TimeInterval = 5 * 60 // 5 minutes local cache
    
    private struct CachedSignal {
        let signal: TradingSignal
        let timestamp: Date
    }
    
    private init() {}

    // MARK: - Canonical Signal Keys

    /// Canonicalize market identifiers so fetch/clear/read paths use the same key.
    private static func canonicalIdentifier(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Canonical in-memory key used by this service for all signal cache operations.
    static func canonicalSignalKey(for coinId: String) -> String {
        let normalized = canonicalIdentifier(coinId)
        if normalized.hasPrefix("stock-") {
            let suffix = String(normalized.dropFirst("stock-".count))
            return "stock-\(canonicalIdentifier(suffix))"
        }
        if normalized.hasPrefix("commodity-") {
            let suffix = String(normalized.dropFirst("commodity-".count))
            return "commodity-\(canonicalIdentifier(suffix))"
        }
        return normalized
    }

    static func stockSignalCoinId(symbol: String) -> String {
        "stock-\(canonicalIdentifier(symbol))"
    }

    static func commoditySignalCoinId(identifier: String) -> String {
        "commodity-\(canonicalIdentifier(identifier))"
    }
    
    /// Public read-only access to cached signals for AI context building.
    /// Returns all non-expired cached signals as (coinId, signal) pairs.
    var cachedSignalsList: [(coinId: String, signal: TradingSignal)] {
        let now = Date()
        return cache.compactMap { (key, cached) in
            guard now.timeIntervalSince(cached.timestamp) < cacheDuration else { return nil }
            return (coinId: key, signal: cached.signal)
        }
    }
    
    // MARK: - Public API
    
    /// Fetch an AI trading signal for a coin.
    /// Tries Firebase first (DeepSeek AI), falls back to local algorithmic analysis.
    ///
    /// - Parameters:
    ///   - coinId: CoinGecko coin ID (e.g., "bitcoin")
    ///   - symbol: Coin symbol (e.g., "BTC")
    ///   - price: Current price
    ///   - change24h: 24-hour price change percentage
    ///   - change7d: 7-day price change percentage (optional)
    ///   - sparkline: 7-day sparkline prices for local fallback
    ///   - techVM: TechnicalsViewModel for indicator data
    ///   - fearGreedValue: Current Fear & Greed index value (0-100)
    /// - Returns: A `TradingSignal` with AI reasoning or local analysis
    func fetchSignal(
        coinId: String,
        symbol: String,
        price: Double,
        change24h: Double,
        change7d: Double?,
        sparkline: [Double],
        techVM: TechnicalsViewModel?,
        fearGreedValue: Int?
    ) async -> TradingSignal {
        let signalKey = Self.canonicalSignalKey(for: coinId)

        // Check local in-memory cache first
        if let cached = cache[signalKey],
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.signal
        }
        
        // Pre-extract technicals summary on MainActor (safe access)
        let summarySnapshot: TechnicalsSummary? = await {
            if let techVM = techVM {
                return await MainActor.run { techVM.summary }
            }
            return nil
        }()
        
        // Try Firebase AI signal
        do {
            let signal = try await fetchFromFirebase(
                coinId: signalKey,
                symbol: symbol,
                price: price,
                change24h: change24h,
                change7d: change7d,
                summary: summarySnapshot,
                fearGreedValue: fearGreedValue
            )
            
            // Cache the result
            cache[signalKey] = CachedSignal(signal: signal, timestamp: Date())
            return signal
        } catch {
            #if DEBUG
            print("[AITradingSignalService] Firebase failed (\(error.localizedDescription)), using local fallback")
            #endif
            
            // Fall back to local algorithmic calculation
            let signal = calculateLocalSignal(
                sparkline: sparkline,
                price: price,
                change24h: change24h,
                summary: summarySnapshot,
                fearGreedValue: fearGreedValue
            )
            
            // Cache even the fallback (avoid hammering failed Firebase)
            cache[signalKey] = CachedSignal(signal: signal, timestamp: Date())
            return signal
        }
    }
    
    /// Clear cached signal for a specific coin (e.g., on pull-to-refresh)
    func clearCache(for coinId: String) {
        cache.removeValue(forKey: Self.canonicalSignalKey(for: coinId))
    }

    /// Return a fresh cached signal if available.
    func cachedSignal(for coinId: String) -> TradingSignal? {
        let signalKey = Self.canonicalSignalKey(for: coinId)
        guard let cached = cache[signalKey] else { return nil }
        guard Date().timeIntervalSince(cached.timestamp) < cacheDuration else {
            cache.removeValue(forKey: signalKey)
            return nil
        }
        return cached.signal
    }

    /// Build an immediate local preview signal so UI can render instantly
    /// while the Firebase-backed signal request is still in flight.
    func localPreviewSignal(
        symbol: String,
        price: Double,
        change24h: Double,
        sparkline: [Double],
        techVM: TechnicalsViewModel?,
        fearGreedValue: Int?
    ) async -> TradingSignal {
        let summarySnapshot: TechnicalsSummary? = await {
            if let techVM = techVM {
                return await MainActor.run { techVM.summary }
            }
            return nil
        }()

        return calculateLocalSignal(
            sparkline: sparkline,
            price: price,
            change24h: change24h,
            summary: summarySnapshot,
            fearGreedValue: fearGreedValue
        )
    }
    
    /// Clear all cached signals
    func clearAllCache() {
        cache.removeAll()
    }
    
    // MARK: - Firebase AI Signal
    
    private func fetchFromFirebase(
        coinId: String,
        symbol: String,
        price: Double,
        change24h: Double,
        change7d: Double?,
        summary: TechnicalsSummary?,
        fearGreedValue: Int?
    ) async throws -> TradingSignal {
        // Build technical indicators dictionary from the pre-extracted summary
        var indicators: [String: Any] = [:]
        
        if let summary = summary {
            // Extract indicator values from the summary
            for indicator in summary.indicators {
                switch indicator.label {
                case "RSI(14)":
                    if let value = indicator.valueText, let rsi = Double(value) {
                        indicators["rsi"] = rsi
                    }
                case "MACD(12,26,9)":
                    if let value = indicator.valueText {
                        indicators["macdSignal"] = value
                    }
                case "Stoch RSI":
                    if let value = indicator.valueText {
                        indicators["stochRSI"] = value
                    }
                case "ADX(14)":
                    if let value = indicator.valueText, let adx = Double(value) {
                        indicators["adx"] = adx
                    }
                case "SMA(20)":
                    if let value = indicator.valueText, let sma = Double(value) {
                        indicators["sma20"] = sma
                    }
                case "SMA(50)":
                    if let value = indicator.valueText, let sma = Double(value) {
                        indicators["sma50"] = sma
                    }
                case "EMA(12)":
                    if let value = indicator.valueText, let ema = Double(value) {
                        indicators["ema12"] = ema
                    }
                case "EMA(26)":
                    if let value = indicator.valueText, let ema = Double(value) {
                        indicators["ema26"] = ema
                    }
                default:
                    break
                }
            }
            
            // Add trend/volatility context if available
            if let trendStrength = summary.trendStrength {
                indicators["maTrend"] = trendStrength
            }
            if let volatility = summary.volatilityRegime {
                indicators["volumeTrend"] = volatility
            }
            if let bbPos = summary.indicators.first(where: { $0.label.contains("Bollinger") })?.valueText {
                indicators["bollingerPosition"] = bbPos
            }
        }
        
        let response = try await FirebaseService.shared.getTradingSignal(
            coinId: coinId,
            symbol: symbol,
            currentPrice: price,
            change24h: change24h,
            change7d: change7d,
            technicalIndicators: indicators.isEmpty ? nil : indicators,
            fearGreedIndex: fearGreedValue
        )
        
        // Parse the response timestamp
        let updatedAt: Date
        if let date = ISO8601DateFormatter().date(from: response.updatedAt) {
            updatedAt = date
        } else {
            updatedAt = Date()
        }
        
        // Map response to TradingSignal model
        let signalType: TradingSignalType
        switch response.signal.uppercased() {
        case "BUY": signalType = .buy
        case "SELL": signalType = .sell
        default: signalType = .hold
        }
        
        return TradingSignal(
            type: signalType,
            confidence: Double(response.confidenceScore) / 100.0,
            confidenceLabel: response.confidence,
            reasons: response.keyFactors,
            reasoning: response.reasoning,
            sentimentScore: response.sentimentScore,
            riskLevel: response.riskLevel,
            timestamp: updatedAt,
            isAIPowered: true
        )
    }
    
    // MARK: - Local Algorithmic Fallback
    
    /// Local signal calculation (same algorithm as before, used as offline fallback)
    private func calculateLocalSignal(
        sparkline: [Double],
        price: Double,
        change24h: Double,
        summary: TechnicalsSummary?,
        fearGreedValue: Int?
    ) -> TradingSignal {
        var bullishPoints = 0
        var bearishPoints = 0
        var reasons: [String] = []
        
        // RSI analysis - prefer chart RSI for consistency
        let rsi: Double? = {
            if let summary = summary {
                if let rsiInd = summary.indicators.first(where: { $0.label == "RSI(14)" }),
                   let value = rsiInd.valueText,
                   let rsiVal = Double(value), rsiVal.isFinite {
                    return rsiVal
                }
            }
            if sparkline.count >= 14 {
                return TechnicalsEngine.rsi(sparkline, period: 14)
            }
            return nil
        }()
        
        if let rsi = rsi {
            if rsi < 30 {
                bullishPoints += 2
                reasons.append("RSI oversold at \(Int(rsi))")
            } else if rsi < 40 {
                bullishPoints += 1
                reasons.append("RSI near oversold (\(Int(rsi)))")
            } else if rsi > 70 {
                bearishPoints += 2
                reasons.append("RSI overbought at \(Int(rsi))")
            } else if rsi > 60 {
                bearishPoints += 1
                reasons.append("RSI elevated (\(Int(rsi)))")
            }
        }
        
        // MACD analysis
        if sparkline.count >= 26 {
            if let macdResult = TechnicalsEngine.macdLineSignal(sparkline) {
                if macdResult.macd > macdResult.signal {
                    bullishPoints += 1
                    reasons.append("MACD bullish crossover")
                } else {
                    bearishPoints += 1
                    reasons.append("MACD bearish")
                }
            }
        }
        
        // Trend analysis (SMA)
        if sparkline.count >= 20 {
            if let sma20 = TechnicalsEngine.sma(sparkline, period: 20), sma20 > 0 {
                if price > sma20 * 1.02 {
                    bullishPoints += 1
                    reasons.append("Above 20 SMA")
                } else if price < sma20 * 0.98 {
                    bearishPoints += 1
                    reasons.append("Below 20 SMA")
                }
            }
        }
        
        // Momentum (7D from sparkline)
        if let first = sparkline.first, let last = sparkline.last, first > 0 {
            let momentum = ((last - first) / first) * 100
            if momentum > 10 {
                bullishPoints += 1
                reasons.append("Strong 7D momentum (+\(String(format: "%.0f", momentum))%)")
            } else if momentum < -10 {
                bearishPoints += 1
                reasons.append("Weak 7D momentum (\(String(format: "%.0f", momentum))%)")
            }
        }
        
        // 24h momentum
        if change24h > 5 {
            bullishPoints += 1
            reasons.append("Strong 24h gain (+\(String(format: "%.1f", change24h))%)")
        } else if change24h < -5 {
            bearishPoints += 1
            reasons.append("Sharp 24h decline (\(String(format: "%.1f", change24h))%)")
        }
        
        // Market sentiment
        if let sentiment = fearGreedValue {
            if sentiment < 25 {
                bullishPoints += 1
                reasons.append("Extreme fear (contrarian)")
            } else if sentiment > 75 {
                bearishPoints += 1
                reasons.append("Extreme greed (caution)")
            }
        }
        
        // Determine signal
        let totalPoints = bullishPoints + bearishPoints
        let confidence: Double
        let signal: TradingSignalType
        
        if totalPoints == 0 {
            signal = .hold
            confidence = 0.5
        } else if bullishPoints > bearishPoints + 1 {
            signal = .buy
            confidence = min(0.9, 0.5 + Double(bullishPoints - bearishPoints) * 0.1)
        } else if bearishPoints > bullishPoints + 1 {
            signal = .sell
            confidence = min(0.9, 0.5 + Double(bearishPoints - bullishPoints) * 0.1)
        } else {
            signal = .hold
            confidence = 0.5
        }
        
        // Build a reasoning sentence from the local analysis
        let reasoning: String
        switch signal {
        case .buy:
            reasoning = "Local analysis: \(bullishPoints) bullish vs \(bearishPoints) bearish indicators suggest upside potential."
        case .sell:
            reasoning = "Local analysis: \(bearishPoints) bearish vs \(bullishPoints) bullish indicators suggest downside pressure."
        case .hold:
            reasoning = "Local analysis: Mixed signals with \(bullishPoints) bullish and \(bearishPoints) bearish indicators. No clear edge."
        }
        
        let confidenceLabel: String
        if confidence >= 0.7 { confidenceLabel = "High" }
        else if confidence >= 0.55 { confidenceLabel = "Medium" }
        else { confidenceLabel = "Low" }
        
        // Map confidence to sentiment score
        let sentimentScore: Double
        switch signal {
        case .buy: sentimentScore = confidence
        case .sell: sentimentScore = -confidence
        case .hold: sentimentScore = 0
        }
        
        return TradingSignal(
            type: signal,
            confidence: confidence,
            confidenceLabel: confidenceLabel,
            reasons: reasons,
            reasoning: reasoning,
            sentimentScore: sentimentScore,
            riskLevel: totalPoints <= 2 ? "Low" : (totalPoints <= 4 ? "Medium" : "High"),
            timestamp: Date(),
            isAIPowered: false
        )
    }
}
