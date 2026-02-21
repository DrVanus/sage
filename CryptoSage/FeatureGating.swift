//
//  FeatureGating.swift
//  CryptoSage
//
//  Comprehensive feature gating system with different UX patterns:
//  - Hard paywall: Full lockout with upgrade CTA
//  - Soft paywall: Teaser preview with blur
//  - Action gating: View content but block actions
//  - Limit-based: Allow limited use, then prompt
//

import SwiftUI

// MARK: - Gating Style

/// Different UX patterns for feature gating
public enum GatingStyle {
    /// Full lockout - user cannot access anything without upgrading
    case hardPaywall
    
    /// Teaser preview - show partial content with blur
    case softPaywall
    
    /// Action gating - view content but block actions
    case actionGated
    
    /// Limit-based - allow limited use
    case limitBased
}

// MARK: - Hard Paywall View

/// A full-screen paywall that completely blocks access to a feature
public struct HardPaywallView: View {
    let feature: PremiumFeature
    let title: String?
    let subtitle: String?
    let benefits: [String]?
    var onDismiss: (() -> Void)?
    
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showSubscriptionView = false
    @State private var animateIn = false
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        feature: PremiumFeature,
        title: String? = nil,
        subtitle: String? = nil,
        benefits: [String]? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.feature = feature
        self.title = title
        self.subtitle = subtitle
        self.benefits = benefits
        self.onDismiss = onDismiss
    }
    
    private var hasAccess: Bool {
        subscriptionManager.hasAccess(to: feature)
    }
    
    private var tierColor: Color {
        feature.requiredTier == .premium ? .purple : BrandColors.goldBase
    }
    
    private var tierForegroundColor: Color {
        feature.requiredTier == .premium ? .white : .black.opacity(0.92)
    }
    
    private var defaultBenefits: [String] {
        switch feature {
        case .tradingBots:
            return [
                "Create automated DCA, Grid & Signal bots",
                "24/7 trading without manual intervention",
                "AI-powered strategy suggestions",
                "Multiple bots running simultaneously"
            ]
        case .copyTrading:
            return [
                "Copy top traders automatically",
                "Replicate profitable strategies",
                "Real-time portfolio mirroring",
                "Risk-adjusted position sizing"
            ]
        case .botMarketplace:
            return [
                "Access proven bot configurations",
                "Copy bots from successful traders",
                "Detailed performance history",
                "One-click bot deployment"
            ]
        case .derivativesFeatures:
            return [
                "Trade futures & perpetuals",
                "Up to 125x leverage",
                "Advanced order types",
                "Cross/isolated margin modes"
            ]
        case .taxReports:
            return [
                "Automated cost basis calculation",
                "Form 8949 & Schedule D export",
                "TurboTax, TaxAct integration",
                "Multiple accounting methods"
            ]
        default:
            return [
                feature.displayName,
                "Full feature access",
                "Priority performance",
                "Early access to new features"
            ]
        }
    }
    
    public var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background
            (colorScheme == .dark ? Color.black : Color(white: 0.95))
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Scrollable content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Hero icon - compact
                        heroIcon
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 20)
                        
                        // Title
                        Text(title ?? feature.displayName)
                            .font(.title2.weight(.bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .multilineTextAlignment(.center)
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 15)
                        
                        // Subtitle
                        Text(subtitle ?? feature.upgradeMessage)
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 10)
                        
                        // Tier badge
                        HStack(spacing: 6) {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                            Text("Requires \(feature.requiredTier.displayName)")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundColor(tierColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(tierColor.opacity(0.15))
                                .overlay(
                                    Capsule()
                                        .stroke(tierColor.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .opacity(animateIn ? 1 : 0)
                        
                        // Benefits
                        benefitsSection
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                
                // CTA pinned at bottom - always visible
                ctaSection
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 30)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
            
            // X button overlaid in top-right (if dismissible)
            if onDismiss != nil {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
                .padding(.trailing, 16)
            }
        }
        .sheet(isPresented: $showSubscriptionView) {
            SubscriptionPricingView()
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                animateIn = true
            }
            // Track paywall view
            AnalyticsService.shared.trackPaywallViewed(source: "hard_paywall", feature: feature.rawValue)
        }
    }
    
    private var heroIcon: some View {
        ZStack {
            // Glow - compact
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tierColor.opacity(0.4), tierColor.opacity(0)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
            
            // Main circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tierColor.opacity(0.3), tierColor.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 72)
                .overlay(
                    Circle()
                        .stroke(tierColor.opacity(0.5), lineWidth: 2)
                )
            
            // Icon
            Image(systemName: feature.iconName)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [tierColor, tierColor.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
    
    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(benefits ?? defaultBenefits, id: \.self) { benefit in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(tierColor)
                    
                    Text(benefit)
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 32)
    }
    
    private var ctaSection: some View {
        VStack(spacing: 16) {
            // Price info
            HStack(spacing: 4) {
                Text("Starting at")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                Text(feature.requiredTier.monthlyPrice)
                    .font(.title3.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text("/month")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            // Upgrade button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showSubscriptionView = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Get \(feature.requiredTier.displayName)")
                        .font(.headline.weight(.bold))
                }
                .foregroundColor(feature.requiredTier == .premium ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: feature.requiredTier == .premium
                            ? [.purple, .purple.opacity(0.8)]
                            : [BrandColors.goldLight, BrandColors.goldBase],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
            }
            
            // Maybe later
            if onDismiss != nil {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss?()
                } label: {
                    Text("Maybe Later")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
        }
    }
}

// MARK: - Feature Gate Wrapper

/// A comprehensive wrapper that applies the appropriate gating pattern
public struct FeatureGateWrapper<UnlockedContent: View, TeaserContent: View>: View {
    let feature: PremiumFeature
    let style: GatingStyle
    let unlockedContent: () -> UnlockedContent
    let teaserContent: (() -> TeaserContent)?
    
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showUpgradeSheet = false
    
    public init(
        feature: PremiumFeature,
        style: GatingStyle = .softPaywall,
        @ViewBuilder unlockedContent: @escaping () -> UnlockedContent,
        @ViewBuilder teaserContent: @escaping () -> TeaserContent
    ) {
        self.feature = feature
        self.style = style
        self.unlockedContent = unlockedContent
        self.teaserContent = teaserContent
    }
    
    private var hasAccess: Bool {
        subscriptionManager.hasAccess(to: feature)
    }
    
    public var body: some View {
        Group {
            if hasAccess {
                unlockedContent()
            } else {
                switch style {
                case .hardPaywall:
                    HardPaywallView(feature: feature)
                case .softPaywall:
                    if let teaser = teaserContent {
                        SoftPaywallView(feature: feature, unlockedContent: unlockedContent, lockedPreview: teaser)
                    } else {
                        HardPaywallView(feature: feature)
                    }
                case .actionGated:
                    unlockedContent()
                        .overlay(actionGatedOverlay)
                case .limitBased:
                    unlockedContent()
                }
            }
        }
        .unifiedPaywallSheet(feature: feature, isPresented: $showUpgradeSheet)
    }
    
    private var actionGatedOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                // Don't block all taps, just intercept when needed
            }
    }
}

// Convenience initializer without teaser
extension FeatureGateWrapper where TeaserContent == EmptyView {
    public init(
        feature: PremiumFeature,
        style: GatingStyle = .hardPaywall,
        @ViewBuilder unlockedContent: @escaping () -> UnlockedContent
    ) {
        self.feature = feature
        self.style = style
        self.unlockedContent = unlockedContent
        self.teaserContent = nil
    }
}

// MARK: - AI Prompt Limit Banner

/// A banner shown when user is approaching or has reached AI prompt limit
public struct AIPromptLimitBanner: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showUpgradeSheet = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var remaining: Int {
        subscriptionManager.remainingAIPrompts
    }
    
    private var limit: Int {
        subscriptionManager.effectiveTier.aiPromptsPerDay
    }
    
    private var isAtLimit: Bool {
        remaining <= 0 && subscriptionManager.effectiveTier != .premium
    }
    
    private var isNearLimit: Bool {
        subscriptionManager.isApproachingPromptLimit
    }
    
    private var shouldShow: Bool {
        subscriptionManager.effectiveTier != .premium && (isAtLimit || isNearLimit)
    }
    
    public var body: some View {
        if shouldShow {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: isAtLimit ? "exclamationmark.circle.fill" : "info.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isAtLimit ? .red : .orange)
                
                // Message
                VStack(alignment: .leading, spacing: 2) {
                    Text(isAtLimit ? "Daily limit reached" : "Running low on prompts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(isAtLimit 
                         ? "Upgrade for more AI conversations" 
                         : "\(remaining) of \(limit) prompts remaining today")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                // Upgrade button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showUpgradeSheet = true
                } label: {
                    Text("Upgrade")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(
                    PremiumCompactCTAStyle(
                        height: 30,
                        horizontalPadding: 12,
                        cornerRadius: 15,
                        font: .caption.weight(.bold)
                    )
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isAtLimit 
                          ? Color.red.opacity(0.1) 
                          : Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isAtLimit ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
            .sheet(isPresented: $showUpgradeSheet) {
                AIPromptLimitSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
        }
    }
}

// MARK: - Price Alert Limit Banner

/// Banner shown when user hits price alert limit
public struct PriceAlertLimitBanner: View {
    let currentAlertCount: Int
    
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showUpgradeSheet = false
    
    private var limit: Int {
        subscriptionManager.effectiveTier.maxPriceAlerts
    }
    
    private var isAtLimit: Bool {
        limit != Int.max && currentAlertCount >= limit
    }
    
    public var body: some View {
        if isAtLimit {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alert limit reached")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text("Free users can have up to \(limit) active alerts")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showUpgradeSheet = true
                } label: {
                    Text("Unlock More")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(
                    PremiumCompactCTAStyle(
                        height: 28,
                        horizontalPadding: 10,
                        cornerRadius: 12,
                        font: .caption.weight(.bold)
                    )
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
            .unifiedPaywallSheet(feature: .unlimitedPriceAlerts, isPresented: $showUpgradeSheet)
        }
    }
}

// MARK: - Teaser Card

/// A card that shows a preview of premium content with upgrade CTA
public struct TeaserCard: View {
    let feature: PremiumFeature
    let title: String
    let previewContent: AnyView
    
    @State private var showUpgradeSheet = false
    @Environment(\.colorScheme) private var colorScheme
    
    public init<Content: View>(
        feature: PremiumFeature,
        title: String,
        @ViewBuilder previewContent: () -> Content
    ) {
        self.feature = feature
        self.title = title
        self.previewContent = AnyView(previewContent())
    }
    
    private var tierColor: Color {
        feature.requiredTier == .premium ? .purple : BrandColors.goldBase
    }
    
    private var tierForegroundColor: Color {
        feature.requiredTier == .premium ? .white : .black.opacity(0.92)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                // Lock badge
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                    Text(feature.requiredTier.displayName)
                        .font(.caption2.weight(.bold))
                }
                .foregroundColor(tierColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(tierColor.opacity(0.15))
                )
            }
            
            // Preview content with blur
            ZStack {
                previewContent
                    .allowsHitTesting(false)
                
                // Overlay
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundStyle(tierColor)
                    
                    Text("Upgrade to unlock")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill((colorScheme == .dark ? Color.black : Color.white).opacity(0.7))
                )
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Upgrade button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showUpgradeSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                    Text("Upgrade to \(feature.requiredTier.displayName)")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                PremiumAccentCTAStyle(
                    accent: tierColor,
                    foregroundColor: tierForegroundColor,
                    height: 38,
                    horizontalPadding: 14,
                    cornerRadius: 10,
                    font: .subheadline.weight(.bold)
                )
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(tierColor.opacity(0.2), lineWidth: 1)
                )
        )
        .unifiedPaywallSheet(feature: feature, isPresented: $showUpgradeSheet)
    }
}

