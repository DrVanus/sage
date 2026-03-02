//
//  AIService.swift
//  CryptoSage
//
//  Core AI service using OpenAI Chat Completions API with function calling.
//  Provides streaming responses and tool execution for crypto assistant.
//

import Foundation
import Combine

// MARK: - Chat Message Types

/// Represents a message in the chat conversation for API calls
struct APIChatMessage: Codable {
    let role: String // "system", "user", "assistant", "tool"
    let content: String?
    let name: String? // For tool messages
    let toolCallId: String? // For tool responses
    let toolCalls: [ToolCall]? // For assistant messages with tool calls
    
    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCallId = "tool_call_id"
        case toolCalls = "tool_calls"
    }
    
    init(role: String, content: String?, name: String? = nil, toolCallId: String? = nil, toolCalls: [ToolCall]? = nil) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }
    
    static func system(_ content: String) -> APIChatMessage {
        APIChatMessage(role: "system", content: content)
    }
    
    static func user(_ content: String) -> APIChatMessage {
        APIChatMessage(role: "user", content: content)
    }
    
    static func assistant(_ content: String) -> APIChatMessage {
        APIChatMessage(role: "assistant", content: content)
    }
    
    static func tool(callId: String, name: String, content: String) -> APIChatMessage {
        APIChatMessage(role: "tool", content: content, name: name, toolCallId: callId)
    }
}

// MARK: - Tool Call Types

struct ToolCall: Codable {
    let id: String
    let type: String
    let function: FunctionCall
}

struct FunctionCall: Codable {
    let name: String
    let arguments: String
}

// MARK: - API Request/Response Types

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [APIChatMessage]
    let tools: [Tool]?
    let toolChoice: String? // "auto", "none", or specific tool
    let stream: Bool?
    let temperature: Double?
    let maxTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream, temperature
        case toolChoice = "tool_choice"
        case maxTokens = "max_tokens"
    }
}

struct Tool: Codable {
    let type: String // "function"
    let function: FunctionDefinition
}

struct FunctionDefinition: Codable {
    let name: String
    let description: String
    let parameters: FunctionParameters
}

struct FunctionParameters: Codable {
    let type: String // "object"
    let properties: [String: ParameterProperty]
    let required: [String]?
}

struct ParameterProperty: Codable {
    let type: String
    let description: String
    let enumValues: [String]?
    
    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
    }
}

struct ChatCompletionResponse: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [Choice]?
    let usage: Usage?
    let error: APIError?
}

struct Choice: Codable {
    let index: Int?
    let message: ResponseMessage?
    let delta: ResponseMessage? // For streaming
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, message, delta
        case finishReason = "finish_reason"
    }
}

struct ResponseMessage: Codable {
    let role: String?
    let content: String?
    let toolCalls: [ToolCall]?
    
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

struct Usage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct APIError: Codable {
    let message: String?
    let type: String?
    let code: String?
}

// MARK: - Streaming Types

struct StreamChunk: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [StreamChoice]?
}

struct StreamChoice: Codable {
    let index: Int?
    let delta: StreamDelta?
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

struct StreamDelta: Codable {
    let role: String?
    let content: String?
    let toolCalls: [StreamToolCall]?
    
    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

struct StreamToolCall: Codable {
    let index: Int?
    let id: String?
    let type: String?
    let function: StreamFunctionCall?
}

struct StreamFunctionCall: Codable {
    let name: String?
    let arguments: String?
}

// MARK: - AI Service

/// Main AI service for handling chat completions with OpenAI and other providers
/// Now supports multi-provider architecture with DeepSeek recommended for predictions
/// (Alpha Arena results: DeepSeek +116%, GPT -62% for crypto trading)
@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()
    
    // MARK: - Published Properties
    @Published var isProcessing: Bool = false
    @Published var currentStreamedText: String = ""
    @Published var lastError: String? = nil
    
    // MARK: - API Key Validation State
    /// Tracks if the current API key is known to be invalid (received 401)
    /// Prevents repeated failed API calls with the same invalid key
    private var apiKeyKnownInvalid: Bool = false
    /// The key that was marked invalid (to detect when key changes)
    private var lastInvalidKeyHash: Int = 0
    
    // MARK: - Multi-Provider Client
    private let multiProviderClient = MultiProviderAIClient()
    
    // MARK: - Configuration
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let defaultModel = "gpt-4o-mini" // Cost-effective model (still excellent quality)
    private let premiumModel = "gpt-4o" // Premium model for Platinum chat only
    
    // DeepSeek models (recommended for crypto predictions - Alpha Arena winner)
    private let deepseekModel = "deepseek-chat" // DeepSeek V3 - best for crypto
    private let deepseekBaseURL = "https://api.deepseek.com/v1/chat/completions"
    
