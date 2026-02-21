//
//  CurrencyManager.swift
//  CryptoSage
//
//  Global currency state management for multi-currency display support.
//

import Foundation
import Combine
import SwiftUI

/// Supported display currencies with their metadata
public enum DisplayCurrency: String, CaseIterable, Codable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case cad = "CAD"
    case aud = "AUD"
    case chf = "CHF"
    case cny = "CNY"
    case inr = "INR"
    case krw = "KRW"
    case brl = "BRL"
    case mxn = "MXN"
    
    /// Human-readable name
    var displayName: String {
        switch self {
        case .usd: return "US Dollar"
        case .eur: return "Euro"
        case .gbp: return "British Pound"
        case .jpy: return "Japanese Yen"
        case .cad: return "Canadian Dollar"
        case .aud: return "Australian Dollar"
        case .chf: return "Swiss Franc"
        case .cny: return "Chinese Yuan"
        case .inr: return "Indian Rupee"
        case .krw: return "South Korean Won"
        case .brl: return "Brazilian Real"
        case .mxn: return "Mexican Peso"
        }
    }
    
    /// Currency symbol for display
    var symbol: String {
        switch self {
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .jpy: return "¥"
        case .cad: return "C$"
        case .aud: return "A$"
        case .chf: return "CHF "
        case .cny: return "¥"
        case .inr: return "₹"
        case .krw: return "₩"
        case .brl: return "R$"
        case .mxn: return "MX$"
        }
    }
    
    /// Flag emoji for visual identification
    var flag: String {
        switch self {
        case .usd: return "🇺🇸"
        case .eur: return "🇪🇺"
        case .gbp: return "🇬🇧"
        case .jpy: return "🇯🇵"
        case .cad: return "🇨🇦"
        case .aud: return "🇦🇺"
        case .chf: return "🇨🇭"
        case .cny: return "🇨🇳"
        case .inr: return "🇮🇳"
        case .krw: return "🇰🇷"
        case .brl: return "🇧🇷"
        case .mxn: return "🇲🇽"
        }
    }
    
    /// CoinGecko API parameter value
    var apiValue: String {
        rawValue.lowercased()
    }
    
    /// Whether this currency typically uses decimal places for small amounts
    var usesDecimals: Bool {
        switch self {
        case .jpy, .krw:
            return false
        default:
            return true
        }
    }
    
    /// Locale identifier for proper number formatting
    var localeIdentifier: String {
        switch self {
        case .usd: return "en_US"
        case .eur: return "de_DE"
        case .gbp: return "en_GB"
        case .jpy: return "ja_JP"
        case .cad: return "en_CA"
        case .aud: return "en_AU"
        case .chf: return "de_CH"
        case .cny: return "zh_CN"
        case .inr: return "en_IN"
        case .krw: return "ko_KR"
        case .brl: return "pt_BR"
        case .mxn: return "es_MX"
        }
    }
}

/// Singleton manager for currency state and exchange rate caching
@MainActor
public final class CurrencyManager: ObservableObject {
    public static let shared = CurrencyManager()
    
    // MARK: - Published Properties
    
    /// Currently selected display currency
    @Published public private(set) var currency: DisplayCurrency = .usd
    
    /// Cached exchange rates (base USD -> other currencies)
    @Published public private(set) var exchangeRates: [DisplayCurrency: Double] = [.usd: 1.0]
    
    /// Last successful rate fetch timestamp
    @Published public private(set) var lastRateFetch: Date?
    
    /// Whether rates are currently being fetched
    @Published public private(set) var isFetchingRates: Bool = false
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let ratesCacheKey = "CachedExchangeRates"
    private let ratesTimestampKey = "ExchangeRatesTimestamp"
    private let rateFetchInterval: TimeInterval = 15 * 60 // 15 minutes
    
    // MARK: - Initialization
    
    private init() {
        loadCachedRates()
        observeCurrencySetting()
        
        // Fetch rates on launch if stale
        Task {
            await refreshRatesIfNeeded()
        }
    }
    
    // MARK: - Public Methods
    
    /// Update the selected currency (called from settings)
    public func setCurrency(_ newCurrency: DisplayCurrency) {
        guard newCurrency != currency else { return }
        currency = newCurrency
        UserDefaults.standard.set(newCurrency.rawValue, forKey: "selectedCurrency")
        
        // Notify observers
        NotificationCenter.default.post(name: .currencyDidChange, object: newCurrency)
    }
    
