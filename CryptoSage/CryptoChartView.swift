//
//  ChartDataPoint.swift
//  CSAI1
//
//  Created by DM on 4/23/25.
//


// Live window duration in seconds for the live chart interval
private let liveWindow: TimeInterval = 300
import Foundation
import SwiftUI
import Charts
import Combine

// MARK: – Data Model
struct ChartDataPoint: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let close: Double
    let volume: Double

    init(id: UUID = UUID(), date: Date, close: Double, volume: Double = 0) {
        self.id = id
        self.date = date
        self.close = close
        self.volume = volume
    }
}

// MARK: – Interval Enum
enum ChartInterval: String, CaseIterable {
    case live = "LIVE"
    case oneMin = "1m", fiveMin = "5m", fifteenMin = "15m", thirtyMin = "30m"
    case oneHour = "1H", fourHour = "4H", oneDay = "1D", oneWeek = "1W"
    case oneMonth = "1M", threeMonth = "3M", oneYear = "1Y", threeYear = "3Y", all = "ALL"
    
    var binanceInterval: String {
        switch self {
        case .live:
            return "1m"
        default:
            return self.rawValue.lowercased()
        }
    }
    var binanceLimit: Int {
        switch self {
        case .live:      return Int(liveWindow)
        case .oneMin:     return 60
        case .fiveMin:    return 48
        case .fifteenMin: return 24
        case .thirtyMin:  return 24
        case .oneHour:    return 48
        case .fourHour:   return 120
        case .oneDay:     return 60
        case .oneWeek:    return 52
        case .oneMonth:   return 12
        case .threeMonth: return 90
        case .oneYear:    return 365
        case .threeYear:  return 1095
        case .all:        return 999
        }
    }
    var hideCrosshairTime: Bool {
        switch self {
        case .oneWeek, .oneMonth, .threeMonth, .oneYear, .threeYear, .all:
            return true
        default:
            return false
        }
    }

    /// Duration of one interval in seconds (approximate for larger intervals)
    var secondsPerInterval: TimeInterval {
        switch self {
        case .live, .oneMin:      return 60
        case .fiveMin:           return 300
        case .fifteenMin:        return 900
        case .thirtyMin:         return 1800
        case .oneHour:           return 3600
        case .fourHour:          return 14400
        case .oneDay:            return 86400
        case .oneWeek:           return 604800
        case .oneMonth:          return 2_592_000   // ~30 days
        case .threeMonth:        return 7_776_000   // ~90 days
        case .oneYear:           return 31_536_000  // ~365 days
        case .threeYear:         return 94_608_000  // ~3 years
        case .all:               return 0          // handle separately if needed
        }
    }
}

// MARK: – ViewModel
class CryptoChartViewModel: ObservableObject {
    /// Number of days to always display on the chart for non-live intervals
    private let desiredDays: Int = 7
    @Published var dataPoints   : [ChartDataPoint] = []
    @Published var isLoading    = false
    @Published var errorMessage : String? = nil

    private var lastLiveUpdate: Date = .init(timeIntervalSince1970: 0)

