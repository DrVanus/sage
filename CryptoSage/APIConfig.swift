//
//  APIConfig.swift
//  CryptoSage
//
//  Created by DM on 3/24/25.
//
//  IMPORTANT: Do not commit this file with your actual API key to your public repository.
//  API keys are now stored securely in Keychain.
//

import Foundation

/// Centralized API configuration and shared URLSession with secure key management.
final class APIConfig {
    /// Singleton instance for shared use.
    static let shared = APIConfig()
    
    // MARK: - Keychain Service Identifiers
    private static let keychainService = "CryptoSage.APIKeys"
    private static let openAIKeyAccount = "openai_api_key"
    private static let deepseekKeyAccount = "deepseek_api_key"
    private static let grokKeyAccount = "grok_api_key"
    private static let openrouterKeyAccount = "openrouter_api_key"
    private static let newsAPIKeyAccount = "newsapi_key"
    private static let debankKeyAccount = "debank_api_key"
    private static let zapperKeyAccount = "zapper_api_key"
    private static let alchemyKeyAccount = "alchemy_api_key"
    private static let heliusKeyAccount = "helius_api_key"
    private static let finnhubKeyAccount = "finnhub_api_key"
    private static let tavilyKeyAccount = "tavily_api_key"

    /// Shared URLSession for all network calls.
    let session: URLSession
    
    // MARK: - OpenAI API Key
    
    // Known invalid keys that should be ignored (e.g., expired or revoked)
    // Add suffixes of keys that have been rejected by OpenAI to prevent repeated failed calls
    private static let invalidKeyPatterns = ["Ea4A", "U0EA"] // Old revoked key suffixes
    
    /// OpenAI API key - reads from Keychain only.
    /// SECURITY: API keys should be stored in Firebase Cloud Functions, not in the client app.
    /// Firebase is the primary method - this is only a fallback when Firebase is unavailable.
    static var openAIKey: String {
        get {
            // Try Keychain (skip known invalid keys)
            if let key = try? KeychainHelper.shared.read(
                service: keychainService,
                account: openAIKeyAccount
            ), !key.isEmpty {
                // Skip if it matches a known invalid key pattern
                let isInvalid = invalidKeyPatterns.contains { key.hasSuffix($0) }
                if !isInvalid {
                    return key
                }
            }
            // No valid local key - Firebase should be used for AI features
            return ""
        }
    }
    
    /// Check if a valid OpenAI API key is configured locally
    /// Note: With Firebase backend, this may be false but AI features still work
    static var hasValidOpenAIKey: Bool {
        let key = openAIKey
        return !key.isEmpty && key != "keygoeshere" && key.hasPrefix("sk-")
    }
    
    /// Check if AI features are available (via Firebase OR local key)
    @MainActor
    static var hasAICapability: Bool {
        // Firebase backend is the preferred method
        if FirebaseService.shared.useFirebaseForAI {
            return true
        }
        // Fallback to local API key
        return hasValidOpenAIKey
    }
    
    /// Save OpenAI API key to Keychain
    /// - Parameter key: The API key to save
    /// - Throws: KeychainError if save fails
    static func setOpenAIKey(_ key: String) throws {
        try KeychainHelper.shared.save(
            key,
            service: keychainService,
            account: openAIKeyAccount
        )
    }
    
    /// Remove OpenAI API key from Keychain
    static func removeOpenAIKey() {
        try? KeychainHelper.shared.delete(
            service: keychainService,
            account: openAIKeyAccount
        )
    }
    
    // MARK: - DeepSeek API Key (Best for Crypto Predictions - Alpha Arena Winner)
    
    /// DeepSeek API key - reads from Keychain only.
    /// DeepSeek V3.2 achieved +116.53% return in Alpha Arena crypto trading benchmark.
    /// Used by Firebase backend for all shared predictions (primary) and client-side fallback.
    static var deepseekKey: String {
        get {
            if let key = try? KeychainHelper.shared.read(
                service: keychainService,
                account: deepseekKeyAccount
            ), !key.isEmpty {
                return key
            }
            return ""
        }
    }
    
    /// Check if a valid DeepSeek API key is configured
    static var hasValidDeepseekKey: Bool {
        let key = deepseekKey
        return !key.isEmpty && key.hasPrefix("sk-") && key.count >= 30
    }
    
