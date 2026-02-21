//
//  AIProviderService.swift
//  CryptoSage
//
//  Multi-provider AI service abstraction layer.
//  Supports OpenAI, DeepSeek, Grok, and other OpenAI-compatible providers.
//  Based on Alpha Arena benchmark results: DeepSeek leads for crypto predictions (+116% return).
//

import Foundation
import Combine

// MARK: - AI Provider Enum

/// Supported AI providers with their configurations
/// Performance notes from Alpha Arena crypto trading benchmark (real money, Hyperliquid DEX):
/// - DeepSeek V3.2: +116.53% return (BEST for crypto) - superior risk management & diversification
/// - Qwen3 Max: +71.40% return - strong quantitative reasoning
/// - Claude Sonnet 4: +15.68% return - conservative but accurate
/// - Grok 4: +5.07% return - real-time data advantage
/// - GPT-5: -62.02% return (WORST for crypto) - excessive leverage, poor adaptation
public enum AIProvider: String, CaseIterable, Codable {
    case openai = "openai"
    case deepseek = "deepseek"
    case grok = "grok"
    case openrouter = "openrouter"
    
    // MARK: - Display Properties
    
    public var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .grok: return "Grok (xAI)"
        case .openrouter: return "OpenRouter"
        }
    }
    
    public var description: String {
        switch self {
        case .openai: return "Powers CryptoSage AI chat experience"
        case .deepseek: return "Powers CryptoSage AI predictions (Alpha Arena winner)"
        case .grok: return "Real-time data, strong reasoning"
        case .openrouter: return "Access 500+ models via unified API"
        }
    }
    
    public var icon: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .deepseek: return "chart.line.uptrend.xyaxis"
        case .grok: return "bolt.fill"
        case .openrouter: return "arrow.triangle.branch"
        }
    }
    
    /// Crypto prediction performance rating (based on Alpha Arena results)
    public var cryptoPredictionRating: String {
        switch self {
        case .deepseek: return "Excellent"
        case .grok: return "Good"
        case .openai: return "Fair"
        case .openrouter: return "Varies by model"
        }
    }
    
    // MARK: - API Configuration
    
    public var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .deepseek: return "https://api.deepseek.com/v1/chat/completions"
        case .grok: return "https://api.x.ai/v1/chat/completions"
        case .openrouter: return "https://openrouter.ai/api/v1/chat/completions"
        }
    }
    
    public var keyPrefix: String {
        switch self {
        case .openai: return "sk-"
        case .deepseek: return "sk-"
        case .grok: return "xai-"
        case .openrouter: return "sk-or-"
        }
    }
    
    public var keychainAccount: String {
        switch self {
        case .openai: return "openai_api_key"
        case .deepseek: return "deepseek_api_key"
        case .grok: return "grok_api_key"
        case .openrouter: return "openrouter_api_key"
        }
    }
    
    /// Minimum key length for validation
    public var minKeyLength: Int {
        switch self {
        case .openai: return 40
        case .deepseek: return 30
        case .grok: return 30
        case .openrouter: return 40
        }
    }
    
    /// Get API key URL for this provider
    public var apiKeyURL: String {
        switch self {
        case .openai: return "https://platform.openai.com/api-keys"
        case .deepseek: return "https://platform.deepseek.com/api_keys"
        case .grok: return "https://console.x.ai"
        case .openrouter: return "https://openrouter.ai/keys"
        }
    }
    
    // MARK: - Pricing (per million tokens, USD)
    
    public var inputPricePerMillion: Double {
        switch self {
        case .openai: return 2.50  // GPT-4o
        case .deepseek: return 0.15  // DeepSeek V3.2 (93% cheaper than GPT-4o)
        case .grok: return 3.00  // Grok 4
        case .openrouter: return 0.0  // Varies by model
        }
    }
    
    public var outputPricePerMillion: Double {
        switch self {
        case .openai: return 10.00  // GPT-4o
        case .deepseek: return 0.75  // DeepSeek V3.2 (92% cheaper than GPT-4o)
        case .grok: return 15.00  // Grok 4
        case .openrouter: return 0.0  // Varies by model
        }
    }
}

