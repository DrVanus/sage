// TechnicalsEngine.swift
// Minimal native technicals computation (Phase 1)

import Foundation
import SwiftUI

// Lightweight indicator helpers for RSI, EMA/SMA, and MACD
struct TechnicalsEngine {
    // Compute RSI(14) from close prices
    static func rsi(_ closes: [Double], period: Int = 14) -> Double? {
        guard closes.count > period else { return nil }
        var gains: [Double] = []
        var losses: [Double] = []
        for i in 1..<closes.count {
            let delta = closes[i] - closes[i-1]
            if delta >= 0 { gains.append(delta) } else { losses.append(-delta) }
        }
        if gains.count < period || losses.count < period { return nil }
        let avgGain = gains.suffix(period).reduce(0, +) / Double(period)
        let avgLoss = losses.suffix(period).reduce(0, +) / Double(period)
        if avgLoss == 0 { return 100 }
        let rs = avgGain / avgLoss
        return 100 - (100 / (1 + rs))
    }

    static func sma(_ closes: [Double], period: Int) -> Double? {
        guard closes.count >= period else { return nil }
        let slice = closes.suffix(period)
        let sum = slice.reduce(0, +)
        return sum / Double(period)
    }

    static func ema(_ closes: [Double], period: Int) -> Double? {
        guard closes.count >= period else { return nil }
        let k = 2.0 / Double(period + 1)
        var ema = closes[closes.count - period]
        for price in closes.suffix(from: closes.count - period + 1) {
            ema = price * k + ema * (1 - k)
        }
        return ema
    }

    // MACD(12,26,9) — returns histogram latest value
    static func macdHistogram(_ closes: [Double], fast: Int = 12, slow: Int = 26, signal: Int = 9) -> Double? {
        guard closes.count >= slow + signal else { return nil }
        // naive EMA chain for last point only
        func emaSeries(_ input: [Double], period: Int) -> [Double] {
            let k = 2.0 / Double(period + 1)
            var out: [Double] = []
            let prev = input.first ?? 0
            for i in 0..<input.count {
                let val: Double
                if i == 0 { val = prev } else { val = input[i] * k + out[i-1] * (1 - k) }
                out.append(val)
            }
            return out
        }
        let fastEMA = emaSeries(closes, period: fast)
        let slowEMA = emaSeries(closes, period: slow)
        let count = min(fastEMA.count, slowEMA.count)
        guard count > 0 else { return nil }
        let macdLine = zip(fastEMA.suffix(count), slowEMA.suffix(count)).map { $0 - $1 }
        let signalLine = emaSeries(macdLine, period: signal)
        guard let m = macdLine.last, let s = signalLine.last else { return nil }
        return m - s
    }

    /// MACD line and signal line (latest values)
    static func macdLineSignal(_ closes: [Double], fast: Int = 12, slow: Int = 26, signal: Int = 9) -> (macd: Double, signal: Double)? {
        guard closes.count >= slow + signal else { return nil }
        func emaSeries(_ input: [Double], period: Int) -> [Double] {
            let k = 2.0 / Double(period + 1)
            var out: [Double] = []
            let prev = input.first ?? 0
            for i in 0..<input.count {
                let val: Double
                if i == 0 { val = prev } else { val = input[i] * k + out[i-1] * (1 - k) }
                out.append(val)
            }
            return out
        }
        let fastEMA = emaSeries(closes, period: fast)
        let slowEMA = emaSeries(closes, period: slow)
        let count = min(fastEMA.count, slowEMA.count)
        guard count > 0 else { return nil }
        let macdLine = zip(fastEMA.suffix(count), slowEMA.suffix(count)).map { $0 - $1 }
        let signalLine = emaSeries(macdLine, period: signal)
        guard let m = macdLine.last, let s = signalLine.last else { return nil }
        return (m, s)
    }

    /// RSI series computed over a rolling window (naive, O(n*period))
    static func rsiSeries(_ closes: [Double], period: Int = 14) -> [Double]? {
        guard closes.count > period else { return nil }
        var series: [Double] = []
        // Start at index = period, compute RSI for the last `period` deltas
        for i in period..<closes.count {
            var gains: Double = 0
            var losses: Double = 0
            var count: Int = 0
            var j = i - period + 1
            while j <= i {
                let d = closes[j] - closes[j-1]
                if d >= 0 { gains += d } else { losses += -d }
                count += 1
                j += 1
            }
            guard count == period else { continue }
            if losses == 0 {
                series.append(100)
            } else {
                let rs = (gains / Double(period)) / (losses / Double(period))
                let rsi = 100 - (100 / (1 + rs))
                series.append(rsi)
            }
        }
        return series.isEmpty ? nil : series
    }

    /// Stochastic RSI (returns %K and %D)
    static func stochRSI(_ closes: [Double], rsiPeriod: Int = 14, stochPeriod: Int = 14, kPeriod: Int = 3, dPeriod: Int = 3) -> (k: Double, d: Double)? {
        guard let rsiVals = rsiSeries(closes, period: rsiPeriod), rsiVals.count >= stochPeriod else { return nil }
        // Raw %K of RSI over the last stochPeriod
        var kSeries: [Double] = []
        for i in (stochPeriod-1)..<rsiVals.count {
            let window = rsiVals[(i - (stochPeriod - 1))...i]
            guard let minV = window.min(), let maxV = window.max(), maxV > minV else { continue }
            let current = rsiVals[i]
            let k = (current - minV) / (maxV - minV) * 100.0
            kSeries.append(k)
        }
        guard !kSeries.isEmpty else { return nil }
        func sma(_ arr: [Double], _ period: Int) -> [Double] {
            guard arr.count >= period else { return [] }
            var out: [Double] = []
            var sum: Double = arr.prefix(period).reduce(0, +)
            out.append(sum / Double(period))
            if period < arr.count {
                for i in period..<arr.count {
                    sum += arr[i]
                    sum -= arr[i - period]
                    out.append(sum / Double(period))
                }
            }
            return out
        }
        let kSmoothed = (kPeriod > 1) ? sma(kSeries, kPeriod) : kSeries
        let dSmoothed = (dPeriod > 1) ? sma(kSmoothed, dPeriod) : kSmoothed
        guard let kLast = kSmoothed.last, let dLast = dSmoothed.last else { return nil }
        return (kLast, dLast)
    }

    // Aggregate to 0..1 score using simple rules
    static func aggregateScore(price: Double, closes: [Double]) -> Double {
        var votes: Double = 0
        var total: Double = 0

        // MAs (weight 0.6)
        let maPeriods = [10, 20, 50, 100, 200]
        for p in maPeriods {
            if let ma = sma(closes, period: p) {
                total += 0.6 / Double(maPeriods.count)
                if price > ma * 1.001 { votes += 0.6 / Double(maPeriods.count) } // small buffer
                else if abs(price - ma) <= ma * 0.001 { votes += (0.6 / Double(maPeriods.count)) * 0.5 } // neutral-ish
            }
        }

        // Oscillators (weight 0.4)
        var oscWeight: Double = 0
        if let r = rsi(closes) {
            let w = 0.2; oscWeight += w; total += w
            if r < 30 { votes += w } else if r <= 70 { votes += w * 0.5 }
        }
        if let hist = macdHistogram(closes) {
            let w = 0.2; oscWeight += w; total += w
            if hist > 0 { votes += w } else if abs(hist) < 1e-9 { votes += w * 0.5 }
        }

        if total <= 0 { return 0.5 }
        let score01 = max(0, min(1, votes / total))
        return score01
    }

    // MARK: - Additional Indicator Helpers (Phase 2)

    /// Standard deviation of a slice
    static func stddev(_ slice: ArraySlice<Double>) -> Double {
        let n = Double(slice.count)
        guard n > 0 else { return 0 }
        let mean = slice.reduce(0, +) / n
        let variance = slice.reduce(0) { $0 + pow($1 - mean, 2) } / n
        return sqrt(variance)
    }

    /// Bollinger Bands (middle SMA, upper, lower)
    static func bollingerBands(_ closes: [Double], period: Int = 20, k: Double = 2.0) -> (middle: Double, upper: Double, lower: Double)? {
        guard closes.count >= period else { return nil }
        let tail = closes.suffix(period)
        let smaVal = tail.reduce(0, +) / Double(period)
        let sd = stddev(tail)
        let upper = smaVal + k * sd
        let lower = smaVal - k * sd
        return (smaVal, upper, lower)
    }