// MARK: - Standard Locked Content View

/// A standardized locked content view for consistent paywall UX across the app
/// Use this for features that require a full-screen locked state
public struct StandardLockedContentView: View {
    let feature: PremiumFeature
    let title: String
    let subtitle: String
    let iconName: String
    let iconColor: Color
    let benefits: [(icon: String, title: String, description: String)]
    var onDismiss: (() -> Void)?
    
    @State private var showUpgradeSheet = false
    @State private var animateIn = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    public init(
        feature: PremiumFeature,
        title: String? = nil,
        subtitle: String? = nil,
        iconName: String? = nil,
        iconColor: Color? = nil,
        benefits: [(icon: String, title: String, description: String)]? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.feature = feature
        self.title = title ?? feature.displayName
        self.subtitle = subtitle ?? feature.upgradeMessage
        self.iconName = iconName ?? feature.iconName
        self.iconColor = iconColor ?? (feature.requiredTier == .premium ? .purple : BrandColors.goldBase)
        self.benefits = benefits ?? []
        self.onDismiss = onDismiss
    }
    
    private var tierColor: Color {
        feature.requiredTier == .premium ? .purple : BrandColors.goldBase
    }
    
    private var tierForegroundColor: Color {
        feature.requiredTier == .premium ? .white : .black.opacity(0.92)
    }
    
