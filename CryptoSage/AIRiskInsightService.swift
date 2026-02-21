//
//  AIRiskInsightService.swift
//  CryptoSage
//
//  AI-powered risk analysis recommendations using OpenAI/Firebase backend.
//  Generates personalized, actionable risk management advice based on portfolio metrics.
//

import Foundation

/// Represents AI-generated risk recommendations
public struct AIRiskRecommendation: Codable, Identifiable {
    public let id: UUID
    public let text: String
    public let category: RiskCategory
    public let priority: Int // 1 = highest priority
    
    public init(text: String, category: RiskCategory, priority: Int) {
        self.id = UUID()
        self.text = text
        self.category = category
        self.priority = priority
    }
    
    public enum RiskCategory: String, Codable {
        case concentration
        case diversification
        case volatility
        case drawdown
        case liquidity
        case general
    }
}

/// Complete AI risk analysis result
public struct AIRiskAnalysis: Codable {
    public let summary: String
    public let recommendations: [AIRiskRecommendation]
    public let timestamp: Date
    
    public init(summary: String, recommendations: [AIRiskRecommendation], timestamp: Date = Date()) {
        self.summary = summary
        self.recommendations = recommendations
        self.timestamp = timestamp
    }
}

/// Error types for AIRiskInsightService
enum AIRiskInsightError: LocalizedError {
    case noPortfolioData
    case aiServiceFailed(String)
    case firebaseError(String)
    case authenticationRequired
    case parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .noPortfolioData:
            return "No portfolio data available for risk analysis"
        case .aiServiceFailed(let message):
            return "AI service error: \(message)"
        case .firebaseError(let message):
            return "Server error: \(message)"
        case .authenticationRequired:
            return "Sign in to get AI-powered risk recommendations"
        case .parsingFailed:
            return "Failed to parse AI response"
        }
    }
}

/// Service responsible for generating AI-powered risk recommendations
@MainActor
final class AIRiskInsightService {
    static let shared = AIRiskInsightService()
    
    // MARK: - Cache Keys
    private let cacheAnalysisKey = "AIRiskInsightService.cachedAnalysis"
    private let cacheTimestampKey = "AIRiskInsightService.cacheTimestamp"
    private let lastRequestKey = "AIRiskInsightService.lastRequestTimestamp"
    
    // MARK: - Cache
    private var cachedAnalysis: AIRiskAnalysis?
    private var cacheTimestamp: Date?
    // Risk analysis can be cached longer since portfolio changes infrequently
    private let cacheValiditySeconds: TimeInterval = 4 * 3600 // 4 hours
    
    // MARK: - Cooldown
    private var lastRequestTimestamp: Date?
    private let minimumCooldownSeconds: TimeInterval = 30 * 60 // 30 minutes
    
    private init() {
        loadCacheFromDisk()
    }
    
    // MARK: - Cache Persistence
    
    private func loadCacheFromDisk() {
        let defaults = UserDefaults.standard
        
        if let data = defaults.data(forKey: cacheAnalysisKey) {
            do {
                cachedAnalysis = try JSONDecoder().decode(AIRiskAnalysis.self, from: data)
            } catch {
                print("[AIRiskInsightService] Failed to load cached analysis: \(error)")
            }
        }
        
        cacheTimestamp = defaults.object(forKey: cacheTimestampKey) as? Date
        lastRequestTimestamp = defaults.object(forKey: lastRequestKey) as? Date
        
        // Validate cache freshness
        if let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) >= cacheValiditySeconds {
            cachedAnalysis = nil
            cacheTimestamp = nil
        }
        
