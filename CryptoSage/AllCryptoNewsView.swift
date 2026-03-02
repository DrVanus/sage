import SwiftUI
import UIKit
import SafariServices
import Foundation


// Consistent URL sanitizer for See All page
private func sanitizedArticleURL(_ url: URL) -> URL {
    return ArticleLink.sanitizeAndUnwrap(url)
}

// MARK: - Shared Pressable Style (uses shared definition from PremiumNewsSection)
// CSPressableScaleStyle is defined in PremiumNewsSection.swift

struct AllCryptoNewsView: View {
    @EnvironmentObject var vm: CryptoNewsFeedViewModel
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("CryptoNews.ShowSearchBar") private var showSearchBar: Bool = false
    @State private var showingFilters: Bool = false
    @State private var lastPagingTriggerCount: Int = 0
    @State private var lastRefreshDate: Date? = nil
    @State private var showNewArticlesToast: Bool = false
    @State private var newArticlesCount: Int = 0
    @State private var previousArticleCount: Int = 0
    @State private var isExtractingArticle: Bool = false
    @State private var isSearchFocused: Bool = false  // Tracks ChatTextField focus state

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.filteredArticles.isEmpty && vm.articles.isEmpty {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.errorMessage, vm.filteredArticles.isEmpty, vm.articles.isEmpty {
            VStack(spacing: 16) {
                Text(error)
                    // DARK MODE FIX: Use adaptive error color (red works well in both modes)
                    .foregroundColor(Color.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    vm.loadAllNews()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if vm.filteredArticles.isEmpty && !vm.articles.isEmpty {
            // Category filter returned no results, but we have articles
            List {
                Section {
                    ScrollableChips(items: NewsCategory.allCases.map { ($0.rawValue, $0) }, selection: $vm.selectedCategory)
                }
                .listRowBackground(Color.clear)
                
                Section {
                    EmptyCategoryState(
                        category: vm.selectedCategory.rawValue,
                        onSelectAll: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                vm.selectedCategory = .all
                            }
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        },
                        suggestedCategories: suggestedCategories(for: vm.selectedCategory),
                        onSelectCategory: { category in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                vm.selectedCategory = category
                            }
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                    )
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)  // Dismiss keyboard on scroll
        } else {
            List {
                Section {
                    ScrollableChips(items: NewsCategory.allCases.map { ($0.rawValue, $0) }, selection: $vm.selectedCategory)
                }
                .listRowBackground(Color.clear)

                // Optional non-blocking banner only for retryable errors (e.g., transient network)
                if let error = vm.errorMessage, vm.isRetryableError {
                    Section {
                        CryptoNewsErrorView(message: error) {
                            vm.loadAllNews()
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                ForEach(vm.filteredArticles) { article in
                    let thumbURL = vm.thumbnailURL(for: article)
                    NewsSwipeRow(
                        id: article.id,
                        leading: [
                            .init(title: "Ask AI", systemName: "wand.and.stars", style: .gold) { askAI(for: article) }
                        ],
                        trailing: [
                            .init(title: vm.isBookmarked(article) ? "Remove" : "Bookmark", systemName: vm.isBookmarked(article) ? "bookmark.slash" : "bookmark", style: .orange) { DispatchQueue.main.async { vm.toggleBookmark(article) } },
                            .init(title: "Copy", systemName: "doc.on.doc", style: .gray) { DispatchQueue.main.async { UIPasteboard.general.url = vm.bestURL(for: article) } }
                        ],
                        enableSwipe: true
                    ) {
                        NavigationLink(destination: ArticleReaderView(url: vm.bestURL(for: article))) {
                            ZStack(alignment: .topLeading) {
                                UnifiedNewsRow(
                                    article: article,
                                    thumbnailURL: thumbURL,
                                    showUnreadDot: !vm.isRead(article),
                                    isBookmarked: vm.isBookmarked(article)
                                )
                                
                                // Debug badge overlay (only in debug mode)
                                if NewsDebug.enabled {
                                    DebugThumbBadge(url: thumbURL, article: article, isOverride: vm.hasThumbnailOverride(for: article))
                                        .padding(.leading, 4)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .id(article.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
                    .contextMenu {
                        Button { askAI(for: article) } label: { Label("Ask AI", systemImage: "wand.and.stars") }
                        Button { vm.toggleBookmark(article) } label: {
                            Label(vm.isBookmarked(article) ? "Remove Bookmark" : "Bookmark", systemImage: vm.isBookmarked(article) ? "bookmark.slash" : "bookmark")
                        }
                        Button { UIPasteboard.general.url = vm.bestURL(for: article) } label: { Label("Copy Link", systemImage: "doc.on.doc") }
                        Button { UIApplication.shared.open(vm.bestURL(for: article)) } label: { Label("Open in Safari", systemImage: "safari") }
                    }
                    .onAppear {
                        // Defer state modifications to avoid "Modifying state during view update"
                        let articleId = article.id
                        let filteredCount = vm.filteredArticles.count
                        Task { @MainActor [weak vm] in
                            guard let vm = vm else { return }
                            // Upgrade thumbnail if possible
                            vm.upgradeImageIfPossible(article)
                            // Prefetch thumbnails around the current row
                            guard let idx = vm.filteredArticles.firstIndex(where: { $0.id == articleId }) else { return }
                            vm.prefetchAround(index: idx)
                            // Trigger paging when we reach the last 5 rows, but only once per article-count snapshot
                            let triggerIndex = max(0, filteredCount - 5)
                            if idx >= triggerIndex && vm.hasMore && !vm.isLoadingPage {
                                if lastPagingTriggerCount != filteredCount {
                                    lastPagingTriggerCount = filteredCount
                                    vm.loadMoreNews()
                                }
                            }
                        }
                    }
                }
                if vm.hasMore {
                    LoadMoreRow(isLoading: vm.isLoadingPage) { vm.loadMoreNews() }
                        .frame(height: 44)
                        .id("loadmore-\(vm.filteredArticles.count)")
                        .listRowBackground(Color.clear)
                }
                // Sentinel to ensure paging triggers even if LoadMoreRow is not visible yet
                Color.clear
                    .frame(height: 1)
                    .listRowBackground(Color.clear)
                    .onAppear {
                        // Defer to avoid "Modifying state during view update"
                        DispatchQueue.main.async {
                            if vm.hasMore && !vm.isLoadingPage {
                                if lastPagingTriggerCount != vm.filteredArticles.count {
                                    lastPagingTriggerCount = vm.filteredArticles.count
                                    vm.loadMoreNews()
                                }
                            }
                        }
                    }
            }
            .refreshable {
                vm.forceFreshReload()
            }
            .listStyle(PlainListStyle())
            .scrollDismissesKeyboard(.interactively)  // Dismiss keyboard on scroll
            // Smooth spring animation for article transitions (matches homepage)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.filteredArticles.count)
        }
    }

    // MARK: - Search Bar
    @ViewBuilder
    private var searchBar: some View {
        if showSearchBar {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.Adaptive.textSecondary)
                
                // UIKit-backed text field for reliable keyboard focus
                SearchTextField(
                    text: $vm.searchText,
                    placeholder: "Search news...",
                    autoFocus: true, // Automatically focus when search bar appears
                    onTextChange: { _ in
                        // News search is API-based, so we don't filter on every keystroke
                        // User must press search button to perform search
                    },
                    onSubmit: {
                        vm.performSearch()
                        isSearchFocused = false
                    },
                    onEditingChanged: { focused in
                        isSearchFocused = focused
                    }
                )
                .frame(height: 36)
                
                if !vm.searchText.isEmpty {
                    Button {
                        vm.searchText = ""
                        vm.performSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                    .buttonStyle(CSPressableScaleStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(DS.Adaptive.chipBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSearchFocused ? DS.Adaptive.gold.opacity(0.5) : DS.Adaptive.stroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Unified header with SubpageHeaderBar
            SubpageHeaderBar(
                title: "Crypto News",
                subtitle: lastRefreshDate.map { "Updated \(Self.lastUpdateFormatter.string(from: $0))" },
                onDismiss: { dismiss() }
            ) {
                // Right-side action buttons
                HStack(spacing: 12) {
                    Button {
                        showingFilters = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                    .accessibilityLabel("Filter news")
                    .accessibilityHint("Open news source and category filters")

                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            showSearchBar.toggle()
                            if !showSearchBar {
                                isSearchFocused = false
                                if !vm.searchText.isEmpty {
                                    vm.searchText = ""
                                    vm.performSearch()
                                }
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isSearchFocused = true
                                }
                            }
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: showSearchBar ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(showSearchBar ? DS.Adaptive.gold : DS.Adaptive.textSecondary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Search news")
                    .accessibilityValue(showSearchBar ? "Search bar visible" : "Search bar hidden")
                    .accessibilityHint("Toggle the search bar")

                    NavigationLink(destination: BookmarksView().environmentObject(vm)) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                    .accessibilityLabel("Bookmarked articles")
                    .accessibilityHint("View your saved articles")
                }
            }
            
            content
                .withBannerAd() // Show ads for free tier users
                .safeAreaInset(edge: .top, spacing: 0) {
                    searchBar
                        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showSearchBar)
                }
                .overlay(alignment: .top) {
                    // New articles toast notification - positioned at very top
                    if showNewArticlesToast {
                        NewArticlesToast(count: newArticlesCount)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, showSearchBar ? 60 : 8)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showNewArticlesToast = false
                                }
                            }
                            .zIndex(100)
                    }
                }
        }
        .background(DS.Adaptive.background)
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                previousArticleCount = vm.filteredArticles.count
                if !vm.isLoading && vm.filteredArticles.isEmpty {
                    vm.loadAllNews()
                }
                else if let newest = vm.articles.map({ $0.publishedAt }).max(), Date().timeIntervalSince(newest) > 2 * 3600 {
                    vm.forceFreshReload()
                }
            }
        }
        .onDisappear {
            // Reset search bar state when leaving to prevent it staying open
            if showSearchBar {
                showSearchBar = false
                isSearchFocused = false
                if !vm.searchText.isEmpty {
                    vm.searchText = ""
                }
            }
        }
        .task { @MainActor in
            // Prefetch the first screenful once content is present
            if !vm.filteredArticles.isEmpty {
                vm.prefetchTop(count: 20)
            }
        }
        .navigationTitle("Crypto News")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .sheet(isPresented: $showingFilters) {
            FiltersSheet()
                .environmentObject(vm)
                .presentationDetents([.medium, .large])
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if let newest = vm.articles.map({ $0.publishedAt }).max(), Date().timeIntervalSince(newest) > 2 * 3600 {
                    vm.forceFreshReload()
                } else {
                    Task { await vm.loadLatestNews() }
                }
            }
        }
        .onChange(of: vm.filteredArticles.count) { _, newCount in
            // Track article count changes for toast notification
            // Only show toast for genuine new articles (small increments, not initial load)
            let diff = newCount - previousArticleCount
            let isGenuineNewArticles = diff > 0 && diff <= 10 && previousArticleCount >= 5
            
            if isGenuineNewArticles {
                // New articles arrived during refresh
                newArticlesCount = diff
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showNewArticlesToast = true
                }
                // Auto-dismiss after 3.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showNewArticlesToast = false
                    }
                }
            }
            previousArticleCount = newCount
        }
        .onChange(of: vm.isLoading) { _, isLoading in
            // Update last refresh timestamp when loading completes
            if !isLoading && !vm.filteredArticles.isEmpty {
                lastRefreshDate = Date()
            }
        }
        .accentColor(.white)
    }
    
    // Date formatter for last update time
    private static let lastUpdateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    private func askAI(for article: CryptoNewsArticle) {
        // Prevent multiple simultaneous extractions
        guard !isExtractingArticle else { return }
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        isExtractingArticle = true
        
        let cleanURL = sanitizedArticleURL(vm.bestURL(for: article))
        
        Task {
            // Extract article content for AI analysis
            let content = await ArticleContentExtractor.shared.extract(from: cleanURL, article: article)
            
            await MainActor.run {
                chatVM.inputText = content.buildPrompt()
                appState.selectedTab = .ai
                isExtractingArticle = false
            }
        }
    }
    
    /// Suggests related categories based on the current empty category
    private func suggestedCategories(for category: NewsCategory) -> [NewsCategory] {
        switch category {
        case .all:
            return []
        case .bitcoin:
            return [.macro, .layer2, .all]
        case .ethereum:
            return [.defi, .nfts, .layer2]
        case .solana:
            return [.defi, .nfts, .altcoins]
        case .defi:
            return [.ethereum, .solana, .layer2]
        case .nfts:
            return [.ethereum, .solana, .all]
        case .macro:
            return [.bitcoin, .ethereum, .all]
        case .layer2:
            return [.ethereum, .defi, .all]
        case .altcoins:
            return [.solana, .defi, .all]
        }
    }
}

struct AllCryptoNewsView_Previews: PreviewProvider {
    static var previews: some View {
        AllCryptoNewsView()
            .environmentObject(CryptoNewsFeedViewModel.shared)
    }
}

struct FiltersSheet: View {
    @EnvironmentObject var vm: CryptoNewsFeedViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var categories: [NewsCategory] { NewsCategory.allCases }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Categories").font(.headline)
                    WrapChips(items: categories.map { ($0.rawValue, $0) }, selection: $vm.selectedCategory)

                    Toggle(isOn: $vm.withImagesOnly) {
                        Label("With images only", systemImage: "photo")
                    }
                    .toggleStyle(SwitchToggleStyle(tint: DS.Adaptive.gold))

                    Text("Sources").font(.headline)
                    HStack(spacing: 8) {
                        Button("Clear") { vm.selectedSources.removeAll() }
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .tintedRoundedChip(isSelected: false, isDark: colorScheme == .dark, cornerRadius: 10)
                        Button("Select All") { vm.selectedSources = Set(vm.knownSources) }
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .tintedRoundedChip(isSelected: false, isDark: colorScheme == .dark, cornerRadius: 10)
                        Spacer()
                        if !vm.selectedSources.isEmpty {
                            Text("\(vm.selectedSources.count) selected")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.knownSources, id: \.self) { src in
                            Button(action: {
                                if vm.selectedSources.contains(src) { vm.selectedSources.remove(src) }
                                else { vm.selectedSources.insert(src) }
                            }) {
                                HStack {
                                    Image(systemName: vm.selectedSources.contains(src) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(DS.Adaptive.gold)
                                    Text(src)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(8)
                                .background(DS.Adaptive.chipBackground)
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text("Close")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        vm.hasMore = true
                        vm.loadAllNews()
                        dismiss()
                    } label: {
                        Text("Apply")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
            }
        }
    }
}

// Single-row horizontally scrollable chips (matches homepage style)
struct ScrollableChips<T: Hashable>: View {
    let items: [(String, T)]
    @Binding var selection: T
    @State private var animatedSelection: T?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.1) { item in
                    let (title, value) = item
                    let isSelected = selection == value
                    Button(action: {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            animatedSelection = value
                            selection = value
                        }
                        // Reset animation trigger after bounce
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            animatedSelection = nil
                        }
                    }) {
                        Text(title)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(isSelected ? TintedChipStyle.selectedText(isDark: isDark) : DS.Adaptive.textPrimary)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 34)
                            .tintedCapsuleChip(isSelected: isSelected, isDark: isDark)
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                            .scaleEffect(animatedSelection == value ? 1.08 : 1.0)
                    }
                    .buttonStyle(CSPressableScaleStyle())
                    .hoverEffect(.lift)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 24) // Extra trailing padding for better scroll visibility
            .padding(.vertical, 2)
        }
    }
}

