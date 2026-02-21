//
//  SharedBotDetailView.swift
//  CryptoSage
//
//  Detailed view for a shared bot configuration with copy functionality.
//

import SwiftUI

struct SharedBotDetailView: View {
    let bot: SharedBotConfig
    var onBotCopied: ((UUID) -> Void)? = nil  // Callback for navigation after copy
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var socialService = SocialService.shared
    @StateObject private var copyTradingManager = CopyTradingManager.shared
    @StateObject private var liveBotManager = LiveBotManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    @State private var showingCopySheet = false
    @State private var showingUpgradeSheet = false
    @State private var customName = ""
    @State private var isCopying = false
    @State private var showingCopySuccess = false
    @State private var isLiked = false
    @State private var selectedTab: BotDetailTab = .overview
    @State private var comments: [BotReview] = []
    @State private var newCommentText = ""
    @State private var userRating: Int = 0
    
    // Copy sheet state
    @State private var selectedTradingMode: CopyTradingMode = .paper
    @State private var showConfigDetails = false
    @State private var hasConfirmedLiveRisk = false
    @State private var copiedBotId: UUID?
    @State private var copyError: String?
    
    enum CopyTradingMode: String, CaseIterable {
        case paper = "Paper Trading"
        case live = "Live Trading"
        
        var icon: String {
            switch self {
            case .paper: return "doc.text"
            case .live: return "bolt.fill"
            }
        }
        
        var description: String {
            switch self {
            case .paper: return "Practice with virtual funds - no real money at risk"
            case .live: return "Trade with real funds via 3Commas - requires API connection"
            }
        }
    }
    
    enum BotDetailTab: String, CaseIterable {
        case overview = "Overview"
        case reviews = "Reviews"
        case similar = "Similar"
    }
    
    struct BotReview: Identifiable {
        let id = UUID()
        let username: String
        let rating: Int
        let text: String
        let timeAgo: String
        var likes: Int
        var isLiked: Bool = false
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection
                    
                    // Tab Selector
                    tabSelector
                    
                    // Tab Content
                    switch selectedTab {
                    case .overview:
                        overviewContent
                    case .reviews:
                        reviewsContent
                    case .similar:
                        similarBotsContent
                    }
                    