    // Combine throttling for live data
    private var liveSubject = PassthroughSubject<ChartDataPoint, Never>()
    private var cancellables = Set<AnyCancellable>()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 10
        cfg.timeoutIntervalForResource = 10
        return URLSession(configuration: cfg)
    }()

    private var liveSocket: URLSessionWebSocketTask? = nil

    init() {
        liveSubject
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] pt in
                guard let self = self else { return }
                self.dataPoints.append(pt)
                if self.dataPoints.count > Int(liveWindow) {
                    self.dataPoints.removeFirst()
                }
                self.isLoading = false
            }
            .store(in: &cancellables)
    }

    func startLive(symbol: String) {
        let stream = (symbol + "USDT").lowercased() + "@trade"
        // Reset state and show loading before starting live socket
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
            self.dataPoints.removeAll()
        }
        liveSocket = URLSession.shared.webSocketTask(with: URL(string: "wss://stream.binance.com:9443/ws/\(stream)")!)
        liveSocket?.resume()
        receiveLive()
    }

    private func receiveLive() {
        liveSocket?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err):
                DispatchQueue.main.async {
                    self.errorMessage = err.localizedDescription
                    self.isLoading = false
                }
            case .success(.data(let data)):
                handleLiveData(data)
            case .success(.string(let text)):
                if let data = text.data(using: .utf8) {
                    handleLiveData(data)
                }
            @unknown default:
                break
            }
            self.receiveLive()
        }
    }

    // helper to parse and append a live data point
    private func handleLiveData(_ data: Data) {
        if let msg = try? JSONDecoder().decode(TradeMessage.self, from: data),
           let price = Double(msg.p) {
            let pt = ChartDataPoint(date: Date(timeIntervalSince1970: msg.T / 1000), close: price)
            let current = Date()
            guard current.timeIntervalSince(lastLiveUpdate) >= 1 else { return }
            lastLiveUpdate = current
            // send new point through throttling pipeline instead of direct append
            liveSubject.send(pt)
        }
    }

    func stopLive() {
        liveSocket?.cancel(with: .goingAway, reason: nil)
        liveSocket = nil
    }

    private struct TradeMessage: Decodable {
        let p: String
        let T: TimeInterval
    }

    /// Recursively fetches Binance klines to cover the desired time range, handling pagination.
    private func fetchKlinesRecursively(
        pair: String,
        interval: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        accumulated: [[Any]],
        completion: @escaping ([[Any]]) -> Void
    ) {
        // Build URL with startTime and endTime, limit=1000
        let urlStr = "https://api.binance.com/api/v3/klines?symbol=\(pair)&interval=\(interval)&startTime=\(Int(startTime))&endTime=\(Int(endTime))&limit=1000"
        guard let url = URL(string: urlStr) else {
            DispatchQueue.main.async { self.errorMessage = "Invalid URL for pagination" }
            completion(accumulated)
            return
        }
        session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if let err = error {
                DispatchQueue.main.async { self.errorMessage = err.localizedDescription }
                completion(accumulated)
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { self.errorMessage = "No data during pagination" }
                completion(accumulated)
                return
            }
            // Decode JSON to [[Any]]
            guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
                DispatchQueue.main.async { self.errorMessage = "Bad JSON during pagination" }
                completion(accumulated)
                return
            }
            // If no more data or earliest timestamp <= startTime, finish accumulation
            if raw.isEmpty {
                completion(accumulated)
                return
            }
            // Combine accumulated with this batch
            let combined = raw + accumulated
            // Earliest entry timestamp in ms
            if let firstEntry = raw.first, let t0 = firstEntry[0] as? Double {
                let earliestTs = t0
                if earliestTs <= startTime || raw.count < 1000 {
                    // We have covered the desired range or no more pages
                    completion(combined)
                } else {
                    // Need to fetch previous batch: set new endTime to earliestTs - 1 ms
                    let newEnd = earliestTs - 1
                    self.fetchKlinesRecursively(
                        pair: pair,
                        interval: interval,
                        startTime: startTime,
                        endTime: newEnd,
                        accumulated: combined,
                        completion: completion
                    )
                }
            } else {
                completion(combined)
            }
        }.resume()
    }

    func fetchData(symbol: String, interval: ChartInterval) {
        if interval == .live {
            self.stopLive()    // tear down any previous stream
            self.startLive(symbol: symbol)
            return
        }
        // Special handling for 1Y, 3Y, and ALL: use daily for 1Y, weekly for 3Y, monthly for ALL, with startTime
        if interval == .oneYear || interval == .threeYear || interval == .all {
            let pair = symbol.uppercased() + "USDT"
            let nowMs = Date().timeIntervalSince1970 * 1000
            let (requestInterval, requestLimit, startTimeMs): (String, Int, TimeInterval) = {
                switch interval {
                case .oneYear:
                    // 1-day bars for one year (~365 days)
                    return ("1d", 365, nowMs - TimeInterval(365 * 86_400 * 1000))
                case .threeYear:
                    // 1-week bars for three years (~156 weeks)
                    return ("1w", 156, nowMs - TimeInterval(3 * 365 * 86_400 * 1000))
                case .all:
                    // 1-month bars for all time; start at 0 to fetch as far back as possible
                    return ("1M", 1000, 0)
                default:
                    return ("1d", 365, nowMs - TimeInterval(365 * 86_400 * 1000))
                }
            }()
            let urlStr = "https://api.binance.com/api/v3/klines?symbol=\(pair)&interval=\(requestInterval)&startTime=\(Int(startTimeMs))&limit=\(requestLimit)"
            guard let url = URL(string: urlStr) else {
                DispatchQueue.main.async { self.errorMessage = "Invalid URL for \(interval)" }
                return
            }
            DispatchQueue.main.async {
                self.isLoading = true
                self.errorMessage = nil
            }
            session.dataTask(with: url) { [weak self] data, response, error in
                guard let self = self else { return }
                DispatchQueue.main.async { self.isLoading = false }
                if let err = error {
                    return DispatchQueue.main.async { self.errorMessage = err.localizedDescription }
                }
                if let http = response as? HTTPURLResponse, http.statusCode == 451 {
                    self.fetchDataFromUS(symbol: symbol, interval: interval)
                    return
                }
                guard let data = data else {
                    return DispatchQueue.main.async { self.errorMessage = "No data for \(interval)" }
                }
                // Parse daily/weekly/monthly response directly
                self.parse(data: data)
            }.resume()
            return
        }
        let pair = symbol.uppercased() + "USDT"
        // Calculate desired time range: last `desiredDays` days in milliseconds
        let nowMs = Date().timeIntervalSince1970 * 1000
        let startMs = nowMs - TimeInterval(desiredDays * 86_400 * 1000)

        // Compute how many candles needed (avoid division by zero)
        let candlesNeeded: Int
        if interval.secondsPerInterval > 0 {
            candlesNeeded = Int((TimeInterval(desiredDays * 86_400)) / interval.secondsPerInterval)
        } else {
            // For intervals like .all, which have secondsPerInterval = 0
            candlesNeeded = 0
        }
        let secondsPerInterval = interval.secondsPerInterval
        // Only use recursive fetch if not .oneMin or .fiveMin
        if secondsPerInterval > 0 && candlesNeeded > 1000 && interval != .oneMin && interval != .fiveMin {
            // Use recursive fetch to cover full range
            DispatchQueue.main.async {
                self.isLoading = true
                self.errorMessage = nil
            }
            fetchKlinesRecursively(
                pair: pair,
                interval: interval.binanceInterval,
                startTime: startMs,
                endTime: nowMs,
                accumulated: [],
                completion: { rawCombined in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        // Parse and assign combined data
                        var pts: [ChartDataPoint] = []
                        for entry in rawCombined {
                            guard entry.count >= 6,
                                  let t = entry[0] as? Double else { continue }
                            let date = Date(timeIntervalSince1970: t / 1000)
                            let closeRaw = entry[4]
                            let rawVolume = entry[5]
                            let close: Double? = {
                                if let d = closeRaw as? Double { return d }
                                if let s = closeRaw as? String { return Double(s) }
                                return nil
                            }()
                            let volume: Double? = {
                                if let d = rawVolume as? Double { return d }
                                if let s = rawVolume as? String { return Double(s) }
                                return nil
                            }()
                            if let c = close {
                                pts.append(.init(date: date, close: c, volume: volume ?? 0))
                            }
                        }
                        pts.sort { $0.date < $1.date }
                        self.dataPoints = pts
                    }
                }
            )
        } else {
            // Simple single-fetch case
            let limit: Int
            if interval == .oneMin || interval == .fiveMin {
                // Use fixed binanceLimit for high-frequency intervals to avoid too many candles
                limit = interval.binanceLimit
            } else if interval.secondsPerInterval > 0 {
                let totalSeconds = TimeInterval(desiredDays * 86_400)
                let calc = Int(totalSeconds / interval.secondsPerInterval)
                // Ensure at least 1 candle if calc < 1
                if calc < 1 {
                    limit = interval.binanceLimit
                } else {
                    limit = min(calc, 1000)
                }
            } else {
                // For intervals like .all, use default binanceLimit
                limit = interval.binanceLimit
            }
            let urlStr = "https://api.binance.com/api/v3/klines?symbol=\(pair)&interval=\(interval.binanceInterval)&limit=\(limit)"
            guard let url = URL(string: urlStr) else {
                DispatchQueue.main.async { self.errorMessage = "Invalid URL" }
                return
            }

            DispatchQueue.main.async {
                self.isLoading    = true
                self.errorMessage = nil
            }

            session.dataTask(with: url) { [weak self] data, response, error in
                guard let self = self else { return }
                DispatchQueue.main.async { self.isLoading = false }
                if let err = error {
                    return DispatchQueue.main.async { self.errorMessage = err.localizedDescription }
                }
                if let http = response as? HTTPURLResponse, http.statusCode == 451 {
                    self.fetchDataFromUS(symbol: symbol, interval: interval)
                    return
                }
                guard let data = data else {
                    return DispatchQueue.main.async { self.errorMessage = "No data" }
                }
                // Parse single-batch data
                self.parse(data: data)
            }.resume()
        }
    }

    private func parse(data: Data) {
        do {
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [[Any]] else {
                return DispatchQueue.main.async { self.errorMessage = "Bad JSON" }
            }
            var pts: [ChartDataPoint] = []
            for entry in raw {
                guard entry.count >= 5,
                      let t = entry[0] as? Double
                else { continue }
                let closeRaw = entry[4]
                let date = Date(timeIntervalSince1970: t / 1000)
                let close: Double? = {
                    if let d = closeRaw as? Double { return d }
                    if let s = closeRaw as? String { return Double(s) }
                    return nil
                }()
                let rawVolume = entry[5]
                let volume: Double? = {
                    if let d = rawVolume as? Double { return d }
                    if let s = rawVolume as? String { return Double(s) }
                    return nil
                }()
                if let c = close {
                    pts.append(.init(date: date, close: c, volume: volume ?? 0))
                }
            }
            pts.sort { $0.date < $1.date }
            DispatchQueue.main.async { self.dataPoints = pts }
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
        }
    }

    /// If Binance.com returns HTTP 451, try Binance.US
    private func fetchDataFromUS(symbol: String, interval: ChartInterval) {
        let pair = symbol.uppercased() + "USDT"
        let urlStr = "https://api.binance.us/api/v3/klines?symbol=\(pair)&interval=\(interval.binanceInterval)&limit=\(interval.binanceLimit)"
        guard let url = URL(string: urlStr) else {
            DispatchQueue.main.async { self.errorMessage = "Invalid US URL" }
            return
        }
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        session.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async { self.isLoading = false }
            if let err = error {
                return DispatchQueue.main.async { self.errorMessage = err.localizedDescription }
            }
            guard let data = data else {
                return DispatchQueue.main.async { self.errorMessage = "No data from US" }
            }
            self.parse(data: data)
        }.resume()
    }
}

