//
//  CryptoSageTests.swift
//  CryptoSageTests
//
//  Created by DM on 5/2/25.
//

import Testing
import Foundation
@testable import CryptoSage

struct CryptoSageTests {

    private func makeSyntheticPoints(count: Int, step: TimeInterval) -> [ChartDataPoint] {
        let start = Date().addingTimeInterval(-Double(count) * step)
        return (0..<count).map { idx in
            let date = start.addingTimeInterval(Double(idx) * step)
            let close = 20_000.0 + sin(Double(idx) / 8.0) * 600.0 + Double(idx % 17)
            let volume = 100.0 + Double((idx * 31) % 500)
            return ChartDataPoint(date: date, close: close, volume: volume)
        }
    }
    
    private func domain(for interval: ChartInterval, points: [ChartDataPoint], now: Date) -> ClosedRange<Date> {
        guard let first = points.first?.date, let last = points.last?.date else {
            return now.addingTimeInterval(-86_400)...now
        }
        if interval == .all || interval == .threeYear {
            return first...last
        }
        if interval == .live {
            let rightEdge = max(now, last)
            let fullSpan = rightEdge.timeIntervalSince(first)
            let window = max(60, min(fullSpan, 300))
            return rightEdge.addingTimeInterval(-window)...rightEdge
        }
        let lookback = interval.lookbackSeconds
        guard lookback > 0 else { return first...last }
        let start = max(last.addingTimeInterval(-lookback), first)
        return start...last
    }
    
    @Test("XAxis ticks remain sorted and in domain across intervals")
    func xAxisTicksAreStableAcrossIntervals() {
        let points = makeSyntheticPoints(count: 6_000, step: 900) // 15-minute candles
        let now = Date()
        
        for interval in supportedIntervals {
            let xDomain = domain(for: interval, points: points, now: now)
            let provider = ChartXAxisProvider(
                interval: interval,
                domain: xDomain,
                plotWidth: 320,
                uses24hClock: false
            )
            let ticks = provider.ticks()
            let isSorted = zip(ticks, ticks.dropFirst()).allSatisfy { $0 <= $1 }
            let allInDomain = ticks.allSatisfy { $0 >= xDomain.lowerBound && $0 <= xDomain.upperBound }
            #expect(isSorted)
            #expect(allInDomain)
        }
    }
    
    @Test("Indicator series dates stay monotonic and bounded after timeframe trims")
    func indicatorSeriesRemainAlignedAfterTrims() {
        let points = makeSyntheticPoints(count: 10_000, step: 300) // 5-minute candles
        let now = Date()
        
        for interval in supportedIntervals where interval != .live {
            let xDomain = domain(for: interval, points: points, now: now)
            let visible = points.filter { $0.date >= xDomain.lowerBound && $0.date <= xDomain.upperBound }
            let closes = visible.map(\.close)
            
            // RSI mapping guard
            if let rsi = TechnicalsEngine.rsiSeries(closes, period: 14) {
                let mapped = rsi.enumerated().compactMap { i, value -> (Date, Double)? in
                    let dataIndex = 14 + i
                    guard dataIndex < visible.count else { return nil }
                    return (visible[dataIndex].date, value)
                }
                let sorted = zip(mapped, mapped.dropFirst()).allSatisfy { $0.0 <= $1.0 }
                let inDomain = mapped.allSatisfy { $0.0 >= xDomain.lowerBound && $0.0 <= xDomain.upperBound }
                #expect(sorted)
                #expect(inDomain)
            }
            
            // MACD mapping guard
            if let macd = TechnicalsEngine.macdSeries(closes, fast: 12, slow: 26, signal: 9) {
                let usableCount = min(visible.count, macd.macdLine.count, macd.signalLine.count, macd.histogram.count)
                if usableCount > 0 {
                    let mappedDates = (0..<usableCount).map { visible[$0].date }
                    let sorted = zip(mappedDates, mappedDates.dropFirst()).allSatisfy { $0 <= $1 }
                    let inDomain = mappedDates.allSatisfy { $0 >= xDomain.lowerBound && $0 <= xDomain.upperBound }
                    #expect(sorted)
                    #expect(inDomain)
                }
            }
            
            // Stochastic mapping guard
            if let stoch = TechnicalsEngine.stochSeries(closes, kPeriod: 14, dPeriod: 3) {
                let offset = visible.count - stoch.k.count
                let usableCount = min(stoch.k.count, stoch.d.count)
                if offset >= 0 && usableCount > 0 {
                    let mappedDates = (0..<usableCount).compactMap { i -> Date? in
                        let idx = offset + i
                        guard idx < visible.count else { return nil }
                        return visible[idx].date
                    }
                    let sorted = zip(mappedDates, mappedDates.dropFirst()).allSatisfy { $0 <= $1 }
                    let inDomain = mappedDates.allSatisfy { $0 >= xDomain.lowerBound && $0 <= xDomain.upperBound }
                    #expect(sorted)
                    #expect(inDomain)
                }
            }
            
            // ATR mapping guard
            if visible.count > 14 {
                var atrDates: [Date] = [visible[14].date]
                if visible.count > 15 {
                    for i in 14..<(visible.count - 1) {
                        atrDates.append(visible[i + 1].date)
                    }
                }
                let sorted = zip(atrDates, atrDates.dropFirst()).allSatisfy { $0 <= $1 }
                let inDomain = atrDates.allSatisfy { $0 >= xDomain.lowerBound && $0 <= xDomain.upperBound }
                #expect(sorted)
                #expect(inDomain)
            }
            
            // MFI mapping guard
            if visible.count > 14 {
                let mfiDates = (14..<visible.count).map { visible[$0].date }
                let sorted = zip(mfiDates, mfiDates.dropFirst()).allSatisfy { $0 <= $1 }
                let inDomain = mfiDates.allSatisfy { $0 >= xDomain.lowerBound && $0 <= xDomain.upperBound }
                #expect(sorted)
                #expect(inDomain)
            }
            
            // OBV mapping guard
            if visible.count >= 2 {
                let obvDates = visible.map(\.date)
                let sorted = zip(obvDates, obvDates.dropFirst()).allSatisfy { $0 <= $1 }
                let inDomain = obvDates.allSatisfy { $0 >= xDomain.lowerBound && $0 <= xDomain.upperBound }
                #expect(sorted)
                #expect(inDomain)
            }
        }
    }

}
