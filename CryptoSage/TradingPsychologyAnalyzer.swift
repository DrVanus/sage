//
//  TradingPsychologyAnalyzer.swift
//  CryptoSage
//
//  Trading Psychology Analyzer — Detects behavioral biases,
//  emotional state of the market, and provides psychology-aware
//  trading guidance.
//

import Foundation
import Combine

// MARK: - Psychology Analysis

public struct PsychologyAnalysis: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let overallSentiment: MarketMood
    public let emotionalCycle: EmotionalCyclePhase
    public let biasWarnings: [BiasWarning]
    public let contrarianSignal: ContrarianSignal
    public let tradingGuidance: [PsychologyGuidance]
    public let compositeScore: Double  // -100 (extreme fear) to +100 (extreme greed)
}

// MARK: - Market Mood

public enum MarketMood: String, CaseIterable {
    case euphoria = "Euphoria"
    case greed = "Greed"
    case optimism = "Optimism"
    case hope = "Hope"
    case neutral = "Neutral"
    case anxiety = "Anxiety"
    case fear = "Fear"
    case panic = "Panic"
    case capitulation = "Capitulation"
    case depression = "Depression"

    public var icon: String {
        switch self {
        case .euphoria:     return "star.circle.fill"
        case .greed:        return "dollarsign.circle.fill"
        case .optimism:     return "sun.max.fill"
        case .hope:         return "sunrise.fill"
        case .neutral:      return "minus.circle.fill"
        case .anxiety:      return "exclamationmark.circle.fill"
        case .fear:         return "exclamationmark.triangle.fill"
        case .panic:        return "bolt.circle.fill"
        case .capitulation: return "flag.circle.fill"
        case .depression:   return "cloud.rain.fill"
        }
    }

    public var description: String {
        switch self {
        case .euphoria:     return "Everyone is making money. Top is near."
        case .greed:        return "Strong risk appetite. Be cautious with new positions."
        case .optimism:     return "Healthy bullish sentiment. Good for trends."
        case .hope:         return "Recovery emerging from fear. Early bullish signal."
        case .neutral:      return "Mixed signals. Wait for clarity."
        case .anxiety:      return "Growing uncertainty. Tighten risk management."
        case .fear:         return "Market is afraid. Contrarian buying opportunity."
        case .panic:        return "Selling climax possible. Extreme contrarian opportunity."
        case .capitulation: return "Everyone is selling. Historic buying opportunity."
        case .depression:   return "Market bottoming. Accumulation phase."
        }
    }

    public var contrarianScore: Double {
        switch self {
        case .euphoria:     return -90
        case .greed:        return -60
        case .optimism:     return -20
        case .hope:         return 20
        case .neutral:      return 0
        case .anxiety:      return 10
        case .fear:         return 40
        case .panic:        return 70
        case .capitulation: return 90
        case .depression:   return 60
        }
    }
}

// MARK: - Emotional Cycle Phase

public enum EmotionalCyclePhase: String, CaseIterable {
    case disbelief = "Disbelief"
    case hope = "Hope"
    case belief = "Belief"
    case thrill = "Thrill"
    case euphoria = "Euphoria"
    case complacency = "Complacency"
    case anxiety = "Anxiety"
    case denial = "Denial"
    case panic = "Panic"
    case capitulation = "Capitulation"
    case anger = "Anger"
    case depression = "Depression"

    public var marketPhase: String {
        switch self {
        case .disbelief, .hope:               return "Early Bull"
        case .belief, .thrill:                return "Mid Bull"
        case .euphoria:                       return "Late Bull (Top)"
        case .complacency, .anxiety, .denial: return "Early Bear"
        case .panic, .capitulation:           return "Late Bear (Bottom)"
        case .anger, .depression:             return "Bear Bottom"
        }
    }

    public var investmentImplication: String {
        switch self {
        case .disbelief:    return "Best time to buy. Nobody believes the rally."
        case .hope:         return "Accumulate. Smart money is entering."
        case .belief:       return "Hold and add. Trend is established."
        case .thrill:       return "Begin taking profits. Set trailing stops."
        case .euphoria:     return "Take significant profits. This is the top signal."
        case .complacency:  return "Reduce positions. The trend has changed."
        case .anxiety:      return "Move to defensive positions."
        case .denial:       return "Cut losses. Do not average down yet."
        case .panic:        return "Hold cash. Wait for capitulation."
        case .capitulation: return "Begin accumulating. The bottom is forming."
        case .anger:        return "Continue DCA. Patience will be rewarded."
        case .depression:   return "Maximum accumulation phase. Best prices."
        }
    }
}