// MARK: – View
struct CryptoChartView: View {
    let symbol  : String
    let interval: ChartInterval
    let height  : CGFloat

    @StateObject private var vm             = CryptoChartViewModel()
    @State private var showCrosshair        = false
    @State private var crosshairDataPoint   : ChartDataPoint? = nil
    @State private var now: Date = Date()
    @State private var shouldAnimate = false
    @State private var pulse = false
    @State private var showLiveDotOverlay = true
    @State private var showVolumeOverlay    = true

    var body: some View {
        ZStack {
            // Loading overlay
            if vm.isLoading && vm.dataPoints.isEmpty && interval == .live {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
            }

            // Error or chart content
            if let err = vm.errorMessage {
                errorView(err)
            } else {
                chartContent
                    .padding(.leading, 16)
                    .padding(.trailing, 24)
                    .padding(.top, 24)
                    .frame(height: height)
            }
        }
        .onAppear {
            vm.errorMessage = nil
            if interval == .live {
                vm.startLive(symbol: symbol)
            } else {
                vm.fetchData(symbol: symbol, interval: interval)
            }
            shouldAnimate = false
        }
        .onChange(of: symbol) { newSymbol in
            vm.errorMessage = nil
            vm.stopLive()
            if interval == .live {
                vm.startLive(symbol: newSymbol)
            } else {
                vm.fetchData(symbol: newSymbol, interval: interval)
            }
        }
        .onChange(of: interval) { newInterval in
            vm.errorMessage = nil
            vm.stopLive()
            if newInterval == .live {
                // Load an initial minute's worth of historical data before streaming
                vm.fetchData(symbol: symbol, interval: .oneMin)
                vm.startLive(symbol: symbol)
            } else {
                vm.fetchData(symbol: symbol, interval: newInterval)
            }
            shouldAnimate = true
        }
        .onDisappear {
            vm.stopLive()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            self.now = date
        }
    }

