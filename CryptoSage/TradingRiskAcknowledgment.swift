//
//  TradingRiskAcknowledgment.swift
//  CryptoSage
//
//  Manages user acknowledgment of trading risks and Terms of Service acceptance
//  before enabling real trade execution. Tracks consent state, version, and provides
//  SwiftUI views for the acknowledgment flow. Includes audit trail for legal protection.
//

import SwiftUI
import UIKit

// MARK: - Audit Trail Entry

/// Represents a single audit trail entry for legal compliance
struct ConsentAuditEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let consentType: ConsentType
    let version: Int
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let userAgent: String
    
    enum ConsentType: String, Codable {
        case termsOfService = "terms_of_service"
        case tradingRisk = "trading_risk"
        case derivativesRisk = "derivatives_risk"
        case botTradingRisk = "bot_trading_risk"
        case tradeConfirmation = "trade_confirmation"
    }
    
    init(consentType: ConsentType, version: Int) {
        self.id = UUID()
        self.timestamp = Date()
        self.consentType = consentType
        self.version = version
        self.deviceModel = UIDevice.current.model
        self.osVersion = UIDevice.current.systemVersion
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        self.userAgent = "CryptoSage/\(self.appVersion) iOS/\(self.osVersion)"
    }
}

// MARK: - Trading Risk Manager

/// Manages trading risk acknowledgment state, Terms of Service acceptance, and audit trail
final class TradingRiskAcknowledgmentManager {
    static let shared = TradingRiskAcknowledgmentManager()
    
    // MARK: - Constants
    
    /// Current version of the risk acknowledgment terms
    /// Increment this when terms change significantly to require re-acknowledgment
    private static let currentTermsVersion = 1
    
    /// Current version of the Terms of Service
    /// Increment this when ToS changes to require re-acceptance
    private static let currentToSVersion = 1
    
    /// How long (in seconds) before requiring re-acknowledgment (365 days)
    private static let acknowledgmentValidityPeriod: TimeInterval = 365 * 24 * 60 * 60
    
    // MARK: - UserDefaults Keys
    
    private let hasAcknowledgedKey = "TradingRisk.HasAcknowledged"
    private let acknowledgmentDateKey = "TradingRisk.AcknowledgmentDate"
    private let termsVersionKey = "TradingRisk.TermsVersion"
    private let derivativesAcknowledgedKey = "TradingRisk.DerivativesAcknowledged"
    private let botTradingAcknowledgedKey = "TradingRisk.BotTradingAcknowledged"
    
    // Terms of Service keys
    private let hasAcceptedToSKey = "TermsOfService.HasAccepted"
    private let tosAcceptanceDateKey = "TermsOfService.AcceptanceDate"
    private let tosVersionKey = "TermsOfService.Version"
    
    // Audit trail key
    private let auditTrailKey = "ConsentAuditTrail"
    
    private let userDefaults = UserDefaults.standard
    
    private init() {}
    
    // MARK: - Computed Properties
    
    /// Whether the user has acknowledged basic trading risks and acknowledgment is still valid
    var hasValidAcknowledgment: Bool {
        guard userDefaults.bool(forKey: hasAcknowledgedKey) else { return false }
        guard let acknowledgmentDate = userDefaults.object(forKey: acknowledgmentDateKey) as? Date else { return false }
        guard userDefaults.integer(forKey: termsVersionKey) >= Self.currentTermsVersion else { return false }
        
        // Check if acknowledgment has expired
        let elapsed = Date().timeIntervalSince(acknowledgmentDate)
        return elapsed < Self.acknowledgmentValidityPeriod
    }
    
    /// Whether derivatives/leverage trading has been specifically acknowledged
    var hasAcknowledgedDerivatives: Bool {
        userDefaults.bool(forKey: derivativesAcknowledgedKey)
    }
    
    /// Whether automated bot trading has been specifically acknowledged
    var hasAcknowledgedBotTrading: Bool {
        userDefaults.bool(forKey: botTradingAcknowledgedKey)
    }
    
    /// Date when the user acknowledged trading risks (nil if never)
    var acknowledgmentDate: Date? {
        userDefaults.object(forKey: acknowledgmentDateKey) as? Date
    }
    