    /// Returns the appropriate model based on user's subscription tier and feature type
    /// - Parameter isChat: True for direct chat interactions (user-facing), false for automated features
    /// 
    /// Model Selection Strategy (Cost Optimization):
    /// - Developer mode: Always GPT-4o for testing
    /// - Platinum tier: GPT-4o for CHAT ONLY (premium differentiator), gpt-4o-mini for automated
    /// - Elite tier: gpt-4o-mini everywhere (profitable, still excellent quality)
    /// - Free/Pro tier: gpt-4o-mini everywhere
    ///
    /// Cost Analysis:
    /// - Premium at max (105 calls × GPT-4o): $78.75/month vs $19.99 revenue = LOSS
    /// - Premium at max (105 calls × gpt-4o-mini): $6.30/month vs $19.99 revenue = $13.69 profit (68.5%)
    /// - Platinum ALL GPT-4o at max usage:
    ///   - Chat (100/day): ~$15/month
    ///   - Portfolio insights (15/day): ~$1.35/month
    ///   - Price explainer (15/day): ~$2.25/month
    ///   - Total: ~$18.60/month vs $59.99 revenue = $41.39 profit (69%)
    ///   - At realistic 30% utilization: ~$6/month cost = $54 profit (90%)
    ///
    /// NOTE: Shared features (Market Sentiment, Coin Insights, Predictions, F&G)
    /// are handled by Firebase and use GPT-4o for ALL users (cached/shared).
    /// The cost is amortized across all users, not charged per-user.
    ///
    /// This makes Platinum the "premium AI" tier with GPT-4o everywhere,
    /// while keeping Elite profitable with still-excellent gpt-4o-mini quality.
    private func modelForCurrentTier(isChat: Bool = true) -> String {
        // Developer mode always gets the best model
        if SubscriptionManager.shared.isDeveloperMode {
            return premiumModel
        }
        
        let tier = SubscriptionManager.shared.effectiveTier
        
        switch tier {
        case .premium:
            // Premium gets GPT-4o for ALL features (chat AND automated)
            // At $19.99/month, this is the key differentiator that justifies the premium price
            return premiumModel
        case .pro, .free:
            // All other tiers use gpt-4o-mini everywhere
            // gpt-4o-mini is still excellent for crypto questions - users won't notice
            // the difference for insights, predictions, and most chat queries
            return defaultModel
        }
    }
    
    /// Legacy property for backward compatibility - defaults to chat model
    private var modelForCurrentTierLegacy: String {
        return modelForCurrentTier(isChat: true)
    }
    
    /// Whether the current user has access to the premium AI model
    /// Developer mode always has access for testing purposes
    var hasPremiumModelAccess: Bool {
        SubscriptionManager.shared.isDeveloperMode || SubscriptionManager.shared.hasAccess(to: .premiumAIModel)
    }
    
    // Reuse session for connection efficiency
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        // Reduced from 120s to 45s/60s for better mobile UX - prevents 2-minute hangs
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    
    // Dedicated session for streaming with no buffering
    private lazy var streamingSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        // Reduced from 120s to 45s/60s for better mobile UX - prevents 2-minute hangs
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    
    // Conversation history for context
    private var conversationHistory: [APIChatMessage] = []
    private let maxHistoryMessages = 50 // Keep last N messages for context
    
    private init() {}
    
    // MARK: - Public API
    