    /// Stochastic series - returns arrays of (%K, %D) for plotting
    static func stochSeries(_ closes: [Double], kPeriod: Int = 14, dPeriod: Int = 3) -> (k: [Double], d: [Double])? {
        guard closes.count >= kPeriod + dPeriod else { return nil }
        
        // Calculate raw %K values
        var kSeries: [Double] = []
        for i in (kPeriod - 1)..<closes.count {
            let window = closes[(i - kPeriod + 1)...i]
            guard let minV = window.min(), let maxV = window.max() else { continue }
            if maxV > minV {
                let k = (closes[i] - minV) / (maxV - minV) * 100.0
                kSeries.append(k)
            } else {
                kSeries.append(50.0) // Neutral when no range
            }
        }
        
        guard kSeries.count >= dPeriod else { return nil }
        
        // Calculate %D as SMA of %K
        var dSeries: [Double] = []
        for i in (dPeriod - 1)..<kSeries.count {
            let window = kSeries[(i - dPeriod + 1)...i]
            let d = window.reduce(0, +) / Double(dPeriod)
            dSeries.append(d)
        }
        
        // Pad K series to match D series alignment
        _ = kSeries.count - dSeries.count
        let alignedK = Array(kSeries.suffix(dSeries.count))
        
        return (alignedK, dSeries)
    }

    /// Stochastic %K using only closes (approximation): (close - min) / (max - min) * 100
    static func stochK(_ closes: [Double], period: Int = 14) -> Double? {
        guard closes.count >= period else { return nil }
        let tail = closes.suffix(period)
        guard let minV = tail.min(), let maxV = tail.max(), maxV > minV, let last = closes.last else { return nil }
        return (last - minV) / (maxV - minV) * 100.0
    }

    /// Williams %R (approximation using closes): -100 * (max - close) / (max - min)
    static func williamsR(_ closes: [Double], period: Int = 14) -> Double? {
        guard closes.count >= period else { return nil }
        let tail = closes.suffix(period)
        guard let minV = tail.min(), let maxV = tail.max(), maxV > minV, let last = closes.last else { return nil }
        return -100.0 * (maxV - last) / (maxV - minV)
    }

    /// Momentum over period: close[n] - close[n-period]
    static func momentum(_ closes: [Double], period: Int = 10) -> Double? {
        guard closes.count > period else { return nil }
        guard let last = closes.last else { return nil }
        let prev = closes[closes.count - 1 - period]
        return last - prev
    }

    /// Rate of Change (%): 100 * (close / close[n-period] - 1)
    static func roc(_ closes: [Double], period: Int = 12) -> Double? {
        guard closes.count > period else { return nil }
        guard let last = closes.last else { return nil }
        let prev = closes[closes.count - 1 - period]
        guard prev != 0 else { return nil }
        return 100.0 * (last / prev - 1.0)
    }

    // MARK: - Additional Oscillators (approximations using closes only)

    /// Approximate ADX(14) using close deltas as TR and directional movement.
    /// Returns (ADX, +DI, -DI) in 0..100 range.
    static func adxApprox(_ closes: [Double], period: Int = 14) -> (adx: Double, plusDI: Double, minusDI: Double)? {
        guard closes.count > period + 1 else { return nil }
        // Approximate TR and directional movement from close-to-close changes
        var tr: [Double] = [0]
        var dmPlus: [Double] = [0]
        var dmMinus: [Double] = [0]
        for i in 1..<closes.count {
            let upMove = closes[i] - closes[i-1]
            let downMove = closes[i-1] - closes[i]
            let trueRange = abs(upMove)
            tr.append(max(trueRange, 1e-12))
            dmPlus.append(upMove > 0 && upMove > downMove ? upMove : 0)
            dmMinus.append(downMove > 0 && downMove > upMove ? downMove : 0)
        }
        // Wilder smoothing
        func wilderSmooth(_ input: [Double], period: Int) -> [Double] {
            guard input.count >= period else { return [] }
            var out: [Double] = []
            let first = input.prefix(period).reduce(0, +)
            out.append(first)
            if input.count > period {
                for i in period..<input.count {
                    let next = out.last! - (out.last! / Double(period)) + input[i]
                    out.append(next)
                }
            }
            return out
        }
        let atrSeries = wilderSmooth(tr, period: period)
        let dmPlusSeries = wilderSmooth(dmPlus, period: period)
        let dmMinusSeries = wilderSmooth(dmMinus, period: period)
        guard let atr = atrSeries.last, let smPlus = dmPlusSeries.last, let smMinus = dmMinusSeries.last, atr > 0 else { return nil }
        let plusDI = 100.0 * (smPlus / atr)
        let minusDI = 100.0 * (smMinus / atr)
        let denom = max(1e-12, plusDI + minusDI)
        let dx = 100.0 * abs(plusDI - minusDI) / denom
        // Smooth DX to ADX (one-step approximation: return latest DX as ADX if too short)
        if atrSeries.count < period { return (dx, plusDI, minusDI) }
        // Build DX series for last `period` windows to smooth
        var dxSeries: [Double] = []
        for i in 0..<(min(tr.count, dmPlus.count, dmMinus.count)) {
            if i >= period {
                let atrWin = atrSeries[min(i - 1, atrSeries.count - 1)]
                let dmp = dmPlusSeries[min(i - 1, dmPlusSeries.count - 1)]
                let dmm = dmMinusSeries[min(i - 1, dmMinusSeries.count - 1)]
                if atrWin > 0 {
                    let pdi = 100.0 * (dmp / atrWin)
                    let mdi = 100.0 * (dmm / atrWin)
                    let d = 100.0 * abs(pdi - mdi) / max(1e-12, pdi + mdi)
                    dxSeries.append(d)
                }
            }
        }
        let adx = dxSeries.isEmpty ? dx : (dxSeries.suffix(period).reduce(0, +) / Double(min(period, dxSeries.count)))
        return (adx, plusDI, minusDI)
    }

    /// Commodity Channel Index using closes as typical price approximation.
    static func cci(_ closes: [Double], period: Int = 20) -> Double? {
        guard closes.count >= period else { return nil }
        let tp = closes // typical price approximated by close
        let sma = tp.suffix(period).reduce(0, +) / Double(period)
        let meanDev = tp.suffix(period).reduce(0) { $0 + abs($1 - sma) } / Double(period)
        let denom = 0.015 * max(meanDev, 1e-12)
        return (tp.last! - sma) / denom
    }

    /// MACD series - returns arrays of (macdLine, signalLine, histogram) aligned with input
    /// Output arrays start at index (slow + signal - 1) relative to input
    static func macdSeries(_ closes: [Double], fast: Int = 12, slow: Int = 26, signal: Int = 9) -> (macdLine: [Double], signalLine: [Double], histogram: [Double])? {
        guard closes.count >= slow + signal else { return nil }
        
        func emaSeries(_ input: [Double], period: Int) -> [Double] {
            let k = 2.0 / Double(period + 1)
            var out: [Double] = []
            for i in 0..<input.count {
                if i == 0 {
                    out.append(input[0])
                } else {
                    out.append(input[i] * k + out[i-1] * (1 - k))
                }
            }
            return out
        }
        
        let fastEMA = emaSeries(closes, period: fast)
        let slowEMA = emaSeries(closes, period: slow)
        
        // MACD line = fast EMA - slow EMA
        var macdLine: [Double] = []
        for i in 0..<closes.count {
            macdLine.append(fastEMA[i] - slowEMA[i])
        }
        
        // Signal line = EMA of MACD line
        let signalLine = emaSeries(macdLine, period: signal)
        
        // Histogram = MACD - Signal
        var histogram: [Double] = []
        for i in 0..<closes.count {
            histogram.append(macdLine[i] - signalLine[i])
        }
        
        return (macdLine, signalLine, histogram)
    }

    /// Ultimate Oscillator approximation using closes as both high/low proxy.
    static func ultimateOscillatorApprox(_ closes: [Double], s: Int = 7, m: Int = 14, l: Int = 28) -> Double? {
        guard closes.count > l else { return nil }
        // Approximate BP = close - min(close, prevClose), TR = max(close, prevClose) - min(close, prevClose)
        var bp: [Double] = [0]
        var tr: [Double] = [0]
        for i in 1..<closes.count {
            let c = closes[i]
            let pc = closes[i-1]
            let minLC = min(c, pc)
            let maxHC = max(c, pc)
            bp.append(c - minLC)
            tr.append(maxHC - minLC)
        }
        func sumLast(_ arr: [Double], _ n: Int) -> Double {
            guard arr.count >= n else { return 0 }
            return arr.suffix(n).reduce(0, +)
        }
        let bs = sumLast(bp, s); let ts = max(sumLast(tr, s), 1e-12)
        let bm = sumLast(bp, m); let tm = max(sumLast(tr, m), 1e-12)
        let bl = sumLast(bp, l); let tl = max(sumLast(tr, l), 1e-12)
        let uo = 100.0 * ((4.0 * (bs/ts)) + (2.0 * (bm/tm)) + (1.0 * (bl/tl))) / 7.0
        return uo.isFinite ? uo : nil
    }
    