    /// Get the current currency symbol
    public var currentSymbol: String {
        currency.symbol
    }
    
    /// Get the current currency API value for CoinGecko
    public var currentAPIValue: String {
        currency.apiValue
    }
    
    /// Static nonisolated accessor for API value (safe to use from any context)
    /// Reads directly from UserDefaults to avoid MainActor requirement
    public nonisolated static var apiValue: String {
        let stored = UserDefaults.standard.string(forKey: "selectedCurrency") ?? "USD"
        return (DisplayCurrency(rawValue: stored) ?? .usd).apiValue
    }
    
    /// Static nonisolated accessor for currency symbol (safe to use from any context)
    public nonisolated static var symbol: String {
        let stored = UserDefaults.standard.string(forKey: "selectedCurrency") ?? "USD"
        return (DisplayCurrency(rawValue: stored) ?? .usd).symbol
    }
    
    /// Static nonisolated accessor for checking if currency uses decimals
    public nonisolated static var usesDecimals: Bool {
        let stored = UserDefaults.standard.string(forKey: "selectedCurrency") ?? "USD"
        return (DisplayCurrency(rawValue: stored) ?? .usd).usesDecimals
    }
    
    /// Static nonisolated accessor for the ISO 4217 currency code (e.g., "USD", "EUR")
    public nonisolated static var currencyCode: String {
        UserDefaults.standard.string(forKey: "selectedCurrency") ?? "USD"
    }
    
    /// Static nonisolated conversion from USD (uses cached rate from UserDefaults)
    public nonisolated static func convertFromUSD(_ usdValue: Double) -> Double {
        let stored = UserDefaults.standard.string(forKey: "selectedCurrency") ?? "USD"
        let currency = DisplayCurrency(rawValue: stored) ?? .usd
        
        // Get cached rate
        if let ratesData = UserDefaults.standard.data(forKey: "CachedExchangeRates"),
           let rates = try? JSONDecoder().decode([String: Double].self, from: ratesData),
           let rate = rates[currency.rawValue] {
            return usdValue * rate
        }
        return usdValue
    }
    
    /// Convert a USD value to the current currency
    public func convert(_ usdValue: Double) -> Double {
        guard let rate = exchangeRates[currency] else { return usdValue }
        return usdValue * rate
    }
    
    /// Convert a value from one currency to another
    public func convert(_ value: Double, from: DisplayCurrency, to: DisplayCurrency) -> Double {
        guard let fromRate = exchangeRates[from],
              let toRate = exchangeRates[to],
              fromRate > 0 else {
            return value
        }
        // Convert to USD first, then to target
        let usdValue = value / fromRate
        return usdValue * toRate
    }
    
    /// Format a price in the current currency
    public func formatPrice(_ value: Double, compact: Bool = false) -> String {
        let converted = convert(value)
        
        if compact {
            return formatCompactPrice(converted)
        }
        
        return formatFullPrice(converted)
    }
    
    /// Force refresh exchange rates
    public func refreshRates() async {
        await fetchExchangeRates()
    }
    
    /// Refresh rates if they're stale (older than 15 minutes)
    public func refreshRatesIfNeeded() async {
        guard !isFetchingRates else { return }
        
        if let lastFetch = lastRateFetch {
            let elapsed = Date().timeIntervalSince(lastFetch)
            if elapsed < rateFetchInterval {
                return // Rates are fresh
            }
        }
        
        await fetchExchangeRates()
    }
    
    // MARK: - Private Methods
    
    private func observeCurrencySetting() {
        // Watch for changes from UserDefaults (e.g., from SettingsView)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFromUserDefaults()
            }
            .store(in: &cancellables)
        
