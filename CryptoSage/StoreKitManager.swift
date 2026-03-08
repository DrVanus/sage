//
//  StoreKitManager.swift
//  CryptoSage
//
//  Handles StoreKit 2 in-app purchases for subscription management.
//

import Foundation
import StoreKit
import SwiftUI

// MARK: - Product IDs

/// Product identifiers for CryptoSage subscriptions
/// These must match the product IDs configured in App Store Connect
///
/// New simplified pricing (3-tier structure):
/// - Pro Monthly: $9.99/month
/// - Pro Annual: $89.99/year (saves 25%)
/// - Premium Monthly: $19.99/month
/// - Premium Annual: $179.99/year (saves 25%)
///
/// Legacy product IDs (for existing subscribers):
/// - Elite Monthly/Annual -> maps to Premium
/// - Platinum Monthly/Annual -> maps to Premium
public enum SubscriptionProductID: String, CaseIterable {
    // Monthly subscriptions (new pricing)
    case proMonthly = "com.cryptosage.pro.monthly"            // $9.99/month
    case premiumMonthly = "com.cryptosage.premium.monthly"    // $19.99/month
    
    // Annual subscriptions (new pricing)
    case proAnnual = "com.cryptosage.pro.annual"              // $89.99/year
    case premiumAnnual = "com.cryptosage.premium.annual"      // $179.99/year
    
    // Legacy product IDs (kept for migration - map to Premium)
    case eliteMonthly = "com.cryptosage.elite.monthly"        // Legacy -> Premium
    case eliteAnnual = "com.cryptosage.elite.annual"          // Legacy -> Premium
    case platinumMonthly = "com.cryptosage.platinum.monthly"  // Legacy -> Premium
    case platinumAnnual = "com.cryptosage.platinum.annual"    // Legacy -> Premium
    
    /// All product IDs as strings
    static var allIDs: [String] {
        allCases.map { $0.rawValue }
    }
    
    /// New product IDs only (excluding legacy)
    static var newProductIDs: [String] {
        [proMonthly, proAnnual, premiumMonthly, premiumAnnual].map { $0.rawValue }
    }
    
    /// The tier this product grants
    var tier: SubscriptionTierType {
        switch self {
        case .proMonthly, .proAnnual:
            return .pro
        // Premium tier (includes legacy Elite and Platinum)
        case .premiumMonthly, .premiumAnnual,
             .eliteMonthly, .eliteAnnual,
             .platinumMonthly, .platinumAnnual:
            return .premium
        }
    }
    
    /// Whether this is an annual subscription
    var isAnnual: Bool {
        switch self {
        case .proAnnual, .premiumAnnual, .eliteAnnual, .platinumAnnual:
            return true
        case .proMonthly, .premiumMonthly, .eliteMonthly, .platinumMonthly:
            return false
        }
    }
    
    /// Whether this is a legacy product ID
    var isLegacy: Bool {
        switch self {
        case .eliteMonthly, .eliteAnnual, .platinumMonthly, .platinumAnnual:
            return true
        default:
            return false
        }
    }
}

// MARK: - Purchase State

public enum PurchaseState: Equatable {
    case idle
    case loading
    case purchasing
    case purchased
    case failed(String)
    case pending
    case restored
    
