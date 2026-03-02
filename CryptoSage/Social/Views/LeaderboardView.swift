//
//  LeaderboardView.swift
//  CryptoSage
//
//  Leaderboard display with categories and time periods.
//

import SwiftUI

struct LeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var leaderboardEngine = LeaderboardEngine.shared
    @StateObject private var socialService = SocialService.shared
    
    @State private var selectedCategory: LeaderboardCategory = .pnlPercent
    @State private var selectedPeriod: StatsPeriod = .month
    @State private var isLoading = false
    @State private var showJoinLeaderboardSheet = false
    @State private var showScoringInfoSheet = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 8) {
                    // Rankings header row with compact trading mode toggle
                    rankingsHeaderRow
                    
                    // Category Filter
                    categoryPicker
                    
                    // Period Filter
                    periodPicker
                    
                    // Join Leaderboard CTA (if user not enrolled or no profile)
                    if socialService.currentProfile == nil || socialService.currentProfile?.showOnLeaderboard == false {
                        joinLeaderboardBanner
                    }
                    
                    // Loading State
                    if isLoading && leaderboardEngine.currentLeaderboard.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(DS.Adaptive.textSecondary)
                            Text("Loading leaderboard...")
                                .font(.subheadline)
                                .foregroundStyle(DS.Adaptive.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        // Top 3 Podium
                        if leaderboardEngine.currentLeaderboard.count >= 3 {
                            podiumView
                                .padding(.top, 4)
                        }

                        // Leaderboard List
                        leaderboardList
                    }
                    
                    // Demo Data Indicator (subtle, at bottom)
                    if let statusMessage = leaderboardEngine.demoDataStatusMessage {
                        demoDataIndicator(message: statusMessage)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .padding(.bottom, currentUserEntry != nil ? 90 : 0) // Space for sticky footer
            }
            .task {
                await loadLeaderboard()
            }
            .refreshable {
                await loadLeaderboard(forceRefresh: true)
            }
            
            // Sticky "Your Rank" Footer
            if let userEntry = currentUserEntry {
                yourRankStickyFooter(entry: userEntry)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentUserEntry != nil)
        .sheet(isPresented: $showJoinLeaderboardSheet) {
            JoinLeaderboardSheet()
        }
        .sheet(isPresented: $showScoringInfoSheet) {
            leaderboardScoringInfoSheet
        }
    }
    
    // MARK: - Rankings Header with Compact Trading Mode Toggle
    
    private var rankingsHeaderRow: some View {
        HStack(spacing: 0) {
            // Left: "Rankings" title with participant count
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("Rankings")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    
                    Button {
                        showScoringInfoSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Text("\(leaderboardEngine.currentLeaderboard.count) traders")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Right: Trading mode segmented toggle
            compactTradingModeToggle
        }
    }
    
    private var compactTradingModeToggle: some View {
        HStack(spacing: 0) {
            ForEach(LeaderboardTradingMode.allCases, id: \.self) { mode in
                let isSelected = mode == leaderboardEngine.currentTradingMode
                let modeColor = mode.color
                
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        await leaderboardEngine.switchTradingMode(mode)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .semibold))
                        
                        Text(mode.shortName)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        if isSelected {
                            ZStack {
                                // Radial glass fill
                                Capsule()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                modeColor.opacity(isDark ? 0.14 : 0.08),
                                                modeColor.opacity(isDark ? 0.04 : 0.02),
                                                Color.clear
                                            ],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 40
                                        )
                                    )
                                // Glass top shine
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(isDark ? 0.06 : 0.18), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                modeColor.opacity(isDark ? 0.45 : 0.28),
                                                modeColor.opacity(isDark ? 0.15 : 0.08)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: isDark ? 1 : 1.2
                                    )
                            )
                        }
                    }
                    .foregroundStyle(isSelected ? modeColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            ZStack {
                Capsule()
                    .fill(DS.Adaptive.chipBackground)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(isDark ? 0.03 : 0.10), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
            .overlay(
                Capsule()
                    .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: isDark ? 0.5 : 0.8)
            )
        )
    }
    
    // MARK: - Join Leaderboard Banner (Compact)
    
    private var joinLeaderboardBanner: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showJoinLeaderboardSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Join Leaderboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Text("Compete & Win")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.Adaptive.chipBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    colors: [.yellow.opacity(0.5), .orange.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Scoring Info Sheet
    
    private var leaderboardScoringInfoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // How Rankings Work
                    VStack(alignment: .leading, spacing: 10) {
                        Label("How Rankings Work", systemImage: "trophy")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Rankings are based on your trading performance. You can compete on the Paper Trading or Portfolio leaderboard — or both.")
                            .font(.system(size: 12))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .lineSpacing(2)
                        
                        scoringInfoBullet(icon: "chart.line.uptrend.xyaxis", color: .green,
                            title: "PnL & Win Rate",
                            detail: "Your profit/loss percentage and trade success rate determine your base score")
                        scoringInfoBullet(icon: "calendar", color: .blue,
                            title: "Time-Weighted",
                            detail: "Longer track records earn up to a 1.5x score bonus — consistency is rewarded")
                        scoringInfoBullet(icon: "clock.fill", color: .purple,
                            title: "Period Filters",
                            detail: "Compare performance over the last week, month, quarter, or all-time")
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Paper Trading
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Paper Trading", systemImage: "doc.text")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Compete using virtual funds. Everyone starts with the same $100K balance for a level playing field.")
                            .font(.system(size: 12))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .lineSpacing(2)
                        
                        scoringInfoBullet(icon: "equal.circle", color: .orange,
                            title: "Standard Balance",
                            detail: "You must use the default $100K starting balance to appear on the leaderboard")
                        scoringInfoBullet(icon: "arrow.counterclockwise", color: .red,
                            title: "Resets Have Consequences",
                            detail: "Resetting triggers a 14-day cooldown, a 20% score penalty, and your time-weight bonus drops to minimum")
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Portfolio Mode
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Portfolio Mode", systemImage: "chart.pie.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Compete with your real portfolio performance from connected exchanges.")
                            .font(.system(size: 12))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .lineSpacing(2)
                        
                        scoringInfoBullet(icon: "dollarsign.circle", color: .green,
                            title: "Minimum $500 Portfolio",
                            detail: "Your connected portfolio must hold at least $500 to prevent micro-account gaming")
                        scoringInfoBullet(icon: "calendar.badge.clock", color: .blue,
                            title: "7-Day Account Age",
                            detail: "Your account must be at least 7 days old to appear on the leaderboard")
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Fair Play
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Fair Play", systemImage: "shield.checkered")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Our scoring system is designed to reward consistent, long-term performance — not lucky streaks or gaming.")
                            .font(.system(size: 12))
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .lineSpacing(2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(DS.Adaptive.background)
            .navigationTitle("How Scoring Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showScoringInfoSheet = false }
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private func scoringInfoBullet(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineSpacing(1)
            }
        }
    }
    
    // MARK: - Demo Data Indicator (Subtle, Transparent)
    
    private func demoDataIndicator(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
            
            Text(message)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.secondary.opacity(0.7))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.Adaptive.chipBackground.opacity(0.5))
        )
        .padding(.top, 8)
    }
    
    // Current user's leaderboard entry
    private var currentUserEntry: LeaderboardEntry? {
        guard let currentProfile = socialService.currentProfile else { return nil }
        return leaderboardEngine.currentLeaderboard.first(where: { $0.userId == currentProfile.id })
    }
    
    // MARK: - Premium Your Rank Sticky Footer
    @State private var footerAppeared = false
    
    private func yourRankStickyFooter(entry: LeaderboardEntry) -> some View {
        HStack(spacing: 14) {
            // Rank badge with glow — adapts glow intensity for light/dark
            ZStack {
                // Glow effect — softer in light mode
                Circle()
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.3 : 0.18))
                    .frame(width: 48, height: 48)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                    .overlay(
                        Circle()
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.3)
                                    : Color.white.opacity(0.5),
                                lineWidth: 1.5
                            )
                    )
                
                Text("#\(entry.rank)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .scaleEffect(footerAppeared ? 1 : 0.8)
            .opacity(footerAppeared ? 1 : 0)
            
            // Avatar — uses shared component for light/dark consistency
            UserAvatarView(
                username: entry.username,
                avatarPresetId: entry.avatarPresetId,
                size: 38,
                showRing: true,
                ringColor: Color.accentColor
            )
            
            // Info section
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Your Position")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    // Trading mode indicator
                    HStack(spacing: 3) {
                        Circle()
                            .fill(entry.tradingMode == .portfolio ? Color.green : Color.orange)
                            .frame(width: 5, height: 5)
                        Text(entry.tradingMode == .portfolio ? "Portfolio" : "Paper")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(entry.tradingMode == .portfolio ? Color.green : Color.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill((entry.tradingMode == .portfolio ? Color.green : Color.orange).opacity(0.15))
                    )
                }
                
                Text("@\(entry.username)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Score section with progress to next rank
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatScore(entry))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.pnlPercent >= 0 ? .green : .red)
                
                // Progress to next rank
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.yellow.opacity(0.8))
                    
                    Text("\(String(format: "%.0f", entry.winRate * 100))% win")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Scroll to position button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // In production, this would scroll to the user's position
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            // Glass-morphic background
            RoundedRectangle(cornerRadius: 20)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.08),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.5),
                                    Color.accentColor.opacity(0.2),
                                    Color.accentColor.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2)) {
                footerAppeared = true
            }
        }
    }
    
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LeaderboardCategory.allCases, id: \.self) { category in
                    Button {
                        selectedCategory = category
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await loadLeaderboard() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .font(.caption)
                            Text(category.displayName)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            Capsule()
                                .fill(selectedCategory == category 
                                    ? AnyShapeStyle(DS.Adaptive.surfaceOverlay)
                                    : AnyShapeStyle(DS.Adaptive.chipBackground))
                        }
                        .overlay {
                            Capsule()
                                .stroke(selectedCategory == category ? DS.Adaptive.textPrimary.opacity(0.3) : Color.clear, lineWidth: 1)
                        }
                        .foregroundStyle(selectedCategory == category 
                            ? DS.Adaptive.textPrimary
                            : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach([StatsPeriod.week, .month, .threeMonths, .allTime], id: \.self) { period in
                let isSelected = selectedPeriod == period
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPeriod = period
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await loadLeaderboard() }
                } label: {
                    Text(period.rawValue.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(
                                        isDark
                                            ? AnyShapeStyle(
                                                LinearGradient(
                                                    colors: [BrandColors.goldLight.opacity(0.25), BrandColors.goldBase.opacity(0.15)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            : AnyShapeStyle(BrandColors.goldBase.opacity(0.12))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(BrandColors.goldBase.opacity(isDark ? 0.5 : 0.35), lineWidth: 1)
                                    )
                            }
                        }
                        .foregroundStyle(isSelected
                            ? (isDark ? BrandColors.goldLight : BrandColors.goldBase)
                            : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DS.Adaptive.chipBackground)
        )
    }
    
    // MARK: - Premium Podium Colors
    
    // LIGHT MODE FIX: Slightly more vibrant podium colors in light mode
    // to maintain visual pop against the light background.
    private var goldGradientColors: [Color] {
        isDark ? [
            Color(red: 1.0, green: 0.85, blue: 0.4),
            Color(red: 0.85, green: 0.65, blue: 0.2),
            Color(red: 0.7, green: 0.5, blue: 0.1)
        ] : [
            Color(red: 1.0, green: 0.87, blue: 0.42),
            Color(red: 0.90, green: 0.72, blue: 0.28),
            Color(red: 0.78, green: 0.58, blue: 0.15)
        ]
    }
    
    private var silverGradientColors: [Color] {
        isDark ? [
            Color(red: 0.9, green: 0.92, blue: 0.95),
            Color(red: 0.75, green: 0.78, blue: 0.82),
            Color(red: 0.6, green: 0.65, blue: 0.7)
        ] : [
            Color(red: 0.88, green: 0.90, blue: 0.94),
            Color(red: 0.78, green: 0.80, blue: 0.86),
            Color(red: 0.65, green: 0.68, blue: 0.75)
        ]
    }
    
    private var bronzeGradientColors: [Color] {
        isDark ? [
            Color(red: 0.9, green: 0.65, blue: 0.45),
            Color(red: 0.75, green: 0.48, blue: 0.28),
            Color(red: 0.55, green: 0.35, blue: 0.2)
        ] : [
            Color(red: 0.92, green: 0.68, blue: 0.48),
            Color(red: 0.80, green: 0.55, blue: 0.35),
            Color(red: 0.65, green: 0.42, blue: 0.25)
        ]
    }
    
    @State private var podiumAnimated = false
    @State private var crownBounce = false
    @State private var shimmerPhase: CGFloat = -1
    
    private var podiumView: some View {
        VStack(spacing: 0) {
            // Winners row
            HStack(alignment: .bottom, spacing: 8) {
                // 2nd Place
                if leaderboardEngine.currentLeaderboard.count > 1 {
                    premiumPodiumItem(
                        entry: leaderboardEngine.currentLeaderboard[1],
                        rank: 2,
                        avatarSize: 56,
                        delay: 0.15
                    )
                    .opacity(podiumAnimated ? 1 : 0)
                    .offset(y: podiumAnimated ? 0 : 30)
                }
                
                // 1st Place - Larger and prominent
                premiumPodiumItem(
                    entry: leaderboardEngine.currentLeaderboard[0],
                    rank: 1,
                    avatarSize: 72,
                    delay: 0
                )
                .opacity(podiumAnimated ? 1 : 0)
                .offset(y: podiumAnimated ? 0 : 40)
                
                // 3rd Place
                if leaderboardEngine.currentLeaderboard.count > 2 {
                    premiumPodiumItem(
                        entry: leaderboardEngine.currentLeaderboard[2],
                        rank: 3,
                        avatarSize: 50,
                        delay: 0.25
                    )
                    .opacity(podiumAnimated ? 1 : 0)
                    .offset(y: podiumAnimated ? 0 : 25)
                }
            }
            
            // 3D Podium Base
            premium3DPodium
                .opacity(podiumAnimated ? 1 : 0)
                .scaleEffect(podiumAnimated ? 1 : 0.9)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                podiumAnimated = true
            }
            // Crown bounce animation
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.5)) {
                crownBounce = true
            }
            // Shimmer animation
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false).delay(1)) {
                shimmerPhase = 2
            }
        }
    }
    
    private func premiumPodiumItem(entry: LeaderboardEntry, rank: Int, avatarSize: CGFloat, delay: Double) -> some View {
        let colors = rank == 1 ? goldGradientColors : rank == 2 ? silverGradientColors : bronzeGradientColors
        let glowColor = rank == 1 ? Color.yellow : rank == 2 ? Color(white: 0.85) : Color(red: 0.85, green: 0.55, blue: 0.35)
        let medal = rank == 1 ? "🏆" : rank == 2 ? "🥈" : "🥉"
        
        // LIGHT MODE FIX: Score text colors - yellow is unreadable on light backgrounds
        let scoreColor: Color = {
            if rank == 1 {
                return isDark ? Color.yellow : Color(red: 0.72, green: 0.52, blue: 0.04) // Dark amber
            } else if rank == 2 {
                return isDark ? Color(white: 0.7) : Color(white: 0.40) // Darker gray
            } else {
                return isDark ? Color(red: 0.8, green: 0.5, blue: 0.3) : Color(red: 0.60, green: 0.35, blue: 0.15)
            }
        }()
        
        return VStack(spacing: 6) {
            // Crown for 1st place
            if rank == 1 {
                Text("👑")
                    .font(.system(size: 28))
                    .offset(y: crownBounce ? -4 : 0)
            }
            
            // Premium Avatar with animated ring
            ZStack {
                // Outer glow - reduced in light mode to avoid washed-out halo
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                glowColor.opacity(isDark ? 0.6 : 0.25),
                                glowColor.opacity(isDark ? 0.2 : 0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: avatarSize * 0.3,
                            endRadius: avatarSize * 0.8
                        )
                    )
                    .frame(width: avatarSize + 20, height: avatarSize + 20)
                
                // Animated gradient ring
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: colors + [colors[0]],
                            center: .center
                        ),
                        lineWidth: rank == 1 ? 4 : 3
                    )
                    .frame(width: avatarSize + 8, height: avatarSize + 8)
                
                // Shimmer overlay on ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(isDark ? 0.6 : 0.4), .clear],
                            startPoint: UnitPoint(x: shimmerPhase - 0.3, y: shimmerPhase - 0.3),
                            endPoint: UnitPoint(x: shimmerPhase + 0.3, y: shimmerPhase + 0.3)
                        ),
                        lineWidth: rank == 1 ? 4 : 3
                    )
                    .frame(width: avatarSize + 8, height: avatarSize + 8)
                
                // Main avatar using UserAvatarView
                UserAvatarView(
                    username: entry.username,
                    avatarPresetId: entry.avatarPresetId,
                    size: avatarSize,
                    isVerified: entry.tradingMode == .portfolio
                )
                
                // Medal badge
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                    
                    Text(medal)
                        .font(.system(size: 14))
                }
                .offset(x: avatarSize * 0.35, y: avatarSize * 0.35)
            }
            
            // Username
            Text("@\(entry.username)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
                .lineLimit(1)
            
            // Score with badge styling - adaptive colors
            Text(formatScore(entry))
                .font(.caption2.weight(.bold))
                .foregroundStyle(scoreColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(glowColor.opacity(isDark ? 0.15 : 0.12))
                )
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay), value: podiumAnimated)
    }
    
    private var premium3DPodium: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let unitWidth = width / 3
            
            ZStack {
                // 2nd place podium (left - under the 2nd place avatar)
                podiumBlock(
                    width: unitWidth - 4,
                    height: 70,
                    colors: silverGradientColors,
                    label: "2"
                )
                .offset(x: -unitWidth, y: 20)
                
                // 1st place podium (center, tallest - under the crown/winner)
                podiumBlock(
                    width: unitWidth + 8,
                    height: 90,
                    colors: goldGradientColors,
                    label: "1"
                )
                .offset(x: 0, y: 0)
                
                // 3rd place podium (right - under the 3rd place avatar)
                podiumBlock(
                    width: unitWidth - 4,
                    height: 50,
                    colors: bronzeGradientColors,
                    label: "3"
                )
                .offset(x: unitWidth, y: 30)
            }
            .frame(width: width, height: 90, alignment: .bottom)
        }
        .frame(height: 90)
    }
    
    private func podiumBlock(width: CGFloat, height: CGFloat, colors: [Color], label: String) -> some View {
        let isFirst = label == "1"
        let isDark = colorScheme == .dark
        
        // Clean number color - dark enough for contrast on metallic podiums
        let numberColor: Color = {
            if isFirst {
                return Color(red: 0.45, green: 0.32, blue: 0.05)
            } else {
                return Color(white: isDark ? 0.15 : 0.22)
            }
        }()
        
        return ZStack {
            // Shadow/depth - adaptive: lighter in light mode
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(isDark ? 0.35 : 0.12))
                .frame(width: width, height: height)
                .offset(y: isDark ? 5 : 3)
            
            // Main block with 3D gradient
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [colors[0], colors[1], colors[2]],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width, height: height)
                .overlay(
                    // Top shine band - slightly softer in light mode
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isDark ? 0.35 : 0.50),
                                        Color.white.opacity(isDark ? 0.10 : 0.15),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: height * 0.4)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                )
                .overlay(
                    // Border with metallic effect
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            LinearGradient(
                                colors: [colors[0].opacity(isDark ? 0.9 : 0.7), colors[2].opacity(isDark ? 0.5 : 0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: isDark ? 2 : 1.5
                        )
                )
            
            // REDESIGNED: Clean rank number - single layer with subtle shadow.
            // Removed the triple-stack emboss (shadow text + main text + highlight mask)
            // which created a muddled, hard-to-read effect in both modes.
            Text(label)
                .font(.system(size: isFirst ? 36 : 30, weight: .black, design: .rounded))
                .foregroundStyle(numberColor)
                .offset(y: -height * 0.08)
        }
    }
    
    private var leaderboardList: some View {
        VStack(spacing: 8) {
            ForEach(Array(leaderboardEngine.currentLeaderboard.dropFirst(3).enumerated()), id: \.element.id) { index, entry in
                LeaderboardRowView(
                    entry: entry, 
                    category: selectedCategory,
                    previousRank: generatePreviousRank(for: entry),
                    showSparkline: true,
                    isCurrentUser: entry.userId == socialService.currentProfile?.id
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)).combined(with: .scale(scale: 0.95)),
                    removal: .opacity
                ))
                .animation(
                    .spring(response: 0.4, dampingFraction: 0.75)
                    .delay(Double(index) * 0.06),
                    value: leaderboardEngine.currentLeaderboard.count
                )
            }
        }
    }
    
    private func generatePreviousRank(for entry: LeaderboardEntry) -> Int? {
        // Simulate previous rank for demo (in production, this would come from cached data)
        let change = Int.random(in: -3...5)
        let prevRank = entry.rank + change
        return prevRank > 0 ? prevRank : nil
    }
    
    private func formatScore(_ entry: LeaderboardEntry) -> String {
        switch selectedCategory {
        case .pnl:
            return "$\(formatNumber(entry.pnl))"
        case .pnlPercent:
            return "\(String(format: "%.1f", entry.pnlPercent))%"
        case .winRate:
            return "\(String(format: "%.0f", entry.winRate * 100))%"
        case .consistency, .botPerformance:
            return String(format: "%.1f", entry.score)
        case .copiedMost:
            return "\(Int(entry.score)) copies"
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }
    
    private func loadLeaderboard(forceRefresh: Bool = false) async {
        isLoading = true
        _ = try? await leaderboardEngine.fetchLeaderboard(
            category: selectedCategory,
            period: selectedPeriod,
            tradingMode: leaderboardEngine.currentTradingMode,
            forceRefresh: forceRefresh
        )
        isLoading = false
    }
}