    /// Send a message and get a response (non-streaming)
    /// Respects user's chat model selection from AIProviderManager
    /// Uses Firebase backend when available (works for all users without API keys)
    /// - Parameters:
    ///   - userMessage: The user's message
    ///   - systemPrompt: Optional custom system prompt
    ///   - usePremiumModel: If true, forces premium model (Elite users always get premium)
    ///   - includeTools: Whether to include function tools
    ///   - temperature: Controls randomness (0.0 = deterministic, 1.0 = creative). Default 0.7 for chat.
    ///   - isAutomatedFeature: If true, uses cost-effective model even for Platinum (for predictions, insights, etc.)
    ///   - maxTokens: Maximum tokens for response (default 2048, can be reduced for cost savings)
    func sendMessage(
        _ userMessage: String,
        systemPrompt: String? = nil,
        usePremiumModel: Bool = false,
        includeTools: Bool = true,
        temperature: Double? = nil,
        isAutomatedFeature: Bool = false,
        maxTokens: Int = 2048,
        onToolExecution: ((String) -> Void)? = nil
    ) async throws -> String {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        
        // PRIORITY 1: Try Firebase backend first (works for ALL users)
        // This is the primary path - no API key needed on device.
        // FIX: Previously skipped Firebase for automated features (e.g. AI portfolio monitor gatekeeper),
        // which caused them to silently fail when no local API key was configured. Now Firebase is
        // used as fallback for automated features too — but WITHOUT conversation history and with
        // reduced max tokens to keep costs minimal.
        let firebaseService = FirebaseService.shared
        
        #if DEBUG
        print("[AIService] Non-streaming request started")
        print("[AIService] isAutomatedFeature: \(isAutomatedFeature)")
        print("[AIService] Firebase useFirebaseForAI: \(firebaseService.useFirebaseForAI)")
        #endif
        
        if firebaseService.useFirebaseForAI {
            do {
                // For automated features, skip conversation history to reduce cost and latency.
                // These are one-shot prompts (like the portfolio gatekeeper) that don't need context.
                let historyForFirebase: [[String: String]]?
                if isAutomatedFeature {
                    historyForFirebase = nil
                } else {
                    historyForFirebase = conversationHistory.suffix(20).compactMap { msg in
                        guard let content = msg.content else { return nil }
                        return ["role": msg.role, "content": content]
                    }
                }
                
                #if DEBUG
                print("[AIService] Attempting Firebase non-streaming chat\(isAutomatedFeature ? " (automated)" : "")")
                #endif
                let response = try await firebaseService.sendChatMessage(
                    message: userMessage,
                    history: historyForFirebase,
                    systemPrompt: systemPrompt
                )
                
                let cleanedText = stripMarkdown(response.response)
                #if DEBUG
                print("[AIService] Firebase chat succeeded, response length: \(cleanedText.count)")
                #endif
                
                // Update conversation history (skip for automated features)
                if !isAutomatedFeature {
                    conversationHistory.append(.user(userMessage))
                    conversationHistory.append(.assistant(cleanedText))
                    trimHistory()
                }
                
                return cleanedText
            } catch {
                #if DEBUG
                print("[AIService] Firebase chat failed: \(error.localizedDescription)")
                print("[AIService] Trying local API key fallback...")
                #endif
                // Continue to local API key fallback
            }
        } else {
            #if DEBUG
            print("[AIService] Firebase not available for chat")
            #endif
        }
        
        // PRIORITY 2: Fall back to local API keys
        // Get user's preferred chat model from AIProviderManager
        let manager = AIProviderManager.shared
        let chatModelConfig = manager.chatModel
        let selectedProvider = chatModelConfig.provider
        
        // Build messages array
        var messages: [APIChatMessage] = []
        
        // Add system prompt
        if let system = systemPrompt {
            messages.append(.system(system))
        } else {
            messages.append(.system(AIContextBuilder.shared.buildSystemPrompt()))
        }
        
        // Add conversation history (limited) - skip for automated features to save tokens
        if !isAutomatedFeature {
            let historyToInclude = Array(conversationHistory.suffix(maxHistoryMessages))
            messages.append(contentsOf: historyToInclude)
        }
        
        // Add new user message
        let userMsg = APIChatMessage.user(userMessage)
        messages.append(userMsg)
        
        // Determine which provider to use based on user's selection and availability
        let useOpenAI = selectedProvider == .openai || !manager.hasValidKey(for: selectedProvider)
        
        // For OpenAI: use existing flow with tools support
        if useOpenAI {
            let apiKey = getAPIKey()
            #if DEBUG
            print("[AIService] Using OpenAI path, API key available: \(!apiKey.isEmpty)")
            #endif
            guard !apiKey.isEmpty else {
                // Try to fall back to any available provider
                #if DEBUG
                print("[AIService] No OpenAI API key, looking for fallback provider...")
                #endif
                if let fallback = findAvailableProvider(), fallback.provider != .openai {
                    #if DEBUG
                    print("[AIService] Using fallback provider: \(fallback.provider)")
                    #endif
                    return try await sendChatWithProvider(
                        messages: messages,
                        userMsg: userMsg,
                        provider: fallback.provider,
                        model: fallback.modelId,
                        temperature: temperature ?? 0.7,
                        maxTokens: maxTokens,
                        isAutomatedFeature: isAutomatedFeature
                    )
                }
                #if DEBUG
                print("[AIService] No fallback provider available - throwing missingAPIKey error")
                #endif
                throw AIServiceError.missingAPIKey
            }
            
            // Get tools if enabled (skip for automated features to reduce complexity)
            let tools = (includeTools && !isAutomatedFeature) ? AIFunctionTools.shared.getAllTools() : nil
            
            // Select model based on subscription tier and feature type
            let selectedModel: String
            if usePremiumModel && hasPremiumModelAccess {
                selectedModel = premiumModel
            } else {
                selectedModel = modelForCurrentTier(isChat: !isAutomatedFeature)
            }
            
            // Make API call
            let response = try await callChatAPI(
                messages: messages,
                model: selectedModel,
                tools: tools,
                stream: false,
                temperature: temperature,
                maxTokens: maxTokens
            )
            
            // Handle tool calls if present
            if let toolCalls = response.choices?.first?.message?.toolCalls, !toolCalls.isEmpty {
                return try await handleToolCalls(
                    toolCalls: toolCalls,
                    messages: messages,
                    model: selectedModel,
                    onToolExecution: onToolExecution
                )
            }
            
            // Extract response text
            guard let responseText = response.choices?.first?.message?.content else {
                throw AIServiceError.noResponse
            }
            
            // Clean up any markdown formatting that slipped through
            let cleanedText = stripMarkdown(responseText)
            
            // Update conversation history (skip for automated features)
            if !isAutomatedFeature {
                conversationHistory.append(userMsg)
                conversationHistory.append(.assistant(cleanedText))
                trimHistory()
            }
            
            return cleanedText
        }
        
        // For non-OpenAI providers: use multiProviderClient
        return try await sendChatWithProvider(
            messages: messages,
            userMsg: userMsg,
            provider: selectedProvider,
            model: chatModelConfig.modelId,
            temperature: temperature ?? 0.7,
            maxTokens: maxTokens,
            isAutomatedFeature: isAutomatedFeature
        )
    }
    
    /// Helper to send chat with a specific non-OpenAI provider
    private func sendChatWithProvider(
        messages: [APIChatMessage],
        userMsg: APIChatMessage,
        provider: AIProvider,
        model: String,
        temperature: Double,
        maxTokens: Int,
        isAutomatedFeature: Bool
    ) async throws -> String {
        let apiKey = AIProviderManager.shared.getAPIKey(for: provider)
        
        let response = try await multiProviderClient.sendChatCompletion(
            provider: provider,
            apiKey: apiKey,
            model: model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            tools: nil // Non-OpenAI providers don't support tools in this implementation
        )
        
        guard let responseText = response.choices?.first?.message?.content else {
            throw AIServiceError.noResponse
        }
        
        let cleanedText = stripMarkdown(responseText)
        
        // Update conversation history (skip for automated features)
        if !isAutomatedFeature {
            conversationHistory.append(userMsg)
            conversationHistory.append(.assistant(cleanedText))
            trimHistory()
        }
        
        return cleanedText
    }
    
