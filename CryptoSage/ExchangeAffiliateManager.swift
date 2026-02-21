//
//  ExchangeAffiliateManager.swift
//  CryptoSage
//
//  Manages exchange affiliate/referral programs for additional revenue.
//  When users sign up for exchanges through CryptoSage, we earn a commission
//  from the exchange (not from the user). This is a common, safe monetization
//  strategy that doesn't require money transmitter registration.
//

import Foundation
import UIKit

// MARK: - Exchange Affiliate Data

/// Contains affiliate program information for a cryptocurrency exchange
struct ExchangeAffiliateInfo {
    let exchangeId: String
    let displayName: String
    let referralURL: URL?
    let signUpURL: URL?
    let commissionDescription: String
    let isActive: Bool
    
    /// Returns the URL to open - uses referral URL if available, falls back to sign up URL
    var bestURL: URL? {
        referralURL ?? signUpURL
    }
}

// MARK: - Exchange Affiliate Manager

/// Manages exchange affiliate/referral links for revenue generation
/// 
/// Revenue model: Exchanges pay CryptoSage a commission when users sign up through our
/// referral links. This is passive income from trading volume without handling money.
/// 
/// To activate affiliate revenue:
/// 1. Sign up for each exchange's affiliate program
/// 2. Get your unique referral codes/links
/// 3. Update the referralURLs dictionary below with your actual links
/// 
/// Affiliate program signup links:
/// - Binance: https://www.binance.com/en/activity/affiliate
/// - Coinbase: https://www.coinbase.com/affiliates
/// - Bybit: https://www.bybit.com/en/affiliate
/// - KuCoin: https://www.kucoin.com/affiliate
/// - Kraken: https://www.kraken.com/features/affiliate
/// - OKX: https://www.okx.com/affiliate
final class ExchangeAffiliateManager {
    static let shared = ExchangeAffiliateManager()
    
    private init() {}
    
    // MARK: - Referral URLs
    
    /// Referral URLs for each exchange
    /// Replace these placeholder URLs with your actual affiliate referral links
    /// 
    /// IMPORTANT: These are PLACEHOLDER values. You must:
    /// 1. Register for each exchange's affiliate program
    /// 2. Get your unique referral codes
    /// 3. Replace the URLs below with your actual referral links
    private let referralURLs: [String: String] = [
        // Format: "exchange_id": "https://exchange.com/signup?ref=YOUR_CODE"
        
        // Binance - Up to 50% commission on trading fees
        // Sign up at: https://www.binance.com/en/activity/affiliate
        "binance": "https://accounts.binance.com/register?ref=PLACEHOLDER",
        
        // Binance US - Similar program for US users
        "binance_us": "https://www.binance.us/register?ref=PLACEHOLDER",
        
        // Coinbase - $10 per new user (varies by region)
        // Sign up at: https://www.coinbase.com/affiliates
        "coinbase": "https://www.coinbase.com/join/PLACEHOLDER",
        
        // Bybit - Up to 30% commission on trading fees
        // Sign up at: https://www.bybit.com/en/affiliate
        "bybit": "https://www.bybit.com/invite?ref=PLACEHOLDER",
        
        // KuCoin - Up to 45% commission on trading fees
        // Sign up at: https://www.kucoin.com/affiliate
        "kucoin": "https://www.kucoin.com/ucenter/signup?rcode=PLACEHOLDER",
        
        // Kraken - Commission structure varies
        // Sign up at: https://www.kraken.com/features/affiliate
        "kraken": "https://www.kraken.com/sign-up?ref=PLACEHOLDER",
        
        // OKX - Up to 40% commission on trading fees
        // Sign up at: https://www.okx.com/affiliate
        "okx": "https://www.okx.com/join/PLACEHOLDER",
        
        // Gate.io
        "gate": "https://www.gate.io/signup?ref_type=103&ref=PLACEHOLDER",
        
        // Huobi
        "huobi": "https://www.huobi.com/invite/PLACEHOLDER"
    ]
    
    /// Default sign-up URLs (non-referral) as fallback
    private let defaultSignUpURLs: [String: String] = [
        "binance": "https://www.binance.com/register",
        "binance_us": "https://www.binance.us/register",
        "coinbase": "https://www.coinbase.com/signup",
        "bybit": "https://www.bybit.com/register",
        "kucoin": "https://www.kucoin.com/ucenter/signup",
        "kraken": "https://www.kraken.com/sign-up",
        "okx": "https://www.okx.com/join",
        "gate": "https://www.gate.io/signup",
        "huobi": "https://www.huobi.com/invite"
    ]
    
    /// Commission descriptions for user transparency
    /// Only shown when affiliate program is actually active (not PLACEHOLDER)
    private let commissionDescriptions: [String: String] = [
        "binance": "You get the same fees as any other user. No extra cost to you.",
        "binance_us": "No extra cost to you. Standard Binance.US fees apply.",
        "coinbase": "Create a free Coinbase account to get started.",
        "bybit": "No extra cost to you. Standard Bybit fees apply.",
        "kucoin": "No extra cost to you. Standard KuCoin fees apply.",
        "kraken": "Create a free Kraken account to get started.",
        "okx": "No extra cost to you. Standard OKX fees apply.",
        "gate": "No extra cost to you. Standard Gate.io fees apply.",
        "huobi": "Create a free HTX account to get started."
    ]
    
    // MARK: - Public Methods
    