// MARK: - Bias Warning

public struct BiasWarning: Identifiable {
    public let id = UUID()
    public let bias: CognitiveBias
    public let severity: BiasSeverity
    public let description: String
    public let mitigation: String
}

public enum CognitiveBias: String, CaseIterable {
    case fomo = "FOMO"
    case recencyBias = "Recency Bias"
    case confirmationBias = "Confirmation Bias"
    case anchoringBias = "Anchoring Bias"
    case lossAversion = "Loss Aversion"
    case overconfidence = "Overconfidence"
    case herdMentality = "Herd Mentality"
    case sunkCostFallacy = "Sunk Cost Fallacy"
}

public enum BiasSeverity: String {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

// MARK: - Contrarian Signal

public struct ContrarianSignal {
    public let direction: String
    public let strength: Double
    public let reasoning: String
}

// MARK: - Psychology Guidance

public struct PsychologyGuidance: Identifiable {
    public let id = UUID()
    public let title: String
    public let guidance: String
    public let icon: String
    public let priority: Int
}

// MARK: - Trading Psychology Analyzer

@MainActor
public final class TradingPsychologyAnalyzer: ObservableObject {

    public static let shared = TradingPsychologyAnalyzer()

    @Published public var currentAnalysis: PsychologyAnalysis?
    @Published public var isAnalyzing: Bool = false

    private init() {}

    // MARK: - Analyze

    public func analyze(
        fearGreedValue: Int,
        priceChange24h: Double,
        priceChange7d: Double,
        priceChange30d: Double,
        volatility: Double,
        volume24hChange: Double
    ) -> PsychologyAnalysis {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let mood = determineMood(fearGreed: fearGreedValue, change24h: priceChange24h, change7d: priceChange7d)
        let phase = determinePhase(fearGreed: fearGreedValue, change7d: priceChange7d, change30d: priceChange30d, volume24hChange: volume24hChange)
        let biases = detectBiases(fearGreed: fearGreedValue, mood: mood, change24h: priceChange24h, change7d: priceChange7d, volatility: volatility, volume24hChange: volume24hChange)
        let contrarian = generateContrarian(fearGreed: fearGreedValue, mood: mood, phase: phase)
        let guidance = generateGuidance(mood: mood, phase: phase, biases: biases, contrarian: contrarian)
        let composite = Double(fearGreedValue - 50) * 1.2 + mood.contrarianScore * 0.4

        let analysis = PsychologyAnalysis(
            timestamp: Date(), overallSentiment: mood, emotionalCycle: phase,
            biasWarnings: biases, contrarianSignal: contrarian,
            tradingGuidance: guidance, compositeScore: max(-100, min(100, composite))
        )
        currentAnalysis = analysis
        return analysis
    }

    // MARK: - Mood

    private func determineMood(fearGreed: Int, change24h: Double, change7d: Double) -> MarketMood {
        switch fearGreed {
        case 0..<8:    return .capitulation
        case 8..<15:   return .panic
        case 15..<25:  return change7d < -10 ? .panic : .fear
        case 25..<35:  return .fear
        case 35..<45:  return change24h < 0 ? .anxiety : .hope
        case 45..<55:  return .neutral
        case 55..<65:  return .optimism
        case 65..<75:  return .optimism
        case 75..<85:  return change7d > 15 ? .euphoria : .greed
        case 85..<92:  return .greed
        case 92...100: return .euphoria
        default:       return .neutral
        }
    }

    // MARK: - Phase

    private func determinePhase(fearGreed: Int, change7d: Double, change30d: Double, volume24hChange: Double) -> EmotionalCyclePhase {
        if fearGreed > 85 && change30d > 30 { return .euphoria }
        if fearGreed > 75 && change30d > 15 { return .thrill }
        if fearGreed > 60 && change30d > 5 { return .belief }
        if fearGreed > 50 && change30d > 0 { return change7d > 5 ? .hope : .complacency }
        if fearGreed > 40 && change30d < -5 { return .anxiety }
        if fearGreed > 30 && change30d < -15 { return .denial }
        if fearGreed < 20 && change30d < -25 && volume24hChange > 1.5 { return .capitulation }
        if fearGreed < 20 && change30d < -20 { return .panic }
        if fearGreed < 30 && change30d < -30 { return .depression }
        if fearGreed < 35 && change7d > 3 { return .disbelief }
        return .belief
    }

