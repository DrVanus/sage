//
//  SocialTabView.swift
//  CryptoSage
//
//  Main social tab with feed, leaderboard, and discover sections.
//

import SwiftUI

struct SocialTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var socialService = SocialService.shared
    @StateObject private var leaderboardEngine = LeaderboardEngine.shared
    
    @State private var selectedSection: SocialSection
    @State private var showingProfileSheet = false
    @State private var showingCreateProfileSheet = false
    @State private var showingUserSearch = false
    @State private var showSocialProfilePaywall = false
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Namespace private var sectionAnimation
    
    /// Optional dismiss callback when presented as fullScreenCover
    var onDismiss: (() -> Void)?
    
    private var isDark: Bool { colorScheme == .dark }
    
    enum SocialSection: String, CaseIterable {
        case leaderboard = "Leaderboard"
        case feed = "Feed"
        case discover = "Discover"
        
        var icon: String {
            switch self {
            case .leaderboard: return "trophy"
            case .feed: return "bubble.left.and.text.bubble.right"
            case .discover: return "safari"
            }
        }
    }
    
    /// Initialize with an optional starting section for deep linking
    init(initialSection: SocialSection = .leaderboard, onDismiss: (() -> Void)? = nil) {
        _selectedSection = State(initialValue: initialSection)
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    // Unified header: back chevron + section tabs + search/profile
                    unifiedHeaderBar
                    
                    // Content — tab order matches SocialSection.allCases
                    TabView(selection: $selectedSection) {
                        LeaderboardView()
                            .tag(SocialSection.leaderboard)
                        
                        SocialFeedView()
                            .tag(SocialSection.feed)
                        
                        BotMarketplaceView()
                            .tag(SocialSection.discover)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                
                // Show onboarding overlay if no profile exists and not browsing as guest
                if socialService.currentProfile == nil && !socialService.isBrowsingAsGuest {
                    socialOnboardingOverlay
                }
            }
            .background(backgroundColor)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingProfileSheet) {
                if socialService.currentProfile != nil {
                    UserProfileView(isCurrentUser: true)
                }
            }
            .sheet(isPresented: $showingCreateProfileSheet) {
                EditProfileView(isNewProfile: true)
            }
            .sheet(isPresented: $showingUserSearch) {
                UserSearchSheet()
            }
            .unifiedPaywallSheet(feature: .socialProfile, isPresented: $showSocialProfilePaywall)
        }
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .simpleEdgeSwipeToDismiss(minimumDistance: 70, onDismiss: dismissSocialTab)
    }

    private func dismissSocialTab() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
    
    // MARK: - Unified Header Bar (replaces SubpageHeaderBar + sectionPicker)
    
    private var unifiedHeaderBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left: Premium gold nav button (unified across app)
                CSNavButton(
                    icon: "chevron.left",
                    action: dismissSocialTab
                )
                
                Spacer(minLength: 0)
                
                // Center: Section tabs (Feed | Leaderboard | Discover) — truly centered
                HStack(spacing: 0) {
                    ForEach(SocialSection.allCases, id: \.self) { section in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedSection = section
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(section.rawValue)
                                .font(.system(size: 13, weight: selectedSection == section ? .bold : .medium))
                                .foregroundStyle(
                                    selectedSection == section
                                        ? (isDark ? Color.black : Color.white)
                                        : DS.Adaptive.textSecondary
                                )
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background {
                                    if selectedSection == section {
                                        Capsule()
                                            .fill(
                                                isDark
                                                    ? AnyShapeStyle(BrandColors.goldHorizontal)
                                                    : AnyShapeStyle(BrandColors.goldBase)
                                            )
                                            .matchedGeometryEffect(id: "sectionTab", in: sectionAnimation)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(
                    Capsule()
                        .fill(DS.Adaptive.chipBackground)
                )
                
                Spacer(minLength: 0)
                
                // Right: Search + Profile (same width allocation as left for centering)
                HStack(spacing: 8) {
                    Button {
                        showingUserSearch = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                    
                    profileButton
                }
                .frame(width: 44, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DS.Adaptive.background.opacity(0.98))
            
            // Bottom divider (matches SubpageHeaderBar)
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(height: 0.5)
        }
    }
    
    // MARK: - Social Onboarding Overlay
    
    private var socialOnboardingOverlay: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Title
                VStack(spacing: 8) {
                    Text("Join the Community")
                        .font(.title2.bold())
                    
                    Text("Create a profile to compete on leaderboards, share bots, and connect with other traders")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                // Features
                VStack(alignment: .leading, spacing: 12) {
                    featureRow(icon: "trophy.fill", color: .yellow, text: "Compete on Paper & Portfolio leaderboards")
                    featureRow(icon: "square.and.arrow.up.fill", color: .blue, text: "Share your trading bots")
                    featureRow(icon: "person.2.fill", color: .purple, text: "Follow top traders")
                    featureRow(icon: "lock.shield.fill", color: .green, text: "Your privacy is protected")
                }
                .padding(.horizontal, 32)
                
                // Create Profile Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if subscriptionManager.hasAccess(to: .socialProfile) {
                        showingCreateProfileSheet = true
                    } else {
                        showSocialProfilePaywall = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                        Text("Create Profile")
                    }
                    .font(.headline)
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
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
                
                // Browse as Guest
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    // Allow browsing without profile - just dismiss the overlay
                    // by enabling demo mode silently for viewing only
                    socialService.enableDemoMode()
                } label: {
                    Text("Browse as Guest")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.cyan)
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(DS.Adaptive.textPrimary)
        }
    }
    
    // sectionPicker is now integrated into unifiedHeaderBar above
    
    private var profileButton: some View {
        Button {
            if socialService.currentProfile != nil {
                showingProfileSheet = true
            } else if subscriptionManager.hasAccess(to: .socialProfile) {
                showingCreateProfileSheet = true
            } else {
                showSocialProfilePaywall = true
            }
        } label: {
            if let profile = socialService.currentProfile {
                HStack(spacing: 6) {
                    UserAvatarView(
                        username: profile.username,
                        avatarPresetId: profile.avatarPresetId,
                        size: 28
                    )
                }
            } else {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title3)
            }
        }
    }
    
    private var backgroundColor: Color {
        DS.Adaptive.backgroundSecondary
    }
}

