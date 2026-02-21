//
//  LocaleManager.swift
//  CryptoSage
//
//  Manages the user's selected language and provides locale-aware
//  formatting for dates and numbers throughout the app.
//

import Foundation
import Combine

/// Singleton that maps the user's language preference to a Locale
/// and provides formatters that respect that choice.
@MainActor
public final class LocaleManager: ObservableObject {
    public static let shared = LocaleManager()
    
    /// The currently active display locale based on the user's language setting
    @Published public private(set) var displayLocale: Locale
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let stored = UserDefaults.standard.string(forKey: "language") ?? "English"
        displayLocale = Self.locale(for: stored)
        observeLanguageSetting()
    }
    
    // MARK: - Language → Locale Mapping
    
    /// Maps a language display name (e.g., "Spanish") to a locale identifier (e.g., "es")
    nonisolated private static let languageToLocale: [String: String] = [
        "English":    "en_US",
        "Spanish":    "es_ES",
        "French":     "fr_FR",
        "German":     "de_DE",
        "Italian":    "it_IT",
        "Portuguese": "pt_BR",
        "Japanese":   "ja_JP",
        "Korean":     "ko_KR",
        "Chinese":    "zh_Hans_CN",
        "Russian":    "ru_RU",
        "Arabic":     "ar_SA",
        "Hindi":      "hi_IN",
        "Turkish":    "tr_TR",
        "Dutch":      "nl_NL",
        "Polish":     "pl_PL",
        "Vietnamese": "vi_VN",
        "Thai":       "th_TH",
        "Indonesian": "id_ID"
    ]
    
    /// Returns the Locale for a given language name
    nonisolated static func locale(for languageName: String) -> Locale {
        let identifier = languageToLocale[languageName] ?? "en_US"
        return Locale(identifier: identifier)
    }
    
    /// Static nonisolated accessor — safe to call from any thread.
    /// Returns the display Locale based on the saved language preference.
    public nonisolated static var current: Locale {
        let stored = UserDefaults.standard.string(forKey: "language") ?? "English"
        return locale(for: stored)
    }
    
    /// Static nonisolated accessor for the locale identifier string
    public nonisolated static var localeIdentifier: String {
        current.identifier
    }
    
    // MARK: - Observation
    
    private func observeLanguageSetting() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFromUserDefaults()
            }
            .store(in: &cancellables)
    }
    
    private func syncFromUserDefaults() {
        let stored = UserDefaults.standard.string(forKey: "language") ?? "English"
        let newLocale = Self.locale(for: stored)
        if newLocale.identifier != displayLocale.identifier {
            displayLocale = newLocale
            // Notify that formatters should refresh
            NotificationCenter.default.post(name: .languageDidChange, object: newLocale)
            // Rebuild date and number formatters with new locale
            ChartDateFormatters.rebuildFormatters()
            MarketFormat.rebuildFormatters()
        }
    }
}

// MARK: - Notification

public extension Notification.Name {
    static let languageDidChange = Notification.Name("LanguageDidChange")
}