    /// Save DeepSeek API key to Keychain
    static func setDeepseekKey(_ key: String) throws {
        try KeychainHelper.shared.save(
            key,
            service: keychainService,
            account: deepseekKeyAccount
        )
    }
    
    /// Remove DeepSeek API key from Keychain
    static func removeDeepseekKey() {
        try? KeychainHelper.shared.delete(
            service: keychainService,
            account: deepseekKeyAccount
        )
    }
    
    // MARK: - Grok API Key (xAI)
    
    /// Grok API key - reads from Keychain only.
    static var grokKey: String {
        get {
            if let key = try? KeychainHelper.shared.read(
                service: keychainService,
                account: grokKeyAccount
            ), !key.isEmpty {
                return key
            }
            return ""
        }
    }
    
    /// Check if a valid Grok API key is configured
    static var hasValidGrokKey: Bool {
        let key = grokKey
        return !key.isEmpty && key.hasPrefix("xai-") && key.count >= 30
    }
    
    /// Save Grok API key to Keychain
    static func setGrokKey(_ key: String) throws {
        try KeychainHelper.shared.save(
            key,
            service: keychainService,
            account: grokKeyAccount
        )
    }
    
    /// Remove Grok API key from Keychain
    static func removeGrokKey() {
        try? KeychainHelper.shared.delete(
            service: keychainService,
            account: grokKeyAccount
        )
    }
    
    // MARK: - OpenRouter API Key (Multi-Model Gateway)
    
    /// OpenRouter API key - reads from Keychain only.
    /// Provides access to 500+ models through a unified API.
    static var openrouterKey: String {
        get {
            if let key = try? KeychainHelper.shared.read(
                service: keychainService,
                account: openrouterKeyAccount
            ), !key.isEmpty {
                return key
            }
            return ""
        }
    }
    
    /// Check if a valid OpenRouter API key is configured
    static var hasValidOpenRouterKey: Bool {
        let key = openrouterKey
        return !key.isEmpty && key.hasPrefix("sk-or-") && key.count >= 40
    }
    
    /// Save OpenRouter API key to Keychain
    static func setOpenRouterKey(_ key: String) throws {
        try KeychainHelper.shared.save(
            key,
            service: keychainService,
            account: openrouterKeyAccount
        )
    }
    
    /// Remove OpenRouter API key from Keychain
    static func removeOpenRouterKey() {
        try? KeychainHelper.shared.delete(
            service: keychainService,
            account: openrouterKeyAccount
        )
    }
    
    // MARK: - NewsAPI Key
    
    /// NewsAPI.org key - reads from Keychain only.
    /// SECURITY: API keys should not be hardcoded.
    static var newsAPIKey: String {
        get {
            if let key = try? KeychainHelper.shared.read(
                service: keychainService,
                account: newsAPIKeyAccount
            ), !key.isEmpty {
                return key
            }
            // No hardcoded key - user must configure in Settings
            return ""
        }
    }
    
    /// Check if NewsAPI key is configured
    static var hasValidNewsAPIKey: Bool {
        let key = newsAPIKey
        return !key.isEmpty && key.count >= 20
    }
    
    /// Save NewsAPI key to Keychain
    static func setNewsAPIKey(_ key: String) throws {
        try KeychainHelper.shared.save(
            key,
            service: keychainService,
            account: newsAPIKeyAccount
        )
    }
    
    // MARK: - DeBank API Key (DeFi Aggregator)
    
    /// DeBank API key - reads from Keychain
    static var debankAPIKey: String {
        get {
            if let key = try? KeychainHelper.shared.read(
                service: keychainService,
                account: debankKeyAccount
            ), !key.isEmpty {
                return key
            }
            return ""
        }
    }
    
    /// Check if DeBank API key is configured
    static var hasValidDebankKey: Bool {
        let key = debankAPIKey
        return !key.isEmpty && key.count >= 20
    }
    
    /// Save DeBank API key to Keychain
    static func setDebankAPIKey(_ key: String) throws {
        try KeychainHelper.shared.save(
            key,
            service: keychainService,
            account: debankKeyAccount
        )
        // DeFiAggregatorService reads from Keychain directly when needed
    }
    
    /// Remove DeBank API key from Keychain
    static func removeDebankAPIKey() {
        try? KeychainHelper.shared.delete(
            service: keychainService,
            account: debankKeyAccount
        )
    }
    