// MARK: - AI Model Configuration

/// Model configurations for each provider
public struct AIModelConfig: Codable, Identifiable, Equatable {
    public let id: String
    public let provider: AIProvider
    public let modelId: String
    public let displayName: String
    public let description: String
    public let tier: ModelTier
    public let contextWindow: Int
    public let supportsTools: Bool
    public let supportsStreaming: Bool
    
    public enum ModelTier: String, Codable {
        case standard = "Standard"
        case premium = "Premium"
        case experimental = "Experimental"
    }
    
    public init(
        provider: AIProvider,
        modelId: String,
        displayName: String,
        description: String,
        tier: ModelTier = .standard,
        contextWindow: Int = 128000,
        supportsTools: Bool = true,
        supportsStreaming: Bool = true
    ) {
        self.id = "\(provider.rawValue):\(modelId)"
        self.provider = provider
        self.modelId = modelId
        self.displayName = displayName
        self.description = description
        self.tier = tier
        self.contextWindow = contextWindow
        self.supportsTools = supportsTools
        self.supportsStreaming = supportsStreaming
    }
}

// MARK: - Predefined Model Configurations

public extension AIModelConfig {
    // MARK: - OpenAI Models
    static let gpt4oMini = AIModelConfig(
        provider: .openai,
        modelId: "gpt-4o-mini",
        displayName: "GPT-4o Mini",
        description: "Fast & affordable, great for most tasks",
        tier: .standard,
        contextWindow: 128000
    )
    
    static let gpt4o = AIModelConfig(
        provider: .openai,
        modelId: "gpt-4o",
        displayName: "GPT-4o",
        description: "Most capable OpenAI model",
        tier: .premium,
        contextWindow: 128000
    )
    
    // MARK: - DeepSeek Models (Best for Crypto - Alpha Arena Winner)
    static let deepseekChat = AIModelConfig(
        provider: .deepseek,
        modelId: "deepseek-chat",
        displayName: "DeepSeek V3.2",
        description: "Best for crypto predictions (+116% Alpha Arena)",
        tier: .standard,
        contextWindow: 128000
    )
    
    static let deepseekReasoner = AIModelConfig(
        provider: .deepseek,
        modelId: "deepseek-reasoner",
        displayName: "DeepSeek R1",
        description: "Advanced reasoning for long-term predictions (7D/30D)",
        tier: .premium,
        contextWindow: 128000
    )
    
    // MARK: - Grok Models
    static let grok4 = AIModelConfig(
        provider: .grok,
        modelId: "grok-4",
        displayName: "Grok 4",
        description: "Real-time data, strong reasoning",
        tier: .premium,
        contextWindow: 256000
    )
    
    static let grok4Fast = AIModelConfig(
        provider: .grok,
        modelId: "grok-4.1-fast",
        displayName: "Grok 4.1 Fast",
        description: "Fast responses, 2M context",
        tier: .standard,
        contextWindow: 2000000
    )
    
    // MARK: - OpenRouter Models (Access to multiple providers)
    static let openrouterDeepseek = AIModelConfig(
        provider: .openrouter,
        modelId: "deepseek/deepseek-chat",
        displayName: "DeepSeek (via OpenRouter)",
        description: "Access DeepSeek through OpenRouter",
        tier: .standard,
        contextWindow: 128000
    )
    
    static let openrouterClaude = AIModelConfig(
        provider: .openrouter,
        modelId: "anthropic/claude-sonnet-4",
        displayName: "Claude Sonnet 4 (via OpenRouter)",
        description: "Anthropic's Claude via OpenRouter",
        tier: .premium,
        contextWindow: 200000
    )
    
    // MARK: - All Available Models
    static let allModels: [AIModelConfig] = [
        // OpenAI
        .gpt4oMini, .gpt4o,
        // DeepSeek (recommended for predictions)
        .deepseekChat, .deepseekReasoner,
        // Grok
        .grok4, .grok4Fast,
        // OpenRouter
        .openrouterDeepseek, .openrouterClaude
    ]
    