    /// Gold gradient for back button (consistent with other views)
    private var chipGoldGradient: LinearGradient {
        LinearGradient(
            colors: [BrandColors.goldLight, BrandColors.goldBase],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Consistent header with back button
            header
            
            Divider().opacity(0.3)
            
            // Main content
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 40)
                    
                    // Icon
                    heroIcon
                        .opacity(animateIn ? 1 : 0)
                        .offset(y: animateIn ? 0 : 20)
                    
                    // Title
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .opacity(animateIn ? 1 : 0)
                    
                    // Subtitle
                    Text(subtitle)
                        .font(.body)
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .opacity(animateIn ? 1 : 0)
                    
                    // Benefits list
                    if !benefits.isEmpty {
                        benefitsList
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 10)
                    }
                    
                    // Tier badge
                    LockedFeatureBadge(feature: feature, style: .standard)
                        .opacity(animateIn ? 1 : 0)
                    
                    Spacer().frame(height: 20)
                    
                    // Upgrade button
                    upgradeButton
                        .opacity(animateIn ? 1 : 0)
                        .offset(y: animateIn ? 0 : 20)
                    
                    // Price hint
                    Text("Starting at \(feature.requiredTier.monthlyPrice)/month")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .opacity(animateIn ? 1 : 0)
                    