    // MARK: - Native Indicators (ATR, OBV, VWAP, MFI)
    
    /// Average True Range (ATR) - measures volatility
    /// True Range = max(High - Low, |High - PrevClose|, |Low - PrevClose|)
    /// ATR = Wilder smoothed average of True Range
    static func atr(highs: [Double], lows: [Double], closes: [Double], period: Int = 14) -> Double? {
        guard highs.count == lows.count, lows.count == closes.count else { return nil }
        guard closes.count > period else { return nil }
        
        // Calculate True Range series
        var trSeries: [Double] = []
        for i in 1..<closes.count {
            let highLow = highs[i] - lows[i]
            let highPrevClose = abs(highs[i] - closes[i-1])
            let lowPrevClose = abs(lows[i] - closes[i-1])
            let tr = max(highLow, max(highPrevClose, lowPrevClose))
            trSeries.append(tr)
        }
        
        guard trSeries.count >= period else { return nil }
        
        // Wilder smoothing (exponential with alpha = 1/period)
        let firstATR = trSeries.prefix(period).reduce(0, +) / Double(period)
        var atr = firstATR
        for i in period..<trSeries.count {
            atr = (atr * Double(period - 1) + trSeries[i]) / Double(period)
        }
        
        return atr
    }
    
    /// ATR series for charting - returns ATR values aligned with price data
    static func atrSeries(highs: [Double], lows: [Double], closes: [Double], period: Int = 14) -> [Double]? {
        guard highs.count == lows.count, lows.count == closes.count else { return nil }
        guard closes.count > period else { return nil }
        
        // Calculate True Range series
        var trSeries: [Double] = []
        for i in 1..<closes.count {
            let highLow = highs[i] - lows[i]
            let highPrevClose = abs(highs[i] - closes[i-1])
            let lowPrevClose = abs(lows[i] - closes[i-1])
            let tr = max(highLow, max(highPrevClose, lowPrevClose))
            trSeries.append(tr)
        }
        
        guard trSeries.count >= period else { return nil }
        
        // Wilder smoothing with series output
        var atrValues: [Double] = []
        let firstATR = trSeries.prefix(period).reduce(0, +) / Double(period)
        var atr = firstATR
        atrValues.append(atr)
        
        for i in period..<trSeries.count {
            atr = (atr * Double(period - 1) + trSeries[i]) / Double(period)
            atrValues.append(atr)
        }
        
        return atrValues
    }
    
    /// On Balance Volume (OBV) - cumulative volume indicator
    /// OBV adds volume on up days and subtracts on down days
    static func obv(closes: [Double], volumes: [Double]) -> Double? {
        guard closes.count == volumes.count, closes.count >= 2 else { return nil }
        
        var obvValue: Double = 0
        for i in 1..<closes.count {
            if closes[i] > closes[i-1] {
                obvValue += volumes[i]
            } else if closes[i] < closes[i-1] {
                obvValue -= volumes[i]
            }
            // If close == prevClose, OBV stays the same
        }
        
        return obvValue
    }
    
    /// OBV series for charting - returns cumulative OBV values
    static func obvSeries(closes: [Double], volumes: [Double]) -> [Double]? {
        guard closes.count == volumes.count, closes.count >= 2 else { return nil }
        
        var obvValues: [Double] = [0] // Start at 0
        var obvValue: Double = 0
        
        for i in 1..<closes.count {
            if closes[i] > closes[i-1] {
                obvValue += volumes[i]
            } else if closes[i] < closes[i-1] {
                obvValue -= volumes[i]
            }
            obvValues.append(obvValue)
        }
        
        return obvValues
    }
    
    /// Volume Weighted Average Price (VWAP) - benchmark price
    /// VWAP = Cumulative(Typical Price × Volume) / Cumulative(Volume)
    /// Typical Price = (High + Low + Close) / 3
    static func vwap(highs: [Double], lows: [Double], closes: [Double], volumes: [Double]) -> Double? {
        guard highs.count == lows.count, lows.count == closes.count, closes.count == volumes.count else { return nil }
        guard closes.count >= 1 else { return nil }
        
        var cumulativeTPV: Double = 0
        var cumulativeVolume: Double = 0
        
        for i in 0..<closes.count {
            let typicalPrice = (highs[i] + lows[i] + closes[i]) / 3.0
            cumulativeTPV += typicalPrice * volumes[i]
            cumulativeVolume += volumes[i]
        }
        
        guard cumulativeVolume > 0 else { return nil }
        return cumulativeTPV / cumulativeVolume
    }
    
    /// VWAP series for charting - returns running VWAP values
    static func vwapSeries(highs: [Double], lows: [Double], closes: [Double], volumes: [Double]) -> [Double]? {
        guard highs.count == lows.count, lows.count == closes.count, closes.count == volumes.count else { return nil }
        guard closes.count >= 1 else { return nil }
        
        var vwapValues: [Double] = []
        var cumulativeTPV: Double = 0
        var cumulativeVolume: Double = 0
        
        for i in 0..<closes.count {
            let typicalPrice = (highs[i] + lows[i] + closes[i]) / 3.0
            cumulativeTPV += typicalPrice * volumes[i]
            cumulativeVolume += volumes[i]
            
            if cumulativeVolume > 0 {
                vwapValues.append(cumulativeTPV / cumulativeVolume)
            } else {
                vwapValues.append(closes[i]) // Fallback to close
            }
        }
        
        return vwapValues
    }
    
    /// Money Flow Index (MFI) - volume-weighted RSI
    /// MFI = 100 - (100 / (1 + Money Flow Ratio))
    /// Money Flow Ratio = Positive Money Flow / Negative Money Flow
    static func mfi(highs: [Double], lows: [Double], closes: [Double], volumes: [Double], period: Int = 14) -> Double? {
        guard highs.count == lows.count, lows.count == closes.count, closes.count == volumes.count else { return nil }
        guard closes.count > period else { return nil }
        
        // Calculate typical prices and raw money flow
        var typicalPrices: [Double] = []
        var rawMoneyFlow: [Double] = []
        
        for i in 0..<closes.count {
            let tp = (highs[i] + lows[i] + closes[i]) / 3.0
            typicalPrices.append(tp)
            rawMoneyFlow.append(tp * volumes[i])
        }
        
        // Calculate positive and negative money flow over the period
        var positiveFlow: Double = 0
        var negativeFlow: Double = 0
        
        let startIdx = closes.count - period
        for i in startIdx..<closes.count {
            if i > 0 {
                if typicalPrices[i] > typicalPrices[i-1] {
                    positiveFlow += rawMoneyFlow[i]
                } else if typicalPrices[i] < typicalPrices[i-1] {
                    negativeFlow += rawMoneyFlow[i]
                }
            }
        }
        
        guard negativeFlow > 0 else { return 100 } // All positive flow
        
        let moneyFlowRatio = positiveFlow / negativeFlow
        let mfi = 100 - (100 / (1 + moneyFlowRatio))
        
        return mfi.isFinite ? mfi : nil
    }
    
    /// MFI series for charting - returns MFI values over rolling windows
    static func mfiSeries(highs: [Double], lows: [Double], closes: [Double], volumes: [Double], period: Int = 14) -> [Double]? {
        guard highs.count == lows.count, lows.count == closes.count, closes.count == volumes.count else { return nil }
        guard closes.count > period else { return nil }
        
        // Calculate typical prices and raw money flow
        var typicalPrices: [Double] = []
        var rawMoneyFlow: [Double] = []
        
        for i in 0..<closes.count {
            let tp = (highs[i] + lows[i] + closes[i]) / 3.0
            typicalPrices.append(tp)
            rawMoneyFlow.append(tp * volumes[i])
        }
        
        var mfiValues: [Double] = []
        
        // Calculate MFI for each window starting at period
        for windowEnd in period..<closes.count {
            var positiveFlow: Double = 0
            var negativeFlow: Double = 0
            
            for i in (windowEnd - period + 1)...windowEnd {
                if i > 0 {
                    if typicalPrices[i] > typicalPrices[i-1] {
                        positiveFlow += rawMoneyFlow[i]
                    } else if typicalPrices[i] < typicalPrices[i-1] {
                        negativeFlow += rawMoneyFlow[i]
                    }
                }
            }
            
            let mfi: Double
            if negativeFlow <= 0 {
                mfi = 100
            } else {
                let moneyFlowRatio = positiveFlow / negativeFlow
                mfi = 100 - (100 / (1 + moneyFlowRatio))
            }
            
            mfiValues.append(mfi.isFinite ? mfi : 50)
        }
        
        return mfiValues.isEmpty ? nil : mfiValues
    }
    
    // MARK: - Professional Swing Trading Indicators
    
