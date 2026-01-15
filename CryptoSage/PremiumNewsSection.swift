import SwiftUI
import SafariServices

// MARK: - PremiumNewsSection

public struct PremiumNewsSection: View {
    @ObservedObject public var viewModel: CryptoNewsFeedViewModel
    @Binding public var lastSeenArticleID: String?
    public var onSeeAllTapped: () -> Void = {}
    
    public init(viewModel: CryptoNewsFeedViewModel, lastSeenArticleID: Binding<String?>, onSeeAllTapped: @escaping () -> Void = {}) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._lastSeenArticleID = lastSeenArticleID
        self.onSeeAllTapped = onSeeAllTapped
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            SectionHeader(systemImage: "newspaper", title: "Latest Crypto News")
                .padding(.horizontal, 16)
            
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.articles.isEmpty {
                    emptyStateView
                } else {
                    articlesCard
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var loadingView: some View {
        glassCard {
            VStack(spacing: 10) {
                ForEach(0..<3) { _ in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 80)
                        .redacted(reason: .placeholder)
                        .shimmering()
                }
            }
            .padding(12)
        }
    }
    
    private var emptyStateView: some View {
        glassCard {
            VStack(spacing: 12) {
                Text("No news available right now.")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.callout)
                Button(action: {
                    viewModel.reload()
                }) {
                    Text("Retry")
                }
                .buttonStyle(CSPrimaryCTAButtonStyle())
                .frame(maxWidth: 160)
            }
            .padding(20)
        }
    }
    
    private var articlesCard: some View {
        glassCard {
            VStack(spacing: 12) {
                ForEach(Array(viewModel.articles.prefix(3).enumerated()), id: \.1.id) { (idx, article) in
                    articleRow(article: article)
                        .onAppear {
                            viewModel.prefetchAround(index: idx, radius: 6)
                        }
                }
                HStack {
                    Spacer()
                    Button(action: onSeeAllTapped) {
                        HStack(spacing: 4) {
                            Text("See All News")
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(CSSecondaryCTAButtonStyle(height: 30, cornerRadius: 10, horizontalPadding: 10, font: .caption.weight(.semibold)))
                }
            }
            .padding(12)
        }
    }
    
    @ViewBuilder
    private func articleRow(article: CryptoNewsFeedArticle) -> some View {
        Button(action: {
            if let url = article.url.flatMap(upgradeToHTTPS) {
                OpenSafariHelper.openSafari(url)
                lastSeenArticleID = article.id
            }
        }) {
            HStack(alignment: .top, spacing: 12) {
                if let thumbUrl = article.thumbnail, let httpsUrl = upgradeToHTTPS(thumbUrl) {
                    CachingAsyncImage(url: httpsUrl) { phase in
                        switch phase {
                        case .empty:
                            Color.gray.opacity(0.2)
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Color.gray.opacity(0.2)
                        @unknown default:
                            Color.gray.opacity(0.2)
                        }
                    }
                    .frame(width: 120, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .clipped()
                } else {
                    Color.gray.opacity(0.2)
                        .frame(width: 120, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title ?? "")
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(3)
                    
                    HStack(spacing: 6) {
                        if let source = article.source, !source.isEmpty {
                            Text(source)
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                                        )
                                )
                        }
                        Spacer(minLength: 2)
                        RelativeTimeLabel(date: article.publishedAt)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Spacer(minLength: 8)
                
                Image(systemName: "chevron.right")
                    .foregroundColor(Color.secondary)
                    .padding(.top, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .overlay(
                content()
                    .padding(12)
            )
    }
}

// MARK: - SectionHeader (local copy)

fileprivate struct SectionHeader: View {
    var systemImage: String
    var title: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundColor(.csGoldSolid)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Spacer()
        }
    }
}

// MARK: - OpenSafariHelper (local)

fileprivate struct OpenSafariHelper {
    static func openSafari(_ url: URL) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else {
                return
            }
            let safariVC = SFSafariViewController(url: url)
            rootVC.present(safariVC, animated: true)
        }
    }
}

// MARK: - upgradeToHTTPS fallback

fileprivate func upgradeToHTTPS(_ url: URL) -> URL {
    guard url.scheme?.lowercased() == "http" else {
        return url
    }
    var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    comps?.scheme = "https"
    return comps?.url ?? url
}

// MARK: - RelativeTimeLabel fallback

fileprivate struct RelativeTimeLabel: View {
    let date: Date?
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
    
    var body: some View {
        if let date = date {
            Text(Self.formatter.localizedString(for: date, relativeTo: Date()))
        } else {
            Text("-")
        }
    }
}

// MARK: - Shimmering modifier

fileprivate struct Shimmering: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.1), Color.white.opacity(0.3)]),
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .rotationEffect(.degrees(30))
                    .offset(x: phase)
                    .blendMode(.plusLighter)
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 220
                }
            }
    }
}

