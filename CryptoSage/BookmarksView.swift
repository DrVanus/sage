//
//  BookmarksView.swift
//  CryptoSage
//
//  Created by DM on 6/10/25.
//


import SwiftUI

/// Shows a list of all bookmarked news articles.
struct BookmarksView: View {
    @EnvironmentObject var vm: CryptoNewsFeedViewModel

    /// Only the articles the user has bookmarked
    private var bookmarked: [CryptoNewsArticle] {
        vm.articles.filter { vm.isBookmarked($0) }
    }

    var body: some View {
        List {
            if bookmarked.isEmpty {
                Text("No bookmarks yet")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(bookmarked) { article in
                    NavigationLink(destination: NewsWebView(url: article.url)) {
                        NewsRowView(article: article)
                            .environmentObject(vm)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .listStyle(PlainListStyle())
        .navigationTitle("Bookmarks")
    }
}

struct BookmarksView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview with some fake articles if you like
        BookmarksView()
            .environmentObject(CryptoNewsFeedViewModel())
    }
}