    /// Send a message with streaming response
    /// Respects user's chat model selection from AIProviderManager
    /// Uses Firebase backend when available (works for all users without API keys)
    /// Note: For true streaming UX, tools are disabled. Use sendMessage() for tool-enabled queries.
    func sendMessageStreaming(
        _ userMessage: String,
        systemPrompt: String? = nil,
        usePremiumModel: Bool = false,
        includeTools: Bool = true,
        isAutomatedFeature: Bool = false,
        onChunk: @escaping (String) -> Void
    ) async throws -> String {
        isProcessing = true
        lastError = nil
        currentStreamedText = ""
        defer { isProcessing = false }
        
        // PRIORITY 1: Try Firebase backend first (works for ALL users)
        // This is the primary path - no API key needed on device
        let firebaseService = FirebaseService.shared
        
        // Debug logging for streaming diagnostics
        #if DEBUG
        print("[AIService] Streaming request started")
        print("[AIService] Firebase isConfigured: \(firebaseService.isConfigured)")
        print("[AIService] Firebase useFirebaseForAI: \(firebaseService.useFirebaseForAI)")
        #endif
        
        if firebaseService.useFirebaseForAI {
            do {
                // Build history for Firebase
                let historyForFirebase: [[String: String]] = conversationHistory.suffix(20).compactMap { msg in
                    guard let content = msg.content else { return nil }
                    return ["role": msg.role, "content": content]
                }
                
                #if DEBUG
                print("[AIService] Attempting Firebase streaming with \(historyForFirebase.count) history messages")
                #endif
                
                // Try streaming first - pass systemPrompt with rich context
                var chunkCount = 0
                let fullText = try await firebaseService.streamChatMessage(
                    message: userMessage,
                    history: historyForFirebase.isEmpty ? nil : historyForFirebase,
                    systemPrompt: systemPrompt,  // Pass the rich context (portfolio, market data, etc.)
                    onChunk: { text in
                        chunkCount += 1
                        #if DEBUG
                        if chunkCount <= 3 || chunkCount % 10 == 0 {
                            print("[AIService] Streaming chunk #\(chunkCount), total length: \(text.count)")
                        }
                        #endif
                        self.currentStreamedText = text
                        onChunk(text)
                    }
                )
                
                #if DEBUG
                print("[AIService] Streaming completed with \(chunkCount) chunks, final length: \(fullText.count)")
                #endif
                
                // Update conversation history
                if !isAutomatedFeature {
                    conversationHistory.append(.user(userMessage))
                    conversationHistory.append(.assistant(fullText))
                    trimHistory()
                }
                
                return fullText
            } catch {
                // Log Firebase error but continue to fallback
                #if DEBUG
                print("[AIService] Firebase streaming failed: \(error.localizedDescription)")
                print("[AIService] Error type: \(type(of: error))")
                #endif

                // Try non-streaming Firebase as fallback
                #if DEBUG
                print("[AIService] Attempting Firebase non-streaming fallback...")
                #endif
                do {
                    let historyForFirebase: [[String: String]] = conversationHistory.suffix(20).compactMap { msg in
                        guard let content = msg.content else { return nil }
                        return ["role": msg.role, "content": content]
                    }
                    
                    let response = try await firebaseService.sendChatMessage(
                        message: userMessage,
                        history: historyForFirebase.isEmpty ? nil : historyForFirebase,
                        systemPrompt: systemPrompt  // Pass the rich context for fallback too
                    )
                    
                    let fullText = response.response
                    #if DEBUG
                    print("[AIService] Firebase non-streaming succeeded, length: \(fullText.count)")
                    #endif
                    currentStreamedText = fullText
                    onChunk(fullText)
                    
                    if !isAutomatedFeature {
                        conversationHistory.append(.user(userMessage))
                        conversationHistory.append(.assistant(fullText))
                        trimHistory()
                    }
                    
                    return fullText
                } catch {
                    #if DEBUG
                    print("[AIService] Firebase non-streaming also failed: \(error.localizedDescription)")
                    print("[AIService] Falling back to local API keys...")
                    #endif
                    // Continue to local API key fallback
                }
            }
        } else {
            #if DEBUG
            print("[AIService] Firebase not available, using local API keys")
            #endif
        }
        
        // PRIORITY 2: Fall back to local API keys (for users who configured their own)
        // Get user's preferred chat model from AIProviderManager
        let manager = AIProviderManager.shared
        let chatModelConfig = manager.chatModel
        let selectedProvider = chatModelConfig.provider
        
        // Build messages array
        var messages: [APIChatMessage] = []
        
        if let system = systemPrompt {
            messages.append(.system(system))
        } else {
            messages.append(.system(AIContextBuilder.shared.buildSystemPrompt()))
        }
        
        // Skip history for automated features to save tokens
        if !isAutomatedFeature {
            let historyToInclude = Array(conversationHistory.suffix(maxHistoryMessages))
            messages.append(contentsOf: historyToInclude)
        }
        
        let userMsg = APIChatMessage.user(userMessage)
        messages.append(userMsg)
        
        // Determine which provider to use based on user's selection and availability
        let useOpenAI = selectedProvider == .openai || !manager.hasValidKey(for: selectedProvider)
        
        var fullText: String
        
        if useOpenAI {
            let apiKey = getAPIKey()
            guard !apiKey.isEmpty else {
                // Try to fall back to any available provider
                if let fallback = findAvailableProvider(), fallback.provider != .openai {
                    fullText = try await streamWithProvider(
                        messages: messages,
                        provider: fallback.provider,
                        model: fallback.modelId,
                        onChunk: onChunk
                    )
                } else {
                    // No Firebase, no local key - show helpful error
                    throw AIServiceError.missingAPIKey
                }
                
                // Update conversation history
                if !isAutomatedFeature {
                    conversationHistory.append(userMsg)
                    conversationHistory.append(.assistant(fullText))
                    trimHistory()
                }
                return fullText
            }
            
            // Select model based on subscription tier
            let selectedModel: String
            if usePremiumModel && hasPremiumModelAccess {
                selectedModel = premiumModel
            } else {
                selectedModel = modelForCurrentTier(isChat: !isAutomatedFeature)
            }
            
            // For streaming, we go directly to streaming without tool calls
            fullText = try await streamChatAPI(
                messages: messages,
                model: selectedModel,
                onChunk: onChunk
            )
        } else {
            // For non-OpenAI providers: use multiProviderClient streaming
            fullText = try await streamWithProvider(
                messages: messages,
                provider: selectedProvider,
                model: chatModelConfig.modelId,
                onChunk: onChunk
            )
        }
        
        // Update conversation history (skip for automated features)
        if !isAutomatedFeature {
            conversationHistory.append(userMsg)
            conversationHistory.append(.assistant(fullText))
            trimHistory()
        }
        
        return fullText
    }
    
