import Combine
import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Price Service Architecture
//
// This file provides the PriceService protocol and implementations for live price streaming.
//
// Key components:
// - PriceService: Protocol defining the price publisher interface
// - BinanceWebSocketPriceService: Primary service using Binance WebSocket with CoinGecko fallback
// - CoinGeckoPriceService: Simple CoinGecko polling implementation
//
// Note: The app primarily uses LivePriceManager for market data (polling-based).
// BinanceWebSocketPriceService is used by PriceViewModel for individual coin detail views.

// Map common ticker symbols to CoinGecko IDs
private let tickerToGeckoID: [String: String] = [
    "btc": "bitcoin",
    "eth": "ethereum",
    "bnb": "binancecoin"
    // add other tickers as needed
]

/// Protocol for services that publish live price updates for given symbols.
protocol PriceService {
    func pricePublisher(
        for symbols: [String],
        interval: TimeInterval
    ) -> AnyPublisher<[String: Double], Never>
}

/// Live implementation using Binance WebSocket for real-time price updates.
/// Falls back to CoinGecko polling when WebSocket is unavailable or in background.
final class BinanceWebSocketPriceService: PriceService {
    // Feature gate: disable WebSocket on iOS 26 and Simulator (known Apple crash in URLSessionWebSocketTask)
    // You can force-disable via UserDefaults.standard.bool(forKey: "DisableBinanceWS")
    private var wsSupported: Bool {
        if UserDefaults.standard.bool(forKey: "DisableBinanceWS") { return false }
        #if targetEnvironment(simulator)
        return false
        #else
        if #available(iOS 26.0, *) { return false } // runtime kill-switch on iOS 26
        return true
        #endif
    }
    
    static let shared = BinanceWebSocketPriceService()
    #if canImport(UIKit)
    private var isInBackground = false
    #endif
    
    // Rate-limited logging to prevent console spam
    // THREAD-SAFETY FIX: Protected with NSLock — rateLimitedLog is called from
    // WebSocket delegate callbacks on background threads AND from main thread,
    // causing potential Dictionary corruption crashes.
    private var lastLogTimes: [String: Date] = [:]
    private let lastLogTimesLock = NSLock()
    private func rateLimitedLog(_ key: String, _ message: String, minInterval: TimeInterval = 30.0) {
        let now = Date()
        lastLogTimesLock.lock()
        if let lastTime = lastLogTimes[key], now.timeIntervalSince(lastTime) < minInterval {
            lastLogTimesLock.unlock()
            return
        }
        lastLogTimes[key] = now
        lastLogTimesLock.unlock()
        #if DEBUG
        print(message)
        #endif
    }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = true
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    private var task: URLSessionWebSocketTask?
    private var lastPrices: [String: Double] = [:]
    private var currentSymbols: [String] = []
    private var currentInterval: TimeInterval = 5
    private let subject = PassthroughSubject<[String: Double], Never>()

    private var reconnectWorkItem: DispatchWorkItem?
    private var connecting = false

    // PERFORMANCE FIX: Removed duplicate NWPathMonitor - use shared NetworkReachability instead
    // This avoids running two separate network monitors and ensures consistent state
    private var isReachable: Bool { NetworkReachability.shared.isReachable }
    private var reconnectDelay: TimeInterval = 2.0
    private var wsCooldownUntil: Date?
    
    // PERFORMANCE FIX: Throttle WebSocket price updates to reduce UI update frequency
    // Allows at most one update per 100ms instead of sending on every WS message
    private var lastWSPriceEmitAt: CFTimeInterval = 0
    private let wsEmitMinInterval: CFTimeInterval = 0.10  // 100ms minimum between emissions
    private var pendingWSPriceEmit: Bool = false

    private var failureCount = 0
    /// FIX v5.0.3: Track total reconnect attempts across the session. After maxReconnectAttempts,
    /// permanently fall back to REST polling to avoid indefinite WS retry storms.
    private var totalReconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private var wsPermDisabled = false
    private var fallbackCancellable: AnyCancellable?
    // PERFORMANCE FIX: Use shared singleton instead of creating new instance
    private var geckoFallback: CoinGeckoPriceService { CoinGeckoPriceService.shared }

    private var keepAliveTimer: Timer?
    private var lastMessageAt: Date = Date.distantPast

    // Serial queue to protect policy state (preferred/blocked hosts, failures, current host)
    private let policyQueue = DispatchQueue(label: "BinanceWS.PolicyQueue")

    // WS endpoint preference & health tracking
    private var _wsPreferredHostUntil: (host: String, until: Date)?
    private var _wsBlockedHosts: [String: Date] = [:]

    // Inserted dictionary to track per-host failures:
    private var _wsHostFailures: [String: Int] = [:]

