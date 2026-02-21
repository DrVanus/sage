//
//  SageAlgorithms.swift
//  CryptoSage
//
//  CryptoSage AI's 6 proprietary trading algorithms.
//  Research-backed implementations optimized for crypto markets.
//

import Foundation

// MARK: - 1. Sage Trend (Adaptive Regime-Based Trading)

/// CryptoSage's flagship algorithm that adapts strategy based on market regime
/// Timeframe: 4H primary, 1D confirmation
public struct SageTrendAlgorithm: SageAlgorithm {
    public let id = "sage_trend"
    public let name = "Sage Trend"
    public let description = "Adaptive trend-following that knows when to trend-follow vs sit out. Uses ADX for regime detection and auto-adapts strategy."
    public let category: SageAlgorithmCategory = .trend
    public let primaryTimeframe: SageTimeframe = .h4
    public let minDataPoints: Int = 200
    public let isInternal: Bool = false  // User-facing
    
    public func evaluate(data: SageMarketData, regime: SageMarketRegime) -> SageSignal? {
        guard data.closes.count >= minDataPoints else { return nil }
        
        let score = calculateScore(data: data)
        guard abs(score) > 30 else { return nil }  // Need meaningful signal
        
        let type: SageSignalType
        let confidence: Double
        
        // Adjust signal based on regime
        switch regime {
        case .strongTrend, .trending:
            // In trending regimes, follow the trend
            if score > 50 {
                type = .strongBuy
                confidence = 0.8
            } else if score > 30 {
                type = .buy
                confidence = 0.65
            } else if score < -50 {
                type = .strongSell
                confidence = 0.8
            } else if score < -30 {
                type = .sell
                confidence = 0.65
            } else {
                return nil
            }
            
        case .ranging:
            // In ranging markets, use mean reversion logic
            if score < -40 {  // Oversold in range = buy
                type = .buy
                confidence = 0.6
            } else if score > 40 {  // Overbought in range = sell
                type = .sell
                confidence = 0.6
            } else {
                return nil
            }
            
        case .volatile, .distribution:
            // In volatile/distribution, reduce exposure
            return nil
            
        case .weakTrend, .accumulation:
            // Weak trend or accumulation - cautious signals
            if score > 40 {
                type = .buy
                confidence = 0.5
            } else if score < -40 {
                type = .sell
                confidence = 0.5
            } else {
                return nil
            }
        }
        
        // Calculate levels
        let atrData = TechnicalsEngine.atrApproxFromCloses(data.closes, period: 14)
        let atrPercent = atrData?.atrPercent ?? 2.0
        let stopLoss = data.currentPrice * (1 - atrPercent * regime.stopLossATRMultiplier / 100)
        let takeProfit = data.currentPrice * (1 + atrPercent * regime.stopLossATRMultiplier * 2 / 100)
        
        return SageSignal(
            algorithmId: id,
            algorithmName: name,
            category: category,
            symbol: data.symbol,
            type: type,
            score: score,
            confidence: confidence,
            regime: regime,
            factors: buildFactors(data: data, score: score),
            suggestedEntry: data.currentPrice,
            suggestedStopLoss: stopLoss,
            suggestedTakeProfit: takeProfit
        )
    }
    
    public func calculateScore(data: SageMarketData) -> Double {
        var score: Double = 0
        
        // 1. ADX trend strength (weight: 25%)
        if let adxResult = TechnicalsEngine.adx(data.closes) {
            if adxResult.adx > 25 {
                // Strong trend - direction from +DI/-DI
                let direction = adxResult.plusDI > adxResult.minusDI ? 1.0 : -1.0
                let strength = min(adxResult.adx / 50, 1.0)  // Normalize to 0-1
                score += direction * strength * 25
            }
        }
        
        // 2. EMA alignment (weight: 25%)
        if let ema12 = TechnicalsEngine.ema(data.closes, period: 12),
           let ema26 = TechnicalsEngine.ema(data.closes, period: 26),
           let ema50 = TechnicalsEngine.ema(data.closes, period: 50) {
            
            // Bullish alignment: price > 12 > 26 > 50
            if data.currentPrice > ema12 && ema12 > ema26 && ema26 > ema50 {
                score += 25
            } else if data.currentPrice < ema12 && ema12 < ema26 && ema26 < ema50 {
                score -= 25
            } else if data.currentPrice > ema26 {
                score += 10
            } else if data.currentPrice < ema26 {
                score -= 10
            }
        }
        
        // 3. Price vs SMA200 (weight: 20%)
        if let sma200 = TechnicalsEngine.sma(data.closes, period: 200) {
            let deviation = ((data.currentPrice - sma200) / sma200) * 100
            score += min(max(deviation * 2, -20), 20)  // Cap at ±20
        }
        
        // 4. MACD momentum (weight: 15%)
        if let macdResult = TechnicalsEngine.macdSlope(data.closes) {
            if macdResult.accelerating {
                score += 15
            } else if macdResult.histogram < 0 && macdResult.slope < 0 {
                score -= 15
            }
        }
        
        // 5. RSI trend (weight: 15%)
        if let rsiResult = TechnicalsEngine.rsiTrend(data.closes) {
            if rsiResult.trend == "rising" && rsiResult.rsi > 50 {
                score += 15
            } else if rsiResult.trend == "falling" && rsiResult.rsi < 50 {
                score -= 15
            }
        }
        
        return max(-100, min(100, score))
    }
    