    /// Average Daily Range Percentage (ADR%) - measures average volatility as % of price
    /// Used for stock selection: ADR% > 5% indicates sufficient volatility for swing trading
    static func adrPercent(highs: [Double], lows: [Double], period: Int = 14) -> Double? {
        guard highs.count == lows.count, highs.count >= period else { return nil }
        
        var dailyRanges: [Double] = []
        for i in 0..<highs.count {
            let range = highs[i] - lows[i]
            let midPrice = (highs[i] + lows[i]) / 2.0
            if midPrice > 0 {
                dailyRanges.append((range / midPrice) * 100.0)
            }
        }
        
        guard dailyRanges.count >= period else { return nil }
        let recentRanges = dailyRanges.suffix(period)
        let adr = recentRanges.reduce(0, +) / Double(period)
        
        return adr.isFinite ? adr : nil
    }
    
    /// ADR in absolute price terms (not percentage)
    static func adrAbsolute(highs: [Double], lows: [Double], period: Int = 14) -> Double? {
        guard highs.count == lows.count, highs.count >= period else { return nil }
        
        var dailyRanges: [Double] = []
        for i in 0..<highs.count {
            dailyRanges.append(highs[i] - lows[i])
        }
        
        guard dailyRanges.count >= period else { return nil }
        let recentRanges = dailyRanges.suffix(period)
        return recentRanges.reduce(0, +) / Double(period)
    }
    
    /// Volume trend analysis - detects if volume is drying up (consolidation) or expanding (breakout)
    /// Returns trend direction and ratio of recent volume to average
    static func volumeTrend(volumes: [Double], shortPeriod: Int = 5, longPeriod: Int = 20) -> (trend: String, ratio: Double, dryingUp: Bool)? {
        guard volumes.count >= longPeriod else { return nil }
        
        let recentVolume = volumes.suffix(shortPeriod)
        let avgRecentVol = recentVolume.reduce(0, +) / Double(shortPeriod)
        
        let longerVolume = volumes.suffix(longPeriod)
        let avgLongerVol = longerVolume.reduce(0, +) / Double(longPeriod)
        
        guard avgLongerVol > 0 else { return nil }
        
        let ratio = avgRecentVol / avgLongerVol
        
        // Volume drying up = ratio < 0.7 (recent vol is 70% or less of average)
        // Volume expanding = ratio > 1.3 (recent vol is 130% or more of average)
        let trend: String
        let dryingUp: Bool
        
        if ratio < 0.7 {
            trend = "drying_up"
            dryingUp = true
        } else if ratio > 1.3 {
            trend = "expanding"
            dryingUp = false
        } else {
            trend = "neutral"
            dryingUp = false
        }
        
        return (trend, ratio, dryingUp)
    }
    
    /// MA Alignment Analysis - checks if multiple MAs are in bullish/bearish order
    /// Bullish order: 10 > 20 > 50 > 200 (all inclining)
    /// Returns alignment status and whether MAs are inclining
    static func maAlignment(closes: [Double]) -> (aligned: Bool, order: String, bullish: Bool, sma10Above20: Bool, allInclining: Bool)? {
        guard closes.count >= 200 else { return nil }
        
        // Calculate current SMA values
        guard let sma10 = sma(closes, period: 10),
              let sma20 = sma(closes, period: 20),
              let sma50 = sma(closes, period: 50),
              let sma200 = sma(closes, period: 200) else { return nil }
        
        // Calculate SMAs from 5 periods ago to check inclining
        let closesOlder = Array(closes.dropLast(5))
        let sma10Old = sma(closesOlder, period: 10)
        let sma20Old = sma(closesOlder, period: 20)
        
        // Check if 10/20 are inclining (current > 5 days ago)
        let sma10Inclining = sma10Old.map { sma10 > $0 } ?? false
        let sma20Inclining = sma20Old.map { sma20 > $0 } ?? false
        let allInclining = sma10Inclining && sma20Inclining
        
        // Check bullish alignment: 10 > 20 > 50 > 200
        let bullishAligned = sma10 > sma20 && sma20 > sma50 && sma50 > sma200
        
        // Check bearish alignment: 10 < 20 < 50 < 200
        let bearishAligned = sma10 < sma20 && sma20 < sma50 && sma50 < sma200
        
        // Key check: is 10 SMA above 20 SMA? (market regime indicator)
        let sma10Above20 = sma10 > sma20
        
        let order: String
        if bullishAligned {
            order = "bullish_perfect"
        } else if sma10 > sma20 && sma20 > sma50 {
            order = "bullish_partial"
        } else if bearishAligned {
            order = "bearish_perfect"
        } else if sma10 < sma20 && sma20 < sma50 {
            order = "bearish_partial"
        } else {
            order = "mixed"
        }
        
        return (bullishAligned || bearishAligned, order, sma10Above20, sma10Above20, allInclining)
    }
    
    /// Range tightness detector - identifies consolidation (narrowing price range)
    /// Used to spot potential breakout setups where range is tightening
    static func rangeTightness(closes: [Double], period: Int = 10) -> (tightening: Bool, ratio: Double, avgRange: Double)? {
        guard closes.count >= period * 2 else { return nil }
        
        // Calculate range (high-low approximation from closes) for recent vs older period
        func calculateRange(_ data: ArraySlice<Double>) -> Double {
            guard let max = data.max(), let min = data.min() else { return 0 }
            return max - min
        }
        
        let recentData = closes.suffix(period)
        let olderData = closes.dropLast(period).suffix(period)
        
        let recentRange = calculateRange(recentData)
        let olderRange = calculateRange(olderData)
        
        guard olderRange > 0 else { return nil }
        
        let ratio = recentRange / olderRange
        
        // Tightening if recent range is less than 70% of older range
        let tightening = ratio < 0.7
        
        // Calculate average range as percentage
        let avgPrice = recentData.reduce(0, +) / Double(period)
        let avgRangePct = avgPrice > 0 ? (recentRange / avgPrice) * 100 : 0
        
        return (tightening, ratio, avgRangePct)
    }
    
    /// Breakout result structure
    struct BreakoutResult {
        let isBreakout: Bool
        let direction: String // "bullish" or "bearish"
        let breakoutPrice: Double
        let supportLevel: Double
        let resistanceLevel: Double
        let volumeConfirmed: Bool
        let score: Int // 0-100 confidence score
        let notes: [String]
    }
    
    /// Comprehensive breakout detector using the 5-step process
    /// 1. Prior move (30%+ gain)
    /// 2. MA inclining (10/20 SMA)
    /// 3. Orderly pullback with tightening range
    /// 4. Volume drying up
    /// 5. Breakout on increased volume
    static func detectBreakout(closes: [Double], volumes: [Double], highs: [Double]? = nil, lows: [Double]? = nil) -> BreakoutResult? {
        guard closes.count >= 50, volumes.count >= 50 else { return nil }
        guard closes.count == volumes.count else { return nil }
        
        var score = 0
        var notes: [String] = []
        
        // Use closes for high/low if not provided
        let highsData = highs ?? closes
        let lowsData = lows ?? closes
        
        // Step 1: Check for prior move (30%+ over 20-50 days)
        let lookbackStart = max(0, closes.count - 50)
        let lookbackEnd = max(0, closes.count - 10)
        guard lookbackStart < lookbackEnd else { return nil }
        
        let priorLow = closes[lookbackStart..<lookbackEnd].min() ?? closes[lookbackStart]
        let priorHigh = closes[lookbackStart..<lookbackEnd].max() ?? closes[lookbackEnd]
        let priorMove = priorLow > 0 ? ((priorHigh - priorLow) / priorLow) * 100 : 0
        
        if priorMove >= 30 {
            score += 20
            notes.append("Prior move: +\(String(format: "%.1f", priorMove))% (meets 30%+ criteria)")
        } else if priorMove >= 15 {
            score += 10
            notes.append("Prior move: +\(String(format: "%.1f", priorMove))% (partial, below 30%)")
        } else {
            notes.append("Prior move: +\(String(format: "%.1f", priorMove))% (weak, need 30%+)")
        }
        
        // Step 2: Check MA alignment and inclining
        if let maResult = maAlignment(closes: closes) {
            if maResult.sma10Above20 && maResult.allInclining {
                score += 20
                notes.append("10/20 SMA inclining and aligned (bullish)")
            } else if maResult.sma10Above20 {
                score += 10
                notes.append("10 SMA > 20 SMA but not all inclining")
            } else {
                notes.append("10 SMA below 20 SMA (bearish conditions)")
            }
        }
        
        // Step 3: Check for orderly pullback with tightening range
        if let rangeResult = rangeTightness(closes: closes, period: 10) {
            if rangeResult.tightening {
                score += 20
                notes.append("Range tightening: \(String(format: "%.1f", rangeResult.ratio * 100))% of prior range (consolidating)")
            } else {
                notes.append("Range not tightening yet")
            }
        }
        
        // Step 4: Check volume drying up
        if let volResult = volumeTrend(volumes: volumes) {
            if volResult.dryingUp {
                score += 20
                notes.append("Volume drying up: \(String(format: "%.1f", volResult.ratio * 100))% of average (good)")
            } else if volResult.trend == "neutral" {
                score += 5
                notes.append("Volume neutral")
            } else {
                notes.append("Volume expanding (not ideal for setup)")
            }
        }
        
        // Step 5: Check for breakout (price above recent range with volume)
        let recentHigh = highsData.suffix(10).max() ?? closes.last!
        let recentLow = lowsData.suffix(10).min() ?? closes.last!
        let currentPrice = closes.last ?? 0
        let avgRecentVol = volumes.suffix(5).reduce(0, +) / 5
        let avgPriorVol = volumes.dropLast(5).suffix(20).reduce(0, +) / 20
        
        let priceAboveRange = currentPrice > recentHigh * 0.99 // Within 1% of high
        let volumeExpanding = avgPriorVol > 0 ? (avgRecentVol / avgPriorVol) > 1.2 : false
        
        if priceAboveRange && volumeExpanding {
            score += 20
            notes.append("BREAKOUT IN PROGRESS: Price at range high with volume expansion!")
        } else if priceAboveRange {
            score += 10
            notes.append("Price near range high, waiting for volume confirmation")
        } else {
            notes.append("Price not at breakout level yet")
        }
        
        // Calculate support/resistance levels
        let resistanceLevel = recentHigh
        let supportLevel = recentLow
        
        // Determine if this is a valid breakout
        let isBreakout = score >= 60 && priceAboveRange
        
        return BreakoutResult(
            isBreakout: isBreakout,
            direction: "bullish",
            breakoutPrice: resistanceLevel,
            supportLevel: supportLevel,
            resistanceLevel: resistanceLevel,
            volumeConfirmed: volumeExpanding,
            score: score,
            notes: notes
        )
    }
    