    /// Get affiliate info for an exchange
    func affiliateInfo(for exchangeName: String) -> ExchangeAffiliateInfo {
        let exchangeId = normalizeExchangeId(exchangeName)
        
        let referralURLString = referralURLs[exchangeId]
        let signUpURLString = defaultSignUpURLs[exchangeId]
        let description = commissionDescriptions[exchangeId] ?? "Create a free account to get started."
        
        // Check if referral URL is a placeholder
        let referralURL: URL?
        if let urlString = referralURLString, !urlString.contains("PLACEHOLDER") {
            referralURL = URL(string: urlString)
        } else {
            referralURL = nil
        }
        
        let signUpURL = signUpURLString.flatMap { URL(string: $0) }
        
        return ExchangeAffiliateInfo(
            exchangeId: exchangeId,
            displayName: exchangeName,
            referralURL: referralURL,
            signUpURL: signUpURL,
            commissionDescription: description,
            isActive: referralURL != nil
        )
    }
    
    /// Open the sign-up page for an exchange (uses referral link if available)
    func openSignUpPage(for exchangeName: String) {
        let info = affiliateInfo(for: exchangeName)
        
        if let url = info.bestURL {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    /// Check if we have an active referral link for an exchange
    func hasActiveReferral(for exchangeName: String) -> Bool {
        affiliateInfo(for: exchangeName).isActive
    }
    
    /// Get all exchanges with active referral programs
    func exchangesWithActiveReferrals() -> [String] {
        return referralURLs.compactMap { key, value in
            value.contains("PLACEHOLDER") ? nil : key
        }
    }
    
    /// Get the referral URL directly (for analytics or deep linking)
    func referralURL(for exchangeName: String) -> URL? {
        affiliateInfo(for: exchangeName).referralURL
    }
    
    // MARK: - Private Helpers
    
    /// Normalize exchange name to ID format
    private func normalizeExchangeId(_ name: String) -> String {
        let lowercased = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle special cases
        if lowercased.contains("binance") && lowercased.contains("us") {
            return "binance_us"
        }
        
        // Remove common suffixes and clean up
        let cleaned = lowercased
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "exchange", with: "")
            .replacingOccurrences(of: ".com", with: "")
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        
        // Map to known exchange IDs
        switch cleaned {
        case let s where s.contains("binance") && s.contains("us"):
            return "binance_us"
        case let s where s.contains("binance"):
            return "binance"
        case let s where s.contains("coinbase"):
            return "coinbase"
        case let s where s.contains("bybit"):
            return "bybit"
        case let s where s.contains("kucoin"):
            return "kucoin"
        case let s where s.contains("kraken"):
            return "kraken"
        case let s where s.contains("okx") || s.contains("okex"):
            return "okx"
        case let s where s.contains("gate"):
            return "gate"
        case let s where s.contains("huobi") || s.contains("htx"):
            return "huobi"
        default:
            return cleaned
        }
    }
}

// MARK: - Setup Instructions

extension ExchangeAffiliateManager {
    
    /// Get instructions for setting up affiliate program for an exchange
    static func setupInstructions(for exchangeId: String) -> String {
        let programs: [String: String] = [
            "binance": """
                Binance Affiliate Program Setup:
                1. Go to https://www.binance.com/en/activity/affiliate
                2. Click "Apply Now" and log in with your Binance account
                3. Fill out the application (you'll need to describe your app/website)
                4. Once approved, get your referral code from the dashboard
                5. Update ExchangeAffiliateManager.swift with your referral code
                
                Commission: Up to 50% of referred users' trading fees
                """,
            
            "coinbase": """
                Coinbase Affiliate Program Setup:
                1. Go to https://www.coinbase.com/affiliates
                2. Click "Apply Now"
                3. Fill out the application form
                4. Once approved, get your referral link from the dashboard
                5. Update ExchangeAffiliateManager.swift with your referral code
                
                Commission: $10 per new user (varies by region)
                """,
            
            "bybit": """
                Bybit Affiliate Program Setup:
                1. Go to https://www.bybit.com/en/affiliate
                2. Click "Apply Now" or "Become a Partner"
                3. Fill out the application
                4. Once approved, get your referral code
                5. Update ExchangeAffiliateManager.swift with your code
                
                Commission: Up to 30% of referred users' trading fees
                """,
            
            "kucoin": """
                KuCoin Affiliate Program Setup:
                1. Go to https://www.kucoin.com/affiliate
                2. Apply for the affiliate program
                3. Once approved, get your referral code
                4. Update ExchangeAffiliateManager.swift with your code
                
                Commission: Up to 45% of referred users' trading fees
                """
        ]
        
        return programs[exchangeId] ?? """
            To set up affiliate program for \(exchangeId):
            1. Visit the exchange's affiliate/partner page
            2. Apply for their affiliate program
            3. Once approved, get your referral code/link
            4. Update ExchangeAffiliateManager.swift with your code
            """
    }
    
    /// Print all setup instructions (for developer reference)
    static func printAllSetupInstructions() {
        print("""
        ===============================================
        EXCHANGE AFFILIATE PROGRAM SETUP INSTRUCTIONS
        ===============================================
        
        To monetize exchange signups through CryptoSage:
        
        1. BINANCE
        \(setupInstructions(for: "binance"))
        
        2. COINBASE
        \(setupInstructions(for: "coinbase"))
        
        3. BYBIT
        \(setupInstructions(for: "bybit"))
        
        4. KUCOIN
        \(setupInstructions(for: "kucoin"))
        
        After getting your referral codes, update the
        referralURLs dictionary in ExchangeAffiliateManager.swift
        ===============================================
        """)
    }
}