    /// Models by provider
    static func models(for provider: AIProvider) -> [AIModelConfig] {
        allModels.filter { $0.provider == provider }
    }
    
    /// Recommended model for crypto predictions (based on Alpha Arena results)
    static var recommendedForPredictions: AIModelConfig {
        return .deepseekChat
    }
    
    /// Recommended model for general chat
    static var recommendedForChat: AIModelConfig {
        return .gpt4oMini
    }
}

// MARK: - AI Provider Manager

/// Manages AI provider configuration and API key storage
@MainActor
public final class AIProviderManager: ObservableObject {
    public static let shared = AIProviderManager()
    
    // MARK: - Published Properties
    
    /// Provider used for general chat
    @Published public var chatProvider: AIProvider {
        didSet { saveSetting("chatProvider", value: chatProvider.rawValue) }
    }
    
    /// Provider used for price predictions (DeepSeek recommended)
    @Published public var predictionProvider: AIProvider {
        didSet { saveSetting("predictionProvider", value: predictionProvider.rawValue) }
    }
    
    /// Selected model for chat
    @Published public var chatModel: AIModelConfig {
        didSet { saveSetting("chatModelId", value: chatModel.id) }
    }
    
    /// Selected model for predictions
    @Published public var predictionModel: AIModelConfig {
        didSet { saveSetting("predictionModelId", value: predictionModel.id) }
    }
    
    /// Whether to use different models for predictions vs chat
    @Published public var useSeparatePredictionModel: Bool {
        didSet { saveSetting("useSeparatePredictionModel", value: useSeparatePredictionModel) }
    }
    
    // MARK: - Keychain
    
    private let keychainService = "CryptoSage.APIKeys"
    
    // MARK: - Initialization
    
    private init() {
        // Load saved preferences or use defaults
        let savedChatProvider = UserDefaults.standard.string(forKey: "AIProviderManager.chatProvider") ?? AIProvider.openai.rawValue
        let savedPredictionProvider = UserDefaults.standard.string(forKey: "AIProviderManager.predictionProvider") ?? AIProvider.deepseek.rawValue
        
        self.chatProvider = AIProvider(rawValue: savedChatProvider) ?? .openai
        self.predictionProvider = AIProvider(rawValue: savedPredictionProvider) ?? .deepseek
        
        // Load saved models or use defaults
        let savedChatModelId = UserDefaults.standard.string(forKey: "AIProviderManager.chatModelId") ?? AIModelConfig.gpt4oMini.id
        let savedPredictionModelId = UserDefaults.standard.string(forKey: "AIProviderManager.predictionModelId") ?? AIModelConfig.deepseekChat.id
        
        self.chatModel = AIModelConfig.allModels.first { $0.id == savedChatModelId } ?? .gpt4oMini
        self.predictionModel = AIModelConfig.allModels.first { $0.id == savedPredictionModelId } ?? .deepseekChat
        
        self.useSeparatePredictionModel = UserDefaults.standard.bool(forKey: "AIProviderManager.useSeparatePredictionModel")
    }
    
    // MARK: - Settings Persistence
    
    private func saveSetting(_ key: String, value: Any) {
        UserDefaults.standard.set(value, forKey: "AIProviderManager.\(key)")
    }
    
    // MARK: - API Key Management
    
    /// Get API key for a provider from Keychain
    public func getAPIKey(for provider: AIProvider) -> String {
        // Special case: OpenAI key uses existing location for backward compatibility
        if provider == .openai {
            return APIConfig.openAIKey
        }
        
        if let key = try? KeychainHelper.shared.read(
            service: keychainService,
            account: provider.keychainAccount
        ), !key.isEmpty {
            return key
        }
        return ""
    }
    
    /// Save API key for a provider to Keychain
    public func setAPIKey(_ key: String, for provider: AIProvider) throws {
        // Special case: OpenAI key uses existing location for backward compatibility
        if provider == .openai {
            try APIConfig.setOpenAIKey(key)
            return
        }
        
        try KeychainHelper.shared.save(
            key,
            service: keychainService,
            account: provider.keychainAccount
        )
    }
    
