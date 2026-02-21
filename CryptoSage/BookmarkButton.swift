//
//  BookmarkButton.swift
//  CSAI1
//
//  Created by DM on 4/26/25.
//


import SwiftUI

/// A reusable bookmark button for navigating to the BookmarksView.
struct BookmarkButton: View {
    @EnvironmentObject var viewModel: CryptoNewsFeedViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        NavigationLink(destination: AllCryptoNewsView()
            .environmentObject(viewModel)) {
            Image(systemName: "bookmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: isDark
                            ? [BrandColors.goldLight, BrandColors.goldBase]
                            : [BrandColors.goldBase, BrandColors.goldDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                // ACCESSIBILITY FIX: Add proper accessibility label for screen readers
                .accessibilityLabel("Bookmarks")
                .accessibilityHint("View your saved articles")
        }
        .simultaneousGesture(TapGesture().onEnded {
            // UX FIX: Add haptic feedback for navigation interaction
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        })
    }
}