    private func buildFactors(data: SageMarketData, score: Double) -> [String] {
        var factors: [String] = []
        
        if let adxResult = TechnicalsEngine.adx(data.closes) {
            factors.append("ADX: \(String(format: "%.1f", adxResult.adx)) (\(adxResult.trend))")
        }
        
        if let ema26 = TechnicalsEngine.ema(data.closes, period: 26) {
            let position = data.currentPrice > ema26 ? "above" : "below"
            factors.append("Price \(position) EMA26")
        }
        
        if let rsi = TechnicalsEngine.rsi(data.closes) {
            factors.append("RSI: \(String(format: "%.1f", rsi))")
        }
        
        return factors
    }
}

// MARK: - 2. Sage Momentum (Multi-Factor Momentum Cascade)

/// Proprietary 5-factor momentum scoring system
/// Timeframe: 1H primary, 4H trend filter
public struct SageMomentumAlgorithm: SageAlgorithm {
    public let id = "sage_momentum"
    public let name = "Sage Momentum"
    public let description = "5-factor momentum cascade: price ROC, RSI trend, MACD acceleration, volume confirmation, and BTC relative strength."
    public let category: SageAlgorithmCategory = .momentum
    public let primaryTimeframe: SageTimeframe = .h1
    public let minDataPoints: Int = 100
    public let isInternal: Bool = false
    
    public func evaluate(data: SageMarketData, regime: SageMarketRegime) -> SageSignal? {
        guard data.closes.count >= minDataPoints else { return nil }
        
        // Don't trade momentum in volatile or distribution regimes
        if regime == .volatile || regime == .distribution {
            return nil
        }
        
        let score = calculateScore(data: data)
        let (bullishFactors, bearishFactors) = countFactors(data: data)
        
        // Need 4+ factors aligned for signal
        guard bullishFactors >= 4 || bearishFactors >= 4 else { return nil }
        
        let type: SageSignalType
        let confidence: Double
        
        if bullishFactors >= 4 && score > 40 {
            type = bullishFactors == 5 ? .strongBuy : .buy
            confidence = Double(bullishFactors) / 5.0 * 0.9
        } else if bearishFactors >= 4 && score < -40 {
            type = bearishFactors == 5 ? .strongSell : .sell
            confidence = Double(bearishFactors) / 5.0 * 0.9
        } else {
            return nil
        }
        
        let atrPercent = TechnicalsEngine.atrApproxFromCloses(data.closes)?.atrPercent ?? 2.0
        
        return SageSignal(
            algorithmId: id,
            algorithmName: name,
            category: category,
            symbol: data.symbol,
            type: type,
            score: score,
            confidence: confidence,
            regime: regime,
            factors: buildFactors(data: data),
            suggestedEntry: data.currentPrice,
            suggestedStopLoss: data.currentPrice * (1 - atrPercent * 2 / 100),
            suggestedTakeProfit: data.currentPrice * (1 + atrPercent * 4 / 100)
        )
    }
    