// MARK: - Social Tab Colors Extension

extension SocialTabView {
    static func cardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.1) : .white
    }
}

// MARK: - Feed Filter Type

enum FeedFilterType: String, CaseIterable {
    case all = "All"
    case shares = "Shares"
    case copies = "Copies"
    case achievements = "Achievements"
    case updates = "Updates"
    
    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .shares: return "square.and.arrow.up"
        case .copies: return "doc.on.doc"
        case .achievements: return "trophy"
        case .updates: return "chart.line.uptrend.xyaxis"
        }
    }
    
    var activityTypes: [ActivityType] {
        switch self {
        case .all: return ActivityType.allCases
        case .shares: return [.sharedBot]
        case .copies: return [.copiedBot]
        case .achievements: return [.achievedRank, .earnedBadge, .milestoneReached]
        case .updates: return [.botPerformance]
        }
    }
}

// MARK: - Social Feed View

struct SocialFeedView: View {
    @StateObject private var socialService = SocialService.shared
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var selectedFilter: FeedFilterType = .all
    @Environment(\.colorScheme) private var colorScheme
    
    private var filteredFeed: [ActivityFeedItem] {
        if selectedFilter == .all {
            return socialService.activityFeed
        }
        return socialService.activityFeed.filter { item in
            selectedFilter.activityTypes.contains(item.activityType)
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Feed Filter Chips
                feedFilterBar
                
                // Pull-to-refresh indicator
                if isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Refreshing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                if isLoading && socialService.activityFeed.isEmpty {
                    // Skeleton loading states
                    ForEach(0..<4, id: \.self) { _ in
                        ActivityFeedSkeletonCard()
                    }
                } else if filteredFeed.isEmpty && !isLoading {
                    if selectedFilter == .all {
                    emptyStateView
                    } else {
                        emptyFilterView
                    }
                } else {
                    ForEach(Array(filteredFeed.enumerated()), id: \.element.id) { index, item in
                        ActivityFeedCard(item: item)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.8)
                                .delay(Double(index) * 0.05),
                                value: filteredFeed.count
                            )
                    }
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.3), value: filteredFeed.count)
        }
        // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
        .withUIKitScrollBridge()
        .refreshable {
            await refreshFeed()
        }
        .task {
            if socialService.activityFeed.isEmpty {
                isLoading = true
                _ = try? await socialService.fetchActivityFeed()
                isLoading = false
            }
        }
    }
    
    private var feedFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedFilterType.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.icon)
                                .font(.caption)
                            Text(filter.rawValue)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            Capsule()
                                .fill(selectedFilter == filter
                                    ? Color.accentColor.opacity(0.2)
                                    : (colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.94)))
                        }
                        .foregroundStyle(selectedFilter == filter ? Color.accentColor : .secondary)
                        .overlay(
                            Capsule()
                                .stroke(selectedFilter == filter ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 4)
    }
    
    private var emptyFilterView: some View {
        VStack(spacing: 16) {
            Image(systemName: selectedFilter.icon)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            
            Text("No \(selectedFilter.rawValue) Activity")
                .font(.headline)
            
            Text("Check back later or try a different filter")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button {
                withAnimation {
                    selectedFilter = .all
                }
            } label: {
                Text("View All Activity")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private func refreshFeed() async {
        withAnimation(.easeInOut(duration: 0.2)) {
            isRefreshing = true
        }
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        _ = try? await socialService.fetchActivityFeed()
        
        // Small delay for visual feedback
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            isRefreshing = false
        }
        
        // Success haptic
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No Activity Yet")
                    .font(.title3.bold())
                
                Text("Follow traders to see their activity here.\nDiscover top performers on the Leaderboard!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            
            Button {
                // Navigate to discover
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Discover Traders")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Activity Feed Skeleton Card

struct ActivityFeedSkeletonCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar skeleton
                Circle()
                    .fill(shimmerGradient)
                    .frame(width: 44, height: 44)
                
                VStack(alignment: .leading, spacing: 8) {
                    // Username skeleton
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerGradient)
                        .frame(width: 100, height: 14)
                    
                    // Title skeleton
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerGradient)
                        .frame(height: 12)
                    
                    // Description skeleton
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerGradient)
                        .frame(width: 180, height: 12)
                }
                
                Spacer()
            }
            .padding()
            
            Divider()
                .opacity(0.5)
            
            // Interaction buttons skeleton
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerGradient)
                        .frame(width: 60, height: 12)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    
                    if index < 2 {
                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                            .frame(width: 1)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
    
    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.9),
                colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95),
                colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.9)
            ],
            startPoint: isAnimating ? .leading : .trailing,
            endPoint: isAnimating ? .trailing : .leading
        )
    }
}

