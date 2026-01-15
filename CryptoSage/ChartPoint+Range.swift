import Foundation

public struct ChartPoint {
    public let date: Date
    public let value: Double
    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public extension Array where Element == ChartPoint {
    func filtered(for range: HomeView.PortfolioRange) -> [ChartPoint] {
        guard !self.isEmpty else { return [] }
        switch range {
        case .all:
            return self
        case .day:
            let cutoff = Calendar.current.date(byAdding: .hour, value: -36, to: Date()) ?? Date()
            let filtered = self.filter { $0.date >= cutoff }
            // Ensure we always have enough points to draw a sparkline
            return filtered.count >= 2 ? filtered : Array(self.suffix(min(7, self.count)))
        case .week:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return self.filter { $0.date >= cutoff }
        case .month:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            return self.filter { $0.date >= cutoff }
        case .year:
            let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date()
            return self.filter { $0.date >= cutoff }
        }
    }
}