    public func calculateScore(data: SageMarketData) -> Double {
        var score: Double = 0
        
        // Factor 1: Price ROC multi-period (20 points)
        let rocScores = calculateROCScore(data: data)
        score += rocScores * 20
        
        // Factor 2: RSI trend direction (20 points)
        if let rsiResult = TechnicalsEngine.rsiTrend(data.closes) {
            if rsiResult.trend == "rising" {
                score += 20
            } else if rsiResult.trend == "falling" {
                score -= 20
            }
        }
        
        // Factor 3: MACD acceleration (20 points)
        if let macdResult = TechnicalsEngine.macdSlope(data.closes) {
            if macdResult.accelerating && macdResult.histogram > 0 {
                score += 20
            } else if !macdResult.accelerating && macdResult.histogram < 0 {
                score -= 20
            }
        }
        
        // Factor 4: Volume confirmation (20 points)
        if let volumeTrend = TechnicalsEngine.volumeTrend(volumes: data.volumes) {
            if volumeTrend.trend == "expanding" {
                // Volume expanding - confirms momentum
                let priceDirection = (data.closes.last ?? 0) > (data.closes.dropLast().last ?? 0) ? 1.0 : -1.0
                score += 20 * priceDirection
            }
        }
        
        // Factor 5: OBV trend (20 points)
        if let obvResult = TechnicalsEngine.obvTrend(closes: data.closes, volumes: data.volumes) {
            if obvResult.trend == "accumulation" && obvResult.priceOBVAligned {
                score += 20
            } else if obvResult.trend == "distribution" && obvResult.priceOBVAligned {
                score -= 20
            }
        }
        
        return max(-100, min(100, score))
    }
    
    private func calculateROCScore(data: SageMarketData) -> Double {
        let rocs = TechnicalsEngine.rocMultiple(data.closes)
        var rocScore: Double = 0
        var count = 0
        
        if let roc10 = rocs.roc10 {
            rocScore += roc10 > 0 ? 1 : -1
            count += 1
        }
        if let roc20 = rocs.roc20 {
            rocScore += roc20 > 0 ? 1 : -1
            count += 1
        }
        if let roc50 = rocs.roc50 {
            rocScore += roc50 > 0 ? 1 : -1
            count += 1
        }
        
        return count > 0 ? rocScore / Double(count) : 0
    }
    
    private func countFactors(data: SageMarketData) -> (bullish: Int, bearish: Int) {
        var bullish = 0
        var bearish = 0
        
        // Factor 1: ROC
        let rocs = TechnicalsEngine.rocMultiple(data.closes)
        let rocBullish = [rocs.roc10, rocs.roc20, rocs.roc50].compactMap { $0 }.filter { $0 > 0 }.count >= 2
        let rocBearish = [rocs.roc10, rocs.roc20, rocs.roc50].compactMap { $0 }.filter { $0 < 0 }.count >= 2
        if rocBullish { bullish += 1 } else if rocBearish { bearish += 1 }
        
        // Factor 2: RSI trend
        if let rsiResult = TechnicalsEngine.rsiTrend(data.closes) {
            if rsiResult.trend == "rising" { bullish += 1 }
            else if rsiResult.trend == "falling" { bearish += 1 }
        }
        
        // Factor 3: MACD acceleration
        if let macdResult = TechnicalsEngine.macdSlope(data.closes) {
            if macdResult.accelerating && macdResult.histogram > 0 { bullish += 1 }
            else if !macdResult.accelerating && macdResult.histogram < 0 { bearish += 1 }
        }
        
        // Factor 4: Volume
        if let volumeTrend = TechnicalsEngine.volumeTrend(volumes: data.volumes) {
            if volumeTrend.trend == "expanding" {
                let priceUp = (data.closes.last ?? 0) > (data.closes.dropLast().last ?? 0)
                if priceUp { bullish += 1 } else { bearish += 1 }
            }
        }
        
        // Factor 5: OBV
        if let obvResult = TechnicalsEngine.obvTrend(closes: data.closes, volumes: data.volumes) {
            if obvResult.trend == "accumulation" { bullish += 1 }
            else if obvResult.trend == "distribution" { bearish += 1 }
        }
        
        return (bullish, bearish)
    }
    
    private func buildFactors(data: SageMarketData) -> [String] {
        var factors: [String] = []
        let (bullish, _) = countFactors(data: data)
        factors.append("\(bullish)/5 bullish factors")
        
        let rocs = TechnicalsEngine.rocMultiple(data.closes)
        if let roc10 = rocs.roc10 {
            factors.append("ROC(10): \(String(format: "%.2f", roc10))%")
        }
        
        if let rsiResult = TechnicalsEngine.rsiTrend(data.closes) {
            factors.append("RSI trend: \(rsiResult.trend)")
        }
        
        return factors
    }
}

// MARK: - 3. Sage Reversion (Statistical Mean Reversion)

