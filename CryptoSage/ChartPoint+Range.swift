import Foundation

extension Array where Element == ChartPoint {
    
    /// Minimum number of points required for a good sparkline visualization
    private static var minimumPointsForRange: [HomeView.PortfolioRange: Int] {
        [
            .day: 48,    // Hourly for 2 days
            .week: 56,   // Every 3 hours for a week
            .month: 60,  // Every 12 hours for a month
            .year: 73,   // Every 5 days for a year
            .all: 60     // At least 60 points for any range
        ]
    }
    
    func filtered(for range: HomeView.PortfolioRange) -> [ChartPoint] {
        guard !self.isEmpty else { return [] }
        
        let now = Date()
        let cutoff: Date
        let targetPoints: Int
        
        switch range {
        case .all:
            // For "all", return all points but ensure density
            let minPoints = Self.minimumPointsForRange[.all] ?? 60
            if self.count >= minPoints {
                return self
            }
            // Sparse data - interpolate to target density
            return interpolateToMinimumDensity(targetPoints: minPoints)
            
        case .day:
            cutoff = Calendar.current.date(byAdding: .hour, value: -36, to: now) ?? now
            targetPoints = Self.minimumPointsForRange[.day] ?? 48
            
        case .week:
            cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            targetPoints = Self.minimumPointsForRange[.week] ?? 56
            
        case .month:
            cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
            targetPoints = Self.minimumPointsForRange[.month] ?? 60
            
        case .year:
            cutoff = Calendar.current.date(byAdding: .day, value: -365, to: now) ?? now
            targetPoints = Self.minimumPointsForRange[.year] ?? 73
        }
        
        // Filter points within the date range
        var filtered = self.filter { $0.date >= cutoff }
        
        // Fallback: if filtered is too sparse, take the most recent points
        if filtered.count < 2 {
            filtered = Array(self.suffix(Swift.min(targetPoints, self.count)))
        }
        
        // If still below minimum density, interpolate to create more points
        if filtered.count < targetPoints && filtered.count >= 2 {
            return filtered.interpolateToMinimumDensity(targetPoints: targetPoints)
        }
        
        return filtered
    }
    
    /// Interpolates sparse chart points to create a denser array for smooth sparkline rendering
    /// Uses linear interpolation with optional micro-variance for organic appearance
    /// - Parameter targetPoints: Minimum number of points to generate
    /// - Returns: Interpolated array with at least targetPoints elements
    func interpolateToMinimumDensity(targetPoints: Int) -> [ChartPoint] {
        guard self.count >= 2 else {
            // Not enough data to interpolate - return as-is or synthesize
            if let single = self.first {
                // For single-value data, create a flat line (honest representation)
                // Only add imperceptible variance to prevent numerical rendering issues
                let now = Date()
                var points: [ChartPoint] = []
                for i in 0..<targetPoints {
                    let date = now.addingTimeInterval(-Double(targetPoints - 1 - i) * 3600)
                    // Minimal variance (0.0001%) - prevents rendering glitches but invisible to users
                    let microVariance = sin(Double(i) * 0.3) * 0.000001 * single.value
                    points.append(ChartPoint(date: date, value: single.value + microVariance))
                }
                return points
            }
            return self
        }
        
        // Already have enough points
        if self.count >= targetPoints {
            return Array(self)
        }
        
        // Sort by date ascending
        let sorted = self.sorted { $0.date < $1.date }
        guard let firstPoint = sorted.first, let lastPoint = sorted.last else {
            return Array(self)
        }
        
        let totalTimeSpan = lastPoint.date.timeIntervalSince(firstPoint.date)
        guard totalTimeSpan > 0 else {
            // All points at same time - create synthetic spread
            return synthesizeFromSingleTime(sorted, targetPoints: targetPoints)
        }
        
        // Calculate time interval between interpolated points
        let intervalSeconds = totalTimeSpan / Double(targetPoints - 1)
        
        var interpolatedPoints: [ChartPoint] = []
        interpolatedPoints.reserveCapacity(targetPoints)
        
        for i in 0..<targetPoints {
            let targetDate = firstPoint.date.addingTimeInterval(Double(i) * intervalSeconds)
            
            // Find the two original points that bracket this target date
            var beforePoint = sorted.first!
            var afterPoint = sorted.last!
            
            for j in 0..<sorted.count {
                if sorted[j].date <= targetDate {
                    beforePoint = sorted[j]
                }
                if sorted[j].date > targetDate {
                    afterPoint = sorted[j]
                    break
                }
            }
            
            // Linear interpolation between bracket points
            let bracketTimeSpan = afterPoint.date.timeIntervalSince(beforePoint.date)
            let progress: Double
            if bracketTimeSpan > 0 {
                progress = Swift.min(1.0, Swift.max(0.0, targetDate.timeIntervalSince(beforePoint.date) / bracketTimeSpan))
            } else {
                progress = 1.0
            }
            
            let interpolatedValue = beforePoint.value + (afterPoint.value - beforePoint.value) * progress
            
            // Use pure linear interpolation without artificial variance
            // This preserves the actual price data faithfully
            // Minimal variance only to prevent numerical rendering issues
            let microVariance = sin(Double(i) * 0.5) * 0.000001 * interpolatedValue
            let finalValue = Swift.max(interpolatedValue + microVariance, 0.01)
            
            interpolatedPoints.append(ChartPoint(date: targetDate, value: finalValue))
        }
        
        // Ensure first and last points match original data exactly
        if !interpolatedPoints.isEmpty {
            interpolatedPoints[0] = ChartPoint(date: firstPoint.date, value: firstPoint.value)
            interpolatedPoints[interpolatedPoints.count - 1] = ChartPoint(date: lastPoint.date, value: lastPoint.value)
        }
        
        return interpolatedPoints
    }
    
    /// Creates synthetic time-spread points when all original data is at the same timestamp
    private func synthesizeFromSingleTime(_ points: [ChartPoint], targetPoints: Int) -> [ChartPoint] {
        guard let avgValue = points.isEmpty ? nil : points.reduce(0, { $0 + $1.value }) / Double(points.count) else {
            return points
        }
        
        let now = Date()
        var synthetic: [ChartPoint] = []
        synthetic.reserveCapacity(targetPoints)
        
        // Spread over the last 24 hours by default
        let totalSeconds: Double = 24 * 3600
        let interval = totalSeconds / Double(targetPoints - 1)
        
        for i in 0..<targetPoints {
            let date = now.addingTimeInterval(-totalSeconds + Double(i) * interval)
            // Minimal variance for numerical stability only - preserves data integrity
            let microVariance = sin(Double(i) * 0.3) * 0.000001 * avgValue
            synthetic.append(ChartPoint(date: date, value: avgValue + microVariance))
        }
        
        // Ensure last point is the actual value
        if let lastOriginal = points.last, !synthetic.isEmpty {
            synthetic[synthetic.count - 1] = ChartPoint(date: now, value: lastOriginal.value)
        }
        
        return synthetic
    }
}