    /// Calculate the gain from a starting point to find prior move percentage
    static func priorMovePercent(closes: [Double], lookbackDays: Int = 30) -> Double? {
        guard closes.count > lookbackDays else { return nil }
        
        let startIndex = closes.count - lookbackDays
        let startPrice = closes[startIndex]
        let endPrice = closes.last ?? 0
        
        guard startPrice > 0 else { return nil }
        return ((endPrice - startPrice) / startPrice) * 100
    }
    
    /// Simple trend direction based on closes vs MA
    static func trendDirection(closes: [Double], maPeriod: Int = 20) -> String? {
        guard let currentSMA = sma(closes, period: maPeriod) else { return nil }
        guard let currentPrice = closes.last else { return nil }
        
        // Price above SMA = bullish, below = bearish
        if currentPrice > currentSMA * 1.02 {
            return "bullish"
        } else if currentPrice < currentSMA * 0.98 {
            return "bearish"
        } else {
            return "neutral"
        }
    }
    
    /// Get all key SMA values at once
    static func getAllSMAs(closes: [Double]) -> (sma10: Double?, sma20: Double?, sma50: Double?, sma200: Double?) {
        return (
            sma(closes, period: 10),
            sma(closes, period: 20),
            sma(closes, period: 50),
            sma(closes, period: 200)
        )
    }
    
    // MARK: - CryptoSage AI Advanced Indicators
    
    /// Z-Score: Statistical deviation from mean
    /// z = (price - mean) / stddev
    /// Used for mean reversion: |z| > 2 indicates extreme deviation
    static func zScore(_ closes: [Double], period: Int = 20) -> Double? {
        guard closes.count >= period else { return nil }
        let tail = closes.suffix(period)
        let mean = tail.reduce(0, +) / Double(period)
        let sd = stddev(tail)
        guard sd > 0, let currentPrice = closes.last else { return nil }
        return (currentPrice - mean) / sd
    }
    
    /// Z-Score series for charting
    static func zScoreSeries(_ closes: [Double], period: Int = 20) -> [Double]? {
        guard closes.count >= period else { return nil }
        var series: [Double] = []
        
        for i in (period - 1)..<closes.count {
            let window = closes[(i - period + 1)...i]
            let mean = window.reduce(0, +) / Double(period)
            let sd = stddev(window)
            if sd > 0 {
                series.append((closes[i] - mean) / sd)
            } else {
                series.append(0)
            }
        }
        return series.isEmpty ? nil : series
    }
    
    /// Bollinger %B: Normalized position within Bollinger Bands
    /// %B = (Price - Lower Band) / (Upper Band - Lower Band)
    /// %B < 0 = below lower band, %B > 1 = above upper band
    /// %B = 0.5 = at middle band
    static func bollingerPercentB(_ closes: [Double], period: Int = 20, k: Double = 2.0) -> Double? {
        guard let bands = bollingerBands(closes, period: period, k: k) else { return nil }
        guard let currentPrice = closes.last else { return nil }
        let bandWidth = bands.upper - bands.lower
        guard bandWidth > 0 else { return 0.5 }
        return (currentPrice - bands.lower) / bandWidth
    }
    
    /// Bollinger Band Width: Measures volatility (width of bands relative to middle)
    /// BBW = (Upper - Lower) / Middle * 100
    /// Low BBW indicates consolidation (potential squeeze), high BBW indicates high volatility
    static func bollingerBandWidth(_ closes: [Double], period: Int = 20, k: Double = 2.0) -> Double? {
        guard let bands = bollingerBands(closes, period: period, k: k) else { return nil }
        guard bands.middle > 0 else { return nil }
        return ((bands.upper - bands.lower) / bands.middle) * 100
    }
    
    /// Bollinger Band Width series for charting and squeeze detection
    static func bollingerBandWidthSeries(_ closes: [Double], period: Int = 20, k: Double = 2.0) -> [Double]? {
        guard closes.count >= period else { return nil }
        var series: [Double] = []
        
        for i in (period - 1)..<closes.count {
            let window = Array(closes[(i - period + 1)...i])
            if let bands = bollingerBands(window, period: period, k: k), bands.middle > 0 {
                series.append(((bands.upper - bands.lower) / bands.middle) * 100)
            }
        }
        return series.isEmpty ? nil : series
    }
    
    /// Keltner Channels: ATR-based channels for squeeze detection
    /// Middle = EMA(20), Upper/Lower = Middle ± multiplier * ATR
    /// When BB inside Keltner = "squeeze" (low volatility, breakout pending)
    static func keltnerChannels(_ closes: [Double], period: Int = 20, atrPeriod: Int = 10, multiplier: Double = 1.5) -> (middle: Double, upper: Double, lower: Double)? {
        guard closes.count >= max(period, atrPeriod) else { return nil }
        
        // Middle line = EMA
        guard let middle = ema(closes, period: period) else { return nil }
        
        // ATR approximation from closes
        guard let atrData = atrApproxFromCloses(closes, period: atrPeriod) else { return nil }
        let atr = atrData.atr
        
        let upper = middle + (multiplier * atr)
        let lower = middle - (multiplier * atr)
        
        return (middle, upper, lower)
    }
    
    /// Squeeze indicator: Detects when Bollinger Bands are inside Keltner Channels
    /// Returns (isSqueeze, squeezeIntensity) where intensity is how tight the squeeze is
    static func detectSqueeze(_ closes: [Double], bbPeriod: Int = 20, bbK: Double = 2.0, keltnerPeriod: Int = 20, keltnerMultiplier: Double = 1.5) -> (isSqueeze: Bool, intensity: Double)? {
        guard let bb = bollingerBands(closes, period: bbPeriod, k: bbK),
              let keltner = keltnerChannels(closes, period: keltnerPeriod, multiplier: keltnerMultiplier) else {
            return nil
        }
        
        // Squeeze occurs when BB is inside Keltner
        let isSqueeze = bb.lower > keltner.lower && bb.upper < keltner.upper
        
        // Intensity: how much BB is inside Keltner (0 = barely, 1 = very tight)
        let bbWidth = bb.upper - bb.lower
        let keltnerWidth = keltner.upper - keltner.lower
        let intensity = keltnerWidth > 0 ? max(0, 1 - (bbWidth / keltnerWidth)) : 0
        
        return (isSqueeze, intensity)
    }
    
    /// Rate of Change at multiple periods for momentum cascade
    /// Returns ROC at 10, 20, and 50 periods
    static func rocMultiple(_ closes: [Double]) -> (roc10: Double?, roc20: Double?, roc50: Double?) {
        return (
            roc(closes, period: 10),
            roc(closes, period: 20),
            roc(closes, period: 50)
        )
    }
    