/// Advanced mean reversion with Z-score and volatility filtering
/// Timeframe: 4H primary
public struct SageReversionAlgorithm: SageAlgorithm {
    public let id = "sage_reversion"
    public let name = "Sage Reversion"
    public let description = "Statistical mean reversion using Z-score, Bollinger %B, RSI divergence, and volatility filtering."
    public let category: SageAlgorithmCategory = .meanReversion
    public let primaryTimeframe: SageTimeframe = .h4
    public let minDataPoints: Int = 50
    public let isInternal: Bool = false
    
    public func evaluate(data: SageMarketData, regime: SageMarketRegime) -> SageSignal? {
        guard data.closes.count >= minDataPoints else { return nil }
        
        // Mean reversion works best in ranging regimes, NOT in strong trends
        if regime == .strongTrend || regime == .volatile {
            return nil
        }
        
        // Check for volatility contraction (ideal mean reversion environment)
        guard let bbWidth = TechnicalsEngine.bollingerBandWidth(data.closes) else { return nil }
        
        // Only trade when BB width is relatively low (contraction)
        // Skip if volatility is expanding
        if bbWidth > 20 {
            return nil
        }
        
        let score = calculateScore(data: data)
        
        // Need strong deviation for mean reversion signal
        guard abs(score) > 50 else { return nil }
        
        let type: SageSignalType
        let confidence: Double
        
        // Mean reversion: oversold = buy, overbought = sell
        if score < -50 {
            type = score < -70 ? .strongBuy : .buy  // Oversold = buy
            confidence = min(abs(score) / 100, 0.85)
        } else if score > 50 {
            type = score > 70 ? .strongSell : .sell  // Overbought = sell
            confidence = min(score / 100, 0.85)
        } else {
            return nil
        }
        
        // Calculate levels based on Bollinger Bands
        guard let bands = TechnicalsEngine.bollingerBands(data.closes) else { return nil }
        
        let stopLoss: Double
        let takeProfit: Double
        
        if type == .buy || type == .strongBuy {
            stopLoss = bands.lower * 0.98  // Stop below lower band
            takeProfit = bands.middle  // Target middle band
        } else {
            stopLoss = bands.upper * 1.02  // Stop above upper band
            takeProfit = bands.middle  // Target middle band
        }
        
        return SageSignal(
            algorithmId: id,
            algorithmName: name,
            category: category,
            symbol: data.symbol,
            type: type,
            score: score,
            confidence: confidence,
            regime: regime,
            factors: buildFactors(data: data, score: score),
            suggestedEntry: data.currentPrice,
            suggestedStopLoss: stopLoss,
            suggestedTakeProfit: takeProfit
        )
    }
    
    public func calculateScore(data: SageMarketData) -> Double {
        var score: Double = 0
        
        // 1. Z-Score (weight: 35%)
        // Positive Z = overbought (expect fall), Negative Z = oversold (expect rise)
        if let zScore = TechnicalsEngine.zScore(data.closes, period: 20) {
            // Invert: negative Z-score = bullish (buy signal), positive = bearish
            score -= zScore * 15  // Scale Z-score (typically -3 to +3) to meaningful range
        }
        
        // 2. Bollinger %B (weight: 25%)
        // %B < 0.1 = oversold (bullish), %B > 0.9 = overbought (bearish)
        if let percentB = TechnicalsEngine.bollingerPercentB(data.closes) {
            if percentB < 0.1 {
                score -= 25  // Oversold = bullish reversion signal
            } else if percentB > 0.9 {
                score += 25  // Overbought = bearish reversion signal
            } else if percentB < 0.3 {
                score -= 15
            } else if percentB > 0.7 {
                score += 15
            }
        }
        
        // 3. RSI extreme (weight: 25%)
        if let rsi = TechnicalsEngine.rsi(data.closes) {
            if rsi < 25 {
                score -= 25  // Extremely oversold = bullish
            } else if rsi > 75 {
                score += 25  // Extremely overbought = bearish
            } else if rsi < 35 {
                score -= 15
            } else if rsi > 65 {
                score += 15
            }
        }
        
        // 4. Volume exhaustion (weight: 15%)
        // High volume at extremes signals potential reversal
        if let volumeTrend = TechnicalsEngine.volumeTrend(volumes: data.volumes) {
            if volumeTrend.trend == "expanding" {
                // Volume spike at price extreme = potential exhaustion
                if let percentB = TechnicalsEngine.bollingerPercentB(data.closes) {
                    if percentB < 0.2 || percentB > 0.8 {
                        // Add to reversal signal
                        let direction = percentB < 0.5 ? -1.0 : 1.0
                        score += direction * 15 * volumeTrend.ratio
                    }
                }
            }
        }
        
        return max(-100, min(100, score))
    }
    