    // MARK: – Chart Subviews Extraction
    private var priceChartView: some View {
        Chart {
            ForEach(vm.dataPoints) { pt in
                LineMark(x: .value("Time", pt.date),
                         y: .value("Price", pt.close))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.yellow)

                // only draw gradient fill on historical intervals
                if interval != .live {
                    AreaMark(x: .value("Time", pt.date),
                             yStart: .value("Price", yDomain.lowerBound),
                             yEnd: .value("Price", pt.close))
                        .foregroundStyle(
                            LinearGradient(gradient: Gradient(colors: [
                                .yellow.opacity(0.3),
                                .yellow.opacity(0.15),
                                .yellow.opacity(0.05),
                                .clear
                            ]), startPoint: .top, endPoint: .bottom)
                        )
                }
            }
        }
        .transaction { transaction in
            transaction.animation = shouldAnimate ? .easeInOut(duration: 1) : nil
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks() { value in
                AxisGridLine()
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisTick()
                    .foregroundStyle(Color.white.opacity(0.3))
                AxisValueLabel()
                    .foregroundStyle(Color.gray.opacity(0.95))
                    .font(.caption2)
            }
        }
        .chartXScale(domain: xDomain)
        .chartXScale(range: 0.05...0.95)
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .tint(Color.yellow)
        .accentColor(.yellow)
        .chartXAxis {
            // Common X-axis styling: grid lines and ticks
            if xAxisTickDates.isEmpty {
                AxisMarks() { value in
                    AxisGridLine()
                        .foregroundStyle(Color.white.opacity(0.1))
                    AxisTick()
                        .foregroundStyle(Color.white.opacity(0.3))
                    AxisValueLabel() {
                        if let dt = value.as(Date.self) {
                            Text(formatAxisDate(dt))
                                .foregroundStyle(Color.gray.opacity(0.95))
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                }
            } else {
                AxisMarks(values: xAxisTickDates) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.white.opacity(0.1))
                    AxisTick()
                        .foregroundStyle(Color.white.opacity(0.3))
                    AxisValueLabel() {
                        if let dt = value.as(Date.self) {
                            Text(formatAxisDate(dt))
                                .foregroundStyle(Color.gray.opacity(0.95))
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                }
            }
        }
        // Overlay pulsing dot at last price
        .chartOverlay { proxy in
            GeometryReader { geo in
                if showLiveDotOverlay,
                   let last = vm.dataPoints.last,
                   let xPos = proxy.position(forX: last.date),
                   let yPos = proxy.position(forY: last.close) {
                     
                     Circle()
                       .fill(Color.yellow)
                       .frame(width: 8, height: 8)
                       .scaleEffect(pulse ? 1.5 : 1)
                       .position(x: geo[proxy.plotAreaFrame].origin.x + xPos,
                                 y: geo[proxy.plotAreaFrame].origin.y + yPos)
                       .shadow(color: Color.yellow.opacity(0.7), radius: pulse ? 8 : 2)
                       .onAppear {
                           withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                               pulse.toggle()
                           }
                       }
                       .allowsHitTesting(false)
                }
            }
        }
    }