    /// EMA series for charting
    static func emaSeries(_ closes: [Double], period: Int) -> [Double]? {
        guard closes.count >= period else { return nil }
        let k = 2.0 / Double(period + 1)
        var series: [Double] = []
        
        for i in 0..<closes.count {
            if i == 0 {
                series.append(closes[0])
            } else {
                series.append(closes[i] * k + series[i-1] * (1 - k))
            }
        }
        return series
    }
    
    /// SMA series for charting
    static func smaSeries(_ closes: [Double], period: Int) -> [Double]? {
        guard closes.count >= period else { return nil }
        var series: [Double] = []
        
        for i in (period - 1)..<closes.count {
            let window = closes[(i - period + 1)...i]
            series.append(window.reduce(0, +) / Double(period))
        }
        return series
    }
    
    /// RSI trend direction: Is RSI rising or falling?
    /// Returns (current RSI, trend direction, momentum)
    static func rsiTrend(_ closes: [Double], period: Int = 14, lookback: Int = 5) -> (rsi: Double, trend: String, momentum: Double)? {
        guard let rsiValues = rsiSeries(closes, period: period), rsiValues.count >= lookback else {
            return nil
        }
        
        guard let currentRSI = rsiValues.last else { return nil }
        let recentRSI = Array(rsiValues.suffix(lookback))
        
        // Calculate RSI momentum (current - lookback periods ago)
        let oldRSI = recentRSI.first ?? currentRSI
        let momentum = currentRSI - oldRSI
        
        // Determine trend
        let trend: String
        if momentum > 5 {
            trend = "rising"
        } else if momentum < -5 {
            trend = "falling"
        } else {
            trend = "neutral"
        }
        
        return (currentRSI, trend, momentum)
    }
    
    /// MACD histogram slope: Is momentum accelerating or decelerating?
    /// Returns (histogram, slope, accelerating)
    static func macdSlope(_ closes: [Double], lookback: Int = 3) -> (histogram: Double, slope: Double, accelerating: Bool)? {
        guard let macd = macdSeries(closes), macd.histogram.count >= lookback else {
            return nil
        }
        
        let recent = Array(macd.histogram.suffix(lookback))
        guard let current = recent.last, let old = recent.first else { return nil }
        
        let slope = (current - old) / Double(lookback - 1)
        let accelerating = slope > 0 && current > 0 // Positive and increasing
        
        return (current, slope, accelerating)
    }
    
    /// OBV trend: Is volume confirming price movement?
    /// Returns (obv, trend, divergence)
    static func obvTrend(closes: [Double], volumes: [Double], lookback: Int = 10) -> (obv: Double, trend: String, priceOBVAligned: Bool)? {
        guard let obvValues = obvSeries(closes: closes, volumes: volumes), obvValues.count >= lookback else {
            return nil
        }
        guard closes.count >= lookback else { return nil }
        
        guard let currentOBV = obvValues.last else { return nil }
        let oldOBV = obvValues[obvValues.count - lookback]
        let obvChange = currentOBV - oldOBV
        
        guard let currentPrice = closes.last else { return nil }
        let oldPrice = closes[closes.count - lookback]
        let priceChange = currentPrice - oldPrice
        
        // OBV trend
        let trend: String
        if obvChange > 0 {
            trend = "accumulation"
        } else if obvChange < 0 {
            trend = "distribution"
        } else {
            trend = "neutral"
        }
        
        // Check if price and OBV are aligned (both up or both down)
        let aligned = (priceChange > 0 && obvChange > 0) || (priceChange < 0 && obvChange < 0)
        
        return (currentOBV, trend, aligned)
    }
    
    /// Full ADX calculation with +DI and -DI
    /// Enhanced version with proper Wilder smoothing
    static func adx(_ closes: [Double], period: Int = 14) -> (adx: Double, plusDI: Double, minusDI: Double, trend: String)? {
        guard let result = adxApprox(closes, period: period) else { return nil }
        
        // Determine trend based on ADX and DI values
        let trend: String
        if result.adx > 25 {
            if result.plusDI > result.minusDI {
                trend = result.adx > 40 ? "strong_uptrend" : "uptrend"
            } else {
                trend = result.adx > 40 ? "strong_downtrend" : "downtrend"
            }
        } else if result.adx < 20 {
            trend = "ranging"
        } else {
            trend = "weak_trend"
        }
        
        return (result.adx, result.plusDI, result.minusDI, trend)
    }
    
    /// Comprehensive regime detection for CryptoSage AI
    /// Combines ADX, BB width, ATR, and OBV for regime classification
    static func detectMarketRegime(closes: [Double], volumes: [Double]) -> (regime: String, confidence: Double, details: [String: Any])? {
        guard closes.count >= 50 else { return nil }
        
        var details: [String: Any] = [:]
        var regimeScores: [String: Double] = [
            "strongTrend": 0,
            "trending": 0,
            "weakTrend": 0,
            "ranging": 0,
            "volatile": 0,
            "accumulation": 0,
            "distribution": 0
        ]
        
        // 1. ADX analysis
        if let adxResult = adx(closes) {
            details["adx"] = adxResult.adx
            details["plusDI"] = adxResult.plusDI
            details["minusDI"] = adxResult.minusDI
            
            if adxResult.adx > 40 {
                regimeScores["strongTrend"]! += 40
            } else if adxResult.adx > 25 {
                regimeScores["trending"]! += 30
            } else if adxResult.adx > 20 {
                regimeScores["weakTrend"]! += 25
            } else {
                regimeScores["ranging"]! += 35
            }
        }
        
        // 2. BB width analysis (volatility)
        if let bbWidth = bollingerBandWidth(closes) {
            details["bbWidth"] = bbWidth
            
            if bbWidth < 5 {
                // Very low volatility - potential squeeze
                regimeScores["ranging"]! += 20
                regimeScores["accumulation"]! += 15
            } else if bbWidth > 15 {
                // High volatility
                regimeScores["volatile"]! += 25
            }
        }
        
        // 3. Squeeze detection
        if let squeeze = detectSqueeze(closes) {
            details["isSqueeze"] = squeeze.isSqueeze
            details["squeezeIntensity"] = squeeze.intensity
            
            if squeeze.isSqueeze {
                regimeScores["accumulation"]! += 20
                regimeScores["ranging"]! += 10
            }
        }
        
        // 4. ATR trend (is volatility expanding or contracting?)
        if let atrData = atrApproxFromCloses(closes) {
            details["atrPercent"] = atrData.atrPercent
            
            if atrData.atrPercent > 5 {
                regimeScores["volatile"]! += 20
            }
        }
        
        // 5. OBV analysis for accumulation/distribution
        if let obvResult = obvTrend(closes: closes, volumes: volumes) {
            details["obvTrend"] = obvResult.trend
            details["priceOBVAligned"] = obvResult.priceOBVAligned
            
            if obvResult.trend == "accumulation" {
                regimeScores["accumulation"]! += 25
            } else if obvResult.trend == "distribution" {
                regimeScores["distribution"]! += 25
            }
            
            // Divergence detection
            if !obvResult.priceOBVAligned {
                if obvResult.trend == "distribution" {
                    regimeScores["distribution"]! += 15
                } else if obvResult.trend == "accumulation" {
                    regimeScores["accumulation"]! += 15
                }
            }
        }
        
        // 6. Price vs MAs for trend confirmation
        if let maResult = maAlignment(closes: closes) {
            details["maOrder"] = maResult.order
            details["allInclining"] = maResult.allInclining
            
            if maResult.aligned && maResult.allInclining {
                regimeScores["trending"]! += 15
                regimeScores["strongTrend"]! += 10
            }
        }
        
        // Find winning regime
        let sortedRegimes = regimeScores.sorted { $0.value > $1.value }
        guard let topRegime = sortedRegimes.first else { return nil }
        
        // Calculate confidence (top score / max possible)
        let maxPossible: Double = 100
        let confidence = min(topRegime.value / maxPossible, 1.0)
        
        details["allScores"] = regimeScores
        
        return (topRegime.key, confidence, details)
    }
    
    // MARK: - Enhanced Trading Level Calculations
    
    /// ATR approximation using only close prices (when high/low not available)
    /// Uses absolute close-to-close changes as a proxy for true range
    /// Returns ATR as a percentage of current price for easier use
    static func atrApproxFromCloses(_ closes: [Double], period: Int = 14) -> (atr: Double, atrPercent: Double)? {
        guard closes.count > period else { return nil }
        
        // Calculate absolute changes as proxy for true range
        var ranges: [Double] = []
        for i in 1..<closes.count {
            let change = abs(closes[i] - closes[i-1])
            ranges.append(change)
        }
        
        guard ranges.count >= period else { return nil }
        
        // Wilder smoothing
        var atr = ranges.prefix(period).reduce(0, +) / Double(period)
        for i in period..<ranges.count {
            atr = (atr * Double(period - 1) + ranges[i]) / Double(period)
        }
        
        // Calculate as percentage of current price
        guard let currentPrice = closes.last, currentPrice > 0 else { return nil }
        let atrPercent = (atr / currentPrice) * 100
        
        return (atr, atrPercent)
    }
    
