// NewsWebView.swift
// CSAI1
//
// Created by ChatGPT on 4/18/25.
// Native SwiftUI crypto‑news feed (no WKWebView).

import SwiftUI
import WebKit


// MARK: - Custom Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.3),
                        Color.gray.opacity(0.5),
                        Color.gray.opacity(0.3)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase * 300)
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// Applies a shimmer animation to placeholder content.
    func shimmeringEffect() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: -- Thumbnail Caching

actor ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, UIImage>()
    func loadImage(from url: URL?) async -> UIImage? {
        guard let url = url else { return nil }
        let key = url as NSURL
        if let img = cache.object(forKey: key) {
            return img
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                cache.setObject(img, forKey: key)
                return img
            }
        } catch { }
        return nil
    }
}

struct CachingAsyncImage: View {
    let url: URL?
    var body: some View {
        CachingAsyncImageContent(url: url)
    }
}

private struct CachingAsyncImageContent: View {
    let url: URL?
    @State private var uiImage: UIImage?
    var body: some View {
        Group {
            if let img = uiImage {
                Image(uiImage: img).resizable()
            } else {
                ZStack {
                    Color.gray.opacity(0.3)
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.7))
                }
                .shimmeringEffect()
            }
        }
        .onAppear {
            Task {
                if let loaded = await ThumbnailCache.shared.loadImage(from: url) {
                    uiImage = loaded
                }
            }
        }
    }
}

// Formatter for absolute dates
private let fullDateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "MMM d yyyy, h:mm a"
    return df
}()

/// Skeleton row view for loading state
struct SkeletonNewsRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 100, height: 60)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 20)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 14)
            }
        }
        .redacted(reason: .placeholder)
        .shimmeringEffect()
        .padding(.vertical, 2)
    }
}

// MARK: -- Error View

struct CryptoNewsErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)

            Button(action: onRetry) {
                Text("Retry")
                    .font(.caption2)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.yellow)
                    .foregroundColor(.black)
                    .cornerRadius(6)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.8))
        .cornerRadius(8)
    }
}


// MARK: -- ViewModel

// MARK: -- Row

// MARK: -- Row

struct CryptoNewsRow: View {
    @EnvironmentObject var viewModel: CryptoNewsFeedViewModel
    let article: CryptoNewsArticle

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CachingAsyncImage(url: article.urlToImage)
                .frame(width: 100, height: 60)
                .cornerRadius(6)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(article.publishedAt, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(article.title), published: \(fullDateFormatter.string(from: article.publishedAt))")
        .swipeActions(edge: .leading) {
            Button {
                viewModel.toggleRead(article)
            } label: {
                Label(viewModel.isRead(article) ? "Mark Unread" : "Mark Read",
                      systemImage: viewModel.isRead(article) ? "envelope.open" : "envelope.badge")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                viewModel.toggleBookmark(article)
            } label: {
                Image(systemName: viewModel.isBookmarked(article) ? "bookmark.fill" : "bookmark")
                    .font(.title2)
                    .accessibilityLabel(viewModel.isBookmarked(article) ? "Remove Bookmark" : "Bookmark")
            }
            .tint(.orange)
            
            Button {
                UIPasteboard.general.url = article.url
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.title2)
                    .accessibilityLabel("Copy Link")
            }
            .tint(.gray)
            
            Button {
                UIApplication.shared.open(article.url)
            } label: {
                Image(systemName: "safari")
                    .font(.title2)
                    .accessibilityLabel("Open in Safari")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button { UIApplication.shared.open(article.url) }
                label: { Label("Open in Safari", systemImage: "safari") }
            Button { UIPasteboard.general.url = article.url }
                label: { Label("Copy Link", systemImage: "doc.on.doc") }
            ShareLink(item: article.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .padding(.vertical, 8)
    }
}


import SwiftUI

struct NewsWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }
    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.load(URLRequest(url: url))
    }
}