    // Track current WS host for failure tracking
    private var _currentWSHost: String?

    // New private flag to detect first received message
    private var hasReceivedMessage = false

    private var lastReceiveErrorLogAt: Date = .distantPast

    private func _orderWSByPreference(urls: [URL]) -> [URL] {
        let now = Date()
        // Snapshot policy under serialization
        let snapshot: (preferred: String?, blocked: [String: Date]) = policyQueue.sync {
            let pref: String? = {
                if let p = _wsPreferredHostUntil, p.until > now { return p.host }
                return nil
            }()
            return (pref, _wsBlockedHosts)
        }
        func isBlocked(_ host: String?) -> Bool {
            guard let h = host, let until = snapshot.blocked[h] else { return false }
            return until > now
        }
        return urls.sorted { lhs, rhs in
            let lh = lhs.host
            let rh = rhs.host
            // Blocked goes last
            if isBlocked(lh) && !isBlocked(rh) { return false }
            if isBlocked(rh) && !isBlocked(lh) { return true }
            // Preferred goes first
            if let p = snapshot.preferred, lh == p, rh != p { return true }
            if let p = snapshot.preferred, rh == p, lh != p { return false }
            // Stable fallback ordering
            return (lh ?? lhs.absoluteString) < (rh ?? rhs.absoluteString)
        }
    }

    // PERFORMANCE FIX: Subscription to shared NetworkReachability instead of duplicate monitor
    private var reachabilityCancellable: AnyCancellable?
    
    init() {
        // Subscribe to shared NetworkReachability for network state changes
        // This avoids duplicate NWPathMonitor instances
        reachabilityCancellable = NetworkReachability.shared.$isReachable
            .dropFirst() // Skip initial value to only react to changes
            .sink { [weak self] isReachable in
                if isReachable {
                    // Network restored, try reconnecting with reset backoff
                    self?.reconnectDelay = 2.0
                    self?.connectIfNeeded(force: true)
                }
            }
        setupLifecycleObservers()
    }

