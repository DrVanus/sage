//
//  UserProfileView.swift
//  CryptoSage
//
//  User profile display with stats, badges, and shared bots.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct UserProfileView: View {
    var isCurrentUser: Bool = false
    var userId: UUID?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var socialService = SocialService.shared
    
    @State private var selectedTab: ProfileTab = .stats
    @State private var showingEditProfile = false
    @State private var isFollowing = false
    
    enum ProfileTab: String, CaseIterable {
        case stats = "Stats"
        case bots = "Bots"
        case badges = "Badges"
    }
    
    @State private var showingFollowers = false
    @State private var showingFollowing = false
    @State private var showingShareSheet = false
    @State private var selectedChartPeriod: ChartPeriod = .thirtyDays
    
    enum ChartPeriod: String, CaseIterable {
        case sevenDays = "7D"
        case thirtyDays = "30D"
        case ninetyDays = "90D"
        
        var days: Int {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            }
        }
        
        var displayName: String {
            switch self {
            case .sevenDays: return "7 Days"
            case .thirtyDays: return "30 Days"
            case .ninetyDays: return "90 Days"
            }
        }
    }
    
    private var profile: UserProfile? {
        if isCurrentUser {
            return socialService.currentProfile
        }
        // In real app, would fetch from server
        return socialService.currentProfile
    }
    
    // Get paper trading starting balance
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    
    private var startingBalance: Double {
        // Use paper trading starting balance, default to $100,000
        paperTradingManager.startingBalance
    }
    
    // Generate performance data for the chart based on selected period
    // Uses seeded random to prevent glitching on re-renders
    // More data points + smoother noise for a professional chart appearance
    private var performanceChartData: [Double] {
        let baseValue = startingBalance
        let finalPnL = profile?.performanceStats.totalPnL ?? 0
        let days = selectedChartPeriod.days
        
        // Use more data points for smoother curves (3x the day count, min 60)
        let pointCount = max(60, days * 3)
        var data: [Double] = []
        
        // Scale PnL based on period (longer period = more cumulative)
        let scaledPnL = finalPnL * (Double(days) / 30.0)
        
        // Use deterministic "random" based on profile ID + period to prevent glitching
        let seed = (profile?.id.hashValue ?? 0) ^ selectedChartPeriod.days.hashValue
        var seededRandom = SeededRandomNumberGenerator(seed: UInt64(abs(seed)))
        
        // Generate smoother data with momentum and mean-reversion
        var current = baseValue
        var velocity: Double = 0
        
        for i in 0..<pointCount {
            let progress = Double(i) / Double(max(1, pointCount - 1))
            let targetValue = baseValue + (scaledPnL * progress)
            
            // Smooth noise: small random impulse + momentum + mean-reversion to target
            let impulse = Double.random(in: -1.0...1.0, using: &seededRandom) * baseValue * 0.003
            velocity = velocity * 0.7 + impulse  // Momentum with damping
            let meanReversion = (targetValue - current) * 0.15  // Pull towards trend line
            
            current += velocity + meanReversion
            data.append(current)
        }
        return data
    }
    
    // Seeded random number generator for deterministic chart data
    struct SeededRandomNumberGenerator: RandomNumberGenerator {
        var state: UInt64
        
        init(seed: UInt64) {
            state = seed == 0 ? 1 : seed
        }
        
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Profile Header
                    profileHeader
                    
                    // Performance Chart
                    performanceChartSection
                    
                    // Stats Summary
                    statsSummary
                    
                    // Tab Picker
                    tabPicker
                    
                    // Tab Content
                    tabContent
                }
                .padding()
            }
            .background(backgroundColor)
            .navigationTitle(isCurrentUser ? "My Profile" : "@\(profile?.username ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CSNavButton(
                        icon: "xmark",
                        action: { dismiss() },
                        accessibilityText: "Close",
                        accessibilityHintText: "Return to previous screen"
                    )
                }
                
                if isCurrentUser {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingEditProfile = true
                        } label: {
                            Text("Edit")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(
                                            colorScheme == .dark
                                                ? AnyShapeStyle(BrandColors.goldHorizontal)
                                                : AnyShapeStyle(BrandColors.goldBase)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView(isNewProfile: false)
            }
            .sheet(isPresented: $showingFollowers) {
                FollowListView(mode: .followers, username: profile?.username ?? "")
            }
            .sheet(isPresented: $showingFollowing) {
                FollowListView(mode: .following, username: profile?.username ?? "")
            }
            .sheet(isPresented: $showingShareSheet) {
                if let profile = profile {
                    ShareProfileSheet(profile: profile)
                }
            }
            .toolbarBackground(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
    }
    
    // MARK: - Performance Chart Section
    
    private var performanceChartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with period picker
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Performance")
                        .font(.headline.weight(.semibold))
                }
                
                Spacer()
                
                // Premium Period Picker
                HStack(spacing: 2) {
                    ForEach(ChartPeriod.allCases, id: \.self) { period in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedChartPeriod = period
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(period.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selectedChartPeriod == period ? .white : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background {
                                    if selectedChartPeriod == period {
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.purple, Color.blue],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.94))
                )
            }
            
            // Chart with enhanced styling — inspired by HomeLineChartView
            SparklineView(
                data: performanceChartData,
                isPositive: (profile?.performanceStats.totalPnL ?? 0) >= 0,
                height: 150,
                lineWidth: SparklineConsistency.listLineWidth + 0.2,
                fillOpacity: 0.35,
                gradientStroke: true,
                showEndDot: true,
                leadingFade: 0.04,
                trailingFade: 0.01,
                showTrailHighlight: true,
                trailLengthRatio: 0.2,
                endDotPulse: true,
                showBaseline: true,
                backgroundStyle: .glass,
                cornerRadius: 14,
                glowOpacity: SparklineConsistency.listGlowOpacity + 0.08,
                glowLineWidth: SparklineConsistency.listGlowLineWidth,
                smoothSamplesPerSegment: SparklineConsistency.listSmoothSamplesPerSegment + 1,
                maxPlottedPoints: SparklineConsistency.listMaxPlottedPoints + 40,
                horizontalInset: SparklineConsistency.listHorizontalInset + 2,
                compact: false
            )
            
            // Chart labels with enhanced styling
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Starting")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    Text(formatCurrencySimple(startingBalance))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                // Period change indicator
                VStack(spacing: 4) {
                    Text(selectedChartPeriod.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    let changePercent = (profile?.performanceStats.pnlPercent ?? 0) * (Double(selectedChartPeriod.days) / 30.0)
                    HStack(spacing: 4) {
                        Image(systemName: changePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.bold))
                        Text("\(changePercent >= 0 ? "+" : "")\(String(format: "%.1f", changePercent))%")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(changePercent >= 0 ? .green : .red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Current")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    let currentValue = startingBalance + (profile?.performanceStats.totalPnL ?? 0)
                    Text(formatCurrencySimple(currentValue))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle((profile?.performanceStats.totalPnL ?? 0) >= 0 ? .green : .red)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(white: 0.08) : .white)
        }
    }
    
    private func formatCurrencySimple(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.2fK", value / 1_000)
        }
        return String(format: "$%.2f", value)
    }
    
    // MARK: - Premium Avatar Ring Animation
    @State private var avatarRingRotation: Double = 0
    @State private var avatarPulse: Double = 1.0
    
    private var profileHeader: some View {
        VStack(spacing: 20) {
            // Premium Avatar with animated gradient ring
            ZStack {
                // Outer animated gradient ring
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.purple,
                                Color.blue,
                                Color.cyan,
                                Color.purple
                            ],
                            center: .center,
                            startAngle: .degrees(avatarRingRotation),
                            endAngle: .degrees(avatarRingRotation + 360)
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(avatarPulse)
                
                // Soft glow behind avatar — reduced in light mode to avoid dark shading
                Circle()
                    .fill(
                        RadialGradient(
                            colors: colorScheme == .dark
                                ? [
                                    Color.purple.opacity(0.5),
                                    Color.blue.opacity(0.3),
                                    Color.clear
                                  ]
                                : [
                                    Color.purple.opacity(0.12),
                                    Color.blue.opacity(0.08),
                                    Color.clear
                                  ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                
                // Main avatar background + content
                if let presetId = profile?.avatarPresetId,
                   let preset = AvatarCatalog.avatar(withId: presetId) {
                    // User has chosen a preset avatar — show it
                    ZStack {
                        Circle()
                            .fill(preset.gradient)
                            .frame(width: 108, height: 108)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: colorScheme == .dark
                                                ? [Color.white.opacity(0.6), Color.white.opacity(0.1)]
                                                : [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                        
                        if let assetName = preset.assetImageName {
                            Image(assetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: preset.iconName)
                                .font(.system(size: 44, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                } else {
                    // No preset — show initials
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.55, green: 0.25, blue: 0.85),
                                    Color(red: 0.35, green: 0.45, blue: 0.95),
                                    Color(red: 0.25, green: 0.70, blue: 0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 108, height: 108)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [Color.white.opacity(0.6), Color.white.opacity(0.1)]
                                            : [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                    
                    Text(profile?.username.prefix(1).uppercased() ?? "?")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                
                // Verified badge (if verified)
                if profile?.isVerified ?? false {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 40, y: 40)
                }
            }
            .onAppear {
                // Animate ring rotation
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    avatarRingRotation = 360
                }
                // Subtle pulse animation
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    avatarPulse = 1.03
                }
            }
            
            // Name, Username & Trading Mode Badge
            VStack(spacing: 8) {
                // Display name
                if let displayName = profile?.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(.title2.bold())
                        .foregroundStyle(DS.Adaptive.textPrimary)
                }
                
                // Username row with trading mode badge
                HStack(spacing: 10) {
                    Text("@\(profile?.username ?? "unknown")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    // Trading mode badge
                    let tradingMode = profile?.primaryTradingMode ?? .paper
                    HStack(spacing: 4) {
                        Circle()
                            .fill(tradingMode == .portfolio ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        
                        Text(tradingMode == .portfolio ? "Portfolio" : "Paper")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(tradingMode == .portfolio ? Color.green : Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill((tradingMode == .portfolio ? Color.green : Color.orange).opacity(0.15))
                    )
                }
            }
            
            // Bio
            if let bio = profile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            
            // Social Links Row
            if let links = profile?.socialLinks, (links.twitter != nil || links.telegram != nil || links.discord != nil || links.website != nil) {
                HStack(spacing: 16) {
                    if let twitter = links.twitter, !twitter.isEmpty {
                        socialLinkButton(icon: "at", platform: "Twitter", handle: twitter, color: Color(red: 0.11, green: 0.63, blue: 0.95))
                    }
                    if let telegram = links.telegram, !telegram.isEmpty {
                        socialLinkButton(icon: "paperplane.fill", platform: "Telegram", handle: telegram, color: Color(red: 0.16, green: 0.67, blue: 0.89))
                    }
                    if let discord = links.discord, !discord.isEmpty {
                        socialLinkButton(icon: "bubble.left.fill", platform: "Discord", handle: discord, color: Color(red: 0.34, green: 0.40, blue: 0.95))
                    }
                    if let website = links.website, !website.isEmpty {
                        socialLinkButton(icon: "globe", platform: "Website", handle: website, color: Color.purple)
                    }
                }
                .padding(.top, 4)
            }
            
            // Follow Stats - Glass-morphic style
            HStack(spacing: 0) {
                Button {
                    showingFollowers = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    profileStatItemPremium(value: profile?.followersCount ?? 0, label: "Followers")
                }
                .buttonStyle(.plain)
                
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 36)
                
                Button {
                    showingFollowing = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    profileStatItemPremium(value: profile?.followingCount ?? 0, label: "Following")
                }
                .buttonStyle(.plain)
                
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1, height: 36)
                
                profileStatItemPremium(value: profile?.sharedBotsCount ?? 0, label: "Bots")
            }
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
            )
            
            // Action buttons
            HStack(spacing: 12) {
                // Follow Button (if not current user)
                if !isCurrentUser, let id = userId {
                    Button {
                        toggleFollow(id)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isFollowing ? "checkmark" : "plus")
                                .font(.system(size: 14, weight: .bold))
                            Text(isFollowing ? "Following" : "Follow")
                                .font(.subheadline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Group {
                                if isFollowing {
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.92))
                                } else {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.purple, Color.blue],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                        )
                        .foregroundColor(isFollowing ? DS.Adaptive.textPrimary : .white)
                        .overlay(
                            Capsule()
                                .stroke(isFollowing ? Color.secondary.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                }
                
                // Share Profile Button
                Button {
                    showingShareSheet = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Share")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: isCurrentUser ? .infinity : nil)
                    .padding(.horizontal, isCurrentUser ? 0 : 24)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.92))
                    )
                    .foregroundColor(DS.Adaptive.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(white: 0.08) : .white)
        }
    }
    
    private func socialLinkButton(icon: String, platform: String, handle: String, color: Color) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // In production, open the social link URL
        } label: {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func profileStatItemPremium(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text(formatCompactNumber(value))
                .font(.headline.weight(.bold))
                .foregroundStyle(DS.Adaptive.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formatCompactNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
    
    
    // MARK: - Premium Stats Summary
    @State private var statsAnimated = false
    
    private var statsSummary: some View {
        HStack(spacing: 12) {
            premiumStatCard(
                title: "Total PnL",
                value: profile?.performanceStats.totalPnL ?? 0,
                formatStyle: .currency,
                icon: "dollarsign.circle.fill",
                delay: 0
            )
            
            premiumStatCard(
                title: "ROI",
                value: profile?.performanceStats.pnlPercent ?? 0,
                formatStyle: .percent,
                icon: "chart.line.uptrend.xyaxis",
                delay: 0.1
            )
            
            premiumStatCard(
                title: "Win Rate",
                value: (profile?.performanceStats.winRate ?? 0) * 100,
                formatStyle: .winRate,
                icon: "trophy.fill",
                delay: 0.2
            )
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                statsAnimated = true
            }
        }
    }
    
    private enum StatFormatStyle {
        case currency
        case percent
        case winRate
    }
    
    private func premiumStatCard(title: String, value: Double, formatStyle: StatFormatStyle, icon: String, delay: Double) -> some View {
        let isPositive: Bool
        let displayValue: String
        let accentColor: Color
        
        switch formatStyle {
        case .currency:
            isPositive = value >= 0
            displayValue = formatCurrency(value)
            accentColor = isPositive ? .green : .red
        case .percent:
            isPositive = value >= 0
            displayValue = formatPercent(value)
            accentColor = isPositive ? .green : .red
        case .winRate:
            isPositive = value >= 50
            displayValue = "\(String(format: "%.0f", value))%"
            accentColor = isPositive ? .green : .orange
        }
        
        return VStack(spacing: 10) {
            // Icon with glow
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            
            // Value with animated appearance
            Text(displayValue)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
                .opacity(statsAnimated ? 1 : 0)
                .offset(y: statsAnimated ? 0 : 10)
                .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay), value: statsAnimated)
            
            // Label
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background {
            // Glass-morphic background
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    colorScheme == .dark
                        ? Color(white: 0.08)
                        : Color.white
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.08),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [accentColor.opacity(0.4), accentColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        
                        // Indicator bar
                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 3)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .background(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 1)
        }
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .stats:
            statsContent
        case .bots:
            botsContent
        case .badges:
            badgesContent
        }
    }
    
    private var statsContent: some View {
        VStack(spacing: 12) {
            let stats = profile?.performanceStats ?? .empty
            
            statRow(label: "Total Trades", value: "\(stats.totalTrades)")
            statRow(label: "Winning Trades", value: "\(stats.winningTrades)")
            statRow(label: "Losing Trades", value: "\(stats.losingTrades)")
            statRow(label: "Avg Trade Profit", value: formatCurrency(stats.avgProfitPerTrade))
            statRow(label: "Max Drawdown", value: formatPercent(-stats.maxDrawdown * 100))
            
            if let sharpe = stats.sharpeRatio {
                statRow(label: "Sharpe Ratio", value: String(format: "%.2f", sharpe))
            }
            
            if let best = stats.bestTrade {
                statRow(label: "Best Trade", value: formatCurrency(best))
            }
            
            if let worst = stats.worstTrade {
                statRow(label: "Worst Trade", value: formatCurrency(worst))
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 4)
    }
    
    private var botsContent: some View {
        VStack(spacing: 12) {
            if socialService.sharedBots.isEmpty {
                emptyBotsView
            } else {
                ForEach(socialService.sharedBots) { bot in
                    BotCard(
                        bot: bot,
                        isCopied: CopyTradingManager.shared.isCopied(sharedBotId: bot.id)
                    )
                }
            }
        }
    }
    
    private var emptyBotsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            
            Text("No Shared Bots")
                .font(.headline)
            
            Text("Share your trading bot configurations with the community")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private var badgesContent: some View {
        VStack(spacing: 16) {
            if profile?.badges.isEmpty ?? true {
                // Empty state with locked achievements
                emptyBadgesView
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(profile?.badges ?? []) { badge in
                        badgeCard(badge)
                    }
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private var emptyBadgesView: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "trophy")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("No Badges Yet")
                    .font(.headline)
                
                Text("Complete achievements to earn badges!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
            
            // Locked achievements preview
            VStack(alignment: .leading, spacing: 12) {
                Text("Achievements to Unlock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(lockedAchievements, id: \.name) { achievement in
                        lockedBadgeCard(achievement)
                    }
                }
            }
        }
    }
    
    private var lockedAchievements: [(name: String, icon: String, requirement: String, color: Color)] {
        [
            ("First Trade", "1.circle.fill", "Complete your first trade", .blue),
            ("Winning Streak", "flame.fill", "Win 5 trades in a row", .orange),
            ("Bot Creator", "gearshape.2.fill", "Create your first bot", .purple),
            ("Top 100", "chart.line.uptrend.xyaxis", "Reach top 100 on leaderboard", .green),
            ("Follower Magnet", "person.2.fill", "Get 100 followers", .pink),
            ("Whale Status", "dollarsign.circle.fill", "Reach $10k total PnL", .yellow)
        ]
    }
    
    private func lockedBadgeCard(_ achievement: (name: String, icon: String, requirement: String, color: Color)) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(achievement.color.opacity(0.1))
                    .frame(width: 50, height: 50)
                
                // Lock overlay
                Circle()
                    .fill(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.95))
                    .frame(width: 50, height: 50)
                    .opacity(0.7)
                
                Image(systemName: achievement.icon)
                    .font(.title3)
                    .foregroundStyle(achievement.color.opacity(0.4))
                
                // Small lock icon
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .offset(x: 16, y: 16)
            }
            
            Text(achievement.name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .onTapGesture {
            // Could show requirement in a tooltip/alert
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    
    private func badgeCard(_ badge: UserBadge) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(badge.tier.color.opacity(0.2))
                    .frame(width: 56, height: 56)
                
                Image(systemName: badge.iconName)
                    .font(.title2)
                    .foregroundStyle(badge.tier.color)
            }
            
            Text(badge.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            
            Text(badge.tier.rawValue.capitalized)
                .font(.caption2)
                .foregroundStyle(badge.tier.color)
        }
    }
    
    private func toggleFollow(_ userId: UUID) {
        Task {
            if isFollowing {
                try? await socialService.unfollow(userId: userId)
            } else {
                try? await socialService.follow(userId: userId)
            }
            isFollowing.toggle()
        }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let prefix = value >= 0 ? "+$" : "-$"
        return "\(prefix)\(String(format: "%.2f", abs(value)))"
    }
    
    private func formatPercent(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.1f", value))%"
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.96)
    }
}