    /// Remove API key for a provider
    public func removeAPIKey(for provider: AIProvider) {
        if provider == .openai {
            APIConfig.removeOpenAIKey()
            return
        }
        
        try? KeychainHelper.shared.delete(
            service: keychainService,
            account: provider.keychainAccount
        )
    }
    
    /// Check if a valid API key exists for a provider
    public func hasValidKey(for provider: AIProvider) -> Bool {
        let key = getAPIKey(for: provider)
        guard !key.isEmpty else { return false }
        
        // Validate key format
        if !key.isEmpty && key.count >= provider.minKeyLength {
            // Check prefix if applicable
            if !provider.keyPrefix.isEmpty {
                return key.hasPrefix(provider.keyPrefix)
            }
            return true
        }
        return false
    }
    
    /// Validate API key format for a provider
    public func isValidKeyFormat(_ key: String, for provider: AIProvider) -> Bool {
        guard key.count >= provider.minKeyLength else { return false }
        if !provider.keyPrefix.isEmpty {
            return key.hasPrefix(provider.keyPrefix)
        }
        return true
    }
    
    /// Mask API key for display
    public func maskAPIKey(_ key: String) -> String {
        guard key.count > 15 else { return String(repeating: "*", count: key.count) }
        let prefix = String(key.prefix(7))
        let suffix = String(key.suffix(4))
        let masked = String(repeating: "*", count: min(key.count - 11, 20))
        return "\(prefix)\(masked)\(suffix)"
    }
    
    // MARK: - Provider Selection
    
    /// Get the appropriate model for a specific use case
    public func model(for useCase: AIUseCase) -> AIModelConfig {
        switch useCase {
        case .chat:
            return chatModel
        case .prediction:
            return useSeparatePredictionModel ? predictionModel : chatModel
        case .insight:
            // Use prediction model for insights too (same analytical need)
            return useSeparatePredictionModel ? predictionModel : chatModel
        }
    }
    
    /// Get API key for a specific use case
    public func apiKey(for useCase: AIUseCase) -> String {
        let selectedModel = model(for: useCase)
        return getAPIKey(for: selectedModel.provider)
    }
    
    /// Get base URL for a specific use case
    public func baseURL(for useCase: AIUseCase) -> String {
        let selectedModel = model(for: useCase)
        return selectedModel.provider.baseURL
    }
    
    /// Check if AI is available for a use case
    public func isAvailable(for useCase: AIUseCase) -> Bool {
        let selectedModel = model(for: useCase)
        return hasValidKey(for: selectedModel.provider)
    }
    
    // MARK: - Configured Providers Summary
    
    /// List of providers that have valid API keys configured
    public var configuredProviders: [AIProvider] {
        AIProvider.allCases.filter { hasValidKey(for: $0) }
    }
    
    /// Summary of provider configuration status
    public var providerStatus: [AIProvider: Bool] {
        Dictionary(uniqueKeysWithValues: AIProvider.allCases.map { ($0, hasValidKey(for: $0)) })
    }
}

// MARK: - AI Use Case

/// Different AI use cases that may use different models
public enum AIUseCase {
    case chat        // General conversation
    case prediction  // Price predictions (use best model)
    case insight     // Portfolio/coin insights
}

// MARK: - Custom Provider Configuration

/// Configuration for user-defined AI providers (OpenAI-compatible endpoints)
public struct CustomProviderConfig: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var baseURL: String
    public var modelId: String
    public var description: String
    public var icon: String
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        modelId: String,
        description: String = "",
        icon: String = "server.rack"
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.modelId = modelId
        self.description = description
        self.icon = icon
    }
    
    /// Keychain account for this custom provider's API key
    var keychainAccount: String {
        "custom_provider_\(id)"
    }
    
    /// Convert to AIModelConfig for use in the selection UI
    func toModelConfig() -> AIModelConfig {
        // Create a custom model config - we'll use openrouter as a proxy provider
        // since custom providers work the same way (OpenAI-compatible)
        AIModelConfig(
            provider: .openrouter, // Used as fallback, actual URL is custom
            modelId: "custom:\(id)",
            displayName: name,
            description: description.isEmpty ? "Custom endpoint: \(baseURL)" : description,
            tier: .standard,
            contextWindow: 128000,
            supportsTools: false, // Conservative default for custom providers
            supportsStreaming: true
        )
    }
}