    #if canImport(UIKit)
    // MEMORY LEAK FIX: Store observer tokens for proper cleanup in deinit
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    
    private func setupLifecycleObservers() {
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.isInBackground = true
            // Stop WS and switch to fallback while backgrounded
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            self.stopKeepAlive()
            self.startFallbackPolling()
        }
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.isInBackground = false
            // Resume WS when foregrounded
            self.stopFallbackPolling()
            self.connectIfNeeded(force: true)
        }
    }
    #else
    private func setupLifecycleObservers() { /* no-op on non-UIKit platforms */ }
    #endif

    deinit {
        // PERFORMANCE FIX: Cancel reachability subscription (no longer using local monitor)
        reachabilityCancellable?.cancel()
        #if canImport(UIKit)
        // MEMORY LEAK FIX: Remove NotificationCenter observers to prevent retain cycles
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
        // Clean up WebSocket and timers
        task?.cancel(with: .goingAway, reason: nil)
        keepAliveTimer?.invalidate()
        reconnectWorkItem?.cancel()
        fallbackCancellable?.cancel()
    }

    func pricePublisher(
        for symbols: [String],
        interval: TimeInterval
    ) -> AnyPublisher<[String: Double], Never> {
        // Global kill-switch for WS: fall back to polling when not supported
        // FIX v5.0.3: Also respect permanent disable after max reconnect attempts
        if !wsSupported || wsPermDisabled {
            startFallbackPolling()
            return Publishers.Merge(
                Just(lastPrices).eraseToAnyPublisher(),
                subject.eraseToAnyPublisher()
            )
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
        }

        // Normalize inputs
        let uniq = Array(Set(symbols.map { $0.uppercased() })).sorted()
        currentSymbols = uniq
        currentInterval = max(1, interval)
        startFallbackPolling()

        if !NetworkReachability.shared.isReachable {
            startFallbackPolling()
            return Publishers.Merge(
                Just(lastPrices).eraseToAnyPublisher(),
                subject.eraseToAnyPublisher()
            )
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
        }
        #if canImport(UIKit)
        if isInBackground {
            startFallbackPolling()
            return Publishers.Merge(
                Just(lastPrices).eraseToAnyPublisher(),
                subject.eraseToAnyPublisher()
            )
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
        }
        #endif

        // Start or restart the socket
        connectIfNeeded(force: true)

        // Emit on a timer to avoid spamming UI
        let timer = Timer.publish(every: currentInterval, on: .main, in: .common)
            .autoconnect()
            .map { [weak self] _ -> [String: Double] in self?.lastPrices ?? [:] }
            .eraseToAnyPublisher()

        // Also merge immediate pushes from the subject when prices change
        return Publishers.Merge(timer, subject.eraseToAnyPublisher())
            .prepend(lastPrices)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    private func connectIfNeeded(force: Bool = false) {
        // Respect global WS kill-switch
        // FIX v5.0.3: Also respect permanent disable after max reconnect attempts
        if !wsSupported || wsPermDisabled {
            startFallbackPolling()
            stopKeepAlive()
            return
        }
        if !force, task != nil { return }
        if connecting { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        reconnectWorkItem?.cancel(); reconnectWorkItem = nil
        #if canImport(UIKit)
        if isInBackground {
            startFallbackPolling()
            stopKeepAlive()
            return
        }
        #endif
        guard !currentSymbols.isEmpty else { return }
        guard isReachable && NetworkReachability.shared.isReachable else {
            startFallbackPolling()
            return
        }
        if let until = wsCooldownUntil, until > Date() {
            startFallbackPolling()
            stopKeepAlive()
            return
        }
        connecting = true
        Task { await openSocketWithPolicyFallback() }
    }

    private func geckoID(for symbol: String) -> String {
        let lower = symbol.lowercased()
        let clean = lower.hasSuffix("usdt") ? String(lower.dropLast(4)) : lower
        if let mappedID = tickerToGeckoID[clean] { return mappedID }
        return LivePriceManager.shared.geckoIDMap[clean] ?? clean
    }

    private func startFallbackPolling() {
        let symbols = currentSymbols
        // Do not start fallback when we have no symbols; cancel if previously running to avoid noise
        guard !symbols.isEmpty else {
            if fallbackCancellable != nil {
                #if DEBUG
                rateLimitedLog("fallback.stop", "[BinanceWS] Stopping CoinGecko fallback (no symbols)")
                #endif
                fallbackCancellable?.cancel()
                fallbackCancellable = nil
            }
            #if DEBUG
            // Rate-limit this message to prevent console spam (was appearing 30+ times)
            rateLimitedLog("fallback.nosymbols", "[BinanceWS] Not starting CoinGecko fallback: no symbols")
            #endif
            return
        }
        // Avoid duplicate subscriptions
        // let symbols = currentSymbols  // removed duplicate declaration
        // Build reverse map: id -> SYMBOL
        var idToSymbol: [String: String] = [:]
        for sym in symbols {
            let id = geckoID(for: sym)
            idToSymbol[id] = sym.uppercased()
        }
        #if DEBUG
        print("[BinanceWS] Starting CoinGecko fallback for symbols=\(symbols)")
        #endif
        let fallbackInterval = max(5.0, currentInterval)
        fallbackCancellable = geckoFallback
            .pricePublisher(for: symbols, interval: fallbackInterval)
            .sink { [weak self] idPrices in
                guard let self = self else { return }
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    var mapped: [String: Double] = self.lastPrices
                    for (id, price) in idPrices {
                        if let sym = idToSymbol[id] {
                            // Base symbol (e.g., BTC)
                            mapped[sym] = price
                            // Also publish common pair with USDT for consumers keyed by pair
                            let pair = sym.uppercased().hasSuffix("USDT") ? sym.uppercased() : sym.uppercased() + "USDT"
                            mapped[pair] = price
                        }
                    }
                    self.lastPrices = mapped
                    self.subject.send(mapped)
                }
            }
    }

    private func stopFallbackPolling() {
        if fallbackCancellable != nil {
            #if DEBUG
            print("[BinanceWS] Stopping CoinGecko fallback")
            #endif
        }
        fallbackCancellable?.cancel()
        fallbackCancellable = nil
    }

    private func buildStreams(from symbols: [String]) -> [String] {
        let isUS = ComplianceManager.shared.isUSUser
        return symbols.map { sym in
            let base = sym.uppercased()
            let pair: String
            if base.hasSuffix("USDT") || base.hasSuffix("USD") {
                pair = base
            } else {
                pair = base + (isUS ? "USD" : "USDT")
            }
            return pair.lowercased() + "@trade"
        }
    }

    private func buildStreams(forHost host: String?, symbols: [String]) -> [String] {
        let isUSHost = (host?.contains("binance.us") == true)
        return symbols.map { sym in
            let base = sym.uppercased()
            let pair: String
            if base.hasSuffix("USDT") || base.hasSuffix("USD") {
                // Keep caller-provided suffix, but if host is .us prefer USD variant
                let root = base.replacingOccurrences(of: "USDT", with: "").replacingOccurrences(of: "USD", with: "")
                pair = isUSHost ? (root + "USD") : (root + "USDT")
            } else {
                pair = base + (isUSHost ? "USD" : "USDT")
            }
            return pair.lowercased() + "@trade"
        }
    }

    private func streamsURL(base: URL, streams: [String]) -> URL? {
        guard var comp = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let basePath = comp.path.hasSuffix("/") ? String(comp.path.dropLast()) : comp.path
        if streams.count == 1 {
            comp.path = basePath + "/ws/" + streams[0]
            comp.queryItems = nil
        } else {
            comp.path = basePath + "/stream"
            comp.queryItems = [URLQueryItem(name: "streams", value: streams.joined(separator: "/"))]
        }
        if let scheme = comp.scheme?.lowercased() {
            if scheme == "https" { comp.scheme = "wss" }
            else if scheme == "http" { comp.scheme = "ws" }
        }
        // Ensure WebSocket schemes are used; never pass https:// to webSocketTask
        return comp.url
    }
    
    private func streamsURLs(base: URL, streams: [String]) -> [URL] {
        var urls: [URL] = []
        // Build components from base
        func makeComponents() -> URLComponents? {
            return URLComponents(url: base, resolvingAgainstBaseURL: false)
        }
        // Helper to finalize URL with proper ws/wss scheme
        func finalize(_ comp: URLComponents?) -> URL? {
            guard var comp = comp else { return nil }
            let basePath = comp.path.hasSuffix("/") ? String(comp.path.dropLast()) : comp.path
            comp.path = basePath // ensure stable base path
            if let scheme = comp.scheme?.lowercased() {
                if scheme == "https" { comp.scheme = "wss" }
                else if scheme == "http" { comp.scheme = "ws" }
            }
            return comp.url
        }

        if streams.count <= 1, let single = streams.first {
            // Variant A: /ws/<stream>
            if var comp = makeComponents() {
                let basePath = comp.path.hasSuffix("/") ? String(comp.path.dropLast()) : comp.path
                comp.path = basePath + "/ws/" + single
                comp.queryItems = nil
                if let url = finalize(comp) { urls.append(url) }
            }
            // Variant B: /stream?streams=<stream>
            if var comp = makeComponents() {
                let basePath = comp.path.hasSuffix("/") ? String(comp.path.dropLast()) : comp.path
                comp.path = basePath + "/stream"
                comp.queryItems = [URLQueryItem(name: "streams", value: single)]
                if let url = finalize(comp) { urls.append(url) }
            }
        } else {
            // Multi-stream: only /stream variant is valid
            let joined = streams.joined(separator: "/")
            if var comp = makeComponents() {
                let basePath = comp.path.hasSuffix("/") ? String(comp.path.dropLast()) : comp.path
                comp.path = basePath + "/stream"
                comp.queryItems = [URLQueryItem(name: "streams", value: joined)]
                if let url = finalize(comp) { urls.append(url) }
            }
        }
        return urls
    }

    private func openSocketWithPolicyFallback() async {
        // PERFORMANCE FIX v20: Removed binance.us endpoints — Binance US is shut down.
        // Dead endpoints caused immediate TCP RSTs and rapid circuit-breaker escalation.
        // Also skip entirely when geo-blocked to avoid wasted connection attempts.
        let isGeoBlocked = UserDefaults.standard.bool(forKey: "BinanceGlobalGeoBlocked")
        if isGeoBlocked {
            rateLimitedLog("ws.geoblocked", "[BinanceWS] Skipping WebSocket - Binance geo-blocked")
            connecting = false
            startFallbackPolling()
            return
        }
        // Try both with and without explicit :9443 to avoid handshake proxy issues
        let bases: [URL] = [
            URL(string: "https://stream.binance.com:9443")!,
            URL(string: "https://stream.binance.com")!
        ]
        var candidates: [URL] = []
        for base in bases {
            let perHostStreams = buildStreams(forHost: base.host, symbols: currentSymbols)
            candidates.append(contentsOf: streamsURLs(base: base, streams: perHostStreams))
        }
        let ordered = _orderWSByPreference(urls: candidates)
        await openFirstWorking(from: ordered)
    }

    private func openFirstWorking(from candidates: [URL]) async {
        guard !candidates.isEmpty else { connecting = false; return }
        for (idx, url) in candidates.enumerated() {
            if await open(url: url) { connecting = false; return }
            // Mark this host as blocked for a while before trying the next
            if idx == 0 || candidates[idx - 1].host != url.host {
                self._wsMarkBlocked(host: url.host)
            } else {
                self._wsMarkBlocked(host: url.host)
            }
            // small backoff between candidates
            try? await Task.sleep(nanoseconds: 300_000_000)
            if idx == candidates.count - 1 {
                failureCount += 1
                if failureCount >= 3 {
                    // Extend cooldown progressively up to 15 minutes
                    let minutes = min(15, failureCount * 2)
                    wsCooldownUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
                    startFallbackPolling()
                }
                connecting = false
                scheduleReconnect()
            }
        }
    }

    /// Sends a WebSocket ping and resolves once, with a timeout to avoid multiple resumes.
    private func awaitPing(_ ws: URLSessionWebSocketTask, timeout: TimeInterval = 2.0) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            var resumed = false
            ws.sendPing { error in
                if !resumed {
                    resumed = true
                    cont.resume(returning: error == nil)
                }
            }
            // Failsafe timeout in case the completion never fires
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if !resumed {
                    resumed = true
                    cont.resume(returning: false)
                }
            }
        }
    }

    private func open(url: URL) async -> Bool {
        if !wsSupported { return false }
        #if DEBUG
        print("[BinanceWS] Opening WebSocket: \(url.absoluteString)")
        print("[BinanceWS] WebSocket scheme=\(url.scheme ?? "nil") host=\(url.host ?? "nil")")
        #endif
        var req = URLRequest(url: url)
        // Set Origin to match the target host to improve handshake success
        let originHost = (url.host?.contains("binance.us") == true) ? "https://www.binance.us" : "https://www.binance.com"
        req.setValue(originHost, forHTTPHeaderField: "Origin")
        req.setValue("CryptoSage/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        policyQueue.sync { _currentWSHost = url.host }

        let ws = session.webSocketTask(with: req)
        ws.resume()
        self.task = ws
        receiveLoop()
        lastMessageAt = Date()
        let success = await awaitPing(ws)
        if !success {
            ws.cancel(with: .goingAway, reason: nil)
            self.task = nil
            return false
        }
        // Successful handshake, reset backoff and counters
        reconnectDelay = 2.0
        failureCount = 0
        totalReconnectAttempts = 0  // FIX v5.0.3: Reset on success so transient failures don't accumulate
        wsCooldownUntil = nil
        _wsMarkPreferred(host: _currentWSHost)
        policyQueue.sync {
            if let h = _currentWSHost { _wsHostFailures[h] = 0 }
        }
        // Do NOT call stopFallbackPolling() here
        hasReceivedMessage = false
        startKeepAlive()
        return true
    }

    // Updated scheduleReconnect with larger jitter and extra guards preventing redundant reconnects.
    private func scheduleReconnect() {
        if !wsSupported || wsPermDisabled {
            startFallbackPolling()
            return
        }
        // FIX v5.0.3: After maxReconnectAttempts, permanently fall back to REST polling.
        // This prevents indefinite WS retry storms that waste CPU, network, and memory.
        totalReconnectAttempts += 1
        if totalReconnectAttempts >= maxReconnectAttempts {
            wsPermDisabled = true
            #if DEBUG
            print("[PriceService] 🛑 WS permanently disabled after \(totalReconnectAttempts) reconnect attempts — using REST polling only")
            #endif
            startFallbackPolling()
            return
        }
        #if canImport(UIKit)
        if isInBackground {
            startFallbackPolling()
            return
        }
        #endif
        // If network is down or we're cooling down, don't schedule immediate reconnects
        if !NetworkReachability.shared.isReachable {
            startFallbackPolling()
            return
        }
        if let until = wsCooldownUntil, until > Date() {
            startFallbackPolling()
            return
        }
        reconnectWorkItem?.cancel(); reconnectWorkItem = nil
        stopKeepAlive()
        // Use exponential backoff with wider jitter to reduce thrash
        let delay = reconnectDelay + Double.random(in: 0.2...1.8)
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // Avoid reconnecting if already connecting or if a task exists and is in running state
            if self.connecting { return }
            if let t = self.task, t.state == .running { return }
            self.connectIfNeeded(force: true)
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        // Exponential backoff up to 60s
        reconnectDelay = min(reconnectDelay * 2.0, 60.0)
    }

    private func receiveLoop() {
        guard let ws = task else { return }
        // Capture identity of the task we are receiving on to ignore callbacks from stale tasks
        let wsID = ObjectIdentifier(ws)
        if ws.state != .running {
            self.task = nil
            scheduleReconnect()
            return
        }
        ws.receive { [weak self] result in
            guard let self = self else { return }
            // Ignore callbacks if the task changed/cancelled to avoid races that can crash inside CFNetwork
            if let current = self.task { if ObjectIdentifier(current) != wsID { return } }
            else { return }
            switch result {
            case .failure(let error):
                let nsErr = error as NSError
                #if DEBUG
                let now = Date()
                if now.timeIntervalSince(lastReceiveErrorLogAt) > 2.0 {
                    if !(nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled) {
                        if let reason = nsErr.userInfo["_NSURLErrorWebSocketHandshakeFailureReasonKey"] {
                            print("[BinanceWS] handshake failure reason=\(reason)")
                        }
                        print("[BinanceWS] receive error: code=\(nsErr.code) domain=\(nsErr.domain) desc=\(nsErr.localizedDescription)")
                    }
                    lastReceiveErrorLogAt = now
                }
                #endif
                self.task?.cancel(with: .goingAway, reason: nil)
                self.task = nil
                self.stopKeepAlive()
                self.failureCount += 1
                // Apply cooldown and mark current host blocked on handshake failures
                if nsErr.domain == NSURLErrorDomain && nsErr.code == -1011 {
                    self.wsCooldownUntil = Date().addingTimeInterval(10 * 60)
                    self._wsMarkBlocked(host: self._currentWSHost)
                }
                // Treat socket not connected as a transient host problem and block briefly
                if nsErr.domain == NSPOSIXErrorDomain && nsErr.code == 57 {
                    self._wsMarkBlocked(host: self._currentWSHost)
                }
                var shouldBlockHost: String?
                self.policyQueue.sync {
                    if let h = self._currentWSHost {
                        let c = (self._wsHostFailures[h] ?? 0) + 1
                        self._wsHostFailures[h] = c
                        if c >= 2 { shouldBlockHost = h }
                    }
                }
                if let h = shouldBlockHost { self._wsMarkBlocked(host: h) }
                self.connecting = false
                self.scheduleReconnect()
            case .success(let msg):
                switch msg {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self.receiveLoop()
            }
        }
    }

    private struct StreamEnvelope: Decodable { let stream: String?; let data: Trade }
    private struct Trade: Decodable { let p: String }

    private func handleMessage(_ text: String) {
        // Try envelope form first, then raw trade
        if let data = text.data(using: .utf8) {
            if let env = try? JSONDecoder().decode(StreamEnvelope.self, from: data) {
                if let price = Double(env.data.p) {
                    updatePrice(fromStream: env.stream, price: price)
                    lastMessageAt = Date()
                    if !hasReceivedMessage {
                        hasReceivedMessage = true
                        stopFallbackPolling()
                    }
                    return
                }
            }
            if let trade = try? JSONDecoder().decode(Trade.self, from: data) {
                if let _ = Double(trade.p) {
                    // No stream info; cannot map symbol reliably here, so skip
                    lastMessageAt = Date()
                    if !hasReceivedMessage {
                        hasReceivedMessage = true
                        stopFallbackPolling()
                    }
                    return
                }
            }
        }
    }

    private func updatePrice(fromStream stream: String?, price: Double) {
        // stream format: "btcusdt@trade" or "<pair>@trade"
        guard let stream = stream, let at = stream.firstIndex(of: "@") else { return }
        let pair = String(stream[..<at]).uppercased() // e.g., BTCUSDT
        // Map to base symbol for downstream consumers: strip common USD* quotes
        let quotes = ["USDT", "USD", "BUSD", "USDC"]
        var base = pair
        for q in quotes where base.hasSuffix(q) { base = String(base.dropLast(q.count)); break }
        // Publish both base (e.g., BTC) and full pair (e.g., BTCUSDT)
        lastPrices[base] = price
        lastPrices[pair] = price
        
        // PERFORMANCE FIX: Throttle WebSocket price emissions to 10Hz max (100ms intervals)
        // This significantly reduces UI update frequency while still providing responsive prices
        let now = CACurrentMediaTime()
        if now - lastWSPriceEmitAt >= wsEmitMinInterval {
            lastWSPriceEmitAt = now
            pendingWSPriceEmit = false
            subject.send(lastPrices)
        } else {
            // Mark that we have pending data; the timer will emit it
            pendingWSPriceEmit = true
        }
    }

    private func startKeepAlive() {
        keepAliveTimer?.invalidate(); keepAliveTimer = nil
        // Coinbase keeps sockets alive with regular pings; we do similar.
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: max(8, currentInterval), repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // If we haven't seen any messages for 3x interval, consider it stalled
            let staleAfter = max(8.0, self.currentInterval * 3.0)
            if Date().timeIntervalSince(self.lastMessageAt) > staleAfter {
                #if DEBUG
                print("[BinanceWS] KeepAlive detected stall (>\(staleAfter)s). Reconnecting…")
                #endif
                self.task?.cancel(with: .goingAway, reason: nil)
                self.task = nil
                self.scheduleReconnect()
                return
            }
            // Send a ping; if it errors, the receive loop will handle reconnection
            if let ws = self.task {
                ws.sendPing { error in
                    if let error = error {
                        #if DEBUG
                        print("[BinanceWS] KeepAlive ping error: \(error.localizedDescription)")
                        #endif
                    }
                }
            }
        }
    }

    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    // Helper method to mark host as preferred until some time in future
    private func _wsMarkPreferred(host: String?) {
        guard let host = host else { return }
        let until = Date().addingTimeInterval(10 * 60) // 10 minutes preferred
        policyQueue.sync {
            _wsPreferredHostUntil = (host: host, until: until)
        }
        #if DEBUG
        print("[BinanceWS] Marked host \(host) as preferred until \(until)")
        #endif
    }

    // Helper method to mark host as blocked for some time
    private func _wsMarkBlocked(host: String?) {
        guard let host = host else { return }
        let until = Date().addingTimeInterval(10 * 60) // 10 minutes blocked
        policyQueue.sync {
            _wsBlockedHosts[host] = until
            if let pref = _wsPreferredHostUntil, pref.host == host { _wsPreferredHostUntil = nil }
        }
        #if DEBUG
        print("[BinanceWS] Marked host \(host) as blocked until \(until)")
        #endif
    }
}

