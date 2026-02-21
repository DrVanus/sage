import SwiftUI
import Charts

/// Data model for chart points.
/// Conforms to Identifiable so we can use it in a ForEach,
/// and Equatable so that SwiftUI can animate changes in arrays of these points.
struct EnhancedChartPricePoint: Identifiable, Equatable {
    // PERFORMANCE FIX: Use stable ID based on time instead of random UUID
    // UUID() creates a new ID each time, causing unnecessary view recreation
    // Using timeIntervalSince1970 provides a stable, deterministic ID
    var id: Double { time.timeIntervalSince1970 }
    let time: Date
    let price: Double

    static func == (lhs: EnhancedChartPricePoint, rhs: EnhancedChartPricePoint) -> Bool {
        return lhs.time == rhs.time && lhs.price == rhs.price
    }
}

/// An enhanced chart view with gradient fill, interactive tooltip, crosshair functionality,
/// and optional take-profit/stop-loss level visualization.
struct EnhancedCryptoChartView: View {
    // Array of chart data points
    let priceData: [EnhancedChartPricePoint]
    // Color for the main line (e.g., .yellow)
    let lineColor: Color
    
    // Exit Strategy Visualization - optional TP/SL levels
    /// Take-profit price level (optional) - displayed as green dashed line
    var takeProfitPrice: Double? = nil
    /// Stop-loss price level (optional) - displayed as red dashed line
    var stopLossPrice: Double? = nil
    /// Entry price (optional) - displayed as yellow dashed line
    var entryPrice: Double? = nil
    /// Whether to show price labels on TP/SL/Entry lines
    var showExitLabels: Bool = true
    
    // State for a basic tooltip (shows when user drags)
    @State private var selectedPoint: EnhancedChartPricePoint? = nil
    // Crosshair state toggle and location tracking
    @State private var showCrosshair: Bool = true
    @State private var crosshairLocation: CGPoint? = nil
    
    // PERFORMANCE: Cache sorted timestamps for binary search during drag
    // This reduces O(n) lookups to O(log n) during drag gestures
    private var sortedTimestamps: [TimeInterval] {
        priceData.map { $0.time.timeIntervalSince1970 }.sorted()
    }
    
    /// PERFORMANCE: Binary search for closest point to a given date
    /// Reduces O(n) linear scan to O(log n) during drag gestures
    private func findClosestPoint(to date: Date) -> EnhancedChartPricePoint? {
        guard !priceData.isEmpty else { return nil }
        
        let target = date.timeIntervalSince1970
        
        // Binary search for insertion point
        var low = 0
        var high = priceData.count - 1
        
        while low < high {
            let mid = (low + high) / 2
            if priceData[mid].time.timeIntervalSince1970 < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        // Check neighbors to find closest
        let candidates = [
            low > 0 ? priceData[low - 1] : nil,
            low < priceData.count ? priceData[low] : nil
        ].compactMap { $0 }
        
        return candidates.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
    }

    var body: some View {
        // SAFETY: Handle empty data gracefully
        if priceData.isEmpty {
            Text("No Chart Data")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            chartContent
        }
    }
    
    @ViewBuilder
    private var chartContent: some View {
        ZStack {
            Chart {
                // Gradient area under the price line
                ForEach(priceData) { point in
                    AreaMark(
                        x: .value("Time", point.time),
                        y: .value("Price", point.price)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: lineColor.opacity(0.45), location: 0.0),   // Top - vibrant
                                .init(color: lineColor.opacity(0.28), location: 0.25),  // Upper mid
                                .init(color: lineColor.opacity(0.12), location: 0.6),   // Lower mid
                                .init(color: lineColor.opacity(0.03), location: 0.85),  // Near bottom
                                .init(color: .clear, location: 1.0)                     // Bottom - clear
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                }
                
                // The main price line
                ForEach(priceData) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("Price", point.price)
                    )
                    .foregroundStyle(lineColor)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                
                // If a point is selected, show a vertical rule and a tooltip annotation.
                if let selectedPoint = selectedPoint {
                    RuleMark(x: .value("Selected Time", selectedPoint.time))
                        .foregroundStyle(Color.white.opacity(0.4))
                    
                    PointMark(
                        x: .value("Time", selectedPoint.time),
                        y: .value("Price", selectedPoint.price)
                    )
                    .annotation(position: .top) {
                        Text("\(selectedPoint.price, format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2)))")
                            .font(.caption)
                            .padding(6)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(4)
                            .foregroundColor(.white)
                    }
                }
                
                // MARK: - Exit Strategy Lines (TP/SL/Entry)
                
                // Take-Profit line (green dashed)
                if let tp = takeProfitPrice {
                    RuleMark(y: .value("Take Profit", tp))
                        .foregroundStyle(Color.green.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                        .annotation(position: .trailing, alignment: .center) {
                            if showExitLabels {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.caption2)
                                    Text("TP")
                                        .font(.caption2.weight(.semibold))
                                    Text(formatExitPrice(tp))
                                        .font(.caption2.monospacedDigit())
                                }
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(4)
                            }
                        }
                }
                
                // Stop-Loss line (red dashed)
                if let sl = stopLossPrice {
                    RuleMark(y: .value("Stop Loss", sl))
                        .foregroundStyle(Color.red.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                        .annotation(position: .trailing, alignment: .center) {
                            if showExitLabels {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.caption2)
                                    Text("SL")
                                        .font(.caption2.weight(.semibold))
                                    Text(formatExitPrice(sl))
                                        .font(.caption2.monospacedDigit())
                                }
                                .foregroundColor(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.15))
                                .cornerRadius(4)
                            }
                        }
                }
                