// MARK: - Follow List View

struct FollowListView: View {
    enum Mode {
        case followers
        case following
        
        var title: String {
            switch self {
            case .followers: return "Followers"
            case .following: return "Following"
            }
        }
    }
    
    let mode: Mode
    let username: String
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var users: [DemoFollowUser] = []
    @State private var searchText = ""
    
    struct DemoFollowUser: Identifiable {
        let id = UUID()
        let username: String
        let displayName: String
        let pnlPercent: Double
        var isFollowing: Bool
    }
    
    var filteredUsers: [DemoFollowUser] {
        if searchText.isEmpty {
            return users
        }
        return users.filter {
            $0.username.lowercased().contains(searchText.lowercased()) ||
            $0.displayName.lowercased().contains(searchText.lowercased())
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                )
                .padding()
                
                // List
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(filteredUsers.enumerated()), id: \.element.id) { index, user in
                            FollowUserRow(user: binding(for: index))
                        }
                        
                        if filteredUsers.isEmpty && !searchText.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary.opacity(0.5))
                                
                                Text("No users found")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(
                                        colorScheme == .dark
                                            ? AnyShapeStyle(BrandColors.goldHorizontal)
                                            : AnyShapeStyle(BrandColors.goldBase)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
        .onAppear {
            generateDemoUsers()
        }
    }
    
    private func binding(for index: Int) -> Binding<DemoFollowUser> {
        Binding(
            get: { users[index] },
            set: { users[index] = $0 }
        )
    }
    
    private func generateDemoUsers() {
        let names = [
            ("crypto_whale", "Crypto Whale"),
            ("btc_maxi", "BTC Maximalist"),
            ("defi_degen", "DeFi Degen"),
            ("grid_master", "Grid Master"),
            ("dca_king", "DCA King"),
            ("moon_hunter", "Moon Hunter"),
            ("algo_trader", "Algo Trader"),
            ("eth_bull", "ETH Bull")
        ]
        
        users = names.map { name in
            DemoFollowUser(
                username: name.0,
                displayName: name.1,
                pnlPercent: Double.random(in: -20...150),
                isFollowing: mode == .following ? true : Bool.random()
            )
        }
    }
}