// MARK: - Custom Provider Manager Extension

extension AIProviderManager {
    
    // MARK: - Custom Providers Storage Key
    
    private static let customProvidersKey = "AIProviderManager.customProviders"
    private static let selectedCustomProviderIdKey = "AIProviderManager.selectedCustomProviderId"
    
    // MARK: - Custom Providers Management
    
    /// Get all custom providers
    public var customProviders: [CustomProviderConfig] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.customProvidersKey),
                  let providers = try? JSONDecoder().decode([CustomProviderConfig].self, from: data) else {
                return []
            }
            return providers
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.customProvidersKey)
            }
        }
    }
    
    /// ID of the currently selected custom provider (if any)
    public var selectedCustomProviderId: String? {
        get { UserDefaults.standard.string(forKey: Self.selectedCustomProviderIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.selectedCustomProviderIdKey) }
    }
    
    /// Get a custom provider by ID
    public func getCustomProvider(id: String) -> CustomProviderConfig? {
        customProviders.first { $0.id == id }
    }
    
    /// Add a new custom provider
    public func addCustomProvider(_ provider: CustomProviderConfig) {
        var providers = customProviders
        // Remove existing provider with same ID if updating
        providers.removeAll { $0.id == provider.id }
        providers.append(provider)
        customProviders = providers
    }
    
    /// Update an existing custom provider
    public func updateCustomProvider(_ provider: CustomProviderConfig) {
        var providers = customProviders
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
            customProviders = providers
        }
    }
    
    /// Remove a custom provider and its API key
    public func removeCustomProvider(id: String) {
        // Remove from list
        var providers = customProviders
        providers.removeAll { $0.id == id }
        customProviders = providers
        
        // Remove API key from keychain
        let account = "custom_provider_\(id)"
        try? KeychainHelper.shared.delete(service: keychainService, account: account)
        
        // Clear selection if this was selected
        if selectedCustomProviderId == id {
            selectedCustomProviderId = nil
        }
    }
    
    /// Get API key for a custom provider
    public func getCustomProviderAPIKey(id: String) -> String {
        let account = "custom_provider_\(id)"
        if let key = try? KeychainHelper.shared.read(service: keychainService, account: account), !key.isEmpty {
            return key
        }
        return ""
    }
    
    /// Set API key for a custom provider
    public func setCustomProviderAPIKey(_ key: String, id: String) throws {
        let account = "custom_provider_\(id)"
        try KeychainHelper.shared.save(key, service: keychainService, account: account)
    }
    
    /// Check if custom provider has a valid API key
    public func hasValidCustomProviderKey(id: String) -> Bool {
        let key = getCustomProviderAPIKey(id: id)
        return !key.isEmpty && key.count >= 10 // Minimum reasonable key length
    }
    
    /// Get all models including custom providers
    public var allAvailableModels: [AIModelConfig] {
        var models = AIModelConfig.allModels
        for customProvider in customProviders {
            models.append(customProvider.toModelConfig())
        }
        return models
    }
    
    /// Check if current selection is a custom provider
    public func isCustomProviderSelected(for useCase: AIUseCase) -> Bool {
        let selectedModel = model(for: useCase)
        return selectedModel.modelId.hasPrefix("custom:")
    }
    
    /// Get custom provider config for a model config (if it's a custom model)
    public func getCustomProviderForModel(_ model: AIModelConfig) -> CustomProviderConfig? {
        guard model.modelId.hasPrefix("custom:") else { return nil }
        let customId = String(model.modelId.dropFirst(7)) // Remove "custom:" prefix
        return getCustomProvider(id: customId)
    }
}

