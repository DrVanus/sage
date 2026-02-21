import Foundation

public final class CoinbaseExchangeAdapter: ExchangeAdapter {
    public var id: String { "coinbase" }
    public var name: String { "Coinbase" }

    private let session: URLSession
    private let baseURL: URL
    
    // MARK: - Products Cache (prevents excessive /products API calls)
    private static var cachedProducts: [(base: String, quote: String)] = []
    private static var productsCacheTime: Date?
    private static let productsCacheTTL: TimeInterval = 3600 // 1 hour - products list rarely changes
    private static var productsFetchInFlight: Task<[(base: String, quote: String)], Error>?
    private static let productsLock = NSLock()

    public init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = URL(string: "https://api.exchange.coinbase.com")!
    }

    public func supportedPairs(for baseSymbol: String) async -> [MMEMarketPair] {
        let base = baseSymbol.uppercased()
        let preferred = ["USD", "USDT", "USDC"]
        if let products = try? await fetchProductsCached() {
            let filtered = products.filter { $0.base == base && preferred.contains($0.quote) }
            if !filtered.isEmpty {
                return filtered.map { MMEMarketPair(exchangeID: id, baseSymbol: $0.base, quoteSymbol: $0.quote) }
            }
        }
        // Fallback to static set if fetching products fails or none match
        return preferred.map { MMEMarketPair(exchangeID: id, baseSymbol: base, quoteSymbol: $0) }
    }
    
    /// Cached fetch of products list with request deduplication
    private func fetchProductsCached() async throws -> [(base: String, quote: String)] {
        // Check cache first (thread-safe read)
        let (cached, cacheTime, existing) = Self.productsLock.withLock {
            (Self.cachedProducts, Self.productsCacheTime, Self.productsFetchInFlight)
        }
        
        // Return cached data if still valid
        if !cached.isEmpty, let time = cacheTime, Date().timeIntervalSince(time) < Self.productsCacheTTL {
            return cached
        }
        
        // If a fetch is already in progress, await it instead of starting a new one
        if let existingTask = existing {
            return try await existingTask.value
        }
        
        // Start new fetch with deduplication
        let task = Task<[(base: String, quote: String)], Error> {
            let result = try await fetchProducts()
            Self.productsLock.withLock {
                if !result.isEmpty {
                    Self.cachedProducts = result
                    Self.productsCacheTime = Date()
                }
                Self.productsFetchInFlight = nil
            }
            return result
        }
        
        Self.productsLock.withLock {
            Self.productsFetchInFlight = task
        }
        
        return try await task.value
    }

    public func fetchTickers(for pairs: [MMEMarketPair]) async throws -> [MMETicker] {
        guard !pairs.isEmpty else { return [] }
        return await withTaskGroup(of: MMETicker?.self) { group in
            for p in pairs {
                group.addTask { [weak self, session, baseURL] in
                    guard let self = self else { return nil }
                    do {
                        let sym = p.baseSymbol.uppercased() + "-" + p.quoteSymbol.uppercased()
                        if let t = try await self.fetchTicker(session: session, base: baseURL, product: sym) {
                            return MMETicker(pair: p, last: t.last, bid: nil, ask: nil, volume24hBase: t.volumeBase, ts: t.ts)
                        }
                        return nil
                    } catch {
                        return nil
                    }
                }
            }
            var out: [MMETicker] = []
            for await item in group { if let t = item { out.append(t) } }
            return out
        }
    }

    public func fetchCandles(pair: MMEMarketPair, interval: MMECandleInterval, limit: Int) async throws -> [MMECandle] {
        let gran = mapGranularity(interval)
        let product = pair.baseSymbol.uppercased() + "-" + pair.quoteSymbol.uppercased()
        let url = baseURL.appendingPathComponent("products").appendingPathComponent(product).appendingPathComponent("candles").appending(queryItems: [
            URLQueryItem(name: "granularity", value: String(gran)),
            URLQueryItem(name: "limit", value: String(limit))
        ])
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        req.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        var (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms backoff
            (data, response) = try await session.data(for: req)
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        // Coinbase returns arrays: [ time, low, high, open, close, volume ]
        let sorted = arr.sorted { a, b in
            let ta = (a.first as? Double) ?? 0
            let tb = (b.first as? Double) ?? 0
            return ta < tb
        }
        var out: [MMECandle] = []
        out.reserveCapacity(sorted.count)
        for row in sorted {
            if row.count >= 6 {
                let t = (row[0] as? Double) ?? 0
                let low = (row[1] as? Double) ?? Double.nan
                let high = (row[2] as? Double) ?? Double.nan
                let open = (row[3] as? Double) ?? Double.nan
                let close = (row[4] as? Double) ?? Double.nan
                let vol = (row[5] as? Double)
                if close.isFinite, close > 0, open.isFinite, high.isFinite, low.isFinite {
                    out.append(
                        MMECandle(
                            pair: pair,
                            interval: interval,
                            open: open,
                            high: high,
                            low: low,
                            close: close,
                            volume: vol,
                            ts: t
                        )
                    )
                }
            }
        }
        return out
    }

    // MARK: - Circuit Breaker for Products Endpoint
    private static var productsFailureCount: Int = 0
    private static var productsBlockedUntil: Date?
    private static let productsMaxFailures: Int = 3
    private static let productsBlockDuration: TimeInterval = 300 // 5 minutes
    
    private func fetchProducts() async throws -> [(base: String, quote: String)] {
        // Circuit breaker: skip if blocked due to repeated failures
        let isBlocked = Self.productsLock.withLock {
            if let blockedUntil = Self.productsBlockedUntil, Date() < blockedUntil {
                return true
            }
            return false
        }
        if isBlocked {
            return Self.cachedProducts
        }
        
        let url = baseURL.appendingPathComponent("products")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        req.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            var (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                // Rate limited - record failure and use exponential backoff
                Self.productsLock.withLock {
                    Self.productsFailureCount += 1
                    if Self.productsFailureCount >= Self.productsMaxFailures {
                        Self.productsBlockedUntil = Date().addingTimeInterval(Self.productsBlockDuration)
                        #if DEBUG
                        print("⚠️ [CoinbaseExchangeAdapter] Products endpoint blocked for \(Int(Self.productsBlockDuration))s after \(Self.productsFailureCount) failures")
                        #endif
                    }
                }
                
                try? await Task.sleep(nanoseconds: 500_000_000) // Increased backoff from 200ms to 500ms
                (data, response) = try await session.data(for: req)
            }
            
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                // Non-success response - increment failure count
                Self.productsLock.withLock {
                    Self.productsFailureCount += 1
                    if Self.productsFailureCount >= Self.productsMaxFailures {
                        Self.productsBlockedUntil = Date().addingTimeInterval(Self.productsBlockDuration)
                    }
                }
                return Self.cachedProducts.isEmpty ? [] : Self.cachedProducts
            }
            
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return Self.cachedProducts.isEmpty ? [] : Self.cachedProducts
            }
            
            var out: [(String, String)] = []
            out.reserveCapacity(arr.count)
            for item in arr {
                guard let base = (item["base_currency"] as? String)?.uppercased(),
                      let quote = (item["quote_currency"] as? String)?.uppercased() else { continue }
                if let status = item["status"] as? String, status.lowercased() != "online" { continue }
                out.append((base, quote))
            }
            
            // Success - reset failure count
            Self.productsLock.withLock {
                Self.productsFailureCount = 0
                Self.productsBlockedUntil = nil
            }
            
            return out
        } catch {
            // Network error - increment failure count
            let cached = Self.productsLock.withLock {
                Self.productsFailureCount += 1
                if Self.productsFailureCount >= Self.productsMaxFailures {
                    Self.productsBlockedUntil = Date().addingTimeInterval(Self.productsBlockDuration)
                    #if DEBUG
                    print("⚠️ [CoinbaseExchangeAdapter] Products endpoint blocked due to network errors")
                    #endif
                }
                return Self.cachedProducts
            }
            
            // Return cached data on error if available
            return cached.isEmpty ? [] : cached
        }
    }

    // MARK: - Helpers

    private func mapGranularity(_ i: MMECandleInterval) -> Int {
        switch i {
        case .m1: return 60
        case .m5: return 300
        case .m15: return 900
        case .h1: return 3600
        case .h4: return 14400
        case .d1: return 86400
        }
    }

    // PERFORMANCE FIX: Cached ISO8601 formatters — avoids 2 allocations per candle parse
    private static let _isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let _isoStandard = ISO8601DateFormatter()

    private func parseISOTime(_ s: String) -> TimeInterval? {
        if let d = Self._isoFractional.date(from: s) { return d.timeIntervalSince1970 }
        if let d2 = Self._isoStandard.date(from: s) { return d2.timeIntervalSince1970 }
        return nil
    }

    private func fetchTicker(session: URLSession, base: URL, product: String) async throws -> (last: Double, volumeBase: Double?, ts: TimeInterval)? {
        // Try /ticker first
        let tickerURL = base.appendingPathComponent("products").appendingPathComponent(product).appendingPathComponent("ticker")
        var req = URLRequest(url: tickerURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        req.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            var (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                (data, response) = try await session.data(for: req)
            }
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let priceStr = json["price"] as? String
                let volStr = json["volume"] as? String
                let timeStr = json["time"] as? String
                let last = priceStr.flatMap(Double.init) ?? 0
                let vol = volStr.flatMap(Double.init)
                let ts = timeStr.flatMap { parseISOTime($0) } ?? Date().timeIntervalSince1970
                if last > 0, last.isFinite { return (last, vol, ts) }
            }
        } catch {
            // Fall through to /stats
        }
        // Fallback: /stats
        let statsURL = base.appendingPathComponent("products").appendingPathComponent(product).appendingPathComponent("stats")
        var req2 = URLRequest(url: statsURL)
        req2.httpMethod = "GET"
        req2.timeoutInterval = 10
        req2.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        req2.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            var (data, response) = try await session.data(for: req2)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                (data, response) = try await session.data(for: req2)
            }
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let lastStr = json["last"] as? String
                let volStr = json["volume"] as? String
                let last = lastStr.flatMap(Double.init) ?? 0
                let vol = volStr.flatMap(Double.init)
                let ts = Date().timeIntervalSince1970
                if last > 0, last.isFinite { return (last, vol, ts) }
            }
        } catch {
            return nil
        }
        return nil
    }
}

// Small URL extension for query items
private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        comps.queryItems = (comps.queryItems ?? []) + queryItems
        return comps.url ?? self
    }
}
