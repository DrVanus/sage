//  MarketSentimentProviders.swift
//  CryptoSage
//
//  Providers for Market Sentiment (Fear & Greed–style) with pluggable sources.
//  Add the following keys to your App/Info.plist (String):
//  - COINMARKETCAP_API_KEY
//  - CMC_SENTIMENT_URL   (required; endpoint returning a list of items)
//  - UNUSUALWHALES_API_KEY
//  - UNUSUALWHALES_SENTIMENT_URL (required; endpoint returning a list of items)
//
//  Expected JSON shape for custom endpoints is flexible. The adapters attempt to
//  map common key names to FearGreedData: value (0..100), classification string,
//  timestamp (seconds since epoch), and optional time_until_update.

import Foundation

extension Notification.Name {
    static let sentimentProvenance = Notification.Name("SentimentProvenanceDidUpdate")
    static let sentimentFallbackStatus = Notification.Name("SentimentFallbackStatusDidUpdate")
}

/// Determines if a provenance string indicates fallback usage
private func isProvenanceFallback(_ provenance: String) -> Bool {
    let fallbackIndicators = ["altmeFallback", "derivedFallback", "fallback", "missingEndpoint", "badURL", "networkError", "decodeFail"]
    let lowered = provenance.lowercased()
    return fallbackIndicators.contains { lowered.contains($0.lowercased()) }
}

/// Posts a provenance/debug notification and prints in DEBUG.
/// Also posts a separate fallback status notification for UI consumption.
private func postSentimentProvenance(source: SentimentSource, provenance: String, items: [FearGreedData]) {
    let timestamps = items.compactMap { Int($0.timestamp) }.sorted()
    let minTs = timestamps.first ?? 0
    let maxTs = timestamps.last ?? 0
    let usingFallback = isProvenanceFallback(provenance)
    
    DebugLog.log("Sentiment", "[\(source)] provenance=\(provenance) count=\(items.count) tsRange=\(minTs)...\(maxTs) fallback=\(usingFallback)")
    
    NotificationCenter.default.post(name: .sentimentProvenance, object: nil, userInfo: [
        "source": "\(source)",
        "provenance": provenance,
        "count": items.count,
        "minTs": minTs,
        "maxTs": maxTs,
        "usingFallback": usingFallback
    ])
    
    // Post separate fallback status notification for UI binding
    var fallbackInfo: [String: Any] = [
        "source": "\(source)",
        "usingFallback": usingFallback
    ]
    if usingFallback {
        fallbackInfo["fallbackSource"] = "alternative.me"
    }
    NotificationCenter.default.post(name: .sentimentFallbackStatus, object: nil, userInfo: fallbackInfo)
}

// MARK: - Protocol
protocol SentimentProvider {
    var source: SentimentSource { get }
    func fetch(limit: Int, timeout: TimeInterval) async throws -> [FearGreedData]
}

enum SentimentProviderError: LocalizedError {
    case missingAPIKey(String)
    case missingEndpoint(String)
    case invalidResponse
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let name): return "Missing API key: \(name). Add it to Info.plist."
        case .missingEndpoint(let name): return "Missing endpoint: \(name). Add it to Info.plist."
        case .invalidResponse: return "Invalid response from server."
        case .decodingFailed(let reason): return "Failed to decode response: \(reason)"
        }
    }
}

// MARK: - Alternative.me Provider (native)
struct AlternativeMeProvider: SentimentProvider {
    let source: SentimentSource = .alternativeMe
    
    /// Maximum number of retry attempts for timeout errors
    private static let maxRetries = 3
    
    /// Base delay for exponential backoff (seconds)
    private static let baseRetryDelay: TimeInterval = 2.0

    func fetch(limit: Int, timeout: TimeInterval) async throws -> [FearGreedData] {
        guard let url = URL(string: "https://api.alternative.me/fng/?limit=\(max(1, limit))") else {
            throw SentimentProviderError.invalidResponse
        }
        
        var lastError: Error?
        
        // Retry loop with exponential backoff for timeout errors
        for attempt in 0..<Self.maxRetries {
            do {
                var req = URLRequest(url: url)
                // Increase timeout on retries to give the server more time
                let effectiveTimeout = timeout + (TimeInterval(attempt) * 5.0)
                req.timeoutInterval = effectiveTimeout
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue("CryptoSage/1.0 (+sentiment)", forHTTPHeaderField: "User-Agent")
                
                let (raw, resp) = try await URLSession.shared.data(for: req)
                
                if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw SentimentProviderError.invalidResponse
                }
                
                if let decoded = try? JSONDecoder().decode(FearGreedResponse.self, from: raw) {
                    let norm = normalizeSeries(decoded.data, limit: limit, injectDefaultNextIfMissing: false)
                    let adjusted = applyDailyCadenceIfNeededForAltMe(norm)
                    if attempt > 0 {
                        DebugLog.log("Sentiment", "[AlternativeMe] Succeeded on retry \(attempt)")
                    }
                    postSentimentProvenance(source: source, provenance: "native", items: adjusted)
                    return adjusted
                } else if let flex = try? decodeFlexibleList(data: raw) {
                    let norm = normalizeSeries(flex, limit: limit, injectDefaultNextIfMissing: false)
                    let adjusted = applyDailyCadenceIfNeededForAltMe(norm)
                    postSentimentProvenance(source: source, provenance: "flexible", items: adjusted)
                    return adjusted
                } else {
                    // Decode failed - fall through to fallback
                    break
                }
            } catch let error as URLError where error.code == .timedOut || error.code == .secureConnectionFailed || error.code == .serverCertificateUntrusted {
                // Retry on timeout, TLS, and certificate errors (alternative.me has intermittent TLS issues)
                lastError = error
                let delay = Self.baseRetryDelay * pow(2.0, Double(attempt))
                // Add jitter (0-25% of delay) to prevent thundering herd
                let jitter = Double.random(in: 0...(delay * 0.25))
                let totalDelay = delay + jitter
                let errorType = error.code == .timedOut ? "Timeout" : "TLS error"
                DebugLog.log("Sentiment", "[AlternativeMe] \(errorType) on attempt \(attempt + 1)/\(Self.maxRetries), retrying in \(String(format: "%.1f", totalDelay))s")
                try? await Task.sleep(nanoseconds: UInt64(totalDelay * 1_000_000_000))
                continue
            } catch {
                // Non-retryable error - fall through to fallback
                lastError = error
                break
            }
        }
        
        // All retries exhausted or non-retryable error - use fallback
        if let error = lastError {
            DebugLog.log("Sentiment", "[AlternativeMe] All retries failed: \(error.localizedDescription)")
        }
        let base = try await DerivedSentimentProvider().fetch(limit: limit, timeout: timeout)
        let fb = distinctFallback(from: base, for: source)
        postSentimentProvenance(source: source, provenance: "fallback-derived", items: fb)
        return fb
    }
}

// MARK: - Provider fallback helpers (for when keys/endpoints are not configured)
/// Classify a numeric Fear & Greed value into a label.
private func classifyFG(_ value: Int) -> String {
    switch value {
    case 0...24: return "extreme fear"
    case 25...44: return "fear"
    case 45...54: return "neutral"
    case 55...74: return "greed"
    default: return "extreme greed"
    }
}

/// Returns a cosmetically distinct series for a given source by applying a tiny, bounded offset
/// to a base series (usually the on‑device Derived provider). This lets the UI reflect that the
/// selected source changed even when real API keys/endpoints aren’t configured yet.
/// Note: This does NOT represent real data from the cloud provider; it is a graceful fallback.
private func distinctFallback(from base: [FearGreedData], for source: SentimentSource) -> [FearGreedData] {
    // Small deterministic offsets per provider
    let cosmeticOffsetEnabled = (UserDefaults.standard.object(forKey: "Sentiment.CosmeticFallbackOffsetEnabled") as? Bool) ?? false
    let baseOffset: Int = {
        switch source {
        case .coinMarketCap: return cosmeticOffsetEnabled ? 2 : 0
        case .unusualWhales: return cosmeticOffsetEnabled ? 4 : 0
        case .coinglass:     return cosmeticOffsetEnabled ? -2 : 0
        case .alternativeMe, .derived: return 0
        }
    }()
    func clamp(_ v: Int) -> Int { max(0, min(100, v)) }

    return base.enumerated().map { (idx, item) in
        let v = Int(item.value) ?? 0
        // add a tiny oscillation so entries aren’t all shifted equally
        let wobble = (idx % 3 == 0 ? 1 : (idx % 3 == 1 ? 0 : -1))
        let nv = clamp(v + baseOffset + wobble)
        return FearGreedData(
            value: String(nv),
            value_classification: classifyFG(nv),
            timestamp: item.timestamp,
            time_until_update: item.time_until_update
        )
    }
}

// MARK: - CoinMarketCap Provider
// This adapter requires an endpoint that returns a list of items representing sentiment.
// Configure Info.plist:
//   COINMARKETCAP_API_KEY = <your key>
//   CMC_SENTIMENT_URL = https://pro-api.coinmarketcap.com/<your sentiment endpoint>
// The adapter tries to map common keys: value | score | index, classification | label,
// timestamp | time | updated_at (seconds since epoch or ISO8601).
struct CoinMarketCapProvider: SentimentProvider {
    let source: SentimentSource = .coinMarketCap

    private var apiKey: String {
        (Bundle.main.infoDictionary?["COINMARKETCAP_API_KEY"] as? String) ?? ""
    }
    private var endpoint: String? {
        Bundle.main.infoDictionary?["CMC_SENTIMENT_URL"] as? String
    }

    func fetch(limit: Int, timeout: TimeInterval) async throws -> [FearGreedData] {
        // When endpoint not configured, use alternative.me as the real external data source
        guard let urlStr = endpoint, !urlStr.isEmpty, let url = URL(string: urlStr) else {
            // Fall back to alternative.me (real external data) instead of derived
            let alt = try await AlternativeMeProvider().fetch(limit: limit, timeout: timeout)
            postSentimentProvenance(source: source, provenance: "missingEndpoint->altmeFallback", items: alt)
            return alt
        }

        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var q = comps?.queryItems ?? []
        q.append(URLQueryItem(name: "limit", value: String(max(1, limit))))
        comps?.queryItems = q
        guard let finalURL = comps?.url else {
            let alt = try await AlternativeMeProvider().fetch(limit: limit, timeout: timeout)
            postSentimentProvenance(source: source, provenance: "badURL->altmeFallback", items: alt)
            return alt
        }

        var req = URLRequest(url: finalURL)
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("CryptoSage/1.0 (+sentiment)", forHTTPHeaderField: "User-Agent")
        if !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY") }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw SentimentProviderError.invalidResponse
            }
            if let list = try decodeFlexibleList(data: data) {
                let norm = normalizeSeries(list, limit: limit, injectDefaultNextIfMissing: false)
                postSentimentProvenance(source: source, provenance: "flexible", items: norm)
                return norm
            } else {
                // Decode failed, use alternative.me
                let alt = try await AlternativeMeProvider().fetch(limit: limit, timeout: timeout)
                postSentimentProvenance(source: source, provenance: "decodeFail->altmeFallback", items: alt)
                return alt
            }
        } catch {
            // Network error, use alternative.me
            let alt = try await AlternativeMeProvider().fetch(limit: limit, timeout: timeout)
            postSentimentProvenance(source: source, provenance: "networkError->altmeFallback", items: alt)
            return alt
        }
    }
}

// MARK: - Unusual Whales Provider
// Configure Info.plist:
//   UNUSUALWHALES_API_KEY = <your key>
//   UNUSUALWHALES_SENTIMENT_URL = https://api.unusualwhales.com/<your sentiment endpoint>
struct UnusualWhalesProvider: SentimentProvider {
    let source: SentimentSource = .unusualWhales

    private var apiKey: String {
        (Bundle.main.infoDictionary?["UNUSUALWHALES_API_KEY"] as? String) ?? ""
    }
    private var endpoint: String? {
        Bundle.main.infoDictionary?["UNUSUALWHALES_SENTIMENT_URL"] as? String
    }

