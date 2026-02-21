import SwiftUI

/// Describes a subscription tier and its benefits.
struct SubscriptionTier: Identifiable {
    let id = UUID()
    let name: String
    let monthlyPrice: String
    let yearlyPrice: String
    let yearlySavings: String?
    let features: [String]
    let isRecommended: Bool
    let tierType: SubscriptionTierType
    let iconName: String
    let gradientColors: [Color]
}

/// A polished subscription pricing view for CryptoSage AI.
struct SubscriptionPricingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var storeKitManager = StoreKitManager.shared
    
    // Gold accent for pricing cards
    private let accentGold = Color(red: 0.85, green: 0.65, blue: 0.13)
    private let lightGold = Color(red: 0.95, green: 0.85, blue: 0.60)
    
    @State private var annualBilling = false
    @State private var showPurchaseSuccess = false
    @State private var showPurchaseError = false
    @State private var showRestoreSuccess = false
    @State private var selectedTierName: String = ""
    @State private var animateCards = false
    @State private var isPurchasing = false
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)

    // Base tiers available to all users (simplified 3-tier structure)
    private let baseTiers: [SubscriptionTier] = [
        SubscriptionTier(
            name: "Free",
            monthlyPrice: "$0",
            yearlyPrice: "$0",
            yearlySavings: nil,
            features: [
                "All market data & portfolio tracking",
                "Unlimited exchange & wallet connections",
                "Basic charts and heatmaps",
                "AI Chat (5/day, top 5 coins)",
                "AI Predictions (1/day, top 5 coins)",
                "AI Coin Insights (2/day, top 5 coins)",
                "Price alerts (3 active)",
                "Ad-supported experience"
            ],
            isRecommended: false,
            tierType: .free,
            iconName: "person.circle.fill",
            gradientColors: [Color.gray.opacity(0.3), Color.gray.opacity(0.1)]
        ),
        SubscriptionTier(
            name: "Pro",
            monthlyPrice: "$9.99",
            yearlyPrice: "$89.99",
            yearlySavings: "Save 25%",
            features: [
                "Everything in Free",
                "AI Chat (30/day, all coins)",
                "AI Predictions (5/day, all coins)",
                "AI Coin Insights (10/day)",
                "AI Portfolio Analysis (5/day)",
                "AI Risk Reports",
                "Paper Trading ($100k virtual portfolio)",
                "Whale Tracking & Smart Money Alerts",
                "Tax Reports (up to 2,500 transactions)",
                "Unlimited price alerts",
                "Advanced + AI-Enhanced Price Alerts",
                "AI Market + Portfolio Monitoring Alerts",
                "Ad-free experience"
            ],
            isRecommended: true,
            tierType: .pro,
            iconName: "star.circle.fill",
            gradientColors: [Color(red: 0.85, green: 0.65, blue: 0.13), Color(red: 0.7, green: 0.5, blue: 0.1)]
        ),
        SubscriptionTier(
            name: "Premium",
            monthlyPrice: "$19.99",
            yearlyPrice: "$179.99",
            yearlySavings: "Save 25%",
            features: [
                "Everything in Pro",
                "Unlimited AI Chat",
                "AI Predictions (20/day)",
                "AI Coin Insights (30/day)",
                "AI Portfolio Analysis (20/day)",
                "Paper Trading Bots (DCA, Grid, Signal)",
                "Paper Derivatives (futures & perpetuals)",
                "Custom Strategy Builder",
                "Strategy & Bot Marketplace",
                "Arbitrage Scanner",
                "Unlimited Tax Transactions",
                "DeFi Yield Insights",
                "Early Access Features"
            ],
            isRecommended: false,
            tierType: .premium,
            iconName: "crown.fill",
            gradientColors: [Color.purple, Color(red: 0.5, green: 0.2, blue: 0.7)]
        )
    ]
    
    // Special Developer tier - only visible in developer mode
    private let developerTier = SubscriptionTier(
        name: "Developer",
        monthlyPrice: "$0",
        yearlyPrice: "$0",
        yearlySavings: "Internal Only",
        features: [
            "Everything in Premium",
            "Truly unlimited AI (no caps)",
            "Tier simulator for testing",
            "Debug tools",
            "No usage tracking"
        ],
        isRecommended: false,
        tierType: .premium, // Uses Premium tier type for full access
        iconName: "wrench.and.screwdriver.fill",
        gradientColors: [Color.orange, Color.red]
    )
    
    // Computed property that includes Developer tier when in dev mode
    private var tiers: [SubscriptionTier] {
        if subscriptionManager.isDeveloperMode {
            return baseTiers + [developerTier]
        }
        return baseTiers
    }