                    Spacer().frame(height: 40)
                }
            }
        }
        .background(DS.Adaptive.background)
        .sheet(isPresented: $showUpgradeSheet) {
            SubscriptionPricingView()
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                animateIn = true
            }
            // Track paywall view
            AnalyticsService.shared.trackPaywallViewed(source: "locked_content", feature: feature.rawValue)
        }
    }
    
    private var header: some View {
        HStack {
            CSNavButton(
                icon: "chevron.left",
                action: {
                    if let onDismiss = onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }
            )
            
            Spacer()
            
            Text(title)
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            // Invisible spacer for symmetric layout
            Image(systemName: "chevron.left")
                .opacity(0)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .background(DS.Adaptive.background)
    }
    
    private var heroIcon: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [iconColor.opacity(0.3), iconColor.opacity(0)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
            
            // Main circle
            Circle()
                .fill(iconColor.opacity(0.15))
                .frame(width: 100, height: 100)
            
            // Icon
            Image(systemName: iconName)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [iconColor, iconColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
    
    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(benefits.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(tierColor.opacity(0.1))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: benefits[index].icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(tierColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(benefits[index].title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text(benefits[index].description)
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(tierColor.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }
    
    private var upgradeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            PaywallManager.shared.trackFeatureAttempt(feature)
            showUpgradeSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Upgrade to \(feature.requiredTier.displayName)")
                    .font(.headline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(
            PremiumAccentCTAStyle(
                accent: tierColor,
                foregroundColor: tierForegroundColor,
                height: 52,
                horizontalPadding: 16,
                cornerRadius: 14,
                font: .headline.weight(.bold)
            )
        )
        .padding(.horizontal, 24)
    }
}

// MARK: - Convenience initializers for common features

extension StandardLockedContentView {
    /// Creates a locked content view for Trading Bots (Premium)
    static func tradingBots(onDismiss: (() -> Void)? = nil) -> StandardLockedContentView {
        StandardLockedContentView(
            feature: .tradingBots,
            title: "Trading Bots",
            subtitle: "Practice automated trading with DCA, Grid, and Signal bots in Paper Trading mode. Test strategies risk-free with virtual funds.",
            iconName: "cpu.fill",
            iconColor: .purple,
            benefits: [
                (icon: "repeat.circle.fill", title: "DCA Bots", description: "Dollar-cost averaging automation"),
                (icon: "square.grid.3x3.fill", title: "Grid Bots", description: "Profit from sideways markets"),
                (icon: "bolt.circle.fill", title: "Signal Bots", description: "React to custom trading signals"),
                (icon: "doc.text.fill", title: "Paper Trading", description: "Test strategies with virtual funds")
            ],
            onDismiss: onDismiss
        )
    }
    
    /// Creates a locked content view for Derivatives (Premium)
    static func derivatives(onDismiss: (() -> Void)? = nil) -> StandardLockedContentView {
        StandardLockedContentView(
            feature: .derivativesFeatures,
            title: "Paper Derivatives",
            subtitle: "Practice advanced derivatives trading including futures, perpetuals, and leverage strategies risk-free with virtual funds.",
            iconName: "chart.line.uptrend.xyaxis.circle.fill",
            iconColor: .purple,
            benefits: [
                (icon: "arrow.up.arrow.down.circle.fill", title: "Leverage Practice", description: "Simulate up to 125x leverage"),
                (icon: "shield.checkered", title: "Risk Management", description: "AI-powered position sizing"),
                (icon: "doc.text.fill", title: "Paper Trading", description: "Test strategies with virtual funds")
            ],
            onDismiss: onDismiss
        )
    }
    
    /// Creates a locked content view for Prediction Bots (Premium)
    static func predictionBots(onDismiss: (() -> Void)? = nil) -> StandardLockedContentView {
        StandardLockedContentView(
            feature: .tradingBots,
            title: "Prediction Markets",
            subtitle: "Create AI-powered prediction market bots for Polymarket and Kalshi. Identify mispriced markets and practice strategies.",
            iconName: "chart.bar.xaxis.ascending",
            iconColor: .cyan,
            benefits: [
                (icon: "brain.head.profile", title: "AI Analysis", description: "Find mispriced markets"),
                (icon: "doc.text.fill", title: "Paper Trading", description: "Practice risk-free"),
                (icon: "chart.line.uptrend.xyaxis", title: "Multi-Platform", description: "Polymarket & Kalshi")
            ],
            onDismiss: onDismiss
        )
    }
    
    /// Creates a locked content view for Strategy Marketplace (Premium)
    static func copyTrading(onDismiss: (() -> Void)? = nil) -> StandardLockedContentView {
        StandardLockedContentView(
            feature: .copyTrading,
            title: "Strategy Marketplace",
            subtitle: "Browse and share paper trading strategies from other users. Apply proven strategies to your virtual portfolio.",
            iconName: "doc.on.doc.fill",
            iconColor: .purple,
            benefits: [
                (icon: "person.2.fill", title: "Community Strategies", description: "Browse strategies from top users"),
                (icon: "doc.text.fill", title: "Paper Trading", description: "Apply strategies with virtual funds"),
                (icon: "slider.horizontal.3", title: "Customize", description: "Adjust parameters to your style")
            ],
            onDismiss: onDismiss
        )
    }
    
    /// Creates a locked content view for Paper Trading (Pro)
    static func paperTrading(onDismiss: (() -> Void)? = nil) -> StandardLockedContentView {
        StandardLockedContentView(
            feature: .paperTrading,
            title: "Paper Trading",
            subtitle: "Practice trading with $100,000 in virtual money. Test strategies risk-free before using real funds.",
            iconName: "doc.text.fill",
            iconColor: BrandColors.goldBase,
            benefits: [
                (icon: "dollarsign.circle.fill", title: "$100K Virtual Balance", description: "Practice with realistic amounts"),
                (icon: "chart.xyaxis.line", title: "Real Market Data", description: "Trade with live prices"),
                (icon: "shield.checkered", title: "Risk-Free Learning", description: "Make mistakes without losing money")
            ],
            onDismiss: onDismiss
        )
    }
}

// MARK: - Preview

#if DEBUG
struct FeatureGating_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StandardLockedContentView.tradingBots()
                .preferredColorScheme(.dark)
            
            VStack(spacing: 20) {
                AIPromptLimitBanner()
                PriceAlertLimitBanner(currentAlertCount: 3)
            }
            .padding()
            .preferredColorScheme(.dark)
        }
    }
}
#endif