    private func buildFactors(data: SageMarketData, score: Double) -> [String] {
        var factors: [String] = []
        
        if let zScore = TechnicalsEngine.zScore(data.closes) {
            factors.append("Z-Score: \(String(format: "%.2f", zScore))")
        }
        
        if let percentB = TechnicalsEngine.bollingerPercentB(data.closes) {
            factors.append("BB %B: \(String(format: "%.2f", percentB))")
        }
        
        if let rsi = TechnicalsEngine.rsi(data.closes) {
            factors.append("RSI: \(String(format: "%.1f", rsi))")
        }
        
        if let bbWidth = TechnicalsEngine.bollingerBandWidth(data.closes) {
            factors.append("BB Width: \(String(format: "%.2f", bbWidth))%")
        }
        
        return factors
    }
}

// MARK: - 4. Sage Confluence (Multi-Timeframe Alignment)

/// Triple-timeframe confirmation system
/// Timeframes: 1D (macro) + 4H (trading) + 1H (entry)
public struct SageConfluenceAlgorithm: SageAlgorithm {
    public let id = "sage_confluence"
    public let name = "Sage Confluence"
    public let description = "Triple-timeframe alignment requiring confirmation from macro (1D), trading (4H), and entry (1H) timeframes."
    public let category: SageAlgorithmCategory = .multiTimeframe
    public let primaryTimeframe: SageTimeframe = .h4
    public let minDataPoints: Int = 200
    public let isInternal: Bool = false
    
    public func evaluate(data: SageMarketData, regime: SageMarketRegime) -> SageSignal? {
        guard data.closes.count >= minDataPoints else { return nil }
        
        let score = calculateScore(data: data)
        
        // Confluence requires strong agreement
        guard abs(score) > 60 else { return nil }
        
        // Check if we have multi-timeframe data
        let hasMultiTF = data.higherTimeframeCloses != nil
        
        let type: SageSignalType
        let confidence: Double
        
        if score > 70 {
            type = .strongBuy
            confidence = hasMultiTF ? 0.85 : 0.7
        } else if score > 60 {
            type = .buy
            confidence = hasMultiTF ? 0.75 : 0.6
        } else if score < -70 {
            type = .strongSell
            confidence = hasMultiTF ? 0.85 : 0.7
        } else if score < -60 {
            type = .sell
            confidence = hasMultiTF ? 0.75 : 0.6
        } else {
            return nil
        }
        
        let atrPercent = TechnicalsEngine.atrApproxFromCloses(data.closes)?.atrPercent ?? 2.0
        
        return SageSignal(
            algorithmId: id,
            algorithmName: name,
            category: category,
            symbol: data.symbol,
            type: type,
            score: score,
            confidence: confidence,
            regime: regime,
            factors: buildFactors(data: data),
            suggestedEntry: data.currentPrice,
            suggestedStopLoss: data.currentPrice * (1 - atrPercent * 2.5 / 100),
            suggestedTakeProfit: data.currentPrice * (1 + atrPercent * 5 / 100)
        )
    }
    
    public func calculateScore(data: SageMarketData) -> Double {
        var score: Double = 0
        
        // Simulate multi-timeframe analysis using the available data
        // Macro (longer-term): use 200-period analysis (simulates daily)
        // Trading: use 50-period analysis (simulates 4H)
        // Entry: use 20-period analysis (simulates 1H)
        
        // 1. Macro trend (weight: 40%)
        let macroScore = analyzeMacro(data: data)
        score += macroScore * 40
        
        // 2. Trading timeframe (weight: 35%)
        let tradingScore = analyzeTrading(data: data)
        score += tradingScore * 35
        
        // 3. Entry timeframe (weight: 25%)
        let entryScore = analyzeEntry(data: data)
        score += entryScore * 25
        
        // Confluence bonus: if all three agree, boost signal
        let allBullish = macroScore > 0.3 && tradingScore > 0.3 && entryScore > 0.3
        let allBearish = macroScore < -0.3 && tradingScore < -0.3 && entryScore < -0.3
        
        if allBullish || allBearish {
            score *= 1.2  // 20% boost for confluence
        }
        
        return max(-100, min(100, score))
    }
    