    private var volumeChartView: some View {
        Chart {
            ForEach(Array(vm.dataPoints.enumerated()), id: \.element.id) { idx, pt in
                let color = (idx > 0 && vm.dataPoints[idx].close >= vm.dataPoints[idx-1].close)
                    ? Color.green.opacity(0.3)
                    : Color.red.opacity(0.3)
                BarMark(
                    x: .value("Time", pt.date),
                    y: .value("Volume", pt.volume)
                )
                .foregroundStyle(color)
                .cornerRadius(2)
            }
            RuleMark(y: .value("Max Vol", maxVolume))
                .foregroundStyle(Color.white.opacity(0.1))
                .lineStyle(StrokeStyle(lineWidth: 0.25))
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.white.opacity(0.1))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
            if showCrosshair, let cp = crosshairDataPoint {
                RuleMark(x: .value("Time", cp.date))
                    .foregroundStyle(.white.opacity(0.7))
                PointMark(
                    x: .value("Time", cp.date),
                    y: .value("Volume", cp.volume)
                )
                .symbolSize(40)
                .foregroundStyle(.white)
                .annotation(position: .bottom) {
                    Text("\(Int(cp.volume))")
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartXScale(range: 0.05...0.95)
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.black.opacity(0.1))
                .padding(.horizontal, 1)
        }
        .chartYScale(domain: 0...overallMaxVolume)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .padding(.horizontal, 16)
        .frame(height: 30)
    }