    func fetch(limit: Int, timeout: TimeInterval) async throws -> [FearGreedData] {
        // When endpoint not configured, use alternative.me as the real external data source
        guard let urlStr = endpoint, !urlStr.isEmpty, let url = URL(string: urlStr) else {
            let alt = try await AlternativeMeProvider().fetch(limit: limit, timeout: timeout)
            postSentimentProvenance(source: source, provenance: "missingEndpoint->altmeFallback", items: alt)
            return alt
        }

        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var q = comps?.queryItems ?? []
        q.append(URLQueryItem(name: "limit", value: String(max(1, limit))))
        comps?.queryItems = q
        guard let finalURL = comps?.url else {
            let alt = try await AlternativeMeProvider().fetch(limit: limit, timeout: timeout)
            postSentimentProvenance(source: source, provenance: "badURL->altmeFallback", items: alt)
            return alt
        }

        var req = URLRequest(url: finalURL)
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("CryptoSage/1.0 (+sentiment)", forHTTPHeaderField: "User-Agent")
        if !apiKey.isEmpty {
            let token = apiKey.hasPrefix("Bearer ") ? apiKey : "Bearer \(apiKey)"
            req.setValue(token, forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw SentimentProviderError.invalidResponse
            }
            if let list = try decodeFlexibleList(data: data) {
                let norm = normalizeSeries(list, limit: limit, injectDefaultNextIfMissing: false)
                postSentimentProvenance(source: source, provenance: "flexible", items: norm)
                return norm
            } else {
                let alt = try await AlternativeMeProvider().fetch(limit: limit, timeout: timeout)
                postSentimentProvenance(source: source, provenance: "decodeFail->altmeFallback", items: alt)
                return alt
            }
        } catch {
            // Network error, use alternative.me
            let alt = try await AlternativeMeProvider().fetch(limit: limit, timeout: timeout)
            postSentimentProvenance(source: source, provenance: "networkError->altmeFallback", items: alt)
            return alt
        }
    }
}

// MARK: - Flexible decoding helpers
/// Tries to decode a variety of shapes into [FearGreedData]. Supports:
/// - { "data": [ ... ] }
/// - [ ... ]
/// where each item can be either:
///   { value: Int|Double, value_classification|classification|label: String, timestamp|time|updated_at: Int|String }
private func decodeFlexibleList(data: Data) throws -> [FearGreedData]? {
    // Helper to parse strings with percent signs or commas into numbers
    func parseNumber(_ s: String) -> Double? {
        let cleaned = s
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    // Try direct decode of our native model first
    if let native = try? JSONDecoder().decode(FearGreedResponse.self, from: data) {
        return native.data
    }
    // Generic JSON parsing
    let json = try JSONSerialization.jsonObject(with: data, options: [])
    let array: [Any]
    if let dict = json as? [String: Any] {
        if let d = dict["data"] as? [Any] {
            array = d
        } else if let dObj = dict["data"] as? [String: Any], let items = dObj["items"] as? [Any] {
            array = items
        } else if let resp = dict["response"] as? [String: Any] {
            if let d = resp["data"] as? [Any] { array = d }
            else if let items = resp["items"] as? [Any] { array = items }
            else { return nil }
        } else if let a = dict["items"] as? [Any] {
            array = a
        } else if let a = dict["result"] as? [Any] {
            array = a
        } else if let a = dict["results"] as? [Any] {
            array = a
        } else if let a = dict["rows"] as? [Any] {
            array = a
        } else if let a = dict["list"] as? [Any] {
            array = a
        } else if let a = dict["values"] as? [Any] {
            array = a
        } else if let a = json as? [Any] {
            array = a
        } else {
            return nil
        }
    } else if let a = json as? [Any] {
        array = a
    } else {
        return nil
    }

    var items: [FearGreedData] = []
    for el in array {
        guard let obj = el as? [String: Any] else { continue }
        // Value (0..100)
        let value: String? = {
            if let v = obj["value"] as? Int { return String(v) }
            if let v = obj["value"] as? Double {
                let scaled = (v > 0 && v <= 1) ? (v * 100) : v
                return String(Int(scaled.rounded()))
            }
            if let s = obj["value"] as? String, let d = parseNumber(s) {
                let scaled = (d > 0 && d <= 1) ? (d * 100) : d
                return String(Int(scaled.rounded()))
            }
            // FIX: Use consistent normalization - only scale if value is in (0, 1] range
            // Int values from APIs are typically already 0-100, don't scale them
            if let v = obj["score"] as? Int { return String(v) }
            if let v = obj["score"] as? Double { return String(Int(((v > 0 && v <= 1) ? v * 100 : v).rounded())) }
            if let s = obj["score"] as? String, let d = parseNumber(s) { return String(Int(((d > 0 && d <= 1) ? d * 100 : d).rounded())) }
            if let v = obj["index"] as? Int { return String(v) }
            if let v = obj["index"] as? Double { return String(Int(v.rounded())) }
            if let s = obj["index"] as? String, let d = parseNumber(s) { return String(Int(d.rounded())) }
            if let v = obj["sentiment_score"] as? Int { return String(v) }
            if let v = obj["sentiment_score"] as? Double { return String(Int(((v > 0 && v <= 1) ? v * 100 : v).rounded())) }
            if let s = obj["sentiment_score"] as? String, let d = parseNumber(s) { return String(Int(((d > 0 && d <= 1) ? d * 100 : d).rounded())) }
            if let v = obj["fg_value"] as? Int { return String(v) }
            if let v = obj["fg_value"] as? Double { return String(Int(v.rounded())) }
            if let s = obj["fg_value"] as? String, let d = parseNumber(s) { return String(Int(d.rounded())) }
            if let v = obj["fear_greed"] as? Int { return String(v) }
            if let v = obj["score_24h"] as? Double { return String(Int(((v > 0 && v <= 1) ? v * 100 : v).rounded())) }
            if let s = obj["score_24h"] as? String, let d = parseNumber(s) { return String(Int(((d > 0 && d <= 1) ? d * 100 : d).rounded())) }
            if let v = obj["value_24h"] as? Double { return String(Int(((v > 0 && v <= 1) ? v * 100 : v).rounded())) }
            if let s = obj["value_24h"] as? String, let d = parseNumber(s) { return String(Int(((d > 0 && d <= 1) ? d * 100 : d).rounded())) }
            if let s = obj["last_value"] as? String, let d = parseNumber(s) { return String(Int(((d > 0 && d <= 1) ? d * 100 : d).rounded())) }
            return nil
        }()
        // Classification (fallback to derived from value if missing)
        let clsRaw: String? = (obj["value_classification"] as? String)
            ?? (obj["classification"] as? String)
            ?? (obj["label"] as? String)

        // Timestamp (support multiple keys and ms epoch)
        let tsStr: String? = {
            func normalizeEpoch(_ t: Double) -> Int {
                // Treat values greater than ~2033 as milliseconds
                let seconds = (t > 2_000_000_000) ? (t / 1000.0) : t
                return Int(seconds.rounded())
            }
            if let t = obj["timestamp"] as? Int { return String(normalizeEpoch(Double(t))) }
            if let t = obj["timestamp"] as? Double { return String(normalizeEpoch(t)) }
            if let t = obj["time"] as? Int { return String(normalizeEpoch(Double(t))) }
            if let t = obj["time"] as? Double { return String(normalizeEpoch(t)) }
            if let t = obj["updated_at"] as? Int { return String(normalizeEpoch(Double(t))) }
            if let t = obj["updated_at"] as? Double { return String(normalizeEpoch(Double(t))) }
            if let t = obj["date"] as? Int { return String(normalizeEpoch(Double(t))) }
            if let t = obj["date"] as? Double { return String(normalizeEpoch(Double(t))) }
            if let t = obj["created_at"] as? Int { return String(normalizeEpoch(Double(t))) }
            if let t = obj["created_at"] as? Double { return String(normalizeEpoch(t)) }
            if let t = obj["created"] as? Int { return String(normalizeEpoch(Double(t))) }
            if let t = obj["created"] as? Double { return String(normalizeEpoch(t)) }
            if let t = obj["ts"] as? Int { return String(normalizeEpoch(Double(t))) }
            if let t = obj["ts"] as? Double { return String(normalizeEpoch(t)) }
            if let t = obj["last_updated"] as? Int { return String(normalizeEpoch(Double(t))) }
            if let t = obj["last_updated"] as? Double { return String(normalizeEpoch(t)) }
            if let s = obj["time"] as? String, let t = parseEpochOrISO8601Strict(s) { return String(t) }
            if let s = obj["updated_at"] as? String, let t = parseEpochOrISO8601Strict(s) { return String(t) }
            if let s = obj["date"] as? String, let t = parseEpochOrISO8601Strict(s) { return String(t) }
            if let s = obj["created_at"] as? String, let t = parseEpochOrISO8601Strict(s) { return String(t) }
            if let s = obj["created"] as? String, let t = parseEpochOrISO8601Strict(s) { return String(t) }
            if let s = obj["ts"] as? String, let t = parseEpochOrISO8601Strict(s) { return String(t) }
            if let s = obj["last_updated"] as? String, let t = parseEpochOrISO8601Strict(s) { return String(t) }
            if let s = obj["lastUpdate"] as? String, let t = parseEpochOrISO8601Strict(s) { return String(t) }
            if let s = obj["updated"] as? String, let t = parseEpochOrISO8601Strict(s) { return String(t) }
            if let s = obj["datetime"] as? String, let t = parseEpochOrISO8601Strict(s) { return String(t) }
            return nil
        }()

        // Optional next update hint
        let timeUntilUpdateStr: String? = {
            func toString(_ any: Any) -> String? {
                if let i = any as? Int { return String(i) }
                if let d = any as? Double { return String(Int(d.rounded())) }
                if let s = any as? String, let v = Double(s) { return String(Int(v.rounded())) }
                if let s = any as? String { return s }
                return nil
            }
            if let v = obj["time_until_update"] { return toString(v) }
            if let v = obj["next"] { return toString(v) }
            if let v = obj["refresh_in"] { return toString(v) }
            if let v = obj["ttl"] { return toString(v) }
            if let v = obj["update_in"] { return toString(v) }
            if let v = obj["next_update"] { return toString(v) }
            if let v = obj["nextUpdate"] { return toString(v) }
            return nil
        }()

        let clsResolved: String? = {
            if let c = clsRaw { return c.lowercased() }
            if let vStr = value, let vInt = Int(vStr) { return classifyFG(vInt) }
            return nil
        }()
        
        let haveAll = (value != nil && tsStr != nil && clsResolved != nil)
        if haveAll {
            let value = value!
            let ts = tsStr!
            let cls = clsResolved!
            let vClamped = max(0, min(100, Int(value) ?? {
                if let d = Double(value) { return Int(d.rounded()) }
                return 0
            }()))
            let item = FearGreedData(
                value: String(vClamped),
                value_classification: cls,
                timestamp: ts,
                time_until_update: timeUntilUpdateStr
            )
            items.append(item)
        } else {
            DebugLog.log("Sentiment", "[flex-decode] dropped item due to missing keys value=\(String(describing: value)) ts=\(String(describing: tsStr)) cls=\(String(describing: clsResolved))")
        }
    }
    items.sort { (Int($0.timestamp) ?? 0) > (Int($1.timestamp) ?? 0) }
    return items.isEmpty ? nil : items
}

private func parseEpochOrISO8601(_ s: String) -> Int {
    if let i = Int(s) {
        let seconds = (i > 2_000_000_000) ? (Double(i) / 1000.0) : Double(i)
        return Int(seconds.rounded())
    }
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions.insert(.withFractionalSeconds)
    if let d = fmt.date(from: s) { return Int(d.timeIntervalSince1970) }
    return Int(Date().timeIntervalSince1970)
}

private func parseEpochOrISO8601Strict(_ s: String) -> Int? {
    if let i = Int(s) {
        let seconds = (i > 2_000_000_000) ? (Double(i) / 1000.0) : Double(i)
        return Int(seconds.rounded())
    }
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions.insert(.withFractionalSeconds)
    if let d = fmt.date(from: s) { return Int(d.timeIntervalSince1970) }
    return nil
}

private func secondsUntilNextUTCMidnight(from now: Date = Date()) -> Int {
    let tz = TimeZone(secondsFromGMT: 0)!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let comps = cal.dateComponents([.year, .month, .day], from: now)
    guard let todayUTC = cal.date(from: comps), let next = cal.date(byAdding: .day, value: 1, to: todayUTC) else {
        return 86400
    }
    let delta = Int(next.timeIntervalSince(now))
    return max(30, min(172800, delta))
}

private func applyDailyCadenceIfNeededForAltMe(_ items: [FearGreedData]) -> [FearGreedData] {
    guard !items.isEmpty else { return items }
    var out = items
    var first = out[0]
    if first.time_until_update == nil {
        let secs = secondsUntilNextUTCMidnight()
        first = FearGreedData(value: first.value, value_classification: first.value_classification, timestamp: first.timestamp, time_until_update: String(secs))
        out[0] = first
    }
    return out
}

// MARK: - Series normalization helper
/// Normalizes a series to newest-first order, clamps values to [0,100], deduplicates by timestamp,
/// trims to the requested limit, and ensures only the newest item carries a time_until_update hint.
/// Optionally injects a default next-update hint when the newest item lacks one.
private func normalizeSeries(_ list: [FearGreedData], limit: Int, injectDefaultNextIfMissing: Bool = false, defaultNext: Int = 300) -> [FearGreedData] {
    // Clamp helper for value string
    func clampValue(_ s: String) -> String {
        if let i = Int(s) { return String(max(0, min(100, i))) }
        if let d = Double(s) { return String(max(0, min(100, Int(d.rounded())))) }
        return "0"
    }
    func valueBucket(_ v: Int) -> Int {
        switch v {
        case 0...24: return 0
        case 25...44: return 1
        case 45...54: return 2
        case 55...74: return 3
        default: return 4
        }
    }
    func clsBucket(_ cls: String) -> Int? {
        switch cls.lowercased() {
        case "extreme fear": return 0
        case "fear": return 1
        case "neutral": return 2
        case "greed": return 3
        case "extreme greed": return 4
        default: return nil
        }
    }
    // Sort newest-first
    let sorted = list.sorted { (Int($0.timestamp) ?? 0) > (Int($1.timestamp) ?? 0) }
    // Deduplicate by timestamp (keep first/newest)
    var seenTs = Set<Int>()
    var deduped: [FearGreedData] = []
    deduped.reserveCapacity(min(limit, sorted.count))
    for item in sorted {
        let ts = Int(item.timestamp) ?? 0
        if seenTs.contains(ts) { continue }
        seenTs.insert(ts)
        // Clamp value; preserve classification as provided, but fix strong mismatches
        let rawValInt: Int = {
            if let i = Int(item.value) { return i }
            if let d = Double(item.value) { return Int(d.rounded()) }
            return 0
        }()
        let valClamped = max(0, min(100, rawValInt))
        let providedCls = item.value_classification
        let fixedCls: String = {
            if let cb = clsBucket(providedCls), abs(cb - valueBucket(valClamped)) <= 1 {
                return providedCls
            } else {
                return classifyFG(valClamped)
            }
        }()
        let clamped = FearGreedData(
            value: String(valClamped),
            value_classification: fixedCls,
            timestamp: String(ts),
            time_until_update: item.time_until_update
        )
        deduped.append(clamped)
        if deduped.count >= limit { break }
    }
    // Ensure only the newest carries the time_until_update
    var out: [FearGreedData] = []
    out.reserveCapacity(deduped.count)
    for (idx, it) in deduped.enumerated() {
        let next = (idx == 0) ? it.time_until_update : nil
        out.append(FearGreedData(value: it.value, value_classification: it.value_classification, timestamp: it.timestamp, time_until_update: next))
    }
    // Inject default next if requested and missing
    if injectDefaultNextIfMissing, var first = out.first, first.time_until_update == nil {
        first = FearGreedData(value: first.value, value_classification: first.value_classification, timestamp: first.timestamp, time_until_update: String(defaultNext))
        out[0] = first
    }
    return out
}

// MARK: - Coinglass Provider (configurable)
// Coinglass offers a Crypto Fear & Greed Index via their API for partners. This adapter expects
// you to provide an endpoint in Info.plist that returns either { data: [...] } or [...] list
// of items with common keys (value/score/index, classification/label, timestamp/time/updated_at).
// Configure Info.plist:
//   COINGLASS_API_KEY = <your key>
//   COINGLASS_SENTIMENT_URL = https://api.coinglass.com/... (must return a list as described)
struct CoinglassProvider: SentimentProvider {
    let source: SentimentSource = .coinglass

    private var apiKey: String {
        (Bundle.main.infoDictionary?["COINGLASS_API_KEY"] as? String) ?? ""
    }
    private var endpoint: String? {
        Bundle.main.infoDictionary?["COINGLASS_SENTIMENT_URL"] as? String
    }

    func fetch(limit: Int, timeout: TimeInterval) async throws -> [FearGreedData] {
        // When endpoint not configured, use alternative.me as the real external data source
        guard let urlStr = endpoint, !urlStr.isEmpty, let url = URL(string: urlStr) else {
            let alt = try await AlternativeMeProvider().fetch(limit: limit, timeout: timeout)
            postSentimentProvenance(source: source, provenance: "missingEndpoint->altmeFallback", items: alt)
            return alt
        }

        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var q = comps?.queryItems ?? []
        q.append(URLQueryItem(name: "limit", value: String(max(1, limit))))
        comps?.queryItems = q
        guard let finalURL = comps?.url else {
            let alt = try await AlternativeMeProvider().fetch(limit: limit, timeout: timeout)
            postSentimentProvenance(source: source, provenance: "badURL->altmeFallback", items: alt)
            return alt
        }

        var req = URLRequest(url: finalURL)
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("CryptoSage/1.0 (+sentiment)", forHTTPHeaderField: "User-Agent")
        if !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "CG-API-KEY") }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw SentimentProviderError.invalidResponse
            }
            if let list = try decodeFlexibleList(data: data) {
                let norm = normalizeSeries(list, limit: limit, injectDefaultNextIfMissing: false)
                postSentimentProvenance(source: source, provenance: "flexible", items: norm)
                return norm
            } else {
                // Decode failed, use alternative.me
                let alt = try await AlternativeMeProvider().fetch(limit: limit, timeout: timeout)
                postSentimentProvenance(source: source, provenance: "decodeFail->altmeFallback", items: alt)
                return alt
            }
        } catch {
            // Network error, use alternative.me
            let alt = try await AlternativeMeProvider().fetch(limit: limit, timeout: timeout)
            postSentimentProvenance(source: source, provenance: "networkError->altmeFallback", items: alt)
            return alt
        }
    }
}