    // MARK: - Zapper API Key (Alternative Aggregator)
    
    /// Zapper API key - reads from Keychain
    static var zapperAPIKey: String {
        get {
            if let key = try? KeychainHelper.shared.read(
                service: keychainService,
                account: zapperKeyAccount
            ), !key.isEmpty {
                return key
            }
            return ""
        }
    }
    
    /// Check if Zapper API key is configured
    static var hasValidZapperKey: Bool {
        let key = zapperAPIKey
        return !key.isEmpty && key.count >= 20
    }
    
    /// Save Zapper API key to Keychain
    static func setZapperAPIKey(_ key: String) throws {
        try KeychainHelper.shared.save(
            key,
            service: keychainService,
            account: zapperKeyAccount
        )
        // DeFiAggregatorService reads from Keychain directly when needed
    }
    
    /// Remove Zapper API key from Keychain
    static func removeZapperAPIKey() {
        try? KeychainHelper.shared.delete(
            service: keychainService,
            account: zapperKeyAccount
        )
    }
    
    // MARK: - Alchemy API Key (NFT & RPC)
    
    /// Alchemy API key - reads from Keychain
    static var alchemyAPIKey: String {
        get {
            if let key = try? KeychainHelper.shared.read(
                service: keychainService,
                account: alchemyKeyAccount
            ), !key.isEmpty {
                return key
            }
            return ""
        }
    }
    
    /// Check if Alchemy API key is configured
    static var hasValidAlchemyKey: Bool {
        let key = alchemyAPIKey
        return !key.isEmpty && key.count >= 20
    }
    
    /// Save Alchemy API key to Keychain
    static func setAlchemyAPIKey(_ key: String) throws {
        try KeychainHelper.shared.save(
            key,
            service: keychainService,
            account: alchemyKeyAccount
        )
        ChainRegistry.shared.setAPIKey(key, for: ChainAPIService.alchemy.rawValue)
    }
    
    /// Remove Alchemy API key from Keychain
    static func removeAlchemyAPIKey() {
        try? KeychainHelper.shared.delete(
            service: keychainService,
            account: alchemyKeyAccount
        )
    }
    
    // MARK: - Helius API Key (Solana)
    
    /// Helius API key - reads from Keychain
    static var heliusAPIKey: String {
        get {
            if let key = try? KeychainHelper.shared.read(
                service: keychainService,
                account: heliusKeyAccount
            ), !key.isEmpty {
                return key
            }
            return ""
        }
    }
    
    /// Check if Helius API key is configured
    static var hasValidHeliusKey: Bool {
        let key = heliusAPIKey
        return !key.isEmpty && key.count >= 20
    }
    
    /// Save Helius API key to Keychain
    static func setHeliusAPIKey(_ key: String) throws {
        try KeychainHelper.shared.save(
            key,
            service: keychainService,
            account: heliusKeyAccount
        )
        ChainRegistry.shared.setAPIKey(key, for: ChainAPIService.helius.rawValue)
    }
    
    /// Remove Helius API key from Keychain
    static func removeHeliusAPIKey() {
        try? KeychainHelper.shared.delete(
            service: keychainService,
            account: heliusKeyAccount
        )
    }
    
    // MARK: - Finnhub API Key (Stock Market Data)
    
    /// Finnhub API key - reads from Keychain
    static var finnhubAPIKey: String {
        get {
            if let key = try? KeychainHelper.shared.read(
                service: keychainService,
                account: finnhubKeyAccount
            ), !key.isEmpty {
                return key
            }
            return ""
        }
    }
    
    /// Check if Finnhub API key is configured
    static var hasValidFinnhubKey: Bool {
        let key = finnhubAPIKey
        return !key.isEmpty && key.count >= 10
    }
    
    /// Save Finnhub API key to Keychain
    static func setFinnhubAPIKey(_ key: String) throws {
        try KeychainHelper.shared.save(
            key,
            service: keychainService,
            account: finnhubKeyAccount
        )
    }
    
    /// Remove Finnhub API key from Keychain
    static func removeFinnhubAPIKey() {
        try? KeychainHelper.shared.delete(
            service: keychainService,
            account: finnhubKeyAccount
        )
    }
    
