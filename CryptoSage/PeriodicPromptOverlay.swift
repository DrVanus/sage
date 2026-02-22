//
//  PeriodicPromptOverlay.swift
//  CryptoSage
//
//  App-level overlay for periodic upgrade prompts.
//  Shows after N sessions to encourage free users to upgrade.
//

import SwiftUI

// MARK: - Periodic Prompt Overlay

/// App-level view modifier that shows periodic upgrade prompts to free users
public struct PeriodicPromptOverlay: ViewModifier {
    @ObservedObject private var paywallManager = PaywallManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPrompt = false
    
    public func body(content: Content) -> some View {
        content
            .onAppear {
                // Record app launch and check if prompt should show
                paywallManager.recordAppLaunch()
                
                // Slight delay before showing prompt for better UX
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if paywallManager.shouldShowPeriodicPrompt {
                        showPrompt = true
                        paywallManager.recordPromptShown()
                    }
                }
            }
            .sheet(isPresented: $showPrompt) {
                PeriodicUpgradePromptView {
                    showPrompt = false
                    paywallManager.recordPromptDismissed()
                }
            }
    }
}

public extension View {
    /// Adds periodic upgrade prompt overlay to the view
    func withPeriodicUpgradePrompt() -> some View {
        modifier(PeriodicPromptOverlay())
    }
}

// MARK: - Periodic Upgrade Prompt View

/// The actual prompt view shown periodically to free users
struct PeriodicUpgradePromptView: View {
    let onDismiss: () -> Void
    
    @ObservedObject private var paywallManager = PaywallManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var animateIn = false
    @State private var showPricingView = false
    
    // Gold accent colors
    private let goldLight = Color(red: 0.95, green: 0.85, blue: 0.60)
    private let goldBase = Color(red: 0.85, green: 0.65, blue: 0.13)
    private let goldDark = Color(red: 0.7, green: 0.5, blue: 0.1)
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Scrollable content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        // Hero section
                        heroSection
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 20)
                        
                        // Benefits grid
                        benefitsSection
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 30)
                        
                        // Trust indicators
                        trustSection
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                
                // CTA pinned at bottom - always visible
                ctaSection
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 50)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            
            // X button overlaid in top-right corner
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
        .background(backgroundGradient)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                animateIn = true
            }
        }
        .sheet(isPresented: $showPricingView) {
            SubscriptionPricingView()
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        ZStack {
            DS.Adaptive.background.ignoresSafeArea()
            
            // Subtle gold gradient overlay
            LinearGradient(
                colors: [
                    goldBase.opacity(0.05),
                    goldBase.opacity(0.02),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Decorative circles
            GeometryReader { geo in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [goldBase.opacity(0.15), goldBase.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .offset(x: -100, y: -50)
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.purple.opacity(0.1), Color.purple.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .offset(x: geo.size.width - 50, y: geo.size.height - 200)
            }
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 14) {
            // Animated crown icon - compact
            ZStack {
                // Outer glow rings
                // FIX: Added id parameter for stable identity
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(goldBase.opacity(0.1 - Double(i) * 0.03), lineWidth: 1.5)
                        .frame(width: CGFloat(60 + i * 20), height: CGFloat(60 + i * 20))
                }
                
                // Inner glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [goldBase.opacity(0.4), goldBase.opacity(0)],
                            center: .center,
                            startRadius: 12,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)
                
                // Icon background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [goldLight.opacity(0.3), goldDark.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(goldBase.opacity(0.5), lineWidth: 2)
                    )
                
                // Crown icon
                Image(systemName: "crown.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [goldLight, goldBase],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            // Title
            Text("Get CryptoSage Pro")
                .font(.title2.weight(.bold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .multilineTextAlignment(.center)
            
            // Subtitle based on user behavior
            Text(subtitleText)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }
    
    private var subtitleText: String {
        if paywallManager.totalFeatureAttempts > 0 {
            return "You've been using free features — imagine what Pro can do. Unlock the full experience."
        } else {
            return "AI-powered analysis, price predictions, unlimited alerts & more — everything you need in one app."
        }
    }
    
    // MARK: - Benefits Section
    
    private var benefitsSection: some View {
        VStack(spacing: 12) {
            // Section header
            HStack {
                Text("What You'll Get")
                    .font(.headline.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
            }
            
            // Benefits based on user's attempted features or default
            let benefits = paywallManager.benefitsList(for: .pro)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(benefits.prefix(4)) { benefit in
                    BenefitCard(benefit: benefit)
                }
            }
            
            // Premium teaser
            premiumTeaser
        }
    }
    
    private var premiumTeaser: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showPricingView = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.purple)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Go Further")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("PREMIUM")
                            .font(.caption2.weight(.heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple)
                            .cornerRadius(4)
                    }
                    
                    Text("Unlimited AI chat, paper trading bots & real-time alerts")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Trust Section
    
    private var trustSection: some View {
        HStack(spacing: 24) {
            trustItem(icon: "lock.shield.fill", text: "Secure")
            trustItem(icon: "checkmark.seal.fill", text: "Verified")
            trustItem(icon: "arrow.uturn.backward.circle.fill", text: "Refundable")
        }
    }
    
    private func trustItem(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(DS.Adaptive.textTertiary)
            Text(text)
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
        }
    }
    
    // MARK: - CTA Section
    
    private var ctaSection: some View {
        VStack(spacing: 10) {
            // Primary CTA - View Plans
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showPricingView = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("View Plans")
                        .font(.headline.weight(.bold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [goldLight, goldBase],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
            }
            
            // Secondary CTA - Maybe Later
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            } label: {
                Text("Maybe Later")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            
            // Terms note
            Text("Cancel anytime · No commitment required")
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
        }
    }
}

// MARK: - Benefit Card

private struct BenefitCard: View {
    let benefit: PaywallBenefit
    @Environment(\.colorScheme) private var colorScheme
    
    private let goldBase = Color(red: 0.85, green: 0.65, blue: 0.13)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle()
                    .fill(goldBase.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: benefit.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(goldBase)
            }
            
            Text(benefit.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
                .lineLimit(1)
            
            Text(benefit.description)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Compact Upgrade Banner

/// A compact banner that can be shown at the top/bottom of screens
public struct CompactUpgradeBanner: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPricingView = false
    @Environment(\.colorScheme) private var colorScheme
    
    private let goldBase = Color(red: 0.85, green: 0.65, blue: 0.13)
    private let goldLight = Color(red: 0.95, green: 0.85, blue: 0.60)
    
    public var body: some View {
        // Only show to free users
        if subscriptionManager.effectiveTier == .free {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showPricingView = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [goldLight, goldBase],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    Text("Upgrade to Pro")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Spacer()
                    
                    Text("From $9.99/mo")
                        .font(.caption.weight(.medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(goldBase.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(goldBase.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPricingView) {
                NavigationStack {
                    SubscriptionPricingView()
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct PeriodicPromptOverlay_Previews: PreviewProvider {
    static var previews: some View {
        PeriodicUpgradePromptView {
            print("Dismissed")
        }
        .preferredColorScheme(.dark)
    }
}
#endif