// MARK: - Activity Feed Card

struct ActivityFeedCard: View {
    let item: ActivityFeedItem
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var socialService = SocialService.shared
    
    @State private var isLiked = false
    @State private var likeCount: Int = 0
    @State private var showComments = false
    @State private var isLikeAnimating = false
    @State private var isFollowing = false
    @State private var showProfilePrompt = false
    @State private var showDoubleTapHeart = false
    
    private var accentColor: Color { item.activityType.color }
    
    /// Whether the user has a social profile (required for interactions)
    private var hasProfile: Bool {
        socialService.currentProfile != nil
    }
    
    // Check if this is the current user's activity
    private var isCurrentUser: Bool {
        item.username == socialService.currentProfile?.username
    }
    
    // Follow button background color
    private var followButtonBackground: Color {
        if isFollowing {
            return colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.9)
        } else {
            return Color.accentColor
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content
        HStack(alignment: .top, spacing: 12) {
                avatarView
                contentView
            }
            .padding()
            
            // Interaction buttons
            Divider()
                .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            
            HStack(spacing: 0) {
                // Like button
                Button {
                    guard hasProfile else {
                        showProfilePrompt = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        return
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isLiked.toggle()
                        isLikeAnimating = true
                        likeCount += isLiked ? 1 : -1
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    
                    // Reset animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isLikeAnimating = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(isLiked ? Color.pink : .secondary)
                            .scaleEffect(isLikeAnimating ? 1.3 : 1.0)
                        
                        if likeCount > 0 {
                            Text("\(likeCount)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(isLiked ? Color.pink : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                
                // Divider
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    .frame(width: 1)
                    .padding(.vertical, 8)
                
                // Comment button
                Button {
                    guard hasProfile else {
                        showProfilePrompt = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        return
                    }
                    showComments = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 16, weight: .medium))
                        Text("Comment")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                
                // Divider
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    .frame(width: 1)
                    .padding(.vertical, 8)
                
                // Share button
                Button {
                    shareActivity()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .medium))
                        Text("Share")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [accentColor.opacity(0.4), accentColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        // Double-tap heart overlay
        .overlay {
            if showDoubleTapHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(showDoubleTapHeart ? 1.0 : 0.5)
                    .opacity(showDoubleTapHeart ? 1.0 : 0)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onTapGesture(count: 2) {
            // Double tap to like — requires profile
            guard hasProfile else {
                showProfilePrompt = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return
            }
            if !isLiked {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isLiked = true
                    likeCount += 1
                    showDoubleTapHeart = true
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                
                // Hide heart after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showDoubleTapHeart = false
                    }
                }
            } else {
                // Already liked - show quick pulse
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    showDoubleTapHeart = true
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showDoubleTapHeart = false
                    }
                }
            }
        }
        .onAppear {
            // Initialize with random like count for demo
            likeCount = Int.random(in: 0...50)
        }
        .sheet(isPresented: $showComments) {
            ActivityCommentsSheet(item: item)
        }
        .alert("Create a Profile", isPresented: $showProfilePrompt) {
            Button("Create Profile") {
                // Dismiss guest mode and show the onboarding overlay
                socialService.disableDemoMode()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You need a profile to interact with the community. Create one to like, comment, and follow traders.")
        }
    }
    
    // MARK: - Sub-views
    
    private var avatarView: some View {
            ZStack {
                // Glow effect
                Circle()
                    .fill(accentColor.opacity(0.3))
                    .frame(width: 52, height: 52)
                
                Circle()
                    .fill(LinearGradient(
                        colors: [accentColor, accentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: item.activityType.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
            }
    }
    
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            
            Text(item.title)
                .font(.subheadline)
            
            descriptionView
            
            botBadgeView
        }
    }
    
    private var headerRow: some View {
        HStack(spacing: 8) {
                    Text("@\(item.username)")
                        .font(.subheadline.weight(.semibold))
                    
            // Follow button (only show for other users)
            if !isCurrentUser {
                Button {
                    guard hasProfile else {
                        showProfilePrompt = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        return
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isFollowing.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isFollowing ? Color.secondary : Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(followButtonBackground)
                        )
                }
                .buttonStyle(.plain)
            }
            
                    Spacer()
                    
                    Text(item.timestamp.timeAgo())
                        .font(.caption)
                        .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private var descriptionView: some View {
        if let description = item.description {
            if item.activityType == .botPerformance {
                let isPositive = description.contains("+")
                let indicatorColor = isPositive ? Color.green : Color.red
                
                HStack(spacing: 4) {
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.weight(.bold))
                    Text(description)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(indicatorColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(indicatorColor.opacity(0.15))
                )
                .padding(.top, 2)
            } else {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
            }
        }
                }
                
    @ViewBuilder
    private var botBadgeView: some View {
                if let botName = item.relatedBotName {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.circle.fill")
                            .font(.caption)
                        Text(botName)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.cyan.opacity(0.15))
                    )
                    .padding(.top, 4)
                }
            }
    
    private func shareActivity() {
        let text = "@\(item.username) \(item.title)"
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
}

// MARK: - Activity Comments Sheet

struct ActivityCommentsSheet: View {
    let item: ActivityFeedItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var commentText = ""
    @State private var comments: [DemoComment] = []
    
    struct DemoComment: Identifiable {
        let id = UUID()
        let username: String
        let text: String
        let timeAgo: String
        var likes: Int
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Comments list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(comments) { comment in
                            CommentRow(comment: comment)
                        }
                        
                        if comments.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary.opacity(0.5))
                                
                                Text("No comments yet")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                Text("Be the first to comment!")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        }
                    }
                    .padding()
                }
                
                // Comment input
                HStack(spacing: 12) {
                    TextField("Add a comment...", text: $commentText)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
                        )
                    
                    Button {
                        if !commentText.isEmpty {
                            let newComment = DemoComment(
                                username: "demo_trader",
                                text: commentText,
                                timeAgo: "now",
                                likes: 0
                            )
                            comments.insert(newComment, at: 0)
                            commentText = ""
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(commentText.isEmpty ? Color.secondary : Color.accentColor)
                    }
                    .disabled(commentText.isEmpty)
        }
        .padding()
                .background(colorScheme == .dark ? Color(white: 0.08) : Color.white)
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.gold)
                    }
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
        .onAppear {
            // Generate demo comments
            comments = [
                DemoComment(username: "crypto_whale", text: "Great strategy! Been following this for weeks.", timeAgo: "2h", likes: 12),
                DemoComment(username: "btc_maxi", text: "What's the win rate on this setup?", timeAgo: "5h", likes: 4),
                DemoComment(username: "moon_hunter", text: "🚀🚀🚀", timeAgo: "1d", likes: 8)
            ]
        }
    }
}

