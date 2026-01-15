import SwiftUI
import Charts

struct CryptoVolumeView: View {
    // Input data and configuration
    let dataPoints: [ChartDataPoint]
    let xDomain: ClosedRange<Date>
    let halfCandleSpan: TimeInterval
    let volumeYMax: Double

    // Crosshair bindings (child updates parent)
    @Binding var showCrosshair: Bool
    @Binding var crosshairDataPoint: ChartDataPoint?

    // Visual alignment/padding so price and volume plots line up perfectly
    let leadingInset: CGFloat
    let trailingInset: CGFloat

    // Desired height for the volume view (defaults typically ~52)
    let height: CGFloat

    var body: some View {
        Chart {
            // Volume bars sized to candle span (TradingView-style)
            ForEach(Array(dataPoints.enumerated()), id: \.element.id) { idx, pt in
                let prevClose = (idx > 0 ? dataPoints[idx-1].close : dataPoints[idx].close)
                let isUp = pt.close >= prevClose
                let color = (idx == 0)
                    ? Color.gray.opacity(0.25)
                    : (isUp ? Color.green.opacity(0.55) : Color.red.opacity(0.55))

                let startDate = max(pt.date.addingTimeInterval(-halfCandleSpan), xDomain.lowerBound)
                let endDate   = min(pt.date.addingTimeInterval( halfCandleSpan), xDomain.upperBound)

                RectangleMark(
                    xStart: .value("Start", startDate),
                    xEnd:   .value("End",   endDate),
                    yStart: .value("Zero", 0),
                    yEnd:   .value("Volume", pt.volume)
                )
                .foregroundStyle(color)
            }

            // Crosshair projection line
            if showCrosshair, let cp = crosshairDataPoint {
                RuleMark(x: .value("Time", cp.date))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .chartXScale(domain: xDomain)
        .chartXScale(range: 0...1)
        .chartYScale(domain: 0...(volumeYMax * 1.08))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let origin = geo[proxy.plotAreaFrame].origin
                                let x = value.location.x - origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    if let nearest = findClosest(to: date) {
                                        crosshairDataPoint = nearest
                                        showCrosshair = true
                                    }
                                }
                            }
                            .onEnded { _ in
                                showCrosshair = false
                            }
                    )
            }
        }
        .overlay(
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.12), .clear]),
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
        .transaction { txn in txn.animation = nil }
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .frame(height: height)
    }

    // Local closest-point search so this view is self-contained
    private func findClosest(to date: Date) -> ChartDataPoint? {
        let points = dataPoints
        guard !points.isEmpty else { return nil }
        var low = 0
        var high = points.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let midDate = points[mid].date
            if midDate == date {
                return points[mid]
            } else if midDate < date {
                low = mid + 1
            } else {
                if mid == 0 { break }
                high = mid - 1
            }
        }
        let idx = max(0, min(points.count - 1, low))
        if idx == 0 { return points[0] }
        if idx >= points.count { return points.last }
        let prev = points[idx - 1]
        let next = points[idx]
        let dtPrev = date.timeIntervalSince(prev.date)
        let dtNext = next.date.timeIntervalSince(date)
        return dtPrev <= dtNext ? prev : next
    }
}
