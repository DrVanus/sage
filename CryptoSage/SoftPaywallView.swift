//
//  SoftPaywallView.swift
//  CryptoSage
//
//  Reusable soft paywall component that shows preview content with blur
//  and upgrade CTA. CoinStats-style teaser paywall.
//

import SwiftUI

// MARK: - Soft Paywall View

/// A soft paywall that shows preview content with a gradient blur and upgrade CTA
/// Uses a "teaser" approach - shows limited content to entice users to upgrade
public struct SoftPaywallView<UnlockedContent: View, LockedPreview: View>: View {
    let feature: PremiumFeature
    let unlockedContent: () -> UnlockedContent
    let lockedPreview: () -> LockedPreview
    
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var paywallManager = PaywallManager.shared
    @State private var showUpgradeSheet = false
    @State private var animatePaywall = false
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        feature: PremiumFeature,
        @ViewBuilder unlockedContent: @escaping () -> UnlockedContent,
        @ViewBuilder lockedPreview: @escaping () -> LockedPreview
    ) {
        self.feature = feature
        self.unlockedContent = unlockedContent
        self.lockedPreview = lockedPreview
    }
    
    private var hasAccess: Bool {
        subscriptionManager.hasAccess(to: feature)
    }
    
    public var body: some View {
        Group {
            if hasAccess {
                unlockedContent()
            } else {
                lockedView
                    .trackPaywallView(for: feature)
            }
        }
        .unifiedPaywallSheet(feature: feature, isPresented: $showUpgradeSheet)
    }
    
    private var lockedView: some View {
        ZStack(alignment: .bottom) {
            // Preview content with blur overlay
            lockedPreview()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.5),
                            .init(color: .white.opacity(0.3), location: 0.75),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Gradient overlay — use adaptive background for proper dark/light mode blending
            LinearGradient(
                colors: [
                    .clear,
                    DS.Adaptive.background.opacity(0.5),
                    DS.Adaptive.background.opacity(0.85),
                    DS.Adaptive.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .allowsHitTesting(false)
            
            // Upgrade CTA overlay
            upgradeOverlay
                .padding(.bottom, 16)
                .opacity(animatePaywall ? 1 : 0)
                .offset(y: animatePaywall ? 0 : 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
                animatePaywall = true
            }
        }
    }
    
    private var upgradeOverlay: some View {
        VStack(spacing: 16) {
            // Lock icon with glow
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [BrandColors.goldLight.opacity(0.4), BrandColors.goldBase.opacity(0)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldLight.opacity(0.3), BrandColors.goldDark.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle()
                            .stroke(BrandColors.goldBase.opacity(0.5), lineWidth: 1)
                    )
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            // Feature name
            Text(feature.displayName)
                .font(.title3.weight(.bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            // Teaser message
            Text(feature.upgradeMessage)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .lineLimit(3)
            
            // Tier badge
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.caption)
                Text("Requires \(feature.requiredTier.displayName)")
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(tierColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tierColor.opacity(0.15))
            )
            
            // Upgrade button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showUpgradeSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(paywallManager.upgradeCtaText(for: feature))
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                PremiumAccentCTAStyle(
                    accent: tierColor,
                    foregroundColor: tierForegroundColor,
                    height: 48,
                    horizontalPadding: 16,
                    cornerRadius: 12,
                    font: .headline.weight(.semibold)
                )
            )
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    colorScheme == .dark
                        ? Color(white: 0.1).opacity(0.95)
                        : Color.white.opacity(0.95)
                )
        )
        .padding(.horizontal, 16)
    }
    
    private var tierColor: Color {
        switch feature.requiredTier {
        case .pro: return BrandColors.goldBase
        case .premium: return .purple
        case .free: return .gray
        }
    }
    
    private var tierForegroundColor: Color {
        feature.requiredTier == .premium ? .white : .black.opacity(0.92)
    }
    
}

// MARK: - Soft Paywall List View

/// A soft paywall specifically designed for list content
/// Shows N items clearly, then blurs the rest with upgrade prompt
public struct SoftPaywallList<Item: Identifiable, ItemView: View>: View {
    let feature: PremiumFeature
    let items: [Item]
    let previewCount: Int
    let itemView: (Item) -> ItemView
    
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showUpgradeSheet = false
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        feature: PremiumFeature,
        items: [Item],
        previewCount: Int = 5,
        @ViewBuilder itemView: @escaping (Item) -> ItemView
    ) {
        self.feature = feature
        self.items = items
        self.previewCount = previewCount
        self.itemView = itemView
    }
    
    private var hasAccess: Bool {
        subscriptionManager.hasAccess(to: feature)
    }
    
    public var body: some View {
        Group {
            if hasAccess {
                // Full access - show all items
                ForEach(items) { item in
                    itemView(item)
                }
            } else {
                // Limited access - show preview with paywall
                VStack(spacing: 0) {
                    // Preview items (clear)
                    ForEach(Array(items.prefix(previewCount))) { item in
                        itemView(item)
                    }
                    
                    // Remaining items with blur if there are more
                    if items.count > previewCount {
                        blurredRemainingItems
                    }
                }
                .trackPaywallView(for: feature)
            }
        }
        .unifiedPaywallSheet(feature: feature, isPresented: $showUpgradeSheet)
    }
    
    private var blurredRemainingItems: some View {
        ZStack(alignment: .center) {
            // Show a couple more items blurred
            VStack(spacing: 0) {
                ForEach(Array(items.dropFirst(previewCount).prefix(2))) { item in
                    itemView(item)
                }
            }
            .allowsHitTesting(false)
            
            // Gradient overlay
            LinearGradient(
                colors: [
                    .clear,
                    (colorScheme == .dark ? Color.black : Color.white).opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Unlock prompt
            unlockPrompt
        }
    }
    
    private var unlockPrompt: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                Text("\(items.count - previewCount) more items")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(DS.Adaptive.textPrimary)
            
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showUpgradeSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                    Text("Unlock All")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(
                PremiumPrimaryCTAStyle(
                    height: 40,
                    horizontalPadding: 20,
                    cornerRadius: 20,
                    font: .subheadline.weight(.semibold)
                )
            )
        }
        .padding(.vertical, 24)
    }
}

