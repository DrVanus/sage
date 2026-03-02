//
//  AISettingsView.swift
//  CryptoSage
//
//  Multi-provider AI Settings view for managing AI configuration.
//  Supports OpenAI, DeepSeek (recommended for predictions), Grok, and OpenRouter.
//

import SwiftUI
import StoreKit

struct AISettingsView: View {
    @StateObject private var providerManager = AIProviderManager.shared
    
    @State private var selectedProvider: AIProvider = .openai
    @State private var apiKeys: [AIProvider: String] = [:]
    @State private var showingKey: [AIProvider: Bool] = [:]
    @State private var isSaving: Bool = false
    @State private var isTesting: Bool = false
    @State private var showSaveSuccess: Bool = false
    @State private var showSaveError: Bool = false
    @State private var showTestSuccess: Bool = false
    @State private var showTestError: Bool = false
    @State private var errorMessage: String = ""
    @State private var testLatency: Int? = nil
    @State private var showRemoveConfirmation: Bool = false
    @State private var providerToRemove: AIProvider? = nil
    @State private var showingProviderPicker: Bool = false
    @State private var showingModelPicker: Bool = false
    @State private var showingPredictionModelPicker: Bool = false
    @State private var pickerMode: ModelPickerMode = .chat
    
    // Custom provider state
    @State private var showingAddCustomProvider: Bool = false
    @State private var editingCustomProvider: CustomProviderConfig? = nil
    @State private var customProviderName: String = ""
    @State private var customProviderURL: String = ""
    @State private var customProviderModel: String = ""
    @State private var customProviderKey: String = ""
    @State private var customProviderDescription: String = ""
    @State private var isTestingCustom: Bool = false
    @State private var showCustomProviderRemoveConfirm: Bool = false
    @State private var customProviderToRemove: CustomProviderConfig? = nil
    
    // Web Search (Tavily) state
    @State private var tavilyKey: String = ""
    @State private var showingTavilyKey: Bool = false
    @State private var isSavingTavily: Bool = false
    @State private var isTestingTavily: Bool = false
    @State private var showTavilySaveSuccess: Bool = false
    @State private var showTavilyTestSuccess: Bool = false
    @State private var showTavilyError: Bool = false
    @State private var tavilyErrorMessage: String = ""
    
    enum ModelPickerMode {
        case chat
        case prediction
    }
    
    @Environment(\.dismiss) private var dismiss
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Premium Header
            headerView
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // How It Works - Quick explanation
                    howItWorksSection
                    
                    // Provider Status Overview
                    providerStatusSection
                    
                    // Model Selection - Now prominently placed before provider cards
                    modelSelectionSection
                    
                    // Provider API Keys Section
                    providerKeysSection
                    
                    // Web Search & AI Tools Section
                    webSearchToolsSection
                    
                    // Testing Guide
                    testingGuideSection
                    
                    // Features Section
                    featuresSection
                    
                    // Resources Section
                    resourcesSection
                    
                    // Footer
                    footerSection
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .scrollViewBackSwipeFix()
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .alert("API Key Saved", isPresented: $showSaveSuccess) {
            Button("OK", role: .cancel) {
                apiKeys[selectedProvider] = ""
            }
        } message: {
            Text("Your \(selectedProvider.displayName) API key has been saved securely.")
        }
        .alert("Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Connection Successful", isPresented: $showTestSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            if let latency = testLatency {
                Text("\(selectedProvider.displayName) connection verified.\nLatency: \(latency)ms")
            } else {
                Text("\(selectedProvider.displayName) connection verified.")
            }
        }
        .alert("Connection Failed", isPresented: $showTestError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog("Remove API Key", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let provider = providerToRemove {
                    removeAPIKey(for: provider)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let provider = providerToRemove {
                Text("Remove your \(provider.displayName) API key? You can add a new key at any time.")
            }
        }
        .sheet(isPresented: $showingModelPicker) {
            modelPickerSheet
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            CSNavButton(
                icon: "chevron.left",
                action: { dismiss() }
            )
            
            Spacer()
            
            Text("AI Providers")
                .font(.headline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Button("Done") {
                impactLight.impactOccurred()
                dismiss()
            }
            .font(.body.weight(.medium))
            .foregroundStyle(DS.Adaptive.gold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.Adaptive.background)
    }
    
    // MARK: - How It Works Section
    
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                Text("HOW THIS WORKS")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            .padding(.leading, 4)
            
            VStack(spacing: 0) {
                // Chat AI explanation
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "message.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chat AI")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.blue)
                        Text("Powers the AI Chat feature for conversations, questions, and analysis")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(12)
                
                Divider().background(DS.Adaptive.stroke)
                
                // Prediction AI explanation
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prediction AI")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.green)
                        Text("Powers price predictions and market forecasts (best with DeepSeek)")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(12)
                
                Divider().background(DS.Adaptive.stroke)
                
                // Local only note
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text("These settings only affect YOUR app. Other users are not affected.")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Spacer()
                }
                .padding(12)
                .background(DS.Adaptive.chipBackground.opacity(0.5))
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Provider Status Overview
    
    private var providerStatusSection: some View {
        let chatInfo = AIService.shared.chatProviderInfo
        let predictionInfo = AIService.shared.predictionProviderInfo
        let usingSameModel = !providerManager.useSeparatePredictionModel
        let configuredCount = AIProvider.allCases.filter { providerManager.hasValidKey(for: $0) }.count
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("ACTIVE CONFIGURATION")
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                // Chat Model Status
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "message.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chat")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        if chatInfo.provider != "None" {
                            HStack(spacing: 4) {
                                Text(chatInfo.provider)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.blue)
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                Text(chatInfo.model)
                                    .font(.caption)
                                    .foregroundColor(DS.Adaptive.textSecondary)
                            }
                        } else {
                            Text("No provider configured")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    Spacer()
                    
                    if chatInfo.provider != "None" {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                    }
                }
                .padding(14)
                
