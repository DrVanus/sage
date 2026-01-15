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
            var prev = input.first ?? 0
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
}
