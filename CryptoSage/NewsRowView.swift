//
//  NewsRowView.swift
//  CryptoSage
//
//  Created by DM on 6/10/25.
//


import SwiftUI

struct NewsRowView: View {
    let article: CryptoNewsArticle
    /// If true, render a compact (single-line) layout for use on the Home screen
    var compact: Bool = false
    @EnvironmentObject var vm: CryptoNewsFeedViewModel
    @State private var imageLoadTimedOut = false

    /// Human-friendly “time ago” formatting using RelativeDateTimeFormatter
    private var formattedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: article.publishedAt, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            if let imageURL = article.urlToImage {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure(_), .empty where imageLoadTimedOut:
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFill()
                            .foregroundColor(.gray)
                            .background(Color.gray.opacity(0.2))
                    default:
                        ProgressView()
                            .task {
                                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                                imageLoadTimedOut = true
                            }
                    }
                }
                .frame(width: 50, height: 50)
                .cornerRadius(6)
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.gray)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(article.sourceName)
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(formattedTime)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                vm.toggleBookmark(article)
            } label: {
                Label(
                    vm.isBookmarked(article) ? "Remove Bookmark" : "Bookmark",
                    systemImage: vm.isBookmarked(article) ? "bookmark.fill" : "bookmark"
                )
            }
            .tint(.yellow)
        }
    }
}

struct NewsRowView_Previews: PreviewProvider {
    static var previews: some View {
        // Sample article for preview
        let sample = CryptoNewsArticle(
            title: "Sample Headline",
            description: "This is a preview description.",
            url: URL(string: "https://example.com")!,
            urlToImage: URL(string: "https://example.com/image.png"),
            sourceName: "Example Source",
            publishedAt: Date().addingTimeInterval(-3600)
        )
        NewsRowView(article: sample)
            .environmentObject(CryptoNewsFeedViewModel())
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