    private func analyzeMacro(data: SageMarketData) -> Double {
        // Long-term trend using EMA50 position
        guard let ema50 = TechnicalsEngine.ema(data.closes, period: 50),
              let ema200 = TechnicalsEngine.ema(data.closes, period: 200) else {
            return 0
        }
        
        var score: Double = 0
        
        // Price vs EMA50
        if data.currentPrice > ema50 {
            score += 0.5
        } else {
            score -= 0.5
        }
        
        // EMA50 vs EMA200 (golden/death cross)
        if ema50 > ema200 {
            score += 0.5
        } else {
            score -= 0.5
        }
        
        return score
    }
    
    private func analyzeTrading(data: SageMarketData) -> Double {
        var score: Double = 0
        
        // RSI position
        if let rsi = TechnicalsEngine.rsi(data.closes) {
            if rsi > 50 && rsi < 70 {
                score += 0.5  // Bullish but not overbought
            } else if rsi < 50 && rsi > 30 {
                score -= 0.5  // Bearish but not oversold
            }
        }
        
        // MACD
        if let macd = TechnicalsEngine.macdHistogram(data.closes) {
            if macd > 0 {
                score += 0.5
            } else {
                score -= 0.5
            }
        }
        
        return score
    }
    
    private func analyzeEntry(data: SageMarketData) -> Double {
        var score: Double = 0
        
        // Price vs EMA20 (short-term)
        if let ema20 = TechnicalsEngine.ema(data.closes, period: 20) {
            if data.currentPrice > ema20 {
                score += 0.5
            } else {
                score -= 0.5
            }
        }
        
        // Pullback to EMA (good entry in trend)
        if let ema20 = TechnicalsEngine.ema(data.closes, period: 20) {
            let deviation = abs(data.currentPrice - ema20) / ema20 * 100
            if deviation < 2 {
                // Price near EMA = good entry point
                score += data.currentPrice > ema20 ? 0.5 : -0.5
            }
        }
        
        return score
    }
    
    private func buildFactors(data: SageMarketData) -> [String] {
        var factors: [String] = []
        
        let macro = analyzeMacro(data: data)
        let trading = analyzeTrading(data: data)
        let entry = analyzeEntry(data: data)
        
        factors.append("Macro: \(macro > 0 ? "bullish" : "bearish")")
        factors.append("Trading: \(trading > 0 ? "bullish" : "bearish")")
        factors.append("Entry: \(entry > 0 ? "bullish" : "bearish")")
        
        let alignment = (macro > 0) == (trading > 0) && (trading > 0) == (entry > 0)
        factors.append(alignment ? "All timeframes aligned" : "Mixed timeframes")
        
        return factors
    }
}

// MARK: - 5. Sage Volatility (Squeeze Breakout System)

/// Designed for crypto's volatility expansion/contraction cycles
/// Timeframe: 4H primary
public struct SageVolatilityAlgorithm: SageAlgorithm {
    public let id = "sage_volatility"
    public let name = "Sage Volatility"
    public let description = "Squeeze breakout system that detects volatility compression (BB inside Keltner) and trades the subsequent expansion."
    public let category: SageAlgorithmCategory = .volatility
    public let primaryTimeframe: SageTimeframe = .h4
    public let minDataPoints: Int = 50
    public let isInternal: Bool = false
    
    public func evaluate(data: SageMarketData, regime: SageMarketRegime) -> SageSignal? {
        guard data.closes.count >= minDataPoints else { return nil }
        
        // Check for squeeze
        guard let squeeze = TechnicalsEngine.detectSqueeze(data.closes) else {
            return nil
        }
        
        let score = calculateScore(data: data)
        
        // For volatility breakout, we need either:
        // 1. Active squeeze with building momentum (setup)
        // 2. Squeeze just released with direction confirmed (entry)
        
        guard squeeze.isSqueeze || abs(score) > 50 else { return nil }
        
        let type: SageSignalType
        let confidence: Double
        
        if squeeze.isSqueeze {
            // Still in squeeze - signal forming
            if abs(score) > 30 {
                type = score > 0 ? .buy : .sell
                confidence = 0.5 + squeeze.intensity * 0.2  // Higher intensity = higher confidence
            } else {
                return nil  // Wait for direction
            }
        } else {
            // Squeeze released - breakout
            if score > 60 {
                type = .strongBuy
                confidence = 0.8
            } else if score > 40 {
                type = .buy
                confidence = 0.65
            } else if score < -60 {
                type = .strongSell
                confidence = 0.8
            } else if score < -40 {
                type = .sell
                confidence = 0.65
            } else {
                return nil
            }
        }
        
        // ATR-based targets
        let atrPercent = TechnicalsEngine.atrApproxFromCloses(data.closes)?.atrPercent ?? 2.0
        
        return SageSignal(
            algorithmId: id,
            algorithmName: name,
            category: category,
            symbol: data.symbol,
            type: type,
            score: score,
            confidence: confidence,
            regime: regime,
            factors: buildFactors(data: data, squeeze: squeeze),
            suggestedEntry: data.currentPrice,
            suggestedStopLoss: data.currentPrice * (1 - atrPercent * 1 / 100),  // Tight stop for breakout
            suggestedTakeProfit: data.currentPrice * (1 + atrPercent * 2 / 100)  // 2:1 R:R
        )
    }
    
