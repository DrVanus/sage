import Foundation

struct TVStudiesMapper {
    
    // MARK: - Public API
    
    /// Builds an array of TradingView study descriptors based on current AppStorage-backed indicator selections and parameters.
    /// Reads from UserDefaults.standard using current `Chart.Indicators.*` keys, with legacy fallbacks (e.g., `SMA.Period`).
    /// Returns each element either as a plain study id string (e.g. "Volume@tv-basicstudies")
    /// or a JSON descriptor string (e.g. {"id":"Moving Average@tv-basicstudies","inputs":{"length":20}}), without surrounding quotes.
    static func buildCurrentStudies() -> [String] {
        let defaults = UserDefaults.standard
        
        // Get selected indicators from the comma-separated string
        let selectedRaw = defaults.string(forKey: "TV.Indicators.Selected") ?? ""
        var selectedSet = parseSelectedSet(raw: selectedRaw)
        
        // Legacy fallback if selected set is empty
        if selectedSet.isEmpty {
            if defaults.bool(forKey: "Chart.ShowVolume") {
                selectedSet.insert("volume")
            }
            if defaults.bool(forKey: "Chart.Indicators.SMA.Enabled") {
                selectedSet.insert("sma")
            }
            if defaults.bool(forKey: "Chart.Indicators.EMA.Enabled") {
                selectedSet.insert("ema")
            }
        }
        
        // Build studies in deterministic order:
        // Volume, SMA, EMA, BB, RSI, MACD, Stoch, VWAP, Ichimoku, ATR, OBV, MFI
        var result: [String] = []
        
        // Volume
        if selectedSet.contains("volume") {
            result.append("Volume@tv-basicstudies")
        }
        
        // SMA - TradingView internal ID: MASimple@tv-basicstudies
        if selectedSet.contains("sma") {
            let lengthRaw = intForKeys(defaults, ["Chart.Indicators.SMA.Period", "SMA.Period"], fallback: 20)
            let length = clampedLength(from: lengthRaw, defaultValue: 20)
            let desc = studyDescriptor(
                id: "MASimple@tv-basicstudies",
                inputs: ["Length": length]  // Capital L - TradingView's expected input name
            )
            result.append(desc)
        }
        
        // EMA - TradingView internal ID: MAExp@tv-basicstudies
        if selectedSet.contains("ema") {
            let lengthRaw = intForKeys(defaults, ["Chart.Indicators.EMA.Period", "EMA.Period"], fallback: 20)
            let length = clampedLength(from: lengthRaw, defaultValue: 20)
            let desc = studyDescriptor(
                id: "MAExp@tv-basicstudies",
                inputs: ["Length": length]  // Capital L - TradingView's expected input name
            )
            result.append(desc)
        }
        
        // BB (Bollinger Bands) - TradingView internal ID: BB@tv-basicstudies
        if selectedSet.contains("bb") {
            let lengthRaw = intForKeys(defaults, ["Chart.Indicators.BB.Period", "BB.Period"], fallback: 20)
            let length = clampedLength(from: lengthRaw, defaultValue: 20)
            let stdVal = doubleForKeys(defaults, ["Chart.Indicators.BB.Dev", "BB.Dev"], fallback: 2.0)
            // Clamp to UI-supported range 0.5 ... 4.0 and round to 0.1
            let std = max(0.5, min(4.0, (stdVal > 0 ? stdVal : 2.0)))
            let stdRounded = (std * 10).rounded() / 10.0
            let desc = studyDescriptor(
                id: "BB@tv-basicstudies",
                inputs: ["Length": length, "StdDev": stdRounded]  // TradingView's expected input names
            )
            result.append(desc)
        }
        
        // RSI - TradingView internal ID: RSI@tv-basicstudies
        if selectedSet.contains("rsi") {
            let lengthRaw = intForKeys(defaults, ["Chart.Indicators.RSI.Period", "RSI.Period"], fallback: 14)
            let length = clampedLength(from: lengthRaw, defaultValue: 14)
            let desc = studyDescriptor(
                id: "RSI@tv-basicstudies",
                inputs: ["RSI Length": length]  // TradingView's expected input name
            )
            result.append(desc)
        }
        
        // MACD - TradingView internal ID: MACD@tv-basicstudies
        if selectedSet.contains("macd") {
            let fastLength = clampedLength(from: intForKeys(defaults, ["Chart.Indicators.MACD.Fast", "MACD.Fast"], fallback: 12), defaultValue: 12)
            var slowLength = clampedLength(from: intForKeys(defaults, ["Chart.Indicators.MACD.Slow", "MACD.Slow"], fallback: 26), defaultValue: 26)
            let signalLength = clampedLength(from: intForKeys(defaults, ["Chart.Indicators.MACD.Signal", "MACD.Signal"], fallback: 9), defaultValue: 9)
            // Ensure slow > fast for MACD to avoid invalid configs
            if slowLength <= fastLength { slowLength = min(1000, fastLength + 1) }
            let desc = studyDescriptor(
                id: "MACD@tv-basicstudies",
                inputs: [
                    "Fast Length": fastLength,
                    "Slow Length": slowLength,
                    "Signal Smoothing": signalLength
                ]
            )
            result.append(desc)
        }
        
        // Stoch (Stochastic) - TradingView internal ID: Stochastic@tv-basicstudies
        if selectedSet.contains("stoch") {
            let kPeriod = clampedLength(from: intForKeys(defaults, ["Chart.Indicators.Stoch.K", "Stoch.K"], fallback: 14), defaultValue: 14)
            let dPeriod = clampedLength(from: intForKeys(defaults, ["Chart.Indicators.Stoch.D", "Stoch.D"], fallback: 3), defaultValue: 3)
            let smoothK = clampedLength(from: intForKeys(defaults, ["Chart.Indicators.Stoch.Smooth", "Stoch.Smooth"], fallback: 3), defaultValue: 3)
            let desc = studyDescriptor(
                id: "Stochastic@tv-basicstudies",
                inputs: [
                    "%K Length": kPeriod,
                    "%K Smoothing": smoothK,
                    "%D Smoothing": dPeriod
                ]
            )
            result.append(desc)
        }
        
        // VWAP - TradingView internal ID: VWAP@tv-basicstudies
        if selectedSet.contains("vwap") {
            // VWAP typically doesn't need custom inputs for the basic version
            result.append("VWAP@tv-basicstudies")
        }
        
        // Ichimoku - TradingView internal ID: IchimokuCloud@tv-basicstudies
        if selectedSet.contains("ichimoku") {
            result.append("IchimokuCloud@tv-basicstudies")
        }
        
        // ATR - TradingView internal ID: ATR@tv-basicstudies
        if selectedSet.contains("atr") {
            let lengthRaw = intForKeys(defaults, ["Chart.Indicators.ATR.Period", "ATR.Period"], fallback: 14)
            let length = clampedLength(from: lengthRaw, defaultValue: 14)
            let desc = studyDescriptor(
                id: "ATR@tv-basicstudies",
                inputs: ["Length": length]
            )
            result.append(desc)
        }
        
        // OBV - TradingView internal ID: OBV@tv-basicstudies
        if selectedSet.contains("obv") {
            result.append("OBV@tv-basicstudies")
        }
        
        // MFI - TradingView internal ID: MFI@tv-basicstudies
        if selectedSet.contains("mfi") {
            let lengthRaw = intForKeys(defaults, ["Chart.Indicators.MFI.Period", "MFI.Period"], fallback: 14)
            let length = clampedLength(from: lengthRaw, defaultValue: 14)
            let desc = studyDescriptor(
                id: "MFI@tv-basicstudies",
                inputs: ["MFI Length": length]
            )
            result.append(desc)
        }
        
        return result
    }
    