    // MARK: - Tavily API Key (Web Search for AI)
    
    /// Tavily API key - reads from Keychain
    /// Tavily provides web search optimized for AI/LLM applications
    static var tavilyKey: String {
        get {
            if let key = try? KeychainHelper.shared.read(
                service: keychainService,
                account: tavilyKeyAccount
            ), !key.isEmpty {
                return key
            }
            return ""
        }
    }
    
    /// Check if Tavily API key is configured
    static var hasValidTavilyKey: Bool {
        let key = tavilyKey
        return !key.isEmpty && key.hasPrefix("tvly-") && key.count >= 20
    }
    
    /// Save Tavily API key to Keychain
    static func setTavilyAPIKey(_ key: String) throws {
        try KeychainHelper.shared.save(
            key,
            service: keychainService,
            account: tavilyKeyAccount
        )
    }
    
    /// Remove Tavily API key from Keychain
    static func removeTavilyAPIKey() {
        try? KeychainHelper.shared.delete(
            service: keychainService,
            account: tavilyKeyAccount
        )
    }

    // MARK: - CoinGecko Demo API Key
    
    /// CoinGecko Demo API key for higher rate limits (30 calls/min vs 10 calls/min).
    /// This is used as a fallback when direct API calls are needed (Firestore pipeline is primary).
    /// The same key is used on the Firebase server side.
    ///
    /// SECURITY: Key is split and reversed at rest to prevent trivial extraction from the binary
    /// via `strings` or disassembly. This is a free-tier demo key (read-only, no billing),
    /// but obfuscation is best practice for any credential shipped in a binary.
    static let coingeckoDemoAPIKey: String = {
        // Split into non-obvious fragments and reassembled at runtime
        let a = String("p98Z".reversed())   // "Z89p"
        let b = String("1rAT".reversed())   // "TAr1"
        let c = String("9szc".reversed())   // "czs9"
        let d = String("J6Sw".reversed())   // "wS6J"
        let e = String("1CQM".reversed())   // "MQC1"
        let f = String("Co5d".reversed())   // "d5oC"
        let pre = ["C", "G", "-"].joined()  // "CG-"
        return pre + f + e + d + c + b + a
    }()
    
    /// Create a URLRequest for CoinGecko API calls with the Demo API key header.
    /// Use this instead of creating bare URLRequests for CoinGecko endpoints.
    static func coinGeckoRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(coingeckoDemoAPIKey, forHTTPHeaderField: "x-cg-demo-api-key")
        return request
    }
    
    // MARK: - Base URLs
    
    /// Base URLs for cryptocurrency data.
    static let coingeckoBaseURL = "https://api.coingecko.com/api/v3"
    static let coinpaprikaBaseURL = "https://api.coinpaprika.com/api/v1"
    static let coinbaseBaseURL = "https://api.coinbase.com/api/v2"
    
    /// Base URL for NewsAPI.org top headlines.
    static let newsBaseURL = "https://newsapi.org/v2"
    
    /// Base URL for OpenAI API
    static let openAIBaseURL = "https://api.openai.com/v1"
    
    /// Base URL for DeepSeek API (Best for crypto predictions)
    static let deepseekBaseURL = "https://api.deepseek.com/v1"
    
    /// Base URL for Grok API (xAI)
    static let grokBaseURL = "https://api.x.ai/v1"
    
    /// Base URL for OpenRouter API (Multi-model gateway)
    static let openrouterBaseURL = "https://openrouter.ai/api/v1"
    
    /// Base URL for DeBank Pro API (DeFi aggregation)
    static let debankBaseURL = "https://pro-openapi.debank.com/v1"
    
    /// Base URL for Zapper API (alternative DeFi aggregation)
    static let zapperBaseURL = "https://api.zapper.xyz/v2"
    
    /// Base URL for Blur API (NFT floor prices)
    static let blurBaseURL = "https://api.blur.io/v1"
    
    /// Base URL for Finnhub API (Stock market data)
    static let finnhubBaseURL = "https://finnhub.io/api/v1"
    
    /// Base URL for Tavily API (Web search for AI)
    static let tavilyBaseURL = "https://api.tavily.com"

    // MARK: - Initialization
    
    private init() {
        session = URLSession(configuration: .default)
    }
}

// MARK: - API Key Settings View Support