// MARK: - Multi-Provider API Client

/// API client that works with any OpenAI-compatible provider
public actor MultiProviderAIClient {
    
    // Shared session for connection reuse
    private let session: URLSession
    
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 90
        self.session = URLSession(configuration: config)
    }
    
    /// Send a chat completion request to any provider
    func sendChatCompletion(
        provider: AIProvider,
        apiKey: String,
        model: String,
        messages: [APIChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        tools: [Tool]? = nil
    ) async throws -> ChatCompletionResponse {
        guard let url = URL(string: provider.baseURL) else {
            throw AIProviderError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Add provider-specific headers
        switch provider {
        case .openrouter:
            request.addValue("CryptoSage iOS", forHTTPHeaderField: "HTTP-Referer")
            request.addValue("CryptoSage", forHTTPHeaderField: "X-Title")
        default:
            break
        }
        
        let payload = ChatCompletionRequest(
            model: model,
            messages: messages,
            tools: tools,
            toolChoice: tools != nil ? "auto" : nil,
            stream: false,
            temperature: temperature,
            maxTokens: maxTokens
        )
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        
        // Handle errors
        if httpResponse.statusCode == 401 {
            throw AIProviderError.invalidAPIKey(provider)
        }
        
        if httpResponse.statusCode == 429 {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.contains("insufficient_quota") || body.contains("exceeded") {
                throw AIProviderError.quotaExceeded(provider)
            }
            throw AIProviderError.rateLimited(provider)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIProviderError.httpError(httpResponse.statusCode, errorBody, provider)
        }
        
        return try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    }
    
    /// Send a streaming chat completion request
    func streamChatCompletion(
        provider: AIProvider,
        apiKey: String,
        model: String,
        messages: [APIChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        onChunk: @escaping (String) -> Void
    ) async throws -> String {
        guard let url = URL(string: provider.baseURL) else {
            throw AIProviderError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        // Add provider-specific headers
        switch provider {
        case .openrouter:
            request.addValue("CryptoSage iOS", forHTTPHeaderField: "HTTP-Referer")
            request.addValue("CryptoSage", forHTTPHeaderField: "X-Title")
        default:
            break
        }
        
        let payload = ChatCompletionRequest(
            model: model,
            messages: messages,
            tools: nil,
            toolChoice: nil,
            stream: true,
            temperature: temperature,
            maxTokens: maxTokens
        )
        
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw AIProviderError.rateLimited(provider)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AIProviderError.httpError(httpResponse.statusCode, "Streaming failed", provider)
        }
        
        var fullText = ""
        
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            
            if jsonString == "[DONE]" { break }
            
            guard !jsonString.isEmpty,
                  let jsonData = jsonString.data(using: .utf8) else { continue }
            
            do {
                let chunk = try JSONDecoder().decode(StreamChunk.self, from: jsonData)
                if let content = chunk.choices?.first?.delta?.content, !content.isEmpty {
                    fullText += content
                    onChunk(fullText)
                }
            } catch {
                continue
            }
        }
        
        return fullText
    }
}

// MARK: - AI Provider Errors

public enum AIProviderError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidAPIKey(AIProvider)
    case rateLimited(AIProvider)
    case quotaExceeded(AIProvider)
    case httpError(Int, String, AIProvider)
    case providerNotConfigured(AIProvider)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from AI service"
        case .invalidAPIKey(let provider):
            return "Invalid \(provider.displayName) API key. Please check your API key in Settings."
        case .rateLimited(let provider):
            return "Rate limited by \(provider.displayName). Please try again in a moment."
        case .quotaExceeded(let provider):
            return "\(provider.displayName) quota exceeded. Please add credits to your account."
        case .httpError(let code, let message, let provider):
            return "\(provider.displayName) error (\(code)): \(message)"
        case .providerNotConfigured(let provider):
            return "\(provider.displayName) is not configured. Please add your API key in Settings."
        }
    }
}