                // Entry price line (yellow/gold dashed)
                if let entry = entryPrice {
                    RuleMark(y: .value("Entry", entry))
                        .foregroundStyle(Color.yellow.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .trailing, alignment: .center) {
                            if showExitLabels {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.caption2)
                                    Text("Entry")
                                        .font(.caption2.weight(.medium))
                                    Text(formatExitPrice(entry))
                                        .font(.caption2.monospacedDigit())
                                }
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2)))
                }
            }
            // Chart overlay for detecting user gestures
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let origin = geo[plotFrame].origin
                                    let locationX = drag.location.x - origin.x
                                    crosshairLocation = drag.location
                                    if let date: Date = proxy.value(atX: locationX) {
                                        // PERFORMANCE: Use binary search instead of O(n) linear scan
                                        selectedPoint = findClosestPoint(to: date)
                                    }
                                }
                                .onEnded { _ in
                                    // Optionally clear selection on end:
                                    // selectedPoint = nil
                                }
                        )
                }
            }
            
            // Crosshair lines overlay
            if showCrosshair, let loc = crosshairLocation {
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = geo.size.height
                    if loc.x >= 0 && loc.y >= 0 && loc.x <= width && loc.y <= height {
                        ZStack {
                            // Vertical line
                            Rectangle()
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 1, height: height)
                                .position(x: loc.x, y: height / 2)
                            // Horizontal line
                            Rectangle()
                                .fill(Color.white.opacity(0.5))
                                .frame(width: width, height: 1)
                                .position(x: width / 2, y: loc.y)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            
            // Crosshair toggle in top-right corner
            VStack {
                HStack {
                    Spacer()
                    Toggle("Crosshair", isOn: $showCrosshair)
                        .padding(6)
                        .toggleStyle(SwitchToggleStyle(tint: .white))
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.25))
                        .cornerRadius(8)
                        .padding([.top, .trailing], 8)
                }
                Spacer()
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Format price for exit strategy labels
    /// SAFETY: Handles edge cases like zero, negative, or invalid prices
    private func formatExitPrice(_ price: Double) -> String {
        let sym = CurrencyManager.symbol
        guard price.isFinite && price > 0 else { return "\(sym)0.00" }
        
        if price >= 1000 {
            return String(format: "%@%.2f", sym, price)
        } else if price >= 1 {
            return String(format: "%@%.4f", sym, price)
        } else {
            return String(format: "%@%.6f", sym, price)
        }
    }
}

struct EnhancedCryptoChartView_Previews: PreviewProvider {
    static var previews: some View {
        // Generate sample data
        let now = Date()
        let sampleData = (0..<24).map { i in
            EnhancedChartPricePoint(
                time: Calendar.current.date(byAdding: .hour, value: -i, to: now) ?? now,
                price: Double.random(in: 20000...25000)
            )
        }
        .sorted { $0.time < $1.time }
        
        Group {
            // Basic chart
            EnhancedCryptoChartView(
                priceData: sampleData,
                lineColor: .yellow
            )
            .frame(height: 300)
            .previewDisplayName("Basic Chart")
            
            // Chart with Exit Strategy Lines
            EnhancedCryptoChartView(
                priceData: sampleData,
                lineColor: .yellow,
                takeProfitPrice: 24000,
                stopLossPrice: 21000,
                entryPrice: 22500
            )
            .frame(height: 300)
            .previewDisplayName("With TP/SL/Entry")
        }
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
        .previewLayout(.sizeThatFits)
    }
}