/// Live implementation using CoinGecko's simple price API to emit up-to-date prices.
/// PERFORMANCE FIX: Now singleton with shared state to prevent multiple polling instances
final class CoinGeckoPriceService: PriceService {
    // PERFORMANCE FIX: Singleton to share cache across all view models
    static let shared = CoinGeckoPriceService()
    
    private var lastGood: [String: Double] = [:]
    
    // PERFORMANCE FIX: Global cache shared across all instances
    private static var globalPriceCache: [String: Double] = [:]
    private static var lastGlobalFetchAt: Date = .distantPast
    private static let globalCacheTTL: TimeInterval = 120.0  // RATE LIMIT FIX: Increased from 30s to 120s - Firestore is primary source
    
    // PERFORMANCE FIX: Track active polling to prevent duplicate timers
    private static var activePollingSymbols: Set<String> = []
    private static let pollingLock = NSLock()
    
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10  // Increased from 6 for better reliability
        cfg.timeoutIntervalForResource = 15
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    func pricePublisher(
        for symbols: [String],
        interval: TimeInterval
    ) -> AnyPublisher<[String: Double], Never> {
        // PERFORMANCE FIX: Enforce minimum poll interval of 30s to prevent request storms
        let pollInterval = max(interval > 0 ? interval : 30.0, 30.0)

        // Build comma-separated CoinGecko IDs from symbols, using ticker mappings first
        let idList = symbols
            .map { symbol in
                let lower = symbol.lowercased()
                let clean = lower.hasSuffix("usdt")
                    ? String(lower.dropLast(4))
                    : lower
                // Check our ticker map before falling back
                if let mappedID = tickerToGeckoID[clean] {
                    return mappedID
                }
                return LivePriceManager.shared.geckoIDMap[clean] ?? clean
            }
            .joined(separator: ",")
        
        // PRICE CONSISTENCY: Check LivePriceManager's Firestore-synced data FIRST.
        // This avoids unnecessary CoinGecko API calls and ensures portfolio prices
        // match the Watchlist, Market, and CoinDetail pages (same Firestore source).
        let lpmPrices = Self.pricesFromLivePriceManager(symbols: symbols)
        if !lpmPrices.isEmpty {
            // Merge LPM prices into global cache so polling can use them
            for (k, v) in lpmPrices { Self.globalPriceCache[k] = v }
            self.lastGood.merge(lpmPrices) { _, new in new }
        }
        
        // PERFORMANCE FIX: Return cached data immediately if fresh enough
        let now = Date()
        if now.timeIntervalSince(Self.lastGlobalFetchAt) < Self.globalCacheTTL && !Self.globalPriceCache.isEmpty {
            // Return cached data via a single emission, then continue with reduced polling
            return Just(Self.globalPriceCache)
                .merge(with: createPollingPublisher(idList: idList, pollInterval: pollInterval))
                .eraseToAnyPublisher()
        }
        
        // If LPM had prices, seed the cache and treat as "fresh" to skip first API call
        if !lpmPrices.isEmpty && Self.globalPriceCache.count >= symbols.count {
            Self.lastGlobalFetchAt = now
            return Just(Self.globalPriceCache)
                .merge(with: createPollingPublisher(idList: idList, pollInterval: pollInterval))
                .eraseToAnyPublisher()
        }
        
        return createPollingPublisher(idList: idList, pollInterval: pollInterval)
    }
    