    /// Human-readable string for when acknowledgment was made
    var acknowledgmentDateString: String? {
        guard let date = acknowledgmentDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // MARK: - Terms of Service Properties
    
    /// Whether the user has accepted the current Terms of Service
    var hasAcceptedTermsOfService: Bool {
        guard userDefaults.bool(forKey: hasAcceptedToSKey) else { return false }
        guard let acceptanceDate = userDefaults.object(forKey: tosAcceptanceDateKey) as? Date else { return false }
        guard userDefaults.integer(forKey: tosVersionKey) >= Self.currentToSVersion else { return false }
        
        // Check if acceptance has expired (same validity period as risk acknowledgment)
        let elapsed = Date().timeIntervalSince(acceptanceDate)
        return elapsed < Self.acknowledgmentValidityPeriod
    }
    
    /// Whether the user needs to accept Terms of Service (never accepted or version changed)
    var needsToSAcceptance: Bool {
        // Never accepted
        if !userDefaults.bool(forKey: hasAcceptedToSKey) { return true }
        
        // ToS version changed
        if userDefaults.integer(forKey: tosVersionKey) < Self.currentToSVersion { return true }
        
        // Acceptance expired
        if let date = tosAcceptanceDate {
            let elapsed = Date().timeIntervalSince(date)
            if elapsed >= Self.acknowledgmentValidityPeriod { return true }
        }
        
        return false
    }
    
    /// Date when the user accepted Terms of Service (nil if never)
    var tosAcceptanceDate: Date? {
        userDefaults.object(forKey: tosAcceptanceDateKey) as? Date
    }
    
    /// Human-readable string for when ToS was accepted
    var tosAcceptanceDateString: String? {
        guard let date = tosAcceptanceDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    /// The current Terms of Service version number
    var currentToSVersionNumber: Int {
        Self.currentToSVersion
    }
    
    /// The user's accepted ToS version (0 if never accepted)
    var acceptedToSVersion: Int {
        userDefaults.integer(forKey: tosVersionKey)
    }
    
    /// Whether user can trade (has both ToS acceptance AND risk acknowledgment)
    var canTrade: Bool {
        hasAcceptedTermsOfService && hasValidAcknowledgment
    }
    
    // MARK: - Actions
    
    /// Record that user has acknowledged basic trading risks
    func acknowledgeBasicTradingRisks() {
        userDefaults.set(true, forKey: hasAcknowledgedKey)
        userDefaults.set(Date(), forKey: acknowledgmentDateKey)
        userDefaults.set(Self.currentTermsVersion, forKey: termsVersionKey)
        
        // Record in audit trail
        logConsentToAuditTrail(type: .tradingRisk, version: Self.currentTermsVersion)
    }
    
    /// Record that user has acknowledged derivatives/leverage risks
    func acknowledgeDerivativesRisks() {
        userDefaults.set(true, forKey: derivativesAcknowledgedKey)
        
        // Record in audit trail
        logConsentToAuditTrail(type: .derivativesRisk, version: Self.currentTermsVersion)
    }
    
    /// Record that user has acknowledged automated bot trading risks
    func acknowledgeBotTradingRisks() {
        userDefaults.set(true, forKey: botTradingAcknowledgedKey)
        
        // Record in audit trail
        logConsentToAuditTrail(type: .botTradingRisk, version: Self.currentTermsVersion)
    }
    
    /// Reset all acknowledgments (for testing or if user requests)
    func resetAllAcknowledgments() {
        userDefaults.removeObject(forKey: hasAcknowledgedKey)
        userDefaults.removeObject(forKey: acknowledgmentDateKey)
        userDefaults.removeObject(forKey: termsVersionKey)
        userDefaults.removeObject(forKey: derivativesAcknowledgedKey)
        userDefaults.removeObject(forKey: botTradingAcknowledgedKey)
        userDefaults.removeObject(forKey: hasAcceptedToSKey)
        userDefaults.removeObject(forKey: tosAcceptanceDateKey)
        userDefaults.removeObject(forKey: tosVersionKey)
        // Note: Audit trail is NOT reset - it's kept for legal compliance
    }
    
    /// Check if user needs to re-acknowledge (terms updated or expired)
    var needsReacknowledgment: Bool {
        // Never acknowledged
        if !userDefaults.bool(forKey: hasAcknowledgedKey) { return true }
        
        // Terms version changed
        if userDefaults.integer(forKey: termsVersionKey) < Self.currentTermsVersion { return true }
        
        // Acknowledgment expired
        if let date = acknowledgmentDate {
            let elapsed = Date().timeIntervalSince(date)
            if elapsed >= Self.acknowledgmentValidityPeriod { return true }
        }
        
        return false
    }
    
    // MARK: - Terms of Service Actions
    
    /// Record that user has accepted the Terms of Service
    func acceptTermsOfService() {
        userDefaults.set(true, forKey: hasAcceptedToSKey)
        userDefaults.set(Date(), forKey: tosAcceptanceDateKey)
        userDefaults.set(Self.currentToSVersion, forKey: tosVersionKey)
        
        // Record in audit trail
        logConsentToAuditTrail(type: .termsOfService, version: Self.currentToSVersion)
    }
    
    // MARK: - Audit Trail
    
    /// Log a consent event to the audit trail
    func logConsentToAuditTrail(type: ConsentAuditEntry.ConsentType, version: Int) {
        let entry = ConsentAuditEntry(consentType: type, version: version)
        var trail = getAuditTrail()
        trail.append(entry)
        
        // Keep only the last 100 entries to prevent unbounded growth
        if trail.count > 100 {
            trail = Array(trail.suffix(100))
        }
        
        saveAuditTrail(trail)
    }
    
    /// Log a trade confirmation to the audit trail
    func logTradeConfirmation(symbol: String, side: String, quantity: Double, price: Double) {
        logConsentToAuditTrail(type: .tradeConfirmation, version: Self.currentTermsVersion)
    }
    
    /// Get all audit trail entries
    func getAuditTrail() -> [ConsentAuditEntry] {
        guard let data = userDefaults.data(forKey: auditTrailKey) else { return [] }
        do {
            return try JSONDecoder().decode([ConsentAuditEntry].self, from: data)
        } catch {
            return []
        }
    }
    
    /// Save audit trail to UserDefaults
    private func saveAuditTrail(_ trail: [ConsentAuditEntry]) {
        do {
            let data = try JSONEncoder().encode(trail)
            userDefaults.set(data, forKey: auditTrailKey)
        } catch {
            // Silently fail - audit trail is not critical to app function
        }
    }
    
    /// Export audit trail as JSON string (for debugging or legal requests)
    func exportAuditTrailAsJSON() -> String? {
        let trail = getAuditTrail()
        guard !trail.isEmpty else { return nil }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(trail)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    /// Get the most recent consent entry for a given type
    func lastConsentEntry(for type: ConsentAuditEntry.ConsentType) -> ConsentAuditEntry? {
        getAuditTrail().filter { $0.consentType == type }.last
    }
}

// MARK: - Risk Acknowledgment Texts

/// Contains all the legal text for risk acknowledgments and Terms of Service
enum TradingRiskTexts {
    
    static let basicRiskTitle = "Trading Risk Acknowledgment"
    
    static let basicRiskWarnings: [String] = [
        "Cryptocurrency trading involves substantial risk of loss. Prices are highly volatile and can change rapidly.",
        "You may lose some or all of your invested capital. Only trade with funds you can afford to lose entirely.",
        "CryptoSage is NOT a registered investment adviser or broker-dealer. Nothing in this app constitutes financial, investment, tax, or legal advice.",
        "AI-generated predictions, analysis, and suggestions may be inaccurate or wrong. Do not rely solely on AI for trading decisions.",
        "Past performance does not guarantee future results. Historical data and backtests are not reliable indicators of future performance.",
        "You are solely responsible for your trading decisions and for complying with all applicable laws and regulations in your jurisdiction."
    ]
    
    static let basicAcknowledgmentStatement = "I have read and understand the risks above. I acknowledge that I am solely responsible for my trading decisions and that CryptoSage is not liable for any losses I may incur."
    
    static let derivativesTitle = "Derivatives & Leverage Risk"
    
    static let derivativesWarnings: [String] = [
        "Leveraged trading carries substantially higher risk than spot trading. You can lose more than your initial investment.",
        "Positions can be liquidated rapidly during volatile market conditions, resulting in total loss of margin.",
        "Leverage amplifies both gains and losses. Small price movements can result in large percentage losses.",
        "Derivatives trading is suitable only for experienced traders who fully understand the risks involved.",
        "Funding rates and fees can significantly impact your positions over time."
    ]
    
    static let derivativesAcknowledgmentStatement = "I understand that derivatives and leveraged trading carry substantial risk of total loss. I am an experienced trader and accept full responsibility for any leveraged positions."
    
    static let botTradingTitle = "Automated Trading Risk"
    
    static let botWarnings: [String] = [
        "Trading bots execute trades automatically based on your configured parameters, 24 hours a day, 7 days a week.",
        "Bots can and do lose money. A strategy that worked in the past may fail in changing market conditions.",
        "Technical issues, exchange outages, or API errors can cause unexpected bot behavior or failed trades.",
        "You are responsible for monitoring your bots and their performance. Bots should not be left unattended indefinitely.",
        "Market conditions can change rapidly. Bots cannot adapt to unprecedented events or \"black swan\" scenarios."
    ]
    
    static let botAcknowledgmentStatement = "I understand that automated trading bots can lose money and that I am responsible for configuring, monitoring, and the results of any bots I create."
    
    static let preTradeWarning = "You are about to execute a real trade. This action cannot be undone. You may lose money."
    
    static let aiTradeDisclaimer = "This trade suggestion was generated by AI. AI can be wrong. This is NOT financial advice. Only proceed if you have done your own research."
    
    // MARK: - Terms of Service Texts
    
    static let tosTitle = "Terms of Service"
    
    static let tosSubtitle = "Please read and accept our Terms of Service before trading"
    
    static let tosKeyPoints: [String] = [
        "CryptoSage is NOT a registered investment adviser, broker-dealer, or financial institution. We do not provide personalized investment advice.",
        "All trades are executed through third-party exchanges that you connect. CryptoSage is not responsible for exchange outages, errors, or failures.",
        "AI-generated predictions and suggestions may be inaccurate or completely wrong. AI is not a licensed financial professional.",
        "You are solely responsible for your trading decisions and any resulting profits or losses.",
        "You agree to indemnify and hold harmless CryptoSage from any claims arising from your use of the app or trading activities.",
        "Any disputes will be resolved through binding arbitration. You waive the right to participate in class action lawsuits.",
        "You must be at least 18 years old and legally permitted to trade cryptocurrency in your jurisdiction."
    ]
    
    static let tosAcknowledgmentStatement1 = "I have read, understand, and agree to the Terms of Service."
    
    static let tosAcknowledgmentStatement2 = "I understand that CryptoSage is not liable for any trading losses I may incur, and I accept full responsibility for my trading decisions."
    
    static let tosFullText = """
    TERMS OF SERVICE
    Last Updated: January 20, 2026
    
    1. ACCEPTANCE OF TERMS
    
    By downloading, installing, accessing, or using CryptoSage AI ("the App," "Service," or "CryptoSage"), you ("User," "you," or "your") agree to be bound by these Terms of Service ("Terms"). If you do not agree to all of these Terms, do not use the App.
    
    You must be at least 18 years old (or the age of majority in your jurisdiction) to use this App. By using CryptoSage, you represent and warrant that you are of legal age and have the legal capacity to enter into this agreement.
    
    2. IMPORTANT REGULATORY DISCLOSURES
    
    NOT A REGISTERED INVESTMENT ADVISER OR BROKER-DEALER: CryptoSage is NOT registered as an investment adviser with the U.S. Securities and Exchange Commission (SEC) or any state securities regulatory authority. CryptoSage is NOT registered as a broker-dealer with the SEC or the Financial Industry Regulatory Authority (FINRA). CryptoSage does NOT hold any other financial services licenses or registrations.
    
    NO FIDUCIARY RELATIONSHIP: CryptoSage does not act as a fiduciary or investment adviser to you. We do not provide personalized investment advice, and no fiduciary relationship is created between you and CryptoSage by your use of the App.
    
    SECURITIES RISK: Certain cryptocurrency assets may be classified as "securities" under U.S. federal or state law, or the laws of other jurisdictions. The regulatory status of cryptocurrencies is evolving and uncertain. You are solely responsible for determining whether any cryptocurrency you trade or hold is a security in your jurisdiction and for complying with all applicable laws.
    
    3. SERVICE DESCRIPTION
    
    CryptoSage AI provides the following features:
    • Cryptocurrency portfolio tracking and visualization
    • AI-powered market analysis, insights, and chat functionality
    • AI-generated price predictions and technical analysis
    • Exchange API integrations for portfolio synchronization
    • Paper Trading with $100,000 in virtual funds
    • Automated trading bots in Paper Trading mode (DCA, Grid, Signal bots)
    • Price alerts and notifications
    • Market data visualization and heat maps
    
    Note: Live trading via connected exchanges is currently not available. Exchange connections are used for portfolio tracking only.
    
    IMPORTANT: All information, analysis, predictions, and suggestions provided by CryptoSage, including those generated by artificial intelligence, are for INFORMATIONAL AND EDUCATIONAL PURPOSES ONLY and do NOT constitute financial advice, investment advice, trading advice, tax advice, legal advice, or any other form of professional advice. You are solely responsible for your own investment and trading decisions.
    
    4. AI-GENERATED CONTENT DISCLAIMER
    
    CryptoSage utilizes artificial intelligence and machine learning technologies to provide market analysis, price predictions, trading suggestions, and conversational responses. You acknowledge and agree that:
    
    • AI is not a licensed professional: The AI features are not provided by licensed financial advisors, investment professionals, or any regulated entity.
    • AI can be wrong: AI-generated predictions, analysis, and suggestions may be inaccurate, incomplete, outdated, or entirely incorrect. AI systems can "hallucinate" or produce plausible-sounding but false information.
    • No guarantee of accuracy: We make no representations or warranties regarding the accuracy, reliability, completeness, or timeliness of any AI-generated content.
    • Not personalized advice: AI outputs are not tailored to your specific financial situation, risk tolerance, investment objectives, or personal circumstances.
    • Past performance disclaimer: Any historical data, backtesting results, or past performance metrics shown do NOT guarantee or predict future results.
    
    5. TRADE EXECUTION DISCLAIMER
    
    CryptoSage may facilitate the execution of trades on third-party cryptocurrency exchanges through API connections that you configure. By using trade execution features, you acknowledge and agree:
    
    • User-initiated trades: All trades executed through CryptoSage are initiated by you, the user.
    • No recommendation to trade: The presence of a "trade" or "execute" button, or any AI suggestion, does not constitute a recommendation to execute any particular trade.
    • Exchange responsibility: Trade execution occurs on third-party exchanges, not within CryptoSage. We are not responsible for exchange outages, delays, failed transactions, incorrect pricing, slippage, or any other issues arising from the third-party exchange.
    • API key security: You are responsible for the security of your exchange API keys.
    • Trading bots risk: Automated trading bots can execute trades 24/7 based on your parameters. Bots can and do lose money.
    
    YOU CAN LOSE MONEY: Cryptocurrency trading involves substantial risk of loss. You should only trade with funds you can afford to lose entirely.
    
    6. INDEMNIFICATION
    
    You agree to indemnify, defend, and hold harmless CryptoSage, its officers, directors, employees, agents, licensors, and suppliers from and against any and all claims, damages, losses, liabilities, costs, and expenses (including reasonable attorneys' fees) arising out of or related to:
    
    • Your use of the App or any features thereof
    • Your trading or investment decisions
    • Any trades executed through your connected exchange accounts
    • Your violation of these Terms
    • Your violation of any applicable law or regulation
    
    7. DISCLAIMER OF WARRANTIES
    
    THE APP AND ALL CONTENT, FEATURES, AND SERVICES ARE PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED.
    
    8. LIMITATION OF LIABILITY
    
    TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW:
    
    • CRYPTOSAGE SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, PUNITIVE, OR EXEMPLARY DAMAGES.
    • CRYPTOSAGE SHALL NOT BE LIABLE FOR ANY FINANCIAL LOSSES ARISING FROM TRADING DECISIONS.
    • IN NO EVENT SHALL CRYPTOSAGE'S TOTAL LIABILITY EXCEED THE GREATER OF (A) THE AMOUNT YOU PAID TO CRYPTOSAGE IN THE TWELVE (12) MONTHS PRIOR TO THE CLAIM, OR (B) ONE HUNDRED U.S. DOLLARS ($100).
    
    9. ARBITRATION AGREEMENT AND CLASS ACTION WAIVER
    
    PLEASE READ THIS SECTION CAREFULLY. IT AFFECTS YOUR LEGAL RIGHTS.
    
    You and CryptoSage agree that any dispute, claim, or controversy arising out of or relating to these Terms, the App, or your use thereof will be resolved exclusively through binding individual arbitration rather than in court. YOU AND CRYPTOSAGE AGREE THAT EACH MAY BRING CLAIMS AGAINST THE OTHER ONLY IN YOUR OR ITS INDIVIDUAL CAPACITY AND NOT AS A PLAINTIFF OR CLASS MEMBER IN ANY PURPORTED CLASS, COLLECTIVE, OR REPRESENTATIVE ACTION.
    
    10. GOVERNING LAW
    
    These Terms shall be governed by and construed in accordance with the laws of the State of Delaware, United States, without regard to its conflict of law principles.
    
    11. CONTACT
    
    For questions about these Terms of Service:
    Email: hypersageai@gmail.com
    """
}

// MARK: - Trading Risk Acknowledgment View

/// Full-screen view requiring user to acknowledge trading risks before first trade
struct TradingRiskAcknowledgmentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasCheckedAcknowledgment = false
    @State private var scrolledToBottom = false
    
    let onAcknowledge: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Header
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.yellow)
                                
                                Text(TradingRiskTexts.basicRiskTitle)
                                    .font(.title.bold())
                                    .multilineTextAlignment(.center)
                                
                                Text("Please read carefully before trading")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 10)
                            