    /// Pivot-based Support and Resistance detection
    /// Identifies significant price pivots (swing highs and lows) from price action
    struct PivotLevels {
        let resistance1: Double   // Nearest resistance
        let resistance2: Double?  // Second resistance
        let support1: Double      // Nearest support
        let support2: Double?     // Second support
        let pivotPoint: Double    // Classic pivot point
        let currentPrice: Double
        
        /// Distance to nearest resistance as percentage
        var resistanceDistancePercent: Double {
            guard currentPrice > 0 else { return 0 }
            return ((resistance1 - currentPrice) / currentPrice) * 100
        }
        
        /// Distance to nearest support as percentage
        var supportDistancePercent: Double {
            guard currentPrice > 0 else { return 0 }
            return ((currentPrice - support1) / currentPrice) * 100
        }
    }
    
    /// Detect pivot-based support and resistance levels
    /// Uses swing high/low detection with lookback window
    static func detectPivotLevels(_ closes: [Double], lookback: Int = 5) -> PivotLevels? {
        guard closes.count >= lookback * 3 else { return nil }
        guard let currentPrice = closes.last else { return nil }
        
        var swingHighs: [Double] = []
        var swingLows: [Double] = []
        
        // Find swing highs and lows
        for i in lookback..<(closes.count - lookback) {
            let leftWindow = Array(closes[(i - lookback)..<i])
            let rightWindow = Array(closes[(i + 1)...(i + lookback)])
            let current = closes[i]
            
            // Swing high: higher than all neighbors
            if let leftMax = leftWindow.max(), let rightMax = rightWindow.max() {
                if current > leftMax && current > rightMax {
                    swingHighs.append(current)
                }
            }
            
            // Swing low: lower than all neighbors
            if let leftMin = leftWindow.min(), let rightMin = rightWindow.min() {
                if current < leftMin && current < rightMin {
                    swingLows.append(current)
                }
            }
        }
        
        // Sort levels
        let sortedHighs = swingHighs.sorted(by: >)
        let sortedLows = swingLows.sorted()
        
        // Find resistance levels (above current price)
        let resistanceAbove = sortedHighs.filter { $0 > currentPrice * 1.001 }
        let resistance1 = resistanceAbove.min() ?? (closes.max() ?? currentPrice * 1.05)
        let resistance2 = resistanceAbove.count > 1 ? resistanceAbove.sorted()[1] : nil
        
        // Find support levels (below current price)
        let supportBelow = sortedLows.filter { $0 < currentPrice * 0.999 }
        let support1 = supportBelow.max() ?? (closes.min() ?? currentPrice * 0.95)
        let support2 = supportBelow.count > 1 ? supportBelow.sorted(by: >)[1] : nil
        
        // Classic pivot point calculation (using recent data)
        let recentCloses = Array(closes.suffix(20))
        let high = recentCloses.max() ?? currentPrice
        let low = recentCloses.min() ?? currentPrice
        let close = currentPrice
        let pivotPoint = (high + low + close) / 3.0
        
        return PivotLevels(
            resistance1: resistance1,
            resistance2: resistance2,
            support1: support1,
            support2: support2,
            pivotPoint: pivotPoint,
            currentPrice: currentPrice
        )
    }
    
    /// Fibonacci Retracement Levels
    /// Calculates key Fibonacci levels from a swing high to swing low
    struct FibonacciLevels {
        let high: Double
        let low: Double
        let range: Double
        let level236: Double  // 23.6% retracement
        let level382: Double  // 38.2% retracement (key level)
        let level500: Double  // 50% retracement
        let level618: Double  // 61.8% retracement (golden ratio)
        let level786: Double  // 78.6% retracement
        
        /// Get the nearest Fibonacci level above a price
        func nearestLevelAbove(_ price: Double) -> Double {
            let levels = [level236, level382, level500, level618, level786, high]
            return levels.filter { $0 > price }.min() ?? high
        }
        
        /// Get the nearest Fibonacci level below a price
        func nearestLevelBelow(_ price: Double) -> Double {
            let levels = [low, level786, level618, level500, level382, level236]
            return levels.filter { $0 < price }.max() ?? low
        }
    }
    
    /// Calculate Fibonacci retracement levels from recent price action
    /// Automatically detects the swing high and low from the data
    static func fibonacciLevels(_ closes: [Double], lookbackPeriod: Int = 50) -> FibonacciLevels? {
        guard closes.count >= lookbackPeriod else { return nil }
        
        let recentData = Array(closes.suffix(lookbackPeriod))
        guard let high = recentData.max(), let low = recentData.min() else { return nil }
        guard high > low else { return nil }
        
        let range = high - low
        
        // Fibonacci levels (calculated as retracements from high to low)
        // For an uptrend, these are potential support levels on pullback
        return FibonacciLevels(
            high: high,
            low: low,
            range: range,
            level236: high - (range * 0.236),
            level382: high - (range * 0.382),
            level500: high - (range * 0.500),
            level618: high - (range * 0.618),
            level786: high - (range * 0.786)
        )
    }
    
    /// Enhanced trading levels calculation combining ATR, Pivots, and Fibonacci
    struct EnhancedTradingLevels {
        let entryZoneLow: Double
        let entryZoneHigh: Double
        let stopLoss: Double
        let takeProfit: Double      // Primary target (TP3 - full target)
        let riskRewardRatio: Double
        let stopLossPercent: Double
        let takeProfitPercent: Double
        let atrMultipleUsed: Double
        let pivotSupport: Double?
        let pivotResistance: Double?
        let fibLevel: Double?
        let methodology: String  // Description of how levels were calculated
        
        // Multiple take profit levels for scaling out positions
        let takeProfit1: Double     // TP1 - Conservative (33% of move)
        let takeProfit2: Double     // TP2 - Moderate (66% of move)
        let tp1Percent: Double
        let tp2Percent: Double
        let tp3Percent: Double      // Same as takeProfitPercent (full target)
    }
    