    public static func == (lhs: PurchaseState, rhs: PurchaseState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.purchasing, .purchasing),
             (.purchased, .purchased), (.pending, .pending), (.restored, .restored):
            return true
        case (.failed(let l), .failed(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - StoreKit Manager

@MainActor
public final class StoreKitManager: ObservableObject {
    public static let shared = StoreKitManager()
    
    // MARK: - Published Properties
    
    /// Available products fetched from App Store
    @Published public private(set) var products: [Product] = []
    
    /// Current purchase state
    @Published public private(set) var purchaseState: PurchaseState = .idle
    
    /// Whether products are loading
    @Published public private(set) var isLoadingProducts: Bool = false
    
    /// Error message if any
    @Published public private(set) var errorMessage: String?
    
    /// Currently active subscription product ID
    @Published public private(set) var activeSubscriptionID: String?
    
    /// Expiration date of current subscription
    @Published public private(set) var subscriptionExpirationDate: Date?
    
    /// Whether the subscription will auto-renew
    @Published public private(set) var willAutoRenew: Bool = false
    
    // MARK: - Private Properties
    
    private var updateListenerTask: Task<Void, Error>?
    
    // MARK: - Initialization
    
    private init() {
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()
        
        // Load products on init
        _ = Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Product Loading
    
    /// Track if products have been loaded to prevent duplicate requests
    private var hasLoadedProducts: Bool = false
    /// Avoid repeated empty-product warning spam in debug sessions.
    private var hasLoggedEmptyProductsWarning: Bool = false
    
    /// Load available products from App Store
    /// - Parameter force: If true, reload even if products were already loaded
    public func loadProducts(force: Bool = false) async {
        // Prevent duplicate requests unless forced
        guard !isLoadingProducts else {
            #if DEBUG
            print("[StoreKit] Already loading products, skipping duplicate request")
            #endif
            return
        }
        
        // Skip if already loaded unless forced
        guard !hasLoadedProducts || force else {
            #if DEBUG
            print("[StoreKit] Products already loaded, skipping (use force: true to reload)")
            #endif
            return
        }
        
        isLoadingProducts = true
        errorMessage = nil
        
        let requestedIDs = SubscriptionProductID.allIDs
        #if DEBUG
        print("[StoreKit] Requesting products with IDs: \(requestedIDs)")
        print("[StoreKit] Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        #endif
        
        do {
            let storeProducts = try await Product.products(for: requestedIDs)
            
            // Sort products: Pro before Elite, Monthly before Annual
            products = storeProducts.sorted { p1, p2 in
                let id1 = SubscriptionProductID(rawValue: p1.id)
                let id2 = SubscriptionProductID(rawValue: p2.id)
                
                guard let id1 = id1, let id2 = id2 else { return false }
                
                // Pro comes before Elite
                if id1.tier != id2.tier {
                    return id1.tier == .pro
                }
                // Monthly comes before Annual
                return !id1.isAnnual && id2.isAnnual
            }
            
            isLoadingProducts = false
            hasLoadedProducts = true
            
            #if DEBUG
            print("[StoreKit] Loaded \(products.count) products:")
            for product in products {
                print("  - \(product.id): \(product.displayName) - \(product.displayPrice)")
            }
            if products.isEmpty {
                if !hasLoggedEmptyProductsWarning {
                    hasLoggedEmptyProductsWarning = true
                    print("[StoreKit] ⚠️ No products returned - verify App Store Connect product configuration")
                }
            } else {
                hasLoggedEmptyProductsWarning = false
            }
            #endif
            
        } catch {
            isLoadingProducts = false
            // Don't set hasLoadedProducts on error - allow retry
            errorMessage = "Failed to load products: \(error.localizedDescription)"
            #if DEBUG
            print("[StoreKit] Error loading products: \(error)")
            print("[StoreKit] ⚠️ This often means products don't exist in App Store Connect")
            #endif
        }
    }
    
    // MARK: - Purchasing
    
    /// Purchase a product
    /// - Parameter product: The StoreKit Product to purchase
    /// - Returns: True if purchase was successful
    @discardableResult
    public func purchase(_ product: Product) async -> Bool {
        purchaseState = .purchasing
        errorMessage = nil
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // Check if the transaction is verified
                switch verification {
                case .verified(let transaction):
                    // Grant the user access
                    await handleVerifiedTransaction(transaction)
                    await transaction.finish()
                    purchaseState = .purchased
                    return true
                    
                case .unverified(_, let error):
                    purchaseState = .failed("Transaction verification failed: \(error.localizedDescription)")
                    errorMessage = "Purchase could not be verified"
                    return false
                }
                
            case .userCancelled:
                purchaseState = .idle
                return false
                
            case .pending:
                purchaseState = .pending
                errorMessage = "Purchase is pending approval (e.g., Ask to Buy)"
                return false
                
            @unknown default:
                purchaseState = .failed("Unknown purchase result")
                return false
            }
            
        } catch {
            purchaseState = .failed(error.localizedDescription)
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            #if DEBUG
            print("[StoreKit] Purchase error: \(error)")
            #endif
            return false
        }
    }
    
    /// Purchase a subscription by tier and billing period
    /// - Parameters:
    ///   - tier: The subscription tier to purchase
    ///   - isAnnual: Whether to purchase annual (true) or monthly (false)
    /// - Returns: True if purchase was successful
    @discardableResult
    public func purchaseSubscription(tier: SubscriptionTierType, isAnnual: Bool) async -> Bool {
        let productID: SubscriptionProductID
        
        switch (tier, isAnnual) {
        case (.pro, false):
            productID = .proMonthly
        case (.pro, true):
            productID = .proAnnual
        case (.premium, false):
            productID = .premiumMonthly
        case (.premium, true):
            productID = .premiumAnnual
        case (.free, _):
            // Can't purchase free tier
            return false
        }
        
        guard let product = products.first(where: { $0.id == productID.rawValue }) else {
            errorMessage = "Product not found. Please try again."
            purchaseState = .failed("Product not available")
            AnalyticsService.shared.trackSubscriptionUpgradeFailed(tier: tier.rawValue, reason: "product_not_found")
            return false
        }
        
        // Track upgrade attempt
        let currentTier = SubscriptionManager.shared.effectiveTier
        AnalyticsService.shared.trackSubscriptionUpgradeStarted(
            fromTier: currentTier.rawValue,
            toTier: tier.rawValue,
            isAnnual: isAnnual
        )
        
        let success = await purchase(product)
        
        // Track result
        if success {
            AnalyticsService.shared.trackSubscriptionUpgradeCompleted(tier: tier.rawValue, isAnnual: isAnnual)
        } else if purchaseState != .idle { // Don't track if user cancelled
            AnalyticsService.shared.trackSubscriptionUpgradeFailed(tier: tier.rawValue, reason: errorMessage ?? "unknown")
        }
        
        return success
    }
    
    // MARK: - Restore Purchases
    
    /// Restore previous purchases
    public func restorePurchases() async {
        purchaseState = .loading
        errorMessage = nil
        
        do {
            // Sync with App Store to get the latest transaction history
            try await AppStore.sync()
            
            // Check current entitlements
            await updateSubscriptionStatus()
            
            if activeSubscriptionID != nil {
                purchaseState = .restored
                
                // ANALYTICS: Track successful subscription restore
                let tier = currentSubscriptionTier.rawValue
                AnalyticsService.shared.trackSubscriptionRestored(tier: tier)
            } else {
                purchaseState = .idle
                errorMessage = "No active subscriptions found to restore"
            }
            
        } catch {
            purchaseState = .failed(error.localizedDescription)
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
            #if DEBUG
            print("[StoreKit] Restore error: \(error)")
            #endif
        }
    }
    
    // MARK: - Subscription Status
    
    /// Update subscription status from current entitlements
    ///
    /// THREAD SAFETY FIX: StoreKit's `Transaction.currentEntitlements` async sequence may
    /// deliver values on a background thread. Even though this class is @MainActor, the
    /// `for await` loop can resume off the main thread. To prevent "Publishing changes from
    /// background threads" warnings, we collect entitlement data in a detached task
    /// (value types only), then update @Published properties once we're guaranteed
    /// back on @MainActor after the detached work completes.
    public func updateSubscriptionStatus() async {
        // Phase 1: Iterate StoreKit entitlements in a detached task — the async
        // sequence delivers on arbitrary threads, so we must NOT touch @Published
        // properties here.  We only collect Sendable value types.
        struct EntitlementInfo: Sendable {
            let productID: String
            let expirationDate: Date?
        }

        let allIDs = SubscriptionProductID.allIDs          // capture Sendable [String]

        let foundEntitlement: EntitlementInfo? = await Task.detached {
            for await result in StoreKit.Transaction.currentEntitlements {
                guard case .verified(let transaction) = result else { continue }

                if allIDs.contains(transaction.productID) {
                    if transaction.revocationDate == nil {
                        return EntitlementInfo(
                            productID: transaction.productID,
                            expirationDate: transaction.expirationDate
                        )
                    }
                }
            }
            return nil
        }.value

        // Phase 2: We're back on @MainActor now — safe to update @Published properties
        if let entitlement = foundEntitlement {
            activeSubscriptionID = entitlement.productID
            subscriptionExpirationDate = entitlement.expirationDate

            // Update the subscription tier in SubscriptionManager
            if let productID = SubscriptionProductID(rawValue: entitlement.productID) {
                SubscriptionManager.shared.setTier(productID.tier)
            }

            // Check auto-renewal status (runs after for-await loop, safely on MainActor)
            if let product = products.first(where: { $0.id == entitlement.productID }) {
                await updateAutoRenewalStatus(for: product)
            }

            #if DEBUG
            print("[StoreKit] Active subscription: \(entitlement.productID)")
            if let expiry = entitlement.expirationDate {
                print("[StoreKit] Expires: \(expiry)")
            }
            #endif
        } else {
            // No active subscription found — set tier to free
            activeSubscriptionID = nil
            subscriptionExpirationDate = nil
            willAutoRenew = false

            // Only reset to free if not in developer mode
            if !SubscriptionManager.shared.isDeveloperMode {
                SubscriptionManager.shared.setTier(.free)
            }
        }
    }
    
    /// Check auto-renewal status for a product
    private func updateAutoRenewalStatus(for product: Product) async {
        guard let subscription = product.subscription else {
            willAutoRenew = true // Default to true if we can't check
            return
        }
        
        do {
            let statuses = try await subscription.status
            for status in statuses {
                switch status.state {
                case .subscribed:
                    // Handle VerificationResult for renewal info
                    switch status.renewalInfo {
                    case .verified(let renewalInfo):
                        willAutoRenew = renewalInfo.willAutoRenew
                    case .unverified:
                        willAutoRenew = true // Default to true if unverified
                    }
                case .expired, .revoked:
                    willAutoRenew = false
                case .inBillingRetryPeriod, .inGracePeriod:
                    willAutoRenew = true
                default:
                    break
                }
            }
        } catch {
            #if DEBUG
            print("[StoreKit] Error checking renewal status: \(error)")
            #endif
            willAutoRenew = true
        }
    }
    
    // MARK: - Transaction Handling
    
    /// Handle a verified transaction
    private func handleVerifiedTransaction(_ transaction: StoreKit.Transaction) async {
        // Update subscription status
        if let productID = SubscriptionProductID(rawValue: transaction.productID) {
            SubscriptionManager.shared.setTier(productID.tier)
            activeSubscriptionID = transaction.productID
            subscriptionExpirationDate = transaction.expirationDate
        }
        
        #if DEBUG
        print("[StoreKit] Handled transaction: \(transaction.productID)")
        #endif
    }
    
    /// Listen for transaction updates
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            // Listen for transaction updates from App Store
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    
                    // Handle the transaction on main actor
                    await MainActor.run {
                        _ = Task {
                            await self.handleVerifiedTransaction(transaction)
                        }
                    }
                    
                    // Always finish transactions
                    await transaction.finish()
                    
                } catch {
                    #if DEBUG
                    print("[StoreKit] Transaction verification failed: \(error)")
                    #endif
                }
            }
        }
    }
    
    /// Verify a transaction result
    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let item):
            return item
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get product for a specific tier and billing period
    public func product(for tier: SubscriptionTierType, isAnnual: Bool) -> Product? {
        let productID: SubscriptionProductID
        
        switch (tier, isAnnual) {
        case (.pro, false): productID = .proMonthly
        case (.pro, true): productID = .proAnnual
        case (.premium, false): productID = .premiumMonthly
        case (.premium, true): productID = .premiumAnnual
        case (.free, _): return nil
        }
        
        return products.first { $0.id == productID.rawValue }
    }
    
    /// Get monthly price for a tier
    public func monthlyPrice(for tier: SubscriptionTierType) -> String {
        guard let product = product(for: tier, isAnnual: false) else {
            return tier.monthlyPrice // Fallback to hardcoded price
        }
        return product.displayPrice
    }
    
    /// Get annual price for a tier
    public func annualPrice(for tier: SubscriptionTierType) -> String {
        guard let product = product(for: tier, isAnnual: true) else {
            return "" // No fallback for annual
        }
        return product.displayPrice
    }
    
    /// Calculate monthly equivalent for annual subscription
    public func monthlyEquivalent(for tier: SubscriptionTierType) -> String {
        guard let product = product(for: tier, isAnnual: true) else { return "" }
        let monthlyAmount = product.price / 12
        return monthlyAmount.formatted(.currency(code: product.priceFormatStyle.currencyCode))
    }
    
    /// Calculate savings percentage for annual vs monthly
    public func annualSavingsPercent(for tier: SubscriptionTierType) -> Int {
        guard let monthly = product(for: tier, isAnnual: false),
              let annual = product(for: tier, isAnnual: true) else { return 0 }
        
        let monthlyYearCost = monthly.price * 12
        let annualCost = annual.price
        let savings = (monthlyYearCost - annualCost) / monthlyYearCost * 100
        // Convert Decimal to Double for rounding
        return Int((savings as NSDecimalNumber).doubleValue.rounded())
    }
    
    /// Reset purchase state to idle
    public func resetPurchaseState() {
        purchaseState = .idle
        errorMessage = nil
    }
    
    /// Check if user has an active subscription
    public var hasActiveSubscription: Bool {
        activeSubscriptionID != nil
    }
    
    /// Get the current subscription tier from active subscription
    public var currentSubscriptionTier: SubscriptionTierType {
        guard let activeID = activeSubscriptionID,
              let productID = SubscriptionProductID(rawValue: activeID) else {
            return .free
        }
        return productID.tier
    }
    
    /// Format subscription expiration date
    public var formattedExpirationDate: String? {
        guard let date = subscriptionExpirationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    /// Check if subscription is expiring soon (within 7 days)
    public var isExpiringSoon: Bool {
        guard let date = subscriptionExpirationDate else { return false }
        let daysUntilExpiry = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return daysUntilExpiry <= 7 && daysUntilExpiry >= 0
    }
    
    // MARK: - Free Trial / Introductory Offer Support
    
    /// Check if a product has an introductory offer (free trial)
    public func introductoryOffer(for tier: SubscriptionTierType, isAnnual: Bool) -> Product.SubscriptionOffer? {
        guard let product = product(for: tier, isAnnual: isAnnual),
              let subscription = product.subscription else { return nil }
        return subscription.introductoryOffer
    }
    
    /// Check if user is eligible for the introductory offer on a product
    /// Returns true if a trial/intro offer exists and the user hasn't used one before
    public func isEligibleForIntroOffer(for tier: SubscriptionTierType, isAnnual: Bool) async -> Bool {
        guard let product = product(for: tier, isAnnual: isAnnual),
              let subscription = product.subscription,
              subscription.introductoryOffer != nil else {
            return false
        }
        
        // Check if user is eligible (hasn't used an intro offer in this subscription group)
        do {
            let statuses = try await subscription.status
            // If there are no statuses, user has never subscribed = eligible
            if statuses.isEmpty { return true }
            
            // Check if any status indicates a prior subscription
            for status in statuses {
                switch status.state {
                case .subscribed, .inBillingRetryPeriod, .inGracePeriod:
                    // Currently subscribed — not eligible for trial
                    return false
                case .expired, .revoked:
                    // Previously subscribed — Apple may still allow intro offer
                    // but typically not. Let Apple handle this during purchase.
                    return false
                default:
                    continue
                }
            }
            return true
        } catch {
            // If we can't determine status, assume eligible and let Apple decide at purchase time
            #if DEBUG
            print("[StoreKit] Error checking intro offer eligibility: \(error)")
            #endif
            return true
        }
    }
    
    /// Get human-readable trial description for a product
    /// e.g. "7-day free trial" or "3-day free trial"
    public func trialDescription(for tier: SubscriptionTierType, isAnnual: Bool) -> String? {
        guard let offer = introductoryOffer(for: tier, isAnnual: isAnnual) else { return nil }
        
        // Only show for free trial type offers
        guard offer.paymentMode == .freeTrial else { return nil }
        
        let period = offer.period
        switch period.unit {
        case .day:
            return "\(period.value)-day free trial"
        case .week:
            let days = period.value * 7
            return "\(days)-day free trial"
        case .month:
            return "\(period.value)-month free trial"
        case .year:
            return "\(period.value)-year free trial"
        @unknown default:
            return "Free trial"
        }
    }
    
    /// Check if any paid product has a free trial available
    public var hasAnyTrialAvailable: Bool {
        for product in products {
            if let subscription = product.subscription,
               let introOffer = subscription.introductoryOffer,
               introOffer.paymentMode == .freeTrial {
                return true
            }
        }
        return false
    }
}

// MARK: - SwiftUI Environment Key

private struct StoreKitManagerKey: EnvironmentKey {
    // EnvironmentKey.defaultValue is nonisolated; resolve through MainActor explicitly.
    static var defaultValue: StoreKitManager {
        MainActor.assumeIsolated { StoreKitManager.shared }
    }
}

extension EnvironmentValues {
    var storeKitManager: StoreKitManager {
        get { self[StoreKitManagerKey.self] }
        set { self[StoreKitManagerKey.self] = newValue }
    }
}