// MARK: - Join Leaderboard Sheet

struct JoinLeaderboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var socialService = SocialService.shared
    @StateObject private var liveTracker = LivePerformanceTracker.shared
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    
    @State private var selectedMode: LeaderboardParticipationMode = .paperOnly
    @State private var isJoining = false
    @State private var showLiveConsentSheet = false
    @State private var liveTrackingConsent = false
    
    // Available modes (excluding .none since this is a join sheet)
    private var availableModes: [LeaderboardParticipationMode] {
        [.paperOnly, .liveOnly, .both]
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection
                    
                    // Trading Mode Selection
                    modeSelectionSection
                    
                    // Live Tracking Consent (if needed)
                    if selectedMode == .liveOnly || selectedMode == .both {
                        liveTrackingSection
                    }
                    
                    // Privacy Info
                    privacySection
                    
                    Spacer(minLength: 20)
                    
                    // Join Button
                    joinButton
                }
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .sheet(isPresented: $showLiveConsentSheet) {
                LiveTrackingConsentView { granted in
                    liveTrackingConsent = granted
                    if !granted && selectedMode == .liveOnly {
                        selectedMode = .paperOnly
                    } else if !granted && selectedMode == .both {
                        selectedMode = .paperOnly
                    }
                }
            }
        }
        .onAppear {
            // Default to paper if paper trading is enabled
            if paperTradingManager.isPaperTradingEnabled {
                selectedMode = .paperOnly
            }
            liveTrackingConsent = liveTracker.hasConsent
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.yellow.opacity(0.3), Color.orange.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "trophy.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Join the Leaderboard")
                .font(.title2.bold())
            
            Text("Track your trading performance and compete with other traders")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // How it works clarification
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Tracks your paper trades and/or connected exchange portfolio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
            )
            .padding(.horizontal)
        }
        .padding(.top)
    }
    
    // MARK: - Mode Selection Section
    
    private var modeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Competition Mode")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            VStack(spacing: 10) {
                ForEach(availableModes, id: \.self) { mode in
                    modeOptionRow(mode)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func modeOptionRow(_ mode: LeaderboardParticipationMode) -> some View {
        Button {
            selectedMode = mode
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            
            // Show consent sheet if selecting live mode and no consent yet
            if (mode == .liveOnly || mode == .both) && !liveTracker.hasConsent {
                showLiveConsentSheet = true
            }
        } label: {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor(for: mode).opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: mode.icon)
                        .font(.title3)
                        .foregroundStyle(iconColor(for: mode))
                }
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    
                    Text(modeDescription(for: mode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedMode == mode ? iconColor(for: mode) : .secondary.opacity(0.5))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedMode == mode ? iconColor(for: mode) : DS.Adaptive.stroke, lineWidth: selectedMode == mode ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func iconColor(for mode: LeaderboardParticipationMode) -> Color {
        switch mode {
        case .none: return .gray
        case .paperOnly: return AppTradingMode.paper.color
        case .liveOnly: return .green
        case .both: return .yellow
        }
    }
    
    private func modeDescription(for mode: LeaderboardParticipationMode) -> String {
        switch mode {
        case .none: return "Your trading performance won't appear"
        case .paperOnly: return "Uses your paper trading account ($100K virtual)"
        case .liveOnly: return "Tracks your connected exchange portfolio"
        case .both: return "Track both paper trades and real portfolio"
        }
    }
    
    // MARK: - Live Tracking Section
    
    private var liveTrackingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $liveTrackingConsent) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Portfolio Tracking")
                            .font(.subheadline.weight(.medium))
                        Text("Required for Portfolio leaderboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: liveTrackingConsent) { oldValue, newValue in
                if newValue && !liveTracker.hasConsent {
                    showLiveConsentSheet = true
                } else if !newValue && liveTracker.hasConsent {
                    liveTracker.revokeConsent()
                }
            }
            
            if !liveTrackingConsent && (selectedMode == .liveOnly || selectedMode == .both) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    
                    Text("Portfolio tracking consent required to compete in Portfolio leaderboard")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
        )
        .padding(.horizontal)
    }
    
    // MARK: - Privacy Section
    
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Your Privacy")
                    .font(.subheadline.weight(.semibold))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                privacyBullet("Only your username is shown (not real name)")
                privacyBullet("Aggregated stats only (PnL %, win rate)")
                privacyBullet("Individual trades are never shared")
                privacyBullet("You can leave anytime in Settings")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.1))
        )
        .padding(.horizontal)
    }
    
    private func privacyBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Join Button (Premium Gold Styling)
    
    private var joinButton: some View {
        let canJoin = selectedMode != .none && 
            (selectedMode == .paperOnly || liveTrackingConsent)
        
        // Gold gradient for the button
        let goldGradient = LinearGradient(
            colors: canJoin 
                ? [Color(red: 1.0, green: 0.85, blue: 0.35), Color(red: 0.95, green: 0.7, blue: 0.2)]
                : [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        return Button {
            joinLeaderboard()
        } label: {
            HStack(spacing: 8) {
                if isJoining {
                    ProgressView()
                        .tint(colorScheme == .dark ? .black : .white)
                } else {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(joinButtonText)
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(canJoin ? (colorScheme == .dark ? .black : .white) : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(goldGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: canJoin 
                                ? [Color.white.opacity(0.4), Color.yellow.opacity(0.2)]
                                : [Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isJoining || !canJoin)
        .padding(.horizontal)
    }
    
    private var joinButtonText: String {
        switch selectedMode {
        case .none: return "Select a Mode"
        case .paperOnly: return "Join Paper Leaderboard"
        case .liveOnly: return "Join Portfolio Leaderboard"
        case .both: return "Join Both Leaderboards"
        }
    }
    
    private func joinLeaderboard() {
        isJoining = true
        
        Task {
            // Determine primary trading mode
            let primaryMode: UserTradingMode = selectedMode == .liveOnly ? .portfolio : .paper
            
            if let profile = socialService.currentProfile {
                // Existing profile — update to opt into leaderboard
                try? await socialService.createOrUpdateProfile(
                    username: profile.username,
                    displayName: profile.displayName,
                    avatarPresetId: profile.avatarPresetId,
                    bio: profile.bio,
                    isPublic: profile.isPublic,
                    showOnLeaderboard: true,
                    leaderboardMode: selectedMode,
                    liveTrackingConsent: liveTrackingConsent,
                    primaryTradingMode: primaryMode,
                    socialLinks: profile.socialLinks
                )
            } else {
                // No profile yet — auto-create one with a generated username
                let generatedUsername = UsernameGenerator.generate().lowercased()
                try? await socialService.createOrUpdateProfile(
                    username: generatedUsername,
                    showOnLeaderboard: true,
                    leaderboardMode: selectedMode,
                    liveTrackingConsent: liveTrackingConsent,
                    primaryTradingMode: primaryMode
                )
            }
            
            // Update live tracker consent
            if liveTrackingConsent && !liveTracker.hasConsent {
                liveTracker.grantConsent()
            }
            
            await MainActor.run {
                isJoining = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }
}

// MARK: - Enhanced Leaderboard Row View

struct LeaderboardRowView: View {
    let entry: LeaderboardEntry
    let category: LeaderboardCategory
    var previousRank: Int? = nil
    var showSparkline: Bool = true
    var isCurrentUser: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var rankChangeAnimated = false
    
    // Simulated performance data for sparkline — more data points for smoother line
    private var performanceData: [Double] {
        // Use a seeded random for consistent sparklines per user (avoid re-randomizing on re-render)
        var rng = LeaderboardSeededRNG(seed: UInt64(abs(entry.username.hashValue)))
        let baseValue = 100.0
        let trend = entry.pnlPercent / 100.0
        var data: [Double] = []
        var current = baseValue
        let pointCount = 40
        
        for i in 0..<pointCount {
            let noise = Double.random(in: -1.5...1.5, using: &rng)
            let trendComponent = trend * Double(i) / Double(pointCount) * 12
            // Add some natural-looking momentum
            let momentum = i > 0 ? (current - baseValue) * 0.02 : 0
            current = baseValue + trendComponent + noise + momentum
            data.append(current)
        }
        return data
    }
    
    // Premium avatar gradient colors based on rank tier
    private var avatarGradient: [Color] {
        switch entry.rank {
        case 4...5:
            return [Color(red: 0.65, green: 0.45, blue: 0.85), Color(red: 0.45, green: 0.25, blue: 0.65)]
        case 6...7:
            return [Color(red: 0.35, green: 0.55, blue: 0.85), Color(red: 0.25, green: 0.40, blue: 0.70)]
        case 8...10:
            return [Color(red: 0.25, green: 0.65, blue: 0.65), Color(red: 0.15, green: 0.50, blue: 0.55)]
        default:
            return [Color(red: 0.55, green: 0.55, blue: 0.65), Color(red: 0.40, green: 0.40, blue: 0.50)]
        }
    }
    
    private var isTopTen: Bool { entry.rank <= 10 }
    
    private var rankChange: Int? {
        guard let prev = previousRank else { return nil }
        return prev - entry.rank
    }
    
    private var isTrending: Bool {
        guard let change = rankChange else { return false }
        return change >= 3
    }
    
    private var isHotStreak: Bool {
        entry.winRate >= 0.7 && entry.totalTrades >= 10
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Rank Section with change indicator
            rankSection
            
            // Avatar with premium styling
            avatarSection
            
            // User info
            infoSection
            
            Spacer(minLength: 2)
            
            // Mini sparkline chart — inspired by home watchlist sparklines
            if showSparkline {
                SparklineView(
                    data: performanceData,
                    isPositive: entry.pnlPercent >= 0,
                    height: 30,
                    lineWidth: SparklineConsistency.miniCardLineWidth,
                    fillOpacity: SparklineConsistency.miniCardFillOpacity,
                    gradientStroke: true,
                    showEndDot: true,
                    leadingFade: 0.0,
                    trailingFade: 0.0,
                    showTrailHighlight: false,
                    trailLengthRatio: 0.0,
                    endDotPulse: false,
                    preferredWidth: 64,
                    backgroundStyle: .none,
                    cornerRadius: 4,
                    glowOpacity: SparklineConsistency.miniCardGlowOpacity,
                    glowLineWidth: SparklineConsistency.miniCardGlowLineWidth,
                    smoothSamplesPerSegment: SparklineConsistency.miniCardSmoothSamplesPerSegment,
                    maxPlottedPoints: SparklineConsistency.miniCardMaxPlottedPoints,
                    horizontalInset: SparklineConsistency.miniCardHorizontalInset,
                    compact: false
                )
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: appeared)
            }
            
            // Score section
            scoreSection
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            // LIGHT MODE FIX: Use warm cream instead of pure white for cohesion
            // with the rest of the app's light mode card backgrounds
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    isCurrentUser
                        ? (colorScheme == .dark ? Color.accentColor.opacity(0.08) : Color.accentColor.opacity(0.05))
                        : (colorScheme == .dark ? Color(white: 0.08) : Color(red: 1.0, green: 0.99, blue: 0.97))
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    // LIGHT MODE FIX: Add subtle warm stroke for non-ranked rows in light mode
                    // so they don't float without definition against the background.
                    strokeWidth > 0
                        ? strokeGradient
                        : LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.clear]
                                : [DS.Adaptive.stroke.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                          ),
                    lineWidth: strokeWidth > 0 ? strokeWidth : (colorScheme == .dark ? 0 : 0.8)
                )
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(Double(entry.rank - 3) * 0.04)) {
                appeared = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.3)) {
                rankChangeAnimated = true
            }
        }
    }
    
    // MARK: - Subviews
    
    private var rankSection: some View {
        VStack(spacing: 2) {
            ZStack {
                // Background for top 10
                if isTopTen {
                    Circle()
                        .fill(rankBadgeColor.opacity(0.12))
                        .frame(width: 30, height: 30)
                }
                
                Text("#\(entry.rank)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isTopTen ? rankBadgeColor : .secondary)
            }
            
            // Rank change indicator with animation
            if let change = rankChange, change != 0 {
                HStack(spacing: 1) {
                    Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(abs(change))")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(change > 0 ? .green : .red)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule()
                        .fill((change > 0 ? Color.green : Color.red).opacity(0.12))
                )
                .scaleEffect(rankChangeAnimated ? 1 : 0.5)
                .opacity(rankChangeAnimated ? 1 : 0)
            }
        }
        .frame(width: 36, alignment: .center)
    }
    
    private var avatarSection: some View {
        ZStack {
            // Glow for top performers
            if isTopTen || isTrending {
                Circle()
                    .fill(avatarGradient[0].opacity(0.35))
                    .frame(width: 44, height: 44)
            }
            
            // Main avatar using UserAvatarView
            LeaderboardAvatarView(
                username: entry.username,
                avatarPresetId: entry.avatarPresetId,
                rank: entry.rank,
                size: 38,
                tradingMode: entry.tradingMode
            )
            
            // Trending flame or hot streak badge
            if isTrending {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .offset(x: 15, y: -15)
            } else if isHotStreak {
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 14, height: 14)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(x: 15, y: -15)
            }
        }
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                // Username - allow more space for full display
                Text("@\(entry.username)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8) // Scale down slightly if needed
                
                // Trading mode indicator - colored dot
                Circle()
                    .fill(entry.tradingMode == .portfolio ? Color.green : Color.orange)
                    .frame(width: 5, height: 5)
                    .overlay(
                        Circle()
                            .stroke(entry.tradingMode == .portfolio ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1.5)
                    )
                
                // Badges inline with name for space efficiency
                if !entry.badges.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(entry.badges.prefix(2)) { badge in
                            Image(systemName: badge.iconName)
                                .font(.system(size: 9))
                                .foregroundStyle(badge.tier.color)
                        }
                    }
                }
            }
            
            // Trade count
            Text("\(entry.totalTrades) trades")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 80, alignment: .leading)
        .layoutPriority(1) // Give username priority over sparkline
    }
    
    private var scoreSection: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(formatScore())
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(entry.pnlPercent >= 0 ? .green : .red)
            
            HStack(spacing: 2) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary.opacity(0.7))
                
                Text("\(String(format: "%.0f", entry.winRate * 100))%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 60, alignment: .trailing)
    }
    
    // MARK: - Computed Styling
    
    private var rankBadgeColor: Color {
        switch entry.rank {
        case 4...5: return .purple
        case 6...7: return .blue
        case 8...10: return .cyan
        default: return .secondary
        }
    }
    
    private var strokeGradient: LinearGradient {
        if isCurrentUser {
            return LinearGradient(
                colors: [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if isTrending {
            return LinearGradient(
                colors: [.orange.opacity(0.5), .red.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if isTopTen {
            return LinearGradient(
                colors: [rankBadgeColor.opacity(0.35), rankBadgeColor.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
        }
    }
    
    private var strokeWidth: CGFloat {
        isCurrentUser ? 2 : (isTrending || isTopTen ? 1 : 0)
    }
    
    private var shadowColor: Color {
        if isCurrentUser {
            return Color.accentColor.opacity(0.2)
        } else if isTrending {
            return Color.orange.opacity(0.15)
        }
        return Color.clear
    }
    
    private var shadowRadius: CGFloat {
        (isCurrentUser || isTrending) ? 8 : 0
    }
    
    private func formatScore() -> String {
        switch category {
        case .pnl:
            let prefix = entry.pnl >= 0 ? "+" : ""
            return "\(prefix)$\(formatNumber(abs(entry.pnl)))"
        case .pnlPercent:
            let prefix = entry.pnlPercent >= 0 ? "+" : ""
            return "\(prefix)\(String(format: "%.1f", entry.pnlPercent))%"
        case .winRate:
            return "\(String(format: "%.0f", entry.winRate * 100))%"
        default:
            return String(format: "%.1f", entry.score)
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }
}

// MARK: - Seeded Random Number Generator (deterministic sparkline data)

private struct LeaderboardSeededRNG: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed == 0 ? 1 : seed
    }
    
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

#Preview {
    LeaderboardView()
}