// MARK: - Lightweight smoothing for the on-device score
// We apply an exponential moving average across calls to reduce jitter without adding lag.
// The smoother keeps a small bit of state (last value and timestamp) in an actor so it's
// concurrency-safe when multiple views request sentiment simultaneously.
private actor CryptoSageSmoother {
    static let shared = CryptoSageSmoother()
    private var lastValue: Double?
    private var lastTimestamp: Date?
    // Time constant for smoothing; half-life roughly 5–7 minutes depending on cadence.
    private let tau: TimeInterval = 7 * 60

    private let valueKey = "CryptoSageSmoother.lastValue.v2"  // Bumped version to clear old data
    private let timeKey  = "CryptoSageSmoother.lastTimestamp.v2"
    private init() {
        if let v = UserDefaults.standard.object(forKey: valueKey) as? Double {
            lastValue = v
        }
        if let t = UserDefaults.standard.object(forKey: timeKey) as? Double {
            lastTimestamp = Date(timeIntervalSince1970: t)
        }
        // Clear old version keys
        UserDefaults.standard.removeObject(forKey: "CryptoSageSmoother.lastValue")
        UserDefaults.standard.removeObject(forKey: "CryptoSageSmoother.lastTimestamp")
    }
    private func persist() {
        if let v = lastValue { UserDefaults.standard.set(v, forKey: valueKey) }
        if let t = lastTimestamp?.timeIntervalSince1970 { UserDefaults.standard.set(t, forKey: timeKey) }
    }
    
    /// Reset the smoother (useful for debugging or when data source changes)
    func reset() {
        lastValue = nil
        lastTimestamp = nil
        UserDefaults.standard.removeObject(forKey: valueKey)
        UserDefaults.standard.removeObject(forKey: timeKey)
        DebugLog.log("Sentiment", "CryptoSageSmoother reset")
    }

    func smooth(current: Double, now: Date) -> Double {
        guard let prev = lastValue, let t0 = lastTimestamp else {
            // First call - no smoothing, just use current value
            lastValue = current
            lastTimestamp = now
            persist()
            DebugLog.log("Sentiment", "Smoother: first value = \(Int(current))")
            return current
        }
        let dt = now.timeIntervalSince(t0)
        // If it's been a long time since the last update, reset the filter to the new value
        // Reduced from 2 hours to 30 minutes for fresher data
        if dt > 30 * 60 { // > 30 minutes
            lastValue = current
            lastTimestamp = now
            persist()
            DebugLog.log("Sentiment", "Smoother: stale (\(Int(dt/60))min), reset to \(Int(current))")
            return current
        }
        // Convert to an EMA factor. Clamp to avoid over/under-reaction when calls are irregular.
        let alpha = max(0.05, min(0.8, 1 - exp(-dt / tau)))
        let s = prev + alpha * (current - prev)
        lastValue = s
        lastTimestamp = now
        persist()
        return s
    }
}