var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Custom header
                subscriptionHeader
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Hero section
                        heroSection
                            .padding(.top, 8)
                        
                        // Billing toggle
                        billingToggle
                            .padding(.horizontal, 20)
                        
                        // Subscription cards
                        VStack(spacing: 20) {
                            ForEach(Array(tiers.enumerated()), id: \.element.id) { index, tier in
                                EnhancedPricingCard(
                                    tier: tier,
                                    annual: annualBilling,
                                    isCurrentTier: isCurrentTier(tier),
                                    isPurchasing: isPurchasing,
                                    storeKitManager: storeKitManager,
                                    onSelect: {
                                        handleTierSelection(tier)
                                    }
                                )
                                .opacity(animateCards ? 1 : 0)
                                .offset(y: animateCards ? 0 : 30)
                                .animation(
                                    .spring(response: 0.6, dampingFraction: 0.8)
                                    .delay(Double(index) * 0.15),
                                    value: animateCards
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Restore and terms
                        footerSection
                            .padding(.top, 16)
                            .padding(.bottom, 32)
                    }
                }
            }
            .disabled(isPurchasing)
            
            // Purchase loading overlay
            if isPurchasing {
                purchaseLoadingOverlay
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                animateCards = true
            }
            // Load products from StoreKit
            Task {
                await storeKitManager.loadProducts()
            }
        }
        .alert("Subscription Updated", isPresented: $showPurchaseSuccess) {
            Button("OK") {
                impactLight.impactOccurred()
                dismiss()
            }
        } message: {
            Text("You are now subscribed to \(selectedTierName)!")
        }
        .alert("Purchase Failed", isPresented: $showPurchaseError) {
            Button("OK") {
                storeKitManager.resetPurchaseState()
            }
        } message: {
            Text(storeKitManager.errorMessage ?? "An error occurred during purchase. Please try again.")
        }
        .alert("Purchases Restored", isPresented: $showRestoreSuccess) {
            Button("OK") {
                storeKitManager.resetPurchaseState()
                if storeKitManager.hasActiveSubscription {
                    dismiss()
                }
            }
        } message: {
            if storeKitManager.hasActiveSubscription {
                Text("Your subscription has been restored successfully!")
            } else {
                Text(storeKitManager.errorMessage ?? "No active subscriptions found.")
            }
        }
        .onChange(of: storeKitManager.purchaseState) { _, newState in
            switch newState {
            case .purchased:
                isPurchasing = false
                showPurchaseSuccess = true
            case .failed:
                isPurchasing = false
                showPurchaseError = true
            case .restored:
                isPurchasing = false
                showRestoreSuccess = true
            case .idle, .pending:
                isPurchasing = false
            default:
                break
            }
        }
    }
    
    // MARK: - Purchase Loading Overlay
    
    private var purchaseLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: accentGold))
                    .scaleEffect(1.5)
                
                Text("Processing...")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Please wait while we complete your purchase")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.8))
            )
        }
    }
    
    // MARK: - Header
    
    private var subscriptionHeader: some View {
        HStack {
            CSNavButton(
                icon: "chevron.left",
                action: { dismiss() }
            )
            
            Spacer()
            
            Text("Choose Your Plan")
                .font(.headline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Color.clear
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.Adaptive.background)
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 16) {
            // Animated crown icon
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accentGold.opacity(0.4), accentGold.opacity(0)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                
                // Inner circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentGold.opacity(0.3), accentGold.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(accentGold.opacity(0.5), lineWidth: 2)
                    )
                
                Image(systemName: "crown.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentGold, lightGold],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            Text("Unlock Premium Features")
                .font(.title2.weight(.bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Choose the plan that's right for you and unlock the full power of AI-driven crypto intelligence.")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
    
    // MARK: - Billing Toggle
    
    private var billingToggle: some View {
        VStack(spacing: 12) {
            // Custom segmented control
            HStack(spacing: 0) {
                billingOption(title: "Monthly", isSelected: !annualBilling) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        annualBilling = false
                    }
                    impactLight.impactOccurred()
                }
                
                billingOption(title: "Annual", isSelected: annualBilling, badge: "Save 25%") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        annualBilling = true
                    }
                    impactLight.impactOccurred()
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                    )
            )
        }
    }
    
    private func billingOption(title: String, isSelected: Bool, badge: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                
                if let badge = badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.green : Color.green.opacity(0.3))
                        )
                        .foregroundColor(.white)
                }
            }
            .foregroundColor(isSelected ? .white : DS.Adaptive.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? accentGold : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Footer
    
    @State private var showTerms = false
    @State private var showPrivacy = false
    
    private var footerSection: some View {
        VStack(spacing: 16) {
            Button(action: {
                impactLight.impactOccurred()
                restorePurchases()
            }) {
                HStack(spacing: 8) {
                    if storeKitManager.purchaseState == .loading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: accentGold))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                    Text("Restore Purchases")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(accentGold)
            }
            .disabled(storeKitManager.purchaseState == .loading || isPurchasing)
            
            VStack(spacing: 4) {
                if storeKitManager.hasAnyTrialAvailable {
                    Text("Free trial available. No charge until trial ends.")
                        .padding(.bottom, 2)
                }
                Text("All trading features use simulated paper trading with virtual funds.")
                    .padding(.bottom, 2)
                Text("Subscription automatically renews unless cancelled.")
                Text("Cancel anytime in Settings > Subscriptions.")
            }
            .font(.caption2)
            .foregroundColor(DS.Adaptive.textTertiary)
            .multilineTextAlignment(.center)
            
            // Terms & Privacy — required by Apple for subscription screens
            HStack(spacing: 4) {
                Button { showTerms = true } label: {
                    Text("Terms of Service")
                        .underline()
                }
                Text("and")
                Button { showPrivacy = true } label: {
                    Text("Privacy Policy")
                        .underline()
                }
            }
            .font(.caption2)
            .foregroundColor(DS.Adaptive.textTertiary)
            .sheet(isPresented: $showTerms) {
                NavigationStack { TermsOfServiceView() }
            }
            .sheet(isPresented: $showPrivacy) {
                NavigationStack { PrivacyPolicyView() }
            }
            
            // Trust badges
            HStack(spacing: 24) {
                trustBadge(icon: "lock.shield.fill", text: "Secure")
                trustBadge(icon: "checkmark.seal.fill", text: "Verified")
                trustBadge(icon: "arrow.uturn.backward.circle.fill", text: "Refundable")
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - Restore Purchases
    
    private func restorePurchases() {
        Task {
            await storeKitManager.restorePurchases()
            showRestoreSuccess = true
        }
    }
    
    private func trustBadge(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(DS.Adaptive.textTertiary)
            Text(text)
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
        }
    }
    
    /// Check if a tier is the current active tier
    private func isCurrentTier(_ tier: SubscriptionTier) -> Bool {
        // Developer tier is current when dev mode is active
        if tier.name == "Developer" {
            return subscriptionManager.isDeveloperMode
        }
        // For regular tiers, check against current tier (or simulated tier in dev mode)
        return subscriptionManager.effectiveTier == tier.tierType
    }
    
    private func handleTierSelection(_ tier: SubscriptionTier) {
        impactHeavy.impactOccurred()
        selectedTierName = tier.name
        
        // Developer tier - already in dev mode, just confirm
        if tier.name == "Developer" {
            // Set simulated tier to Premium for full access
            subscriptionManager.developerSimulatedTier = .premium
            showPurchaseSuccess = true
            return
        }
        
        // Free tier doesn't need purchase
        if tier.tierType == .free {
            subscriptionManager.setTier(.free)
            showPurchaseSuccess = true
            return
        }
        
        // Start purchase flow
        isPurchasing = true
        
        Task {
            let success = await storeKitManager.purchaseSubscription(
                tier: tier.tierType,
                isAnnual: annualBilling
            )
            
            await MainActor.run {
                if success {
                    // Purchase successful - state will be updated via onChange
                } else if storeKitManager.purchaseState == .pending {
                    // Purchase is pending (Ask to Buy)
                    isPurchasing = false
                } else if storeKitManager.purchaseState == .idle {
                    // User cancelled
                    isPurchasing = false
                }
                // Error case is handled by onChange observer
            }
        }
    }
}

// MARK: - Enhanced Pricing Card

private struct EnhancedPricingCard: View {
    let tier: SubscriptionTier
    let annual: Bool
    let isCurrentTier: Bool
    let isPurchasing: Bool
    let storeKitManager: StoreKitManager
    let onSelect: () -> Void
    
    @State private var isPressed = false
    
    private var tierGradient: LinearGradient {
        LinearGradient(
            colors: tier.gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var accentGold: Color {
        Color(red: 0.85, green: 0.65, blue: 0.13)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header section with tier info
            cardHeader
            
            // Features section
            cardFeatures
            
            // Price and CTA section
            cardFooter
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(cardBorderColor, lineWidth: cardBorderWidth)
        )
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
    }
    
    // MARK: - Card Header
    
    private var cardHeader: some View {
        HStack(alignment: .center) {
            // Tier icon and name
            HStack(spacing: 12) {
                // Icon with gradient background
                ZStack {
                    Circle()
                        .fill(tierGradient.opacity(0.3))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: tier.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tierGradient)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                    Text(tier.name)
                            .font(.title3.weight(.bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        if tier.isRecommended {
                            Text("POPULAR")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(accentGold)
                                )
                                .foregroundColor(.white)
                        }
                        
                        if isCurrentTier {
                            Text("ACTIVE")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.green)
                                )
                                .foregroundColor(.white)
                        }
                    }
                    
                    Text(tierDescription)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
            
            Spacer()
            
            // Price display
            VStack(alignment: .trailing, spacing: 2) {
                Text(displayPrice)
                    .font(.title2.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(pricePeriod)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(tierGradient.opacity(0.1))
                .mask(
                    VStack {
                        Rectangle()
                        Rectangle()
                            .frame(height: 0)
                    }
                )
        )
    }
    
    // MARK: - Card Features
    
    private var cardFeatures: some View {
        VStack(alignment: .leading, spacing: 10) {
                    ForEach(tier.features, id: \.self) { feature in
                HStack(alignment: .top, spacing: 10) {
                            Image(systemName: featureIcon(feature))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tierGradient)
                        .frame(width: 20)
                    
                            Text(feature)
                                .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
    
    // MARK: - Card Footer
    
    private var cardFooter: some View {
        VStack(spacing: 12) {
            // Free trial badge
            if let trial = trialText, !isCurrentTier, tier.tierType != .free {
                HStack(spacing: 6) {
                    Image(systemName: "gift.fill")
                        .font(.caption)
                    Text(trial.capitalized + ", then \(displayPrice)/\(annual ? "mo" : "month")")
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.12))
                )
            }
            
            // Annual savings badge
            if annual, let savings = savingsText {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.caption)
                    Text(savings)
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.15))
                )
            }
            
            // CTA Button
            Button(action: {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                    onSelect()
                }
            }) {
                HStack(spacing: 8) {
                    if isCurrentTier {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(buttonText)
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(buttonTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(buttonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(isButtonDisabled)
            .opacity(isButtonDisabled ? 0.7 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Computed Properties
    
    private var tierDescription: String {
        switch tier.tierType {
        case .free: return "Get started for free"
        case .pro: return "Full AI toolkit for serious traders"
        case .premium: return "The ultimate AI trading experience"
        }
    }
    
    private var displayPrice: String {
        if tier.tierType == .free {
            return "$0"
        }
        
        // Try to get price from StoreKit
        if annual {
            // For annual, show monthly equivalent
            let monthlyEquiv = storeKitManager.monthlyEquivalent(for: tier.tierType)
            if !monthlyEquiv.isEmpty {
                return monthlyEquiv
            }
            // Fallback to hardcoded monthly equivalent for annual
            switch tier.tierType {
            case .pro: return "$7.50"      // $89.99/12
            case .premium: return "$15"    // $179.99/12
            default: return tier.yearlyPrice
            }
        } else {
            // Monthly price from StoreKit
            let storePrice = storeKitManager.monthlyPrice(for: tier.tierType)
            if storePrice != tier.tierType.monthlyPrice {
                return storePrice
            }
            return tier.monthlyPrice
        }
    }
    
    private var pricePeriod: String {
        if tier.tierType == .free {
            return "forever"
        }
        if annual {
            // Show actual annual price
            let annualPrice = storeKitManager.annualPrice(for: tier.tierType)
            if !annualPrice.isEmpty {
                return "per month (\(annualPrice)/year)"
            }
            return "per month, billed annually"
        }
        return "per month"
    }
    
    private var savingsText: String? {
        guard tier.tierType != .free else { return nil }
        let savings = storeKitManager.annualSavingsPercent(for: tier.tierType)
        if savings > 0 {
            return "Save \(savings)%/year"
        }
        return tier.yearlySavings
    }
    
    private var trialText: String? {
        storeKitManager.trialDescription(for: tier.tierType, isAnnual: annual)
    }
    
    private var buttonText: String {
        if isCurrentTier {
            return "Current Plan"
        }
        if tier.tierType == .free {
            return "Continue with Free"
        }
        // Show "Start Free Trial" if a trial is available
        if let trial = trialText {
            return "Start \(trial)"
        }
        return "Upgrade to \(tier.name)"
    }
    
    private var buttonTextColor: Color {
        if isCurrentTier {
            return .white.opacity(0.7)
        }
        if tier.tierType == .free {
            return DS.Adaptive.textPrimary
        }
        return .white
    }
    
    private var isButtonDisabled: Bool {
        isCurrentTier || isPurchasing
    }
    
    private var buttonBackground: some View {
        Group {
            if isCurrentTier {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.4))
            } else if tier.tierType == .free {
                RoundedRectangle(cornerRadius: 14)
                    .fill(DS.Adaptive.stroke)
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(tierGradient)
            }
        }
    }
    
    private var cardBorderColor: Color {
        if isCurrentTier {
            return .green
        }
        if tier.isRecommended {
            return accentGold
        }
        return DS.Adaptive.stroke
    }
    
    private var cardBorderWidth: CGFloat {
        if isCurrentTier || tier.isRecommended {
            return 2
        }
        return 1
    }
    
    private var cardShadowColor: Color {
        if tier.isRecommended {
            return accentGold.opacity(0.2)
        }
        if tier.tierType == .premium {
            return Color.purple.opacity(0.15)
        }
        return Color.black.opacity(0.1)
    }
}

// MARK: - Feature Icon Helper

private func featureIcon(_ feature: String) -> String {
    let lower = feature.lowercased()
    switch true {
    case lower.contains("everything in"):
        return "checkmark.circle.fill"
    case lower.contains("trading bots") || lower.contains("dca") || lower.contains("grid") || lower.contains("signal"):
        return "cpu.fill"
    case lower.contains("derivatives"):
        return "arrow.up.arrow.down.circle.fill"
    case lower.contains("custom") && lower.contains("strateg"):
        return "slider.horizontal.3"
    case lower.contains("copy trading") || lower.contains("bot marketplace") || lower.contains("strategy") && lower.contains("marketplace"):
        return "doc.on.doc.fill"
    case lower.contains("arbitrage"):
        return "arrow.triangle.2.circlepath"
    case lower.contains("risk"):
        return "shield.lefthalf.filled"
    case lower.contains("paper trading"):
        return "doc.text.fill"
    case lower.contains("unlimited") && lower.contains("exchange"):
        return "link.circle.fill"
    case lower.contains("connect"):
        return "link.circle.fill"
    case lower.contains("wallet"):
        return "wallet.pass.fill"
    case lower.contains("exchange"):
        return "bitcoinsign.circle.fill"
    case lower.contains("market data") || lower.contains("portfolio tracking"):
        return "chart.line.uptrend.xyaxis"
    case lower.contains("heatmap") || lower.contains("chart"):
        return "square.grid.3x3.fill"
    case lower.contains("prediction"):
        return "wand.and.stars"
    case lower.contains("portfolio analysis"):
        return "chart.pie.fill"
    case lower.contains("insight") || lower.contains("analysis"):
        return "lightbulb.fill"
    case lower.contains("chat") || lower.contains("prompts"):
        return "bubble.left.and.bubble.right.fill"
    case lower.contains("gpt-4") || lower.contains("premium") && lower.contains("ai"):
        return "sparkles"
    case lower.contains("whale"):
        return "water.waves"
    case lower.contains("smart") && lower.contains("money"):
        return "dollarsign.arrow.circlepath"
    case lower.contains("ai-powered"):
        return "bell.badge.fill"
    case lower.contains("alert"):
        return "bell.fill"
    case lower.contains("tax"):
        return "doc.text.fill"
    case lower.contains("social") || lower.contains("leaderboard"):
        return "person.2.fill"
    case lower.contains("profile"):
        return "person.crop.circle.fill"
    case lower.contains("ad-supported"):
        return "megaphone.fill"
    case lower.contains("ad-free"):
        return "checkmark.seal.fill"
    case lower.contains("early access"):
        return "clock.badge.checkmark.fill"
    case lower.contains("defi") || lower.contains("yield"):
        return "leaf.fill"
    case lower.contains("unlimited"):
        return "infinity"
    default:
        return "checkmark.circle.fill"
    }
}

// MARK: - Preview

struct SubscriptionPricingView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionPricingView()
            .environmentObject(PortfolioViewModel.sample)
            .preferredColorScheme(.dark)
    }
}