    // MARK: - Private Helpers
    
    /// Reads the first present integer value for the given keys (in order). Falls back to `fallback` if none exist.
    private static func intForKeys(_ defaults: UserDefaults, _ keys: [String], fallback: Int) -> Int {
        for k in keys {
            if defaults.object(forKey: k) != nil { return defaults.integer(forKey: k) }
        }
        return fallback
    }

    /// Reads the first present double value for the given keys (in order). Falls back to `fallback` if none exist.
    private static func doubleForKeys(_ defaults: UserDefaults, _ keys: [String], fallback: Double) -> Double {
        for k in keys {
            if defaults.object(forKey: k) != nil { return defaults.double(forKey: k) }
        }
        return fallback
    }

    /// Reads the first present bool value for the given keys (in order). Falls back to `fallback` if none exist.
    private static func boolForKeys(_ defaults: UserDefaults, _ keys: [String], fallback: Bool) -> Bool {
        for k in keys {
            if defaults.object(forKey: k) != nil { return defaults.bool(forKey: k) }
        }
        return fallback
    }
    
    // MARK: - Constants
    /// Supported indicator short keys that map to TradingView studies.
    private static let allowedKeys: Set<String> = [
        "volume", "sma", "ema", "bb", "rsi", "macd", "stoch", "vwap", "ichimoku", "atr", "obv", "mfi"
    ]

    /// Returns true for transient version-bump tokens like "v1700000000" that are used only to trigger refreshes.
    private static func isTransientVersionToken(_ token: String) -> Bool {
        guard token.first == "v" else { return false }
        return token.dropFirst().allSatisfy { $0 >= "0" && $0 <= "9" }
    }
    
    /// Parses a comma-separated string of selected indicator short keys into a Set<String>.
    /// - Behavior:
    ///   - Trims whitespace and lowercases each token.
    ///   - Ignores transient version-bump tokens like `v1700000000`.
    ///   - Filters to a whitelist of supported keys to avoid stray/legacy tokens causing issues.
    private static func parseSelectedSet(raw: String) -> Set<String> {
        let parts = raw.split(separator: ",")
        var result = Set<String>()
        for part in parts {
            let token = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !token.isEmpty else { continue }
            if isTransientVersionToken(token) { continue }
            if allowedKeys.contains(token) { result.insert(token) }
        }
        return result
    }
    
    /// Clamps an integer length parameter to sensible minimum and maximum values. Minimum 1, max 1000.
    /// If the input is zero or negative, returns the default value.
    private static func clampedLength(from input: Int, defaultValue: Int) -> Int {
        guard input >= 1 else { return defaultValue }
        return min(input, 1000)
    }
    
    /// Safely encodes a dictionary [String: Any] into a JSON string without surrounding quotes.
    /// Returns "{}" if encoding fails.
    /// IMPORTANT: Uses .sortedKeys to ensure deterministic output - prevents infinite reload loops
    /// when comparing studies arrays, as unsorted JSON can produce different key orders each call.
    private static func studyDescriptor(id: String, inputs: [String: Any]) -> String {
        var dict: [String: Any] = ["id": id]
        if !inputs.isEmpty {
            dict["inputs"] = inputs
        }
        // CRITICAL: Use .sortedKeys to ensure consistent JSON output across calls
        // Without this, {"id":"...", "inputs":{...}} could sometimes become {"inputs":{...}, "id":"..."}
        // which causes the TradingView widget to think studies changed and trigger infinite reloads
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }
}