// WrapChips implementation using FlowLayout (used in FiltersSheet where wrapping is appropriate)
struct WrapChips<T: Hashable>: View {
    let items: [(String, T)]
    @Binding var selection: T

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.1) { item in
                WrapChipButton(title: item.0, value: item.1, selection: $selection)
            }
        }
        .padding(.vertical, 4)
    }
}

// Extracted chip button to help compiler type-check
private struct WrapChipButton<T: Hashable>: View {
    let title: String
    let value: T
    @Binding var selection: T
    @Environment(\.colorScheme) private var colorScheme
    
    private var isSelected: Bool { selection == value }
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            selection = value
        } label: {
            chipLabel
        }
        .buttonStyle(CSPressableScaleStyle())
        .hoverEffect(.lift)
    }
    
    private var chipLabel: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(isSelected ? TintedChipStyle.selectedText(isDark: isDark) : DS.Adaptive.textPrimary)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .tintedCapsuleChip(isSelected: isSelected, isDark: isDark)
            .clipShape(Capsule())
            .contentShape(Capsule())
    }
}

// FlowLayout is defined in MarketFilterSheet.swift - reused here

struct LoadMoreRow: View {
    let isLoading: Bool
    let onTrigger: () -> Void
    var body: some View {
        HStack {
            Spacer()
            if isLoading {
                ProgressView().tint(.white)
            } else {
                Button("Load more") { onTrigger() }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if !isLoading { onTrigger() }
            }
        }
    }
}