// MARK: - Soft Paywall Section

/// A section wrapper that adds a soft paywall around content
public struct SoftPaywallSection<Content: View>: View {
    let feature: PremiumFeature
    let title: String?
    let content: () -> Content
    
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showUpgradeSheet = false
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        feature: PremiumFeature,
        title: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.feature = feature
        self.title = title
        self.content = content
    }
    
    private var hasAccess: Bool {
        subscriptionManager.hasAccess(to: feature)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with lock badge if locked
            if let title = title {
                HStack {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    if !hasAccess {
                        LockedFeatureBadge(feature: feature, style: .compact)
                    }
                    
                    Spacer()
                }
            }
            
            // Content with optional paywall
            if hasAccess {
                content()
            } else {
                lockedContent
            }
        }
        .unifiedPaywallSheet(feature: feature, isPresented: $showUpgradeSheet)
    }
    
    private var lockedContent: some View {
        ZStack {
            content()
                .allowsHitTesting(false)
            
            // Tap to unlock overlay
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showUpgradeSheet = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [BrandColors.goldLight, BrandColors.goldBase],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    Text("Tap to unlock")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill((colorScheme == .dark ? Color.black : Color.white).opacity(0.7))
                )
            }
            .buttonStyle(.plain)
        }
        .trackPaywallView(for: feature)
    }
}

// MARK: - Inline Upgrade Prompt

/// A compact inline upgrade prompt for use within lists or cards
public struct InlineUpgradePrompt: View {
    let feature: PremiumFeature
    var style: PromptStyle = .standard
    
    @State private var showUpgradeSheet = false
    @Environment(\.colorScheme) private var colorScheme
    
    public enum PromptStyle {
        case compact    // Just a button
        case standard   // Button with brief message
        case expanded   // Full message with benefits
    }
    
    private var tierColor: Color {
        switch feature.requiredTier {
        case .pro: return BrandColors.goldBase
        case .premium: return .purple
        case .free: return .gray
        }
    }
    
    private var tierForegroundColor: Color {
        feature.requiredTier == .premium ? .white : .black.opacity(0.92)
    }
    
    public var body: some View {
        Group {
            switch style {
            case .compact:
                compactPrompt
            case .standard:
                standardPrompt
            case .expanded:
                expandedPrompt
            }
        }
        .unifiedPaywallSheet(feature: feature, isPresented: $showUpgradeSheet)
    }
    
    private var compactPrompt: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showUpgradeSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                Text(feature.requiredTier.displayName)
                    .font(.caption.weight(.bold))
            }
            .foregroundColor(tierColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tierColor.opacity(0.15))
            )
        }
    }
    
    private var standardPrompt: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showUpgradeSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: feature.iconName)
                    .font(.title3)
                    .foregroundStyle(tierColor)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text("Requires \(feature.requiredTier.displayName)")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(tierColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var expandedPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tierColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: feature.iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(tierColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(feature.displayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        LockedFeatureBadge(feature: feature, style: .compact)
                    }
                    
                    Text(feature.upgradeMessage)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(2)
                }
            }
            
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showUpgradeSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("Upgrade to \(feature.requiredTier.displayName)")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                PremiumAccentCTAStyle(
                    accent: tierColor,
                    foregroundColor: tierForegroundColor,
                    height: 42,
                    horizontalPadding: 14,
                    cornerRadius: 10,
                    font: .subheadline.weight(.semibold)
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
    }
}

// MARK: - Paywall Action Button

/// A button that triggers the paywall when tapped (for gating specific actions)
public struct PaywallActionButton<Label: View>: View {
    let feature: PremiumFeature
    let action: () -> Void
    let label: () -> Label
    
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var paywallManager = PaywallManager.shared
    @State private var showUpgradeSheet = false
    
    public init(
        feature: PremiumFeature,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.feature = feature
        self.action = action
        self.label = label
    }
    
    private var hasAccess: Bool {
        subscriptionManager.hasAccess(to: feature)
    }
    
    public var body: some View {
        Button {
            if hasAccess {
                action()
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                paywallManager.trackFeatureAttempt(feature)
                showUpgradeSheet = true
            }
        } label: {
            label()
        }
        .unifiedPaywallSheet(feature: feature, isPresented: $showUpgradeSheet)
    }
}

// MARK: - Preview

#if DEBUG
struct SoftPaywallView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            InlineUpgradePrompt(feature: .whaleTracking, style: .compact)
            InlineUpgradePrompt(feature: .copyTrading, style: .standard)
            InlineUpgradePrompt(feature: .tradingBots, style: .expanded)
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}
#endif
