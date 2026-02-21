//
//  UnifiedPaywallSheet.swift
//  CryptoSage
//
//  A unified, polished paywall sheet component for consistent upgrade prompts
//  across the entire app. Replaces FeatureUpgradePromptView with a modern
//  modal sheet design following industry best practices.
//

import SwiftUI

// MARK: - Unified Paywall Sheet

/// A polished modal sheet for presenting upgrade prompts consistently across the app.
/// Uses modern iOS design patterns with tier-specific styling and smooth animations.
public struct UnifiedPaywallSheet: View {
    let feature: PremiumFeature
    var showBenefits: Bool = true
    var onUpgrade: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    @State private var animateIn = false
    @State private var showSubscriptionView = false
    @State private var showPremiumTier = false  // Toggle to view Premium tier benefits
    
    public init(
        feature: PremiumFeature,
        showBenefits: Bool = true,
        onUpgrade: (() -> Void)? = nil
    ) {
        self.feature = feature
        self.showBenefits = showBenefits
        self.onUpgrade = onUpgrade
    }
    
    // MARK: - Tier Colors
    
    private var tierColor: Color {
        switch feature.requiredTier {
        case .free: return .gray
        case .pro: return BrandColors.goldBase
        case .premium: return .purple
        }
    }
    
    private var tierGradient: LinearGradient {
        switch feature.requiredTier {
        case .free:
            return LinearGradient(
                colors: [Color.gray.opacity(0.6), Color.gray],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .pro:
            return LinearGradient(
                colors: [BrandColors.goldLight, BrandColors.goldBase],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .premium:
            return LinearGradient(
                colors: [Color.purple.opacity(0.8), Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var ctaButtonGradient: LinearGradient {
        switch feature.requiredTier {
        case .free:
            return LinearGradient(
                colors: [Color.gray.opacity(0.8), Color.gray],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .pro:
            return LinearGradient(
                colors: [BrandColors.goldLight, BrandColors.goldBase],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .premium:
            return LinearGradient(
                colors: [Color.purple.opacity(0.9), Color.purple],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    
    // MARK: - Default Benefits
    
    private var defaultBenefits: [(icon: String, text: String)] {
        switch feature {
        case .paperTrading:
            return [
                (icon: "dollarsign.circle.fill", text: "$100,000 virtual funds to practice"),
                (icon: "chart.xyaxis.line", text: "Market, Limit, Stop-Loss & Take-Profit orders"),
                (icon: "wand.and.stars", text: "AI trade suggestions & market insights"),
                (icon: "chart.bar.doc.horizontal", text: "Track P&L, win rate & trade history"),
                (icon: "trophy.fill", text: "Compete on Paper Trading Leaderboards"),
                (icon: "person.crop.circle.badge.checkmark", text: "Social profile & portfolio sharing")
            ]
        case .tradingBots:
            return [
                (icon: "cpu.fill", text: "DCA, Grid & Signal bot simulators"),
                (icon: "bubble.left.and.bubble.right.fill", text: "AI assistant helps build strategies"),
                (icon: "chart.line.uptrend.xyaxis", text: "Backtest strategies on historical data"),
                (icon: "arrow.triangle.2.circlepath", text: "Simulated buy & sell execution"),
                (icon: "wand.and.stars", text: "AI suggests optimal bot settings")
            ]
        case .copyTrading:
            return [
                (icon: "person.2.fill", text: "Copy top traders automatically"),
                (icon: "arrow.triangle.2.circlepath", text: "Mirror trades in real-time"),
                (icon: "slider.horizontal.3", text: "Adjust position sizes to your risk level"),
                (icon: "chart.bar.doc.horizontal", text: "View each trader's performance history"),
                (icon: "bell.badge.fill", text: "Get notified when traders open positions")
            ]
        case .derivativesFeatures:
            return [
                (icon: "arrow.up.arrow.down.circle.fill", text: "Trade futures & perpetuals"),
                (icon: "chart.bar.xaxis", text: "Up to 125x leverage"),
                (icon: "shield.checkered", text: "Built-in risk controls"),
                (icon: "doc.text.fill", text: "Cross & isolated margin modes"),
                (icon: "bell.badge.fill", text: "Liquidation price warnings")
            ]
        case .whaleTracking:
            return [
                (icon: "water.waves", text: "Track large wallet movements"),
                (icon: "bell.badge.fill", text: "Alerts when whales buy or sell"),
                (icon: "wand.and.stars", text: "See what smart money is doing"),
                (icon: "clock.fill", text: "Real-time transaction monitoring"),
                (icon: "magnifyingglass", text: "Filter by wallet size & activity type")
            ]
        case .taxReports:
            return [
                (icon: "doc.text.magnifyingglass", text: "Automatic cost basis calculation"),
                (icon: "square.and.arrow.up.fill", text: "Export for TurboTax & TaxAct"),
                (icon: "calendar", text: "FIFO, LIFO & other methods"),
                (icon: "chart.bar.xaxis", text: "Capital gains & losses breakdown"),
                (icon: "doc.text.fill", text: "Generate Form 8949 & Schedule D")
            ]
        case .aiPoweredAlerts:
            return [
                (icon: "sparkles", text: "AI monitors major market shifts around the clock"),
                (icon: "newspaper.fill", text: "Breaking news alerts for your held coins"),
                (icon: "brain.head.profile", text: "Market sentiment shift notifications"),
                (icon: "chart.line.uptrend.xyaxis", text: "AI-enhanced price alerts with smart timing and volume analysis"),
                (icon: "bell.badge.fill", text: "AI explains what's happening and why")
            ]
        case .aiPricePredictions:
            return [
                (icon: "wand.and.stars", text: "15 AI predictions per day on any coin"),
                (icon: "target", text: "Price targets with confidence levels"),
                (icon: "sparkles", text: "Professional Insights: volume, regime & confluence"),
                (icon: "chart.line.uptrend.xyaxis", text: "Trading levels with entry, stop & take-profit"),
                (icon: "checkmark.circle.fill", text: "Track prediction accuracy over time")
            ]
        case .botMarketplace:
            return [
                (icon: "storefront.fill", text: "Browse DCA, Grid & Signal bot strategies"),
                (icon: "chart.bar.fill", text: "See ROI, win rate & performance history"),
                (icon: "doc.on.doc.fill", text: "Copy any bot with one tap"),
                (icon: "star.fill", text: "Top-rated & verified bot configurations"),
                (icon: "slider.horizontal.3", text: "Adjust risk, allocation & notifications")
            ]
        case .smartMoneyAlerts:
            return [
                (icon: "water.waves", text: "Track large wallet movements"),
                (icon: "bell.badge.fill", text: "Real-time whale activity alerts"),
                (icon: "wand.and.stars", text: "See what smart money is doing"),
                (icon: "clock.fill", text: "Real-time transaction monitoring"),
                (icon: "magnifyingglass", text: "Filter by wallet size & activity type")
            ]
        case .personalizedPortfolioAnalysis:
            return [
                (icon: "chart.pie.fill", text: "AI analyzes your entire portfolio"),
                (icon: "lightbulb.fill", text: "Personalized AI recommendations"),
                (icon: "arrow.triangle.2.circlepath", text: "Smart rebalancing suggestions"),
                (icon: "shield.lefthalf.filled", text: "AI risk scores & diversification grades"),
                (icon: "wand.and.stars", text: "AI portfolio summaries on your homepage")
            ]
        case .advancedAlerts:
            return [
                (icon: "bell.badge.fill", text: "RSI & volume spike alerts"),
                (icon: "percent", text: "Percentage change triggers"),
                (icon: "clock.fill", text: "Multiple timeframe conditions"),
                (icon: "chart.xyaxis.line", text: "MACD, Bollinger & more indicators"),
                (icon: "square.stack.3d.up.fill", text: "Combine conditions with AND/OR logic")
            ]
        case .unlimitedPriceAlerts:
            return [
                (icon: "bell.badge.fill", text: "Unlimited price alerts"),
                (icon: "target", text: "Set any price target"),
                (icon: "iphone.radiowaves.left.and.right", text: "Push notifications"),
                (icon: "arrow.up.arrow.down", text: "Above & below price triggers"),
                (icon: "clock.fill", text: "Recurring & one-time alert modes")
            ]
        case .adFreeExperience:
            return [
                (icon: "checkmark.seal.fill", text: "No ads or interruptions"),
                (icon: "sparkles", text: "Clean, focused experience"),
                (icon: "bolt.fill", text: "Faster app performance"),
                (icon: "paintbrush.fill", text: "Premium visual themes"),
                (icon: "star.fill", text: "Support continued development")
            ]
        case .premiumAIModel:
            return [
                (icon: "sparkles", text: "More detailed and nuanced AI responses"),
                (icon: "lightbulb.max.fill", text: "Deeper analysis of coins, trades & portfolios"),
                (icon: "bubble.left.and.bubble.right.fill", text: "Unlimited AI conversations"),
                (icon: "brain.head.profile", text: "Advanced reasoning for complex questions"),
                (icon: "bolt.fill", text: "Faster response times")
            ]
        case .arbitrageScanner:
            return [
                (icon: "arrow.triangle.2.circlepath", text: "Scan prices across exchanges"),
                (icon: "dollarsign.circle.fill", text: "Spot profit opportunities"),
                (icon: "clock.fill", text: "Real-time price differences"),
                (icon: "bell.badge.fill", text: "Alerts for profitable spreads"),
                (icon: "chart.bar.xaxis", text: "Estimated profit after fees")
            ]
        case .defiYieldOptimization:
            return [
                (icon: "leaf.fill", text: "Find the best yield opportunities"),
                (icon: "wand.and.stars", text: "Compare APY across protocols"),
                (icon: "shield.checkered", text: "Risk-rated recommendations"),
                (icon: "chart.line.uptrend.xyaxis", text: "Historical yield performance data"),
                (icon: "bell.badge.fill", text: "Alerts when rates change significantly")
            ]
        case .riskReport:
            return [
                (icon: "shield.lefthalf.filled", text: "AI-generated portfolio risk score"),
                (icon: "lightbulb.fill", text: "Personalized AI recommendations"),
                (icon: "chart.pie.fill", text: "Concentration & diversification analysis"),
                (icon: "arrow.triangle.2.circlepath", text: "Smart rebalancing suggestions"),
                (icon: "chart.bar.xaxis", text: "Historical risk trend tracking")
            ]
        case .advancedInsights:
            return [
                (icon: "lightbulb.max.fill", text: "AI explains why prices are moving"),
                (icon: "chart.xyaxis.line", text: "AI-powered technicals & chart analysis"),
                (icon: "sparkles", text: "Sentiment analysis & trend detection"),
                (icon: "wand.and.stars", text: "AI summaries for any coin at a glance"),
                (icon: "bell.badge.fill", text: "Alerts for significant market shifts")
            ]
        case .tradeExecution:
            return [
                (icon: "arrow.left.arrow.right.circle.fill", text: "Execute trades from the app"),
                (icon: "bolt.fill", text: "Fast order execution"),
                (icon: "lock.shield.fill", text: "Secure exchange connections"),
                (icon: "doc.text.fill", text: "Market, limit & stop-loss orders"),
                (icon: "chart.bar.xaxis", text: "Real-time order status tracking")
            ]
        case .customStrategies:
            return [
                (icon: "slider.horizontal.3", text: "Build your own trading strategies"),
                (icon: "chart.line.uptrend.xyaxis", text: "Backtest on historical data"),
                (icon: "gearshape.2.fill", text: "Customize entry & exit rules"),
                (icon: "cpu.fill", text: "Automate with bot integration"),
                (icon: "doc.text.fill", text: "Save & share strategy templates")
            ]
        case .unlimitedTaxTransactions:
            return [
                (icon: "infinity", text: "Unlimited transaction tracking"),
                (icon: "doc.text.fill", text: "Complete tax report history"),
                (icon: "arrow.down.doc.fill", text: "Export all years"),
                (icon: "calendar", text: "Multi-year reporting support"),
                (icon: "magnifyingglass", text: "Tax-loss harvesting opportunities")
            ]
        case .earlyAccessFeatures:
            return [
                (icon: "star.fill", text: "Be first to try new features & updates"),
                (icon: "gift.fill", text: "Exclusive access to beta features"),
                (icon: "bell.badge.fill", text: "Priority feature requests"),
                (icon: "bubble.left.and.bubble.right.fill", text: "Direct feedback channel with the team"),
                (icon: "crown.fill", text: "Premium member recognition")
            ]
        case .socialProfile:
            return [
                (icon: "person.crop.circle.fill", text: "Create your trader profile"),
                (icon: "chart.bar.fill", text: "Share your performance stats"),
                (icon: "trophy.fill", text: "Compete on leaderboards"),
                (icon: "person.2.fill", text: "Follow & be followed by traders"),
                (icon: "square.and.arrow.up.fill", text: "Share insights & trade ideas")
            ]
        }
    }
    
    // MARK: - Body
    
    public var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Scrollable content area
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Hero icon with glow - compact
                        heroIcon
                            .scaleEffect(0.8)
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 20)
                        
                        // Title
                        Text(feature.displayName)
                            .font(.title2.weight(.bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .multilineTextAlignment(.center)
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 15)
                        
                        // Subtitle/Description — updates when user toggles tier
                        Text(displayedUpgradeMessage)
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 10)
                            .animation(.easeInOut(duration: 0.2), value: showPremiumTier)
                        
                        // Tier badge
                        tierBadge
                            .opacity(animateIn ? 1 : 0)
                        
                        // Benefits list
                        if showBenefits {
                            benefitsList
                                .opacity(animateIn ? 1 : 0)
                                .offset(y: animateIn ? 0 : 15)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                
                // CTA Section pinned at bottom - always visible
                ctaSection
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 20)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .background(
                        // Fade-in top edge so scroll content blends into CTA
                        LinearGradient(
                            colors: [
                                (colorScheme == .dark ? Color.black : Color(white: 0.98)).opacity(0),
                                colorScheme == .dark ? Color.black : Color(white: 0.98)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 16)
                        .allowsHitTesting(false),
                        alignment: .top
                    )
            }
            
            // X button overlaid in top-right corner (no NavigationStack needed)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
        .background(sheetBackground)
        .sheet(isPresented: $showSubscriptionView) {
            SubscriptionPricingView()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                animateIn = true
            }
            // Track paywall view
            AnalyticsService.shared.trackPaywallViewed(source: "unified_paywall_sheet", feature: feature.rawValue)
        }
    }
    
    // MARK: - Hero Icon
    
    /// Icon to display - uses feature's icon for relevance instead of generic lock
    private var heroIconName: String {
        switch feature {
        case .paperTrading:
            return "doc.text.fill"  // Paper/document icon - matches mode switcher
        case .tradingBots:
            return "cpu.fill"  // Bot/automation icon
        case .whaleTracking:
            return "water.waves"  // Whale icon
        case .taxReports:
            return "doc.text.magnifyingglass"  // Tax document icon
        case .aiPricePredictions:
            return "wand.and.stars"  // AI/magic icon
        case .advancedInsights:
            return "lightbulb.max.fill"  // Insights icon
        default:
            return feature.iconName  // Use feature's own icon
        }
    }
    
    private var heroIcon: some View {
        // Use displayed tier color when user toggles to Premium
        let iconColor = (showPremiumTier && feature.requiredTier == .pro) ? displayedTierColor : tierColor
        let iconGradient = (showPremiumTier && feature.requiredTier == .pro)
            ? LinearGradient(colors: [.purple, .purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : tierGradient
        
        return ZStack {
            // Outer glow - compact
            Circle()
                .fill(
                    RadialGradient(
                        colors: [iconColor.opacity(0.4), iconColor.opacity(0)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
            
            // Main circle with gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [iconColor.opacity(0.3), iconColor.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 72)
                .overlay(
                    Circle()
                        .stroke(iconColor.opacity(0.5), lineWidth: 2)
                )
            
            // Feature-specific icon (not generic lock)
            Image(systemName: heroIconName)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(iconGradient)
        }
        .animation(.easeInOut(duration: 0.25), value: showPremiumTier)
    }
    
    // MARK: - Dynamic Text
    
    /// Subtitle that updates when user toggles between Pro and Premium tabs.
    /// Swaps "Upgrade to Pro" → "Upgrade to Premium" so the message matches the selected tier.
    private var displayedUpgradeMessage: String {
        if showPremiumTier && feature.requiredTier == .pro {
            return feature.upgradeMessage
                .replacingOccurrences(of: "Upgrade to Pro", with: "Upgrade to Premium")
        }
        return feature.upgradeMessage
    }
    
    // MARK: - Tier Badge
    
    /// Badge text that updates based on selected tier.
    /// For Pro features viewed on the Premium tab, shows "Included in Premium"
    /// (not "Requires Premium" which would be misleading — Pro is sufficient).
    private var tierBadgeText: String {
        if showPremiumTier && feature.requiredTier == .pro {
            return "Included in Premium"
        }
        return "Requires \(feature.requiredTier.displayName)"
    }
    
    private var tierBadge: some View {
        let isPremiumDisplayed = showPremiumTier && feature.requiredTier == .pro
        let badgeTextColor: Color = isPremiumDisplayed ? .white : .black.opacity(0.9)
        let badgeFill = LinearGradient(
            colors: isPremiumDisplayed
                ? [Color.purple.opacity(0.95), Color.purple.opacity(0.78)]
                : [BrandColors.goldLight, BrandColors.goldBase],
            startPoint: .leading,
            endPoint: .trailing
        )

        return HStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .font(.caption)
            Text(tierBadgeText)
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(badgeTextColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(badgeFill)
                .overlay(
                    Capsule()
                        .stroke(
                            isPremiumDisplayed
                                ? Color.purple.opacity(0.5)
                                : BrandColors.goldBase.opacity(0.45),
                            lineWidth: 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.2), value: showPremiumTier)
    }
    
    // MARK: - Benefits List
    
    /// Benefits that update based on selected tier (Pro vs Premium)
    private var displayedBenefits: [(icon: String, text: String)] {
        if showPremiumTier && feature.requiredTier == .pro {
            // Show feature-specific Premium benefits
            return premiumBenefitsForFeature
        }
        return defaultBenefits
    }
    
    /// Feature-specific Premium tier benefits
    private var premiumBenefitsForFeature: [(icon: String, text: String)] {
        switch feature {
        case .paperTrading:
            return [
                (icon: "cpu.fill", text: "Bot Simulator: Test DCA, Grid & Signal bots"),
                (icon: "chart.line.uptrend.xyaxis", text: "See how strategies would have performed"),
                (icon: "sparkles", text: "AI suggests best times to buy & sell"),
                (icon: "chart.bar.xaxis", text: "Win rate, profit breakdown & trade stats"),
                (icon: "bell.badge.fill", text: "Alerts for your paper positions"),
                (icon: "crown.fill", text: "Priority support & early access features")
            ]
        case .whaleTracking, .smartMoneyAlerts:
            return [
                (icon: "bubble.left.and.bubble.right.fill", text: "Unlimited AI chat to analyze whale moves"),
                (icon: "cpu.fill", text: "Strategy simulator to act on signals"),
                (icon: "wand.and.stars", text: "AI price predictions (50/day)"),
                (icon: "lightbulb.max.fill", text: "Advanced AI insights & analysis"),
                (icon: "bell.badge.fill", text: "Priority notifications on major whale moves")
            ]
        case .aiPoweredAlerts:
            return [
                (icon: "bell.badge.fill", text: "Unlimited custom alerts across all coins"),
                (icon: "chart.xyaxis.line", text: "Multi-condition alerts with technical triggers"),
                (icon: "waveform.path.ecg", text: "Whale movement & smart money signals"),
                (icon: "wand.and.stars", text: "AI price predictions (50/day)"),
                (icon: "bolt.badge.clock.fill", text: "Priority alert delivery & custom scheduling")
            ]
        case .advancedAlerts, .unlimitedPriceAlerts:
            return [
                (icon: "bell.badge.fill", text: "Unlimited custom alerts across all coins"),
                (icon: "chart.xyaxis.line", text: "Advanced technical indicator triggers"),
                (icon: "bubble.left.and.bubble.right.fill", text: "Unlimited AI chat for market analysis"),
                (icon: "wand.and.stars", text: "AI price predictions (50/day)"),
                (icon: "bolt.badge.clock.fill", text: "Priority alert delivery & custom scheduling")
            ]
        case .aiPricePredictions:
            return [
                (icon: "arrow.up.circle.fill", text: "50 predictions per day"),
                (icon: "clock.arrow.circlepath", text: "Half the wait time between refreshes"),
                (icon: "bubble.left.and.bubble.right.fill", text: "Unlimited AI chat to discuss predictions"),
                (icon: "cpu.fill", text: "Advanced DeepSeek R1 for long-range forecasts"),
                (icon: "chart.bar.doc.horizontal", text: "Compare forecasts from multiple AI models")
            ]
        case .tradingBots, .botMarketplace:
            return [
                (icon: "cpu.fill", text: "Unlimited bot configurations"),
                (icon: "chart.line.uptrend.xyaxis", text: "Test strategies on years of data"),
                (icon: "sparkles", text: "AI finds the best bot settings"),
                (icon: "arrow.triangle.2.circlepath", text: "Run bots across multiple exchanges"),
                (icon: "doc.text.fill", text: "Detailed strategy performance reports")
            ]
        case .riskReport:
            return [
                (icon: "arrow.up.circle.fill", text: "20 portfolio analyses per day (4x more)"),
                (icon: "bubble.left.and.bubble.right.fill", text: "Unlimited AI chat for risk discussion"),
                (icon: "cpu.fill", text: "Strategy simulator for backtesting"),
                (icon: "lightbulb.max.fill", text: "Advanced AI insights & analysis"),
                (icon: "slider.horizontal.3", text: "Custom risk thresholds & automated alerts")
            ]
        case .taxReports:
            return [
                (icon: "infinity", text: "Unlimited transactions (vs 2,500 in Pro)"),
                (icon: "bubble.left.and.bubble.right.fill", text: "Unlimited AI chat for tax questions"),
                (icon: "cpu.fill", text: "Strategy simulator for backtesting"),
                (icon: "lightbulb.max.fill", text: "Advanced AI insights & analysis"),
                (icon: "calendar.badge.clock", text: "Multi-year tax history & advanced reporting")
            ]
        case .personalizedPortfolioAnalysis:
            return [
                (icon: "brain.head.profile", text: "Enhanced AI model for deeper analysis"),
                (icon: "arrow.up.circle.fill", text: "20 analyses per day (4x more than Pro)"),
                (icon: "bubble.left.and.bubble.right.fill", text: "Unlimited AI chat for portfolio discussion"),
                (icon: "cpu.fill", text: "Strategy simulator for backtesting"),
                (icon: "arrow.triangle.2.circlepath", text: "Rebalancing suggestions with target allocations")
            ]
        case .derivativesFeatures:
            return [
                (icon: "chart.line.uptrend.xyaxis", text: "Advanced trading strategies"),
                (icon: "cpu.fill", text: "Perpetual & futures bots"),
                (icon: "shield.checkered", text: "AI helps manage your risk"),
                (icon: "bell.badge.fill", text: "Liquidation warning alerts"),
                (icon: "arrow.triangle.2.circlepath", text: "Cross-margin support")
            ]
        case .copyTrading:
            return [
                (icon: "person.2.fill", text: "Copy unlimited traders"),
                (icon: "chart.bar.doc.horizontal", text: "See full performance history"),
                (icon: "slider.horizontal.3", text: "Set your own risk limits"),
                (icon: "bell.badge.fill", text: "Alerts when traders make moves"),
                (icon: "chart.bar.xaxis", text: "Detailed strategy analytics")
            ]
        case .arbitrageScanner:
            return [
                (icon: "bolt.fill", text: "Instant opportunity alerts"),
                (icon: "arrow.triangle.2.circlepath", text: "Scan all major exchanges"),
                (icon: "chart.bar.xaxis", text: "See potential profit on each trade"),
                (icon: "clock.fill", text: "Historical opportunity data"),
                (icon: "dollarsign.circle.fill", text: "Profit & fee calculations per trade")
            ]
        case .defiYieldOptimization:
            return [
                (icon: "sparkles", text: "AI finds the best yields"),
                (icon: "chart.bar.xaxis", text: "Compare APY across all protocols"),
                (icon: "shield.checkered", text: "Risk ratings for each protocol"),
                (icon: "arrow.triangle.2.circlepath", text: "Yield comparison across chains"),
                (icon: "chart.line.uptrend.xyaxis", text: "Historical APY performance data")
            ]
        case .advancedInsights:
            return [
                (icon: "sparkles", text: "AI-powered deep analysis for any coin"),
                (icon: "chart.line.uptrend.xyaxis", text: "Multi-timeframe chart insights"),
                (icon: "brain.head.profile", text: "AI sentiment & trend analysis"),
                (icon: "lightbulb.max.fill", text: "Real-time AI summaries & key levels"),
                (icon: "chart.bar.xaxis", text: "Comprehensive on-demand analysis")
            ]
        case .adFreeExperience:
            return [
                (icon: "sparkles", text: "Premium visual experience"),
                (icon: "bolt.fill", text: "Faster app performance"),
                (icon: "checkmark.seal.fill", text: "Zero interruptions"),
                (icon: "paintbrush.fill", text: "Exclusive themes"),
                (icon: "star.fill", text: "Early access to new features")
            ]
        case .socialProfile:
            return [
                (icon: "person.crop.circle.badge.checkmark", text: "Verified trader badge"),
                (icon: "chart.bar.fill", text: "Detailed performance statistics"),
                (icon: "person.2.fill", text: "Unlimited followers"),
                (icon: "doc.text.fill", text: "Control what you share"),
                (icon: "trophy.fill", text: "Compete on leaderboards")
            ]
        case .tradeExecution:
            return [
                (icon: "bolt.fill", text: "Priority order execution"),
                (icon: "chart.line.uptrend.xyaxis", text: "Advanced order types"),
                (icon: "arrow.triangle.2.circlepath", text: "Multi-exchange trading"),
                (icon: "lock.shield.fill", text: "Enhanced security"),
                (icon: "bell.badge.fill", text: "Trade confirmation alerts")
            ]
        case .customStrategies:
            return [
                (icon: "slider.horizontal.3", text: "Unlimited custom strategies"),
                (icon: "chart.line.uptrend.xyaxis", text: "Advanced backtesting"),
                (icon: "cpu.fill", text: "AI strategy optimization"),
                (icon: "square.stack.3d.up.fill", text: "Strategy templates library"),
                (icon: "arrow.triangle.2.circlepath", text: "Live strategy deployment")
            ]
        case .premiumAIModel:
            return [
                (icon: "sparkles", text: "Advanced AI for all features"),
                (icon: "brain.head.profile", text: "Deeper market analysis"),
                (icon: "bolt.fill", text: "Faster AI responses"),
                (icon: "chart.bar.xaxis", text: "More detailed insights"),
                (icon: "infinity", text: "Higher daily limits")
            ]
        case .unlimitedTaxTransactions:
            return [
                (icon: "infinity", text: "Truly unlimited transactions"),
                (icon: "calendar", text: "Multi-year tax history"),
                (icon: "doc.text.fill", text: "All accounting methods"),
                (icon: "arrow.down.doc.fill", text: "Bulk export options"),
                (icon: "magnifyingglass", text: "Tax-loss harvesting insights")
            ]
        case .earlyAccessFeatures:
            return [
                (icon: "star.fill", text: "First access to all new features"),
                (icon: "gift.fill", text: "Exclusive beta programs"),
                (icon: "bubble.left.and.bubble.right.fill", text: "Direct feedback channel"),
                (icon: "person.badge.key.fill", text: "Priority feature voting"),
                (icon: "crown.fill", text: "Founding member benefits")
            ]
        }
    }
    
    /// Whether to show the "includes Pro" header for Premium tier
    private var showPremiumHeader: Bool {
        showPremiumTier && feature.requiredTier == .pro
    }
    
    /// Context-aware header text for the Pro tier benefits list
    private var proHeaderText: String {
        switch feature {
        case .aiPoweredAlerts:
            return "Unlock AI market + portfolio alerts:"
        case .advancedAlerts, .unlimitedPriceAlerts:
            return "Unlock advanced alert features:"
        case .paperTrading:
            return "Unlock paper trading:"
        case .tradingBots, .botMarketplace:
            return "Unlock trading bots:"
        case .taxReports, .unlimitedTaxTransactions:
            return "Unlock tax reporting:"
        case .whaleTracking, .smartMoneyAlerts:
            return "Unlock whale tracking:"
        case .aiPricePredictions:
            return "Unlock AI price predictions:"
        case .tradeExecution:
            return "Unlock trade execution:"
        case .riskReport:
            return "Unlock portfolio risk reports:"
        default:
            return "Unlock powerful trading tools:"
        }
    }
    
    /// Target number of rows — always the max so both tabs render identically sized lists.
    private var targetBenefitCount: Int {
        max(defaultBenefits.count, premiumBenefitsForFeature.count)
    }
    
    /// Returns benefits for the displayed tier, trimmed to consistent count.
    /// Both Pro and Premium now have 5 real benefits each, so padding should not be needed.
    private var paddedDisplayedBenefits: [(icon: String, text: String)] {
        let list = displayedBenefits
        // Both tiers should now have equal counts; just return as-is, capped to target
        return Array(list.prefix(targetBenefitCount))
    }
    
    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tier-specific header — different text for Pro vs Premium
            // Both always visible so the list height stays consistent when switching tabs.
            HStack(spacing: 8) {
                if showPremiumHeader {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.purple)
                    Text("Includes everything in Pro, plus:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textSecondary)
                } else {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [BrandColors.goldLight, BrandColors.goldBase],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(proHeaderText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
            .padding(.bottom, 2)
            .animation(.easeInOut(duration: 0.2), value: showPremiumTier)
            
            ForEach(Array(paddedDisplayedBenefits.enumerated()), id: \.offset) { index, benefit in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(displayedTierColor.opacity(0.12))
                            .frame(width: 34, height: 34)
                        
                        Image(systemName: benefit.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: showPremiumTier && feature.requiredTier == .pro
                                        ? [.purple, .purple.opacity(0.7)]
                                        : [BrandColors.goldBase, BrandColors.goldDark],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    Text(benefit.text)
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Spacer()
                }
                .opacity(animateIn ? 1 : 0)
                .offset(x: animateIn ? 0 : -20)
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.8)
                    .delay(0.2 + Double(index) * 0.06),
                    value: animateIn
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(displayedTierColor.opacity(0.15), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.25), value: showPremiumTier)
    }
    
    // MARK: - CTA Section
    
    /// The currently displayed tier (can toggle between Pro and Premium)
    private var displayedTier: SubscriptionTierType {
        showPremiumTier ? .premium : (feature.requiredTier == .premium ? .premium : .pro)
    }
    
    private var displayedTierColor: Color {
        displayedTier == .premium ? .purple : BrandColors.goldBase
    }
    
    private var displayedTierPrice: String {
        displayedTier == .premium ? "$19.99" : "$9.99"
    }
    
    /// Button text that shows "Start Free Trial" when a trial is available
    private var trialButtonText: String {
        if let trial = StoreKitManager.shared.trialDescription(for: displayedTier, isAnnual: false) {
            return "Start \(trial)"
        }
        return displayedTier == .premium ? "Get Premium" : "Get Pro"
    }
    
    private var ctaSection: some View {
        VStack(spacing: 16) {
            // Tier toggle (only show if this is a Pro feature, so users can see Premium option)
            if feature.requiredTier == .pro {
                HStack(spacing: 0) {
                    tierToggleButton(tier: .pro, label: "Pro", price: "$9.99")
                    tierToggleButton(tier: .premium, label: "Premium", price: "$19.99")
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
            }
            
            // Price hint
            HStack(spacing: 4) {
                Text("Starting at")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                Text(displayedTierPrice)
                    .font(.title3.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text("/month")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            // Trial info if available
            if let trialDesc = StoreKitManager.shared.trialDescription(for: displayedTier, isAnnual: false) {
                HStack(spacing: 6) {
                    Image(systemName: "gift.fill")
                        .font(.caption2)
                    Text(trialDesc.capitalized + " included")
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(.blue)
                .padding(.top, 2)
            }
            
            // Upgrade button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                PaywallManager.shared.trackFeatureAttempt(feature)
                onUpgrade?()
                showSubscriptionView = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(trialButtonText)
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                PremiumAccentCTAStyle(
                    accent: displayedTier == .premium ? .purple : BrandColors.goldBase,
                    foregroundColor: displayedTier == .premium ? .white : .black.opacity(0.92),
                    height: 52,
                    horizontalPadding: 16,
                    cornerRadius: 14,
                    font: .headline.weight(.bold)
                )
            )
            
            // Maybe later button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Text("Maybe Later")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
    }
    
    @ViewBuilder
    private func tierToggleButton(tier: SubscriptionTierType, label: String, price: String) -> some View {
        let isSelected = displayedTier == tier
        let color: Color = tier == .premium ? .purple : BrandColors.goldBase
        let selectedFill = LinearGradient(
            colors: tier == .premium
                ? [Color.purple.opacity(0.95), Color.purple.opacity(0.78)]
                : [BrandColors.goldLight, BrandColors.goldBase],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                showPremiumTier = (tier == .premium)
            }
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                Text(price + "/mo")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.8)
            }
            .foregroundColor(isSelected ? (tier == .premium ? .white : .black.opacity(0.92)) : DS.Adaptive.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(selectedFill) : AnyShapeStyle(Color.clear))
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.16), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? color.opacity(0.45) : DS.Adaptive.stroke.opacity(0.7),
                        lineWidth: isSelected ? 1 : 0.8
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Background
    
    private var sheetBackground: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color(white: 0.98))
            
            // Subtle gradient overlay
            LinearGradient(
                colors: [
                    tierColor.opacity(colorScheme == .dark ? 0.08 : 0.04),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Convenience View Modifier

/// A view modifier for easily presenting the unified paywall sheet
public struct UnifiedPaywallSheetModifier: ViewModifier {
    let feature: PremiumFeature
    @Binding var isPresented: Bool
    var showBenefits: Bool
    var onUpgrade: (() -> Void)?
    
    public func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                UnifiedPaywallSheet(
                    feature: feature,
                    showBenefits: showBenefits,
                    onUpgrade: onUpgrade
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
    }
}

public extension View {
    /// Presents the unified paywall sheet for a premium feature
    func unifiedPaywallSheet(
        feature: PremiumFeature,
        isPresented: Binding<Bool>,
        showBenefits: Bool = true,
        onUpgrade: (() -> Void)? = nil
    ) -> some View {
        modifier(UnifiedPaywallSheetModifier(
            feature: feature,
            isPresented: isPresented,
            showBenefits: showBenefits,
            onUpgrade: onUpgrade
        ))
    }
}

// MARK: - AI Prompt Limit Sheet

/// A specialized paywall sheet for AI prompt limits with remaining count display
public struct AIPromptLimitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    @State private var animateIn = false
    @State private var showSubscriptionView = false
    
    private var tierColor: Color { BrandColors.goldBase }
    
    public var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Scrollable content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Hero icon - compact
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color.orange.opacity(0.4), Color.orange.opacity(0)],
                                        center: .center,
                                        startRadius: 20,
                                        endRadius: 60
                                    )
                                )
                                .frame(width: 120, height: 120)
                            
                            Circle()
                                .fill(Color.orange.opacity(0.2))
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Circle()
                                        .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                                )
                            
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.orange, Color.orange.opacity(0.7)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        .scaleEffect(0.8)
                        .opacity(animateIn ? 1 : 0)
                        .offset(y: animateIn ? 0 : 20)
                        
                        // Title
                        Text("Daily Limit Reached")
                            .font(.title2.weight(.bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .opacity(animateIn ? 1 : 0)
                        
                        // Message
                        Text("You've used all \(subscriptionManager.currentTier.aiPromptsPerDay) AI prompts for today. Upgrade for more conversations!")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .opacity(animateIn ? 1 : 0)
                        
                        // Tier comparison
                        tierComparison
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 15)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                
                // CTA pinned at bottom (uses effectiveTier for developer mode consistency)
                if subscriptionManager.effectiveTier != .premium {
                    ctaSection
                        .opacity(animateIn ? 1 : 0)
                        .offset(y: animateIn ? 0 : 20)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
            }
            
            // X button overlaid in top-right corner
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
        .background(
            (colorScheme == .dark ? Color.black : Color(white: 0.98))
                .ignoresSafeArea()
        )
        .sheet(isPresented: $showSubscriptionView) {
            SubscriptionPricingView()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                animateIn = true
            }
            AnalyticsService.shared.trackPaywallViewed(source: "ai_prompt_limit_sheet", feature: "ai_prompts")
        }
    }
    
    private var tierComparison: some View {
        // Uses effectiveTier for developer mode consistency
        VStack(spacing: 10) {
            AIPromptTierRow(tier: .free, isCurrentTier: subscriptionManager.effectiveTier == .free)
            AIPromptTierRow(tier: .pro, isCurrentTier: subscriptionManager.effectiveTier == .pro)
            AIPromptTierRow(tier: .premium, isCurrentTier: subscriptionManager.effectiveTier == .premium)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DS.Adaptive.cardBackground)
        )
    }
    
    private var ctaSection: some View {
        VStack(spacing: 16) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showSubscriptionView = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text(StoreKitManager.shared.hasAnyTrialAvailable ? "Start Free Trial" : "Upgrade for More Prompts")
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                PremiumPrimaryCTAStyle(
                    height: 52,
                    horizontalPadding: 16,
                    cornerRadius: 14,
                    font: .headline.weight(.bold)
                )
            )
            
            Button {
                dismiss()
            } label: {
                Text("Maybe Later")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
        }
    }
}

// MARK: - AI Prompt Tier Row (for AI Prompt Limit Sheet)

/// Shows a tier's AI prompt allowance for comparison
private struct AIPromptTierRow: View {
    let tier: SubscriptionTierType
    let isCurrentTier: Bool
    
    var body: some View {
        HStack {
            // Tier name with icon
            HStack(spacing: 8) {
                Image(systemName: tierIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tierColor)
                    .frame(width: 20)
                
                Text(tier.displayName)
                    .font(.subheadline.weight(isCurrentTier ? .semibold : .regular))
                    .foregroundColor(isCurrentTier ? DS.Adaptive.textPrimary : DS.Adaptive.textSecondary)
                
                if isCurrentTier {
                    let currentBadgeTextColor: Color = (tier == .premium) ? .white : .black.opacity(0.9)
                    Text("Current")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(currentBadgeTextColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tierColor))
                }
            }
            
            Spacer()
            
            // Prompts per day
            Text(tier.aiPromptsDisplay)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(tier == .premium ? .green : DS.Adaptive.textSecondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrentTier ? tierColor.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isCurrentTier ? tierColor.opacity(0.3) : DS.Adaptive.stroke, lineWidth: 1)
                )
        )
    }
    
    private var tierIcon: String {
        switch tier {
        case .free: return "person.circle"
        case .pro: return "bolt.circle.fill"
        case .premium: return "crown.fill"
        }
    }
    
    private var tierColor: Color {
        switch tier {
        case .free: return .gray
        case .pro: return BrandColors.goldBase
        case .premium: return .purple
        }
    }
}

// MARK: - Preview

#if DEBUG
struct UnifiedPaywallSheet_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            UnifiedPaywallSheet(feature: .paperTrading)
                .preferredColorScheme(.dark)
            
            UnifiedPaywallSheet(feature: .whaleTracking)
                .preferredColorScheme(.dark)
            
            UnifiedPaywallSheet(feature: .advancedInsights)
                .preferredColorScheme(.light)
            
            AIPromptLimitSheet()
                .preferredColorScheme(.dark)
        }
    }
}
#endif
