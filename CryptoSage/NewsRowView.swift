//
//  NewsRowView.swift
//  CryptoSage
//
//  Created by DM on 6/10/25.
//

import SwiftUI
import Combine

// MARK: - Unified News Row Component
/// A consistent, reusable news article row used across all news views.
/// Provides uniform sizing, fonts, spacing, and thumbnail handling.
struct UnifiedNewsRow: View {
    let article: CryptoNewsArticle
    let thumbnailURL: URL?
    var showUnreadDot: Bool = false
    var isBookmarked: Bool = false
    var onTap: (() -> Void)? = nil
    
    /// Sanitized article URL for referer header
    private var sanitizedURL: URL {
        ArticleLink.sanitizeAndUnwrap(article.url)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Gold accent bar for unread articles
            if showUnreadDot {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2.5, height: 65)
                    .padding(.trailing, 10)
            } else {
                Color.clear.frame(width: 2.5).padding(.trailing, 10)
            }
            
            // Thumbnail - consistent 120x85 with 12px corner radius
            CachingAsyncImage(url: thumbnailURL, referer: sanitizedURL)
                .frame(width: 120, height: 85)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
            
            Spacer().frame(width: 14)
            
            // Text content
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if showUnreadDot {
                        PulsingUnreadDot()
                    }
                    Text(article.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .layoutPriority(1)
                }
                
                HStack(spacing: 8) {
                    SourcePill(text: article.sourceName)
                    RelativeTimeText(date: article.publishedAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .if(onTap != nil) { view in
            view.onTapGesture { onTap?() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(article.title), from \(article.sourceName)")
    }
}

// MARK: - Pulsing Unread Dot
/// An animated unread indicator with subtle glow pulse
private struct PulsingUnreadDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        ZStack {
            // Outer glow - uses implicit animation to avoid state resets
            Circle()
                .fill(Color.yellow.opacity(0.3))
                .frame(width: 12, height: 12)
                .modifier(PulseAnimationModifier(reduceMotion: reduceMotion))
            
            // Main dot - static, no animation needed
            Circle()
                .fill(
                    RadialGradient(
                        colors: [BrandColors.goldLight, BrandColors.goldBase],
                        center: .center,
                        startRadius: 0,
                        endRadius: 4
                    )
                )
                .frame(width: 7, height: 7)
        }
    }
}

/// Separate modifier for pulse animation - prevents state reset issues on cell reuse
private struct PulseAnimationModifier: ViewModifier {
    let reduceMotion: Bool
    @State private var isPulsing: Bool = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0 : 0.6)
            .scrollAwarePulse(active: $isPulsing, duration: 1.5, autoreverses: true, delay: reduceMotion ? 999999 : 0.5)
    }
}

// MARK: - Compact News Row (for smaller displays)
/// A more compact version of the news row with smaller thumbnail.
struct CompactNewsRow: View {
    let article: CryptoNewsArticle
    let thumbnailURL: URL?
    var showUnreadDot: Bool = false
    var onTap: (() -> Void)? = nil
    
    private var sanitizedURL: URL {
        ArticleLink.sanitizeAndUnwrap(article.url)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Gold accent bar for unread articles
            if showUnreadDot {
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2.5, height: 50)
                    .padding(.trailing, 8)
            } else {
                Color.clear.frame(width: 2.5).padding(.trailing, 8)
            }
            
            // Smaller thumbnail for compact mode - 80x60 with 10px corner radius
            CachingAsyncImage(url: thumbnailURL, referer: sanitizedURL)
                .frame(width: 80, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
            
            Spacer().frame(width: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if showUnreadDot {
                        PulsingUnreadDot()
                    }
                    Text(article.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                HStack(spacing: 6) {
                    Text(article.sourceName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    RelativeTimeText(date: article.publishedAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .if(onTap != nil) { view in
            view.onTapGesture { onTap?() }
        }
    }
}

// MARK: - Legacy NewsRowView (deprecated, use UnifiedNewsRow)
/// Legacy component kept for backward compatibility. Use `UnifiedNewsRow` for new code.
@available(*, deprecated, message: "Use UnifiedNewsRow instead for consistent styling")
struct NewsRowView: View {
    let article: CryptoNewsArticle
    var compact: Bool = false
    @EnvironmentObject var vm: CryptoNewsFeedViewModel

    var body: some View {
        UnifiedNewsRow(
            article: article,
            thumbnailURL: vm.thumbnailURL(for: article),
            showUnreadDot: !vm.isRead(article),
            isBookmarked: vm.isBookmarked(article)
        )
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

// MARK: - Preview
struct NewsRowView_Previews: PreviewProvider {
    static var previews: some View {
        let sample = CryptoNewsArticle(
            title: "Bitcoin ETF redemptions explain why BTC stalled near $91k",
            description: "This is a preview description.",
            url: URL(string: "https://example.com")!,
            urlToImage: URL(string: "https://example.com/image.png"),
            sourceName: "AMB Crypto",
            publishedAt: Date().addingTimeInterval(-240)
        )
        
        VStack(spacing: 20) {
            // Standard row
            UnifiedNewsRow(
                article: sample,
                thumbnailURL: sample.urlToImage,
                showUnreadDot: true
            )
            
            Divider()
            
            // Compact row
            CompactNewsRow(
                article: sample,
                thumbnailURL: sample.urlToImage,
                showUnreadDot: false
            )
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