    /// Calculate enhanced trading levels using ATR, pivots, and Fibonacci
    /// - Parameters:
    ///   - closes: Price history (sparkline data)
    ///   - currentPrice: Current market price
    ///   - direction: "bullish", "bearish", or "neutral"
    ///   - predictedChange: AI-predicted percentage change
    ///   - predictedHigh: AI-predicted high price
    ///   - predictedLow: AI-predicted low price
    ///   - timeframe: Trading timeframe for ATR multiplier adjustment
    static func calculateEnhancedTradingLevels(
        closes: [Double],
        currentPrice: Double,
        direction: String,
        predictedChange: Double,
        predictedHigh: Double,
        predictedLow: Double,
        timeframe: String = "1d"
    ) -> EnhancedTradingLevels {
        
        // Get ATR for volatility-based stops
        let atrData = atrApproxFromCloses(closes, period: 14)
        let atrPercent = atrData?.atrPercent ?? 2.0  // Default 2% if ATR unavailable
        
        // ATR multiplier based on timeframe (tighter for shorter timeframes)
        let atrMultiplier: Double = {
            switch timeframe.lowercased() {
            case "1h": return 1.0
            case "4h": return 1.5
            case "12h": return 1.8
            case "1d", "24h": return 2.0
            case "7d": return 2.5
            case "30d": return 3.0
            case "90d": return 3.5
            case "1y": return 4.0
            default: return 2.0
            }
        }()
        
        // Get pivot levels for S/R awareness
        let pivots = detectPivotLevels(closes)
        
        // Get Fibonacci levels for entry zones
        let fibs = fibonacciLevels(closes)
        
        var methodology: [String] = []
        
        // Calculate entry zone, stop loss, and take profit based on direction
        var entryZoneLow: Double
        var entryZoneHigh: Double
        let stopLoss: Double
        let takeProfit: Double
        
        if direction == "bullish" {
            // ENTRY ZONE: Use Fibonacci 38.2% or 50% retracement as potential entry
            if let fib = fibs {
                // Entry zone between 38.2% and 23.6% Fib levels (buying the dip)
                entryZoneLow = max(fib.level382, currentPrice * 0.97)  // Not more than 3% below
                entryZoneHigh = min(fib.level236, currentPrice * 1.005)
                methodology.append("Entry: Fib 38.2%-23.6%")
            } else {
                // Fallback: small pullback zone
                let pullback = min(abs(predictedChange) * 0.3, 2.0)
                entryZoneLow = currentPrice * (1 - pullback / 100)
                entryZoneHigh = currentPrice * 1.002
                methodology.append("Entry: Pullback zone")
            }
            
            // STOP LOSS: ATR-based with pivot support awareness
            let atrStop = currentPrice * (1 - (atrPercent * atrMultiplier) / 100)
            
            // Use pivot support if it provides a better (tighter) stop
            if let pivotSupport = pivots?.support1, pivotSupport > atrStop && pivotSupport < currentPrice * 0.99 {
                // Place stop just below pivot support
                stopLoss = pivotSupport * 0.995
                methodology.append("Stop: Below pivot support")
            } else {
                // Use ATR-based stop
                stopLoss = atrStop
                methodology.append("Stop: \(String(format: "%.1f", atrMultiplier))x ATR")
            }
            
            // TAKE PROFIT: Use pivot resistance or predicted high
            if let pivotResistance = pivots?.resistance1, pivotResistance > currentPrice {
                // First target at pivot resistance
                takeProfit = max(pivotResistance, predictedHigh)
                methodology.append("Target: Pivot resistance")
            } else {
                takeProfit = predictedHigh
                methodology.append("Target: AI predicted high")
            }
            
        } else if direction == "bearish" {
            // ENTRY ZONE for short: Wait for bounce to resistance
            if let fib = fibs {
                entryZoneLow = max(fib.level236, currentPrice * 0.995)
                entryZoneHigh = min(fib.level382, currentPrice * 1.03)
                methodology.append("Entry: Fib bounce zone")
            } else {
                let bounce = min(abs(predictedChange) * 0.3, 2.0)
                entryZoneLow = currentPrice * 0.998
                entryZoneHigh = currentPrice * (1 + bounce / 100)
                methodology.append("Entry: Bounce zone")
            }
            
            // STOP LOSS for short: ATR-based above current with resistance awareness
            let atrStop = currentPrice * (1 + (atrPercent * atrMultiplier) / 100)
            
            if let pivotResistance = pivots?.resistance1, pivotResistance < atrStop && pivotResistance > currentPrice * 1.01 {
                stopLoss = pivotResistance * 1.005
                methodology.append("Stop: Above pivot resistance")
            } else {
                stopLoss = atrStop
                methodology.append("Stop: \(String(format: "%.1f", atrMultiplier))x ATR")
            }
            
            // TAKE PROFIT for short
            if let pivotSupport = pivots?.support1, pivotSupport < currentPrice {
                takeProfit = min(pivotSupport, predictedLow)
                methodology.append("Target: Pivot support")
            } else {
                takeProfit = predictedLow
                methodology.append("Target: AI predicted low")
            }
            
        } else {
            // NEUTRAL: Range trading setup
            if let fib = fibs {
                entryZoneLow = fib.level618
                entryZoneHigh = fib.level382
            } else {
                entryZoneLow = predictedLow
                entryZoneHigh = predictedHigh
            }
            stopLoss = predictedLow * 0.98
            takeProfit = predictedHigh
            methodology.append("Range trade setup")
        }
        
        // Maximum stop loss percentages per timeframe (professional risk management)
        let maxStopLossPercent: Double = {
            switch timeframe.lowercased() {
            case "1h": return 2.0
            case "4h": return 3.5
            case "12h": return 4.5
            case "1d", "24h": return 5.0
            case "7d": return 8.0
            case "30d": return 12.0
            case "90d": return 18.0
            case "1y": return 25.0
            default: return 5.0
            }
        }()
        
        // Cap stop loss at max percentage to avoid unrealistic stops
        var finalStopLoss = stopLoss
        var finalTakeProfit = takeProfit
        
        let rawStopPercent = abs((stopLoss - currentPrice) / currentPrice * 100)
        if rawStopPercent > maxStopLossPercent {
            if direction == "bullish" {
                finalStopLoss = currentPrice * (1 - maxStopLossPercent / 100)
            } else if direction == "bearish" {
                finalStopLoss = currentPrice * (1 + maxStopLossPercent / 100)
            }
            methodology.append("Stop capped at \(String(format: "%.0f", maxStopLossPercent))%")
        }
        
        // Calculate risk and reward with capped stop
        let risk = abs(currentPrice - finalStopLoss)
        let reward = abs(finalTakeProfit - currentPrice)
        var riskRewardRatio = risk > 0 ? reward / risk : 1.0
        
        // Enforce minimum R:R of 1.5:1 for professional-grade setups
        let minAcceptableRR: Double = 1.5
        if riskRewardRatio < minAcceptableRR && risk > 0 {
            // Adjust take profit to achieve minimum R:R
            let requiredReward = risk * minAcceptableRR
            if direction == "bullish" {
                finalTakeProfit = currentPrice + requiredReward
            } else if direction == "bearish" {
                finalTakeProfit = currentPrice - requiredReward
            } else {
                // Neutral - adjust high target
                finalTakeProfit = currentPrice + requiredReward
            }
            riskRewardRatio = minAcceptableRR
            methodology.append("R:R adjusted to 1:1.5")
        }
        
        // === VALIDATION: Ensure meaningful separation between levels ===
        // Minimum move percentages per timeframe so entry ≠ TP and levels make sense
        let minMovePercent: Double = {
            switch timeframe.lowercased() {
            case "1h": return 0.5
            case "4h": return 1.0
            case "12h": return 1.5
            case "1d", "24h": return 2.0
            case "7d": return 4.0
            case "30d": return 8.0
            case "90d": return 12.0
            case "1y": return 18.0
            default: return 2.0
            }
        }()
        
        // Ensure take profit is far enough from current price
        let currentTPPercent = abs((finalTakeProfit - currentPrice) / currentPrice * 100)
        if currentTPPercent < minMovePercent {
            if direction == "bullish" {
                finalTakeProfit = currentPrice * (1 + minMovePercent / 100)
            } else if direction == "bearish" {
                finalTakeProfit = currentPrice * (1 - minMovePercent / 100)
            } else {
                finalTakeProfit = currentPrice * (1 + minMovePercent / 100)
            }
            // Re-check R:R after TP adjustment
            let adjReward = abs(finalTakeProfit - currentPrice)
            let adjRisk = abs(currentPrice - finalStopLoss)
            riskRewardRatio = adjRisk > 0 ? adjReward / adjRisk : 1.5
            methodology.append("Target widened to min \(String(format: "%.1f", minMovePercent))%")
        }
        
        // Ensure entry zone high is meaningfully below take profit (bullish)
        // or above take profit (bearish) — at least 40% of the move away
        if direction == "bullish" {
            let moveToBullTP = finalTakeProfit - currentPrice
            let maxEntryHigh = currentPrice + moveToBullTP * 0.35  // Entry no higher than 35% of the move
            if entryZoneHigh > maxEntryHigh {
                entryZoneHigh = maxEntryHigh
            }
            // Ensure entry low < entry high
            if entryZoneLow >= entryZoneHigh {
                entryZoneLow = currentPrice * 0.995
            }
        } else if direction == "bearish" {
            let moveToBearTP = currentPrice - finalTakeProfit
            let minEntryLow = currentPrice - moveToBearTP * 0.35
            if entryZoneLow < minEntryLow {
                entryZoneLow = minEntryLow
            }
            if entryZoneLow >= entryZoneHigh {
                entryZoneHigh = currentPrice * 1.005
            }
        }
        
        // Recalculate final percentages
        let stopLossPercent = abs((finalStopLoss - currentPrice) / currentPrice * 100)
        let takeProfitPercent = abs((finalTakeProfit - currentPrice) / currentPrice * 100)
        
        // Calculate multiple take profit levels for scaling out
        // TP1 = 33% of the move, TP2 = 66% of the move, TP3 = full target
        let priceMove = finalTakeProfit - currentPrice
        let tp1 = currentPrice + (priceMove * 0.33)
        let tp2 = currentPrice + (priceMove * 0.66)
        let tp1Percent = abs((tp1 - currentPrice) / currentPrice * 100)
        let tp2Percent = abs((tp2 - currentPrice) / currentPrice * 100)
        
        return EnhancedTradingLevels(
            entryZoneLow: entryZoneLow,
            entryZoneHigh: entryZoneHigh,
            stopLoss: finalStopLoss,
            takeProfit: finalTakeProfit,
            riskRewardRatio: riskRewardRatio,
            stopLossPercent: stopLossPercent,
            takeProfitPercent: takeProfitPercent,
            atrMultipleUsed: atrMultiplier,
            pivotSupport: pivots?.support1,
            pivotResistance: pivots?.resistance1,
            fibLevel: fibs?.level382,
            methodology: methodology.joined(separator: " | "),
            takeProfit1: tp1,
            takeProfit2: tp2,
            tp1Percent: tp1Percent,
            tp2Percent: tp2Percent,
            tp3Percent: takeProfitPercent
        )
    }
}