        // Initial sync
        syncFromUserDefaults()
    }
    
    private func syncFromUserDefaults() {
        let stored = UserDefaults.standard.string(forKey: "selectedCurrency") ?? "USD"
        if let newCurrency = DisplayCurrency(rawValue: stored), newCurrency != currency {
            currency = newCurrency
        }
    }
    
    private func loadCachedRates() {
        if let data = UserDefaults.standard.data(forKey: ratesCacheKey),
           let rates = try? JSONDecoder().decode([String: Double].self, from: data) {
            var converted: [DisplayCurrency: Double] = [:]
            for (key, value) in rates {
                if let currency = DisplayCurrency(rawValue: key.uppercased()) {
                    converted[currency] = value
                }
            }
            if !converted.isEmpty {
                exchangeRates = converted
            }
        }
        
        if let timestamp = UserDefaults.standard.object(forKey: ratesTimestampKey) as? Date {
            lastRateFetch = timestamp
        }
    }
    
    private func cacheRates() {
        var stringKeyed: [String: Double] = [:]
        for (currency, rate) in exchangeRates {
            stringKeyed[currency.rawValue] = rate
        }
        
        if let data = try? JSONEncoder().encode(stringKeyed) {
            UserDefaults.standard.set(data, forKey: ratesCacheKey)
        }
        UserDefaults.standard.set(Date(), forKey: ratesTimestampKey)
    }
    
    private func fetchExchangeRates() async {
        guard !isFetchingRates else { return }
        isFetchingRates = true
        defer { isFetchingRates = false }
        
        // Use CoinGecko's exchange_rates endpoint (with Demo API key for higher rate limits)
        guard let url = URL(string: "https://api.coingecko.com/api/v3/exchange_rates") else {
            return
        }
        
        do {
            let req = APIConfig.coinGeckoRequest(url: url)
            let (data, response) = try await URLSession.shared.data(for: req)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }
            
            let decoded = try JSONDecoder().decode(ExchangeRatesResponse.self, from: data)
            
            // CoinGecko returns rates relative to BTC, we need to convert to USD base
            guard let btcUsdRate = decoded.rates["usd"]?.value, btcUsdRate > 0 else {
                return
            }
            
            var newRates: [DisplayCurrency: Double] = [.usd: 1.0]
            
            for currency in DisplayCurrency.allCases {
                if currency == .usd { continue }
                if let rateInfo = decoded.rates[currency.apiValue],
                   rateInfo.value > 0 {
                    // Convert from BTC-base to USD-base
                    newRates[currency] = rateInfo.value / btcUsdRate
                }
            }
            
            exchangeRates = newRates
            lastRateFetch = Date()
            cacheRates()
            
        } catch {
            print("[CurrencyManager] Failed to fetch exchange rates: \(error)")
        }
    }
    
    // MARK: - Formatting Helpers
    
    private func formatFullPrice(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "\(currency.symbol)0" }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: currency.localeIdentifier)
        
        if currency.usesDecimals {
            if value < 1.0 {
                formatter.minimumFractionDigits = 2
                formatter.maximumFractionDigits = 8
            } else {
                formatter.minimumFractionDigits = 2
                formatter.maximumFractionDigits = 2
            }
        } else {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        }
        
        let num = formatter.string(from: NSNumber(value: value)) ?? "0"
        return currency.symbol + num
    }
    
    private func formatCompactPrice(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "\(currency.symbol)0" }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        
        if value >= 1_000_000_000 {
            let short = value / 1_000_000_000
            formatter.maximumFractionDigits = short >= 10 ? 0 : 1
            return currency.symbol + (formatter.string(from: NSNumber(value: short)) ?? "0") + "B"
        } else if value >= 1_000_000 {
            let short = value / 1_000_000
            formatter.maximumFractionDigits = short >= 10 ? 0 : 1
            return currency.symbol + (formatter.string(from: NSNumber(value: short)) ?? "0") + "M"
        } else if value >= 1_000 {
            let short = value / 1_000
            formatter.maximumFractionDigits = short >= 10 ? 0 : 1
            return currency.symbol + (formatter.string(from: NSNumber(value: short)) ?? "0") + "K"
        } else {
            formatter.maximumFractionDigits = currency.usesDecimals ? 2 : 0
            return currency.symbol + (formatter.string(from: NSNumber(value: value)) ?? "0")
        }
    }
}

// MARK: - Response Models

private struct ExchangeRatesResponse: Decodable {
    let rates: [String: RateInfo]
    
    struct RateInfo: Decodable {
        let name: String
        let unit: String
        let value: Double
        let type: String
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    static let currencyDidChange = Notification.Name("CurrencyDidChange")
}

// MARK: - Environment Key

private struct CurrencyManagerKey: EnvironmentKey {
    static var defaultValue: CurrencyManager {
        MainActor.assumeIsolated { CurrencyManager.shared }
    }
}

public extension EnvironmentValues {
    var currencyManager: CurrencyManager {
        get { self[CurrencyManagerKey.self] }
        set { self[CurrencyManagerKey.self] = newValue }
    }
}