    // MARK: - Biases

    private func detectBiases(fearGreed: Int, mood: MarketMood, change24h: Double, change7d: Double, volatility: Double, volume24hChange: Double) -> [BiasWarning] {
        var biases: [BiasWarning] = []

        if fearGreed > 75 && change24h > 5 && volume24hChange > 1.3 {
            biases.append(BiasWarning(
                bias: .fomo, severity: fearGreed > 85 ? .high : .medium,
                description: "Market pumping +\(String(format: "%.1f", change24h))%. FOMO risk high.",
                mitigation: "Stick to your plan. Don't chase pumps."
            ))
        }

        if fearGreed > 80 || fearGreed < 20 {
            biases.append(BiasWarning(
                bias: .herdMentality, severity: .medium,
                description: fearGreed > 80 ? "Everyone bullish. Crowd is usually wrong at extremes." : "Everyone bearish. Crowd is usually wrong at extremes.",
                mitigation: "Consider the contrarian view."
            ))
        }

        if abs(change24h) > 8 {
            biases.append(BiasWarning(
                bias: .recencyBias, severity: .medium,
                description: "\(String(format: "%.1f", change24h))% today may skew perception.",
                mitigation: "Look at weekly/monthly trend. One day doesn't define the trend."
            ))
        }

        if volatility < 0.3 && fearGreed > 60 {
            biases.append(BiasWarning(
                bias: .overconfidence, severity: .low,
                description: "Low vol + positive sentiment can lead to oversized positions.",
                mitigation: "Maintain standard position sizes."
            ))
        }

        if fearGreed < 30 && change7d < -10 {
            biases.append(BiasWarning(
                bias: .lossAversion, severity: .high,
                description: "In fear, tendency to hold losers hoping for recovery.",
                mitigation: "Review positions objectively. Would you buy at this price?"
            ))
        }

        return biases
    }

    // MARK: - Contrarian

    private func generateContrarian(fearGreed: Int, mood: MarketMood, phase: EmotionalCyclePhase) -> ContrarianSignal {
        let score = mood.contrarianScore
        let direction = score > 30 ? "buy" : score < -30 ? "sell" : "neutral"
        let strength = min(abs(score), 100)
        let reasoning: String
        if fearGreed < 20 {
            reasoning = "Extreme fear marks buying opportunities. \(phase.investmentImplication)"
        } else if fearGreed > 80 {
            reasoning = "Extreme greed marks selling opportunities. \(phase.investmentImplication)"
        } else {
            reasoning = "No extreme sentiment. \(phase.investmentImplication)"
        }
        return ContrarianSignal(direction: direction, strength: strength, reasoning: reasoning)
    }

    // MARK: - Guidance

    private func generateGuidance(mood: MarketMood, phase: EmotionalCyclePhase, biases: [BiasWarning], contrarian: ContrarianSignal) -> [PsychologyGuidance] {
        var guidance: [PsychologyGuidance] = []

        guidance.append(PsychologyGuidance(
            title: "Market Phase: \(phase.rawValue)",
            guidance: phase.investmentImplication,
            icon: "chart.line.uptrend.xyaxis", priority: 1
        ))

        guidance.append(PsychologyGuidance(
            title: "Mood: \(mood.rawValue)",
            guidance: mood.description,
            icon: mood.icon, priority: 2
        ))

        if contrarian.strength > 40 {
            guidance.append(PsychologyGuidance(
                title: "Contrarian: \(contrarian.direction.capitalized)",
                guidance: contrarian.reasoning,
                icon: "arrow.triangle.swap", priority: 1
            ))
        }

        for warning in biases where warning.severity == .high {
            guidance.append(PsychologyGuidance(
                title: "\(warning.bias.rawValue) Alert",
                guidance: warning.mitigation,
                icon: "brain.head.profile", priority: 1
            ))
        }

        return guidance.sorted { $0.priority < $1.priority }
    }
}