    /// Helper to stream with a specific non-OpenAI provider
    private func streamWithProvider(
        messages: [APIChatMessage],
        provider: AIProvider,
        model: String,
        onChunk: @escaping (String) -> Void
    ) async throws -> String {
        let apiKey = AIProviderManager.shared.getAPIKey(for: provider)
        
        return try await multiProviderClient.streamChatCompletion(
            provider: provider,
            apiKey: apiKey,
            model: model,
            messages: messages,
            temperature: 0.7,
            maxTokens: 2048,
            onChunk: { text in
                self.currentStreamedText = text
                onChunk(text)
            }
        )
    }
    
    /// Clear conversation history
    func clearHistory() {
        conversationHistory.removeAll()
    }
    
    /// Set conversation history from existing messages
    func setHistory(from messages: [ChatMessage]) {
        conversationHistory = messages.map { msg in
            if msg.sender == "user" {
                return .user(msg.text)
            } else {
                return .assistant(msg.text)
            }
        }
        trimHistory()
    }
    
    // MARK: - Multi-Provider Prediction API
    
    /// Send a message optimized for crypto predictions
    /// Respects user's model selection from AIProviderManager
    /// When "Optimize Predictions" is ON, uses the selected prediction model
    /// When OFF, uses the same model as chat
    /// - Parameters:
    ///   - userMessage: The prediction prompt
    ///   - systemPrompt: System prompt for the prediction
    ///   - temperature: Controls randomness (lower = more deterministic)
    ///   - maxTokens: Maximum tokens for response
    /// - Returns: The AI response text, provider name, and model used
    func sendPredictionMessage(
        _ userMessage: String,
        systemPrompt: String,
        temperature: Double = 0.25,
        maxTokens: Int = 512
    ) async throws -> (response: String, provider: String, model: String) {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        
        // Build messages array
        let messages: [APIChatMessage] = [
            .system(systemPrompt),
            .user(userMessage)
        ]
        
        // Get user's preferred prediction model from AIProviderManager
        let manager = AIProviderManager.shared
        let selectedModelConfig: AIModelConfig
        
        if manager.useSeparatePredictionModel {
            // User wants optimized predictions - use their selected prediction model
            selectedModelConfig = manager.predictionModel
        } else {
            // Use same model as chat
            selectedModelConfig = manager.chatModel
        }
        
        let selectedProvider = selectedModelConfig.provider
        let selectedModelId = selectedModelConfig.modelId
        
        // Check if we have a valid key for the selected provider
        guard manager.hasValidKey(for: selectedProvider) else {
            // Fall back to any available provider
            let fallbackProvider = findAvailableProvider()
            guard let fallback = fallbackProvider else {
                throw AIServiceError.missingAPIKey
            }
            
            #if DEBUG
            print("[AIService] Selected provider \(selectedProvider.displayName) not configured, falling back to \(fallback.provider.displayName)")
            #endif
            return try await sendWithProvider(
                messages: messages,
                provider: fallback.provider,
                model: fallback.modelId,
                temperature: temperature,
                maxTokens: maxTokens
            )
        }
        
        // Use the selected provider
        return try await sendWithProvider(
            messages: messages,
            provider: selectedProvider,
            model: selectedModelId,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
    
    /// Helper to send with a specific provider
    private func sendWithProvider(
        messages: [APIChatMessage],
        provider: AIProvider,
        model: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> (response: String, provider: String, model: String) {
        let apiKey = AIProviderManager.shared.getAPIKey(for: provider)
        
        do {
            let response = try await multiProviderClient.sendChatCompletion(
                provider: provider,
                apiKey: apiKey,
                model: model,
                messages: messages,
                temperature: temperature,
                maxTokens: maxTokens,
                tools: nil
            )
            
            guard let responseText = response.choices?.first?.message?.content else {
                throw AIServiceError.noResponse
            }
            
            let cleanedText = stripMarkdown(responseText)
            return (response: cleanedText, provider: provider.displayName, model: model)
        } catch {
            #if DEBUG
            print("[AIService] \(provider.displayName) request failed: \(error.localizedDescription)")
            #endif
            throw error
        }
    }
    
    /// Find any available provider with a valid API key
    private func findAvailableProvider() -> AIModelConfig? {
        let manager = AIProviderManager.shared
        
        // Priority order: DeepSeek (best for predictions), OpenAI, Grok, OpenRouter
        let priorityOrder: [AIProvider] = [.deepseek, .openai, .grok, .openrouter]
        
        for provider in priorityOrder {
            if manager.hasValidKey(for: provider) {
                // Return the default model for this provider
                switch provider {
                case .deepseek:
                    return .deepseekChat
                case .openai:
                    return .gpt4oMini
                case .grok:
                    return .grok4Fast
                case .openrouter:
                    return .openrouterDeepseek
                }
            }
        }
        return nil
    }
    
    /// Send a message using a specific provider
    /// - Parameters:
    ///   - userMessage: The user's message
    ///   - systemPrompt: System prompt
    ///   - provider: The AI provider to use
    ///   - model: The model ID to use
    ///   - temperature: Controls randomness
    ///   - maxTokens: Maximum tokens for response
    /// - Returns: The AI response text
    func sendMessageWithProvider(
        _ userMessage: String,
        systemPrompt: String,
        provider: AIProvider,
        model: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 2048
    ) async throws -> String {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        
        // Get API key for the provider
        let apiKey = AIProviderManager.shared.getAPIKey(for: provider)
        guard !apiKey.isEmpty else {
            throw AIProviderError.providerNotConfigured(provider)
        }
        
        // Build messages
        let messages: [APIChatMessage] = [
            .system(systemPrompt),
            .user(userMessage)
        ]
        
        // Determine model to use
        let selectedModel: String
        if let model = model {
            selectedModel = model
        } else {
            // Use default model for provider
            switch provider {
            case .openai:
                selectedModel = modelForCurrentTier(isChat: true)
            case .deepseek:
                selectedModel = deepseekModel
            case .grok:
                selectedModel = "grok-4"
            case .openrouter:
                selectedModel = "deepseek/deepseek-chat"
            }
        }
        
        let response = try await multiProviderClient.sendChatCompletion(
            provider: provider,
            apiKey: apiKey,
            model: selectedModel,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            tools: nil
        )
        
        guard let responseText = response.choices?.first?.message?.content else {
            throw AIServiceError.noResponse
        }
        
        return stripMarkdown(responseText)
    }
    
    /// Get the currently configured prediction provider info based on user settings
    var predictionProviderInfo: (provider: String, model: String, isOptimized: Bool) {
        let manager = AIProviderManager.shared
        
        // Determine which model will be used for predictions
        let selectedModelConfig: AIModelConfig
        if manager.useSeparatePredictionModel {
            selectedModelConfig = manager.predictionModel
        } else {
            selectedModelConfig = manager.chatModel
        }
        
        let provider = selectedModelConfig.provider
        let modelId = selectedModelConfig.modelId
        
        // Check if the selected provider is available
        if manager.hasValidKey(for: provider) {
            // DeepSeek is considered "optimized" for predictions
            let isOptimized = provider == .deepseek
            return (provider: provider.displayName, model: modelId, isOptimized: isOptimized)
        }
        
        // Fall back to any available provider
        if let fallback = findAvailableProvider() {
            let isOptimized = fallback.provider == .deepseek
            return (provider: fallback.provider.displayName, model: fallback.modelId, isOptimized: isOptimized)
        }
        
        return (provider: "None", model: "N/A", isOptimized: false)
    }
    
    /// Get the currently configured chat provider info based on user settings
    var chatProviderInfo: (provider: String, model: String) {
        let manager = AIProviderManager.shared
        let selectedModelConfig = manager.chatModel
        let provider = selectedModelConfig.provider
        
        if manager.hasValidKey(for: provider) {
            return (provider: provider.displayName, model: selectedModelConfig.modelId)
        }
        
        // Fall back to any available provider
        if let fallback = findAvailableProvider() {
            return (provider: fallback.provider.displayName, model: fallback.modelId)
        }
        
        return (provider: "None", model: "N/A")
    }
    
    // MARK: - Private Methods
    
    private func getAPIKey() -> String {
        // Use APIConfig which reads from the correct Keychain location (CryptoSage.APIKeys/openai_api_key)
        // This ensures consistency with where the settings UI saves the key
        let configKey = APIConfig.openAIKey
        if !configKey.isEmpty && configKey != "keygoeshere" {
            return configKey
        }
        return ""
    }
    
    private func callChatAPI(
        messages: [APIChatMessage],
        model: String,
        tools: [Tool]?,
        stream: Bool,
        temperature: Double? = nil,
        maxTokens: Int = 2048
    ) async throws -> ChatCompletionResponse {
        // PERFORMANCE FIX: Validate API key before making network request
        // This prevents repeated 401 errors that cause lag
        let apiKey = getAPIKey()
        let currentKeyHash = apiKey.hashValue
        
        // Reset invalid flag if the key has changed
        if currentKeyHash != lastInvalidKeyHash {
            apiKeyKnownInvalid = false
        }
        
        // Check if key is known to be invalid
        if apiKeyKnownInvalid {
            #if DEBUG
            print("[AIService] Skipping API call - key is known to be invalid")
            #endif
            throw AIServiceError.invalidAPIKey
        }
        
        // Validate key format before making request
        if !APIConfig.hasValidOpenAIKey {
            #if DEBUG
            print("[AIService] Skipping API call - key format invalid (must start with 'sk-')")
            #endif
            throw AIServiceError.missingAPIKey
        }
        
        guard let url = URL(string: baseURL) else {
            throw AIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Use provided temperature or default to 0.7 for chat
        let effectiveTemperature = temperature ?? 0.7
        
        let payload = ChatCompletionRequest(
            model: model,
            messages: messages,
            tools: tools,
            toolChoice: tools != nil ? "auto" : nil,
            stream: stream,
            temperature: effectiveTemperature,
            maxTokens: maxTokens
        )
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)
        
        // #region agent log - Hypothesis A: Check API key
        let maskedKey = apiKey.count > 10 ? "\(apiKey.prefix(7))...\(apiKey.suffix(4))" : "TOO_SHORT"
        debugLog(location: "AIService:callChatAPI", message: "API Request Starting", data: ["maskedKey": maskedKey, "keyLength": apiKey.count, "model": model, "hasTools": tools != nil], hypothesisId: "A")
        // #endregion
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            // #region agent log - Hypothesis E
            debugLog(location: "AIService:callChatAPI", message: "Invalid response type", data: ["error": "not HTTPURLResponse"], hypothesisId: "E")
            // #endregion
            throw AIServiceError.invalidResponse
        }
        
        // #region agent log - Hypothesis C: Log actual status code
        let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode"
        debugLog(location: "AIService:callChatAPI", message: "HTTP Response Received", data: ["statusCode": httpResponse.statusCode, "responseBody": String(responseBody.prefix(500))], hypothesisId: "C")
        // #endregion
        
        if httpResponse.statusCode == 401 {
            // #region agent log - Hypothesis A
            debugLog(location: "AIService:callChatAPI", message: "401 Unauthorized", data: ["body": String(responseBody.prefix(300))], hypothesisId: "A")
            // #endregion
            // PERFORMANCE FIX: Mark key as invalid to prevent repeated 401 errors
            apiKeyKnownInvalid = true
            lastInvalidKeyHash = apiKey.hashValue
            #if DEBUG
            print("[AIService] API key marked as invalid - will skip future calls until key changes")
            #endif
            throw AIServiceError.invalidAPIKey
        }
        
        if httpResponse.statusCode == 429 {
            // #region agent log - Hypothesis B
            debugLog(location: "AIService:callChatAPI", message: "429 Rate Limited", data: ["body": String(responseBody.prefix(300))], hypothesisId: "B")
            // #endregion
            // Check if it's quota exceeded vs rate limit
            if responseBody.contains("insufficient_quota") || responseBody.contains("exceeded your current quota") {
                throw AIServiceError.quotaExceeded
            }
            throw AIServiceError.rateLimited
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            // #region agent log - Hypothesis C
            debugLog(location: "AIService:callChatAPI", message: "HTTP Error", data: ["statusCode": httpResponse.statusCode, "errorBody": String(errorBody.prefix(300))], hypothesisId: "C")
            // #endregion
            throw AIServiceError.httpError(httpResponse.statusCode, errorBody)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(ChatCompletionResponse.self, from: data)
    }
    
    // #region agent log helper
    // SECURITY FIX: Only log in DEBUG builds to prevent sensitive data exposure in production
    private func debugLog(location: String, message: String, data: [String: Any], hypothesisId: String) {
        #if DEBUG
        // Only log in development - never write sensitive data to disk in production
        var logData = data
        logData["hypothesisId"] = hypothesisId
        print("[AIService Debug] \(location): \(message) - \(logData)")
        #endif
    }
    // #endregion
    
    private func streamChatAPI(
        messages: [APIChatMessage],
        model: String,
        onChunk: @escaping (String) -> Void
    ) async throws -> String {
        // PERFORMANCE FIX: Validate API key before making network request
        let apiKey = getAPIKey()
        let currentKeyHash = apiKey.hashValue
        
        // Reset invalid flag if the key has changed
        if currentKeyHash != lastInvalidKeyHash {
            apiKeyKnownInvalid = false
        }
        
        // Check if key is known to be invalid
        if apiKeyKnownInvalid {
            #if DEBUG
            print("[AIService] Skipping streaming API call - key is known to be invalid")
            #endif
            throw AIServiceError.invalidAPIKey
        }
        
        // Validate key format before making request
        if !APIConfig.hasValidOpenAIKey {
            #if DEBUG
            print("[AIService] Skipping streaming API call - key format invalid")
            #endif
            throw AIServiceError.missingAPIKey
        }
        
        guard let url = URL(string: baseURL) else {
            throw AIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Enable streaming by accepting text/event-stream
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        let payload = ChatCompletionRequest(
            model: model,
            messages: messages,
            tools: nil, // No tools in streaming mode for simplicity
            toolChoice: nil,
            stream: true,
            temperature: 0.7,
            maxTokens: 2048
        )
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)
        
        // Use streaming session for unbuffered response
        let (bytes, response) = try await streamingSession.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        
        // Check for errors
        if httpResponse.statusCode == 401 {
            // PERFORMANCE FIX: Mark key as invalid to prevent repeated 401 errors
            apiKeyKnownInvalid = true
            lastInvalidKeyHash = apiKey.hashValue
            #if DEBUG
            print("[AIService] Streaming: API key marked as invalid - will skip future calls until key changes")
            #endif
            throw AIServiceError.invalidAPIKey
        }
        
        if httpResponse.statusCode == 429 {
            throw AIServiceError.rateLimited
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AIServiceError.httpError(httpResponse.statusCode, "Streaming request failed")
        }
        
        var fullText = ""
        
        // Process stream line by line
        for try await line in bytes.lines {
            // Skip empty lines and non-data lines
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            
            // Check for stream end
            if jsonString == "[DONE]" { break }
            
            guard !jsonString.isEmpty,
                  let jsonData = jsonString.data(using: .utf8) else { continue }
            
            do {
                let chunk = try JSONDecoder().decode(StreamChunk.self, from: jsonData)
                if let content = chunk.choices?.first?.delta?.content, !content.isEmpty {
                    fullText += content
                    // Apply markdown stripping in real-time for cleaner display
                    let cleanedSoFar = stripMarkdown(fullText)
                    currentStreamedText = cleanedSoFar
                    
                    // Call the chunk handler immediately
                    onChunk(cleanedSoFar)
                    
                    // Yield to allow UI to update
                    await Task.yield()
                }
            } catch {
                // Skip malformed chunks silently
                continue
            }
        }
        
        // Ensure final text is delivered
        let cleanedText = stripMarkdown(fullText)
        if !cleanedText.isEmpty {
            onChunk(cleanedText)
        }
        
        return cleanedText
    }
    
    private func handleToolCalls(
        toolCalls: [ToolCall],
        messages: [APIChatMessage],
        model: String,
        onToolExecution: ((String) -> Void)? = nil
    ) async throws -> String {
        var updatedMessages = messages
        
        // Add the assistant message with tool calls
        let assistantMsg = APIChatMessage(
            role: "assistant",
            content: nil,
            toolCalls: toolCalls
        )
        updatedMessages.append(assistantMsg)
        
        // Execute each tool call and add results
        for toolCall in toolCalls {
            // Notify UI which tool is being executed
            onToolExecution?(toolCall.function.name)
            
            let result = await AIFunctionTools.shared.executeFunction(
                name: toolCall.function.name,
                arguments: toolCall.function.arguments
            )
            
            let toolMsg = APIChatMessage.tool(
                callId: toolCall.id,
                name: toolCall.function.name,
                content: result
            )
            updatedMessages.append(toolMsg)
        }
        
        // Get final response with tool results
        let finalResponse = try await callChatAPI(
            messages: updatedMessages,
            model: model,
            tools: nil, // No more tools needed
            stream: false
        )
        
        guard let responseText = finalResponse.choices?.first?.message?.content else {
            throw AIServiceError.noResponse
        }
        
        // Clean up any markdown formatting
        let cleanedText = stripMarkdown(responseText)
        
        // Update history with the full exchange
        if let userMsg = messages.last {
            conversationHistory.append(userMsg)
        }
        conversationHistory.append(.assistant(cleanedText))
        trimHistory()
        
        return cleanedText
    }
    
    /// Remove markdown syntax from AI responses for clean mobile display
    private func stripMarkdown(_ text: String) -> String {
        var result = text
        
        // Remove headers (### Header -> Header)
        result = result.replacingOccurrences(of: "\\n#{1,6}\\s*", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
        
        // Remove bold (**text** or __text__ -> text) - use non-greedy matching for better handling
        // Run multiple passes to catch nested/repeated patterns
        for _ in 0..<3 {
            result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
            result = result.replacingOccurrences(of: "__(.+?)__", with: "$1", options: .regularExpression)
        }
        
        // Remove italic (*text* or _text_ -> text) - be careful not to affect bullet points
        // Only match single asterisks/underscores with non-whitespace content
        // Run multiple passes for nested patterns
        for _ in 0..<2 {
            result = result.replacingOccurrences(of: "(?<![*\\s])\\*([^*\\n]+?)\\*(?![*])", with: "$1", options: .regularExpression)
            result = result.replacingOccurrences(of: "(?<![_\\s])_([^_\\n]+?)_(?![_])", with: "$1", options: .regularExpression)
        }
        
        // Remove code blocks (```code``` -> code)
        result = result.replacingOccurrences(of: "```[\\w]*\\n?([\\s\\S]*?)```", with: "$1", options: .regularExpression)
        
        // Remove inline code (`code` -> code)
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        
        // Clean up any remaining stray asterisks that might be from incomplete markdown
        // Pattern: isolated ** at word boundaries (not part of multiplication like 2*3)
        result = result.replacingOccurrences(of: "(?<=\\s|^)\\*\\*(?=\\S)", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?<=\\S)\\*\\*(?=\\s|$|[.,!?;:])", with: "", options: .regularExpression)
        
        // Clean up extra whitespace
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func trimHistory() {
        if conversationHistory.count > maxHistoryMessages {
            conversationHistory = Array(conversationHistory.suffix(maxHistoryMessages))
        }
    }
}

// MARK: - Error Types

enum AIServiceError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case invalidURL
    case invalidResponse
    case noResponse
    case rateLimited
    case quotaExceeded
    case httpError(Int, String)
    case toolExecutionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "AI service temporarily unavailable"
        case .invalidAPIKey:
            return "Invalid OpenAI API key. Please check your API key in Settings."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Invalid response from AI service."
        case .noResponse:
            return "No response received from AI."
        case .rateLimited:
            return "Rate limited by OpenAI. Please try again in a moment."
        case .quotaExceeded:
            return "OpenAI quota exceeded. Please add credits to your OpenAI account at platform.openai.com/account/billing"
        case .httpError(let code, let message):
            return "API error (\(code)): \(message)"
        case .toolExecutionFailed(let name):
            return "Failed to execute function: \(name)"
        }
    }
}