struct CommentRow: View {
    let comment: ActivityCommentsSheet.DemoComment
    @State private var isLiked = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(LinearGradient(
                    colors: [.purple.opacity(0.8), .blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                ))
                .frame(width: 32, height: 32)
                .overlay {
                    Text(comment.username.prefix(1).uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("@\(comment.username)")
                        .font(.caption.weight(.semibold))
                    
                    Text("·")
                        .foregroundStyle(.secondary)
                    
                    Text(comment.timeAgo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(comment.text)
                    .font(.subheadline)
                
                HStack(spacing: 16) {
                    Button {
                        isLiked.toggle()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.caption)
                            Text("\(comment.likes + (isLiked ? 1 : 0))")
                                .font(.caption)
                        }
                        .foregroundStyle(isLiked ? .pink : .secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        // Reply action
                    } label: {
                        Text("Reply")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.97))
        )
    }
}

// MARK: - Date Extension

extension Date {
    func timeAgo() -> String {
        let interval = Date().timeIntervalSince(self)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h"
        } else if interval < 604800 {
            return "\(Int(interval / 86400))d"
        } else {
            return "\(Int(interval / 604800))w"
        }
    }
}

// MARK: - User Search Sheet

struct UserSearchSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var socialService = SocialService.shared
    
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [SearchedUser] = []
    @State private var recentSearches: [SearchedUser] = []
    @State private var suggestedUsers: [SearchedUser] = []
    @FocusState private var isSearchFocused: Bool
    
    struct SearchedUser: Identifiable {
        let id: UUID
        let username: String
        let displayName: String
        let avatarGradient: [Color]
        let followers: Int
        let pnlPercent: Double
        let isVerified: Bool
        var isFollowing: Bool
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        
                        TextField("Search traders...", text: $searchText)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit {
                                performSearch()
                            }
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isSearchFocused = true
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.95))
                    )
                }
                .padding()
                .onAppear {
                    // Auto-focus search field when sheet appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isSearchFocused = true
                    }
                }
                
                // Content
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if isSearching {
                            // Loading state
                            ForEach(0..<3, id: \.self) { _ in
                                searchSkeletonRow
                            }
                        } else if !searchText.isEmpty && !searchResults.isEmpty {
                            // Search results
                            ForEach(searchResults) { user in
                                userRow(user)
                            }
                        } else if !searchText.isEmpty && searchResults.isEmpty {
                            // No results
                            noResultsView
                        } else {
                            // Default state: suggested users
                            if !suggestedUsers.isEmpty {
                                sectionHeader("Suggested Traders")
                                ForEach(suggestedUsers) { user in
                                    userRow(user)
                                }
                            }
                            
                            if !recentSearches.isEmpty {
                                sectionHeader("Recent Searches")
                                ForEach(recentSearches) { user in
                                    userRow(user)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Find Traders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.gold)
                    }
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .onAppear {
                loadSuggestedUsers()
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.count >= 2 {
                    performSearch()
                } else if newValue.isEmpty {
                    searchResults = []
                }
            }
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    private func userRow(_ user: SearchedUser) -> some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(LinearGradient(
                    colors: user.avatarGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 48, height: 48)
                .overlay {
                    Text(user.username.prefix(1).uppercased())
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.subheadline.weight(.semibold))
                    
                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    Text("\(user.followers) followers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Text(user.pnlPercent >= 0 ? "+\(String(format: "%.1f", user.pnlPercent))%" : "\(String(format: "%.1f", user.pnlPercent))%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(user.pnlPercent >= 0 ? .green : .red)
                }
            }
            
            Spacer()
            
            // Follow Button
            Button {
                toggleFollow(user)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text(user.isFollowing ? "Following" : "Follow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(user.isFollowing ? Color.secondary : Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(user.isFollowing
                                ? (colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.9))
                                : Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
    
    private var searchSkeletonRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.9))
                .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.9))
                    .frame(width: 120, height: 14)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.93))
                    .frame(width: 80, height: 12)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .shimmer()
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            
            Text("No traders found")
                .font(.headline)
            
            Text("Try a different search term")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private func performSearch() {
        guard searchText.count >= 2 else { return }
        
        isSearching = true
        
        // Simulate search delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Generate demo results based on search text
            let lowercasedSearch = searchText.lowercased()
            searchResults = generateDemoUsers().filter { user in
                user.username.lowercased().contains(lowercasedSearch) ||
                user.displayName.lowercased().contains(lowercasedSearch)
            }
            isSearching = false
        }
    }
    
    private func loadSuggestedUsers() {
        suggestedUsers = generateDemoUsers().shuffled().prefix(5).map { $0 }
    }
    
    private func toggleFollow(_ user: SearchedUser) {
        if let index = searchResults.firstIndex(where: { $0.id == user.id }) {
            searchResults[index].isFollowing.toggle()
        }
        if let index = suggestedUsers.firstIndex(where: { $0.id == user.id }) {
            suggestedUsers[index].isFollowing.toggle()
        }
    }
    
    private func generateDemoUsers() -> [SearchedUser] {
        let gradients: [[Color]] = [
            [.purple, .blue],
            [.orange, .red],
            [.green, .teal],
            [.pink, .purple],
            [.yellow, .orange],
            [.cyan, .blue],
            [.indigo, .purple]
        ]
        
        return [
            SearchedUser(id: UUID(), username: "crypto_legend", displayName: "Crypto Legend", avatarGradient: gradients[0], followers: 15420, pnlPercent: 285.4, isVerified: true, isFollowing: false),
            SearchedUser(id: UUID(), username: "whale_hunter", displayName: "Whale Hunter", avatarGradient: gradients[1], followers: 8930, pnlPercent: 195.2, isVerified: true, isFollowing: false),
            SearchedUser(id: UUID(), username: "moon_sniper", displayName: "Moon Sniper", avatarGradient: gradients[2], followers: 6250, pnlPercent: 168.5, isVerified: false, isFollowing: false),
            SearchedUser(id: UUID(), username: "diamond_whale", displayName: "Diamond Whale", avatarGradient: gradients[3], followers: 4820, pnlPercent: 142.3, isVerified: true, isFollowing: false),
            SearchedUser(id: UUID(), username: "defi_master", displayName: "DeFi Master", avatarGradient: gradients[4], followers: 3950, pnlPercent: 128.9, isVerified: false, isFollowing: false),
            SearchedUser(id: UUID(), username: "grid_genius", displayName: "Grid Genius", avatarGradient: gradients[5], followers: 3120, pnlPercent: 115.4, isVerified: true, isFollowing: false),
            SearchedUser(id: UUID(), username: "dca_warrior", displayName: "DCA Warrior", avatarGradient: gradients[6], followers: 2840, pnlPercent: 98.7, isVerified: false, isFollowing: false),
            SearchedUser(id: UUID(), username: "btc_maxi", displayName: "BTC Maximalist", avatarGradient: gradients[0], followers: 2150, pnlPercent: 76.3, isVerified: false, isFollowing: false),
            SearchedUser(id: UUID(), username: "algo_trader", displayName: "Algo Trader", avatarGradient: gradients[1], followers: 1890, pnlPercent: 64.2, isVerified: true, isFollowing: false),
            SearchedUser(id: UUID(), username: "scalper_pro", displayName: "Scalper Pro", avatarGradient: gradients[2], followers: 1420, pnlPercent: 52.8, isVerified: false, isFollowing: false)
        ]
    }
}

// MARK: - Social Header Button Style

private struct SocialHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    SocialTabView()
}