                    // Copy Button (always visible)
                    copyButton
                }
                .padding()
            }
            .background(backgroundColor)
            .navigationTitle("Bot Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("Close")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleLike()
                    } label: {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? .red : .primary)
                    }
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
            .sheet(isPresented: $showingCopySheet) {
                copyBotSheet
            }
            .alert("Bot Copied!", isPresented: $showingCopySuccess) {
                Button("View Bot") {
                    dismiss()
                    if let botId = copiedBotId {
                        onBotCopied?(botId)
                    }
                }
                Button("Done", role: .cancel) { 
                    dismiss() 
                }
            } message: {
                Text(selectedTradingMode == .paper 
                    ? "Your paper trading bot is ready! Start it anytime from your bots list."
                    : "Your live bot has been created. Monitor it in the Trading tab.")
            }
            .onAppear {
                isLiked = socialService.hasLikedBot(bot.id)
                loadDemoReviews()
            }
        }
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(BotDetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text(tab.rawValue)
                                .font(.subheadline.weight(selectedTab == tab ? .bold : .medium))
                            
                            if tab == .reviews {
                                Text("(\(comments.count))")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        
                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 3)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
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
    
    // MARK: - Overview Content
    
    private var overviewContent: some View {
        VStack(spacing: 20) {
            performanceSection
            configurationSection
            creatorSection
            
            if !bot.tags.isEmpty {
                tagsSection
            }
        }
    }
    
    // MARK: - Reviews Content
    
    private var reviewsContent: some View {
        VStack(spacing: 16) {
            // Average rating summary
            averageRatingSection
            
            // Write a review
            writeReviewSection
            
            // Reviews list
            if comments.isEmpty {
                emptyReviewsState
            } else {
                ForEach(Array(comments.enumerated()), id: \.element.id) { index, review in
                    reviewCard(review: review, index: index)
                }
            }
        }
    }
    
    private var averageRatingSection: some View {
        let avgRating = comments.isEmpty ? 0.0 : Double(comments.reduce(0) { $0 + $1.rating }) / Double(comments.count)
        
        return HStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(String(format: "%.1f", avgRating))
                    .font(.system(size: 40, weight: .bold))
                
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= Int(avgRating.rounded()) ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundStyle(star <= Int(avgRating.rounded()) ? Color.yellow : Color.secondary.opacity(0.3))
                    }
                }
                
                Text("\(comments.count) reviews")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
                .frame(height: 60)
            
            // Rating breakdown
            VStack(alignment: .leading, spacing: 4) {
                ForEach([5, 4, 3, 2, 1], id: \.self) { rating in
                    let count = comments.filter { $0.rating == rating }.count
                    let percentage = comments.isEmpty ? 0 : Double(count) / Double(comments.count)
                    
                    HStack(spacing: 8) {
                        Text("\(rating)")
                            .font(.caption)
                            .frame(width: 12)
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.2))
                                
                                Capsule()
                                    .fill(Color.yellow)
                                    .frame(width: geo.size.width * percentage)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private var writeReviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Write a Review")
                .font(.headline)
            
            // Star rating
            HStack(spacing: 8) {
                Text("Your rating:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                userRating = star
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: star <= userRating ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundStyle(star <= userRating ? Color.yellow : Color.secondary.opacity(0.3))
                                .scaleEffect(star <= userRating ? 1.1 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Comment input
            HStack(spacing: 12) {
                TextField("Share your experience...", text: $newCommentText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.95))
                    )
                
                Button {
                    submitReview()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(newCommentText.isEmpty || userRating == 0 ? Color.secondary : Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                        )
                }
                .disabled(newCommentText.isEmpty || userRating == 0)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private var emptyReviewsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No Reviews Yet")
                .font(.headline)
            
            Text("Be the first to review this bot!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private func reviewCard(review: BotReview, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Avatar
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.8), .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(review.username.prefix(1).uppercased())
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(review.username)")
                        .font(.subheadline.weight(.semibold))
                    
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= review.rating ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(star <= review.rating ? Color.yellow : Color.secondary.opacity(0.3))
                        }
                    }
                }
                
                Spacer()
                
                Text(review.timeAgo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(review.text)
                .font(.subheadline)
            
            // Actions
            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        comments[index].isLiked.toggle()
                        comments[index].likes += comments[index].isLiked ? 1 : -1
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: review.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.caption)
                        Text("Helpful (\(review.likes))")
                            .font(.caption)
                    }
                    .foregroundStyle(review.isLiked ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                
                Button {
                    // Reply action
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.caption)
                        Text("Reply")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    // MARK: - Similar Bots Content
    
    private var similarBotsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bots with similar strategy")
                .font(.headline)
            
            ForEach(generateSimilarBots()) { similarBot in
                similarBotRow(bot: similarBot)
            }
        }
    }
    
    private func similarBotRow(bot: SharedBotConfig) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(bot.botType.color.gradient)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: bot.botType.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(bot.name)
                    .font(.subheadline.weight(.semibold))
                
                Text("by @\(bot.creatorUsername)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(bot.performanceStats.pnlPercent >= 0 ? "+\(String(format: "%.1f", bot.performanceStats.pnlPercent))%" : "\(String(format: "%.1f", bot.performanceStats.pnlPercent))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(bot.performanceStats.pnlPercent >= 0 ? .green : .red)
                
                Text("\(bot.copiesCount) copies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private func generateSimilarBots() -> [SharedBotConfig] {
        // Generate 3-4 similar bots
        let names = ["Smart DCA Pro", "Grid Optimizer", "Momentum Hunter", "Trend Follower"]
        let usernames = ["algo_master", "grid_pro", "trend_king", "dca_wizard"]
        
        return (0..<3).map { i in
            SharedBotConfig(
                creatorId: UUID(),
                creatorUsername: usernames[i],
                botType: bot.botType,
                name: names[i],
                config: [:],
                tradingPair: bot.tradingPair,
                exchange: bot.exchange,
                performanceStats: BotPerformanceStats(
                    totalPnL: Double.random(in: 500...5000),
                    pnlPercent: Double.random(in: 10...60),
                    totalTrades: Int.random(in: 30...200),
                    winRate: Double.random(in: 0.5...0.8),
                    runningDays: Int.random(in: 14...90)
                ),
                copiesCount: Int.random(in: 50...300),
                likesCount: Int.random(in: 20...200),
                riskLevel: bot.riskLevel
            )
        }
    }
    
    private func loadDemoReviews() {
        comments = [
            BotReview(username: "crypto_whale", rating: 5, text: "Excellent bot! Been running it for 3 months with consistent profits. The DCA strategy works perfectly during market dips.", timeAgo: "2d", likes: 24),
            BotReview(username: "btc_maxi", rating: 4, text: "Good performance overall. Would be nice to have more customization options for the entry points.", timeAgo: "1w", likes: 12),
            BotReview(username: "defi_degen", rating: 5, text: "🚀🚀🚀 This bot is a game changer! Easy setup and great returns.", timeAgo: "2w", likes: 8),
            BotReview(username: "grid_master", rating: 3, text: "Works as expected but drawdowns can be significant during high volatility. Use with caution.", timeAgo: "1mo", likes: 15)
        ]
    }
    
    private func submitReview() {
        guard !newCommentText.isEmpty && userRating > 0 else { return }
        
        let newReview = BotReview(
            username: "demo_trader",
            rating: userRating,
            text: newCommentText,
            timeAgo: "now",
            likes: 0
        )
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            comments.insert(newReview, at: 0)
        }
        
        newCommentText = ""
        userRating = 0
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Bot Icon
            Circle()
                .fill(LinearGradient(
                    colors: [bot.botType.color, bot.botType.color.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: bot.botType.icon)
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                }
            
            Text(bot.name)
                .font(.title2.bold())
            
            HStack(spacing: 16) {
                Label(bot.botType.displayName, systemImage: bot.botType.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Label(bot.riskLevel.rawValue, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(bot.riskLevel.badgeColor)
            }
            
            if let description = bot.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                performanceCard(
                    title: "Total ROI",
                    value: formatPercent(bot.performanceStats.pnlPercent),
                    icon: "chart.line.uptrend.xyaxis",
                    color: bot.performanceStats.pnlPercent >= 0 ? .green : .red
                )
                
                performanceCard(
                    title: "Total PnL",
                    value: formatCurrency(bot.performanceStats.totalPnL),
                    icon: "dollarsign.circle",
                    color: bot.performanceStats.totalPnL >= 0 ? .green : .red
                )
                
                performanceCard(
                    title: "Win Rate",
                    value: "\(String(format: "%.1f", bot.performanceStats.winRate * 100))%",
                    icon: "trophy",
                    color: bot.performanceStats.winRate >= 0.5 ? .green : .orange
                )
                
                performanceCard(
                    title: "Total Trades",
                    value: "\(bot.performanceStats.totalTrades)",
                    icon: "arrow.left.arrow.right",
                    color: .blue
                )
                
                performanceCard(
                    title: "Max Drawdown",
                    value: "\(String(format: "%.1f", bot.performanceStats.maxDrawdown * 100))%",
                    icon: "arrow.down.right",
                    color: .orange
                )
                
                performanceCard(
                    title: "Running",
                    value: "\(bot.performanceStats.runningDays) days",
                    icon: "clock",
                    color: .purple
                )
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private func performanceCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
            }
            
            Spacer()
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        }
    }
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)
            
            VStack(spacing: 8) {
                configRow(label: "Trading Pair", value: bot.tradingPair)
                configRow(label: "Exchange", value: bot.exchange)
                
                ForEach(Array(bot.config.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                    configRow(label: key.capitalized, value: value)
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private func configRow(label: String, value: String) -> some View {
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
    
    private var creatorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Created by")
                .font(.headline)
            
            HStack(spacing: 12) {
                Circle()
                    .fill(LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text(bot.creatorUsername.prefix(1).uppercased())
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(bot.creatorUsername)")
                        .font(.subheadline.weight(.semibold))
                    
                    Text("Created \(bot.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    // View profile action
                } label: {
                    Text("View Profile")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags")
                .font(.headline)
            
            FlowLayout(spacing: 8) {
                ForEach(bot.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private var copyButton: some View {
        let isCopied = copyTradingManager.isCopied(sharedBotId: bot.id)
        let hasAccess = subscriptionManager.hasAccess(to: .copyTrading)
        
        return VStack(spacing: 12) {
            Button {
                if !isCopied {
                    if hasAccess {
                        // User has Premium access - show copy sheet
                        customName = "Copy: \(bot.name)"
                        showingCopySheet = true
                    } else {
                        // User needs to upgrade - show paywall
                        PaywallManager.shared.trackFeatureAttempt(.copyTrading)
                        showingUpgradeSheet = true
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } label: {
                HStack(spacing: 10) {
                    if isCopied {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Already Copied")
                            .font(.headline)
                    } else {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .symbolEffect(.bounce, value: showingCopySheet)
                        
                        Text("Copy This Bot")
                            .font(.headline)
                        
                        Spacer()
                        
                        // Show lock icon if user doesn't have access
                        if !hasAccess {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                Text("PREMIUM")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.purple.opacity(0.5))
                            )
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .background {
                    if isCopied {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.gray.opacity(0.3))
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: hasAccess 
                                        ? [bot.botType.color, bot.botType.color.opacity(0.7)]
                                        : [Color.purple, Color.purple.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .overlay {
                    if !isCopied {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    }
                }
                .foregroundColor(isCopied ? Color.secondary : Color.white)
            }
            .disabled(isCopied)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)
            
            // Upgrade hint for free users
            if !hasAccess && !isCopied {
                Text("Upgrade to Premium to copy trading bots from top performers")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .unifiedPaywallSheet(feature: .copyTrading, isPresented: $showingUpgradeSheet)
    }
    
    private var copyBotSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Bot Preview Card
                    botPreviewCard
                    
                    // Trading Mode Selection
                    tradingModeSelector
                    
                    // Bot Name Input
                    botNameInput
                    
                    // Configuration Preview
                    configPreviewSection
                    
                    // Live Mode Warning (if applicable)
                    if selectedTradingMode == .live {
                        liveTradeWarning
                    }
                    
                    // Error message
                    if let error = copyError {
                        errorBanner(message: error)
                    }
                    
                    // Copy Button
                    copyActionButton
                }
                .padding()
            }
            .background(colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.96))
            .navigationTitle("Copy Bot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { 
                        showingCopySheet = false 
                        resetCopyState()
                    } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.large])
        .onAppear {
            // Reset state when sheet appears
            selectedTradingMode = .paper
            hasConfirmedLiveRisk = false
            copyError = nil
        }
    }
    
    // MARK: - Copy Sheet Components
    
    private var botPreviewCard: some View {
        HStack(spacing: 14) {
            // Bot Icon
            ZStack {
                Circle()
                    .fill(bot.botType.color.opacity(0.2))
                    .frame(width: 56, height: 56)
                
                Circle()
                    .fill(bot.botType.color.gradient)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: bot.botType.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(bot.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Label(bot.botType.displayName, systemImage: bot.botType.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Text(bot.tradingPair)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 12) {
                    Label(formatPercent(bot.performanceStats.pnlPercent), systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(bot.performanceStats.pnlPercent >= 0 ? .green : .red)
                    
                    Label("\(String(format: "%.0f", bot.performanceStats.winRate * 100))% win", systemImage: "trophy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private var tradingModeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trading Mode")
                .font(.headline)
            
            ForEach(CopyTradingMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTradingMode = mode
                        if mode == .paper {
                            hasConfirmedLiveRisk = false
                        }
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 14) {
                        // Radio button
                        ZStack {
                            Circle()
                                .stroke(selectedTradingMode == mode ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                                .frame(width: 22, height: 22)
                            
                            if selectedTradingMode == mode {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 12, height: 12)
                            }
                        }
                        
                        // Icon
                        Image(systemName: mode.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(mode == .paper ? AppTradingMode.paper.color : .green)  // Amber for paper, green for live
                            .frame(width: 32)
                        
                        // Text
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(mode.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                
                                if mode == .live && !liveBotManager.isConfigured {
                                    Text("Requires 3Commas")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange)
                                        .clipShape(Capsule())
                                }
                            }
                            
                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        
                        Spacer()
                    }
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedTradingMode == mode 
                                ? (mode == .paper ? AppTradingMode.paper.color.opacity(0.1) : Color.green.opacity(0.1))
                                : (colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.97)))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selectedTradingMode == mode 
                                ? (mode == .paper ? AppTradingMode.paper.color.opacity(0.5) : Color.green.opacity(0.5))
                                : Color.clear, 
                                lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private var botNameInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bot Name")
                .font(.headline)
            
            TextField("Enter a name for your bot", text: $customName)
                .textFieldStyle(.plain)
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.95))
                }
            
            Text("This name will appear in your bot list")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private var configPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showConfigDetails.toggle()
                }
            } label: {
                HStack {
                    Text("Configuration")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: showConfigDetails ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            // Always show key config items
            VStack(spacing: 8) {
                configPreviewRow(label: "Exchange", value: bot.exchange, icon: "building.columns")
                configPreviewRow(label: "Trading Pair", value: bot.tradingPair, icon: "arrow.left.arrow.right")
                configPreviewRow(label: "Risk Level", value: bot.riskLevel.rawValue, icon: "exclamationmark.triangle", valueColor: bot.riskLevel.badgeColor)
            }
            
            // Expandable detailed config
            if showConfigDetails && !bot.config.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                
                VStack(spacing: 8) {
                    ForEach(Array(bot.config.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                        configPreviewRow(label: key.capitalized, value: value, icon: "gearshape")
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
    
    private func configPreviewRow(label: String, value: String, icon: String, valueColor: Color = .primary) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(valueColor)
        }
    }
    
    private var liveTradeWarning: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                
                Text("Live Trading Warning")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
            
            Text("This will create a real trading bot that uses actual funds. You may lose real money. Past performance does not guarantee future results.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            if !liveBotManager.isConfigured {
                HStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                        .foregroundStyle(.blue)
                    
                    Text("Connect your 3Commas account in Settings to enable live trading.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.1))
                }
            } else {
                // Risk confirmation checkbox
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        hasConfirmedLiveRisk.toggle()
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(hasConfirmedLiveRisk ? Color.orange : Color.secondary.opacity(0.3), lineWidth: 2)
                                .frame(width: 24, height: 24)
                            
                            if hasConfirmedLiveRisk {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.orange)
                            }
                        }
                        
                        Text("I understand the risks and want to proceed with live trading")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                }
        }
    }
    
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button {
                withAnimation {
                    copyError = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        }
    }
    
    private var copyActionButton: some View {
        let isLiveBlocked = selectedTradingMode == .live && (!liveBotManager.isConfigured || !hasConfirmedLiveRisk)
        let canCopy = !customName.isEmpty && !isCopying && !isLiveBlocked
        
        return Button {
            copyBot()
        } label: {
            HStack(spacing: 10) {
                if isCopying {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: selectedTradingMode == .paper ? "doc.on.doc.fill" : "bolt.fill")
                        .font(.system(size: 18, weight: .semibold))
                    
                    Text(selectedTradingMode == .paper ? "Copy as Paper Bot" : "Create Live Bot")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(canCopy 
                        ? (selectedTradingMode == .paper 
                            ? LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing))
                        : LinearGradient(colors: [Color.gray, Color.gray], startPoint: .leading, endPoint: .trailing))
            }
            .foregroundStyle(.white)
        }
        .disabled(!canCopy)
        .animation(.easeInOut(duration: 0.2), value: canCopy)
    }
    
    private func resetCopyState() {
        selectedTradingMode = .paper
        hasConfirmedLiveRisk = false
        copyError = nil
        copiedBotId = nil
    }
    
    private func copyBot() {
        isCopying = true
        copyError = nil
        
        Task {
            do {
                if selectedTradingMode == .paper {
                    // Create paper trading bot
                    let paperBot = try await copyTradingManager.copyBot(bot, customName: customName.isEmpty ? nil : customName)
                    await MainActor.run {
                        isCopying = false
                        copiedBotId = paperBot.id
                        showingCopySheet = false
                        showingCopySuccess = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } else {
                    // Live mode - requires 3Commas
                    guard liveBotManager.isConfigured else {
                        throw CopyTradingError.notAuthenticated
                    }
                    
                    // For now, create paper bot with a note that live integration is coming
                    // In full implementation, this would use SocialTo3CommasBridge
                    let paperBot = try await copyTradingManager.copyBot(bot, customName: customName.isEmpty ? nil : customName)
                    await MainActor.run {
                        isCopying = false
                        copiedBotId = paperBot.id
                        showingCopySheet = false
                        showingCopySuccess = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            } catch let error as CopyTradingError {
                await MainActor.run {
                    isCopying = false
                    
                    // If subscription required, show paywall instead of error
                    if error.shouldShowPaywall {
                        showingCopySheet = false
                        showingUpgradeSheet = true
                    } else {
                        copyError = error.localizedDescription
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            } catch {
                await MainActor.run {
                    isCopying = false
                    copyError = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
    
    private func toggleLike() {
        Task {
            if isLiked {
                try? await socialService.unlikeBot(bot.id)
            } else {
                try? await socialService.likeBot(bot.id)
            }
            isLiked.toggle()
        }
    }
    
    private func formatPercent(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.1f", value))%"
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let prefix = value >= 0 ? "+$" : "-$"
        return "\(prefix)\(String(format: "%.2f", abs(value)))"
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.96)
    }
}

#Preview {
    SharedBotDetailView(bot: SharedBotConfig(
        creatorId: UUID(),
        creatorUsername: "crypto_whale",
        botType: .dca,
        name: "BTC Weekly DCA",
        description: "Dollar cost averaging into Bitcoin weekly",
        config: ["interval": "weekly", "amount": "100"],
        tradingPair: "BTCUSDT",
        exchange: "Binance",
        performanceStats: BotPerformanceStats(
            totalPnL: 1234.56,
            pnlPercent: 23.5,
            totalTrades: 52,
            winRate: 0.65
        ),
        tags: ["btc", "dca", "longterm"],
        riskLevel: .low
    ))
}