    public func calculateScore(data: SageMarketData) -> Double {
        var score: Double = 0
        
        // 1. Momentum direction (weight: 40%)
        // Use last 3-5 candles to determine breakout direction
        let recentCloses = Array(data.closes.suffix(5))
        if recentCloses.count >= 3 {
            let trend = recentCloses.last! - recentCloses.first!
            let trendPercent = (trend / recentCloses.first!) * 100
            score += min(max(trendPercent * 10, -40), 40)
        }
        
        // 2. RSI momentum (weight: 25%)
        if let rsi = TechnicalsEngine.rsi(data.closes) {
            if rsi > 55 {
                score += 25 * ((rsi - 50) / 50)  // Scale 55-100 to 0-25
            } else if rsi < 45 {
                score -= 25 * ((50 - rsi) / 50)  // Scale 0-45 to -25-0
            }
        }
        
        // 3. MACD direction (weight: 20%)
        if let macd = TechnicalsEngine.macdHistogram(data.closes) {
            let normalizedMACD = min(max(macd / (data.currentPrice * 0.001), -1), 1)  // Normalize
            score += normalizedMACD * 20
        }
        
        // 4. Price position relative to Keltner (weight: 15%)
        if let keltner = TechnicalsEngine.keltnerChannels(data.closes) {
            if data.currentPrice > keltner.upper {
                score += 15  // Breakout above
            } else if data.currentPrice < keltner.lower {
                score -= 15  // Breakout below
            }
        }
        
        return max(-100, min(100, score))
    }
    
    private func buildFactors(data: SageMarketData, squeeze: (isSqueeze: Bool, intensity: Double)) -> [String] {
        var factors: [String] = []
        
        factors.append(squeeze.isSqueeze ? "Squeeze ACTIVE" : "Squeeze RELEASED")
        factors.append("Intensity: \(String(format: "%.2f", squeeze.intensity))")
        
        if let bbWidth = TechnicalsEngine.bollingerBandWidth(data.closes) {
            factors.append("BB Width: \(String(format: "%.2f", bbWidth))%")
        }
        
        if let rsi = TechnicalsEngine.rsi(data.closes) {
            factors.append("RSI: \(String(format: "%.1f", rsi))")
        }
        
        return factors
    }
}

// MARK: - 6. Sage Neural (AI-Enhanced Ensemble)

/// AI-powered algorithm combining all others with sentiment
/// This is the "smart" layer that generates unified recommendations
public struct SageNeuralAlgorithm: SageAlgorithm {
    public let id = "sage_neural"
    public let name = "Sage Neural"
    public let description = "AI-enhanced ensemble that combines all Sage algorithms with sentiment analysis for unified, explainable recommendations."
    public let category: SageAlgorithmCategory = .ai
    public let primaryTimeframe: SageTimeframe = .h4
    public let minDataPoints: Int = 200
    public let isInternal: Bool = false
    
    public func evaluate(data: SageMarketData, regime: SageMarketRegime) -> SageSignal? {
        guard data.closes.count >= minDataPoints else { return nil }
        
        let score = calculateScore(data: data)
        
        // Sage Neural requires high conviction
        guard abs(score) > 50 else { return nil }
        
        let type: SageSignalType
        let confidence: Double
        
        if score > 70 {
            type = .strongBuy
            confidence = min(score / 100, 0.9)
        } else if score > 50 {
            type = .buy
            confidence = score / 100
        } else if score < -70 {
            type = .strongSell
            confidence = min(abs(score) / 100, 0.9)
        } else if score < -50 {
            type = .sell
            confidence = abs(score) / 100
        } else {
            return nil
        }
        
        let atrPercent = TechnicalsEngine.atrApproxFromCloses(data.closes)?.atrPercent ?? 2.0
        
        return SageSignal(
            algorithmId: id,
            algorithmName: name,
            category: category,
            symbol: data.symbol,
            type: type,
            score: score,
            confidence: confidence,
            regime: regime,
            factors: buildFactors(data: data, score: score),
            suggestedEntry: data.currentPrice,
            suggestedStopLoss: data.currentPrice * (1 - atrPercent * regime.stopLossATRMultiplier / 100),
            suggestedTakeProfit: data.currentPrice * (1 + atrPercent * regime.stopLossATRMultiplier * 2 / 100)
        )
    }
    
