import Foundation

public final class LiveChangeService {
    public static let shared = LiveChangeService()

    internal struct MinuteEntry {
        let minute: Int
        var price: Double
    }

    private let queue = DispatchQueue(label: "LiveChangeService.queue")
    private var history: [String: [MinuteEntry]] = [:]
    private let maxMinutes = 8 * 24 * 60

    private func minuteKey(for date: Date) -> Int {
        let timeInterval = date.timeIntervalSince1970
        return Int(timeInterval / 60.0)
    }

    public func ingest(prices: [String: Double], at date: Date = Date()) {
        queue.async {
            let minute = self.minuteKey(for: date)
            for (symbol, price) in prices {
                guard price.isFinite, price > 0 else { continue }
                let sym = symbol.uppercased()
                var entries = self.history[sym] ?? []
                if let last = entries.last, last.minute == minute {
                    entries[entries.count - 1].price = price
                } else {
                    entries.append(MinuteEntry(minute: minute, price: price))
                }
                while let first = entries.first, first.minute < minute - self.maxMinutes {
                    entries.removeFirst()
                }
                self.history[sym] = entries
            }
        }
    }

    public func change(symbol: String, lookbackHours: Int, livePrice: Double?) -> Double? {
        queue.sync {
            let sym = symbol.uppercased()
            guard let entries = history[sym], !entries.isEmpty else { return nil }
            let currentMinute = minuteKey(for: Date())
            let targetMinute = currentMinute - lookbackHours * 60
            // find latest entry with minute <= targetMinute by scanning from the end
            var foundEntry: MinuteEntry? = nil
            for entry in entries.reversed() {
                if entry.minute <= targetMinute {
                    foundEntry = entry
                    break
                }
            }
            guard let prevEntry = foundEntry else { return nil }
            let prev = prevEntry.price
            let curr = livePrice ?? entries.last!.price
            guard prev > 0, curr.isFinite, curr > 0 else { return nil }
            return ((curr - prev) / prev) * 100.0
        }
    }

    public func haveCoverage(symbol: String, hours: Int) -> Bool {
        queue.sync {
            let sym = symbol.uppercased()
            guard let entries = history[sym], entries.count >= 2 else { return false }
            let first = entries.first!
            let last = entries.last!
            let spanMinutes = last.minute - first.minute + 1
            let requiredMinutes = Int(Double(hours) * 60.0 * 0.8)
            return spanMinutes >= requiredMinutes
        }
    }
}