    /// Pull current prices from LivePriceManager's Firestore-synced coin list.
    /// Returns a [symbol: price] dictionary for any symbols found.
    private static func pricesFromLivePriceManager(symbols: [String]) -> [String: Double] {
        // Access LivePriceManager on main actor since currentCoinsList is @MainActor
        let coins: [MarketCoin] = {
            if Thread.isMainThread {
                return MainActor.assumeIsolated { LivePriceManager.shared.currentCoinsList }
            }
            // Use a semaphore-free approach: dispatch async + wait with timeout
            var result: [MarketCoin] = []
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.main.async {
                result = MainActor.assumeIsolated { LivePriceManager.shared.currentCoinsList }
                group.leave()
            }
            // Wait with timeout to prevent deadlock; return empty on timeout
            if group.wait(timeout: .now() + 0.5) == .timedOut {
                #if DEBUG
                print("[PriceService] Warning: main thread access timed out, returning empty coin list")
                #endif
                return []
            }
            return result
        }()
        var result: [String: Double] = [:]
        for sym in symbols {
            let lower = sym.lowercased()
            let clean = lower.hasSuffix("usdt") ? String(lower.dropLast(4)) : lower
            // Match by symbol (case-insensitive) or by CoinGecko ID
            if let coin = coins.first(where: {
                $0.symbol.lowercased() == clean || $0.id.lowercased() == clean
            }), let price = coin.priceUsd, price > 0 {
                // Store under both the CoinGecko ID and the original symbol for lookup compatibility
                result[coin.id] = price
                result[clean] = price
            }
        }
        return result
    }
    
