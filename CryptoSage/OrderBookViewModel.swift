// MARK: - OrderBookViewModel.swift
import Foundation
import SwiftUI

@MainActor
class OrderBookViewModel: ObservableObject {
    @Published var currentSymbol: String = ""
    struct OrderBookEntry: Equatable, Codable {
        let price: String
        let qty: String
    }

    // MARK: - Order Book Caching Helpers
    private func cacheKeys(for symbol: String) -> (bidsKey: String, asksKey: String) {
        let base = "OrderBookCache_\(symbol)"
        return ("\(base)_bids", "\(base)_asks")
    }

    private func loadCache(for symbol: String) {
        let keys = cacheKeys(for: symbol)
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: keys.bidsKey),
           let cached = try? decoder.decode([OrderBookEntry].self, from: data) {
            bids = Array(cached.prefix(100))
        }
        if let data = UserDefaults.standard.data(forKey: keys.asksKey),
           let cached = try? decoder.decode([OrderBookEntry].self, from: data) {
            asks = Array(cached.prefix(100))
        }
    }

    private func saveCache(for symbol: String) {
        let keys = cacheKeys(for: symbol)
        let encoder = JSONEncoder()
        let maxPersistRows = 100
        let trimmedBids = Array(bids.prefix(maxPersistRows))
        let trimmedAsks = Array(asks.prefix(maxPersistRows))
        if let data = try? encoder.encode(trimmedBids) {
            UserDefaults.standard.set(data, forKey: keys.bidsKey)
        }
        if let data = try? encoder.encode(trimmedAsks) {
            UserDefaults.standard.set(data, forKey: keys.asksKey)
        }
    }

    @Published var bids: [OrderBookEntry] = []
    @Published var asks: [OrderBookEntry] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // Throttling / coalescing
    private var lastFetchAt: Date?
    private let minFetchInterval: TimeInterval = 2.0
    private var isFetching: Bool = false
    private var currentPair: String?
    private var urlTask: URLSessionDataTask?

    private var timer: Timer?

    // MARK: - WebSocket (Coinbase level2)
    private var wsSession: URLSession = URLSession(configuration: {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = true
        return cfg
    }())
    private var wsTask: URLSessionWebSocketTask?
    private var wsPingTimer: Timer?
    private var wsReconnectWorkItem: DispatchWorkItem?
    private var lastWSTickAt: Date = .distantPast
    private var wsConnectedAt: Date = .distantPast

    private var restPollTimer: Timer?
    private var restDepthURL: URL?

    private enum DataSource { case coinbase, binance }
    private var currentSourceWS: DataSource = .coinbase
    private var wsWatchdogTimer: Timer?
    private var wsReconnectAttempts: Int = 0
    private var wsBackoff: TimeInterval = 1.0
    private let wsBackoffMax: TimeInterval = 60.0

    // In-memory book (price -> qty)
    private var bookBids: [String: String] = [:]
    private var bookAsks: [String: String] = [:]
    private var publishTimer: DispatchSourceTimer?

    private let maxRowsToPublish: Int = 40

    // Host rotation indices
    private var binanceWSIndex: Int = 0
    private var restIndex: Int = 0

    func startFetchingOrderBook(for symbol: String) {
        self.currentSymbol = symbol
        let pair = symbol.uppercased() + "-USD"

        if currentPair == pair, timer != nil {
            loadCache(for: symbol)
            startWebSocket(for: symbol, source: .binance)
            return
        }

        currentPair = pair
        loadCache(for: symbol)
        fetchOrderBookThrottled(pair: pair)
        startWebSocket(for: symbol, source: .binance)
        startRESTDepthPolling(symbol: symbol)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.fetchOrderBookThrottled(pair: pair)
        }
    }

    private func fetchOrderBookThrottled(pair: String) {
        if isFetching { return }
        if let last = lastFetchAt, Date().timeIntervalSince(last) < minFetchInterval { return }
        lastFetchAt = Date()
        fetchOrderBook(pair: pair)
    }

    func stopFetching() {
        timer?.invalidate()
        timer = nil
        urlTask?.cancel()
        urlTask = nil
        isFetching = false
        stopWebSocket()
        stopRESTDepthPolling()
    }

    private func fetchOrderBook(pair: String) {
        let urlString = "https://api.exchange.coinbase.com/products/\(pair)/book?level=2"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.errorMessage = "Invalid order book URL."
                self.isFetching = false
            }
            return
        }
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
            self.isFetching = true
            self.urlTask?.cancel()
        }

        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let nsErr = error as NSError? {
                if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                    DispatchQueue.main.async { self.isFetching = false }
                    return
                }
                print("Coinbase order book error:", nsErr.localizedDescription)
                self.fallbackFetchOrderBook(pair: pair)
                return
            }
            DispatchQueue.main.async { self.isLoading = false }
            guard let data = data else {
                print("No data from Coinbase order book.")
                self.fallbackFetchOrderBook(pair: pair)
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let bidsArr = json["bids"] as? [[Any]],
                   let asksArr = json["asks"] as? [[Any]] {

                    let parsedBids = bidsArr.map { arr -> OrderBookEntry in
                        let price = arr[0] as? String ?? "0"
                        let qty   = arr[1] as? String ?? "0"
                        return OrderBookEntry(price: price, qty: qty)
                    }
                    let parsedAsks = asksArr.map { arr -> OrderBookEntry in
                        let price = arr[0] as? String ?? "0"
                        let qty   = arr[1] as? String ?? "0"
                        return OrderBookEntry(price: price, qty: qty)
                    }
                    DispatchQueue.main.async {
                        self.bids = parsedBids
                        self.asks = parsedAsks
                        self.saveCache(for: pair.replacingOccurrences(of: "-USD", with: ""))
                        self.isFetching = false
                    }
                } else {
                    print("Coinbase order book parse error, falling back.")
                    self.fallbackFetchOrderBook(pair: pair)
                    return
                }
            } catch {
                print("Coinbase order book JSON parse error:", error.localizedDescription)
                self.fallbackFetchOrderBook(pair: pair)
                return
            }
        }
        self.urlTask = task
        task.resume()
    }

    // MARK: - Fallback Order Book Fetch
    private func fallbackFetchOrderBook(pair: String) {
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
            self.isFetching = true
            self.urlTask?.cancel()
        }

        let base: String = {
            if let dash = pair.firstIndex(of: "-") { return String(pair[..<dash]) } else { return pair }
        }().uppercased()

        let candidates: [String] = [
            "https://api.binance.com/api/v3/depth?symbol=\(base)USDT&limit=50",
            "https://api.binance.com/api/v3/depth?symbol=\(base)USD&limit=50",
            "https://api.binance.us/api/v3/depth?symbol=\(base)USDT&limit=50",
            "https://api.binance.us/api/v3/depth?symbol=\(base)USD&limit=50"
        ]

        func attempt(_ index: Int) {
            if index >= candidates.count {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Error loading order book."
                    self.isFetching = false
                }
                return
            }
            guard let url = URL(string: candidates[index]) else {
                attempt(index + 1)
                return
            }
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                if let nsErr = error as NSError? {
                    if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                        attempt(index + 1)
                        return
                    }
                    print("Binance order book error (attempt \(index)):", nsErr.localizedDescription)
                    attempt(index + 1)
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let bidsArr = json["bids"] as? [[Any]],
                      let asksArr = json["asks"] as? [[Any]],
                      !bidsArr.isEmpty || !asksArr.isEmpty
                else {
                    attempt(index + 1)
                    return
                }

                let parsedBids = bidsArr.map { arr -> OrderBookEntry in
                    let price = arr.indices.contains(0) ? (arr[0] as? String ?? String(describing: arr[0])) : "0"
                    let qty   = arr.indices.contains(1) ? (arr[1] as? String ?? String(describing: arr[1])) : "0"
                    return OrderBookEntry(price: price, qty: qty)
                }
                let parsedAsks = asksArr.map { arr -> OrderBookEntry in
                    let price = arr.indices.contains(0) ? (arr[0] as? String ?? String(describing: arr[0])) : "0"
                    let qty   = arr.indices.contains(1) ? (arr[1] as? String ?? String(describing: arr[1])) : "0"
                    return OrderBookEntry(price: price, qty: qty)
                }

                DispatchQueue.main.async {
                    self.errorMessage = nil
                    self.bids = parsedBids
                    self.asks = parsedAsks
                    self.saveCache(for: base)
                    self.isLoading = false
                    self.isFetching = false
                }
            }
            self.urlTask = task
            task.resume()
        }

        attempt(0)
    }

    // MARK: - Host candidates
    private func binanceWSCandidates(for symbol: String) -> [URL] {
        let stream = symbol.lowercased() + "usdt@depth20@100ms"
        let urls = [
            "wss://stream.binance.com/ws/\(stream)",
            "wss://stream.binance.com:9443/ws/\(stream)",
            "wss://stream.binance.us/ws/\(stream)",
            "wss://stream.binance.us:9443/ws/\(stream)"
        ]
        return urls.compactMap { URL(string: $0) }
    }

    // MARK: - WebSocket lifecycle
    private func startWebSocket(for symbol: String, source: DataSource = .coinbase) {
        stopWebSocket()
        self.currentSourceWS = source
        print("[OrderBook] Starting WebSocket for \(symbol.uppercased()) on \(source)")
        wsReconnectAttempts = 0
        wsBackoff = 1.0
        self.wsConnectedAt = Date()
        self.lastWSTickAt = Date()

        let product = symbol.uppercased() + "-USD"

        switch source {
        case .coinbase:
            guard let url = URL(string: "wss://ws-feed.exchange.coinbase.com") else { return }
            let task = wsSession.webSocketTask(with: url)
            wsTask = task
            task.resume()

            let sub: [String: Any] = [
                "type": "subscribe",
                "channels": [
                    ["name": "level2", "product_ids": [product]]
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: sub, options: []),
               let text = String(data: data, encoding: .utf8) {
                task.send(.string(text)) { err in if let err = err { print("WS send error:", err.localizedDescription) } }
            }

            schedulePing()
            scheduleWatchdog()
            receiveWebSocket(product: product)

        case .binance:
            let candidates = binanceWSCandidates(for: symbol)
            guard !candidates.isEmpty else { return }
            let index = max(0, binanceWSIndex) % candidates.count
            let url = candidates[index]
            print("[OrderBook] Connecting WS to: \(url.absoluteString) [idx=\(index)]")

            let task = wsSession.webSocketTask(with: url)
            wsTask = task
            task.resume()

            schedulePing()
            scheduleWatchdog()
            receiveWebSocket(product: product)
        }
    }

    private func stopWebSocket() {
        wsPingTimer?.invalidate(); wsPingTimer = nil
        wsWatchdogTimer?.invalidate(); wsWatchdogTimer = nil
        wsReconnectWorkItem?.cancel(); wsReconnectWorkItem = nil
        publishTimer?.cancel(); publishTimer = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        lastWSTickAt = .distantPast
    }

    private func schedulePing() {
        DispatchQueue.main.async {
            self.wsPingTimer?.invalidate()
            let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
                self?.wsTask?.sendPing { _ in }
            }
            RunLoop.main.add(t, forMode: .common)
            self.wsPingTimer = t
        }
    }

    private func scheduleWatchdog() {
        DispatchQueue.main.async {
            self.wsWatchdogTimer?.invalidate()
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let sinceConnect = Date().timeIntervalSince(self.wsConnectedAt)
                let gap = Date().timeIntervalSince(self.lastWSTickAt)
                let initialGrace: TimeInterval = 12
                guard sinceConnect > initialGrace else { return }

                if gap > 5 {
                    self.wsReconnectAttempts += 1

                    self.startRESTDepthPolling(symbol: self.currentSymbol)
                    self.wsBackoff = min(max(self.wsBackoff, 1.5) * 1.2, self.wsBackoffMax)

                    if self.wsReconnectAttempts >= 1 {
                        self.startRESTDepthPolling(symbol: self.currentSymbol)
                    }

                    print("[OrderBook] WS inactive (\(Int(gap))s). Attempt #\(self.wsReconnectAttempts) on \(self.currentSourceWS)")

                    if self.currentSourceWS != .binance {
                        print("[OrderBook] Switching to Binance depth WS…")
                        self.binanceWSIndex += 1
                        self.startWebSocket(for: self.currentSymbol, source: .binance)
                    } else {
                        self.binanceWSIndex += 1
                        self.startWebSocket(for: self.currentSymbol, source: .binance)
                    }
                }
            }
            RunLoop.main.add(t, forMode: .common)
            self.wsWatchdogTimer = t
        }
    }

    private func scheduleReconnect(after seconds: Double, symbol: String) {
        wsReconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.startWebSocket(for: symbol, source: self.currentSourceWS)
        }
        wsReconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func receiveWebSocket(product: String) {
        guard let task = wsTask else { return }
        task.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err):
                print("WS receive error:", err.localizedDescription)
                self.wsReconnectAttempts += 1
                self.startRESTDepthPolling(symbol: self.currentSymbol)
                self.wsBackoff = min(self.wsBackoff * 1.8, self.wsBackoffMax)
                let delay = max(1.0, self.wsBackoff)
                if self.wsReconnectAttempts % 3 == 0 {
                    self.currentSourceWS = (self.currentSourceWS == .binance) ? .coinbase : .binance
                }
                if self.currentSourceWS == .binance { self.binanceWSIndex += 1 }
                self.scheduleReconnect(after: delay, symbol: self.currentSymbol)
                return
            case .success(let msg):
                switch msg {
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        switch self.currentSourceWS {
                        case .coinbase: self.handleCoinbaseWSMessage(data: data)
                        case .binance:  self.handleBinanceWSMessage(data: data)
                        }
                    }
                case .data(let data):
                    switch self.currentSourceWS {
                    case .coinbase: self.handleCoinbaseWSMessage(data: data)
                    case .binance:  self.handleBinanceWSMessage(data: data)
                    }
                @unknown default:
                    break
                }
                self.receiveWebSocket(product: product)
            }
        }
    }

    private struct L2Snapshot: Decodable { let type: String; let product_id: String; let bids: [[String]]; let asks: [[String]] }
    private struct L2Update: Decodable { let type: String; let product_id: String; let changes: [[String]] }

    private func handleCoinbaseWSMessage(data: Data) {
        stopRESTDepthPolling()
        if let snap = try? JSONDecoder().decode(L2Snapshot.self, from: data), snap.type == "snapshot" {
            var b: [String: String] = [:]
            var a: [String: String] = [:]
            for arr in snap.bids { if arr.count >= 2 { b[arr[0]] = arr[1] } }
            for arr in snap.asks { if arr.count >= 2 { a[arr[0]] = arr[1] } }
            bookBids = b; bookAsks = a
            wsBackoff = 1.0
            lastWSTickAt = Date()
            wsReconnectAttempts = 0
            schedulePublish()
            return
        }
        if let upd = try? JSONDecoder().decode(L2Update.self, from: data), upd.type == "l2update" {
            for change in upd.changes {
                guard change.count >= 3 else { continue }
                let side = change[0]
                let price = change[1]
                let size  = change[2]
                if side == "buy" {
                    if size == "0" { bookBids.removeValue(forKey: price) } else { bookBids[price] = size }
                } else {
                    if size == "0" { bookAsks.removeValue(forKey: price) } else { bookAsks[price] = size }
                }
            }
            wsBackoff = 1.0
            lastWSTickAt = Date()
            wsReconnectAttempts = 0
            schedulePublish()
            return
        }
    }

    private struct BinanceDepth: Decodable {
        let e: String?
        let b: [[String]]?
        let a: [[String]]?
    }

    private func handleBinanceWSMessage(data: Data) {
        stopRESTDepthPolling()
        if let depth = try? JSONDecoder().decode(BinanceDepth.self, from: data) {
            if let bidsArr = depth.b {
                for arr in bidsArr where arr.count >= 2 {
                    let price = arr[0]
                    let size  = arr[1]
                    if size == "0" || size == "0.00000000" { bookBids.removeValue(forKey: price) }
                    else { bookBids[price] = size }
                }
            }
            if let asksArr = depth.a {
                for arr in asksArr where arr.count >= 2 {
                    let price = arr[0]
                    let size  = arr[1]
                    if size == "0" || size == "0.00000000" { bookAsks.removeValue(forKey: price) }
                    else { bookAsks[price] = size }
                }
            }
            wsBackoff = 1.0
            lastWSTickAt = Date()
            wsReconnectAttempts = 0
            schedulePublish()
        }
    }

    private func startRESTDepthPolling(symbol: String) {
        stopRESTDepthPolling()
        print("[OrderBook] Starting REST depth polling fallback for \(symbol.uppercased()))")

        let base = symbol.uppercased()
        let restCandidates: [URL] = [
            URL(string: "https://api.binance.com/api/v3/depth?symbol=\(base)USDT&limit=50")!,
            URL(string: "https://api.binance.us/api/v3/depth?symbol=\(base)USDT&limit=50")!,
            URL(string: "https://api.binance.com/api/v3/depth?symbol=\(base)USD&limit=50")!,
            URL(string: "https://api.exchange.coinbase.com/products/\(base)-USD/book?level=2")!
        ]

        func discoverWorkingEndpoint(completion: @escaping (URL?) -> Void) {
            var idxTried = 0
            func tryNext(_ index: Int) {
                if index >= restCandidates.count { completion(nil); return }
                let url = restCandidates[(restIndex + index) % restCandidates.count]
                var req = URLRequest(url: url)
                req.timeoutInterval = 8
                URLSession.shared.dataTask(with: req) { data, resp, err in
                    if let err = err {
                        print("[OrderBook][REST] discovery error: \(url.host ?? "?") — \(err.localizedDescription)")
                        idxTried += 1
                        return tryNext(index + 1)
                    }
                    guard let http = resp as? HTTPURLResponse else {
                        print("[OrderBook][REST] discovery no HTTP resp for \(url)")
                        idxTried += 1
                        return tryNext(index + 1)
                    }
                    guard (200...299).contains(http.statusCode), let data = data, data.count > 0 else {
                        print("[OrderBook][REST] discovery bad status=\(http.statusCode) for \(url)")
                        idxTried += 1
                        return tryNext(index + 1)
                    }
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["bids"] != nil || json["asks"] != nil {
                        completion(url); return
                    }
                    print("[OrderBook][REST] discovery parse fail for \(url)")
                    idxTried += 1
                    tryNext(index + 1)
                }.resume()
            }
            tryNext(0)
        }

        DispatchQueue.main.async {
            let t = Timer(timeInterval: 0.9, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let makeRequest: (URL) -> Void = { url in
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 8
                    URLSession.shared.dataTask(with: req) { data, resp, err in
                        if let err = err {
                            print("[OrderBook][REST] poll error: \(err.localizedDescription)")
                            // rotate to next candidate on error
                            self.restIndex = (self.restIndex + 1) % restCandidates.count
                            DispatchQueue.main.async { self.restDepthURL = restCandidates[self.restIndex] }
                            return
                        }
                        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode), let data = data else {
                            print("[OrderBook][REST] poll bad response for \(url.absoluteString)")
                            self.restIndex = (self.restIndex + 1) % restCandidates.count
                            DispatchQueue.main.async { self.restDepthURL = restCandidates[self.restIndex] }
                            return
                        }
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            var b: [String: String] = [:]
                            var a: [String: String] = [:]
                            if let bidsArr = json["bids"] as? [[Any]] {
                                for arr in bidsArr where arr.count >= 2 { b[String(describing: arr[0])] = String(describing: arr[1]) }
                            }
                            if let asksArr = json["asks"] as? [[Any]] {
                                for arr in asksArr where arr.count >= 2 { a[String(describing: arr[0])] = String(describing: arr[1]) }
                            }
                            DispatchQueue.main.async {
                                self.bookBids = b
                                self.bookAsks = a
                                print("[OrderBook] REST depth updated (\(symbol.uppercased())) bids=\(b.count) asks=\(a.count)")
                                self.schedulePublish()
                            }
                        } else {
                            print("[OrderBook][REST] poll JSON parse failed for \(url.host ?? "?")")
                            self.restIndex = (self.restIndex + 1) % restCandidates.count
                            DispatchQueue.main.async { self.restDepthURL = restCandidates[self.restIndex] }
                        }
                    }.resume()
                }

                if let url = self.restDepthURL {
                    makeRequest(url)
                } else {
                    discoverWorkingEndpoint { url in
                        DispatchQueue.main.async {
                            if let url = url { self.restDepthURL = url }
                            else { self.restDepthURL = restCandidates[self.restIndex] }
                            if let url = self.restDepthURL { print("[OrderBook][REST] using \(url.absoluteString)") }
                        }
                    }
                }
            }
            RunLoop.main.add(t, forMode: .common)
            self.restPollTimer = t
        }
    }

    private func stopRESTDepthPolling() {
        DispatchQueue.main.async {
            self.restPollTimer?.invalidate()
            self.restPollTimer = nil
            self.restDepthURL = nil
        }
    }

    private func schedulePublish() {
        if publishTimer == nil {
            let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            t.schedule(deadline: .now() + 0.12, repeating: 0.12)
            t.setEventHandler { [weak self] in self?.publishTopOfBook() }
            publishTimer = t
            t.resume()
        }
    }

    private func publishTopOfBook() {
        let top = maxRowsToPublish

        var bidPairs: [(Double, String)] = []
        bidPairs.reserveCapacity(bookBids.count)
        for (p, q) in bookBids { if let dp = Double(p) { bidPairs.append((dp, q)) } }
        bidPairs.sort { $0.0 > $1.0 }
        let bidSlice = bidPairs.prefix(top)
        let newBids: [OrderBookEntry] = bidSlice.map { pair in
            let priceStr = String(format: "%.2f", pair.0)
            return OrderBookEntry(price: priceStr, qty: pair.1)
        }

        var askPairs: [(Double, String)] = []
        askPairs.reserveCapacity(bookAsks.count)
        for (p, q) in bookAsks { if let dp = Double(p) { askPairs.append((dp, q)) } }
        askPairs.sort { $0.0 < $1.0 }
        let askSlice = askPairs.prefix(top)
        let newAsks: [OrderBookEntry] = askSlice.map { pair in
            let priceStr = String(format: "%.2f", pair.0)
            return OrderBookEntry(price: priceStr, qty: pair.1)
        }

        if !(newBids.isEmpty && newAsks.isEmpty) {
            self.isLoading = false
            self.bids = newBids
            self.asks = newAsks
            self.saveCache(for: self.currentSymbol)
        }
    }
}

// MARK: - OrderBookViewModel (base/quote/data source helpers)
extension OrderBookViewModel {
    var baseCurrency: String { currentSymbol.uppercased() }
    var quoteCurrency: String { return currentSourceWS == .binance ? "USDT" : "USD" }
    var dataSourceLabel: String { return (restPollTimer != nil) ? "REST" : "WS" }
}