extension APIConfig {
    /// Mask an API key for display (shows first 7 and last 4 characters)
    static func maskAPIKey(_ key: String) -> String {
        guard key.count > 15 else { return String(repeating: "*", count: key.count) }
        let prefix = String(key.prefix(7))
        let suffix = String(key.suffix(4))
        let masked = String(repeating: "*", count: min(key.count - 11, 20))
        return "\(prefix)\(masked)\(suffix)"
    }
    
    /// Validate OpenAI API key format
    static func isValidOpenAIKeyFormat(_ key: String) -> Bool {
        // OpenAI keys start with "sk-" and are typically 51 characters
        return key.hasPrefix("sk-") && key.count >= 40
    }
    
    /// Validate DeBank API key format
    static func isValidDebankKeyFormat(_ key: String) -> Bool {
        // DeBank keys are typically 32+ alphanumeric characters
        return key.count >= 20 && key.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil
    }
    
    /// Validate Zapper API key format
    static func isValidZapperKeyFormat(_ key: String) -> Bool {
        // Zapper keys are typically long alphanumeric strings
        return key.count >= 20
    }
    
    /// Validate Alchemy API key format
    static func isValidAlchemyKeyFormat(_ key: String) -> Bool {
        // Alchemy keys are typically 32 alphanumeric characters
        return key.count >= 20 && key.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "-_"))) == nil
    }
    
    /// Validate Helius API key format
    static func isValidHeliusKeyFormat(_ key: String) -> Bool {
        // Helius keys are typically 36 characters (UUID format)
        return key.count >= 20
    }
    
    /// Validate Finnhub API key format
    static func isValidFinnhubKeyFormat(_ key: String) -> Bool {
        // Finnhub keys are alphanumeric strings, typically 20+ characters
        return key.count >= 10 && key.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil
    }
    
    /// Validate Tavily API key format
    static func isValidTavilyKeyFormat(_ key: String) -> Bool {
        // Tavily keys start with "tvly-" and are typically 30+ characters
        return key.hasPrefix("tvly-") && key.count >= 20
    }
    
    /// Get summary of configured API keys
    static var configuredAPIsummary: [String: Bool] {
        return [
            "OpenAI": hasValidOpenAIKey,
            "DeepSeek": hasValidDeepseekKey,
            "Grok": hasValidGrokKey,
            "OpenRouter": hasValidOpenRouterKey,
            "DeBank": hasValidDebankKey,
            "Zapper": hasValidZapperKey,
            "Alchemy": hasValidAlchemyKey,
            "Helius": hasValidHeliusKey,
            "Finnhub": hasValidFinnhubKey,
            "Tavily": hasValidTavilyKey
        ]
    }
    
    /// Get summary of configured AI providers
    static var configuredAIProviders: [String: Bool] {
        return [
            "OpenAI": hasValidOpenAIKey,
            "DeepSeek": hasValidDeepseekKey,
            "Grok": hasValidGrokKey,
            "OpenRouter": hasValidOpenRouterKey
        ]
    }
    
    /// Check if any AI provider is configured
    static var hasAnyAIProvider: Bool {
        return hasValidOpenAIKey || hasValidDeepseekKey || hasValidGrokKey || hasValidOpenRouterKey
    }
    
    /// Check if prediction-optimized AI is available (DeepSeek recommended)
    static var hasPredictionOptimizedAI: Bool {
        return hasValidDeepseekKey
    }
    
    /// Check if DeFi features are fully enabled
    static var hasDeFiCapability: Bool {
        return hasValidDebankKey || hasValidZapperKey
    }
    
    /// Check if NFT features are fully enabled
    static var hasNFTCapability: Bool {
        return hasValidAlchemyKey || hasValidHeliusKey
    }
    
    /// Check if stock market features are enabled
    /// Always returns true since Yahoo Finance (primary source) requires no API key
    /// Finnhub is optional and provides enhanced index constituent data when configured
    static var hasStockMarketCapability: Bool {
        return true  // Yahoo Finance works without API key
    }
    
    /// Check if enhanced stock index data is available (via Finnhub)
    static var hasEnhancedStockIndexData: Bool {
        return hasValidFinnhubKey
    }
    
    /// Check if AI web search is enabled (via Tavily)
    static var hasWebSearchCapability: Bool {
        return hasValidTavilyKey
    }
}