                            // Risk warnings
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(Array(TradingRiskTexts.basicRiskWarnings.enumerated()), id: \.offset) { index, warning in
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundStyle(.red)
                                            .font(.title3)
                                        
                                        Text(warning)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                    }
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(12)
                                }
                            }
                            
                            // Acknowledgment checkbox
                            Button {
                                hasCheckedAcknowledgment.toggle()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: hasCheckedAcknowledgment ? "checkmark.square.fill" : "square")
                                        .font(.title2)
                                        .foregroundStyle(hasCheckedAcknowledgment ? .green : .secondary)
                                    
                                    Text(TradingRiskTexts.basicAcknowledgmentStatement)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding()
                                .background(hasCheckedAcknowledgment ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 10)
                            
                            // Bottom marker for scroll detection
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding()
                    }
                }
                
                // Bottom buttons
                VStack(spacing: 12) {
                    Divider()
                    
                    Button {
                        if hasCheckedAcknowledgment {
                            TradingRiskAcknowledgmentManager.shared.acknowledgeBasicTradingRisks()
                            onAcknowledge()
                            dismiss()
                        }
                    } label: {
                        Text("I Understand and Accept the Risks")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(hasCheckedAcknowledgment ? Color.green : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!hasCheckedAcknowledgment)
                    
                    Button {
                        onDecline()
                        dismiss()
                    } label: {
                        Text("Cancel - I Don't Want to Trade")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
    }
}

// MARK: - Derivatives Risk Acknowledgment View

/// View for acknowledging derivatives/leverage-specific risks
struct DerivativesRiskAcknowledgmentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasCheckedAcknowledgment = false
    
    let onAcknowledge: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 50))
                                .foregroundStyle(.orange)
                            
                            Text(TradingRiskTexts.derivativesTitle)
                                .font(.title.bold())
                                .multilineTextAlignment(.center)
                            
                            Text("Leverage amplifies both gains AND losses")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 10)
                        
                        // Risk warnings
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(TradingRiskTexts.derivativesWarnings.enumerated()), id: \.offset) { index, warning in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.title3)
                                    
                                    Text(warning)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }
                                .padding()
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                        
                        // Acknowledgment checkbox
                        Button {
                            hasCheckedAcknowledgment.toggle()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: hasCheckedAcknowledgment ? "checkmark.square.fill" : "square")
                                    .font(.title2)
                                    .foregroundStyle(hasCheckedAcknowledgment ? .green : .secondary)
                                
                                Text(TradingRiskTexts.derivativesAcknowledgmentStatement)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding()
                            .background(hasCheckedAcknowledgment ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                    .padding()
                }
                
                // Bottom buttons
                VStack(spacing: 12) {
                    Divider()
                    
                    Button {
                        if hasCheckedAcknowledgment {
                            TradingRiskAcknowledgmentManager.shared.acknowledgeDerivativesRisks()
                            onAcknowledge()
                            dismiss()
                        }
                    } label: {
                        Text("I Understand Leverage Risks")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(hasCheckedAcknowledgment ? Color.orange : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!hasCheckedAcknowledgment)
                    
                    Button {
                        onDecline()
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
    }
}

// MARK: - Bot Trading Risk Acknowledgment View

/// View for acknowledging automated trading bot risks
struct BotTradingRiskAcknowledgmentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasCheckedAcknowledgment = false
    
    let onAcknowledge: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "gearshape.2.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.blue)
                            
                            Text(TradingRiskTexts.botTradingTitle)
                                .font(.title.bold())
                                .multilineTextAlignment(.center)
                            
                            Text("Bots trade automatically 24/7")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 10)
                        
                        // Risk warnings
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(TradingRiskTexts.botWarnings.enumerated()), id: \.offset) { index, warning in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                                        .foregroundStyle(.blue)
                                        .font(.title3)
                                    
                                    Text(warning)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                        
                        // Acknowledgment checkbox
                        Button {
                            hasCheckedAcknowledgment.toggle()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: hasCheckedAcknowledgment ? "checkmark.square.fill" : "square")
                                    .font(.title2)
                                    .foregroundStyle(hasCheckedAcknowledgment ? .green : .secondary)
                                
                                Text(TradingRiskTexts.botAcknowledgmentStatement)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding()
                            .background(hasCheckedAcknowledgment ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                    .padding()
                }
                
                // Bottom buttons
                VStack(spacing: 12) {
                    Divider()
                    
                    Button {
                        if hasCheckedAcknowledgment {
                            TradingRiskAcknowledgmentManager.shared.acknowledgeBotTradingRisks()
                            onAcknowledge()
                            dismiss()
                        }
                    } label: {
                        Text("I Understand Bot Trading Risks")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(hasCheckedAcknowledgment ? Color.blue : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!hasCheckedAcknowledgment)
                    
                    Button {
                        onDecline()
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
    }
}

// MARK: - Terms of Service Acceptance View

/// Full-screen view requiring user to read and accept Terms of Service before trading
struct TermsOfServiceAcceptanceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasScrolledToBottom = false
    @State private var hasCheckedTerms = false
    @State private var hasCheckedLiability = false
    
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    private var canAccept: Bool {
        hasScrolledToBottom && hasCheckedTerms && hasCheckedLiability
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                    
                    Text(TradingRiskTexts.tosTitle)
                        .font(.title.bold())
                    
                    Text(TradingRiskTexts.tosSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("Version \(TradingRiskAcknowledgmentManager.shared.currentToSVersionNumber)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.secondarySystemBackground))
                
                // Scrollable Terms of Service
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Key Points Summary
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Key Points")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                ForEach(Array(TradingRiskTexts.tosKeyPoints.enumerated()), id: \.offset) { index, point in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundStyle(.orange)
                                            .font(.body)
                                        
                                        Text(point)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                            
                            // Full Terms
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Full Terms of Service")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                Text(TradingRiskTexts.tosFullText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding()
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(12)
                            
                            // Scroll indicator
                            if !hasScrolledToBottom {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 4) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.blue)
                                        Text("Scroll to continue")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                            
                            // Bottom marker for scroll detection
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                                .onAppear {
                                    hasScrolledToBottom = true
                                }
                        }
                        .padding()
                    }
                }
                
                // Checkboxes and Accept Button
                VStack(spacing: 16) {
                    Divider()
                    
                    // Checkbox 1: Terms acceptance
                    Button {
                        if hasScrolledToBottom {
                            hasCheckedTerms.toggle()
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: hasCheckedTerms ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(hasCheckedTerms ? .green : (hasScrolledToBottom ? .secondary : .gray.opacity(0.5)))
                            
                            Text(TradingRiskTexts.tosAcknowledgmentStatement1)
                                .font(.subheadline)
                                .foregroundStyle(hasScrolledToBottom ? .primary : .secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(12)
                        .background(hasCheckedTerms ? Color.green.opacity(0.1) : Color.secondary.opacity(0.05))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasScrolledToBottom)
                    
                    // Checkbox 2: Liability acknowledgment
                    Button {
                        if hasScrolledToBottom {
                            hasCheckedLiability.toggle()
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: hasCheckedLiability ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(hasCheckedLiability ? .green : (hasScrolledToBottom ? .secondary : .gray.opacity(0.5)))
                            
                            Text(TradingRiskTexts.tosAcknowledgmentStatement2)
                                .font(.subheadline)
                                .foregroundStyle(hasScrolledToBottom ? .primary : .secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(12)
                        .background(hasCheckedLiability ? Color.green.opacity(0.1) : Color.secondary.opacity(0.05))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasScrolledToBottom)
                    
                    // Accept Button
                    Button {
                        if canAccept {
                            TradingRiskAcknowledgmentManager.shared.acceptTermsOfService()
                            onAccept()
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if canAccept {
                                Image(systemName: "checkmark.shield.fill")
                            }
                            Text("I Accept the Terms of Service")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canAccept ? Color.blue : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(!canAccept)
                    
                    // Decline Button
                    Button {
                        onDecline()
                        dismiss()
                    } label: {
                        Text("Decline - I Don't Want to Trade")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Status indicator
                    if !hasScrolledToBottom {
                        Text("Please scroll to read the full Terms of Service")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if !hasCheckedTerms || !hasCheckedLiability {
                        Text("Please check both boxes to continue")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Terms of Service")
                        .font(.headline)
                }
            }
        }
    }
}

// MARK: - Pre-Trade Confirmation Alert

/// Inline warning banner for pre-trade confirmation
struct PreTradeWarningBanner: View {
    let isAIGenerated: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Risk Warning")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            
            Text(TradingRiskTexts.preTradeWarning)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if isAIGenerated {
                Text(TradingRiskTexts.aiTradeDisclaimer)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - View Modifier for Risk Acknowledgment Check

/// View modifier that shows ToS acceptance and risk acknowledgment sheets if needed before allowing action
struct RequiresTradingAcknowledgmentModifier: ViewModifier {
    @State private var showingToSAcceptance = false
    @State private var showingRiskAcknowledgment = false
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                let manager = TradingRiskAcknowledgmentManager.shared
                
                // First check ToS acceptance
                if manager.needsToSAcceptance {
                    showingToSAcceptance = true
                }
                // Then check risk acknowledgment
                else if manager.needsReacknowledgment {
                    showingRiskAcknowledgment = true
                }
                // Both accepted - allow action
                else {
                    action()
                }
            }
            .sheet(isPresented: $showingToSAcceptance) {
                TermsOfServiceAcceptanceView(
                    onAccept: {
                        // After ToS acceptance, check if risk acknowledgment is also needed
                        if TradingRiskAcknowledgmentManager.shared.needsReacknowledgment {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                showingRiskAcknowledgment = true
                            }
                        } else {
                            action()
                        }
                    },
                    onDecline: {
                        // Do nothing - user declined
                    }
                )
            }
            .sheet(isPresented: $showingRiskAcknowledgment) {
                TradingRiskAcknowledgmentView(
                    onAcknowledge: {
                        action()
                    },
                    onDecline: {
                        // Do nothing - user declined
                    }
                )
            }
    }
}

/// View modifier that requires only Terms of Service acceptance
struct RequiresTermsOfServiceModifier: ViewModifier {
    @State private var showingToSAcceptance = false
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                if TradingRiskAcknowledgmentManager.shared.needsToSAcceptance {
                    showingToSAcceptance = true
                } else {
                    action()
                }
            }
            .sheet(isPresented: $showingToSAcceptance) {
                TermsOfServiceAcceptanceView(
                    onAccept: {
                        action()
                    },
                    onDecline: {
                        // Do nothing - user declined
                    }
                )
            }
    }
}

extension View {
    /// Requires trading risk acknowledgment before performing an action
    func requiresTradingAcknowledgment(action: @escaping () -> Void) -> some View {
        modifier(RequiresTradingAcknowledgmentModifier(action: action))
    }
    
    /// Requires Terms of Service acceptance before performing an action
    func requiresTermsOfService(action: @escaping () -> Void) -> some View {
        modifier(RequiresTermsOfServiceModifier(action: action))
    }
}

// MARK: - Preview

#if DEBUG
struct TradingRiskAcknowledgment_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TermsOfServiceAcceptanceView(
                onAccept: {},
                onDecline: {}
            )
            .previewDisplayName("Terms of Service")
            
            TradingRiskAcknowledgmentView(
                onAcknowledge: {},
                onDecline: {}
            )
            .previewDisplayName("Basic Risk")
            
            DerivativesRiskAcknowledgmentView(
                onAcknowledge: {},
                onDecline: {}
            )
            .previewDisplayName("Derivatives Risk")
            
            BotTradingRiskAcknowledgmentView(
                onAcknowledge: {},
                onDecline: {}
            )
            .previewDisplayName("Bot Risk")
            
            PreTradeWarningBanner(isAIGenerated: true)
                .padding()
                .previewDisplayName("Pre-Trade Banner")
        }
    }
}
#endif