struct FollowUserRow: View {
    @Binding var user: FollowListView.DemoFollowUser
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.8), .blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .overlay {
                    Text(user.username.prefix(1).uppercased())
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                HStack(spacing: 4) {
                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(.secondary.opacity(0.5))
                    
                    Text(user.pnlPercent >= 0 ? "+\(String(format: "%.1f", user.pnlPercent))%" : "\(String(format: "%.1f", user.pnlPercent))%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(user.pnlPercent >= 0 ? .green : .red)
                }
            }
            
            Spacer()
            
            // Follow/Unfollow button with clear visual states
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    user.isFollowing.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text(user.isFollowing ? "Following" : "Follow")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background {
                        if user.isFollowing {
                            // Following state: gold-outlined capsule (active, prominent)
                            Capsule()
                                .fill(BrandColors.goldBase.opacity(isDark ? 0.12 : 0.08))
                                .overlay(
                                    Capsule()
                                        .stroke(BrandColors.goldBase.opacity(isDark ? 0.5 : 0.4), lineWidth: 1)
                                )
                        } else {
                            // Follow state: solid gold action button
                            Capsule()
                                .fill(
                                    isDark
                                        ? AnyShapeStyle(BrandColors.goldHorizontal)
                                        : AnyShapeStyle(BrandColors.goldBase)
                                )
                        }
                    }
                    .foregroundStyle(
                        user.isFollowing
                            ? (isDark ? BrandColors.goldLight : BrandColors.goldBase)
                            : (isDark ? Color.black : Color.white)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isDark ? Color(white: 0.08) : .white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(DS.Adaptive.stroke.opacity(0.3), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Share Profile Sheet

struct ShareProfileSheet: View {
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showQRCode = false
    
    private var profileLink: String {
        "cryptosage://profile/\(profile.username)"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Profile preview card
                VStack(spacing: 16) {
                    UserAvatarView(
                        username: profile.username,
                        avatarPresetId: profile.avatarPresetId,
                        size: 80
                    )
                    
                    VStack(spacing: 4) {
                        Text(profile.displayName ?? profile.username)
                            .font(.title3.bold())
                        
                        Text("@\(profile.username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 20) {
                        VStack {
                            Text(formatPercent(profile.performanceStats.pnlPercent))
                                .font(.headline.weight(.bold))
                                .foregroundStyle(profile.performanceStats.pnlPercent >= 0 ? .green : .red)
                            Text("ROI")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack {
                            Text("\(String(format: "%.0f", profile.performanceStats.winRate * 100))%")
                                .font(.headline.weight(.bold))
                            Text("Win Rate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack {
                            Text("\(profile.performanceStats.totalTrades)")
                                .font(.headline.weight(.bold))
                            Text("Trades")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
                )
                .padding(.horizontal)
                
                // Share options
                VStack(spacing: 12) {
                    shareButton(title: "Copy Profile Link", icon: "link", color: .blue) {
                        UIPasteboard.general.string = profileLink
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    
                    shareButton(title: "Show QR Code", icon: "qrcode", color: .orange) {
                        showQRCode = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    
                    shareButton(title: "Share to Social Media", icon: "square.and.arrow.up", color: .purple) {
                        shareToSocial()
                    }
                    
                    shareButton(title: "Share via Message", icon: "message.fill", color: .green) {
                        shareToSocial()
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Share Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(
                                        colorScheme == .dark
                                            ? AnyShapeStyle(BrandColors.goldHorizontal)
                                            : AnyShapeStyle(BrandColors.goldBase)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .sheet(isPresented: $showQRCode) {
                ProfileQRCodeView(profile: profile, link: profileLink)
            }
        }
    }
    
    private func shareButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(color.opacity(0.15))
                    )
                
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func shareToSocial() {
        let text = "Check out @\(profile.username) on CryptoSage! ROI: \(formatPercent(profile.performanceStats.pnlPercent)) | Win Rate: \(String(format: "%.0f", profile.performanceStats.winRate * 100))%"
        
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            // Find the topmost presented view controller
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(activityVC, animated: true)
        }
    }
    
    private func formatPercent(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.1f", value))%"
    }
}

// MARK: - Profile QR Code View

struct ProfileQRCodeView: View {
    let profile: UserProfile
    let link: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var qrImage: UIImage?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Scan to view profile")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                // QR Code with avatar overlay
                ZStack {
                    // QR Code background
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.white)
                        .frame(width: 240, height: 240)
                    
                    // QR Code
                    if let qrImage = qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                    } else {
                        ProgressView()
                            .frame(width: 200, height: 200)
                    }
                    
                    // Avatar overlay in center
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 56, height: 56)
                        
                        UserAvatarView(
                            username: profile.username,
                            avatarPresetId: profile.avatarPresetId,
                            size: 48
                        )
                    }
                }
                
                // Profile info
                VStack(spacing: 4) {
                    Text(profile.displayName ?? profile.username)
                        .font(.title3.weight(.bold))
                    
                    Text("@\(profile.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // Stats
                HStack(spacing: 24) {
                    statItem(value: formatPercent(profile.performanceStats.pnlPercent), label: "ROI", color: profile.performanceStats.pnlPercent >= 0 ? .green : .red)
                    statItem(value: "\(String(format: "%.0f", profile.performanceStats.winRate * 100))%", label: "Win Rate", color: .primary)
                    statItem(value: "\(profile.performanceStats.totalTrades)", label: "Trades", color: .primary)
                }
                .padding(.top, 8)
                
                Spacer()
                
                // Save button
                Button {
                    saveQRCode()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save QR Code")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 32)
            }
            .padding(.top, 32)
            .navigationTitle("Profile QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(
                                        colorScheme == .dark
                                            ? AnyShapeStyle(BrandColors.goldHorizontal)
                                            : AnyShapeStyle(BrandColors.goldBase)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .onAppear {
                generateQRCode()
            }
        }
    }
    
    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private func generateQRCode() {
        guard let data = link.data(using: .utf8) else { return }
        
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("H", forKey: "inputCorrectionLevel") // High error correction for avatar overlay
        
        guard let ciImage = filter?.outputImage else { return }
        
        // Scale up the QR code
        let scale = 10.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = ciImage.transformed(by: transform)
        
        // Convert to UIImage
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return }
        
        qrImage = UIImage(cgImage: cgImage)
    }
    
    private func saveQRCode() {
        guard let qrImage = qrImage else { return }
        UIImageWriteToSavedPhotosAlbum(qrImage, nil, nil, nil)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    private func formatPercent(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.1f", value))%"
    }
}

#Preview {
    UserProfileView(isCurrentUser: true)
}