                Divider().background(DS.Adaptive.stroke)
                
                // Prediction Model Status
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(predictionInfo.isOptimized ? Color.green.opacity(0.15) : Color.yellow.opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 18))
                            .foregroundColor(predictionInfo.isOptimized ? .green : .yellow)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Predictions")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            if predictionInfo.isOptimized {
                                Text("OPTIMIZED")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.green.opacity(0.2)))
                            } else if usingSameModel && chatInfo.provider != "None" {
                                Text("SAME AS CHAT")
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(DS.Adaptive.chipBackground))
                            }
                        }
                        
                        if predictionInfo.provider != "None" {
                            HStack(spacing: 4) {
                                Text(predictionInfo.provider)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(predictionInfo.isOptimized ? .green : .yellow)
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                Text(predictionInfo.model)
                                    .font(.caption)
                                    .foregroundColor(DS.Adaptive.textSecondary)
                            }
                        } else {
                            Text("No provider configured")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    Spacer()
                    
                    if predictionInfo.provider != "None" {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                    }
                }
                .padding(14)
                
                // Recommendation hint
                if !predictionInfo.isOptimized && predictionInfo.provider != "None" {
                    Divider().background(DS.Adaptive.stroke)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                        
                        Text("Add DeepSeek for better crypto predictions (+116% in Alpha Arena)")
                            .font(.caption)
                            .foregroundColor(.yellow.opacity(0.9))
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.yellow.opacity(0.08))
                }
                
                Divider().background(DS.Adaptive.stroke)
                
                // Configured providers count
                HStack(spacing: 8) {
                    Image(systemName: configuredCount > 0 ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(configuredCount > 0 ? .green : .gray)
                    
                    Text("\(configuredCount) of \(AIProvider.allCases.count) providers configured")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Spacer()
                    
                    // Quick status indicators
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Circle()
                            .fill(providerManager.hasValidKey(for: provider) ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Provider Keys Section
    
    private var providerKeysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API KEYS")
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.leading, 4)
            
            Text("Add API keys for the providers you want to use. Each provider has different strengths.")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.horizontal, 4)
            
            // Built-in providers
            ForEach(AIProvider.allCases, id: \.self) { provider in
                providerCard(for: provider)
            }
            
            // Custom providers section
            customProvidersSection
        }
    }
    
    // MARK: - Custom Providers Section
    
    private var customProvidersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CUSTOM PROVIDERS")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Spacer()
                
                Button(action: {
                    impactLight.impactOccurred()
                    resetCustomProviderForm()
                    showingAddCustomProvider = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text("Add")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(BrandColors.goldBase)
                }
            }
            .padding(.leading, 4)
            
            Text("Add any OpenAI-compatible API endpoint, including local LLMs, custom servers, or other AI services.")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.horizontal, 4)
            
            // Existing custom providers
            if providerManager.customProviders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 28))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text("No custom providers")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Text("Add your own AI endpoint to use with CryptoSage")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                .foregroundColor(DS.Adaptive.stroke)
                        )
                )
            } else {
                ForEach(providerManager.customProviders) { customProvider in
                    customProviderCard(for: customProvider)
                }
            }
        }
        .sheet(isPresented: $showingAddCustomProvider) {
            customProviderSheet
        }
        .confirmationDialog("Remove Custom Provider", isPresented: $showCustomProviderRemoveConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let provider = customProviderToRemove {
                    providerManager.removeCustomProvider(id: provider.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let provider = customProviderToRemove {
                Text("Remove '\(provider.name)'? This will also remove the API key.")
            }
        }
    }
    
    private func customProviderCard(for customProvider: CustomProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Color.purple.opacity(0.2), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: customProvider.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.purple)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(customProvider.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("CUSTOM")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.2)))
                        
                        if providerManager.hasValidCustomProviderKey(id: customProvider.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                        }
                    }
                    
                    Text(customProvider.modelId)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
            }
            
            // Action buttons
            HStack(spacing: 10) {
                Button(action: {
                    impactLight.impactOccurred()
                    editingCustomProvider = customProvider
                    customProviderName = customProvider.name
                    customProviderURL = customProvider.baseURL
                    customProviderModel = customProvider.modelId
                    customProviderDescription = customProvider.description
                    customProviderKey = providerManager.getCustomProviderAPIKey(id: customProvider.id)
                    showingAddCustomProvider = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                        Text("Edit")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    impactMedium.impactOccurred()
                    customProviderToRemove = customProvider
                    showCustomProviderRemoveConfirm = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .frame(width: 36, height: 36)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(8)
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var customProviderSheet: some View {
        let isEditing = editingCustomProvider != nil
        let title = isEditing ? "Edit Custom Provider" : "Add Custom Provider"
        
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Info banner
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("OpenAI-Compatible Endpoint")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            Text("Works with any API that uses the OpenAI chat completions format (local LLMs, vLLM, Ollama, etc.)")
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textSecondary)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue.opacity(0.1))
                    )
                    
                    // Form fields
                    VStack(alignment: .leading, spacing: 16) {
                        // Name
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Provider Name")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textSecondary)
                            
                            TextField("e.g., My Local LLM", text: $customProviderName)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(DS.Adaptive.cardBackgroundElevated)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                )
                        }
                        
                        // Base URL
                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Endpoint URL")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textSecondary)
                            
                            TextField("e.g., http://localhost:8000/v1/chat/completions", text: $customProviderURL)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(DS.Adaptive.cardBackgroundElevated)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                )
                            
                            Text("Full URL including /v1/chat/completions if required")
                                .font(.caption2)
                                .foregroundColor(DS.Adaptive.textTertiary)
                            
                            // SECURITY: Warn if user enters a remote HTTP endpoint (API key sent in cleartext)
                            if customProviderURL.lowercased().hasPrefix("http://"),
                               !customProviderURL.lowercased().hasPrefix("http://localhost"),
                               !customProviderURL.lowercased().hasPrefix("http://127.0.0.1") {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("This URL uses HTTP (unencrypted). Your API key will be sent in plain text. Use HTTPS for remote servers.")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                .padding(.top, 2)
                            }
                        }
                        
                        // Model ID
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Model ID")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textSecondary)
                            
                            TextField("e.g., llama-3-70b, gpt-4, etc.", text: $customProviderModel)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(DS.Adaptive.cardBackgroundElevated)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                )
                            
                            Text("The model name to send in API requests")
                                .font(.caption2)
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                        
                        // API Key (optional)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("API Key")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                Text("(optional)")
                                    .font(.caption2)
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                            
                            SecureField("Leave empty if not required", text: $customProviderKey)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(DS.Adaptive.cardBackgroundElevated)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                )
                            
                            Text("Some local servers don't require an API key")
                                .font(.caption2)
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                        
                        // Description (optional)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Description")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                Text("(optional)")
                                    .font(.caption2)
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                            
                            TextField("Brief description", text: $customProviderDescription)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(DS.Adaptive.cardBackgroundElevated)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                )
                        }
                    }
                    
                    // Save button
                    Button(action: saveCustomProvider) {
                        HStack(spacing: 8) {
                            if isTestingCustom {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.black)
                            }
                            Text(isEditing ? "Update Provider" : "Add Provider")
                                .font(.headline.weight(.semibold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: canSaveCustomProvider 
                                    ? [BrandColors.goldBase, BrandColors.goldLight]
                                    : [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                    .disabled(!canSaveCustomProvider || isTestingCustom)
                    
                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingAddCustomProvider = false
                        resetCustomProviderForm()
                    }
                    .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    
    private var canSaveCustomProvider: Bool {
        !customProviderName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !customProviderURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !customProviderModel.trimmingCharacters(in: .whitespaces).isEmpty &&
        (customProviderURL.hasPrefix("http://") || customProviderURL.hasPrefix("https://"))
    }
    
    private func resetCustomProviderForm() {
        editingCustomProvider = nil
        customProviderName = ""
        customProviderURL = ""
        customProviderModel = ""
        customProviderKey = ""
        customProviderDescription = ""
    }
    
    private func saveCustomProvider() {
        let id = editingCustomProvider?.id ?? UUID().uuidString
        
        let config = CustomProviderConfig(
            id: id,
            name: customProviderName.trimmingCharacters(in: .whitespaces),
            baseURL: customProviderURL.trimmingCharacters(in: .whitespaces),
            modelId: customProviderModel.trimmingCharacters(in: .whitespaces),
            description: customProviderDescription.trimmingCharacters(in: .whitespaces)
        )
        
        providerManager.addCustomProvider(config)
        
        // Save API key if provided
        if !customProviderKey.isEmpty {
            try? providerManager.setCustomProviderAPIKey(customProviderKey, id: id)
        }
        
        notificationFeedback.notificationOccurred(.success)
        showingAddCustomProvider = false
        resetCustomProviderForm()
    }
    
    // MARK: - Provider Card
    
    private func providerCard(for provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Provider Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            provider == .deepseek
                                ? LinearGradient(colors: [Color.green.opacity(0.2), Color.green.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [DS.Adaptive.chipBackground, DS.Adaptive.chipBackground.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: provider.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(provider == .deepseek ? .green : BrandColors.goldBase)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        if provider == .deepseek {
                            Text("RECOMMENDED")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.2)))
                        }
                        
                        if providerManager.hasValidKey(for: provider) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                        }
                    }
                    
                    Text(provider.description)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
            }
            
            // API Key Input
            VStack(spacing: 10) {
                let key = apiKeys[provider] ?? ""
                let showKey = showingKey[provider] ?? false
                
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 14))
                        .foregroundColor(BrandColors.goldBase)
                        .frame(width: 20)
                    
                    if showKey {
                        TextField(provider.keyPrefix + "...", text: Binding(
                            get: { apiKeys[provider] ?? "" },
                            set: { apiKeys[provider] = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.caption, design: .monospaced))
                    } else {
                        SecureField(provider.keyPrefix + "...", text: Binding(
                            get: { apiKeys[provider] ?? "" },
                            set: { apiKeys[provider] = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                    
                    Button {
                        impactLight.impactOccurred()
                        showingKey[provider] = !(showingKey[provider] ?? false)
                    } label: {
                        Image(systemName: showKey ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.Adaptive.cardBackgroundElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            !key.isEmpty && !providerManager.isValidKeyFormat(key, for: provider)
                                ? Color.orange.opacity(0.5)
                                : DS.Adaptive.stroke,
                            lineWidth: 1
                        )
                )
                
                // Action Buttons
                HStack(spacing: 10) {
                    // Save Button
                    Button(action: { saveAPIKey(for: provider) }) {
                        HStack(spacing: 6) {
                            if isSaving && selectedProvider == provider {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(Color.black)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Text("Save")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: (key.isEmpty || !providerManager.isValidKeyFormat(key, for: provider))
                                    ? [Color.gray.opacity(0.3), Color.gray.opacity(0.2)]
                                    : [BrandColors.goldBase, BrandColors.goldLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
                    }
                    .disabled(key.isEmpty || isSaving || !providerManager.isValidKeyFormat(key, for: provider))
                    
                    // Test Button (only if key exists)
                    if providerManager.hasValidKey(for: provider) {
                        Button(action: { testConnection(for: provider) }) {
                            HStack(spacing: 6) {
                                if isTesting && selectedProvider == provider {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.system(size: 12))
                                }
                                Text("Test")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                        .disabled(isTesting)
                        
                        // Remove Button
                        Button(action: {
                            impactMedium.impactOccurred()
                            providerToRemove = provider
                            showRemoveConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                                .frame(width: 36, height: 36)
                                .background(Color.red.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }
                }
                
                // Get API Key Link
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption2)
                    Link("Get \(provider.displayName) API Key", destination: URL(string: provider.apiKeyURL) ?? URL(string: "https://google.com")!)
                        .font(.caption)
                }
                .foregroundColor(BrandColors.goldBase)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        provider == .deepseek ? Color.green.opacity(0.3) : DS.Adaptive.stroke,
                        lineWidth: provider == .deepseek ? 1.5 : 0.5
                    )
            )
        }
    }
    
    // MARK: - Model Selection
    
    private var modelSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header with explanation
            VStack(alignment: .leading, spacing: 4) {
                Text("CHOOSE YOUR AI MODELS")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .padding(.leading, 4)
                
                Text("Select which AI model powers each feature. You can use the same model for everything, or optimize predictions with a specialized model.")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .padding(.horizontal, 4)
            }
            
            // Chat AI Card
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                    Text("CHAT AI")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.blue)
                    Spacer()
                    Text("For conversations & analysis")
                        .font(.caption2)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
                
                // Chat Model Selection
                Button(action: {
                    impactLight.impactOccurred()
                    pickerMode = .chat
                    showingModelPicker = true
                }) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: providerManager.chatModel.provider.icon)
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(providerManager.chatModel.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            Text(providerManager.chatModel.provider.displayName)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        // Status indicator
                        if providerManager.hasValidKey(for: providerManager.chatModel.provider) {
                            HStack(spacing: 4) {
                                Text("Active")
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.green)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text("Add API Key Below")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                        }
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )
            
            // Prediction AI Card
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("PREDICTION AI")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.green)
                    Spacer()
                    Text("For price forecasts")
                        .font(.caption2)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
                
                // Optimize toggle
                Toggle(isOn: $providerManager.useSeparatePredictionModel) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Specialized Model")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text(providerManager.useSeparatePredictionModel 
                            ? "Using a separate model optimized for predictions" 
                            : "Currently using the same model as Chat")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .green))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                
                if providerManager.useSeparatePredictionModel {
                    Divider().background(DS.Adaptive.stroke).padding(.horizontal, 14)
                    
                    // Prediction Model Selection
                    Button(action: {
                        impactLight.impactOccurred()
                        pickerMode = .prediction
                        showingModelPicker = true
                    }) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.green.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: providerManager.predictionModel.provider.icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(.green)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(providerManager.predictionModel.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(DS.Adaptive.textPrimary)
                                    
                                    if providerManager.predictionModel.provider == .deepseek {
                                        Text("BEST")
                                            .font(.caption2.weight(.bold))
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.green.opacity(0.2)))
                                    }
                                }
                                Text(providerManager.predictionModel.provider.displayName)
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            
                            Spacer()
                            
                            // Status indicator
                            if providerManager.hasValidKey(for: providerManager.predictionModel.provider) {
                                HStack(spacing: 4) {
                                    Text("Active")
                                        .font(.caption2.weight(.medium))
                                        .foregroundColor(.green)
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.green)
                                }
                            } else {
                                Text("Add API Key Below")
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textTertiary)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Show what model is being used when toggle is off
                    HStack(spacing: 12) {
                        Image(systemName: "equal.circle")
                            .font(.system(size: 14))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text("Using: \(providerManager.chatModel.displayName) (\(providerManager.chatModel.provider.displayName))")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
            
            // Recommendation tip
            if !providerManager.useSeparatePredictionModel || providerManager.predictionModel.provider != .deepseek {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                    Text("Tip: DeepSeek outperforms other models for crypto predictions (+116% in benchmarks)")
                        .font(.caption)
                        .foregroundColor(.yellow.opacity(0.9))
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.yellow.opacity(0.1))
                )
            }
        }
    }
    
    // MARK: - Web Search & AI Tools Section
    
    private var webSearchToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack(spacing: 8) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.cyan)
                Text("WEB SEARCH & AI TOOLS")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            .padding(.leading, 4)
            
            // Status indicator
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
                Text("Web search is enabled")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 4)
            
            Text("AI can search the internet and read articles. Daily limits based on your subscription tier.")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.horizontal, 4)
            
            // Tier limits info
            VStack(alignment: .leading, spacing: 4) {
                tierLimitRow("Free", searches: 5, articles: 5)
                tierLimitRow("Pro", searches: 20, articles: 15)
                tierLimitRow("Premium", searches: 50, articles: 30)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.cyan.opacity(0.1))
            )
            .padding(.horizontal, 4)
            
            // Divider
            Rectangle()
                .fill(DS.Adaptive.stroke)
                .frame(height: 1)
                .padding(.vertical, 8)
            
            Text("Advanced: Add your own Tavily API key for unlimited searches (optional)")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.horizontal, 4)
            
            // Tavily API Key Card
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(colors: [Color.cyan.opacity(0.2), Color.cyan.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.cyan)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Tavily Search")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            if APIConfig.hasValidTavilyKey {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Text("AI-powered web search for real-time research")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                }
                
                // Benefits
                HStack(spacing: 8) {
                    benefitPill("Research topics", icon: "doc.text.magnifyingglass")
                    benefitPill("Read articles", icon: "newspaper")
                    benefitPill("Current events", icon: "clock")
                }
                .padding(.vertical, 4)
                
                // API Key Input
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.cyan)
                            .frame(width: 20)
                        
                        if showingTavilyKey {
                            TextField("tvly-...", text: $tavilyKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.caption, design: .monospaced))
                        } else {
                            SecureField("tvly-...", text: $tavilyKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        
                        Button {
                            impactLight.impactOccurred()
                            showingTavilyKey.toggle()
                        } label: {
                            Image(systemName: showingTavilyKey ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DS.Adaptive.cardBackgroundElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                !tavilyKey.isEmpty && !APIConfig.isValidTavilyKeyFormat(tavilyKey)
                                    ? Color.orange.opacity(0.5)
                                    : DS.Adaptive.stroke,
                                lineWidth: 1
                            )
                    )
                    
                    // Action Buttons
                    HStack(spacing: 10) {
                        // Save Button
                        Button(action: saveTavilyKey) {
                            HStack(spacing: 6) {
                                if isSavingTavily {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(Color.black)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                Text("Save")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: (tavilyKey.isEmpty || !APIConfig.isValidTavilyKeyFormat(tavilyKey))
                                        ? [Color.gray.opacity(0.3), Color.gray.opacity(0.2)]
                                        : [Color.cyan, Color.cyan.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(8)
                        }
                        .disabled(tavilyKey.isEmpty || isSavingTavily || !APIConfig.isValidTavilyKeyFormat(tavilyKey))
                        
                        // Test Button (only if key exists)
                        if APIConfig.hasValidTavilyKey {
                            Button(action: testTavilyConnection) {
                                HStack(spacing: 6) {
                                    if isTestingTavily {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                            .font(.system(size: 12))
                                    }
                                    Text("Test")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(8)
                            }
                            .disabled(isTestingTavily)
                            
                            // Remove Button
                            Button(action: removeTavilyKey) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .frame(width: 36, height: 36)
                                    .background(Color.red.opacity(0.15))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    
                    // Get API Key Link
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Link("Get Tavily API Key (1000 free/month)", destination: URL(string: "https://tavily.com") ?? URL(string: "https://google.com")!)
                            .font(.caption)
                    }
                    .foregroundColor(.cyan)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
            )
        }
        .alert("Tavily API Key Saved", isPresented: $showTavilySaveSuccess) {
            Button("OK", role: .cancel) {
                tavilyKey = ""
            }
        } message: {
            Text("Web search is now enabled. The AI can research topics on the internet.")
        }
        .alert("Web Search Test Successful", isPresented: $showTavilyTestSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Tavily API is working correctly. AI can now search the web.")
        }
        .alert("Tavily Error", isPresented: $showTavilyError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(tavilyErrorMessage)
        }
    }
    
    private func benefitPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.caption2)
        }
        .foregroundColor(.cyan)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.cyan.opacity(0.15)))
    }
    
    private func tierLimitRow(_ tier: String, searches: Int, articles: Int) -> some View {
        HStack {
            Text(tier)
                .font(.caption.weight(.medium))
                .foregroundColor(DS.Adaptive.textPrimary)
                .frame(width: 60, alignment: .leading)
            Text("\(searches) searches/day")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
            Text("\(articles) articles/day")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
        }
    }
    
    private func saveTavilyKey() {
        guard !tavilyKey.isEmpty else { return }
        isSavingTavily = true
        
        Task {
            do {
                try APIConfig.setTavilyAPIKey(tavilyKey)
                await MainActor.run {
                    isSavingTavily = false
                    notificationFeedback.notificationOccurred(.success)
                    showTavilySaveSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSavingTavily = false
                    tavilyErrorMessage = "Failed to save API key: \(error.localizedDescription)"
                    notificationFeedback.notificationOccurred(.error)
                    showTavilyError = true
                }
            }
        }
    }
    
    private func testTavilyConnection() {
        isTestingTavily = true
        
        Task {
            do {
                // Perform a simple test search
                let result = try await TavilyService.shared.search(query: "bitcoin price", maxResults: 1)
                
                await MainActor.run {
                    isTestingTavily = false
                    if result.results.isEmpty && result.answer == nil {
                        tavilyErrorMessage = "Search returned no results"
                        notificationFeedback.notificationOccurred(.warning)
                        showTavilyError = true
                    } else {
                        notificationFeedback.notificationOccurred(.success)
                        showTavilyTestSuccess = true
                    }
                }
            } catch {
                await MainActor.run {
                    isTestingTavily = false
                    tavilyErrorMessage = error.localizedDescription
                    notificationFeedback.notificationOccurred(.error)
                    showTavilyError = true
                }
            }
        }
    }
    
    private func removeTavilyKey() {
        impactMedium.impactOccurred()
        APIConfig.removeTavilyAPIKey()
        tavilyKey = ""
        notificationFeedback.notificationOccurred(.success)
    }
    
    // MARK: - Testing Guide Section
    
    private var testingGuideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 12))
                    .foregroundColor(.cyan)
                Text("TESTING GUIDE")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            .padding(.leading, 4)
            
            VStack(spacing: 0) {
                // Step 1
                TestingStepRow(
                    step: 1,
                    title: "Get a DeepSeek API Key",
                    subtitle: "Sign up at platform.deepseek.com (starts with free credits)",
                    icon: "key.fill",
                    color: .green
                )
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                
                // Step 2
                TestingStepRow(
                    step: 2,
                    title: "Add Key Above",
                    subtitle: "Paste your DeepSeek key in the API Keys section",
                    icon: "plus.circle.fill",
                    color: .blue
                )
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                
                // Step 3
                TestingStepRow(
                    step: 3,
                    title: "Test Connection",
                    subtitle: "Tap 'Test' to verify the key works",
                    icon: "antenna.radiowaves.left.and.right",
                    color: .purple
                )
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                
                // Step 4
                TestingStepRow(
                    step: 4,
                    title: "Try Price Predictions",
                    subtitle: "Go to any coin and tap the prediction button to test",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .orange
                )
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                
                // Important note
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.cyan)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Developer Testing Only")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text("These settings only affect YOUR app. Other users continue using the Firebase backend until you decide to roll out changes.")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
                .padding(14)
                .background(Color.cyan.opacity(0.08))
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Features Section
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROVIDER CAPABILITIES")
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "DeepSeek - Predictions", subtitle: "Best crypto prediction accuracy (+116%)", color: .green)
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                FeatureRow(icon: "message.fill", title: "OpenAI - Chat", subtitle: "Best conversational experience", color: .blue)
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                FeatureRow(icon: "bolt.fill", title: "Grok - Real-time", subtitle: "Access to real-time market data", color: .purple)
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                FeatureRow(icon: "arrow.triangle.branch", title: "OpenRouter - Multi-model", subtitle: "Access 500+ models via one API", color: .orange)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Resources Section
    
    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RESOURCES")
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textSecondary)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                ResourceLink(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "DeepSeek API",
                    subtitle: "Recommended for crypto predictions",
                    color: .green,
                    url: "https://platform.deepseek.com"
                )
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                
                ResourceLink(
                    icon: "brain.head.profile",
                    title: "OpenAI API",
                    subtitle: "Powers CryptoSage AI chat",
                    color: .blue,
                    url: "https://platform.openai.com"
                )
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                
                ResourceLink(
                    icon: "bolt.fill",
                    title: "Grok API (xAI)",
                    subtitle: "Real-time data access",
                    color: .purple,
                    url: "https://x.ai/api"
                )
                
                Divider().background(DS.Adaptive.stroke).padding(.leading, 56)
                
                ResourceLink(
                    icon: "arrow.triangle.branch",
                    title: "OpenRouter",
                    subtitle: "Unified API for 500+ models",
                    color: .orange,
                    url: "https://openrouter.ai"
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Footer
    
    private var footerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [BrandColors.goldBase.opacity(0.2), BrandColors.goldBase.opacity(0)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "brain")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldBase, BrandColors.goldLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Multi-Provider AI")
                .font(.subheadline.weight(.medium))
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Text("API keys are stored securely on-device using Apple Keychain encryption.")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
    
    // MARK: - Model Picker Sheet
    
    private var modelPickerSheet: some View {
        let isChat = pickerMode == .chat
        let currentModel = isChat ? providerManager.chatModel : providerManager.predictionModel
        let title = isChat ? "Select Chat Model" : "Select Prediction Model"
        let accentColor = isChat ? Color.blue : Color.green
        
        return NavigationStack {
            List {
                // Recommendation header for prediction mode
                if !isChat {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.yellow)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("DeepSeek Recommended")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                Text("Alpha Arena winner: +116% crypto trading return")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.green.opacity(0.1))
                }
                
                // Group models by provider
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    let modelsForProvider = AIModelConfig.allModels.filter { $0.provider == provider }
                    let hasKey = providerManager.hasValidKey(for: provider)
                    
                    Section(header: providerSectionHeader(provider: provider, hasKey: hasKey)) {
                        ForEach(modelsForProvider, id: \.id) { model in
                            Button(action: {
                                if hasKey {
                                    impactLight.impactOccurred()
                                    if isChat {
                                        providerManager.chatModel = model
                                    } else {
                                        providerManager.predictionModel = model
                                    }
                                    showingModelPicker = false
                                }
                            }) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(model.id == currentModel.id
                                                ? LinearGradient(
                                                    colors: [accentColor.opacity(0.2), accentColor.opacity(0.1)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                  )
                                                : LinearGradient(
                                                    colors: [DS.Adaptive.chipBackground, DS.Adaptive.chipBackground.opacity(0.5)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                  )
                                            )
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: provider.icon)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(model.id == currentModel.id ? accentColor : DS.Adaptive.textSecondary)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(model.displayName)
                                                .font(.body.weight(.medium))
                                                .foregroundColor(hasKey ? DS.Adaptive.textPrimary : DS.Adaptive.textTertiary)
                                            
                                            if model.tier == .premium {
                                                Text("Premium")
                                                    .font(.caption2.weight(.medium))
                                                    .foregroundColor(BrandColors.goldBase)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(Capsule().fill(BrandColors.goldBase.opacity(0.15)))
                                            }
                                        }
                                        
                                        Text(model.description)
                                            .font(.caption)
                                            .foregroundColor(DS.Adaptive.textSecondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    if model.id == currentModel.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(accentColor)
                                    }
                                }
                                .padding(.vertical, 2)
                                .opacity(hasKey ? 1 : 0.5)
                            }
                            .listRowBackground(Color.clear)
                            .disabled(!hasKey)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingModelPicker = false
                    }
                    .foregroundColor(BrandColors.goldBase)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    
    private func providerSectionHeader(provider: AIProvider, hasKey: Bool) -> some View {
        HStack(spacing: 6) {
            Text(provider.displayName.uppercased())
                .font(.caption.weight(.semibold))
            
            if hasKey {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            } else {
                Text("NOT CONFIGURED")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .foregroundColor(DS.Adaptive.textSecondary)
    }
    
    // MARK: - Actions
    
    private func saveAPIKey(for provider: AIProvider) {
        selectedProvider = provider
        isSaving = true
        impactMedium.impactOccurred()
        
        let trimmedKey = (apiKeys[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do {
                try providerManager.setAPIKey(trimmedKey, for: provider)
                
                // Apply smart defaults based on provider
                applySmartDefaults(for: provider)
                
                isSaving = false
                notificationFeedback.notificationOccurred(.success)
                showSaveSuccess = true
            } catch {
                isSaving = false
                notificationFeedback.notificationOccurred(.error)
                errorMessage = "Failed to save API key: \(error.localizedDescription)"
                showSaveError = true
            }
        }
    }
    
    /// Apply smart defaults when an API key is added
    /// DeepSeek = predictions only, OpenAI = chat, user controls everything via settings
    private func applySmartDefaults(for provider: AIProvider) {
        switch provider {
        case .deepseek:
            // DeepSeek is ONLY for predictions - never touch chat settings
            // Auto-enable optimize predictions and set DeepSeek as the prediction model
            providerManager.useSeparatePredictionModel = true
            providerManager.predictionModel = .deepseekChat
            // Chat stays as whatever it was (OpenAI or whatever user chose)
            
        case .openai:
            // OpenAI is for chat - set as chat model
            providerManager.chatModel = .gpt4oMini
            // Don't touch prediction settings - user controls that with the toggle
            
        case .grok:
            // Grok - only set as chat if user explicitly adds it and has no OpenAI
            if !providerManager.hasValidKey(for: .openai) {
                providerManager.chatModel = .grok4Fast
            }
            
        case .openrouter:
            // OpenRouter - only set as chat if nothing else configured
            if !providerManager.hasValidKey(for: .openai) && !providerManager.hasValidKey(for: .grok) {
                providerManager.chatModel = .openrouterDeepseek
            }
        }
    }
    
    private func removeAPIKey(for provider: AIProvider) {
        impactMedium.impactOccurred()
        providerManager.removeAPIKey(for: provider)
        apiKeys[provider] = ""
        notificationFeedback.notificationOccurred(.success)
    }
    
    private func testConnection(for provider: AIProvider) {
        selectedProvider = provider
        isTesting = true
        impactLight.impactOccurred()
        
        let startTime = Date()
        
        // Actually test the API connection
        Task {
            do {
                // Send a minimal test request
                let _ = try await AIService.shared.sendMessageWithProvider(
                    "Say 'connected' in exactly one word",
                    systemPrompt: "You are a connection test. Respond with exactly one word: 'connected'",
                    provider: provider,
                    maxTokens: 10
                )
                
                let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                
                await MainActor.run {
                    testLatency = elapsed
                    isTesting = false
                    notificationFeedback.notificationOccurred(.success)
                    showTestSuccess = true
                }
            } catch {
                let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                
                await MainActor.run {
                    testLatency = elapsed
                    isTesting = false
                    notificationFeedback.notificationOccurred(.error)
                    
                    // Parse error message for user-friendly display
                    if let providerError = error as? AIProviderError {
                        errorMessage = providerError.localizedDescription
                    } else if let aiError = error as? AIServiceError {
                        errorMessage = aiError.localizedDescription
                    } else {
                        errorMessage = "Connection failed: \(error.localizedDescription)"
                    }
                    
                    showTestError = true
                }
            }
        }
    }
}

// MARK: - Helper Views

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
        }
        .padding(14)
    }
}

private struct ResourceLink: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let url: String
    
    var body: some View {
        Link(destination: URL(string: url) ?? URL(string: "https://google.com")!) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(14)
        }
    }
}

private struct TestingStepRow: View {
    let step: Int
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                VStack(spacing: 0) {
                    Text("\(step)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(color)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color.opacity(0.6))
        }
        .padding(14)
    }
}

// MARK: - Preview

#Preview {
    AISettingsView()
        .preferredColorScheme(.dark)
}