fileprivate extension View {
    func shimmering() -> some View {
        modifier(Shimmering())
    }
}

// MARK: - Color extension (csGoldSolid)

fileprivate extension Color {
    static let csGoldSolid = Color(red: 1.0, green: 0.78, blue: 0.0)
}

// MARK: - Button styles fallback

fileprivate struct CSPrimaryCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.black)
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.csGoldSolid)
                    .opacity(configuration.isPressed ? 0.7 : 1)
            )
    }
}

fileprivate struct CSSecondaryCTAButtonStyle: ButtonStyle {
    let height: CGFloat
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let font: Font
    
    init(height: CGFloat = 30, cornerRadius: CGFloat = 10, horizontalPadding: CGFloat = 10, font: Font = .caption.weight(.semibold)) {
        self.height = height
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.font = font
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundColor(.csGoldSolid)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.csGoldSolid, lineWidth: 1)
                    .background(Color.black.opacity(0))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Preview with stub view model

#if DEBUG
fileprivate class StubCryptoNewsFeedViewModel: CryptoNewsFeedViewModel, ObservableObject {
    @Published override var isLoading: Bool = false
    @Published override var articles: [CryptoNewsFeedArticle] = []
    
    override func reload() {
        // no-op
    }
    override func prefetchAround(index: Int, radius: Int) {
        // no-op
    }
    
    init(withArticles articles: [CryptoNewsFeedArticle] = []) {
        super.init()
        self.articles = articles
    }
}

fileprivate extension CryptoNewsFeedArticle {
    static func stub(id: String = UUID().uuidString) -> CryptoNewsFeedArticle {
        CryptoNewsFeedArticle(
            id: id,
            title: "Bitcoin price surges above $60k",
            url: URL(string: "https://example.com/article"),
            thumbnail: URL(string: "https://via.placeholder.com/120x72.png"),
            source: "CryptoTimes",
            publishedAt: Date().addingTimeInterval(-3600)
        )
    }
}

@available(iOS 15.0, *)
struct PremiumNewsSection_Previews: PreviewProvider {
    @State static var lastSeenID: String? = nil
    
    static var previews: some View {
        Group {
            PremiumNewsSection(
                viewModel: {
                    let vm = StubCryptoNewsFeedViewModel()
                    vm.articles = [
                        .stub(),
                        .stub(),
                        .stub()
                    ]
                    return vm
                }(),
                lastSeenArticleID: $lastSeenID,
                onSeeAllTapped: {}
            )
            .preferredColorScheme(.dark)
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .previewDisplayName("With Articles")
            
            PremiumNewsSection(
                viewModel: {
                    let vm = StubCryptoNewsFeedViewModel()
                    vm.isLoading = true
                    return vm
                }(),
                lastSeenArticleID: $lastSeenID
            )
            .preferredColorScheme(.dark)
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .previewDisplayName("Loading state")
            
            PremiumNewsSection(
                viewModel: {
                    let vm = StubCryptoNewsFeedViewModel()
                    vm.articles = []
                    return vm
                }(),
                lastSeenArticleID: $lastSeenID
            )
            .preferredColorScheme(.dark)
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .previewDisplayName("Empty state")
        }
    }
}
#endif
