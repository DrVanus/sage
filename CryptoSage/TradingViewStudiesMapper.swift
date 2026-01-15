import Foundation

struct TVStudiesMapper {
    
    // MARK: - Public API
    
    /// Builds an array of TradingView study descriptors based on current AppStorage-backed indicator selections and parameters.
    /// Reads from UserDefaults.standard using predefined keys.
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
        
        // SMA
        if selectedSet.contains("sma") {
            let length = clampedLength(from: defaults.integer(forKey: "SMA.Period"), defaultValue: 20)
            let desc = studyDescriptor(
                id: "Moving Average@tv-basicstudies",
                inputs: ["length": length]
            )
            result.append(desc)
        }
        
        // EMA
        if selectedSet.contains("ema") {
            let length = clampedLength(from: defaults.integer(forKey: "EMA.Period"), defaultValue: 20)
            let desc = studyDescriptor(
                id: "Exponential Moving Average@tv-basicstudies",
                inputs: ["length": length]
            )
            result.append(desc)
        }
        
        // BB (Bollinger Bands)
        if selectedSet.contains("bb") {
            let length = clampedLength(from: defaults.integer(forKey: "BB.Period"), defaultValue: 20)
            let stdRaw = defaults.double(forKey: "BB.Dev")
            let std = (stdRaw > 0) ? round(stdRaw * 10) / 10.0 : 2.0
            let desc = studyDescriptor(
                id: "Bollinger Bands@tv-basicstudies",
                inputs: ["length": length, "std": std]
            )
            result.append(desc)
        }
        
        // RSI
        if selectedSet.contains("rsi") {
            let length = clampedLength(from: defaults.integer(forKey: "RSI.Period"), defaultValue: 14)
            let desc = studyDescriptor(
                id: "Relative Strength Index@tv-basicstudies",
                inputs: ["length": length]
            )
            result.append(desc)
        }
        
        // MACD
        if selectedSet.contains("macd") {
            let fastLength = clampedLength(from: defaults.integer(forKey: "MACD.Fast"), defaultValue: 12)
            let slowLength = clampedLength(from: defaults.integer(forKey: "MACD.Slow"), defaultValue: 26)
            let signalLength = clampedLength(from: defaults.integer(forKey: "MACD.Signal"), defaultValue: 9)
            let desc = studyDescriptor(
                id: "MACD@tv-basicstudies",
                inputs: [
                    "fastLength": fastLength,
                    "slowLength": slowLength,
                    "signalLength": signalLength
                ]
            )
            result.append(desc)
        }
        
        // Stoch (Stochastic)
        if selectedSet.contains("stoch") {
            let kPeriod = clampedLength(from: defaults.integer(forKey: "Stoch.K"), defaultValue: 14)
            let dPeriod = clampedLength(from: defaults.integer(forKey: "Stoch.D"), defaultValue: 3)
            let smoothK = clampedLength(from: defaults.integer(forKey: "Stoch.Smooth"), defaultValue: 3)
            let desc = studyDescriptor(
                id: "Stochastic@tv-basicstudies",
                inputs: [
                    "kPeriod": kPeriod,
                    "dPeriod": dPeriod,
                    "smoothK": smoothK
                ]
            )
            result.append(desc)
        }
        
        // VWAP
        if selectedSet.contains("vwap") {
            let session = defaults.bool(forKey: "VWAP.Session")
            let desc = studyDescriptor(
                id: "Volume Weighted Average Price@tv-basicstudies",
                inputs: ["session": session]
            )
            result.append(desc)
        }
        
        // Ichimoku
        if selectedSet.contains("ichimoku") {
            // No parameters documented in instructions, add as plain id
            result.append("Ichimoku Cloud@tv-basicstudies")
        }
        
        // ATR
        if selectedSet.contains("atr") {
            let length = clampedLength(from: defaults.integer(forKey: "ATR.Period"), defaultValue: 14)
            let desc = studyDescriptor(
                id: "Average True Range@tv-basicstudies",
                inputs: ["length": length]
            )
            result.append(desc)
        }
        
        // OBV
        if selectedSet.contains("obv") {
            // No parameters, plain id
            result.append("On Balance Volume@tv-basicstudies")
        }
        
        // MFI
        if selectedSet.contains("mfi") {
            let length = clampedLength(from: defaults.integer(forKey: "MFI.Period"), defaultValue: 14)
            let desc = studyDescriptor(
                id: "Money Flow Index@tv-basicstudies",
                inputs: ["length": length]
            )
            result.append(desc)
        }
        
        return result
    }
    
    // MARK: - Private Helpers
    
    /// Parses a comma-separated string of selected indicator short keys into a Set<String>, trimming whitespace and lowercasing.
    private static func parseSelectedSet(raw: String) -> Set<String> {
        let items = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return Set(items.filter { !$0.isEmpty })
    }
    
    /// Clamps an integer length parameter to sensible minimum and maximum values. Minimum 1, max 1000.
    /// If the input is zero or negative, returns the default value.
    private static func clampedLength(from input: Int, defaultValue: Int) -> Int {
        guard input >= 1 else { return defaultValue }
        return min(input, 1000)
    }
    
    /// Safely encodes a dictionary [String: Any] into a JSON string without surrounding quotes.
    /// Returns "{}" if encoding fails.
    private static func studyDescriptor(id: String, inputs: [String: Any]) -> String {
        var dict: [String: Any] = ["id": id]
        if !inputs.isEmpty {
            dict["inputs"] = inputs
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }
}