    private var chartContent: some View {
        VStack(spacing: 4) {
            priceChartView

            if interval != .live && showVolumeOverlay {
                volumeChartView
            }
        }
    }

    // MARK: – Helpers

    private var maxVolume: Double {
        vm.dataPoints.map(\.volume).max() ?? 1
    }

    /// Placeholder for a globally consistent max‐volume across timeframes.
    /// Currently returns the same as `maxVolume`. Later, one can adjust to use a stored or pre‐fetched value.
    private var overallMaxVolume: Double {
        maxVolume
    }
    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Text("Error loading chart").foregroundColor(.red)
            Text(msg).font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
            Button("Retry") { vm.fetchData(symbol: symbol, interval: interval) }
                .padding(6).background(Color.yellow).cornerRadius(8).foregroundColor(.black)
        }
        .padding()
    }

    private func crosshairDate(_ d: Date) -> Text {
        if interval.hideCrosshairTime {
            return Text(d, format: .dateTime.month().year())
        }
        switch interval {
        case .oneMin, .fiveMin:
            return Text(d, format: .dateTime.hour().minute())
        case .fifteenMin, .thirtyMin, .oneHour, .fourHour:
            return Text(d, format: .dateTime.hour())
        case .oneDay, .oneWeek:
            return Text(d, format: .dateTime.month().day())
        default:
            return Text(d, format: .dateTime.month().year())
        }
    }

    private var yDomain: ClosedRange<Double> {
        let prices = vm.dataPoints.map(\.close)
        guard let lo = prices.min(), let hi = prices.max() else { return 0...1 }
        let pad = (hi - lo) * 0.05
        return (lo - pad)...(hi + pad)
    }

    private var xDomain: ClosedRange<Date> {
        if interval == .live {
            let now = self.now
            return now.addingTimeInterval(-liveWindow)...now
        }
        guard let first = vm.dataPoints.first?.date,
              let last  = vm.dataPoints.last?.date else {
            let now = Date()
            return now.addingTimeInterval(-86_400)...now
        }
        return first...last
    }

    private var xAxisCount: Int {
        switch interval {
        case .live, .oneMin:
            return 6
        case .fiveMin:
            return 4
        case .fifteenMin, .thirtyMin, .oneHour:
            return 6
        case .fourHour:
            return 5
        case .oneDay:
            return 6
        default:
            return 3
        }
    }

    /// Compute tick count dynamically based on view width
    private var dynamicXAxisCount: Int {
        // account for 16pt padding each side
        let totalWidth = UIScreen.main.bounds.width - 32
        let approxTickSpacing: CGFloat = 80
        let count = Int(totalWidth / approxTickSpacing)
        return max(2, min(8, count))
    }

    /// Explicit tick dates for key intervals (start, mid, end)
    private var xAxisTickValues: [Date] {
        let start = xDomain.lowerBound
        let end   = xDomain.upperBound
        switch interval {
        case .oneHour, .fourHour, .oneDay:
            let mid = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            return [start, mid, end]
        default:
            return []
        }
    }


    private func formatAxisDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current

        switch interval {
        case .live, .oneMin, .fiveMin, .fifteenMin, .thirtyMin:
            // Show “h:mm a” but drop “:00” when minute == 0
            if minute == 0 {
                df.dateFormat = "h a"
            } else {
                df.dateFormat = "h:mm a"
            }
        case .oneHour, .fourHour:
            // Only hour, no minutes
            df.dateFormat = "h a"
        case .oneDay, .oneWeek, .oneMonth, .threeMonth:
            df.dateFormat = "MMM d"
        case .oneYear, .threeYear:
            df.dateFormat = "MMM yyyy"
        case .all:
            df.dateFormat = "yyyy"
        }

        return df.string(from: date)
    }

    private func findClosest(to date: Date) -> ChartDataPoint? {
        vm.dataPoints.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    private func formatPrice(_ v: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        if v < 1 {
            fmt.minimumFractionDigits = 2
            fmt.maximumFractionDigits = 8
        } else {
            fmt.minimumFractionDigits = 2
            fmt.maximumFractionDigits = 2
        }
        return "$" + (fmt.string(from: v as NSNumber) ?? "\(v)")
    }

    private var xAxisTickDates: [Date] {
        let calendar = Calendar.current

        switch interval {
        // LIVE & 1 MIN: show 6 evenly spaced “minutes:seconds” within last 5 min
        case .live, .oneMin:
            let totalSeconds = liveWindow
            let desiredTicks = xAxisCount
            let strideSec = totalSeconds / Double(desiredTicks - 1)
            return stride(from: 0.0, through: totalSeconds, by: strideSec)
                .map { xDomain.lowerBound.addingTimeInterval($0) }

        // 15 MIN: only top-of-hour ticks, subsampled to xAxisCount
        case .fifteenMin:
            var firstHour = calendar.nextDate(
                after: xDomain.lowerBound,
                matching: DateComponents(minute: 0, second: 0),
                matchingPolicy: .nextTime
            )!
            if firstHour < xDomain.lowerBound {
                firstHour = calendar.date(byAdding: .hour, value: 1, to: firstHour)!
            }

            var hours: [Date] = []
            var cursor = firstHour
            while cursor <= xDomain.upperBound {
                hours.append(cursor)
                cursor = calendar.date(byAdding: .hour, value: 1, to: cursor)!
            }

            if hours.count <= xAxisCount {
                return hours
            } else {
                let step = max(1, hours.count / xAxisCount)
                return hours.enumerated().filter { idx, _ in
                    idx % step == 0
                }.map { $0.element }
            }

        // 5 MIN & 30 MIN: Only top-of-hour ticks for both 5m and 30m
        case .fiveMin, .thirtyMin:
            // Only top-of-hour ticks for both 5m and 30m
            var firstHour = calendar.nextDate(
                after: xDomain.lowerBound,
                matching: DateComponents(minute: 0, second: 0),
                matchingPolicy: .nextTime
            )!
            if firstHour < xDomain.lowerBound {
                firstHour = calendar.date(byAdding: .hour, value: 1, to: firstHour)!
            }
            var ticksHourOnly: [Date] = []
            var cHour = firstHour
            while cHour <= xDomain.upperBound {
                ticksHourOnly.append(cHour)
                cHour = calendar.date(byAdding: .hour, value: 1, to: cHour)!
            }
            let maxHour = xAxisCount
            if ticksHourOnly.count <= maxHour {
                return ticksHourOnly
            } else {
                let stepHour = max(1, ticksHourOnly.count / maxHour)
                return ticksHourOnly.enumerated().filter { idx, _ in
                    idx % stepHour == 0
                }.map { $0.element }
            }

        // 1 H & 4 H: Only top-of-hour ticks, subsampled to xAxisCount
        case .oneHour, .fourHour:
            // Only top-of-hour ticks, subsampled to xAxisCount
            var firstHour2 = calendar.nextDate(
                after: xDomain.lowerBound,
                matching: DateComponents(minute: 0, second: 0),
                matchingPolicy: .nextTime
            )!
            if firstHour2 < xDomain.lowerBound {
                firstHour2 = calendar.date(byAdding: .hour, value: 1, to: firstHour2)!
            }
            var ticksHO: [Date] = []
            var cHO = firstHour2
            while cHO <= xDomain.upperBound {
                ticksHO.append(cHO)
                cHO = calendar.date(byAdding: .hour, value: 1, to: cHO)!
            }
            let maxHO = xAxisCount
            if ticksHO.count <= maxHO {
                return ticksHO
            } else {
                let step = max(1, ticksHO.count / maxHO)
                return ticksHO.enumerated().filter { idx, _ in
                    idx % step == 0
                }.map { $0.element }
            }

        // 1D & 1W: exactly three ticks (start, midpoint, end)
        case .oneDay, .oneWeek:
            let start = xDomain.lowerBound
            let end = xDomain.upperBound
            let mid = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            return [start, mid, end]

        // 1M & 3M: first day of each month within range, subsampled if too many
        case .oneMonth, .threeMonth:
            var ticks: [Date] = []
            var comp = calendar.dateComponents([.year, .month], from: xDomain.lowerBound)
            comp.day = 1; comp.hour = 0; comp.minute = 0; comp.second = 0
            var cursor = calendar.date(from: comp)!
            if cursor < xDomain.lowerBound {
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor)!
            }
            while cursor <= xDomain.upperBound {
                ticks.append(cursor)
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor)!
            }
            // If too many months, subsample down to dynamicXAxisCount
            if ticks.count > dynamicXAxisCount {
                let step = max(1, ticks.count / dynamicXAxisCount)
                return ticks.enumerated().filter { idx, _ in idx % step == 0 }.map { $0.element }
            }
            return ticks

        // 1Y & 3Y: January 1 of each year within range, subsampled if too many
        case .oneYear, .threeYear:
            var ticks: [Date] = []
            var comp = calendar.dateComponents([.year], from: xDomain.lowerBound)
            comp.month = 1; comp.day = 1; comp.hour = 0; comp.minute = 0; comp.second = 0
            var cursor = calendar.date(from: comp)!
            if cursor < xDomain.lowerBound {
                cursor = calendar.date(byAdding: .year, value: 1, to: cursor)!
            }
            while cursor <= xDomain.upperBound {
                ticks.append(cursor)
                cursor = calendar.date(byAdding: .year, value: 1, to: cursor)!
            }
            // Subsample if too many years
            if ticks.count > dynamicXAxisCount {
                let step = max(1, ticks.count / dynamicXAxisCount)
                return ticks.enumerated().filter { idx, _ in idx % step == 0 }.map { $0.element }
            }
            return ticks

        // ALL: just show the domain’s start and end
        case .all:
            return [xDomain.lowerBound, xDomain.upperBound]
        }
    }

    // MARK: – X‐Axis & Crosshair Subview
    // private var xAndCrosshairAxis: some View {
    //     Chart {
    //         AxisMarks(values: xAxisTickDates) { value in
    //             AxisGridLine()
    //                 .foregroundStyle(Color.white.opacity(0.1))
    //             AxisTick()
    //                 .foregroundStyle(Color.white.opacity(0.3))
    //             AxisValueLabel {
    //                 if let dt = value.as(Date.self) {
    //                     Text(formatAxisDate(dt))
    //                         .font(.caption2)
    //                         .foregroundStyle(.white)
    //                         .lineLimit(1)
    //                         .minimumScaleFactor(0.5)
    //                 }
    //             }
    //         }
    //     }
    // }
}

// MARK: – View Extension for Conditional Modifier
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