    private func createPollingPublisher(idList: String, pollInterval: TimeInterval) -> AnyPublisher<[String: Double], Never> {
        let timer = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .delay(for: .seconds(Double.random(in: 0...2.0)), scheduler: RunLoop.main)  // Jitter to stagger requests
            .prepend(Date())

        return timer
            .flatMap { [weak self] _ -> AnyPublisher<[String: Double], Never> in
                guard let self = self else { return Just([:]).eraseToAnyPublisher() }
                
                // PERFORMANCE FIX: Check APIRequestCoordinator before making request
                guard APIRequestCoordinator.shared.canMakeRequest(for: .coinGecko) else {
                    // Return cached data instead of making request
                    return Just(Self.globalPriceCache.isEmpty ? self.lastGood : Self.globalPriceCache)
                        .eraseToAnyPublisher()
                }
                
                // If no IDs, emit cached dictionary
                if idList.isEmpty {
                    return Just(Self.globalPriceCache.isEmpty ? self.lastGood : Self.globalPriceCache)
                        .eraseToAnyPublisher()
                }
                
                // PERFORMANCE FIX: Check if we have fresh cached data
                let now = Date()
                if now.timeIntervalSince(Self.lastGlobalFetchAt) < Self.globalCacheTTL && !Self.globalPriceCache.isEmpty {
                    return Just(Self.globalPriceCache).eraseToAnyPublisher()
                }
                
                // Record request with coordinator
                APIRequestCoordinator.shared.recordRequest(for: .coinGecko)
                
                // Construct URL for non-empty ID list
                var comps = URLComponents()
                comps.scheme = "https"
                comps.host = APIConfig.coingeckoHost
                comps.path = "/api/v3/simple/price"
                comps.queryItems = [
                    URLQueryItem(name: "ids", value: idList),
                    URLQueryItem(name: "vs_currencies", value: "usd")
                ]

                guard let url = comps.url else {
                    APIRequestCoordinator.shared.recordFailure(for: .coinGecko)
                    return Just(Self.globalPriceCache.isEmpty ? self.lastGood : Self.globalPriceCache)
                        .eraseToAnyPublisher()
                }

                var req = APIConfig.coinGeckoRequest(url: url)
                req.httpMethod = "GET"

                return self.session.dataTaskPublisher(for: req)
                    .timeout(.seconds(10), scheduler: DispatchQueue.main)
                    .retry(0)
                    .map(\.data)
                    .decode(type: [String: [String: Double]].self, decoder: JSONDecoder())
                    .map { dict -> [String: Double] in
                        let fresh = dict.compactMapValues { $0["usd"] }
                        // Record success
                        APIRequestCoordinator.shared.recordSuccess(for: .coinGecko)
                        // If the response is empty, keep publishing the last good snapshot
                        if fresh.isEmpty {
                            return self.lastGood
                        }
                        // Merge new values into lastGood so we never drop keys when some IDs are missing
                        var merged = self.lastGood
                        for (k, v) in fresh { merged[k] = v }
                        return merged
                    }
                    .handleEvents(receiveOutput: { out in
                        self.lastGood = out
                        // PERFORMANCE FIX: Update global cache
                        Self.globalPriceCache = out
                        Self.lastGlobalFetchAt = Date()
                    })
                    .catch { _ -> Just<[String: Double]> in
                        // Record failure
                        APIRequestCoordinator.shared.recordFailure(for: .coinGecko)
                        return Just(Self.globalPriceCache.isEmpty ? self.lastGood : Self.globalPriceCache)
                    }
                    .eraseToAnyPublisher()
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

