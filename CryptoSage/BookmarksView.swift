//
//  BookmarksView.swift
//  CryptoSage
//
//  Created by DM on 6/10/25.
//

import SwiftUI
import UIKit

// CSPressableScaleStyle is defined in PremiumNewsSection.swift

/// Shows a list of all bookmarked news articles.
struct BookmarksView: View {
    @EnvironmentObject var vm: CryptoNewsFeedViewModel
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var chatVM: ChatViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var isExtractingArticle: Bool = false

    /// All bookmarked articles from persistent storage.
    /// Uses the persisted `bookmarkedArticles` array so bookmarks survive feed refreshes
    /// and don't disappear when articles age out of the active news feed.
    private var bookmarked: [CryptoNewsArticle] {
        vm.bookmarkedArticles
    }

    var body: some View {
        Group {
            if bookmarked.isEmpty {
                emptyState
            } else {
                bookmarksList
            }
        }
        .listStyle(PlainListStyle())
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CSNavButton(
                    icon: "chevron.left",
                    action: { dismiss() },
                    compact: true
                )
            }
            ToolbarItem(placement: .principal) {
                Text("Bookmarks")
                    .font(.headline.weight(.semibold))
            }
        }
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
    
    // MARK: - Bookmarks List
    private var bookmarksList: some View {
        List {
            ForEach(bookmarked) { article in
                let thumbURL = vm.thumbnailURL(for: article)
                NewsSwipeRow(
                    id: article.id,
                    leading: [
                        .init(title: "Ask AI", systemName: "wand.and.stars", style: .gold) {
                            askAI(for: article)
                        }
                    ],
                    trailing: [
                        .init(title: "Remove", systemName: "bookmark.slash", style: .orange) {
                            DispatchQueue.main.async {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    vm.toggleBookmark(article)
                                }
                            }
                        },
                        .init(title: "Copy", systemName: "doc.on.doc", style: .gray) {
                            DispatchQueue.main.async {
                                UIPasteboard.general.url = vm.bestURL(for: article)
                                #if os(iOS)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                #endif
                            }
                        }
                    ],
                    enableSwipe: true
                ) {
                    NavigationLink(destination: ArticleReaderView(url: vm.bestURL(for: article))
                        .onAppear { markAsRead(article) }
                    ) {
                        UnifiedNewsRow(
                            article: article,
                            thumbnailURL: thumbURL,
                            showUnreadDot: !vm.isRead(article),
                            isBookmarked: true
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .contextMenu {
                    Button { askAI(for: article) } label: {
                        Label("Ask AI", systemImage: "wand.and.stars")
                    }
                    
                    Button(role: .destructive) {
                        vm.toggleBookmark(article)
                    } label: {
                        Label("Remove Bookmark", systemImage: "bookmark.slash")
                    }
                    
                    Button {
                        UIPasteboard.general.url = vm.bestURL(for: article)
                    } label: {
                        Label("Copy Link", systemImage: "doc.on.doc")
                    }
                    
                    Button {
                        UIApplication.shared.open(vm.bestURL(for: article))
                    } label: {
                        Label("Open in Safari", systemImage: "safari")
                    }
                }
                .onAppear {
                    // Upgrade thumbnail if possible
                    Task { @MainActor in
                        vm.upgradeImageIfPossible(article)
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        let isDark = colorScheme == .dark
        
        return VStack(spacing: 20) {
            Spacer()
            
            // Animated bookmark icon
            ZStack {
                // Background glow
                Circle()
                    .fill(DS.Adaptive.gold.opacity(0.08))
                    .frame(width: 100, height: 100)
                
                // Icon
                Image(systemName: "bookmark")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isDark
                                ? [BrandColors.goldLight, BrandColors.goldBase]
                                : [BrandColors.silverLight, BrandColors.silverBase],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            // Title
            Text("No Bookmarks Yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DS.Adaptive.textPrimary)
            
            // Subtitle
            Text("Save articles by swiping left or using the bookmark button to read later")
                .font(.subheadline)
                .foregroundStyle(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Functions
    private func askAI(for article: CryptoNewsArticle) {
        // Prevent multiple simultaneous extractions
        guard !isExtractingArticle else { return }
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        isExtractingArticle = true
        
        let cleanURL = ArticleLink.sanitizeAndUnwrap(vm.bestURL(for: article))
        
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
    
    private func markAsRead(_ article: CryptoNewsArticle) {
        if !vm.isRead(article) {
            vm.toggleRead(article)
        }
    }
}

// MARK: - Toolbar Circle Icon (local version to avoid dependencies)
private struct ToolbarCircleIconBookmarks: View {
    let systemName: String
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
    }
}

struct BookmarksView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BookmarksView()
                .environmentObject(CryptoNewsFeedViewModel.shared)
                .environmentObject(AppState())
                .environmentObject(ChatViewModel())
        }
    }
}