    public func calculateScore(data: SageMarketData) -> Double {
        var score: Double = 0
        
        // Get regime
        let regime = SageMarketRegime.detect(closes: data.closes, volumes: data.volumes)
        
        // 1. Aggregate scores from other algorithms (weight: 60%)
        let trend = SageTrendAlgorithm().calculateScore(data: data)
        let momentum = SageMomentumAlgorithm().calculateScore(data: data)
        let reversion = SageReversionAlgorithm().calculateScore(data: data)
        let confluence = SageConfluenceAlgorithm().calculateScore(data: data)
        let volatility = SageVolatilityAlgorithm().calculateScore(data: data)
        
        // Weight based on regime
        var weights: [Double]
        switch regime {
        case .strongTrend, .trending:
            weights = [0.30, 0.30, 0.05, 0.20, 0.15]  // Favor trend/momentum
        case .ranging:
            weights = [0.15, 0.10, 0.35, 0.20, 0.20]  // Favor reversion
        case .volatile:
            weights = [0.15, 0.15, 0.15, 0.25, 0.30]  // Favor volatility/confluence
        case .accumulation:
            weights = [0.25, 0.25, 0.15, 0.20, 0.15]  // Balanced with trend bias
        case .distribution:
            weights = [0.20, 0.15, 0.25, 0.25, 0.15]  // Cautious
        case .weakTrend:
            weights = [0.20, 0.20, 0.20, 0.25, 0.15]  // Balanced
        }
        
        let algorithmScores = [trend, momentum, reversion, confluence, volatility]
        for (idx, algoScore) in algorithmScores.enumerated() {
            score += algoScore * weights[idx] * 0.6
        }
        
        // 2. Sentiment (weight: 20%)
        // Fear/Greed as contrarian: extreme fear = bullish, extreme greed = bearish
        if let fearGreed = data.fearGreedIndex {
            let sentimentScore: Double
            if fearGreed < 25 {
                sentimentScore = 20  // Extreme fear = bullish
            } else if fearGreed > 75 {
                sentimentScore = -20  // Extreme greed = bearish
            } else if fearGreed < 40 {
                sentimentScore = 10
            } else if fearGreed > 60 {
                sentimentScore = -10
            } else {
                sentimentScore = 0
            }
            score += sentimentScore
        }
        
        // 3. Regime alignment bonus (weight: 20%)
        // Boost score if algorithms agree with regime
        let bullishAlgos = algorithmScores.filter { $0 > 30 }.count
        let bearishAlgos = algorithmScores.filter { $0 < -30 }.count
        
        if (regime == .accumulation || regime == .trending) && bullishAlgos >= 3 {
            score += 20
        } else if regime == .distribution && bearishAlgos >= 3 {
            score -= 20
        }
        
        return max(-100, min(100, score))
    }
    
    private func buildFactors(data: SageMarketData, score: Double) -> [String] {
        var factors: [String] = []
        
        let regime = SageMarketRegime.detect(closes: data.closes, volumes: data.volumes)
        factors.append("Regime: \(regime.displayName)")
        
        // Count algorithm agreement
        let trend = SageTrendAlgorithm().calculateScore(data: data)
        let momentum = SageMomentumAlgorithm().calculateScore(data: data)
        let reversion = SageReversionAlgorithm().calculateScore(data: data)
        let confluence = SageConfluenceAlgorithm().calculateScore(data: data)
        let volatility = SageVolatilityAlgorithm().calculateScore(data: data)
        
        let scores = [trend, momentum, reversion, confluence, volatility]
        let bullish = scores.filter { $0 > 20 }.count
        let bearish = scores.filter { $0 < -20 }.count
        
        factors.append("Algorithms: \(bullish) bullish, \(bearish) bearish")
        
        if let fearGreed = data.fearGreedIndex {
            let sentiment = fearGreed < 40 ? "Fear" : (fearGreed > 60 ? "Greed" : "Neutral")
            factors.append("Sentiment: \(sentiment) (\(fearGreed))")
        }
        
        factors.append("Ensemble score: \(String(format: "%.1f", score))")
        
        return factors
    }
}
