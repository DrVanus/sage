import SwiftUI
import SafariServices
import UIKit
import Foundation
import Combine
// Uses shared BrandColors

// MARK: - PremiumNewsSection (Home)
@MainActor
struct PremiumNewsSection: View {
    @ObservedObject var viewModel: CryptoNewsFeedViewModel
    @Binding var lastSeenArticleID: String?
    var onSeeAllTapped: () -> Void = {}
    var showCategoryChips: Bool = true

    // Use shared environment so Home can jump to AI tab
    // PERFORMANCE FIX v20: Removed @EnvironmentObject appState (18+ @Published)
    // Only used for dismissHomeSubviews and selectedTab - now via AppState.shared
    @EnvironmentObject private var chatVM: ChatViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var openAllNews: Bool = false
    @State private var processedArticleIDs = Set<String>()
    @State private var isExtractingArticle: Bool = false
    
    /// Computed refresh state - combines viewModel state with local loading indicator
    private var isRefreshing: Bool {
        viewModel.isRefreshingNews || viewModel.isLoading
    }
    
    /// Stable content key combining all visible article IDs for unified animation
    private var contentStabilityKey: String {
        let sorted = viewModel.filteredArticles
        let visibleIDs = sorted.prefix(3).map(\.id).joined(separator: "-")
        return visibleIDs.isEmpty ? "empty" : visibleIDs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header (matches Exchange Prices, Whale Activity, etc.)
            sectionHeader

            CardContainer {
                VStack(alignment: .leading, spacing: 8) {
                    // News content (hero no longer has integrated header)
                    newsContent
                    
                    // Bottom CTA button
                    seeAllNewsButton
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            }
            // No card-level gold bar - individual article rows already have gold accents
        }
        .navigationDestination(isPresented: $openAllNews) {
            AllCryptoNewsView()
                .environmentObject(viewModel)
                .navigationTitle("Crypto News")
                .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: viewModel.feedToken) { _, _ in processedArticleIDs.removeAll() }
        // Dismiss AllCryptoNewsView when home button is tapped (pop-to-root)
        // PERFORMANCE FIX v20: Use targeted onReceive
        .onReceive(AppState.shared.$dismissHomeSubviews) { shouldDismiss in
            if shouldDismiss && openAllNews {
                openAllNews = false
                // Reset the trigger after handling
                DispatchQueue.main.async {
                    AppState.shared.dismissHomeSubviews = false
                }
            }
        }
        .onAppear { 
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                // Only refresh if articles are empty or stale (>5 min old)
                let isStale = viewModel.articles.isEmpty || 
                    (viewModel.articles.first?.publishedAt ?? Date.distantPast).timeIntervalSinceNow < -300
                if isStale {
                    Task { await viewModel.loadLatestNews() }
                }
            }
        }
    }

    // MARK: - Section Header (matches other homepage sections)
    
    private var sectionHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            GoldHeaderGlyph(systemName: "newspaper.fill")
            
            Text("Crypto News")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
            
            // Subtle refresh indicator
            if isRefreshing {
                NewsRefreshIndicator()
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            
            Spacer()
        }
        .animation(.easeInOut(duration: 0.2), value: isRefreshing)
    }
    
    // MARK: Chips
    @State private var animatedChip: NewsCategory? = nil
    
    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NewsCategory.allCases, id: \.self) { cat in
                    CategoryChipSmall(
                        title: cat.rawValue,
                        selected: viewModel.selectedCategory == cat,
                        isAnimating: animatedChip == cat
                    ) {
                        DispatchQueue.main.async {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                animatedChip = cat
                                viewModel.selectedCategory = cat
                            }
                            // Reset animation trigger after bounce
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                animatedChip = nil
                            }
                        }
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 28) // Extra trailing padding for better scroll visibility
            .padding(.vertical, 2)
        }
        // Fade gradient at trailing edge to hint more content is scrollable
        .mask(
            HStack(spacing: 0) {
                Color.black
                LinearGradient(
                    colors: [.black, .black.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 32) // Wider fade for smoother transition
            }
        )
    }

    // MARK: - News Content (inside CardContainer)
    @ViewBuilder
    private var newsContent: some View {
        if viewModel.isLoading && viewModel.filteredArticles.isEmpty {
            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in ShimmerRow() }
            }
        } else if viewModel.filteredArticles.isEmpty {
            VStack(spacing: 10) {
                if viewModel.selectedCategory == .all {
                    Text("No news available right now.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Retry") { Task { await viewModel.loadLatestNews() } }
                        .buttonStyle(CSPrimaryCTAButtonStyle())
                } else {
                    Text("No \(viewModel.selectedCategory.rawValue) news found.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Try selecting \"All\" to see all articles.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else {
            let sorted = viewModel.filteredArticles
            ZStack {
                VStack(spacing: 0) {
                    if let first = sorted.first {
                        let candidate = upgradeToHTTPSLocal(viewModel.thumbnailURL(for: first))
                        let heroURL = PremiumNewsSection.isLikelyIconURL(candidate) ? nil : candidate
                        NewsSwipeRow(id: first.id, leading: [
                            .init(title: "Ask AI", systemName: "wand.and.stars", style: .gold) { askAI(for: first) }
                        ], trailing: [
                            .init(title: viewModel.isBookmarked(first) ? "Remove" : "Bookmark", systemName: viewModel.isBookmarked(first) ? "bookmark.slash" : "bookmark", style: .orange) { DispatchQueue.main.async { viewModel.toggleBookmark(first) } },
                            .init(title: "Copy", systemName: "doc.on.doc", style: .gray) { DispatchQueue.main.async { UIPasteboard.general.url = sanitizedArticleURL(viewModel.bestURL(for: first)) } }
                        ], enableSwipe: true) {
                            TopStoryHero(
                                article: first,
                                imageURL: heroURL,
                                articleURL: sanitizedArticleURL(viewModel.bestURL(for: first)),
                                isBookmarked: viewModel.isBookmarked(first)
                            ) {
                                markReadAndOpen(first)
                            } onAskAI: {
                                askAI(for: first)
                            } onToggleBookmark: {
                                viewModel.toggleBookmark(first)
                            }
                        }
                        .id(first.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .onAppear {
                            let id = first.id
                            // Defer state modifications to avoid "Modifying state during view update"
                            Task { @MainActor [weak viewModel] in
                                guard let viewModel = viewModel else { return }
                                if !processedArticleIDs.contains(id) {
                                    processedArticleIDs.insert(id)
                                    NewsDebug.log("Prefetching hero: id=\(first.id.prefix(12)) host=\(first.url.host ?? "?")")
                                    prefetchAround(article: first)
                                    viewModel.upgradeImageIfPossible(first)
                                }
                            }
                        }
                    }

                    let rest = Array(sorted.dropFirst().prefix(2))
                    ForEach(rest, id: \.id) { article in
                        Divider().background(DS.Adaptive.divider)
                        NewsSwipeRow(id: article.id, leading: [
                            .init(title: "Ask AI", systemName: "wand.and.stars", style: .gold) { askAI(for: article) }
                        ], trailing: [
                            .init(title: viewModel.isBookmarked(article) ? "Remove" : "Bookmark", systemName: viewModel.isBookmarked(article) ? "bookmark.slash" : "bookmark", style: .orange) { DispatchQueue.main.async { viewModel.toggleBookmark(article) } },
                            .init(title: "Copy", systemName: "doc.on.doc", style: .gray) { DispatchQueue.main.async { UIPasteboard.general.url = sanitizedArticleURL(viewModel.bestURL(for: article)) } }
                        ], enableSwipe: true) {
                            NewsRow(
                                title: article.title,
                                source: article.sourceName,
                                publishedAt: article.publishedAt,
                                url: article.url,
                                thumbnail: upgradeToHTTPSLocal(viewModel.thumbnailURL(for: article)),
                                unreadDot: false,  // Removed from home preview - badges handle freshness
                                isBookmarked: viewModel.isBookmarked(article)
                            ) {
                                markReadAndOpen(article)
                            }
                        }
                        .contextMenu {
                            Button { askAI(for: article) } label: { Label("Ask AI", systemImage: "wand.and.stars") }
                            Button { DispatchQueue.main.async { viewModel.toggleBookmark(article) } } label: {
                                Label(viewModel.isBookmarked(article) ? "Remove Bookmark" : "Bookmark", systemImage: viewModel.isBookmarked(article) ? "bookmark.slash" : "bookmark")
                            }
                            Button { DispatchQueue.main.async { UIPasteboard.general.url = sanitizedArticleURL(viewModel.bestURL(for: article)) } } label: { Label("Copy Link", systemImage: "doc.on.doc") }
                            Button {
                                DispatchQueue.main.async {
                                    let url = sanitizedArticleURL(viewModel.bestURL(for: article))
                                    OpenSafariHelper.open(url)
                                }
                            } label: { Label("Open in Safari", systemImage: "safari") }
                        }
                        .onAppear {
                            let id = article.id
                            // Defer state modifications to avoid "Modifying state during view update"
                            DispatchQueue.main.async {
                                if !processedArticleIDs.contains(id) {
                                    processedArticleIDs.insert(id)
                                    NewsDebug.log("Prefetching row: id=\(article.id.prefix(12)) host=\(article.url.host ?? "?")")
                                    prefetchAround(article: article)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .transition(.asymmetric(
                            insertion: .slide.combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                // Unified animation using content stability key for consistent hero + list updates
                .id(contentStabilityKey)
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                
                // Subtle shimmer overlay during refresh (only when we have content)
                if isRefreshing && !sorted.isEmpty {
                    NewsRefreshOverlay()
                        .allowsHitTesting(false)
                }
            }
            // Smooth unified animation for the entire news content
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: contentStabilityKey)
        }
    }
    
    // MARK: - See All News Button
    
    private var seeAllNewsButton: some View {
        SectionCTAButton(title: "See All News", icon: "newspaper.fill", compact: true) {
            viewModel.resetHomeNewCount()
            onSeeAllTapped()
            openAllNews = true
        }
        .padding(.top, 2)
    }

    // MARK: helpers

    private func prefetchAround(article: CryptoNewsArticle) {
        if let idx = viewModel.filteredArticles.firstIndex(where: { $0.id == article.id }) {
            viewModel.prefetchAround(index: idx, radius: 2)
        }
    }

    private func markReadAndOpen(_ article: CryptoNewsArticle) {
        DispatchQueue.main.async {
            if !viewModel.isRead(article) {
                viewModel.toggleRead(article)
            }
            // Open the article URL directly - avoid resolver which can cause 404s
            let target = sanitizedArticleURL(viewModel.bestURL(for: article))
            NewsDebug.log("Opening article: \(target.absoluteString)")
            OpenSafariHelper.open(target)
        }
    }

    private func askAI(for article: CryptoNewsArticle) {
        // Prevent multiple simultaneous extractions
        guard !isExtractingArticle else { return }
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isExtractingArticle = true
        
        let cleanURL = sanitizedArticleURL(viewModel.bestURL(for: article))
        
        Task {
            // Extract article content for AI analysis
            let content = await ArticleContentExtractor.shared.extract(from: cleanURL, article: article)
            
            await MainActor.run {
                chatVM.inputText = content.buildPrompt()
                AppState.shared.selectedTab = .ai
                isExtractingArticle = false
            }
        }
    }
}

// MARK: - Article Badge Type
/// Smart badge classification based on keywords and recency
private enum ArticleBadgeType {
    case breaking   // Red, pulsing - truly urgent news (< 15 min + urgent keywords)
    case latest     // Gold, subtle glow - fresh content (< 30 min)
    case topStory   // Gold, static - recent feature (30 min - 2 hours)
    case none       // No badge (older than 2 hours)
}

// MARK: - Hero Card
private struct TopStoryHero: View {
    let article: CryptoNewsArticle
    let imageURL: URL?
    let articleURL: URL
    let isBookmarked: Bool
    let onTap: () -> Void
    let onAskAI: () -> Void
    let onToggleBookmark: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    private let heroHeight: CGFloat = 180 // Compact height for homepage
    
    /// Whether we have a real article image (not just a favicon)
    private var hasRealImage: Bool {
        guard let url = imageURL else { return false }
        return !PremiumNewsSection.isLikelyIconURL(url)
    }
    
    /// Favicon URL for branded fallback
    private var faviconURL: URL? {
        upgradeToHTTPSLocal(PremiumNewsSection.publisherFaviconURL(for: article.url))
    }
    
    /// Badge type based on smart keyword detection and recency
    private var badgeType: ArticleBadgeType {
        let minutesAgo = Date().timeIntervalSince(article.publishedAt) / 60
        guard minutesAgo >= 0 else { return .none } // Future dates get no badge
        
        let title = article.title.lowercased()
        
        // Keywords that indicate truly breaking/urgent news
        let breakingKeywords = ["breaking", "just in", "alert", "urgent", "developing", "live:"]
        let crisisKeywords = ["hack", "exploit", "breach", "crash", "collapse", "plunge", "plummets", 
                              "tanks", "arrested", "charged", "bankrupt", "insolvent", "shutdown"]
        let surgeKeywords = ["surges", "soars", "spikes", "rallies", "skyrockets", "moons", "pumps"]
        
        let hasBreakingIndicator = breakingKeywords.contains { title.contains($0) }
        let hasCrisisIndicator = crisisKeywords.contains { title.contains($0) }
        let hasSurgeIndicator = surgeKeywords.contains { title.contains($0) }
        let hasUrgentKeyword = hasBreakingIndicator || hasCrisisIndicator || hasSurgeIndicator
        
        // BREAKING: Fresh (< 15 min) AND contains urgent keywords
        if minutesAgo < 15 && hasUrgentKeyword {
            return .breaking
        }
        
        // LATEST: Fresh content (< 30 min), no urgent keywords needed
        if minutesAgo < 30 {
            return .latest
        }
        
        // TOP STORY: Recent (30 min - 2 hours)
        if minutesAgo < 120 {
            return .topStory
        }
        
        return .none
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background layer - either real image or branded gradient
            if hasRealImage {
                // Real article image
                CachingAsyncImage(url: imageURL, referer: sanitizedArticleURL(article.url), maxPixel: 600)
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                // Branded gradient fallback with centered publisher icon - adaptive for light/dark
                ZStack {
                    // Premium gradient background - dark in dark mode, light warm in light mode
                    LinearGradient(
                        colors: isDark ? [
                            Color(red: 0.12, green: 0.12, blue: 0.14),
                            Color(red: 0.06, green: 0.06, blue: 0.08)
                        ] : [
                            Color(red: 0.25, green: 0.22, blue: 0.20),
                            Color(red: 0.18, green: 0.16, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    // Subtle gold accent gradient at top
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.83, blue: 0.40).opacity(isDark ? 0.10 : 0.15),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                    
                    // Publisher favicon in center
                    if let favicon = faviconURL {
                        CachingAsyncImage(url: favicon, referer: nil, maxPixel: 128)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(isDark ? 0.15 : 0.25), lineWidth: 1)
                            )
                            .offset(y: -24) // Slightly above center to leave room for text
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: heroHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            
            // Border stroke - adaptive for light/dark
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 1)
                .frame(maxWidth: .infinity)
                .frame(height: heroHeight)
            
            // Text readability gradient overlay - stronger gradient for text legibility
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.50),
                    Color.black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            
            // Top overlay: Article badge (top-right only)
            VStack {
                HStack(alignment: .top) {
                    Spacer()
                    
                    // Smart badge based on keywords and recency
                    if badgeType != .none {
                        ArticleBadge(type: badgeType)
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 12)
                
                Spacer()
            }
            .frame(height: heroHeight)

            // Content overlay (title + source)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    // Gold unread dot removed from home preview - badges handle freshness indication
                    Text(article.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                }
                HStack(spacing: 8) {
                    SourcePill(text: article.sourceName)
                    RelativeTimeText(date: article.publishedAt)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()
                }
            }
            .padding(14)
        }
        .contentShape(Rectangle())
        // Subtle shadow for visual prominence - adaptive for light/dark
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button { onAskAI() } label: { Label("Ask AI", systemImage: "wand.and.stars") }
            Button { DispatchQueue.main.async { onToggleBookmark() } } label: { Label(isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: isBookmarked ? "bookmark.slash" : "bookmark") }
            Button {
                DispatchQueue.main.async {
                    UIPasteboard.general.url = sanitizedArticleURL(articleURL)
                }
            } label: { Label("Copy Link", systemImage: "doc.on.doc") }
            Button {
                DispatchQueue.main.async {
                    OpenSafariHelper.open(sanitizedArticleURL(articleURL))
                }
            } label: { Label("Open in Safari", systemImage: "safari") }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }
    
}

// MARK: - Article Badge (Smart badge with multiple types)
private struct ArticleBadge: View {
    let type: ArticleBadgeType
    @State private var isPulsing = false
    @State private var glowIntensity: Double = 0.6
    
    private var isBreaking: Bool { type == .breaking }
    private var isLatest: Bool { type == .latest }
    
    private var labelText: String {
        switch type {
        case .breaking: return "BREAKING"
        case .latest: return "LATEST"
        case .topStory: return "TOP STORY"
        case .none: return ""
        }
    }
    
    private var dotColors: [Color] {
        switch type {
        case .breaking:
            return [Color.red, Color(red: 0.8, green: 0.1, blue: 0.1)]
        case .latest:
            return [BrandColors.goldLight, BrandColors.goldBase]
        case .topStory:
            return [BrandColors.goldLight.opacity(0.8), BrandColors.goldBase.opacity(0.8)]
        case .none:
            return [.clear, .clear]
        }
    }
    
    private var backgroundGradient: LinearGradient {
        switch type {
        case .breaking:
            return LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.15, blue: 0.15),
                    Color(red: 0.70, green: 0.10, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .latest:
            return LinearGradient(
                colors: [
                    BrandColors.goldLight,
                    BrandColors.goldBase
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .topStory, .none:
            return LinearGradient(
                colors: [
                    BrandColors.goldLight.opacity(0.85),
                    BrandColors.goldDark.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var borderGradient: LinearGradient {
        switch type {
        case .breaking:
            return LinearGradient(
                colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .latest:
            return LinearGradient(
                colors: [BrandColors.goldLight.opacity(0.7), BrandColors.goldBase.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .topStory, .none:
            return LinearGradient(
                colors: [BrandColors.goldLight.opacity(0.5), BrandColors.goldDark.opacity(0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var shadowColor: Color {
        switch type {
        case .breaking: return Color.red.opacity(glowIntensity)
        case .latest: return BrandColors.goldBase.opacity(0.5)
        case .topStory: return BrandColors.goldBase.opacity(0.3)
        case .none: return .clear
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Animated indicator dot
            ZStack {
                // Outer glow ring (only for breaking)
                if isBreaking {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 12, height: 12)
                        .scaleEffect(isPulsing ? 1.5 : 1.0)
                        .opacity(isPulsing ? 0 : 0.6)
                }
                
                // Subtle glow for latest
                if isLatest {
                    Circle()
                        .fill(BrandColors.goldBase.opacity(0.25))
                        .frame(width: 10, height: 10)
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .opacity(isPulsing ? 0.3 : 0.5)
                }
                
                // Core dot
                Circle()
                    .fill(
                        RadialGradient(
                            colors: dotColors,
                            center: .center,
                            startRadius: 0,
                            endRadius: 4
                        )
                    )
                    .frame(width: 6, height: 6)
            }
            
            // Badge text
            Text(labelText)
                .font(.system(size: 9, weight: .heavy, design: .default))
                .tracking(1.2)
                .foregroundStyle(.white)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(
            ZStack {
                // Base fill
                Capsule()
                    .fill(backgroundGradient)
                
                // Inner highlight
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.25), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                
                // Border
                Capsule()
                    .stroke(borderGradient, lineWidth: 0.8)
            }
        )
        .onAppear {
            // MEMORY FIX v9: Block during startup animation suppression window
            guard !shouldSuppressStartupAnimations() else {
                // News badge animations are decorative — no retry needed during startup
                return
            }
            // PERFORMANCE FIX: Delay animation start during scroll
            let startAnimations = {
                guard !globalAnimationsKilled else { return }
                if isBreaking {
                    // Pulse animation for the dot (breaking only)
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                        isPulsing = true
                    }
                    // Glow animation for the badge
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        glowIntensity = 0.9
                    }
                } else if isLatest {
                    // Subtle pulse for latest (less intense)
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            }
            
            if ScrollStateManager.shared.shouldBlockHeavyOperation() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startAnimations()
                }
            } else {
                startAnimations()
            }
        }
        .onReceive(ScrollStateManager.shared.$isScrolling.removeDuplicates()) { scrolling in
            if scrolling {
                // Pause animations during scroll
                if isBreaking {
                    isPulsing = false
                    glowIntensity = 0.6
                } else if isLatest {
                    isPulsing = false
                }
            } else {
                // Restart animations after scroll ends
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard !globalAnimationsKilled else { return }
                    guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                    if isBreaking {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                            isPulsing = true
                        }
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            glowIntensity = 0.9
                        }
                    } else if isLatest {
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
                }
            }
        }
    }
}

// Legacy wrapper for compatibility (if needed elsewhere)
private struct BreakingBadge: View {
    let isBreaking: Bool
    var body: some View {
        ArticleBadge(type: isBreaking ? .breaking : .topStory)
    }
}

private struct UnreadDot: View {
    var body: some View { Circle().fill(Color.yellow).frame(width: 6, height: 6) }
}

// Shared subtle pressed feedback - internal so other views can use it
struct CSPressableScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Small Category Chip
private struct CategoryChipSmall: View {
    let title: String
    let selected: Bool
    var isAnimating: Bool = false
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        Button { onTap() } label: {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(selected ? TintedChipStyle.selectedText(isDark: isDark) : DS.Adaptive.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 34)
                .tintedCapsuleChip(isSelected: selected, isDark: isDark)
                .scaleEffect(isAnimating ? 1.08 : 1.0)
                .contentShape(Capsule())
        }
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Filters the news feed")
        .buttonStyle(CSPressableScaleStyle())
        .hoverEffect(.lift)
    }
}

// MARK: - News Row (uses UnifiedNewsRow for consistency)
private struct NewsRow: View {
    let title: String
    let source: String
    let publishedAt: Date
    let url: URL
    let thumbnail: URL?
    let unreadDot: Bool
    let isBookmarked: Bool
    let onTap: () -> Void

    var body: some View {
        // Create a temporary article for UnifiedNewsRow
        let article = CryptoNewsArticle(
            title: title,
            description: nil,
            url: url,
            urlToImage: thumbnail,
            sourceName: source,
            publishedAt: publishedAt
        )
        
        UnifiedNewsRow(
            article: article,
            thumbnailURL: thumbnail,
            showUnreadDot: unreadDot,
            isBookmarked: isBookmarked,
            onTap: onTap
        )
    }
}

// MARK: - Shared UI bits
private struct GlassCard<Content: View>: View {
    let content: () -> Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
            content()
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ShimmerRow: View {
    @State private var phase: CGFloat = -1
    
    // Adaptive shimmer placeholder color
    private var placeholderColor: Color {
        DS.Adaptive.chipBackground
    }
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(placeholderColor)
                .frame(width: 120, height: 72)
                .redactedShimmer(phase: phase)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(placeholderColor).frame(height: 14).redactedShimmer(phase: phase)
                RoundedRectangle(cornerRadius: 4).fill(placeholderColor).frame(height: 14).redactedShimmer(phase: phase)
                HStack {
                    RoundedRectangle(cornerRadius: 6).fill(placeholderColor).frame(width: 80, height: 12).redactedShimmer(phase: phase)
                    RoundedRectangle(cornerRadius: 6).fill(placeholderColor).frame(width: 60, height: 12).redactedShimmer(phase: phase)
                    Spacer()
                }
            }
        }
        .onAppear {
            // MEMORY FIX v9: Block during startup animation suppression window
            // MEMORY FIX v10: NO retry — shimmer starts when user scrolls
            guard !shouldSuppressStartupAnimations() else { return }
            guard !globalAnimationsKilled else { return }
            // PERFORMANCE FIX: Delay animation start during scroll
            DispatchQueue.main.async {
                guard !globalAnimationsKilled else { return }
                if ScrollStateManager.shared.shouldBlockHeavyOperation() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard !globalAnimationsKilled else { return }
                        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 2 }
                    }
                } else {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 2 }
                }
            }
        }
        .onReceive(ScrollStateManager.shared.$isScrolling.removeDuplicates()) { scrolling in
            if scrolling {
                phase = -1
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard !globalAnimationsKilled else { return }
                    guard !shouldSuppressStartupAnimations() else { return }
                    guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 2 }
                }
            }
        }
    }
}

private extension View {
    func redactedShimmer(phase: CGFloat) -> some View {
        self.overlay(
            LinearGradient(colors: [Color.clear, DS.Adaptive.gradientHighlight, Color.clear], startPoint: .leading, endPoint: .trailing)
                .frame(maxWidth: .infinity)
                .offset(x: phase * 120)
        )
        .clipShape(Rectangle())
    }
}

// Local openSafari helper
private enum OpenSafariHelper {
    @MainActor static func open(_ url: URL) {
        let cleaned = sanitizedArticleURL(url)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let vc = SFSafariViewController(url: cleaned)
        vc.modalPresentationStyle = .fullScreen
        root.present(vc, animated: true)
    }
}

// Local HTTPS upgrader fallback
private func upgradeToHTTPSLocal(_ url: URL?) -> URL? {
    guard let url else { return nil }
    var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    if comps?.scheme?.lowercased() == "http" { comps?.scheme = "https" }
    return comps?.url ?? url
}

// Shared sanitizer (file-level) so nested views can use it
private func sanitizedArticleURL(_ url: URL) -> URL {
    return ArticleLink.sanitizeAndUnwrap(url)
}

extension PremiumNewsSection {
    // Use shared utilities for icon detection and favicon URLs
    static func publisherFaviconURL(for url: URL) -> URL? {
        return NewsImageUtilities.googleFavicon(for: url, size: 256)
    }
    static func isLikelyIconURL(_ url: URL?) -> Bool {
        return NewsImageUtilities.isLikelyIconURL(url)
    }
}

// MARK: - Premium Swipe Row
// MARK: - Shared Swipe Action Components
enum NewsActionStyle { case gold, blue, gray, orange }

struct NewsSwipeActionDescriptor: Identifiable {
    let id = UUID()
    let title: String
    let systemName: String
    let style: NewsActionStyle
    let action: () -> Void
    init(title: String, systemName: String, style: NewsActionStyle, action: @escaping () -> Void) {
        self.title = title; self.systemName = systemName; self.style = style; self.action = action
    }
}

struct NewsActionButton: View {
    let data: NewsSwipeActionDescriptor
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    private let buttonSize: CGFloat = 36
    
    var body: some View {
        Button {
            DispatchQueue.main.async {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                data.action()
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    // Subtle background circle
                    Circle()
                        .fill(fillColor.opacity(isDark ? 0.2 : 0.15))
                        .frame(width: buttonSize, height: buttonSize)
                    
                    // Border
                    Circle()
                        .stroke(fillColor.opacity(isDark ? 0.5 : 0.4), lineWidth: 1.2)
                        .frame(width: buttonSize, height: buttonSize)
                    
                    // Icon
                    Image(systemName: data.systemName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(fillColor)
                }
                .frame(width: buttonSize, height: buttonSize)
                
                Text(data.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isDark ? DS.Adaptive.textSecondary : DS.Adaptive.textTertiary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CSPressableScaleStyle(scale: 0.92))
        .accessibilityLabel(Text(data.title))
        .accessibilityAddTraits(.isButton)
    }
    
    private var fillColor: Color {
        switch data.style {
        case .gold: return BrandColors.goldBase
        case .blue: return .blue
        case .gray: return isDark ? Color(white: 0.6) : Color(white: 0.4)
        case .orange: return .orange
        }
    }
}

struct NewsSwipeRow<Content: View>: View {
    let id: String
    let leading: [NewsSwipeActionDescriptor]
    let trailing: [NewsSwipeActionDescriptor]
    let enableSwipe: Bool
    let content: () -> Content

    init(id: String, leading: [NewsSwipeActionDescriptor], trailing: [NewsSwipeActionDescriptor], enableSwipe: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.leading = leading
        self.trailing = trailing
        self.enableSwipe = enableSwipe
        self.content = content
    }

    @State private var offset: CGFloat = 0
    @GestureState private var dragX: CGFloat = 0
    @State private var didAnnounceDrag: Bool = false

    private let buttonSize: CGFloat = 48  // Compact button with label
    private let spacing: CGFloat = 8
    private let sidePad: CGFloat = 10
    private let activationThreshold: CGFloat = 8
    /// Minimum horizontal distance required before swipe gesture activates.
    private let swipeMinDistance: CGFloat = 18

    private var leadingWidth: CGFloat { max(0, CGFloat(leading.count) * (buttonSize + spacing) - spacing + sidePad) }
    private var trailingWidth: CGFloat { max(0, CGFloat(trailing.count) * (buttonSize + spacing) - spacing + sidePad) }

    private var currentOffset: CGFloat { offset + dragX }
    private var revealProgress: CGFloat {
        let width = currentOffset >= 0 ? leadingWidth : trailingWidth
        guard width > 0 else { return 0 }
        let absX = abs(currentOffset)
        if absX <= activationThreshold { return 0 }
        let denom = max(1, width - activationThreshold)
        let p = min(1, (absX - activationThreshold) / denom)
        return p
    }
    private var leadingProgress: CGFloat { currentOffset > 0 ? revealProgress : 0 }
    private var trailingProgress: CGFloat { currentOffset < 0 ? revealProgress : 0 }

    var body: some View {
        Group {
            if enableSwipe {
                ZStack {
                    // Leading actions only
                    HStack {
                        HStack(spacing: spacing) {
                            ForEach(leading) { item in NewsActionButton(data: item) }
                        }
                        .padding(.leading, sidePad)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .opacity(leadingProgress)
                    .allowsHitTesting(leadingProgress > 0)
                    .animation(.easeOut(duration: 0.15), value: leadingProgress)

                    // Trailing actions only
                    HStack {
                        Spacer(minLength: 0)
                        HStack(spacing: spacing) {
                            ForEach(trailing.reversed()) { item in NewsActionButton(data: item) }
                        }
                        .padding(.trailing, sidePad)
                    }
                    .padding(.vertical, 4)
                    .opacity(trailingProgress)
                    .allowsHitTesting(trailingProgress > 0)
                    .animation(.easeOut(duration: 0.15), value: trailingProgress)

                    // Foreground content
                    content()
                        .contentShape(Rectangle())
                        .offset(x: offset + dragX)
                        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.86), value: offset)
                        .gesture(drag)
                        .onDisappear {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) { offset = 0 }
                        }
                }
                .clipped()
                .onReceive(NotificationCenter.default.publisher(for: .premiumSwipeRowCloseAll)) { note in
                    if let other = note.object as? String, other != id {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { offset = 0 }
                    }
                }
            } else {
                // Swipe disabled: present content normally so vertical scrolling is never blocked.
                content()
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: swipeMinDistance)
            .updating($dragX) { value, state, _ in
                let t = value.translation
                
                // Early direction lock: decide once whether this is a horizontal drag.
                // Use initial movement direction (first ~20pt) to lock axis.
                // Once locked as vertical, reject until the gesture ends.
                if abs(t.width) < 20 && abs(t.height) < 20 {
                    // Still in ambiguous zone - don't commit yet, but don't show anything
                    state = 0
                    return
                }
                
                // Lock direction: require 1.5x horizontal over vertical for horizontal lock
                let isHorizontal = abs(t.width) > abs(t.height) * 1.5
                if !isHorizontal {
                    // Vertical or diagonal - let scroll view handle it
                    state = 0
                    return
                }
                
                let proposed = t.width
                if abs(proposed) > activationThreshold && !didAnnounceDrag {
                    didAnnounceDrag = true
                    NotificationCenter.default.post(name: .premiumSwipeRowCloseAll, object: id)
                }
                
                // Clamp with rubber-band effect past the button width for natural feel
                let maxWidth = proposed > 0 ? leadingWidth : trailingWidth
                let clamped: CGFloat
                if abs(proposed) <= maxWidth {
                    clamped = proposed
                } else {
                    // Rubber band: diminishing returns past the max
                    let excess = abs(proposed) - maxWidth
                    let rubberBand = maxWidth + excess * 0.2
                    clamped = proposed > 0 ? rubberBand : -rubberBand
                }
                state = clamped
            }
            .onEnded { value in
                didAnnounceDrag = false
                let t = value.translation
                
                // If the gesture was mostly vertical, snap back
                guard abs(t.width) > abs(t.height) * 1.2 else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offset = 0 }
                    return
                }
                
                let total = offset + t.width
                let velocity = value.predictedEndTranslation.width - t.width
                let target: CGFloat
                
                if total > 0 {
                    // Factor in velocity: if swiping fast, lower the threshold
                    let threshold = velocity > 100 ? leadingWidth * 0.25 : leadingWidth * 0.4
                    target = (total > threshold) ? leadingWidth : 0
                } else {
                    let threshold = velocity < -100 ? trailingWidth * 0.25 : trailingWidth * 0.4
                    target = (abs(total) > threshold) ? -trailingWidth : 0
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { offset = target }
            }
    }
}

fileprivate extension Notification.Name {
    static let premiumSwipeRowCloseAll = Notification.Name("PremiumSwipeRowCloseAll")
}

// MARK: - News Refresh Indicator (Header)
/// Subtle animated indicator shown in section header during refresh
private struct NewsRefreshIndicator: View {
    @State private var isAnimating = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 4) {
            // Animated dots
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(BrandColors.goldBase.opacity(0.8))
                    .frame(width: 4, height: 4)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .opacity(isAnimating ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(colorScheme == .dark 
                    ? Color.white.opacity(0.08) 
                    : Color.black.opacity(0.05))
        )
        .onAppear {
            guard !shouldSuppressStartupAnimations() else { return }
            guard !globalAnimationsKilled else { return }
            isAnimating = true
        }
        .onReceive(ScrollStateManager.shared.$isScrolling.removeDuplicates()) { scrolling in
            if scrolling {
                isAnimating = false
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard !globalAnimationsKilled else { return }
                    guard !shouldSuppressStartupAnimations() else { return }
                    guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                    isAnimating = true
                }
            }
        }
    }
}

// MARK: - News Refresh Overlay
/// Subtle shimmer overlay shown over content during refresh
private struct NewsRefreshOverlay: View {
    @State private var shimmerOffset: CGFloat = -1.0
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            (colorScheme == .dark ? Color.white : Color.black).opacity(0.03),
                            (colorScheme == .dark ? Color.white : Color.black).opacity(0.06),
                            (colorScheme == .dark ? Color.white : Color.black).opacity(0.03),
                            Color.clear
                        ],
                        startPoint: UnitPoint(x: shimmerOffset, y: 0),
                        endPoint: UnitPoint(x: shimmerOffset + 0.4, y: 0)
                    )
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear {
                    guard !shouldSuppressStartupAnimations() else { return }
                    guard !globalAnimationsKilled else { return }
                    let startAnimation = {
                        guard !globalAnimationsKilled else { return }
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            shimmerOffset = 1.5
                        }
                    }
                    if ScrollStateManager.shared.shouldBlockHeavyOperation() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            startAnimation()
                        }
                    } else {
                        startAnimation()
                    }
                }
                .onReceive(ScrollStateManager.shared.$isScrolling.removeDuplicates()) { scrolling in
                    if scrolling {
                        shimmerOffset = -1.0
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            guard !globalAnimationsKilled else { return }
                            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                shimmerOffset = 1.5
                            }
                        }
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#if DEBUG
#Preview {
    PremiumNewsSection(viewModel: CryptoNewsFeedViewModel.shared, lastSeenArticleID: .constant(nil))
        .environmentObject(AppState())
        .environmentObject(ChatViewModel())
        .background(Color.black)
}
#endif