struct ArticleReaderView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .top) {
            NewsWebView(url: url)
                .ignoresSafeArea()

            // Top overlay controls (Back + Open in Safari)
            HStack {
                CSNavButton(
                    icon: "chevron.left",
                    action: { dismiss() }
                )
                Spacer()
                CSNavButton(
                    icon: "safari",
                    action: { UIApplication.shared.open(url) },
                    accessibilityText: "Open in Safari"
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .contentShape(Rectangle())
            .zIndex(10)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
}

// MARK: - New Articles Toast
private struct NewArticlesToast: View {
    let count: Int
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let isDark = colorScheme == .dark
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Adaptive.gold)
            
            Text("\(count) new")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Adaptive.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: isDark 
                            ? [Color(white: 0.15), Color(white: 0.08)]
                            : [Color(white: 0.96), Color(white: 0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Capsule()
                        .stroke(isDark ? BrandColors.goldLight.opacity(0.25) : BrandColors.silverBase.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Empty Category State
private struct EmptyCategoryState: View {
    let category: String
    let onSelectAll: () -> Void
    let suggestedCategories: [NewsCategory]
    let onSelectCategory: (NewsCategory) -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isAnimating = false
    
    var body: some View {
        let isDark = colorScheme == .dark
        VStack(spacing: 20) {
            // Animated icon
            ZStack {
                // Background glow
                Circle()
                    .fill(DS.Adaptive.gold.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0.3 : 0.6)
                
                // Icon
                Image(systemName: "newspaper")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(
                        BrandColors.ctaDiagonal(isDark: isDark)
                    )
                    .rotationEffect(.degrees(isAnimating ? 3 : -3))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
            
            // Title
            Text("No \(category) news right now")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            
            // Subtitle
            Text("Articles in this category will appear as they're published")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // Quick actions
            VStack(spacing: 12) {
                // View All button
                Button(action: onSelectAll) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 14, weight: .semibold))
                        Text("View All News")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(DS.Adaptive.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .tintedCapsuleChip(isSelected: false, isDark: colorScheme == .dark)
                }
                .buttonStyle(CSPressableScaleStyle())
                
                // Suggested categories
                if !suggestedCategories.isEmpty {
                    Text("Try these categories:")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                    
                    HStack(spacing: 8) {
                        ForEach(suggestedCategories, id: \.self) { cat in
                            Button(action: { onSelectCategory(cat) }) {
                                Text(cat.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DS.Adaptive.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .tintedCapsuleChip(isSelected: false, isDark: colorScheme == .dark)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(CSPressableScaleStyle())
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private struct ToolbarCircleIcon: View {
    let systemName: String
    var isFilled: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(DS.Adaptive.textSecondary)
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(DS.Adaptive.chipBackground.opacity(0.6))
            )
            .overlay(
                Circle()
                    .stroke(DS.Adaptive.stroke.opacity(0.5), lineWidth: 0.5)
            )
            .accessibilityHidden(false)
    }
}

// MARK: - Debug badge for thumbnails (DEV only)
private struct DebugThumbBadge: View {
    let url: URL?
    let article: CryptoNewsArticle
    let isOverride: Bool

    var body: some View {
        let tag = badgeText()
        if tag.isEmpty { EmptyView() } else {
            Text(tag)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.black.opacity(0.55))
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .fixedSize()
        }
    }

    private func badgeText() -> String {
        guard let u = url else { return "" }
        let icon = isLikelyIconURL(u)
        if isOverride {
            return icon ? "ICON•RES" : "HERO"
        }
        if article.urlToImage != nil {
            return icon ? "ICON•RAW" : "RAW"
        }
        return icon ? "ICON" : "IMG"
    }
}

// Use shared utility for icon URL detection
private func isLikelyIconURL(_ url: URL) -> Bool {
    return NewsImageUtilities.isLikelyIconURL(url)
}