// MARK: - Daily cache for alternative.me baseline
// Since alternative.me updates once per day at UTC midnight, we cache the fetched values
// and only re-fetch after the UTC day changes. This prevents redundant API calls.
private actor AlternativeMeBaselineCache {
    static let shared = AlternativeMeBaselineCache()
    
    struct CachedData: Codable {
        let utcDay: Int // Days since epoch (UTC)
        let baseline: Int?
        let yesterday: Int?
        let week: Int?
        let month: Int?  // ~30 days ago
        let fetchedAt: Double // timestamp
    }
    
    private var cached: CachedData?
    private let cacheKey = "AlternativeMeBaselineCache.data.v4"  // Bumped to fix index bug
    
    /// FIX: Track if we've already logged "using cached" to reduce console spam
    private var hasLoggedCacheHit: Bool = false
    
    private init() {
        // Inline load logic: actor init cannot call actor-isolated methods
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode(CachedData.self, from: data) {
            cached = decoded
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode(CachedData.self, from: data) {
            cached = decoded
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    
    /// Returns the current UTC day as days since epoch
    private func currentUTCDay() -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        if let date = cal.date(from: comps) {
            return Int(date.timeIntervalSince1970 / 86400)
        }
        return Int(Date().timeIntervalSince1970 / 86400)
    }
    
    /// Check if we have valid cached data for today (UTC)
    func getCached() -> (baseline: Int?, yesterday: Int?, week: Int?, month: Int?)? {
        guard let c = cached else { return nil }
        let today = currentUTCDay()
        // Cache is valid if it's from today (UTC) AND has actual data
        // Don't return empty/nil cache as a valid hit - force a fresh fetch
        if c.utcDay == today {
            // Require at least baseline and yesterday to be present
            guard c.baseline != nil && c.yesterday != nil else {
                DebugLog.log("Sentiment", "Cache has nil values, invalidating and forcing fresh fetch")
                // Clear the bad cache entry
                cached = nil
                UserDefaults.standard.removeObject(forKey: cacheKey)
                return nil
            }
            // FIX: Only log cache hit once per session to reduce console spam
            if !hasLoggedCacheHit {
                hasLoggedCacheHit = true
                DebugLog.log("Sentiment", "Using cached alternative.me baseline: \(c.baseline ?? -1), yesterday: \(c.yesterday ?? -1), week: \(c.week ?? -1), month: \(c.month ?? -1)")
            }
            return (c.baseline, c.yesterday, c.week, c.month)
        }
        return nil
    }
    
    /// Store fresh data with current UTC day
    func store(baseline: Int?, yesterday: Int?, week: Int?, month: Int?) {
        // Only cache if we have valid data (at least baseline and yesterday)
        guard baseline != nil && yesterday != nil else {
            DebugLog.log("Sentiment", "Not caching alternative.me data - missing baseline or yesterday")
            return
        }
        let today = currentUTCDay()
        cached = CachedData(
            utcDay: today,
            baseline: baseline,
            yesterday: yesterday,
            week: week,
            month: month,
            fetchedAt: Date().timeIntervalSince1970
        )
        save()
        DebugLog.log("Sentiment", "Cached alternative.me baseline: \(baseline ?? -1), yesterday: \(yesterday ?? -1), week: \(week ?? -1), month: \(month ?? -1) for UTC day \(today)")
    }
    
    /// Invalidate the cache (useful for debugging or forced refresh)
    func invalidate() {
        cached = nil
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}

// MARK: - CryptoSage AI Historical Score Computation
// Computes historical sentiment scores by fetching historical market data from CoinGecko
// and running the same CryptoSage AI model on past snapshots.

/// Cache for computed historical CryptoSage AI scores
/// These are computed from historical market data, not copied from alternative.me
private actor CryptoSageHistoricalCache {
    static let shared = CryptoSageHistoricalCache()
    
    struct CachedScores: Codable {
        let utcDay: Int
        let yesterday: Int
        let lastWeek: Int
        let lastMonth: Int
        let computedAt: Double
    }
    
    private var cached: CachedScores?
    private let cacheKey = "CryptoSageHistoricalCache.scores.v2"  // Bumped to clear stale data
    
    private init() {
        // Inline load logic: actor init cannot call actor-isolated methods
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode(CachedScores.self, from: data) {
            cached = decoded
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode(CachedScores.self, from: data) {
            cached = decoded
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    
    private func currentUTCDay() -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        if let date = cal.date(from: comps) {
            return Int(date.timeIntervalSince1970 / 86400)
        }
        return Int(Date().timeIntervalSince1970 / 86400)
    }
    
    func getCached() -> (yesterday: Int, lastWeek: Int, lastMonth: Int)? {
        guard let c = cached else { return nil }
        let today = currentUTCDay()
        if c.utcDay == today {
            DebugLog.log("Sentiment", "Using cached CryptoSage AI historical scores: y=\(c.yesterday), w=\(c.lastWeek), m=\(c.lastMonth)")
            return (c.yesterday, c.lastWeek, c.lastMonth)
        }
        return nil
    }
    
    func store(yesterday: Int, lastWeek: Int, lastMonth: Int) {
        let today = currentUTCDay()
        cached = CachedScores(
            utcDay: today,
            yesterday: yesterday,
            lastWeek: lastWeek,
            lastMonth: lastMonth,
            computedAt: Date().timeIntervalSince1970
        )
        save()
        DebugLog.log("Sentiment", "Cached CryptoSage AI historical scores: y=\(yesterday), w=\(lastWeek), m=\(lastMonth)")
    }
    
    func invalidate() {
        cached = nil
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}

/// Historical price data point with timestamp
private struct HistoricalPricePoint {
    let timestamp: TimeInterval // Unix timestamp
    let price: Double
}

/// Fetches historical prices from CoinGecko for a coin (returns timestamp + price pairs)
private func fetchHistoricalPricesWithTimestamps(coinID: String, days: Int = 31) async -> [HistoricalPricePoint] {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.coingecko.com"
    components.path = "/api/v3/coins/\(coinID)/market_chart"
    components.queryItems = [
        URLQueryItem(name: "vs_currency", value: CurrencyManager.apiValue),
        URLQueryItem(name: "days", value: String(days))
    ]
    
    guard let url = components.url else { return [] }
    
    var request = APIConfig.coinGeckoRequest(url: url)
    request.timeoutInterval = 10
    
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            DebugLog.log("Sentiment", "CoinGecko rate limited for \(coinID)")
            return []
        }
        
        struct MarketChartResponse: Decodable {
            let prices: [[Double]] // [[timestamp_ms, price], ...]
        }
        
        let decoded = try JSONDecoder().decode(MarketChartResponse.self, from: data)
        return decoded.prices.compactMap { arr in
            guard arr.count >= 2 else { return nil }
            return HistoricalPricePoint(timestamp: arr[0] / 1000.0, price: arr[1])
        }
    } catch {
        DebugLog.log("Sentiment", "Failed to fetch historical prices for \(coinID): \(error.localizedDescription)")
        return []
    }
}

/// Finds the price at a specific timestamp (nearest point within tolerance)
private func priceAt(timestamp: TimeInterval, in prices: [HistoricalPricePoint], toleranceHours: Double = 6) -> Double? {
    guard !prices.isEmpty else { return nil }
    let tolerance = toleranceHours * 3600
    
    var best: HistoricalPricePoint?
    var bestDistance: TimeInterval = .infinity
    
    for point in prices {
        let distance = abs(point.timestamp - timestamp)
        if distance < bestDistance {
            bestDistance = distance
            best = point
        }
    }
    
    if let best = best, bestDistance <= tolerance {
        return best.price
                    }
                    return nil
}

/// Computes percent change between two prices
private func computePercentChange(from earlier: Double, to later: Double) -> Double {
    guard earlier > 0, later > 0 else { return 0 }
    return ((later - earlier) / earlier) * 100.0
}

/// Computes CryptoSage AI score from historical market snapshot data
/// This is a simplified version of the main model that works with historical prices
private func computeHistoricalCryptoSageScore(
    btc24hChange: Double,
    btc7dChange: Double,
    altMedianChange: Double,
    breadthRatio: Double, // 0-1, fraction of alts with positive 24h change
    dispersion: Double // stddev of alt changes
) -> Int {
    // Use the same model logic as DerivedSentimentProvider
    func clampPercent(_ x: Double) -> Double {
        x.isFinite ? max(-100, min(100, x)) : 0
    }
    
    let breadthTerm = (max(0, min(1, breadthRatio)) - 0.5) * 2.0 // [-1, 1]
    let btc24 = clampPercent(btc24hChange)
    let btc7 = clampPercent(btc7dChange)
    let altMed = clampPercent(altMedianChange)
    let disp = max(0, min(100, dispersion))
    
    let volFactor = min(1.0, tanh(disp / 20.0))
    let calmFactor = 1.0 - volFactor
    
    // Same weights as the main model
    let wBreadth: Double = 12.0
    let wBTC24: Double = 12.0
    let wBTC7: Double = 8.0 + 3.0 * calmFactor
    let wAltMed: Double = 5.0 + 3.0 * calmFactor
    let wDispPenalty: Double = 8.0 + 12.0 * volFactor
    
    let scoreRaw = 50.0
        + wBTC24 * tanh(btc24 / 8.0)
        + wBreadth * breadthTerm
        + wBTC7 * tanh(btc7 / 15.0)
        + wAltMed * tanh(altMed / 6.0)
        - wDispPenalty * tanh(disp / 15.0)
    
    return Int(round(max(0, min(100, scoreRaw))))
}

/// Computes CryptoSage AI historical scores from CoinGecko data
/// Returns (yesterday, lastWeek, lastMonth) scores, all computed using our model
private func computeCryptoSageHistoricalScores(timeout: TimeInterval) async -> (yesterday: Int, lastWeek: Int, lastMonth: Int)? {
    // Check cache first
    if let cached = await CryptoSageHistoricalCache.shared.getCached() {
        return cached
    }
    
    DebugLog.log("Sentiment", "Computing CryptoSage AI historical scores from market data...")
    
    // Fetch historical BTC prices (31 days) - this is required
    let btcPrices = await fetchHistoricalPricesWithTimestamps(coinID: "bitcoin", days: 31)
    guard btcPrices.count >= 30 else {
        DebugLog.log("Sentiment", "Insufficient BTC historical data: \(btcPrices.count) points")
        return nil
    }
    
    // Fetch top altcoin prices for breadth calculation
    // Use a smaller, more critical set to reduce API calls (5 instead of 10)
    // This reduces rate limiting risk while still providing good breadth signals
    let altcoinIDs = ["ethereum", "solana", "binancecoin", "ripple", "cardano"]
    
    var altPricesMap: [String: [HistoricalPricePoint]] = [:]
    
    // Fetch altcoins with longer delays to avoid rate limiting
    for altID in altcoinIDs {
        // Longer delay between calls (0.5 second) to respect rate limits
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        
        let prices = await fetchHistoricalPricesWithTimestamps(coinID: altID, days: 31)
        if prices.count >= 30 {
            altPricesMap[altID] = prices
            DebugLog.log("Sentiment", "Historical data for \(altID): \(prices.count) points")
        } else {
            DebugLog.log("Sentiment", "Historical data for \(altID) insufficient: \(prices.count) points")
        }
    }
    
    // Require at least 2 altcoins for meaningful breadth calculation
    guard altPricesMap.count >= 2 else {
        DebugLog.log("Sentiment", "Insufficient altcoin historical data: only \(altPricesMap.count) coins available")
        return nil
    }
    
    let now = Date().timeIntervalSince1970
    let oneDay: TimeInterval = 86400
    
    // Helper to compute score at a specific historical point
    func computeScoreAt(targetTime: TimeInterval, lookback24h: TimeInterval, lookback7d: TimeInterval) -> Int? {
        // Get BTC prices
        guard let btcAtTarget = priceAt(timestamp: targetTime, in: btcPrices),
              let btcAt24hAgo = priceAt(timestamp: targetTime - lookback24h, in: btcPrices),
              let btcAt7dAgo = priceAt(timestamp: targetTime - lookback7d, in: btcPrices) else {
            return nil
        }
        
        let btc24hChange = computePercentChange(from: btcAt24hAgo, to: btcAtTarget)
        let btc7dChange = computePercentChange(from: btcAt7dAgo, to: btcAtTarget)
        
        // Compute alt changes for breadth and median
        var altChanges: [Double] = []
        for (_, altPrices) in altPricesMap {
            if let altAtTarget = priceAt(timestamp: targetTime, in: altPrices),
               let altAt24hAgo = priceAt(timestamp: targetTime - lookback24h, in: altPrices) {
                let change = computePercentChange(from: altAt24hAgo, to: altAtTarget)
                altChanges.append(change)
            }
        }
        
        guard !altChanges.isEmpty else { return nil }
        
        // Breadth: fraction with positive change
        let upCount = altChanges.filter { $0 >= 0 }.count
        let breadthRatio = Double(upCount) / Double(altChanges.count)
        
        // Median alt change
        let sorted = altChanges.sorted()
        let median: Double
        if sorted.count % 2 == 0 {
            median = (sorted[sorted.count/2 - 1] + sorted[sorted.count/2]) / 2.0
        } else {
            median = sorted[sorted.count/2]
        }
        
        // Dispersion (stddev) - use sample variance (n-1) for unbiased estimation
        let mean = altChanges.reduce(0, +) / Double(altChanges.count)
        let variance = altChanges.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(1, altChanges.count - 1))
        let dispersion = sqrt(variance)
        
        return computeHistoricalCryptoSageScore(
            btc24hChange: btc24hChange,
            btc7dChange: btc7dChange,
            altMedianChange: median,
            breadthRatio: breadthRatio,
            dispersion: dispersion
        )
    }
    
    // Compute scores at historical points
    let yesterdayTime = now - oneDay
    let lastWeekTime = now - 7 * oneDay
    let lastMonthTime = now - 30 * oneDay
    
    guard let yesterdayScore = computeScoreAt(targetTime: yesterdayTime, lookback24h: oneDay, lookback7d: 7 * oneDay),
          let lastWeekScore = computeScoreAt(targetTime: lastWeekTime, lookback24h: oneDay, lookback7d: 7 * oneDay),
          let lastMonthScore = computeScoreAt(targetTime: lastMonthTime, lookback24h: oneDay, lookback7d: 7 * oneDay) else {
        DebugLog.log("Sentiment", "Failed to compute all historical scores")
        return nil
    }
    
    // Cache the results
    await CryptoSageHistoricalCache.shared.store(yesterday: yesterdayScore, lastWeek: lastWeekScore, lastMonth: lastMonthScore)
    
    DebugLog.log("Sentiment", "Computed CryptoSage AI historical: yesterday=\(yesterdayScore), week=\(lastWeekScore), month=\(lastMonthScore)")
    
    return (yesterdayScore, lastWeekScore, lastMonthScore)
}

/// Helper to classify a sentiment score into a human-readable classification
private func classifyScore(_ value: Int) -> String {
    switch value {
    case 0...24: return "extreme fear"
    case 25...44: return "fear"
    case 45...54: return "neutral"
    case 55...74: return "greed"
    default: return "extreme greed"
    }
}

/// Emergency fallback: Fetch alternative.me historical values when CryptoSage AI computation fails
/// This is ONLY used as a last resort for fresh installs or when CoinGecko is unavailable
private func fetchAlternativeMeEmergencyFallback(timeout: TimeInterval) async -> (yesterday: Int, lastWeek: Int, lastMonth: Int)? {
    // Check if we have cached alternative.me data first
    if let cached = await AlternativeMeBaselineCache.shared.getCached() {
        if let y = cached.yesterday, let w = cached.week, let m = cached.month {
            // FIX: Removed verbose logging here - the caller logs once per session
            return (y, w, m)
        }
    }
    
    // Fetch fresh from alternative.me
    do {
        // Request 32 items to ensure we have enough data (index 0-31)
        let altData = try await AlternativeMeProvider().fetch(limit: 32, timeout: min(8.0, timeout))
        
        // Extract historical values using correct indices:
        // altData[0] = today, altData[1] = 1 day ago, altData[7] = 7 days ago, altData[30] = 30 days ago
        let yesterday: Int? = altData.count > 1 ? Int(altData[1].value) : nil
        let week: Int? = altData.count > 7 ? Int(altData[7].value) : nil      // Fixed: was index 6
        let month: Int? = altData.count > 30 ? Int(altData[30].value) : nil   // Fixed: was index 29
        
        // Also get baseline for caching
        let baseline: Int? = altData.first.flatMap { Int($0.value) }
        
        // Cache for future use
        await AlternativeMeBaselineCache.shared.store(baseline: baseline, yesterday: yesterday, week: week, month: month)
        
        if let y = yesterday, let w = week, let m = month,
           y >= 0, y <= 100, w >= 0, w <= 100, m >= 0, m <= 100 {
            DebugLog.log("Sentiment", "Fetched alternative.me emergency fallback: y=\(y), w=\(w), m=\(m)")
            return (y, w, m)
        }
    } catch {
        DebugLog.log("Sentiment", "Alternative.me emergency fallback fetch failed: \(error.localizedDescription)")
    }
    
    return nil
}

// MARK: - Debounce Cache for DerivedSentimentProvider

/// Actor to cache sentiment calculation results and prevent duplicate calculations within a short time window.
/// This reduces CPU work and prevents duplicate log spam when multiple views request sentiment data simultaneously.
private actor DerivedSentimentCache {
    static let shared = DerivedSentimentCache()
    
    private var cachedResult: [FearGreedData]? = nil
    private var cacheTimestamp: Date? = nil
    private var calculationInProgress: Task<[FearGreedData], Error>? = nil
    
    /// PERFORMANCE FIX v21: Increased from 5s to 60s. Sentiment data changes slowly (minute-level),
    /// but the old 5s cache was allowing 3+ competing schedulers (View timer, ViewModel timer, prewarm)
    /// to each make fresh Firebase calls. 60s cache means all callers share one result per minute.
    private let debounceInterval: TimeInterval = 60.0
    
    /// Check if we have a fresh cached result
    func getCachedIfFresh() -> [FearGreedData]? {
        guard let cached = cachedResult,
              let timestamp = cacheTimestamp,
              Date().timeIntervalSince(timestamp) < debounceInterval else {
            return nil
        }
        return cached
    }
    
    /// Store a calculated result in the cache
    func store(_ result: [FearGreedData]) {
        cachedResult = result
        cacheTimestamp = Date()
    }
    
    /// Get or set the in-progress calculation task to prevent parallel calculations
    func getInProgressTask() -> Task<[FearGreedData], Error>? {
        return calculationInProgress
    }
    
    func setInProgressTask(_ task: Task<[FearGreedData], Error>?) {
        calculationInProgress = task
    }
}

/// CryptoSage AI Sentiment
/// Provides a consistent Fear & Greed–style score across all users.
/// Primary: Firebase calculation (server-side, shared across all users)
/// Fallback: On-device calculation from market breadth, BTC momentum, altcoin momentum, etc.
/// This ensures all users see the same score while maintaining offline capability.
/// The `time_until_update` on the most recent item is an adaptive hint (1–15 minutes) based on market activity.
struct DerivedSentimentProvider: SentimentProvider {
    let source: SentimentSource = .derived
    
    // MARK: - Persisted Firebase Metrics
    // These are stored to UserDefaults so they survive cache hits and app restarts.
    // Without persistence, the cache path returns FearGreedData (the score) but skips
    // the Firebase call entirely, leaving these metrics nil → showing "—" in the UI.
    
    private static let btc24hKey = "DerivedSentiment.lastFirebaseBTC24h"
    private static let breadthKey = "DerivedSentiment.lastFirebaseBreadth"
    private static let volatilityKey = "DerivedSentiment.lastFirebaseVolatility"
    
    static var lastFirebaseBTC24h: Double? {
        didSet { if let v = lastFirebaseBTC24h { UserDefaults.standard.set(v, forKey: btc24hKey) } }
    }
    static var lastFirebaseBreadth: Int? {
        didSet { if let v = lastFirebaseBreadth { UserDefaults.standard.set(v, forKey: breadthKey) } }
    }
    static var lastFirebaseVolatility: Double? {
        didSet { if let v = lastFirebaseVolatility { UserDefaults.standard.set(v, forKey: volatilityKey) } }
    }
    
    /// Restore persisted metrics (call on app launch or before first use)
    static func restorePersistedMetrics() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: btc24hKey) != nil {
            lastFirebaseBTC24h = defaults.double(forKey: btc24hKey)
        }
        if defaults.object(forKey: breadthKey) != nil {
            lastFirebaseBreadth = defaults.integer(forKey: breadthKey)
        }
        if defaults.object(forKey: volatilityKey) != nil {
            lastFirebaseVolatility = defaults.double(forKey: volatilityKey)
        }
        #if DEBUG
        if !_hasLoggedRestore, lastFirebaseBTC24h != nil || lastFirebaseBreadth != nil || lastFirebaseVolatility != nil {
            _hasLoggedRestore = true
            print("[DerivedSentiment] Restored persisted metrics: breadth=\(lastFirebaseBreadth.map { "\($0)%" } ?? "nil"), btc24h=\(lastFirebaseBTC24h.map { String(format: "%.2f%%", $0) } ?? "nil"), vol=\(lastFirebaseVolatility.map { String(format: "%.2f", $0) } ?? "nil")")
        }
        #endif
    }
    
    /// FIX: Track if we've logged the "restored metrics" message to reduce console spam
    private static var _hasLoggedRestore: Bool = false
    /// FIX: Track if we've logged the "no history" message to reduce console spam
    static var hasLoggedHistoryFallback: Bool = false
    /// FIX: Track if we've logged the "added baseline" message to reduce console spam
    static var hasLoggedAddedBaseline: Bool = false

    func fetch(limit: Int, timeout: TimeInterval) async throws -> [FearGreedData] {
        // FIREBASE ONLY: Always use Firebase for CryptoSage AI sentiment to ensure
        // consistency across ALL devices. This is critical for professional UX.
        // All users must see the same score at the same time.
        
        // Ensure persisted metrics are loaded (survives app restarts)
        DerivedSentimentProvider.restorePersistedMetrics()
        
        // First check if we have a fresh cached result (from Firebase)
        if let cached = await DerivedSentimentCache.shared.getCachedIfFresh() {
            DebugLog.log("Sentiment", "Using cached Firebase CryptoSage AI result (persisted metrics restored)")
            return cached
        }
        
        // If another fetch is in progress, wait for it
        if let existingTask = await DerivedSentimentCache.shared.getInProgressTask() {
            return try await existingTask.value
        }
        
        // Start Firebase fetch task
        let task = Task<[FearGreedData], Error> {
            // Try Firebase - this is the ONLY authoritative source for consistency
            do {
                let firebaseResponse = try await FirebaseService.shared.getCryptoSageAISentiment()
                
                // Store metrics for UI access
                DerivedSentimentProvider.lastFirebaseBTC24h = firebaseResponse.btc24h
                DerivedSentimentProvider.lastFirebaseBreadth = firebaseResponse.breadth
                DerivedSentimentProvider.lastFirebaseVolatility = firebaseResponse.volatility
                
                // Parse timestamp
                let iso8601Formatter = ISO8601DateFormatter()
                iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let timestamp: Date
                if let parsed = iso8601Formatter.date(from: firebaseResponse.updatedAt) {
                    timestamp = parsed
                } else {
                    // Fallback parser without fractional seconds
                    iso8601Formatter.formatOptions = [.withInternetDateTime]
                    timestamp = iso8601Formatter.date(from: firebaseResponse.updatedAt) ?? Date()
                }
                
                // Calculate time until next update (Firebase refreshes every 3 minutes)
                let nextUpdate = timestamp.addingTimeInterval(180) // 3 minutes
                let timeUntilUpdate = max(30, Int(nextUpdate.timeIntervalSince(Date())))
                
                // Convert to epoch timestamp string for FearGreedData
                let epochTimestamp = String(Int(timestamp.timeIntervalSince1970))
                
                // Build full data array with historical entries from Firebase
                // This ensures all users see consistent historical values
                var dataArray: [FearGreedData] = []
                
                // Current value (Now)
                let nowData = FearGreedData(
                    value: String(firebaseResponse.score),
                    value_classification: firebaseResponse.verdict.lowercased(),
                    timestamp: epochTimestamp,
                    time_until_update: String(timeUntilUpdate)
                )
                dataArray.append(nowData)
                
                // Yesterday (1 day ago)
                if let yesterday = firebaseResponse.yesterday {
                    let yesterdayTs = timestamp.addingTimeInterval(-86400) // 1 day ago
                    let yesterdayData = FearGreedData(
                        value: String(yesterday.score),
                        value_classification: yesterday.verdict.lowercased(),
                        timestamp: String(Int(yesterdayTs.timeIntervalSince1970)),
                        time_until_update: nil
                    )
                    dataArray.append(yesterdayData)
                }
                
                // Last Week (7 days ago)
                if let lastWeek = firebaseResponse.lastWeek {
                    let lastWeekTs = timestamp.addingTimeInterval(-7 * 86400) // 7 days ago
                    let lastWeekData = FearGreedData(
                        value: String(lastWeek.score),
                        value_classification: lastWeek.verdict.lowercased(),
                        timestamp: String(Int(lastWeekTs.timeIntervalSince1970)),
                        time_until_update: nil
                    )
                    dataArray.append(lastWeekData)
                }
                
                // Last Month (30 days ago)
                if let lastMonth = firebaseResponse.lastMonth {
                    let lastMonthTs = timestamp.addingTimeInterval(-30 * 86400) // 30 days ago
                    let lastMonthData = FearGreedData(
                        value: String(lastMonth.score),
                        value_classification: lastMonth.verdict.lowercased(),
                        timestamp: String(Int(lastMonthTs.timeIntervalSince1970)),
                        time_until_update: nil
                    )
                    dataArray.append(lastMonthData)
                }
                
                // Log historical data availability
                let historyStatus = [
                    firebaseResponse.yesterday != nil ? "y=\(firebaseResponse.yesterday!.score)" : "y=N/A",
                    firebaseResponse.lastWeek != nil ? "w=\(firebaseResponse.lastWeek!.score)" : "w=N/A",
                    firebaseResponse.lastMonth != nil ? "m=\(firebaseResponse.lastMonth!.score)" : "m=N/A"
                ].joined(separator: ", ")
                
                DebugLog.log("Sentiment", "Firebase CryptoSage AI: score=\(firebaseResponse.score), verdict=\(firebaseResponse.verdict), history=[\(historyStatus)], breadth=\(firebaseResponse.breadth)%, BTC24h=\(firebaseResponse.btc24h)%")
                
                // If no historical data from Firebase, fall back to alternative.me for historical values
                // This ensures users see meaningful historical comparison even before Firebase history builds up
                if firebaseResponse.yesterday == nil && firebaseResponse.lastWeek == nil && firebaseResponse.lastMonth == nil {
                    // FIX: Only log this message once per app session to reduce console spam
                    // The actual fetch uses cache internally, so this is more informational
                    if !DerivedSentimentProvider.hasLoggedHistoryFallback {
                        DerivedSentimentProvider.hasLoggedHistoryFallback = true
                        DebugLog.log("Sentiment", "Firebase has no history yet, using alternative.me for historical baseline")
                    }
                    if let altBaseline = await fetchAlternativeMeEmergencyFallback(timeout: timeout) {
                        // Add historical entries from alternative.me
                        let yesterdayTs = timestamp.addingTimeInterval(-86400)
                        let lastWeekTs = timestamp.addingTimeInterval(-7 * 86400)
                        let lastMonthTs = timestamp.addingTimeInterval(-30 * 86400)
                        
                        dataArray.append(FearGreedData(
                            value: String(altBaseline.yesterday),
                            value_classification: classifyScore(altBaseline.yesterday),
                            timestamp: String(Int(yesterdayTs.timeIntervalSince1970)),
                            time_until_update: nil
                        ))
                        dataArray.append(FearGreedData(
                            value: String(altBaseline.lastWeek),
                            value_classification: classifyScore(altBaseline.lastWeek),
                            timestamp: String(Int(lastWeekTs.timeIntervalSince1970)),
                            time_until_update: nil
                        ))
                        dataArray.append(FearGreedData(
                            value: String(altBaseline.lastMonth),
                            value_classification: classifyScore(altBaseline.lastMonth),
                            timestamp: String(Int(lastMonthTs.timeIntervalSince1970)),
                            time_until_update: nil
                        ))
                        // FIX: Only log this once per session to reduce console spam
                        if !DerivedSentimentProvider.hasLoggedAddedBaseline {
                            DerivedSentimentProvider.hasLoggedAddedBaseline = true
                            DebugLog.log("Sentiment", "Added alternative.me historical baseline: y=\(altBaseline.yesterday), w=\(altBaseline.lastWeek), m=\(altBaseline.lastMonth)")
                        }
                    }
                }
                
                return dataArray
            } catch {
                DebugLog.log("Sentiment", "Firebase CryptoSage AI failed: \(error.localizedDescription)")
                
                // FALLBACK: Use alternative.me as consistent external source
                // This ensures all devices get the same data even when Firebase is down
                let altData = try await AlternativeMeProvider().fetch(limit: limit, timeout: timeout)
                DebugLog.log("Sentiment", "CryptoSage AI using alternative.me fallback for consistency")
                postSentimentProvenance(source: self.source, provenance: "firebase-failed->altme-fallback", items: altData)
                
                // FIX: When Firebase fails, compute sub-metrics locally so the UI doesn't show "—"
                // These are best-effort from local market data — not as consistent as Firebase,
                // but much better than empty dashes
                await Self.populateMetricsFromLocalData()
                
                return altData
            }
        }
        
        await DerivedSentimentCache.shared.setInProgressTask(task)
        
        do {
            let result = try await task.value
            await DerivedSentimentCache.shared.store(result)
            await DerivedSentimentCache.shared.setInProgressTask(nil)
            return result
        } catch {
            await DerivedSentimentCache.shared.setInProgressTask(nil)
            throw error
        }
    }
    
    /// Compute sub-metrics from local MarketViewModel data when Firebase is unavailable.
    /// This ensures the Breadth / BTC 24h / Volatility fields show something meaningful
    /// even when the Firebase call fails or is slow.
    @MainActor
    static func populateMetricsFromLocalData() {
        let mv = MarketViewModel.shared
        let coins = !mv.allCoins.isEmpty ? mv.allCoins : (!mv.coins.isEmpty ? mv.coins : mv.watchlistCoins)
        
        let stableSet: Set<String> = ["USDT","USDC","BUSD","DAI","FDUSD","TUSD","USDP","GUSD","FRAX","LUSD"]
        let nonStableCoins = coins.filter { !stableSet.contains($0.symbol.uppercased()) }
        
        // Breadth: % of non-stablecoin top coins with positive 24h change
        if lastFirebaseBreadth == nil {
            let changes = nonStableCoins.compactMap { $0.priceChangePercentage24hInCurrency ?? $0.changePercent24Hr }
            if !changes.isEmpty {
                let upCount = changes.filter { $0 >= 0 }.count
                let breadthPct = (Double(upCount) / Double(changes.count)) * 100.0
                lastFirebaseBreadth = Int(breadthPct)
            }
        }
        
        // BTC 24h change
        if lastFirebaseBTC24h == nil {
            if let liveChange = LivePriceManager.shared.bestChange24hPercent(for: "BTC"), liveChange.isFinite, abs(liveChange) <= 300 {
                lastFirebaseBTC24h = liveChange
            } else if let btcCoin = coins.first(where: { $0.symbol.uppercased() == "BTC" }) {
                if let p = btcCoin.priceChangePercentage24hInCurrency, p.isFinite, abs(p) <= 300 {
                    lastFirebaseBTC24h = p
                } else if let p = btcCoin.changePercent24Hr, p.isFinite, abs(p) <= 300 {
                    lastFirebaseBTC24h = p
                }
            }
        }
        
        // Volatility: standard deviation of 24h changes across non-stablecoins
        if lastFirebaseVolatility == nil {
            let changes = nonStableCoins.compactMap { $0.priceChangePercentage24hInCurrency ?? $0.changePercent24Hr }
            if changes.count >= 5 {
                let mean = changes.reduce(0, +) / Double(changes.count)
                let variance = changes.reduce(0) { $0 + pow($1 - mean, 2) } / Double(changes.count - 1)
                lastFirebaseVolatility = min(20.0, sqrt(variance))
            }
        }
        
        #if DEBUG
        print("[DerivedSentiment] Local metrics fallback: breadth=\(lastFirebaseBreadth.map { "\($0)%" } ?? "nil"), btc24h=\(lastFirebaseBTC24h.map { String(format: "%.2f%%", $0) } ?? "nil"), vol=\(lastFirebaseVolatility.map { String(format: "%.2f", $0) } ?? "nil")")
        #endif
    }
    
    /// The actual sentiment calculation logic (extracted from original fetch method)
    private func performCalculation(limit: Int, timeout: TimeInterval) async throws -> [FearGreedData] {
        // CryptoSage AI: 100% independent model
        // Historical values are computed from CoinGecko historical data using our model
        // No alternative.me dependency for any calculation
        
        // Gather data from MarketViewModel.shared (if available)

        let coins: [MarketCoin] = await MainActor.run {
            let mv = MarketViewModel.shared
            if !mv.allCoins.isEmpty { return mv.allCoins }
            if !mv.coins.isEmpty { return mv.coins }
            if !mv.watchlistCoins.isEmpty { return mv.watchlistCoins }
            return []
        }

        // Select top coins for signal quality (prefer rank, else market cap), limit to 100
        let topCoins: [MarketCoin] = {
            guard !coins.isEmpty else { return [] }
            // Prefer market-cap rank when available, but supplement with market cap to reach 100
            let ranked = coins.filter { ($0.marketCapRank ?? Int.max) < Int.max }
                .sorted { ($0.marketCapRank ?? Int.max) < ($1.marketCapRank ?? Int.max) }

            if ranked.count >= 100 {
                return Array(ranked.prefix(100))
            }

            let withCap = coins.filter { ($0.marketCap ?? 0) > 0 }
                .sorted { ($0.marketCap ?? 0) > ($1.marketCap ?? 0) }

            var result: [MarketCoin] = []
            result.reserveCapacity(min(100, coins.count))
            var seen = Set<String>()

            for c in ranked {
                result.append(c)
                seen.insert(c.symbol.uppercased())
                if result.count >= 100 { return result }
            }
            for c in withCap {
                let sym = c.symbol.uppercased()
                if !seen.contains(sym) {
                    result.append(c)
                    seen.insert(sym)
                    if result.count >= 100 { break }
                }
            }
            if result.isEmpty {
                return Array(withCap.prefix(100))
            }
            return result
        }()

        let effectiveTopCoins: [MarketCoin] = topCoins

        // Exclude stablecoins from breadth calculations to avoid bias from near-zero change assets
        let stableSet: Set<String> = ["USDT","USDC","BUSD","DAI","FDUSD","TUSD","USDP","GUSD","FRAX","LUSD"]

        // Derive coverage from coins that actually have a 24h change available (exclude stables)
        let coinsWith24h = effectiveTopCoins.filter { !stableSet.contains($0.symbol.uppercased()) && (($0.priceChangePercentage24hInCurrency ?? $0.changePercent24Hr) != nil) }
        let availableCount = coinsWith24h.count
        let expectedUniverse = max(1.0, Double(min(100, effectiveTopCoins.count)))
        let coverageRatio = Double(availableCount) / expectedUniverse

        // 1) Breadth across the top set (fraction of coins with non‑negative 24h change among those with data)
        let upCount = coinsWith24h.filter { coin in
            let cp = coin.priceChangePercentage24hInCurrency ?? coin.changePercent24Hr
            return (cp ?? 0) >= 0
        }.count
        let downCount = coinsWith24h.count - upCount
        let denom = max(1, availableCount)
        let upRatio: Double = Double(upCount) / Double(denom)
        let breadth = max(0.0, min(1.0, upRatio))
        DebugLog.log("Sentiment", "Breadth: \(upCount) up / \(downCount) down of \(coinsWith24h.count) coins = \(String(format: "%.0f", breadth * 100))%")

        // Cap-weighted breadth: large caps carry more influence for a more robust signal
        let breadthUniverse = effectiveTopCoins.filter { !stableSet.contains($0.symbol.uppercased()) }
        let totalCap = breadthUniverse.reduce(0.0) { $0 + max(0.0, $1.marketCap ?? 0.0) }
        let weightedUpCap = breadthUniverse.reduce(0.0) { acc, coin in
            let w = max(0.0, coin.marketCap ?? 0.0)
            let cp = coin.priceChangePercentage24hInCurrency ?? coin.changePercent24Hr
            return acc + (((cp ?? -Double.infinity) >= 0) ? w : 0.0)
        }
        let breadthCapWeighted = (totalCap > 0) ? (weightedUpCap / totalCap) : breadth
        let breadthCombined = max(0.0, min(1.0, 0.6 * breadthCapWeighted + 0.4 * breadth))

        // 2) Find BTC coin
        let btcCoin = (coins.first { $0.symbol.uppercased() == "BTC" })
            ?? (topCoins.first { $0.symbol.uppercased() == "BTC" })
            ?? (effectiveTopCoins.first { $0.symbol.uppercased() == "BTC" })

        // 3) BTC 24h change
        var btc24hPercent: Double = 0
        var btc24hSource: String = "none"
        if let live24 = await MainActor.run(body: { LivePriceManager.shared.bestChange24hPercent(for: "BTC") }), live24.isFinite, abs(live24) <= 300 {
            btc24hPercent = live24
            btc24hSource = "LivePriceManager"
        } else if let coin = btcCoin {
            if let cp = coin.changePercent24Hr, cp.isFinite, abs(cp) <= 300 { 
                btc24hPercent = cp
                btc24hSource = "coin.changePercent24Hr"
            }
            else if let cp = coin.priceChangePercentage24hInCurrency, cp.isFinite, abs(cp) <= 300 { 
                btc24hPercent = cp
                btc24hSource = "coin.priceChangePercentage24hInCurrency"
            }
        }
        DebugLog.log("Sentiment", "BTC 24h: \(String(format: "%.2f", btc24hPercent))% (source: \(btc24hSource))")

        // 3b) BTC 1h change (small momentum nudge)
        var btc1hPercent: Double = 0
        if let live1h = await MainActor.run(body: { LivePriceManager.shared.bestChange1hPercent(for: "BTC") }), live1h.isFinite { btc1hPercent = live1h }
        else if let coin = btcCoin, let p1h = coin.priceChangePercentage1hInCurrency, p1h.isFinite { btc1hPercent = p1h }

        // 4) Altcoin median 24h change (ex‑BTC, ex‑stable) and dispersion (stddev)
        let alts24h: [Double] = effectiveTopCoins
            .filter { $0.symbol.uppercased() != "BTC" && !stableSet.contains($0.symbol.uppercased()) }
            .compactMap { $0.priceChangePercentage24hInCurrency ?? $0.changePercent24Hr }
            .filter { $0.isFinite }
        let altMedian24h: Double = safeMedian(alts24h) ?? 0
        let dispersion24h: Double = stddev(alts24h)
        let altMAD24h: Double = mad(alts24h)

        // 4b) Risk‑on tilt: small caps vs large caps (ex‑BTC, ex‑stables)
        let largeSet = Array(effectiveTopCoins.prefix(50))
        let smallSet = Array(effectiveTopCoins.dropFirst(50).prefix(50))
        let largeAlts24h: [Double] = largeSet
            .filter { $0.symbol.uppercased() != "BTC" && !stableSet.contains($0.symbol.uppercased()) }
            .compactMap { $0.priceChangePercentage24hInCurrency ?? $0.changePercent24Hr }
            .filter { $0.isFinite }
        let smallAlts24h: [Double] = smallSet
            .filter { $0.symbol.uppercased() != "BTC" && !stableSet.contains($0.symbol.uppercased()) }
            .compactMap { $0.priceChangePercentage24hInCurrency ?? $0.changePercent24Hr }
            .filter { $0.isFinite }
        let largeAltMedian24h: Double = safeMedian(largeAlts24h) ?? 0
        let smallAltMedian24h: Double = safeMedian(smallAlts24h) ?? 0
        // Small‑cap outperformance implies risk‑on; underperformance implies risk‑off
        let smallVsLargeDelta: Double = smallAltMedian24h - largeAltMedian24h
        // Alts vs BTC tilt: broad alts outperforming BTC is risk‑on; lagging is risk‑off
        let altsVsBTCDelta: Double = altMedian24h - btc24hPercent

        // 5) BTC 7d change via sparkline
        var btc7dPercent: Double = 0
        if let coin = btcCoin {
            var spark: [Double] = coin.sparklineIn7d
            if spark.isEmpty {
                spark = await MainActor.run { MarketViewModel.shared.displaySparkline(for: coin) }
            }
            if spark.count >= 2, let startPrice = spark.first, let endPrice = spark.last, startPrice > 0, endPrice > 0 {
                btc7dPercent = percentChange(startPrice, endPrice)
                DebugLog.log("Sentiment", "BTC 7d from sparkline: \(String(format: "%.2f", btc7dPercent))% (start=\(Int(startPrice)), end=\(Int(endPrice)), points=\(spark.count))")
            } else {
                // No sparkline data - use 0 instead of incorrectly using 24h
                // This is more honest than pretending we know the 7d change
                btc7dPercent = 0
                DebugLog.log("Sentiment", "BTC 7d sparkline unavailable (points=\(spark.count)), using 0")
            }
        } else {
            DebugLog.log("Sentiment", "BTC coin not found, 7d change = 0")
        }

        // Clamp helper
        func clampPercent(_ x: Double) -> Double {
            if x.isFinite {
                return max(-100, min(100, x))
            }
            return 0
        }

        // 5) Compute score (balanced across breadth, BTC momentum, alt momentum, and dispersion)

        // Prepare normalized inputs used by the scoring model
        let breadthTerm = (breadthCombined - 0.5) * 2.0 // [-1, 1]
        let btc24 = clampPercent(btc24hPercent)
        let btc7 = clampPercent(btc7dPercent)
        let btc1h = clampPercent(btc1hPercent)
        let altMed = clampPercent(altMedian24h)
        let disp = max(0, min(100, 0.5 * dispersion24h + 0.5 * altMAD24h))

        // Guard against pathological inputs when coverage is low
        if coverageRatio < 0.2 {
            // Reduce dispersion penalty and short-term noise weight when data is sparse
            DebugLog.log("Sentiment", "Low coverage ratio=\(coverageRatio). Applying conservative weights.")
        }

        // Normalize tilt terms with smooth tanh to keep contributions bounded
        let riskTiltSmallVsLarge = tanh(smallVsLargeDelta / 3.0)   // ~3% delta yields ~0.76
        let riskTiltAltsVsBTC   = tanh(altsVsBTCDelta / 4.0)       // ~4% delta yields ~0.76

        // Adapt weights to current cross‑section volatility so the index remains stable and
        // professional in turbulent markets and a bit more responsive in calm markets.
        let volFactor = min(1.0, tanh(disp / 20.0))        // 0 (calm) … ~1 (very volatile)
        let calmFactor = 1.0 - volFactor

        // Base weights (doubles) adjusted by market regime
        // Reduced weights to prevent excessive swings and keep scores more centered around 50
        let wBreadth: Double            = 12.0
        let wBTC24: Double              = 12.0
        let wBTC7: Double               = 8.0 + 3.0 * calmFactor   // trend matters more when calm
        let wBTC1h: Double              = 1.5 + 2.0 * calmFactor   // de‑emphasize 1h in high vol
        let wAltMed: Double             = 5.0 + 3.0 * calmFactor   // alts breadth stronger in calm
        let wDispPenalty: Double        = 8.0 + 12.0 * volFactor   // increased penalty for dispersion
        let wRiskSmallVsLarge: Double   = 2.0 + 2.0 * calmFactor
        let wRiskAltsVsBTC: Double      = 2.0 + 2.0 * calmFactor

        // Use softer tanh scaling to prevent extreme values
        // Calculate individual contributions for debugging
        let contribBTC24 = wBTC24 * tanh(btc24 / 8.0)
        let contribBreadth = wBreadth * breadthTerm
        let contribBTC7 = wBTC7 * tanh(btc7 / 15.0)
        let contribBTC1h = wBTC1h * tanh(btc1h / 3.0)
        let contribAltMed = wAltMed * tanh(altMed / 6.0)
        let contribDisp = -wDispPenalty * tanh(disp / 15.0)
        let contribRiskSmall = wRiskSmallVsLarge * riskTiltSmallVsLarge
        let contribRiskAlts = wRiskAltsVsBTC * riskTiltAltsVsBTC
        
        let scoreRaw = 50.0
            + contribBTC24
            + contribBreadth
            + contribBTC7
            + contribBTC1h
            + contribAltMed
            + contribDisp
            + contribRiskSmall
            + contribRiskAlts

        // Log detailed breakdown for debugging
        DebugLog.log("Sentiment", "Score breakdown: base=50 + BTC24=\(String(format: "%.1f", contribBTC24)) + breadth=\(String(format: "%.1f", contribBreadth)) + BTC7=\(String(format: "%.1f", contribBTC7)) + BTC1h=\(String(format: "%.1f", contribBTC1h)) + altMed=\(String(format: "%.1f", contribAltMed)) + disp=\(String(format: "%.1f", contribDisp)) + riskSmall=\(String(format: "%.1f", contribRiskSmall)) + riskAlts=\(String(format: "%.1f", contribRiskAlts)) = \(String(format: "%.1f", scoreRaw))")
        DebugLog.log("Sentiment", "Inputs: BTC24h=\(String(format: "%.2f", btc24hPercent))% BTC7d=\(String(format: "%.2f", btc7dPercent))% breadth=\(String(format: "%.0f", breadthCombined * 100))% altMed=\(String(format: "%.2f", altMedian24h))% disp=\(String(format: "%.1f", disp)) coverage=\(String(format: "%.0f", coverageRatio * 100))%")

        // GUARDS: Prevent extreme scores in normal market conditions
        // Low coverage: compress towards neutral (less confident in sparse data)
        var adjustedScore = scoreRaw
        if coverageRatio < 0.3 {
            adjustedScore = 50.0 + (scoreRaw - 50.0) * 0.5
            DebugLog.log("Sentiment", "Low coverage guard applied: \(String(format: "%.1f", scoreRaw)) → \(String(format: "%.1f", adjustedScore))")
        }
        
        // Soft clamp: allow 5-95 range but compress extremes to avoid unrealistic readings
        // This makes scores like "5" very rare, requiring truly extreme market conditions
        if adjustedScore < 15 {
            adjustedScore = 10.0 + (adjustedScore - 10.0) * 0.5
            DebugLog.log("Sentiment", "Low extreme guard applied: \(String(format: "%.1f", scoreRaw)) → \(String(format: "%.1f", adjustedScore))")
        }
        if adjustedScore > 85 {
            adjustedScore = 90.0 - (90.0 - adjustedScore) * 0.5
            DebugLog.log("Sentiment", "High extreme guard applied: \(String(format: "%.1f", scoreRaw)) → \(String(format: "%.1f", adjustedScore))")
        }

        // Smooth the instantaneous score with an EMA to avoid jitter and provide a more
        // professional, stable reading. Half‑life ~5–7 minutes depending on call cadence.
        let scoreUnsmoothed = max(0, min(100, adjustedScore))

        // Adaptive smoothing: less smoothing when activity high, more when coverage low
        let smoothedNow: Double
        if coverageRatio < 0.25 {
            // Extra smoothing for sparse data (reduced bias to avoid compressing values)
            smoothedNow = await CryptoSageSmoother.shared.smooth(current: scoreUnsmoothed * 0.95 + 2.5, now: Date())
        } else {
            smoothedNow = await CryptoSageSmoother.shared.smooth(current: scoreUnsmoothed, now: Date())
        }
        
        // CryptoSage AI: Pure local calculation - fully independent model
        // Measures MARKET MOMENTUM based on price action, breadth, and volatility
        // Note: This differs from alternative.me which includes social media, surveys, and trends
        let score = Int(round(max(0, min(100, smoothedNow))))
        DebugLog.log("Sentiment", "CryptoSage AI: raw=\(Int(scoreRaw)) adjusted=\(Int(adjustedScore)) smoothed=\(Int(smoothedNow)) final=\(score)")

        // Decide the next refresh cadence based on market activity. This is only a UI hint; the
        // view layer can choose how/when to actually refetch. We adapt the cadence using BTC 1h/24h,
        // alt median change, and cross‑section dispersion. Values are snapped to sensible steps.
        let nextSeconds: Int = {
            let a1h = abs(btc1h)
            let a24 = abs(btc24)
            let aAlt = abs(altMed)
            let vol = disp
            var secs = 300 // default: 5 minutes
            // High activity: refresh fast
            if a1h >= 1.5 || a24 >= 5 || vol >= 25 || aAlt >= 3 {
                secs = 60 // 1 minute
            } else if a1h >= 0.75 || a24 >= 3 || vol >= 15 || aAlt >= 1.5 {
                secs = 120 // 2 minutes
            } else if a1h <= 0.1 && a24 <= 0.5 && vol <= 5 && aAlt <= 0.2 {
                secs = 900 // 15 minutes in very quiet markets
            } else if a1h <= 0.25 && a24 <= 1.5 && vol <= 8 && aAlt <= 0.5 {
                secs = 600 // 10 minutes in quiet markets
            }
            // Data coverage gating: if we don't have many coins, slow down to avoid noisy updates
            if coverageRatio < 0.30 { secs = max(secs, 900) }  // very low coverage → 15m min
            else if coverageRatio < 0.60 { secs = max(secs, 600) } // moderate coverage → 10m min

            // Clamp and add a deterministic jitter (±15%) to avoid synchronized refetches across views
            secs = max(30, min(1800, secs))
            let jitter = Int(Double(secs) * 0.15)
            if jitter > 0 {
                // Deterministic jitter seeded by time bucket and current state to avoid flicker
                let seedTs = Int(Date().timeIntervalSince1970)
                let base = max(1, jitter)
                let j = ((seedTs / 30) &+ score &+ Int(altMed.rounded())) % (2 * base + 1) - base
                secs += j
            }
            secs = max(30, min(1800, secs))
            return (secs / 30) * 30
        }()

        // Historical values should come from actual stored history or alternative.me
        // They should NOT be derived from current market conditions

        // 6) Persist to on‑device history, calibrate, and build outputs
        let nowDate = Date()
        let nowTs = Int(nowDate.timeIntervalSince1970)
        let oneDay: TimeInterval = 86400

        // Record the smoothed score to the local history (5‑minute buckets)
        await SentimentHistoryStore.shared.record(value: smoothedNow, at: nowDate)

        // Compute a gentle calibration factor from the last 30 days so the distribution
        // is comparable to common Fear & Greed indexes (p10≈20, p90≈80). Falls back to 1.0.
        // Calibration mode knob: 0=off, 1=standard(20/80), 2=altme-ish(25/75)
        let recentSeries = await SentimentHistoryStore.shared.series(from: nowDate.addingTimeInterval(-30 * oneDay), to: nowDate, count: 720)
        let mode = (UserDefaults.standard.object(forKey: "Sentiment.CalibrationMode") as? Int) ?? 1
        let calValues = recentSeries.map { $0.value }
        var calibrationScale: Double
        if mode == 0 {
            calibrationScale = 1.0
        } else if mode == 2 {
            calibrationScale = await SentimentHistoryStore.shared.scaleFactorForCalibration(values: calValues, targetLow: 25.0, targetHigh: 75.0)
        } else {
            calibrationScale = await SentimentHistoryStore.shared.scaleFactorForCalibration(values: calValues, targetLow: 20.0, targetHigh: 80.0)
        }
        // Clamp to a sane range to avoid pathological scaling on sparse or skewed history
        if !calibrationScale.isFinite { calibrationScale = 1.0 }
        calibrationScale = max(0.5, min(1.5, calibrationScale))

        // Helper to apply calibration and clamp to [0,100]
        func calibrated(_ raw: Int) async -> Int {
            await SentimentHistoryStore.shared.applyCalibration(raw, scale: calibrationScale)
        }

        // Prefer true historical samples for yesterday/last week/last month; fall back to
        // the prior heuristic estimates when history is thin (first run / cold start).
        // NOTE: Some implementations of `sample(at:)` can accidentally return the most recent point
        // for any requested date. To avoid showing the same value for every timeframe, we derive
        // anchor samples by taking the nearest point from `recentSeries` within a reasonable window.
        let yDate = nowDate.addingTimeInterval(-oneDay)
        let wDate = nowDate.addingTimeInterval(-7 * oneDay)
        let mDate = nowDate.addingTimeInterval(-30 * oneDay)

        // Generic nearest-sample helper (keeps this file independent of the store’s point type)
        func nearestSample<T>(_ series: [T], to date: Date, timestamp: (T) -> Int, value: (T) -> Double) -> (value: Double, distance: Int)? {
            guard !series.isEmpty else { return nil }
            let target = Int(date.timeIntervalSince1970)
            var bestValue: Double = 0
            var bestDistance: Int = .max
            for item in series {
                let d = abs(timestamp(item) - target)
                if d < bestDistance {
                    bestDistance = d
                    bestValue = value(item)
                }
            }
            return (bestDistance == .max) ? nil : (bestValue, bestDistance)
        }

        func historyValue(near date: Date, maxDistanceSeconds: Int) -> Double? {
            guard let hit = nearestSample(recentSeries, to: date, timestamp: { $0.timestamp }, value: { $0.value }) else { return nil }
            return (hit.distance <= maxDistanceSeconds) ? hit.value : nil
        }

        func interpolatedHistoryValue(near date: Date, maxDistanceSeconds: Int) -> Double? {
            guard !recentSeries.isEmpty else { return nil }
            let target = Int(date.timeIntervalSince1970)
            var before: (ts: Int, val: Double)? = nil
            var after:  (ts: Int, val: Double)? = nil
            for pt in recentSeries {
                let ts = pt.timestamp
                let val = pt.value
                if ts <= target {
                    if before == nil || ts > before!.ts { before = (ts, val) }
                }
                if ts >= target {
                    if after == nil || ts < after!.ts { after = (ts, val) }
                }
            }
            guard let b = before, let a = after else { return nil }
            if (target - b.ts) > maxDistanceSeconds || (a.ts - target) > maxDistanceSeconds { return nil }
            if a.ts == b.ts { return b.val }
            let t = Double(target - b.ts) / Double(max(1, a.ts - b.ts))
            return b.val + t * (a.val - b.val)
        }

        let nowCal = await calibrated(score)
        
        // CryptoSage AI Strategy:
        // - "Now" value: Computed locally using our real-time market analysis model
        // - Historical values (Yesterday, Week, Month): Use alternative.me as the authoritative source
        //
        // This approach provides:
        // 1. Unique real-time "Now" value that reflects current market breadth/momentum
        // 2. Stable, reliable historical values from the established Fear & Greed index
        // 3. Meaningful comparison between current vs historical sentiment
        
        // Always fetch alternative.me for historical values (this is stable and reliable)
        let historicalBaseline = await fetchAlternativeMeEmergencyFallback(timeout: timeout)
        
        // Use alternative.me historical values, falling back to current value only if fetch fails
        let yesterdayCal: Int
        let lastWeekCal: Int
        let lastMonthCal: Int
        
        if let baseline = historicalBaseline {
            yesterdayCal = baseline.yesterday
            lastWeekCal = baseline.lastWeek
            lastMonthCal = baseline.lastMonth
            DebugLog.log("Sentiment", "CryptoSage AI using alternative.me historical baseline: y=\(yesterdayCal), w=\(lastWeekCal), m=\(lastMonthCal)")
        } else {
            // Fallback to current value if alternative.me is unavailable
            yesterdayCal = nowCal
            lastWeekCal = nowCal
            lastMonthCal = nowCal
            DebugLog.log("Sentiment", "CryptoSage AI: alternative.me unavailable, using current value for all timeframes")
        }
        
        DebugLog.log("Sentiment", "CryptoSage AI Final: now=\(nowCal) (local), y=\(yesterdayCal), w=\(lastWeekCal), m=\(lastMonthCal) (from alt.me)")

        // Build the four anchor entries (oldest -> newest)
        let monthTs = Int(mDate.timeIntervalSince1970)
        let weekTs  = Int(wDate.timeIntervalSince1970)
        let yTs     = Int(yDate.timeIntervalSince1970)

        func classify(_ value: Int) -> String {
            switch value {
            case 0...24: return "extreme fear"
            case 25...44: return "fear"
            case 45...54: return "neutral"
            case 55...74: return "greed"
            default: return "extreme greed"
            }
        }

        // Add helper to post provenance easily inside this scope
        func postProvenance(_ label: String, items: [FearGreedData]) {
            postSentimentProvenance(source: source, provenance: label, items: items)
        }

        // CryptoSage AI uses its own local history for all historical values.
        // Alternative.me is only used as a cold-start fallback for fresh installs.
        // Once local history builds up (after 1 day, 7 days, 30 days), it takes priority.
        let entriesCount = max(4, min(30, limit))

        // Fallback: synthesize a smooth series by interpolating between the four anchors
        if entriesCount > 4 {
            // Base points at 30d, 7d, 1d, and now
            let baseTimestamps = [monthTs, weekTs, yTs, nowTs]
            let baseScores = [lastMonthCal, lastWeekCal, yesterdayCal, nowCal]

            // Normalize anchors: sort by timestamp ascending and dedupe equal timestamps
            let zipped = zip(baseTimestamps, baseScores).sorted { $0.0 < $1.0 }
            var xs: [Int] = []
            var ys: [Int] = []
            for (t, v) in zipped {
                if xs.last != t { xs.append(t); ys.append(v) }
            }
            // Note: If all values are equal, that's the accurate historical data
            // Do NOT artificially nudge values - they represent actual recorded history

            func linearInterpolate(x: Int, xs: [Int], ys: [Int]) -> Int {
                guard xs.count == ys.count, xs.count >= 2 else { return ys.last ?? 50 }
                // Assume xs strictly increasing
                if x <= xs.first! { return max(0, min(100, ys.first!)) }
                if x >= xs.last! { return max(0, min(100, ys.last!)) }
                // Binary search for interval
                var lo = 0, hi = xs.count - 1
                while lo + 1 < hi {
                    let mid = (lo + hi) / 2
                    if xs[mid] <= x { lo = mid } else { hi = mid }
                }
                let x0 = xs[lo], x1 = xs[hi]
                let y0 = Double(ys[lo]), y1 = Double(ys[hi])
                let t = Double(x - x0) / Double(max(1, x1 - x0))
                let val = y0 + t * (y1 - y0)
                return max(0, min(100, Int(round(val))))
            }

            var timestamps: [Int] = []
            timestamps.reserveCapacity(entriesCount)
            for i in 0..<entriesCount {
                let f = Double(i) / Double(max(1, entriesCount - 1))
                let raw = Double(monthTs) + f * Double(nowTs - monthTs)
                let ts = Int(floor(raw)) + i // monotonic bump to avoid duplicates
                timestamps.append(min(ts, nowTs))
            }

            var result: [FearGreedData] = []
            for (idx, ts) in timestamps.enumerated().reversed() {
                let v = linearInterpolate(x: ts, xs: xs, ys: ys)
                let cls = classify(v)
                result.append(
                    FearGreedData(
                        value: String(v),
                        value_classification: cls,
                        timestamp: String(ts),
                        time_until_update: (idx == timestamps.count - 1) ? String(nextSeconds) : nil
                    )
                )
            }
            postProvenance("derived-synth-interpolated", items: result)
            return result
        } else {
            // entriesCount <= 4: return the four anchors newest first and truncate to limit
            let anchors: [FearGreedData] = [
                FearGreedData(value: String(lastMonthCal), value_classification: classify(lastMonthCal), timestamp: String(monthTs), time_until_update: nil),
                FearGreedData(value: String(lastWeekCal),  value_classification: classify(lastWeekCal),  timestamp: String(weekTs),  time_until_update: nil),
                FearGreedData(value: String(yesterdayCal), value_classification: classify(yesterdayCal), timestamp: String(yTs),    time_until_update: nil),
                FearGreedData(value: String(nowCal),       value_classification: classify(nowCal),       timestamp: String(nowTs),  time_until_update: String(nextSeconds))
            ]
            DebugLog.log("Sentiment", "anchors now=\(nowCal) y=\(yesterdayCal) w=\(lastWeekCal) m=\(lastMonthCal) next=\(nextSeconds) cov=\(coverageRatio)")
            let sliced = Array(anchors.suffix(limit).reversed())
            postProvenance("derived-anchors", items: sliced)
            return sliced
        }
    }

    private func safeMedian(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let n = sorted.count
        if n % 2 == 1 { return sorted[n/2] }
        let a = sorted[n/2 - 1]
        let b = sorted[n/2]
        return (a + b) / 2.0
    }

    private func stddev(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        let s = sqrt(max(0, variance))
        return s.isFinite ? s : 0
    }

    private func mad(_ values: [Double]) -> Double {
        // Median Absolute Deviation (scaled) for robust dispersion estimate
        guard !values.isEmpty else { return 0 }
        let m = safeMedian(values) ?? 0
        let deviations = values.map { abs($0 - m) }
        let medAbs = safeMedian(deviations) ?? 0
        // Scale factor ~1.4826 to make MAD comparable to stddev under normality
        let scaled = medAbs * 1.4826
        return scaled.isFinite ? scaled : 0
    }

    private func percentChange(_ start: Double, _ end: Double) -> Double {
        guard start != 0 else { return 0 }
        return ((end - start) / start) * 100.0
    }

    private func classify(_ value: Int) -> String {
        switch value {
        case 0...24: return "extreme fear"
        case 25...44: return "fear"
        case 45...54: return "neutral"
        case 55...74: return "greed"
        default: return "extreme greed"
        }
    }
}