        #if DEBUG
        if cachedAnalysis != nil {
            print("[AIRiskInsightService] Loaded cached risk analysis from disk")
        }
        #endif
    }
    
    private func saveCacheToDisk() {
        let defaults = UserDefaults.standard
        
        if let analysis = cachedAnalysis {
            do {
                let data = try JSONEncoder().encode(analysis)
                defaults.set(data, forKey: cacheAnalysisKey)
            } catch {
                print("[AIRiskInsightService] Failed to save cached analysis: \(error)")
            }
        } else {
            defaults.removeObject(forKey: cacheAnalysisKey)
        }
        
        defaults.set(cacheTimestamp, forKey: cacheTimestampKey)
        defaults.set(lastRequestTimestamp, forKey: lastRequestKey)
    }
    
    // MARK: - Public API
    
    /// Generate AI-powered risk recommendations based on scan result and portfolio
    /// - Parameters:
    ///   - scanResult: The algorithmic risk scan result
    ///   - portfolioVM: The portfolio view model for context
    /// - Returns: AI-generated risk analysis with recommendations
    func generateAnalysis(
        for scanResult: RiskScanResult,
        portfolioVM: PortfolioViewModel
    ) async throws -> AIRiskAnalysis {
        // Check cache first
        if let cached = cachedAnalysis,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
            // Track cache hit
            AnalyticsService.shared.trackAIFeatureUsage(
                feature: .riskAnalysis,
                model: "gpt-4o-mini",
                maxTokens: 512,
                tier: SubscriptionManager.shared.effectiveTier,
                cached: true
            )
            return cached
        }
        
        // Cooldown check
        if !SubscriptionManager.shared.isDeveloperMode {
            if let lastRequest = lastRequestTimestamp,
               Date().timeIntervalSince(lastRequest) < minimumCooldownSeconds {
                AnalyticsService.shared.trackAICooldownTriggered(
                    feature: .riskAnalysis,
                    tier: SubscriptionManager.shared.effectiveTier
                )
                if let cached = cachedAnalysis {
                    return cached
                }
                throw AIRiskInsightError.aiServiceFailed("Please wait before refreshing again")
            }
        }
        
        // Build the context
        let prompt = buildPrompt(scanResult: scanResult, portfolioVM: portfolioVM)
        
        // Try Firebase first for authenticated users
        if FirebaseService.shared.useFirebaseForAI,
           AuthenticationManager.shared.isAuthenticated {
            do {
                let analysis = try await fetchViaFirebase(
                    scanResult: scanResult,
                    portfolioVM: portfolioVM
                )
                return analysis
            } catch FirebaseServiceError.authenticationRequired {
                print("[AIRiskInsightService] Firebase auth required, falling back to direct API")
            } catch {
                print("[AIRiskInsightService] Firebase error: \(error.localizedDescription), falling back to direct API")
            }
        }
        
        // Fallback: Direct OpenAI call
        guard APIConfig.hasValidOpenAIKey else {
            // Generate fallback recommendations without AI
            let fallback = generateFallbackAnalysis(scanResult: scanResult)
            cachedAnalysis = fallback
            cacheTimestamp = Date()
            saveCacheToDisk()
            return fallback
        }
        
        // Call AI service
        do {
            let systemPrompt = """
            You are a crypto portfolio risk advisor. Analyze the risk metrics and provide actionable recommendations.
            
            Rules:
            - Be specific and mention actual coins when relevant
            - Give concrete actions (buy, sell, rebalance, add stablecoins, etc.)
            - Keep each recommendation to 1-2 sentences
            - Prioritize the most impactful changes first
            - Consider current market conditions
            
            Response format (JSON):
            {
                "summary": "One sentence overall assessment",
                "recommendations": [
                    {"text": "recommendation text", "category": "concentration|diversification|volatility|drawdown|liquidity|general", "priority": 1}
                ]
            }
            """
            
            let response = try await AIService.shared.sendMessage(
                prompt,
                systemPrompt: systemPrompt,
                usePremiumModel: false,
                includeTools: false,
                isAutomatedFeature: false, // Use Firebase backend for all users
                maxTokens: 512
            )
            
            // Parse JSON response
            let analysis = try parseAIResponse(response)
            
            // Cache and persist
            cachedAnalysis = analysis
            cacheTimestamp = Date()
            lastRequestTimestamp = Date()
            saveCacheToDisk()
            
            // Track usage
            AnalyticsService.shared.trackAIFeatureUsage(
                feature: .riskAnalysis,
                model: "gpt-4o-mini",
                maxTokens: 512,
                tier: SubscriptionManager.shared.effectiveTier,
                cached: false
            )
            
            return analysis
        } catch {
            throw AIRiskInsightError.aiServiceFailed(error.localizedDescription)
        }
    }
    
    /// Clear the cached analysis
    func clearCache() {
        cachedAnalysis = nil
        cacheTimestamp = nil
        lastRequestTimestamp = nil
        saveCacheToDisk()
    }
    
    /// Check if we have a cached analysis
    var hasCachedAnalysis: Bool {
        cachedAnalysis != nil
    }
    
    // MARK: - Firebase Backend (Not Yet Implemented)
    
    /// Firebase risk analysis function - throws error to fall back to direct API
    /// TODO: Implement Firebase function "getRiskAnalysis" for server-side caching
    private func fetchViaFirebase(
        scanResult: RiskScanResult,
        portfolioVM: PortfolioViewModel
    ) async throws -> AIRiskAnalysis {
        // Firebase risk analysis function not yet deployed
        // Throw error to fall back to direct OpenAI API
        throw AIRiskInsightError.firebaseError("Risk analysis function not available")
    }
    
    // MARK: - Private Helpers
    
    private func buildPrompt(scanResult: RiskScanResult, portfolioVM: PortfolioViewModel) -> String {
        var parts: [String] = []
        
        // Risk score summary
        parts.append("Risk Score: \(scanResult.score)/100 (\(scanResult.level.rawValue))")
        
        // Metrics
        let m = scanResult.metrics
        parts.append("""
        Metrics:
        - Top Holding Weight: \(String(format: "%.1f", m.topWeight * 100))%
        - HHI (concentration): \(String(format: "%.2f", m.hhi))
        - Stablecoin Allocation: \(String(format: "%.1f", m.stablecoinWeight * 100))%
        - Portfolio Volatility: \(String(format: "%.1f", m.volatility * 100))%
        - Max Drawdown: \(String(format: "%.1f", m.maxDrawdown * 100))%
        - Illiquid Assets: \(m.illiquidCount)
        """)
        
        // Holdings
        let holdings = portfolioVM.holdings.sorted { $0.currentValue > $1.currentValue }
        let totalValue = portfolioVM.totalValue
        
        if !holdings.isEmpty && totalValue > 0 {
            let holdingsList = holdings.prefix(8).map { h -> String in
                let pct = (h.currentValue / totalValue) * 100
                return "\(h.coinSymbol): \(String(format: "%.1f", pct))%"
            }.joined(separator: ", ")
            parts.append("Holdings: \(holdingsList)")
        }
        
        // Market context
        let marketVM = MarketViewModel.shared
        if let btcDom = marketVM.btcDominance {
            parts.append("BTC Dominance: \(String(format: "%.1f", btcDom))%")
        }
        
        // Existing highlights
        if !scanResult.highlights.isEmpty {
            let highlightsList = scanResult.highlights.map { "\($0.title) (\($0.severity.rawValue))" }.joined(separator: ", ")
            parts.append("Identified Issues: \(highlightsList)")
        }
        
        parts.append("\nProvide 3-4 specific, actionable recommendations to improve this portfolio's risk profile.")
        
        return parts.joined(separator: "\n")
    }
    
    private func parseAIResponse(_ response: String) throws -> AIRiskAnalysis {
        // Try to extract JSON from response
        var jsonString = response
        
        // Handle markdown code blocks
        // SAFETY: Use half-open range to prevent String index out of bounds crash
        if let jsonStart = response.range(of: "{"),
           let jsonEnd = response.range(of: "}", options: .backwards),
           jsonStart.lowerBound < jsonEnd.upperBound {
            jsonString = String(response[jsonStart.lowerBound..<jsonEnd.upperBound])
        }
        
        guard let data = jsonString.data(using: .utf8) else {
            throw AIRiskInsightError.parsingFailed
        }
        
        do {
            let decoded = try JSONDecoder().decode(AIResponseFormat.self, from: data)
            
            let recommendations = decoded.recommendations.enumerated().map { index, rec in
                AIRiskRecommendation(
                    text: rec.text,
                    category: AIRiskRecommendation.RiskCategory(rawValue: rec.category) ?? .general,
                    priority: rec.priority ?? (index + 1)
                )
            }
            
            return AIRiskAnalysis(
                summary: decoded.summary,
                recommendations: recommendations
            )
        } catch {
            // Fallback: treat entire response as summary with no structured recommendations
            return AIRiskAnalysis(
                summary: response,
                recommendations: []
            )
        }
    }
    
    /// Generate fallback recommendations when AI is unavailable
    private func generateFallbackAnalysis(scanResult: RiskScanResult) -> AIRiskAnalysis {
        var recommendations: [AIRiskRecommendation] = []
        let m = scanResult.metrics
        
        // Generate recommendations based on metrics
        if m.topWeight > 0.35 {
            recommendations.append(AIRiskRecommendation(
                text: "Your largest holding represents \(String(format: "%.0f", m.topWeight * 100))% of your portfolio. Consider trimming to reduce concentration risk.",
                category: .concentration,
                priority: 1
            ))
        }
        
        if m.stablecoinWeight < 0.1 && scanResult.score > 40 {
            recommendations.append(AIRiskRecommendation(
                text: "Adding 10-20% stablecoins can help reduce overall portfolio volatility and provide dry powder for opportunities.",
                category: .volatility,
                priority: 2
            ))
        }
        
        if m.hhi > 0.25 {
            recommendations.append(AIRiskRecommendation(
                text: "Your portfolio is highly concentrated (HHI: \(String(format: "%.2f", m.hhi))). Consider spreading across more assets to improve diversification.",
                category: .diversification,
                priority: 3
            ))
        }
        
        if m.volatility > 0.03 {
            recommendations.append(AIRiskRecommendation(
                text: "Portfolio volatility is elevated at \(String(format: "%.1f", m.volatility * 100))%. Consider rebalancing toward more stable assets.",
                category: .volatility,
                priority: 4
            ))
        }
        
        if m.illiquidCount > 0 {
            recommendations.append(AIRiskRecommendation(
                text: "\(m.illiquidCount) holding(s) have low trading volume. Ensure you have an exit strategy for these positions.",
                category: .liquidity,
                priority: 5
            ))
        }
        
        // Default recommendation if portfolio looks healthy
        if recommendations.isEmpty {
            recommendations.append(AIRiskRecommendation(
                text: "Your portfolio risk metrics look healthy. Continue monitoring and rebalance periodically to maintain your target allocation.",
                category: .general,
                priority: 1
            ))
        }
        
        // Generate summary
        let summary: String
        switch scanResult.level {
        case .low:
            summary = "Your portfolio has low risk exposure with well-balanced allocations."
        case .medium:
            summary = "Some risk factors need attention, but overall exposure is manageable."
        case .high:
            summary = "Your portfolio has significant risk exposure. Consider the recommendations below."
        }
        
        return AIRiskAnalysis(
            summary: summary,
            recommendations: recommendations
        )
    }
}

// MARK: - Response Parsing Types

private struct AIResponseFormat: Codable {
    let summary: String
    let recommendations: [RecommendationFormat]
    
    struct RecommendationFormat: Codable {
        let text: String
        let category: String
        let priority: Int?
    }
}


